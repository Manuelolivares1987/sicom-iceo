-- ============================================================================
-- MIG484 · Un «Otro» que dice cuál
-- ============================================================================
--
-- LO QUE PIDIÓ MANUEL
-- 01-09-2026: «quiero poder agregar otros tipos de certificados a la
-- documentación del camión; cuando diga Otros, que me pida especificaciones, no
-- que quede como otro».
--
-- LO QUE ESTABA PASANDO
-- El catálogo tiene 38 tipos y un «otra» de escape. Seis papeles cayeron ahí, y
-- en la carpeta del equipo se leen todos igual: «Otro». En el SVBJ-57 —el
-- camión del enlace— hay TRES:
--
--     · Certificado de instalación de dispositivo ADAS (tercer ojo)
--     · Certificado de instalación de dispositivo DSM
--     · otra copia del ADAS
--
-- Y hay algo peor que el nombre. `v_certificacion_actual` y el RPC del QR hacen
-- DISTINCT ON (activo_id, tipo): con los tres bajo el mismo `tipo`, el sistema
-- los trata como VERSIONES DEL MISMO PAPEL y muestra uno solo. El certificado
-- del DSM del SVBJ-57 hoy no se ve en ninguna parte —no está perdido, está
-- tapado por el ADAS—. Lo mismo le pasa al de frenado del TRDP-97.
--
-- LA DECISIÓN
-- La identidad de un documento deja de ser `tipo` y pasa a ser el par
-- (tipo, tipo_otro). Cuando el tipo es «otra», el nombre es obligatorio: sin
-- nombre no se guarda. Así dos «otros» distintos son dos papeles distintos, y
-- dos cargas del mismo nombre siguen siendo renovaciones del mismo papel.
--
-- LOS SEIS QUE YA ESTABAN
-- Se les pone nombre leyéndolo del propio archivo que subieron. No se inventa:
-- el nombre del PDF dice qué certificado es. Queda anotado en las notas de cada
-- fila que el nombre salió de ahí.
-- ============================================================================

BEGIN;

-- ── 1 · El nombre del papel cuando el tipo no alcanza ───────────────────────
ALTER TABLE certificaciones
  ADD COLUMN IF NOT EXISTS tipo_otro TEXT;

COMMENT ON COLUMN certificaciones.tipo_otro IS
    'Cómo se llama este papel cuando el tipo es «otra». Obligatorio en ese '
    'caso: es lo que lo distingue de los demás «otros» del mismo equipo.';

-- ── 2 · Ponerle nombre a los seis que ya estaban ────────────────────────────
UPDATE certificaciones SET tipo_otro = 'Instalación de dispositivo ADAS (tercer ojo)'
 WHERE tipo = 'otra' AND tipo_otro IS NULL AND archivo_url ILIKE '%ADAS_TERCER_OJO%';

UPDATE certificaciones SET tipo_otro = 'Instalación de dispositivo DSM'
 WHERE tipo = 'otra' AND tipo_otro IS NULL AND archivo_url ILIKE '%DISPOSITIVO_DSM%';

UPDATE certificaciones SET tipo_otro = 'Capacidad de frenado'
 WHERE tipo = 'otra' AND tipo_otro IS NULL
   AND (archivo_url ILIKE '%frenado%' OR archivo_url ILIKE '%frenado.pdf%');

UPDATE certificaciones SET tipo_otro = 'Hoja de datos de seguridad (HDS) diésel'
 WHERE tipo = 'otra' AND tipo_otro IS NULL AND archivo_url ILIKE '%HDS%';

-- Lo que no se pueda deducir del archivo NO se inventa: queda dicho.
UPDATE certificaciones SET tipo_otro = 'Sin especificar (cargado antes del 01-09-2026)'
 WHERE tipo = 'otra' AND tipo_otro IS NULL;

UPDATE certificaciones
   SET notas = COALESCE(NULLIF(btrim(notas),''), '')
               || CASE WHEN COALESCE(btrim(notas),'') = '' THEN '' ELSE ' · ' END
               || 'MIG484: el nombre del papel se dedujo del archivo cargado.'
 WHERE tipo = 'otra' AND tipo_otro IS NOT NULL
   AND tipo_otro <> 'Sin especificar (cargado antes del 01-09-2026)';

