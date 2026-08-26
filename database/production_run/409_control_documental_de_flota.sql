-- ============================================================================
-- MIG409 · Control documental: donde los papeles se arreglan, no sólo se miran
-- ----------------------------------------------------------------------------
-- LO QUE PIDIÓ MANUEL
-- 26-08-2026: «tenemos que hacer un menú exclusivo para tratar todos los papeles
-- no vigentes de la flota por camión, con este nuevo escaneo que se ha
-- realizado, actualizar esto y dar profesionalismo a este problema».
--
-- Hasta acá el catastro existe pero vive en un CSV: se mira, se comenta y se
-- pierde. Y las 141 fechas que el lector ya sacó de los documentos no se pueden
-- aplicar sin que alguien las copie a mano una por una.
--
-- ── LA PROPUESTA SE GUARDA, NO SE ADIVINA DOS VECES ─────────────────────────
-- Lo que el lector sacó de cada PDF —la fecha, la regla que usó y el trozo de
-- texto que la respalda— queda en `certificacion_propuestas`. La pantalla la
-- muestra al lado del papel: «el archivo dice 26-03-2026, esto es lo que dice
-- textualmente, ¿lo tomas?».
--
-- Nadie tiene que volver a abrir el PDF para decidir, pero puede: el enlace
-- está ahí. Eso es la diferencia entre un informe y una herramienta.
--
-- ── DE DÓNDE SALIÓ CADA FECHA, PARA SIEMPRE ────────────────────────────────
-- `certificaciones.fecha_origen` guarda si el vencimiento se leyó del
-- documento, si salió de la regla de 2 años, o si lo escribió una persona. En
-- seis meses, cuando alguien pregunte por qué un camión figura vencido, la
-- respuesta va a estar escrita.
--
-- Esto importa más de lo que parece: 86 de las 141 fechas NO están en el papel
-- —son la regla—. Mezclarlas con las leídas sería perder la única distinción
-- que hace confiable al resto.
--
-- ── ACEPTAR NO ES RENOVAR ──────────────────────────────────────────────────
-- Aceptar una propuesta CORRIGE la fila existente: no crea una versión nueva.
-- El papel es el mismo de siempre; lo que faltaba era su fecha. Renovar —cuando
-- llega un certificado nuevo— sigue siendo otra cosa y crea otra fila, como
-- hasta ahora.
-- ============================================================================

BEGIN;

-- ── 1. De dónde salió la fecha ────────────────────────────────────────────
ALTER TABLE public.certificaciones
  ADD COLUMN IF NOT EXISTS fecha_origen TEXT,
  ADD COLUMN IF NOT EXISTS fecha_origen_nota TEXT;

ALTER TABLE public.certificaciones DROP CONSTRAINT IF EXISTS chk_cert_fecha_origen;
ALTER TABLE public.certificaciones ADD CONSTRAINT chk_cert_fecha_origen CHECK (
  fecha_origen IS NULL OR fecha_origen = ANY (ARRAY['documento','regla_2_anios','manual','carga_inicial']));

COMMENT ON COLUMN public.certificaciones.fecha_origen IS
  'MIG409: de dónde salió el vencimiento. «documento» = lo dice el papel; «regla_2_anios» = el papel no lo dice y se asumió; «manual» = lo escribió una persona.';

