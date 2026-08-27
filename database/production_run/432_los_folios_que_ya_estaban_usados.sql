-- ============================================================================
-- MIG432 · El correlativo tiene que arrancar donde quedó el de papel
-- ----------------------------------------------------------------------------
-- MIG431 dejó el sistema listo para emitir y anunció que el próximo folio sería
-- el 01/2026. Ese número ya está usado: lo lleva el certificado del TRST-57, y
-- también el del DCHD-83. Emitir con él habría creado un tercero.
--
-- ── LOS FOLIOS REALES NO ESTABAN EN LA BASE ────────────────────────────────
-- `certificaciones.numero_certificado` tiene valores inventados por la carga de
-- abril —«DCHD-83-HERM», «FJTJ-60-HERM»— que no son folios de nada. Los folios
-- de verdad estaban impresos dentro de los PDF y salieron al leerlos uno por
-- uno en la auditoría forense:
--
--   09/2021  HKSR-81
--   07/2024  SVBJ-57
--   10/2025  FJTJ-60, LCSX-78, SVBJ-56     ← el mismo número, tres camiones
--   12/2025  DJKL-18, JGBY-10              ← el mismo número, dos camiones
--   01/2026  TRST-57, DCHD-83              ← el mismo número, dos camiones
--   02/2026  FSLZ-67
--
-- Cinco números repartidos entre once certificados. Llevar el correlativo a
-- mano en una planilla hace exactamente esto, y es la razón por la que el folio
-- del sistema tiene índice único.
--
-- ── LO QUE SE HACE ─────────────────────────────────────────────────────────
-- Se anotan los folios reales en `numero_certificado` —reemplazando los
-- inventados— y se registran como ocupados para que el correlativo del sistema
-- empiece en 03/2026 y no vuelva a chocar.
--
-- Los duplicados NO se corrigen: el número está impreso en un papel firmado que
-- está en la carpeta y no se puede cambiar desde acá. Queda anotado que se
-- repite, que es lo que se puede hacer honestamente.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.certificado_folio_usado (
    tipo    TEXT NOT NULL,
    anio    INT  NOT NULL,
    numero  INT  NOT NULL,
    motivo  TEXT,
    PRIMARY KEY (tipo, anio, numero)
);

COMMENT ON TABLE public.certificado_folio_usado IS
  'MIG432: folios emitidos fuera del sistema, en papel. El correlativo los saltea para no repetirlos.';

INSERT INTO certificado_folio_usado (tipo, anio, numero, motivo) VALUES
  ('hermeticidad', 2021,  9, 'HKSR-81 — leído del PDF en la auditoría forense'),
  ('hermeticidad', 2024,  7, 'SVBJ-57 — leído del PDF en la auditoría forense'),
  ('hermeticidad', 2025, 10, 'FJTJ-60, LCSX-78 y SVBJ-56 comparten este folio'),
  ('hermeticidad', 2025, 12, 'DJKL-18 y JGBY-10 comparten este folio'),
  ('hermeticidad', 2026,  1, 'TRST-57 y DCHD-83 comparten este folio'),
  ('hermeticidad', 2026,  2, 'FSLZ-67 — leído del PDF en la auditoría forense')
ON CONFLICT DO NOTHING;

-- ── Anotar el folio real donde había un invento ───────────────────────────
CREATE TEMP TABLE _folios(patente TEXT, folio TEXT, dup BOOLEAN) ON COMMIT DROP;
INSERT INTO _folios VALUES
  ('HKSR-81','09/2021',FALSE), ('FJTJ-60','10/2025',TRUE),  ('LCSX-78','10/2025',TRUE),
  ('SVBJ-56','10/2025',TRUE),  ('DJKL-18','12/2025',TRUE),  ('JGBY-10','12/2025',TRUE),
  ('TRST-57','01/2026',TRUE),  ('DCHD-83','01/2026',TRUE),  ('FSLZ-67','02/2026',FALSE);

