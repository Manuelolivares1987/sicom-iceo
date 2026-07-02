-- ============================================================================
-- SICOM-ICEO | 183 — Documentos por vencer/vencidos por equipo + renovar genérico
-- ============================================================================
-- Pedido Manuel (2026-06-30): en el Plan Semanal mostrar las patentes con
-- problemas de documentos (todos los con vencimiento: revisión técnica, SOAP,
-- permiso de circulación, hermeticidad, TC8/SEC, seguro RC, FOPS/ROPS, cert.
-- gancho, etc.), vencidos o por vencer, con acción de renovar.
--
-- 1. Vista v_documentos_equipo_estado: el documento MÁS RECIENTE por (activo,
--    tipo) con días restantes. La app filtra los que vencen dentro de N días.
-- 2. RPC rpc_renovar_certificacion: registra la renovación (nuevo doc + nuevo
--    vencimiento) para CUALQUIER tipo de certificación (generaliza MIG137).
--
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

-- ── 1. Vista: último documento por equipo y tipo ─────────────────────────────
DROP VIEW IF EXISTS v_documentos_equipo_estado CASCADE;
CREATE VIEW v_documentos_equipo_estado AS
WITH ult AS (
    SELECT DISTINCT ON (c.activo_id, c.tipo)
        c.activo_id, c.tipo, c.fecha_emision, c.fecha_vencimiento, c.estado,
        c.archivo_url, c.numero_certificado, c.entidad_certificadora, c.bloqueante
      FROM certificaciones c
     ORDER BY c.activo_id, c.tipo, c.fecha_vencimiento DESC NULLS LAST
)
SELECT
    u.activo_id,
    a.patente, a.codigo, a.nombre, a.estado AS activo_estado, a.operacion,
    u.tipo::text                                   AS tipo,
    u.fecha_emision,
    u.fecha_vencimiento,
    u.estado                                       AS estado_documento,
    u.bloqueante,
    u.archivo_url,
    u.numero_certificado,
    u.entidad_certificadora,
    (u.fecha_vencimiento - CURRENT_DATE)           AS dias_restantes
FROM ult u
JOIN activos a ON a.id = u.activo_id
WHERE a.estado <> 'dado_baja'
  AND u.fecha_vencimiento IS NOT NULL;

COMMENT ON VIEW v_documentos_equipo_estado IS
    'Último documento/certificación por equipo y tipo, con días restantes. MIG183.';
GRANT SELECT ON v_documentos_equipo_estado TO authenticated;


-- ── 2. RPC: renovar cualquier certificación ──────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_renovar_certificacion(
    p_activo_id         UUID,
    p_tipo              tipo_certificacion_enum,
    p_fecha_emision     DATE,
    p_fecha_vencimiento DATE,
    p_archivo_url       TEXT    DEFAULT NULL,
    p_numero            VARCHAR DEFAULT NULL,
    p_entidad           VARCHAR DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_rol  TEXT := fn_user_rol();
    v_id   UUID;
    v_bloq BOOLEAN;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado.'; END IF;
    IF v_rol NOT IN ('administrador','supervisor','subgerente_operaciones','jefe_operaciones',
                     'jefe_mantenimiento','planificador','auditor_calidad') THEN
        RAISE EXCEPTION 'Sin permiso para renovar documentos. Rol: %', v_rol;
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

    -- Documentos legales de circulación son bloqueantes.
    v_bloq := p_tipo IN ('revision_tecnica','soap','permiso_circulacion');

    INSERT INTO certificaciones (
        activo_id, tipo, numero_certificado, entidad_certificadora,
        fecha_emision, fecha_vencimiento, estado, archivo_url, bloqueante,
        notas, created_by
    ) VALUES (
        p_activo_id, p_tipo, p_numero, p_entidad,
        p_fecha_emision, p_fecha_vencimiento,
        CASE WHEN p_fecha_vencimiento <= CURRENT_DATE THEN 'vencido'
             WHEN p_fecha_vencimiento <= CURRENT_DATE + 30 THEN 'por_vencer'
             ELSE 'vigente' END,
        p_archivo_url, v_bloq,
        'Renovado desde Plan Semanal', v_user
    ) RETURNING id INTO v_id;

    RETURN jsonb_build_object('success', true, 'certificacion_id', v_id);
END $$;

REVOKE ALL ON FUNCTION rpc_renovar_certificacion(UUID,tipo_certificacion_enum,DATE,DATE,TEXT,VARCHAR,VARCHAR) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_renovar_certificacion(UUID,tipo_certificacion_enum,DATE,DATE,TEXT,VARCHAR,VARCHAR) TO authenticated;


-- ── VALIDACION ────────────────────────────────────────────────────────────────
SELECT jsonb_build_object(
    'vista_ok', EXISTS(SELECT 1 FROM information_schema.views WHERE table_name='v_documentos_equipo_estado'),
    'rpc_ok', EXISTS(SELECT 1 FROM pg_proc WHERE proname='rpc_renovar_certificacion'),
    'docs_con_problema_30d', (SELECT COUNT(*) FROM v_documentos_equipo_estado WHERE dias_restantes <= 30),
    'por_tipo_30d', (SELECT jsonb_object_agg(tipo, n) FROM (
        SELECT tipo, COUNT(*) n FROM v_documentos_equipo_estado WHERE dias_restantes <= 30 GROUP BY tipo) s)
) AS resultado;

NOTIFY pgrst, 'reload schema';
