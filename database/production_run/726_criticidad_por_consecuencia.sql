-- ============================================================================
-- MIG726 — Criticidad de equipos por CONSECUENCIA DE FALLA (22-11-2026)
-- ----------------------------------------------------------------------------
-- Antes: 42 de 78 equipos «crítica», puesto a mano por la carga inicial de flota
-- (11-04, schema/26_seed_flota_checklist.sql) sin criterio, y nunca revisado:
-- todos los aljibes de agua críticos (aun disponibles en patio) y aljibes de
-- combustible en faena como «alta» si se cargaron como «camion».
--
-- Criterio (práctica de la industria: ISO 14224 / ISO 55000; evaluación de
-- consecuencias de RCM, SAE JA1011): la criticidad sale de la consecuencia de
-- la falla — 1° seguridad y medio ambiente, 2° operación del cliente — y baja
-- cuando el equipo no está en servicio (la consecuencia queda latente).
--
--                                     en servicio(*)   disponible   venta/baja/
--                                                                   externo/prueba
--   Combustible e izaje               CRÍTICA          ALTA         BAJA
--   (aljibe de combustible,
--    lubrimóvil, estanque, surtidor,
--    pluma grúa): incendio, derrame,
--    caída de carga.
--   Equipo productivo                 ALTA             MEDIA        BAJA
--   (aljibe de agua —control de
--    polvo—, ampliroll, camión,
--    grúa horquilla, bombas)
--   Apoyo (camionetas, equipo menor)  MEDIA si es de   BAJA         BAJA
--                                     cliente; BAJA uso interno
--   (*) arrendado, leasing, uso interno, o infraestructura fija sin estado comercial.
--
-- Se recalcula sola al cambiar tipo, equipamiento, estado comercial, baja,
-- externo o prueba. Una criticidad fijada a mano (criticidad_manual = true)
-- se respeta. Autorizado por el usuario («aplica MIG726»).
-- ============================================================================

ALTER TABLE public.activos ADD COLUMN IF NOT EXISTS criticidad_manual BOOLEAN NOT NULL DEFAULT false;
COMMENT ON COLUMN public.activos.criticidad_manual IS
  'MIG726: true = la criticidad la fijó una persona y no se recalcula sola.';

CREATE OR REPLACE FUNCTION public.fn_activo_criticidad_calculada(
    p_tipo TEXT, p_equipamiento TEXT, p_estado_comercial TEXT,
    p_fecha_baja DATE, p_es_externo BOOLEAN, p_es_prueba BOOLEAN
) RETURNS criticidad_enum
LANGUAGE sql IMMUTABLE
AS $$
  SELECT (CASE
    WHEN p_fecha_baja IS NOT NULL OR coalesce(p_es_externo, false) OR coalesce(p_es_prueba, false)
         OR p_estado_comercial IN ('en_venta', 'vendido') THEN 'baja'
    WHEN p_equipamiento IN ('aljibe_combustible', 'lubrimovil', 'pluma_grua')
         OR p_tipo IN ('estanque', 'surtidor', 'lubrimovil', 'punto_fijo', 'dispensador')
      THEN CASE WHEN p_estado_comercial = 'disponible' THEN 'alta' ELSE 'critica' END
    WHEN p_equipamiento IN ('aljibe_agua', 'ampliroll', 'grua_horquilla')
         OR p_tipo IN ('camion', 'camion_cisterna', 'bomba', 'equipo_bombeo')
      THEN CASE WHEN p_estado_comercial = 'disponible' THEN 'media' ELSE 'alta' END
    ELSE CASE WHEN p_estado_comercial IN ('arrendado', 'leasing') THEN 'media' ELSE 'baja' END
  END)::criticidad_enum
$$;

CREATE OR REPLACE FUNCTION public.fn_trg_activo_criticidad()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NOT coalesce(NEW.criticidad_manual, false) THEN
    NEW.criticidad := fn_activo_criticidad_calculada(
      NEW.tipo::text, NEW.tipo_equipamiento::text, NEW.estado_comercial::text,
      NEW.fecha_baja, NEW.es_externo, NEW.es_prueba);
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_activo_criticidad ON public.activos;
CREATE TRIGGER trg_activo_criticidad
  BEFORE INSERT OR UPDATE OF tipo, tipo_equipamiento, estado_comercial, fecha_baja, es_externo, es_prueba, criticidad_manual
  ON public.activos
  FOR EACH ROW EXECUTE FUNCTION public.fn_trg_activo_criticidad();

-- Recalcular la flota actual: solo los equipos que cambian (la auditoría
-- registra cada cambio; nadie la había fijado a mano, venía del seed).
UPDATE public.activos a
   SET criticidad = fn_activo_criticidad_calculada(
         a.tipo::text, a.tipo_equipamiento::text, a.estado_comercial::text,
         a.fecha_baja, a.es_externo, a.es_prueba)
 WHERE NOT a.criticidad_manual
   AND a.criticidad IS DISTINCT FROM fn_activo_criticidad_calculada(
         a.tipo::text, a.tipo_equipamiento::text, a.estado_comercial::text,
         a.fecha_baja, a.es_externo, a.es_prueba);

-- Validación: distribución resultante.
SELECT criticidad::text AS criticidad, count(*) AS equipos FROM public.activos GROUP BY 1 ORDER BY 1;
