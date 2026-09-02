-- ============================================================================
-- MIG486 · Corregir un papel, y anularlo cuando no corresponde
-- ============================================================================
--
-- LO QUE PIDIÓ MANUEL
-- 01-09-2026: «necesito que también se pueda editar, por ejemplo en Control
-- documental; en su defecto eliminar. Lo mismo en Bitácora» — y al preguntarle
-- qué parte de la bitácora: «la parte documental de los equipos».
--
-- LO QUE HABÍA
-- Un papel cargado sólo se podía renovar (cargar la versión siguiente) o fijarle
-- la fecha. Si alguien se equivocaba de tipo, de patente o subía el archivo del
-- camión de al lado, no había forma de arreglarlo desde ninguna pantalla: había
-- que entrar por SQL. Y como cada carga deja una fila, el error quedaba ahí
-- para siempre, compitiendo por ser «el vigente».
--
-- ELIMINAR NO ES BORRAR
-- Estos papeles son la prueba de qué se declaró vigente y cuándo. En un contrato
-- con multas —ENEX— borrar la fila deja al sistema sin cómo explicar por qué el
-- semáforo estaba verde el mes pasado. Así que «eliminar» ANULA: el papel sale
-- de todas las vistas, del QR y de los conteos, pero la fila queda con quién lo
-- anuló, cuándo y por qué. Para el que mira la pantalla desapareció; para una
-- auditoría sigue estando.
--
-- Y un papel anulado deja de tapar al anterior: si había una versión previa del
-- mismo documento, esa vuelve a ser la vigente. Anular el papel equivocado no
-- deja al equipo sin documento, lo devuelve al que estaba antes.
--
-- QUIÉN
-- Corregir, los mismos que pueden cargar. Anular, sólo jefatura: administrador,
-- subgerente y jefe de operaciones, jefe de mantenimiento y planificador. Un
-- papel que desaparece de la carpeta del equipo no es una corrección de tipeo.
-- ============================================================================

BEGIN;

-- ── 1 · La anulación, con nombre y motivo ───────────────────────────────────
ALTER TABLE certificaciones
  ADD COLUMN IF NOT EXISTS anulado_at    TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS anulado_por   UUID REFERENCES usuarios_perfil(id),
  ADD COLUMN IF NOT EXISTS anulado_motivo TEXT;

COMMENT ON COLUMN certificaciones.anulado_at IS
    'El papel se sacó de circulación. No se borra: es la prueba de qué se '
    'declaró vigente y cuándo. Fuera de las vistas, del QR y de los conteos.';

CREATE INDEX IF NOT EXISTS idx_certificaciones_vigentes
    ON certificaciones (activo_id, tipo) WHERE anulado_at IS NULL;