-- ── 3 · Un «otro» sin nombre no entra ───────────────────────────────────────
ALTER TABLE certificaciones DROP CONSTRAINT IF EXISTS chk_cert_otro_con_nombre;
ALTER TABLE certificaciones
  ADD CONSTRAINT chk_cert_otro_con_nombre
  CHECK (tipo <> 'otra' OR length(btrim(COALESCE(tipo_otro, ''))) >= 3);

-- ── 4 · La identidad del documento es el par ────────────────────────────────
--
-- Sin esto, dos «otros» distintos del mismo equipo se tapan uno al otro.
CREATE OR REPLACE FUNCTION fn_certificado_clave(p_tipo TEXT, p_tipo_otro TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE WHEN p_tipo = 'otra'
                THEN 'otra:' || lower(btrim(COALESCE(p_tipo_otro, '')))
                ELSE p_tipo END;
$$;

COMMENT ON FUNCTION fn_certificado_clave(TEXT, TEXT) IS
    'Qué papel es, para efectos de «cuál es el vigente». Dos cargas con la '
    'misma clave son renovaciones; con clave distinta son papeles distintos.';

/** Cómo se muestra: el nombre escrito manda sobre la etiqueta del tipo. */
CREATE OR REPLACE FUNCTION fn_certificado_etiqueta(p_tipo TEXT, p_tipo_otro TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT COALESCE(NULLIF(btrim(COALESCE(p_tipo_otro, '')), ''), p_tipo);
$$;

-- ── 5 · Las vistas dejan de tapar papeles ───────────────────────────────────
--
-- Las columnas nuevas van AL FINAL: CREATE OR REPLACE VIEW no admite meterlas
-- en medio.
CREATE OR REPLACE VIEW v_certificacion_actual AS
 SELECT DISTINCT ON (c.activo_id, fn_certificado_clave(c.tipo::text, c.tipo_otro))
    c.id,
    c.activo_id,
    c.tipo,
    c.numero_certificado,
    c.entidad_certificadora,
    c.fecha_emision,
    c.fecha_vencimiento,
    c.estado,
    c.archivo_url,
    c.notas,
    c.bloqueante,
    c.created_at,
    c.updated_at,
    c.created_by,
        CASE
            WHEN c.fecha_origen = 'documento_sin_vencimiento'::text THEN 'no_aplica'::text
            WHEN c.vigencia_dudosa THEN 'sin_fecha'::text
            WHEN (c.fecha_vencimiento IS NULL OR c.fecha_vencimiento >= '2099-01-01'::date) AND c.archivo_url IS NOT NULL AND COALESCE(tv.vence, false) THEN 'sin_fecha'::text
            WHEN c.fecha_vencimiento IS NULL OR c.fecha_vencimiento >= '2099-01-01'::date THEN 'no_aplica'::text
            WHEN c.fecha_vencimiento < CURRENT_DATE THEN 'vencido'::text
            WHEN c.fecha_vencimiento <= (CURRENT_DATE + 30) THEN 'por_vencer'::text
            ELSE 'vigente'::text
        END::estado_documento_enum AS estado_real,
        CASE
            WHEN c.vigencia_dudosa THEN NULL::integer
            ELSE c.fecha_vencimiento - CURRENT_DATE
        END AS dias_restantes,
    c.tipo_otro,
    fn_certificado_etiqueta(c.tipo::text, c.tipo_otro) AS etiqueta,
    fn_certificado_clave(c.tipo::text, c.tipo_otro)    AS doc_clave
   FROM certificaciones c
     LEFT JOIN v_certificado_tipo_vence tv ON tv.tipo = c.tipo
  ORDER BY c.activo_id, fn_certificado_clave(c.tipo::text, c.tipo_otro),
           c.created_at DESC, c.fecha_vencimiento DESC NULLS LAST;

-- ── 6 · El QR calcula aparte, y hay que arreglarlo en los dos lados ─────────
--
-- Agregar una columna al RETURNS TABLE cambia el tipo de retorno: hay que
-- soltar la función antes, no basta CREATE OR REPLACE.
DROP FUNCTION IF EXISTS public.rpc_documentos_activo_publico(UUID);

CREATE OR REPLACE FUNCTION public.rpc_documentos_activo_publico(p_activo_id uuid)
 RETURNS TABLE(tipo text, numero_certificado text, entidad text, fecha_emision date,
               fecha_vencimiento date, dias_restantes integer, estado text,
               archivo_url text, etiqueta text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT DISTINCT ON (fn_certificado_clave(c.tipo::text, c.tipo_otro))
         c.tipo::text, c.numero_certificado::text, c.entidad_certificadora::text,
         c.fecha_emision,
         CASE WHEN c.vigencia_dudosa OR c.fecha_vencimiento >= DATE '2099-01-01' THEN NULL
              ELSE c.fecha_vencimiento END,
         CASE WHEN c.vigencia_dudosa OR c.fecha_vencimiento >= DATE '2099-01-01' THEN NULL
              ELSE (c.fecha_vencimiento - CURRENT_DATE)::int END,
         CASE
           WHEN c.fecha_origen = 'documento_sin_vencimiento' THEN 'permanente'
           WHEN c.vigencia_dudosa THEN 'sin_fecha'
           WHEN (c.fecha_vencimiento IS NULL OR c.fecha_vencimiento >= DATE '2099-01-01')
                AND c.archivo_url IS NOT NULL
                AND NOT fn_certificado_tipo_permanente(c.tipo::text)
             THEN 'sin_fecha'
           WHEN c.fecha_vencimiento IS NULL OR c.fecha_vencimiento >= DATE '2099-01-01' THEN 'permanente'
           WHEN c.fecha_vencimiento < CURRENT_DATE THEN 'vencido'
           WHEN c.fecha_vencimiento <= CURRENT_DATE + 45 THEN 'por_vencer'
           ELSE 'vigente'
         END,
         c.archivo_url,
         -- [MIG484] Para que el cliente lea «Instalación de ADAS» y no «otra».
         fn_certificado_etiqueta(c.tipo::text, c.tipo_otro)
    FROM certificaciones c
   WHERE c.activo_id = p_activo_id
   -- [MIG429] Mismo criterio que adentro: el QR del cliente y la pantalla del
   -- planificador tienen que estar mirando el mismo papel.
   ORDER BY fn_certificado_clave(c.tipo::text, c.tipo_otro),
            c.created_at DESC, c.fecha_vencimiento DESC NULLS LAST
$function$;

-- ── 7 · Cargar el papel pidiendo el nombre cuando hace falta ────────────────
--
-- Había DOS versiones de esta función (una con VARCHAR, otra con TEXT y
-- p_origen). Agregar un parámetro más habría dejado tres y la llamada sería
-- ambigua: se dejan las dos afuera y queda una sola.
DROP FUNCTION IF EXISTS public.rpc_renovar_certificacion(
    UUID, tipo_certificacion_enum, DATE, DATE, TEXT, CHARACTER VARYING,
    CHARACTER VARYING, BOOLEAN, TEXT);
DROP FUNCTION IF EXISTS public.rpc_renovar_certificacion(
    UUID, tipo_certificacion_enum, DATE, DATE, TEXT, TEXT, TEXT, BOOLEAN, TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.rpc_renovar_certificacion(
    p_activo_id         UUID,
    p_tipo              tipo_certificacion_enum,
    p_fecha_emision     DATE,
    p_fecha_vencimiento DATE,
    p_archivo_url       TEXT    DEFAULT NULL,
    p_numero            TEXT    DEFAULT NULL,
    p_entidad           TEXT    DEFAULT NULL,
    p_bloqueante        BOOLEAN DEFAULT NULL,
    p_notas             TEXT    DEFAULT NULL,
    p_origen            TEXT    DEFAULT NULL,
    p_tipo_otro         TEXT    DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_user  UUID := auth.uid();
    v_rol   TEXT := fn_user_rol();
    v_id    UUID;
    v_bloq  BOOLEAN;
    v_otro  TEXT := NULLIF(btrim(COALESCE(p_tipo_otro, '')), '');
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado.'; END IF;
    IF v_rol NOT IN ('administrador','supervisor','subgerente_operaciones','jefe_operaciones',
                     'jefe_mantenimiento','planificador','auditor_calidad') THEN
        RAISE EXCEPTION 'Sin permiso para actualizar documentación de equipos. Rol: %', v_rol;
    END IF;
    IF p_fecha_emision IS NULL OR p_fecha_vencimiento IS NULL THEN
        RAISE EXCEPTION 'Fecha de emisión y vencimiento son obligatorias.';
    END IF;
    IF p_fecha_vencimiento < p_fecha_emision THEN
        RAISE EXCEPTION 'El vencimiento no puede ser anterior a la emisión.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM activos WHERE id = p_activo_id) THEN
        RAISE EXCEPTION 'Activo % no existe', p_activo_id;
    END IF;

    -- [MIG484] «Otro» sin nombre es lo que hay que terminar. Sin esto, el papel
    -- entra a la carpeta llamándose igual que otros tres y tapa a los demás.
    IF p_tipo = 'otra' AND (v_otro IS NULL OR length(v_otro) < 3) THEN
        RAISE EXCEPTION 'Escribe qué certificado es. «Otro» sin nombre se confunde con los demás.';
    END IF;
    IF p_tipo <> 'otra' AND v_otro IS NOT NULL THEN
        v_otro := NULL;   -- el nombre libre sólo aplica al escape
    END IF;

    -- Por defecto, los documentos legales de circulación son bloqueantes; el
    -- que carga el papel puede marcar cualquier otro como bloqueante.
    v_bloq := COALESCE(p_bloqueante, p_tipo IN ('revision_tecnica','soap','permiso_circulacion'));

    INSERT INTO certificaciones (
        activo_id, tipo, tipo_otro, numero_certificado, entidad_certificadora,
        fecha_emision, fecha_vencimiento, estado, archivo_url, bloqueante,
        notas, created_by, fecha_origen
    ) VALUES (
        p_activo_id, p_tipo, v_otro, p_numero, p_entidad,
        p_fecha_emision, p_fecha_vencimiento,
        -- El cast es obligatorio: sin él el CASE es TEXT y el INSERT revienta.
        (CASE WHEN p_fecha_vencimiento <= CURRENT_DATE THEN 'vencido'
              WHEN p_fecha_vencimiento <= CURRENT_DATE + 30 THEN 'por_vencer'
              ELSE 'vigente' END)::estado_documento_enum,
        p_archivo_url, v_bloq,
        COALESCE(NULLIF(btrim(p_notas), ''), 'Documento actualizado desde el sistema'),
        v_user,
        NULLIF(btrim(COALESCE(p_origen, '')), '')
    ) RETURNING id INTO v_id;

    RETURN jsonb_build_object('success', true, 'certificacion_id', v_id,
                              'etiqueta', fn_certificado_etiqueta(p_tipo::text, v_otro));
END $function$;

-- ── 8 · Los nombres que ya se usaron, para no escribir tres variantes ───────
CREATE OR REPLACE VIEW v_certificado_tipos_otros AS
SELECT btrim(tipo_otro)   AS nombre,
       count(*)           AS usos,
       max(created_at)    AS ultimo_uso
  FROM certificaciones
 WHERE tipo = 'otra' AND btrim(COALESCE(tipo_otro,'')) <> ''
 GROUP BY btrim(tipo_otro)
 ORDER BY count(*) DESC, btrim(tipo_otro);

COMMENT ON VIEW v_certificado_tipos_otros IS
    'Los nombres de «otros» que ya se usaron, para ofrecerlos al cargar uno '
    'nuevo. Evita que el mismo papel termine escrito de tres formas.';

GRANT SELECT ON v_certificado_tipos_otros TO authenticated;

-- ── 9 · Permisos (el DROP se llevó los GRANT) ───────────────────────────────
REVOKE ALL ON FUNCTION public.rpc_renovar_certificacion(
    UUID, tipo_certificacion_enum, DATE, DATE, TEXT, TEXT, TEXT, BOOLEAN, TEXT, TEXT, TEXT)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_renovar_certificacion(
    UUID, tipo_certificacion_enum, DATE, DATE, TEXT, TEXT, TEXT, BOOLEAN, TEXT, TEXT, TEXT)
    TO authenticated;

REVOKE ALL ON FUNCTION public.rpc_documentos_activo_publico(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rpc_documentos_activo_publico(UUID) TO anon, authenticated;

-- ── Verificación (sólo lectura) ─────────────────────────────────────────────
DO $mig$
DECLARE v_sin INT; v_svbj INT; r RECORD;
BEGIN
    SELECT count(*) INTO v_sin FROM certificaciones
     WHERE tipo = 'otra' AND btrim(COALESCE(tipo_otro,'')) = '';
    SELECT count(*) INTO v_svbj FROM v_certificacion_actual
     WHERE activo_id = '9ca9b860-d1ac-4fb0-97e8-af68d7f24f4a' AND tipo = 'otra';
    RAISE NOTICE '«otros» sin nombre: % · los del SVBJ-57 que ahora se ven por separado: %',
                 v_sin, v_svbj;
    FOR r IN SELECT nombre, usos FROM v_certificado_tipos_otros LOOP
        RAISE NOTICE '  % (%)', r.nombre, r.usos;
    END LOOP;
END $mig$;

COMMIT;
