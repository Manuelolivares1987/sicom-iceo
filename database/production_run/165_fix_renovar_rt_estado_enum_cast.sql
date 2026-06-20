-- ============================================================================
-- SICOM-ICEO | 165 — FIX: rpc_renovar_revision_tecnica fallaba al renovar RT
-- ============================================================================
-- Síntoma: al usar «Renovar RT» (Plan Semanal de Taller) salía el toast genérico
-- "Error al renovar la RT" para CUALQUIER rol permitido.
--
-- Causa: la columna certificaciones.estado es enum (estado_documento_enum). El
-- INSERT calculaba el estado con un CASE que devuelve TEXT, y Postgres NO castea
-- implícitamente text -> enum en ese contexto:
--   ERROR: column "estado" is of type estado_documento_enum but expression is of
--          type text
-- (El front mostraba el toast genérico porque el PostgrestError no es un Error de
--  JS, así que el mensaje real quedaba oculto.)
--
-- Fix: castear el resultado del CASE a ::estado_documento_enum. Igual que la
-- migración 137 pero con el cast. IDEMPOTENTE (CREATE OR REPLACE).
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_renovar_revision_tecnica(
    p_activo_id         UUID,
    p_fecha_emision     DATE,
    p_fecha_vencimiento DATE,
    p_archivo_url       TEXT DEFAULT NULL,
    p_numero            VARCHAR DEFAULT NULL,
    p_entidad           VARCHAR DEFAULT NULL,
    p_ot_id             UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_rol  TEXT := fn_user_rol();
    v_id   UUID;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado.'; END IF;
    IF v_rol NOT IN ('administrador','supervisor','subgerente_operaciones','jefe_operaciones',
                     'jefe_mantenimiento','planificador','auditor_calidad') THEN
        RAISE EXCEPTION 'Sin permiso para renovar revisión técnica. Rol: %', v_rol;
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

    INSERT INTO certificaciones (
        activo_id, tipo, numero_certificado, entidad_certificadora,
        fecha_emision, fecha_vencimiento, estado, archivo_url, bloqueante,
        notas, created_by
    ) VALUES (
        p_activo_id, 'revision_tecnica', p_numero, p_entidad,
        p_fecha_emision, p_fecha_vencimiento,
        (CASE WHEN p_fecha_vencimiento <= CURRENT_DATE THEN 'vencido'
              WHEN p_fecha_vencimiento <= CURRENT_DATE + 30 THEN 'por_vencer'
              ELSE 'vigente' END)::estado_documento_enum,
        p_archivo_url, true,
        CASE WHEN p_ot_id IS NOT NULL THEN 'Renovada vía OT inspección RT' ELSE NULL END,
        v_user
    ) RETURNING id INTO v_id;

    RETURN jsonb_build_object('certificacion_id', v_id, 'activo_id', p_activo_id,
                              'fecha_vencimiento', p_fecha_vencimiento);
END $$;
GRANT EXECUTE ON FUNCTION rpc_renovar_revision_tecnica TO authenticated;

SELECT (SELECT count(*) FROM pg_proc WHERE proname='rpc_renovar_revision_tecnica') AS rpc_ok;
