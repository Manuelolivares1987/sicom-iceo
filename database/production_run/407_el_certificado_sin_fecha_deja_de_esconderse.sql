-- ============================================================================
-- MIG407 · Un certificado sin fecha deja de decir «no aplica»
-- ----------------------------------------------------------------------------
-- LA QUEJA
-- Llegó por el TGGF-57: los certificados de láminas de seguridad y de
-- hermeticidad están vencidos, «y para darse cuenta necesariamente hay que leer
-- los archivos».
--
-- Es exactamente así, y se puede mostrar:
--
--   TGGF-57 · hermeticidad ....... sistema: 2099-12-31 / no_aplica
--             el PDF dice: «FECHA INSPECCION: 02/05/2024» +
--                          «CERTIFICADO valido por 1 año desde fecha de Emision»
--                          → venció el 02-05-2025
--
--   TGGF-57 · laminas_seguridad .. sistema: 2099-12-31 / no_aplica
--             el PDF dice: «FECHA INSTALACION: 26/03/2024» +
--                          «garantiza la implementación por un periodo de 2 Años»
--                          → venció el 26-03-2026
--
-- ── DE DÓNDE SALE EL «NO APLICA» ────────────────────────────────────────────
-- `v_certificacion_actual` traduce cualquier fecha ≥ 2099-01-01 a «no_aplica».
-- Eso está bien pensado: hay papeles que de verdad no vencen —la factura de
-- compra, la ficha técnica, el padrón—.
--
-- El problema es que 2099 se usó para DOS cosas distintas:
--   · «este papel no vence nunca»           → correcto
--   · «cargué el PDF y no leí la fecha»     → un hueco disfrazado de estado
--
-- Y son 468 registros, todos con archivo cargado. Si el papel no aplica, ¿por
-- qué hay un PDF adjunto? Ese es justo el que hay que abrir a mano.
--
-- ── CÓMO SE DISTINGUEN, SIN ADIVINAR ────────────────────────────────────────
-- No hace falta una lista escrita a mano de qué tipo vence. El dato ya lo dice:
-- **si algún certificado de ese tipo tiene fecha real, ese tipo vence.**
--
--   revision_tecnica ... 88 con fecha real,  4 en 2099  → vence: los 4 son huecos
--   laminas_seguridad ..  4 con fecha real, 39 en 2099  → vence: 39 huecos
--   hermeticidad ....... 16 con fecha real, 10 en 2099  → vence: 10 huecos
--   factura_compra .....  0 con fecha real, 28 en 2099  → no vence: está bien
--   ficha_tecnica ......  0 con fecha real, 32 en 2099  → no vence: está bien
--
-- El criterio sale de la propia flota, no de una opinión.
--
-- ── QUÉ CAMBIA ─────────────────────────────────────────────────────────────
-- Aparece un estado nuevo, `sin_fecha`: hay un papel cargado, su tipo vence, y
-- nadie anotó hasta cuándo. Deja de contarse como «no aplica» y pasa a pedir
-- revisión. La fecha no se inventa: se dice que falta.
--
-- ── LO QUE NO HACE ──────────────────────────────────────────────────────────
-- No escribe ninguna fecha. Leer los 468 PDF y proponer vencimientos es otra
-- pasada (`analizar-certificados.mjs`), y se aplica revisada: una fecha mal
-- extraída deja un camión parado sin motivo o —peor— declara vigente un
-- certificado que no lo está.
-- ============================================================================

BEGIN;

-- ── 1. El estado nuevo ────────────────────────────────────────────────────
DO $r$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
         WHERE t.typname = 'estado_documento_enum' AND e.enumlabel = 'sin_fecha') THEN
        ALTER TYPE estado_documento_enum ADD VALUE 'sin_fecha';
    END IF;
END
$r$;

COMMIT;

-- El valor nuevo del enum tiene que estar comprometido antes de usarse.
BEGIN;