-- ── 2. Lo que el lector sacó de cada archivo ──────────────────────────────
CREATE TABLE IF NOT EXISTS public.certificacion_propuestas (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    certificacion_id     UUID NOT NULL REFERENCES public.certificaciones(id) ON DELETE CASCADE,
    emision_propuesta    DATE,
    vencimiento_propuesto DATE,
    confianza            TEXT NOT NULL,
    regla                TEXT,
    -- El trozo de texto del PDF que respalda la fecha. Sin esto la propuesta es
    -- un número que hay que creer; con esto es una cita que se puede juzgar.
    evidencia            TEXT,
    caracteres_pdf       INTEGER,
    estado               TEXT NOT NULL DEFAULT 'pendiente',
    resuelto_por         UUID REFERENCES public.usuarios_perfil(id),
    resuelto_at          TIMESTAMPTZ,
    nota_resolucion      TEXT,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_prop_estado CHECK (estado = ANY (ARRAY['pendiente','aceptada','rechazada'])),
    CONSTRAINT chk_prop_confianza CHECK (confianza = ANY (ARRAY[
        'alta','regla_2_anios','sin_ancla','sin_fecha','no_vence','error']))
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_propuesta_pendiente
  ON public.certificacion_propuestas (certificacion_id) WHERE estado = 'pendiente';

COMMENT ON TABLE public.certificacion_propuestas IS
  'MIG409: lo que el lector de PDF sacó de cada archivo, con la cita que lo respalda. Se acepta o se rechaza desde Control documental.';

ALTER TABLE public.certificacion_propuestas ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS prop_lectura ON public.certificacion_propuestas;
CREATE POLICY prop_lectura ON public.certificacion_propuestas
  FOR SELECT TO authenticated USING (true);

-- ── 3. Aceptar la propuesta ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_certificacion_fijar_fecha(
    p_certificacion_id uuid,
    p_vencimiento      date,
    p_emision          date DEFAULT NULL,
    p_origen           text DEFAULT 'manual',
    p_nota             text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_user UUID := auth.uid(); v_rol TEXT := fn_user_rol();
    v_cert RECORD;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_mantenimiento',
                     'supervisor','planificador','prevencionista','auditor_calidad') THEN
        RAISE EXCEPTION 'Tu rol (%) no puede fijar vencimientos de certificados', v_rol;
    END IF;
    IF p_origen NOT IN ('documento','regla_2_anios','manual') THEN
        RAISE EXCEPTION 'Origen de fecha desconocido: %', p_origen; END IF;
    IF p_vencimiento IS NULL THEN
        RAISE EXCEPTION 'Falta la fecha de vencimiento'; END IF;
    -- El 2099 es el placeholder que significa «no vence»; fijarlo como fecha
    -- real volvería a esconder el papel, que es justo lo que se está corrigiendo.
    IF p_vencimiento >= '2099-01-01'::date THEN
        RAISE EXCEPTION 'Esa fecha es el marcador de «no vence». Si el papel no caduca, no le pongas fecha.'; END IF;

    SELECT * INTO v_cert FROM certificaciones WHERE id = p_certificacion_id;
    IF v_cert.id IS NULL THEN RAISE EXCEPTION 'El certificado no existe'; END IF;

    -- Corrige la fila: el papel es el mismo, lo que faltaba era su fecha.
    -- Renovar (papel nuevo) sigue creando una fila aparte, como siempre.
    UPDATE certificaciones
       SET fecha_vencimiento  = p_vencimiento,
           fecha_emision      = COALESCE(p_emision, fecha_emision),
           fecha_origen       = p_origen,
           fecha_origen_nota  = p_nota,
           updated_at         = NOW()
     WHERE id = p_certificacion_id;

    UPDATE certificacion_propuestas
       SET estado = 'aceptada', resuelto_por = v_user, resuelto_at = NOW(),
           nota_resolucion = p_nota
     WHERE certificacion_id = p_certificacion_id AND estado = 'pendiente';

    RETURN jsonb_build_object('success', true, 'vencimiento', p_vencimiento,
        'vencido', p_vencimiento < CURRENT_DATE, 'origen', p_origen);
END $function$;

-- ── 4. Descartar la propuesta ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_certificacion_descartar_propuesta(
    p_certificacion_id uuid,
    p_motivo           text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_user UUID := auth.uid(); v_rol TEXT := fn_user_rol(); v_n INT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_mantenimiento',
                     'supervisor','planificador','prevencionista','auditor_calidad') THEN
        RAISE EXCEPTION 'Tu rol (%) no puede descartar propuestas', v_rol; END IF;
    IF NULLIF(btrim(COALESCE(p_motivo,'')),'') IS NULL THEN
        RAISE EXCEPTION 'Di por qué se descarta: el que venga después necesita saberlo'; END IF;

    UPDATE certificacion_propuestas
       SET estado = 'rechazada', resuelto_por = v_user, resuelto_at = NOW(),
           nota_resolucion = p_motivo
     WHERE certificacion_id = p_certificacion_id AND estado = 'pendiente';
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RETURN jsonb_build_object('success', v_n > 0, 'descartadas', v_n);
END $function$;

GRANT EXECUTE ON FUNCTION public.rpc_certificacion_fijar_fecha(uuid,date,date,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_certificacion_descartar_propuesta(uuid,text) TO authenticated;

-- ── 5. La vista que alimenta la pantalla ──────────────────────────────────
CREATE OR REPLACE VIEW public.v_control_documental AS
SELECT
    a.id                       AS activo_id,
    COALESCE(a.patente, a.codigo) AS patente,
    a.codigo                   AS activo_codigo,
    a.nombre                   AS activo_nombre,
    a.tipo::text               AS activo_tipo,
    a.estado::text             AS activo_estado,
    v.id                       AS certificacion_id,
    v.tipo::text               AS tipo,
    v.numero_certificado,
    v.entidad_certificadora,
    v.fecha_emision::date      AS fecha_emision,
    v.fecha_vencimiento::date  AS fecha_vencimiento,
    v.estado_real::text        AS estado,
    v.dias_restantes,
    v.archivo_url,
    v.bloqueante,
    c.fecha_origen,
    -- La propuesta pendiente, si el lector sacó algo de este archivo.
    p.id                       AS propuesta_id,
    p.vencimiento_propuesto,
    p.emision_propuesta,
    p.confianza                AS propuesta_confianza,
    p.regla                    AS propuesta_regla,
    p.evidencia                AS propuesta_evidencia,
    (p.vencimiento_propuesto IS NOT NULL AND p.vencimiento_propuesto < CURRENT_DATE) AS propuesta_vencida
  FROM v_certificacion_actual v
  JOIN activos a ON a.id = v.activo_id
  JOIN certificaciones c ON c.id = v.id
  LEFT JOIN certificacion_propuestas p
         ON p.certificacion_id = v.id AND p.estado = 'pendiente'
 WHERE a.estado <> 'dado_baja'::estado_activo_enum;

GRANT SELECT ON public.v_control_documental TO authenticated;

COMMENT ON VIEW public.v_control_documental IS
  'MIG409: cada papel de cada equipo con su estado real y, si el lector sacó algo del archivo, la fecha que propone y la cita que la respalda.';

-- ── 6. El resumen por equipo, para la lista de camiones ───────────────────
CREATE OR REPLACE VIEW public.v_control_documental_equipo AS
SELECT activo_id, patente, activo_codigo, activo_nombre, activo_tipo, activo_estado,
       count(*)                                              AS total,
       count(*) FILTER (WHERE estado = 'vencido')            AS vencidos,
       count(*) FILTER (WHERE estado = 'sin_fecha')          AS sin_fecha,
       count(*) FILTER (WHERE estado = 'por_vencer')         AS por_vencer,
       count(*) FILTER (WHERE estado = 'vigente')            AS vigentes,
       count(*) FILTER (WHERE estado = 'no_aplica')          AS no_aplica,
       count(*) FILTER (WHERE propuesta_id IS NOT NULL)      AS con_propuesta,
       count(*) FILTER (WHERE propuesta_vencida)             AS propuestas_vencidas,
       count(*) FILTER (WHERE estado = 'vencido' AND bloqueante) AS vencidos_bloqueantes
  FROM v_control_documental
 GROUP BY 1,2,3,4,5,6;

GRANT SELECT ON public.v_control_documental_equipo TO authenticated;

-- ── 7. Cómo queda ─────────────────────────────────────────────────────────
DO $r$
DECLARE r RECORD;
BEGIN
    SELECT count(*) AS eq,
           sum(vencidos) AS v, sum(sin_fecha) AS s, sum(por_vencer) AS pv
      INTO r FROM v_control_documental_equipo;
    RAISE NOTICE 'Control documental listo: % equipos · % vencidos · % sin fecha · % por vencer',
        r.eq, r.v, r.s, r.pv;
    RAISE NOTICE 'Las propuestas del lector se cargan con: node database/scripts/cargar-propuestas-certificados.mjs';
END
$r$;

COMMIT;