-- ── 2 · El registro de las correcciones ─────────────────────────────────────
--
-- Cambiar la fecha de vencimiento de un papel cambia el semáforo de un camión.
-- Quién lo cambió y qué decía antes no puede depender de la memoria de nadie.
CREATE TABLE IF NOT EXISTS certificacion_ediciones (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    certificacion_id UUID NOT NULL REFERENCES certificaciones(id) ON DELETE CASCADE,
    accion           TEXT NOT NULL CHECK (accion IN ('editar','anular','restaurar')),
    antes            JSONB,
    despues          JSONB,
    motivo           TEXT,
    hecho_por        UUID REFERENCES usuarios_perfil(id),
    hecho_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_cert_ediciones_cert
    ON certificacion_ediciones (certificacion_id, hecho_at DESC);

ALTER TABLE certificacion_ediciones ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS cert_ediciones_lectura ON certificacion_ediciones;
CREATE POLICY cert_ediciones_lectura ON certificacion_ediciones
    FOR SELECT TO authenticated USING (TRUE);

-- ── 3 · Las vistas dejan de ver lo anulado ──────────────────────────────────
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
  -- [MIG486] Un papel anulado no compite por ser el vigente: si había una
  -- versión anterior del mismo documento, esa vuelve a serlo.
  WHERE c.anulado_at IS NULL
  ORDER BY c.activo_id, fn_certificado_clave(c.tipo::text, c.tipo_otro),
           c.created_at DESC, c.fecha_vencimiento DESC NULLS LAST;

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
         fn_certificado_etiqueta(c.tipo::text, c.tipo_otro)
    FROM certificaciones c
   WHERE c.activo_id = p_activo_id
     AND c.anulado_at IS NULL          -- [MIG486]
   ORDER BY fn_certificado_clave(c.tipo::text, c.tipo_otro),
            c.created_at DESC, c.fecha_vencimiento DESC NULLS LAST
$function$;

-- ── 4 · Corregir ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_certificacion_editar(
    p_certificacion_id  UUID,
    p_tipo              tipo_certificacion_enum DEFAULT NULL,
    p_tipo_otro         TEXT    DEFAULT NULL,
    p_fecha_emision     DATE    DEFAULT NULL,
    p_fecha_vencimiento DATE    DEFAULT NULL,
    p_numero            TEXT    DEFAULT NULL,
    p_entidad           TEXT    DEFAULT NULL,
    p_bloqueante        BOOLEAN DEFAULT NULL,
    p_archivo_url       TEXT    DEFAULT NULL,
    p_motivo            TEXT    DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user  UUID := auth.uid();
    v_rol   TEXT := fn_user_rol();
    v_antes JSONB;
    v_desp  JSONB;
    v_tipo  tipo_certificacion_enum;
    v_otro  TEXT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado.'; END IF;
    IF v_rol NOT IN ('administrador','supervisor','subgerente_operaciones','jefe_operaciones',
                     'jefe_mantenimiento','planificador','auditor_calidad') THEN
        RAISE EXCEPTION 'Sin permiso para corregir documentación de equipos. Rol: %', v_rol;
    END IF;

    SELECT to_jsonb(c) INTO v_antes FROM certificaciones c WHERE c.id = p_certificacion_id;
    IF v_antes IS NULL THEN RAISE EXCEPTION 'Ese documento no existe.'; END IF;
    IF (v_antes ->> 'anulado_at') IS NOT NULL THEN
        RAISE EXCEPTION 'Ese documento está anulado. Restáuralo antes de corregirlo.';
    END IF;

    v_tipo := COALESCE(p_tipo, (v_antes ->> 'tipo')::tipo_certificacion_enum);
    v_otro := COALESCE(NULLIF(btrim(COALESCE(p_tipo_otro,'')), ''), v_antes ->> 'tipo_otro');

    -- [MIG484] Sigue valiendo acá: un «otro» sin nombre se confunde con los demás.
    IF v_tipo = 'otra' AND length(btrim(COALESCE(v_otro,''))) < 3 THEN
        RAISE EXCEPTION 'Escribe qué certificado es. «Otro» sin nombre se confunde con los demás.';
    END IF;
    IF v_tipo <> 'otra' THEN v_otro := NULL; END IF;

    IF COALESCE(p_fecha_vencimiento, (v_antes ->> 'fecha_vencimiento')::date)
       < COALESCE(p_fecha_emision, (v_antes ->> 'fecha_emision')::date) THEN
        RAISE EXCEPTION 'El vencimiento no puede ser anterior a la emisión.';
    END IF;

    UPDATE certificaciones c
       SET tipo = v_tipo,
           tipo_otro = v_otro,
           fecha_emision       = COALESCE(p_fecha_emision, c.fecha_emision),
           fecha_vencimiento   = COALESCE(p_fecha_vencimiento, c.fecha_vencimiento),
           numero_certificado  = COALESCE(NULLIF(btrim(COALESCE(p_numero,'')),''), c.numero_certificado),
           entidad_certificadora = COALESCE(NULLIF(btrim(COALESCE(p_entidad,'')),''), c.entidad_certificadora),
           bloqueante          = COALESCE(p_bloqueante, c.bloqueante),
           archivo_url         = COALESCE(NULLIF(btrim(COALESCE(p_archivo_url,'')),''), c.archivo_url),
           -- Una fecha corregida a mano es una fecha escrita a mano: que el
           -- control del estándar la trate como tal y no como leída del archivo.
           fecha_origen        = CASE WHEN p_fecha_vencimiento IS NOT NULL
                                      THEN 'manual' ELSE c.fecha_origen END,
           -- La corrección resuelve la duda: alguien miró el papel.
           vigencia_dudosa     = CASE WHEN p_fecha_vencimiento IS NOT NULL
                                      THEN FALSE ELSE c.vigencia_dudosa END,
           estado = (CASE WHEN COALESCE(p_fecha_vencimiento, c.fecha_vencimiento) <= CURRENT_DATE THEN 'vencido'
                          WHEN COALESCE(p_fecha_vencimiento, c.fecha_vencimiento) <= CURRENT_DATE + 30 THEN 'por_vencer'
                          ELSE 'vigente' END)::estado_documento_enum,
           updated_at = NOW()
     WHERE c.id = p_certificacion_id;

    SELECT to_jsonb(c) INTO v_desp FROM certificaciones c WHERE c.id = p_certificacion_id;

    INSERT INTO certificacion_ediciones (certificacion_id, accion, antes, despues, motivo, hecho_por)
    VALUES (p_certificacion_id, 'editar', v_antes, v_desp,
            NULLIF(btrim(COALESCE(p_motivo,'')),''), v_user);

    RETURN jsonb_build_object('success', TRUE,
        'etiqueta', fn_certificado_etiqueta(v_desp ->> 'tipo', v_desp ->> 'tipo_otro'));
END;
$$;

-- ── 5 · Anular, y volver atrás si se anuló el que no era ────────────────────
CREATE OR REPLACE FUNCTION rpc_certificacion_anular(
    p_certificacion_id UUID,
    p_motivo           TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user  UUID := auth.uid();
    v_rol   TEXT := fn_user_rol();
    v_antes JSONB;
    v_queda TEXT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado.'; END IF;
    -- Más estrecho que corregir a propósito: un papel que desaparece de la
    -- carpeta del equipo no es una corrección de tipeo.
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_operaciones',
                     'jefe_mantenimiento','planificador') THEN
        RAISE EXCEPTION 'Anular un documento es de jefatura. Rol: %', v_rol;
    END IF;
    IF length(btrim(COALESCE(p_motivo,''))) < 5 THEN
        RAISE EXCEPTION 'Escribe por qué se anula: queda en el registro del equipo.';
    END IF;

    SELECT to_jsonb(c) INTO v_antes FROM certificaciones c WHERE c.id = p_certificacion_id;
    IF v_antes IS NULL THEN RAISE EXCEPTION 'Ese documento no existe.'; END IF;
    IF (v_antes ->> 'anulado_at') IS NOT NULL THEN
        RETURN jsonb_build_object('success', TRUE, 'ya_estaba', TRUE);
    END IF;

    UPDATE certificaciones
       SET anulado_at = NOW(), anulado_por = v_user,
           anulado_motivo = btrim(p_motivo), updated_at = NOW()
     WHERE id = p_certificacion_id;

    INSERT INTO certificacion_ediciones (certificacion_id, accion, antes, motivo, hecho_por)
    VALUES (p_certificacion_id, 'anular', v_antes, btrim(p_motivo), v_user);

    -- ¿Queda algún papel del mismo documento? Si sí, ese vuelve a ser el vigente.
    SELECT to_char(v.fecha_vencimiento, 'YYYY-MM-DD') INTO v_queda
      FROM v_certificacion_actual v
     WHERE v.activo_id = (v_antes ->> 'activo_id')::UUID
       AND v.doc_clave = fn_certificado_clave(v_antes ->> 'tipo', v_antes ->> 'tipo_otro');

    RETURN jsonb_build_object('success', TRUE, 'vuelve_a_vigente', v_queda);
END;
$$;

CREATE OR REPLACE FUNCTION rpc_certificacion_restaurar(p_certificacion_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_rol  TEXT := fn_user_rol();
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado.'; END IF;
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_operaciones',
                     'jefe_mantenimiento','planificador') THEN
        RAISE EXCEPTION 'Restaurar un documento es de jefatura. Rol: %', v_rol;
    END IF;

    UPDATE certificaciones
       SET anulado_at = NULL, anulado_por = NULL, anulado_motivo = NULL, updated_at = NOW()
     WHERE id = p_certificacion_id AND anulado_at IS NOT NULL;

    INSERT INTO certificacion_ediciones (certificacion_id, accion, hecho_por)
    VALUES (p_certificacion_id, 'restaurar', v_user);

    RETURN jsonb_build_object('success', TRUE);
END;
$$;

-- ── 6 · Lo anulado, para poder deshacerlo ───────────────────────────────────
CREATE OR REPLACE VIEW v_certificaciones_anuladas AS
SELECT c.id, c.activo_id, COALESCE(a.patente, a.codigo) AS patente,
       c.tipo::text AS tipo, c.tipo_otro,
       fn_certificado_etiqueta(c.tipo::text, c.tipo_otro) AS etiqueta,
       c.fecha_emision, c.fecha_vencimiento, c.archivo_url,
       c.anulado_at, c.anulado_motivo,
       (SELECT up.nombre_completo FROM usuarios_perfil up WHERE up.id = c.anulado_por) AS anulado_por
  FROM certificaciones c
  JOIN activos a ON a.id = c.activo_id
 WHERE c.anulado_at IS NOT NULL;

GRANT SELECT ON v_certificaciones_anuladas TO authenticated;

-- ── 7 · Permisos ────────────────────────────────────────────────────────────
REVOKE ALL ON FUNCTION rpc_certificacion_editar(UUID, tipo_certificacion_enum, TEXT, DATE, DATE, TEXT, TEXT, BOOLEAN, TEXT, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_certificacion_anular(UUID, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_certificacion_restaurar(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_certificacion_editar(UUID, tipo_certificacion_enum, TEXT, DATE, DATE, TEXT, TEXT, BOOLEAN, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_certificacion_anular(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_certificacion_restaurar(UUID) TO authenticated;

-- ── Verificación (sólo lectura) ─────────────────────────────────────────────
DO $mig$
DECLARE v_an INT; v_vig INT;
BEGIN
    SELECT count(*) INTO v_an  FROM certificaciones WHERE anulado_at IS NOT NULL;
    SELECT count(*) INTO v_vig FROM v_certificacion_actual;
    RAISE NOTICE 'papeles anulados: % · documentos vigentes en la flota: %', v_an, v_vig;
END $mig$;

COMMIT;
