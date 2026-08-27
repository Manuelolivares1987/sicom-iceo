-- ============================================================================
-- MIG430 · Una fecha que escribió una persona no se borra: se le avisa
-- ----------------------------------------------------------------------------
-- LO QUE REPORTÓ MANUEL
-- 27-08-2026: «el SVBJ-57, hermeticidad del estanque: coloco la fecha pero
-- sigue colocando "falta la fecha", y genera ruido no necesario».
--
-- Tiene razón y el error es mío. Escribió 07-08-2026 → 07-08-2027 y el trigger
-- de MIG418 la descalificó: la hermeticidad dura 6 meses, él puso 12, y en vez
-- de avisarle el sistema marcó la fila como dudosa. `vigencia_dudosa` hace que
-- la vista reporte `sin_fecha`, o sea «falta la fecha» — sobre un papel que
-- tiene fecha, puesta a mano, a propósito.
--
-- ── LO QUE ESTABA MAL PENSADO ──────────────────────────────────────────────
-- `vigencia_dudosa` se inventó (MIG416) para un caso concreto: una fecha que
-- cargó el sistema y que no se puede sostener. Ahí borrar el dato es correcto,
-- porque nadie lo afirmó nunca.
--
-- Una fecha que escribió una persona es otra cosa. Puede estar equivocada —y
-- acá probablemente lo está— pero alguien la afirmó. El sistema puede
-- contradecirla; no puede hacerla desaparecer y decir que no existe. Menos aún
-- sin explicar qué le objeta: «falta la fecha» sobre una fecha recién escrita
-- no es un aviso, es ruido, exactamente como lo llamó Manuel.
--
-- ── LO QUE CAMBIA ──────────────────────────────────────────────────────────
-- La observación deja de ser un estado y pasa a ser lo que siempre debió ser:
-- una advertencia al lado del dato.
--
--   fecha del sistema, no sostenible  →  vigencia_dudosa (sigue igual)
--   fecha escrita por una persona     →  vigencia_observacion, y la fecha vale
--
-- ── A QUIÉNES ALCANZA ──────────────────────────────────────────────────────
-- Seis papeles. El del SVBJ-57 vuelve a mostrar su fecha, con la advertencia
-- de que 12 meses no calzan con los 6 que dura el documento.
--
-- Los otros cinco —TGGF-56, TGGF-57, TGGF-58, TRDP-97 y TRST-58, todos
-- hermeticidad leída del documento— dejan de decir «falta la fecha» y pasan a
-- decir lo que son: VENCIDOS, en 2025. Ahí el ruido no sólo molestaba: estaba
-- tapando cinco certificados bloqueantes caducados.
-- ============================================================================

BEGIN;

ALTER TABLE public.certificaciones
  ADD COLUMN IF NOT EXISTS vigencia_observacion TEXT;

COMMENT ON COLUMN public.certificaciones.vigencia_observacion IS
  'MIG430: el sistema no está de acuerdo con esta fecha, pero la escribió una persona y vale. Es una advertencia, no un estado.';

-- ── El trigger avisa; sólo descalifica lo que cargó el propio sistema ─────
CREATE OR REPLACE FUNCTION public.fn_certificacion_revisar_estandar()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE v_meses INT; v_real NUMERIC; v_esperado DATE; v_texto TEXT;
BEGIN
    IF NEW.fecha_vencimiento IS NULL OR NEW.fecha_emision IS NULL
       OR NEW.fecha_vencimiento >= '2099-01-01'::date
       OR NEW.fecha_emision >= '2099-01-01'::date THEN
        NEW.vigencia_observacion := NULL;
        RETURN NEW;
    END IF;

    SELECT meses INTO v_meses FROM certificado_vigencia_estandar WHERE tipo = NEW.tipo::text;
    IF v_meses IS NULL THEN
        NEW.vigencia_observacion := NULL;
        RETURN NEW;
    END IF;

    v_real := (NEW.fecha_vencimiento::date - NEW.fecha_emision::date) / 30.44;
    v_esperado := (NEW.fecha_emision::date + (v_meses || ' months')::INTERVAL)::date;

    IF round(v_real) = v_meses THEN
        NEW.vigencia_observacion := NULL;
        RETURN NEW;
    END IF;

    v_texto := 'Está guardado con ' || round(v_real) || ' meses de vigencia y este documento dura '
             || v_meses || '. Según la emisión (' || to_char(NEW.fecha_emision::date,'DD-MM-YYYY')
             || ') el vencimiento sería ' || to_char(v_esperado,'DD-MM-YYYY')
             || '. Si el papel dice otra cosa, está bien así.';

    -- [MIG430] La fecha que escribió una persona vale: se le avisa, no se le
    -- borra. Sólo se descalifica lo que cargó el propio sistema y no puede
    -- sostener — que es para lo que se inventó `vigencia_dudosa` (MIG416).
    IF NEW.fecha_origen IN ('manual', 'documento', 'documento_sin_vencimiento') THEN
        NEW.vigencia_observacion := v_texto;
        NEW.vigencia_dudosa      := FALSE;
        NEW.vigencia_dudosa_nota := NULL;
    ELSE
        NEW.vigencia_observacion := NULL;
        NEW.vigencia_dudosa      := TRUE;
        NEW.vigencia_dudosa_nota := 'MIG430 · ' || v_texto;
    END IF;

    RETURN NEW;
