-- ============================================================================
-- MIG524 · El administrador aprueba aunque haya creado el informe
-- ============================================================================
--
-- LO QUE PIDIÓ MANUEL (04-09-2026)
-- «Como administrador quiero tener la potestad de hacer todo.»
--
-- Venía de chocar con la segregación de MIG191: «el aprobador no puede ser
-- el ejecutor/creador del informe». La regla es sana para los roles del
-- taller (quien redacta no se autoaprueba), pero al ADMINISTRADOR no lo
-- puede dejar sin salida: es la última llave del sistema. La aprobación
-- queda registrada con su nombre igual (aprobado_por), así que la
-- trazabilidad no se pierde — se sabe exactamente quién aprobó qué.
--
-- La segregación se mantiene intacta para jefe_mantenimiento y
-- subgerente_operaciones.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.rpc_aprobar_informe_intervencion(p_informe_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE v_row public.informes_intervencion; v_snap JSONB;
BEGIN
    IF NOT public.fn_ii_puede('approve') THEN RAISE EXCEPTION 'No autorizado para aprobar' USING ERRCODE='42501'; END IF;
    SELECT * INTO v_row FROM public.informes_intervencion WHERE id=p_informe_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Informe no existe' USING ERRCODE='P0002'; END IF;
    IF v_row.estado <> 'pendiente_revision' THEN RAISE EXCEPTION 'Solo aprobable en pendiente_revision (estado %)', v_row.estado USING ERRCODE='42501'; END IF;
    -- Segregación: el aprobador no puede ser el ejecutor principal ni el
    -- creador. [MIG524] El ADMINISTRADOR queda exento: es la última llave y
    -- no puede quedar sin salida — su nombre queda registrado igual.
    IF (auth.uid() = v_row.ejecutor_principal_id OR auth.uid() = v_row.elaborado_por)
       AND public.fn_user_rol() <> 'administrador' THEN
        RAISE EXCEPTION 'El aprobador no puede ser el ejecutor/creador del informe' USING ERRCODE='42501';
    END IF;
    -- Campos mínimos
    IF COALESCE(v_row.trabajo_realizado_resumen,'')='' OR COALESCE(v_row.estado_salida,'')='' THEN
        RAISE EXCEPTION 'Faltan campos mínimos (trabajo_realizado_resumen, estado_salida)' USING ERRCODE='P0001';
    END IF;
    -- Congela snapshot desde fuentes oficiales (equipo, contrato, lecturas, costos, responsables)
    SELECT jsonb_build_object(
        'congelado_at', now(),
        'activo', (SELECT to_jsonb(a) FROM public.activos a WHERE a.id=v_row.activo_id),
        'ot', (SELECT jsonb_build_object('folio',o.folio,'tipo',o.tipo,'estado',o.estado,'contrato_id',o.contrato_id) FROM public.ordenes_trabajo o WHERE o.id=v_row.ot_id),
        'materiales_total', (SELECT COALESCE(SUM(costo_total),0) FROM public.informe_intervencion_materiales WHERE informe_id=p_informe_id),
        'manoobra_total', (SELECT COALESCE(SUM(costo_total_snapshot),0) FROM public.informe_intervencion_manoobra WHERE informe_id=p_informe_id),
        'trabajos', (SELECT jsonb_agg(to_jsonb(t)) FROM public.informe_intervencion_trabajos t WHERE t.informe_id=p_informe_id),
        'pruebas', (SELECT jsonb_agg(to_jsonb(pr)) FROM public.informe_intervencion_pruebas pr WHERE pr.informe_id=p_informe_id)
    ) INTO v_snap;
    UPDATE public.informes_intervencion
       SET estado='aprobado', aprobado_por=auth.uid(), aprobado_at=now(), snapshot=v_snap, updated_at=now()
     WHERE id=p_informe_id;
END; $fn$;

-- ── Verificación: un admin que creó el informe SÍ aprueba (con rollback) ────
DO $mig$
DECLARE v_admin UUID; v_ot RECORD; v_id UUID; v_est TEXT;
BEGIN
    SELECT id INTO v_admin FROM usuarios_perfil WHERE rol='administrador' AND activo LIMIT 1;
    -- Una OT sin informes: (ot_id, version) es único y la 00009 ya tiene el suyo.
    SELECT ot.id, ot.activo_id INTO v_ot FROM ordenes_trabajo ot
     WHERE NOT EXISTS (SELECT 1 FROM informes_intervencion i WHERE i.ot_id = ot.id)
     LIMIT 1;

    BEGIN
        -- Informe de prueba creado POR el mismo admin que va a aprobar.
        INSERT INTO informes_intervencion(
            folio, ot_id, activo_id, version, es_version_vigente, estado,
            tipo_intervencion, fecha_ingreso, trabajo_realizado_resumen, estado_salida,
            ejecutor_principal_id, elaborado_por)
        -- version 1: con v>1 el CHECK chk_ii_anterior_si_v_gt1 exige la anterior.
        VALUES ('IT-TEST-MIG524', v_ot.id, v_ot.activo_id, 1, false, 'pendiente_revision',
                'preventivo', NOW(), 'prueba MIG524', 'Operativo',
                NULL, v_admin)
        RETURNING id INTO v_id;

        PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, TRUE);
        PERFORM rpc_aprobar_informe_intervencion(v_id);
        SELECT estado INTO v_est FROM informes_intervencion WHERE id = v_id;
        IF v_est <> 'aprobado' THEN
            RAISE EXCEPTION 'FALLO_REAL: quedó en % y no aprobado', v_est;
        END IF;
        RAISE EXCEPTION 'ROLLBACK_MARKER ok';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE 'ROLLBACK_MARKER%' THEN
            RAISE NOTICE 'prueba OK (revertida): el admin creador aprueba sin bloqueo';
        ELSE
            RAISE EXCEPTION 'FALLO: %', SQLERRM;
        END IF;
    END;

    IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                    WHERE n.nspname='public' AND p.proname='rpc_aprobar_informe_intervencion'
                      AND p.prosrc LIKE '%MIG524%') THEN
        RAISE EXCEPTION 'FALLO: la excepción de admin no quedó escrita';
    END IF;
    RAISE NOTICE 'MIG524 OK · el administrador aprueba siempre; la segregación sigue para el resto';
END
$mig$;

COMMIT;
