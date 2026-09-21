-- ============================================================================
-- MIG570 · La foto del documento del ingreso de bodega se puede subir
-- ============================================================================
--
-- LO QUE PASÓ (21-09-2026)
-- Bodega Coquimbo quiso ingresar la factura 505471 de Pernostock (50 kg de
-- trapo, OC Softland 14259) adjuntando el PDF, y no entró nada: la pantalla
-- sube primero el archivo a documentos/bodega-ingreso/… y recién después
-- llama a rpc_ingreso_bodega_simple. El bucket `documentos` tiene una
-- política INSERT por carpeta (certificaciones, rt, enex-…) y MIG566 nunca
-- agregó la de bodega-ingreso → «new row violates row-level security policy
-- for table "objects"» y el ingreso completo se abortaba.
--
-- Sin foto el ingreso sí funcionaba (verificado como Gustavo con rollback:
-- el RPC da folio).
--
-- LA CORRECCIÓN
-- Política INSERT para la carpeta bodega-ingreso, con los mismos roles que
-- deja entrar rpc_ingreso_bodega_simple.
-- ============================================================================

BEGIN;

DROP POLICY IF EXISTS storage_bodega_ingreso_insert ON storage.objects;
CREATE POLICY storage_bodega_ingreso_insert ON storage.objects
    FOR INSERT TO authenticated
    WITH CHECK (
        bucket_id = 'documentos'
        AND (storage.foldername(name))[1] = 'bodega-ingreso'
        AND public.fn_user_rol() IN ('administrador','subgerente_operaciones','jefe_mantenimiento',
                                     'supervisor','operador_abastecimiento','bodeguero')
    );

-- ── Verificación como Gustavo (bodeguero Coquimbo) ─────────────────────────
DO $ver$
DECLARE v_u UUID; v_msg TEXT;
BEGIN
    SELECT id INTO v_u FROM usuarios_perfil WHERE email = 'bodegacoq@pillado.cl';
    IF v_u IS NULL THEN RAISE EXCEPTION 'bodegacoq@pillado.cl no existe'; END IF;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_u, 'role', 'authenticated')::text, true);
    SET LOCAL ROLE authenticated;
    BEGIN
        INSERT INTO storage.objects (bucket_id, name, owner)
        VALUES ('documentos', 'bodega-ingreso/_verificacion_mig570/prueba.pdf', v_u);
        RAISE EXCEPTION 'deshacer';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        IF v_msg <> 'deshacer' THEN RAISE EXCEPTION 'FALLO: el bodeguero sigue sin poder subir: %', v_msg; END IF;
    END;
    RESET ROLE;
    PERFORM set_config('request.jwt.claims', '', true);
    RAISE NOTICE 'OK: el bodeguero sube la foto del documento a bodega-ingreso/';
END $ver$;

COMMIT;
