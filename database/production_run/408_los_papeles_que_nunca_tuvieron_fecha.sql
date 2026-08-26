-- ============================================================================
-- MIG408 · El punto ciego: un tipo que NUNCA tuvo fecha parecía no vencer
-- ----------------------------------------------------------------------------
-- MIG407 dedujo qué tipos vencen mirando la propia flota: si algún certificado
-- de ese tipo tiene fecha real, el tipo vence. Es un buen criterio y resolvió
-- 218 huecos.
--
-- Pero tiene un punto ciego, y es grande: **si a un tipo NUNCA nadie le puso
-- fecha, parece que no vence.** El criterio se queda mirando un vacío y
-- concluye que ahí no hay nada que mirar.
--
-- Así quedaron clasificados como «no vencen»:
--
--     seguro_rc ............ 53 registros, ninguno con fecha
--     tacografo ............ 26
--     inscripcion_sec ...... 17
--     mant_hidraulico ...... 15
--     grilletes_eslingas ....  7
--
-- Una póliza de responsabilidad civil vence. Un certificado de funcionamiento
-- de tacógrafo vence. Los grilletes y eslingas se inspeccionan periódicamente
-- —son elementos de izaje, si fallan cae una carga—. La mantención hidráulica
-- vence. Ninguno de esos cinco «no vence»: es que nunca se registró.
--
-- ── LA LISTA SE INVIERTE ────────────────────────────────────────────────────
-- En vez de deducir qué vence, se declara explícitamente qué NO vence. Son los
-- papeles de identidad y propiedad del vehículo, que acompañan al equipo toda
-- su vida:
--
--     factura_compra ..... la compra ocurrió una vez
--     ficha_tecnica ...... describe el equipo, no lo autoriza
--     padron ............. inscripción del vehículo
--     inscripcion_rnvm ... registro nacional de vehículos motorizados
--     homologacion ....... homologación del modelo
--
-- Todo lo demás vence. Es más seguro equivocarse pidiendo revisar un papel que
-- no lo necesitaba, que dar por eterno uno que caducó.
--
-- ── LO QUE ESTO DESTAPA ─────────────────────────────────────────────────────
-- 118 certificados más que estaban en el mismo silencio, entre ellos las 53
-- pólizas de responsabilidad civil de toda la flota.
--
-- ── LA REGLA DE LOS 2 AÑOS ──────────────────────────────────────────────────
-- Decisión de Manuel (26-08-2026), para el lector de PDF: cuando el documento
-- no declara vigencia, se cuentan 2 años desde su fecha. Vive en
-- `analizar-certificados.mjs`, no acá: esta migración sólo hace visible el
-- hueco, no inventa la fecha.
-- ============================================================================

BEGIN;

-- ── 1. Qué papeles no vencen nunca, dicho explícitamente ──────────────────
CREATE OR REPLACE FUNCTION public.fn_certificado_tipo_permanente(p_tipo text)
RETURNS boolean
LANGUAGE sql IMMUTABLE
AS $function$
  -- Papeles de identidad y propiedad del vehículo: acompañan al equipo toda su
  -- vida. Todo lo que no esté acá vence, aunque nunca se le haya puesto fecha.
  SELECT p_tipo = ANY (ARRAY[
    'factura_compra', 'ficha_tecnica', 'padron', 'inscripcion_rnvm', 'homologacion'
  ]);
$function$;

COMMENT ON FUNCTION public.fn_certificado_tipo_permanente(text) IS
  'MIG408: los únicos tipos que de verdad no vencen. Antes se deducía de los datos y un tipo sin ninguna fecha registrada —como seguro_rc— parecía eterno.';

-- ── 2. La vista de tipos, ahora sin el punto ciego ────────────────────────
CREATE OR REPLACE VIEW public.v_certificado_tipo_vence AS
SELECT tipo,
       count(*) FILTER (WHERE fecha_vencimiento::date <> '2099-12-31') AS con_fecha_real,
       count(*) FILTER (WHERE fecha_vencimiento::date  = '2099-12-31') AS en_placeholder,
       NOT fn_certificado_tipo_permanente(tipo::text) AS vence
  FROM certificaciones
 GROUP BY tipo;

-- ── 3. Cuánto más estaba en silencio ──────────────────────────────────────
DO $r$
DECLARE v_antes INT; v_ahora INT; r RECORD;
BEGIN
    SELECT count(*) INTO v_ahora FROM v_certificacion_actual
     WHERE estado_real::text = 'sin_fecha';
    RAISE NOTICE 'Certificados que piden revisión: % (antes de MIG408 eran 218)', v_ahora;

    FOR r IN
        SELECT tipo::text AS tipo, count(*) AS n FROM v_certificacion_actual
         WHERE estado_real::text = 'sin_fecha'
           AND tipo::text IN ('seguro_rc','tacografo','inscripcion_sec','mant_hidraulico','grilletes_eslingas')
         GROUP BY 1 ORDER BY 2 DESC
    LOOP RAISE NOTICE '   destapado · %: %', rpad(r.tipo, 22), r.n; END LOOP;

    SELECT count(*) INTO v_antes FROM v_certificacion_actual WHERE estado_real::text = 'no_aplica';
    RAISE NOTICE 'Quedan como «no vence nunca»: % (factura, ficha técnica, padrón, RNVM, homologación)', v_antes;
END
$r$;

COMMIT;