-- ── 2. Qué tipos de certificado vencen ────────────────────────────────────
CREATE OR REPLACE VIEW public.v_certificado_tipo_vence AS
SELECT tipo,
       count(*) FILTER (WHERE fecha_vencimiento::date <> '2099-12-31') AS con_fecha_real,
       count(*) FILTER (WHERE fecha_vencimiento::date  = '2099-12-31') AS en_placeholder,
       -- Si alguno de ese tipo tiene fecha real, el tipo vence. El criterio lo
       -- da la propia flota: no hay lista escrita a mano que se desactualice.
       (count(*) FILTER (WHERE fecha_vencimiento::date <> '2099-12-31') > 0) AS vence
  FROM certificaciones
 GROUP BY tipo;

COMMENT ON VIEW public.v_certificado_tipo_vence IS
  'MIG407: qué tipos de certificado tienen vencimiento, deducido de la propia flota — si alguno tiene fecha real, el tipo vence.';

GRANT SELECT ON public.v_certificado_tipo_vence TO authenticated;

-- ── 3. La vista deja de esconder los huecos ───────────────────────────────
CREATE OR REPLACE VIEW public.v_certificacion_actual AS
SELECT DISTINCT ON (c.activo_id, c.tipo)
    c.id, c.activo_id, c.tipo, c.numero_certificado, c.entidad_certificadora,
    c.fecha_emision, c.fecha_vencimiento, c.estado, c.archivo_url, c.notas,
    c.bloqueante, c.created_at, c.updated_at, c.created_by,
    CASE
        -- [MIG407] Papel cargado, de un tipo que vence, sin fecha anotada. No
        -- es «no aplica»: es un hueco que hay que ir a leer al PDF.
        WHEN (c.fecha_vencimiento IS NULL OR c.fecha_vencimiento >= '2099-01-01'::date)
             AND c.archivo_url IS NOT NULL
             AND COALESCE(tv.vence, FALSE)
        THEN 'sin_fecha'::text
        WHEN c.fecha_vencimiento IS NULL OR c.fecha_vencimiento >= '2099-01-01'::date THEN 'no_aplica'::text
        WHEN c.fecha_vencimiento < CURRENT_DATE THEN 'vencido'::text
        WHEN c.fecha_vencimiento <= (CURRENT_DATE + 30) THEN 'por_vencer'::text
        ELSE 'vigente'::text
    END::estado_documento_enum AS estado_real,
    c.fecha_vencimiento - CURRENT_DATE AS dias_restantes
  FROM certificaciones c
  LEFT JOIN v_certificado_tipo_vence tv ON tv.tipo = c.tipo
 ORDER BY c.activo_id, c.tipo, c.fecha_vencimiento DESC NULLS LAST, c.created_at DESC;

COMMENT ON VIEW public.v_certificacion_actual IS
  'MIG407: el estado real del último certificado de cada (equipo, tipo). «sin_fecha» = hay PDF cargado de un tipo que vence y nadie anotó hasta cuándo.';

-- ── 4. Cuánto se estaba escondiendo ───────────────────────────────────────
DO $r$
DECLARE r RECORD; v_n INT;
BEGIN
    SELECT count(*) INTO v_n FROM v_certificacion_actual WHERE estado_real::text = 'sin_fecha';
    RAISE NOTICE 'Certificados que decían «no aplica» y en realidad les falta la fecha: %', v_n;

    FOR r IN
        SELECT tipo, count(*) AS n FROM v_certificacion_actual
         WHERE estado_real::text = 'sin_fecha' GROUP BY 1 ORDER BY 2 DESC LIMIT 8
    LOOP RAISE NOTICE '   %: %', rpad(r.tipo::text, 22), r.n; END LOOP;

    FOR r IN
        SELECT a.patente, v.tipo FROM v_certificacion_actual v
          JOIN activos a ON a.id = v.activo_id
         WHERE v.estado_real::text = 'sin_fecha' AND a.patente = 'TGGF-57'
    LOOP RAISE NOTICE 'TGGF-57 · % → ahora pide revisión', r.tipo; END LOOP;
END
$r$;

COMMIT;
