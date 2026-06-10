-- ============================================================================
-- SICOM-ICEO | 145 — Foto en la No Conformidad ad-hoc (faena del mecánico)
-- ----------------------------------------------------------------------------
-- Toda NC que el mecánico registra a mano debe llevar foto. Se agrega p_foto a
-- fn_registrar_nc_recepcion (guarda en no_conformidades.foto_url) + policy de
-- storage para subir la foto al bucket 'evidencias-verificacion' bajo 'nc/'.
-- IDEMPOTENTE.
-- ============================================================================

DROP FUNCTION IF EXISTS fn_registrar_nc_recepcion(UUID, TEXT, VARCHAR, UUID, VARCHAR, TEXT);

CREATE OR REPLACE FUNCTION fn_registrar_nc_recepcion(
    p_activo_id    UUID,
    p_descripcion  TEXT,
    p_severidad    VARCHAR DEFAULT 'media',
    p_informe_id   UUID DEFAULT NULL,
    p_sistema      VARCHAR DEFAULT NULL,
    p_observacion  TEXT DEFAULT NULL,
    p_foto         TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE v_user UUID := auth.uid(); v_id UUID;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado.'; END IF;
    IF p_severidad NOT IN ('baja','media','alta','critica') THEN
        RAISE EXCEPTION 'Severidad invalida: %', p_severidad; END IF;
    INSERT INTO no_conformidades (
        activo_id, tipo, descripcion, fecha_evento, severidad, origen,
        informe_recepcion_id, accion_correctiva, foto_url,
        estado_planificacion, registrada_por, created_by
    ) VALUES (
        p_activo_id, 'otra', p_descripcion, CURRENT_DATE, p_severidad, 'recepcion_adhoc',
        p_informe_id, p_observacion, p_foto,
        'registrada', v_user, v_user
    ) RETURNING id INTO v_id;
    RETURN jsonb_build_object('nc_id', v_id);
END $$;
GRANT EXECUTE ON FUNCTION fn_registrar_nc_recepcion TO authenticated;

-- Storage: subir foto de NC bajo 'evidencias-verificacion/nc/' (autenticados).
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='storage' AND table_name='objects') THEN
        BEGIN
            DROP POLICY IF EXISTS "storage_nc_auth_insert" ON storage.objects;
            CREATE POLICY "storage_nc_auth_insert" ON storage.objects
                FOR INSERT TO authenticated
                WITH CHECK (bucket_id = 'evidencias-verificacion' AND (storage.foldername(name))[1] = 'nc');
        EXCEPTION WHEN insufficient_privilege OR others THEN
            RAISE NOTICE 'No se pudo crear policy storage nc (permiso).';
        END;
    END IF;
END $$;

SELECT (SELECT count(*) FROM pg_proc WHERE proname='fn_registrar_nc_recepcion'
        AND pronargs=7) AS rpc_7args;