END $function$;

-- ── Devolverles la fecha a los seis ───────────────────────────────────────
UPDATE certificaciones c
   SET vigencia_dudosa      = FALSE,
       vigencia_observacion = replace(COALESCE(c.vigencia_dudosa_nota, ''), 'MIG418 · guardado', 'Está guardado'),
       vigencia_dudosa_nota = NULL,
       updated_at           = NOW()
 WHERE c.vigencia_dudosa
   AND c.fecha_origen IN ('manual', 'documento');

-- ── Que la pantalla pueda mostrarla ───────────────────────────────────────
CREATE OR REPLACE VIEW public.v_control_documental AS
 SELECT a.id AS activo_id,
    COALESCE(a.patente, a.codigo) AS patente,
    a.codigo AS activo_codigo,
    a.nombre AS activo_nombre,
    a.tipo::text AS activo_tipo,
    a.estado::text AS activo_estado,
    v.id AS certificacion_id,
    v.tipo::text AS tipo,
    v.numero_certificado,
    v.entidad_certificadora,
    v.fecha_emision,
    v.fecha_vencimiento,
    v.estado_real::text AS estado,
    v.dias_restantes,
    v.archivo_url,
    v.bloqueante,
    c.fecha_origen,
    p.id AS propuesta_id,
    p.vencimiento_propuesto,
    p.emision_propuesta,
    p.confianza AS propuesta_confianza,
    p.regla AS propuesta_regla,
    p.evidencia AS propuesta_evidencia,
    p.vencimiento_propuesto IS NOT NULL AND p.vencimiento_propuesto < CURRENT_DATE AS propuesta_vencida,
    fn_certificado_tipo_permanente(v.tipo::text) AS tipo_no_caduca,
    -- [MIG430] La advertencia va junto al dato, sin borrarlo.
    c.vigencia_observacion,
    c.vigencia_dudosa_nota
   FROM v_certificacion_actual v
     JOIN activos a ON a.id = v.activo_id
     JOIN certificaciones c ON c.id = v.id
     LEFT JOIN certificacion_propuestas p ON p.certificacion_id = v.id AND p.estado = 'pendiente'::text
  WHERE a.estado <> 'dado_baja'::estado_activo_enum;

GRANT SELECT ON public.v_control_documental TO authenticated;

DO $r$
DECLARE r RECORD; v_n INT;
BEGIN
    SELECT count(*) INTO v_n FROM certificaciones WHERE vigencia_observacion IS NOT NULL;
    RAISE NOTICE 'Papeles con advertencia (la fecha vale igual): %', v_n;
    FOR r IN
        SELECT COALESCE(a.patente,a.codigo) AS patente, v.tipo::text AS tipo,
               v.estado_real::text AS estado, v.fecha_vencimiento::date AS vence
          FROM v_certificacion_actual v JOIN certificaciones c ON c.id=v.id
          JOIN activos a ON a.id=v.activo_id
         WHERE c.vigencia_observacion IS NOT NULL ORDER BY 1
    LOOP
        RAISE NOTICE '  % % ahora dice: % (vence %)',
            rpad(r.patente,10), rpad(r.tipo,14), rpad(r.estado,11), r.vence;
    END LOOP;
END
$r$;

COMMIT;
