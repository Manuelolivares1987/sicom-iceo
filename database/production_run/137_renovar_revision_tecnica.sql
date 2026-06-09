-- ============================================================================
-- SICOM-ICEO | 137 — Renovar Revisión Técnica (subir doc + nuevo vencimiento)
-- ============================================================================
-- Cuando se hace la inspección de RT (desde el Plan Semanal), se registra la
-- RT renovada: documento nuevo + nueva fecha de vencimiento. Inserta una fila
-- en certificaciones (tipo='revision_tecnica'); el trigger existente recalcula
-- el estado (vigente/por_vencer/vencido) y el equipo sale de "RT por vencer".
--
-- Incluye policy de storage para subir el documento (bucket 'documentos',
-- prefijo 'rt/') por usuarios autenticados.
-- IDEMPOTENTE.
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
        CASE WHEN p_fecha_vencimiento <= CURRENT_DATE THEN 'vencido'
             WHEN p_fecha_vencimiento <= CURRENT_DATE + 30 THEN 'por_vencer'
             ELSE 'vigente' END,
        p_archivo_url, true,
        CASE WHEN p_ot_id IS NOT NULL THEN 'Renovada vía OT inspección RT' ELSE NULL END,
        v_user
    ) RETURNING id INTO v_id;

    RETURN jsonb_build_object('certificacion_id', v_id, 'activo_id', p_activo_id,
                              'fecha_vencimiento', p_fecha_vencimiento);
END $$;
GRANT EXECUTE ON FUNCTION rpc_renovar_revision_tecnica TO authenticated;

-- Storage: subir el documento de RT bajo 'documentos/rt/' (autenticados).
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables
               WHERE table_schema='storage' AND table_name='objects') THEN
        BEGIN
            DROP POLICY IF EXISTS "storage_rt_auth_insert" ON storage.objects;
            CREATE POLICY "storage_rt_auth_insert" ON storage.objects
                FOR INSERT TO authenticated
                WITH CHECK (bucket_id = 'documentos'
                           AND (storage.foldername(name))[1] = 'rt');
        EXCEPTION WHEN insufficient_privilege OR others THEN
            RAISE NOTICE 'No se pudo crear policy de storage rt (permiso).';
        END;
    END IF;
END $$;

SELECT (SELECT count(*) FROM pg_proc WHERE proname='rpc_renovar_revision_tecnica') AS rpc,
       (SELECT count(*) FROM pg_policies WHERE policyname='storage_rt_auth_insert') AS storage_policy;