UPDATE certificaciones c
   SET numero_certificado = f.folio,
       notas = COALESCE(NULLIF(c.notas,'') || ' · ', '')
             || 'MIG432: folio leído del PDF en la auditoría forense.'
             || CASE WHEN f.dup THEN ' OJO: este número está repetido en otro equipo de la flota.' ELSE '' END,
       updated_at = NOW()
  FROM _folios f, activos a
 WHERE c.activo_id = a.id AND COALESCE(a.patente,a.codigo) = f.patente
   AND c.tipo::text = 'hermeticidad'
   AND c.id IN (SELECT id FROM v_certificacion_actual);

-- ── El correlativo mira los dos lados ─────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_proximo_folio(p_tipo text, p_anio int)
RETURNS int
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $function$
  SELECT GREATEST(
    COALESCE((SELECT max(folio_numero) FROM certificados_emitidos
               WHERE tipo = p_tipo AND folio_anio = p_anio AND NOT anulado), 0),
    -- Los que se emitieron en papel antes de que existiera esto.
    COALESCE((SELECT max(numero) FROM certificado_folio_usado
               WHERE tipo = p_tipo AND anio = p_anio), 0)
  ) + 1;
$function$;

CREATE OR REPLACE FUNCTION public.rpc_emitir_certificado(p_datos jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_rol TEXT; v_activo UUID; v_tipo TEXT; v_prueba DATE; v_meses INT;
    v_vence DATE; v_anio INT; v_num INT; v_folio TEXT;
    v_cert_id UUID; v_emitido_id UUID; v_patente TEXT;
BEGIN
    SELECT rol INTO v_rol FROM usuarios_perfil WHERE id = auth.uid();
    IF v_rol IS NULL OR v_rol NOT IN ('administrador','subgerente_operaciones','jefe_mantenimiento') THEN
        RAISE EXCEPTION 'No tienes permiso para emitir certificados.';
    END IF;

    v_activo := (p_datos->>'activo_id')::uuid;
    v_tipo   := COALESCE(p_datos->>'tipo', 'hermeticidad');
    v_prueba := (p_datos->>'fecha_prueba')::date;
    IF v_activo IS NULL OR v_prueba IS NULL THEN
        RAISE EXCEPTION 'Falta el equipo o la fecha de la prueba.';
    END IF;
    IF v_prueba > CURRENT_DATE THEN
        RAISE EXCEPTION 'La fecha de la prueba no puede estar en el futuro.';
    END IF;

    SELECT COALESCE(patente, codigo) INTO v_patente FROM activos WHERE id = v_activo;
    IF v_patente IS NULL THEN RAISE EXCEPTION 'No se encontró el equipo.'; END IF;

    SELECT meses INTO v_meses FROM certificado_vigencia_estandar WHERE tipo = v_tipo;
    v_vence := (v_prueba + (COALESCE(v_meses, 6) || ' months')::INTERVAL)::date;

    v_anio := EXTRACT(YEAR FROM v_prueba)::int;
    PERFORM pg_advisory_xact_lock(hashtext('folio_cert_' || v_tipo || v_anio));
    -- [MIG432] Salta también los folios que se emitieron en papel.
    v_num   := fn_proximo_folio(v_tipo, v_anio);
    v_folio := lpad(v_num::text, 2, '0') || '/' || v_anio;

    INSERT INTO certificados_emitidos (
        activo_id, tipo, folio, folio_numero, folio_anio, fecha_prueba, fecha_vencimiento,
        informe, instrumento_desc, instrumento_marca, estanque_serie, anio_fabricacion,
        propietario, propietario_direccion, fabricante, norma_revision, tipo_estanque,
        capacidad_nominal, n_compartimientos, cap_compartimientos, protocolo,
        presion_diseno, presion_prueba, longitud_nominal, diametro_nominal,
        ancho_nominal, alto_nominal, manto_material, manto_forma, manto_espesor,
        cabezal_material, cabezal_forma, cabezal_espesor, union_longitudinal,
        union_rectangular, union_manto_cabezal, medio_deteccion, rango_manometro,
        alcance_prueba, numero_plano, especificacion_diseno, duracion_prueba,
        metodo_prueba, lugar_prueba, foto_inicio_url, foto_termino_url,
        firmante_nombre, firmante_titulo, firmante_cargo, emitido_por)
    SELECT v_activo, v_tipo, v_folio, v_num, v_anio, v_prueba, v_vence,
        COALESCE(p_datos->>'informe','Aceptado sin filtraciones'),
        p_datos->>'instrumento_desc', p_datos->>'instrumento_marca',
        p_datos->>'estanque_serie', p_datos->>'anio_fabricacion',
        p_datos->>'propietario', p_datos->>'propietario_direccion', p_datos->>'fabricante',
        p_datos->>'norma_revision', p_datos->>'tipo_estanque',
        p_datos->>'capacidad_nominal', p_datos->>'n_compartimientos',
        p_datos->>'cap_compartimientos', p_datos->>'protocolo',
        p_datos->>'presion_diseno', p_datos->>'presion_prueba',
        p_datos->>'longitud_nominal', p_datos->>'diametro_nominal',
        p_datos->>'ancho_nominal', p_datos->>'alto_nominal',
        p_datos->>'manto_material', p_datos->>'manto_forma', p_datos->>'manto_espesor',
        p_datos->>'cabezal_material', p_datos->>'cabezal_forma', p_datos->>'cabezal_espesor',
        COALESCE(p_datos->>'union_longitudinal','Tope'),
        COALESCE(p_datos->>'union_rectangular','Tope'),
        COALESCE(p_datos->>'union_manto_cabezal','Tope'),
        p_datos->>'medio_deteccion', p_datos->>'rango_manometro',
        p_datos->>'alcance_prueba', p_datos->>'numero_plano',
        p_datos->>'especificacion_diseno', p_datos->>'duracion_prueba',
        p_datos->>'metodo_prueba', p_datos->>'lugar_prueba',
        p_datos->>'foto_inicio_url', p_datos->>'foto_termino_url',
        p_datos->>'firmante_nombre', p_datos->>'firmante_titulo', p_datos->>'firmante_cargo',
        auth.uid()
    RETURNING id INTO v_emitido_id;

    INSERT INTO certificaciones (activo_id, tipo, fecha_emision, fecha_vencimiento,
                                 numero_certificado, entidad_certificadora, bloqueante,
                                 fecha_origen, fecha_origen_nota, notas, created_by)
    VALUES (v_activo, v_tipo::tipo_certificacion_enum, v_prueba, v_vence,
            v_folio, COALESCE(p_datos->>'propietario','PILLADO Y COMPAÑÍA LTDA.'), TRUE,
            'documento',
            'MIG431 · emitido por el sistema, certificado Nº ' || v_folio
              || ': prueba ' || to_char(v_prueba,'DD-MM-YYYY')
              || ', vence ' || to_char(v_vence,'DD-MM-YYYY')
              || ' (' || COALESCE(v_meses,6) || ' meses).',
            'Certificado emitido desde SICOM.', auth.uid())
    RETURNING id INTO v_cert_id;

    UPDATE certificados_emitidos SET certificacion_id = v_cert_id WHERE id = v_emitido_id;

    RETURN jsonb_build_object('success', true, 'id', v_emitido_id, 'folio', v_folio,
                              'patente', v_patente, 'fecha_prueba', v_prueba,
                              'fecha_vencimiento', v_vence, 'certificacion_id', v_cert_id);
END $function$;

GRANT EXECUTE ON FUNCTION public.fn_proximo_folio(text, int) TO authenticated;

DO $r$
BEGIN
    RAISE NOTICE 'Proximo folio de hermeticidad para %: %/%',
      EXTRACT(YEAR FROM CURRENT_DATE)::int,
      lpad(fn_proximo_folio('hermeticidad', EXTRACT(YEAR FROM CURRENT_DATE)::int)::text, 2, '0'),
      EXTRACT(YEAR FROM CURRENT_DATE)::int;
END
$r$;

COMMIT;
