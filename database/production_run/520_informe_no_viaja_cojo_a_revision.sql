-- ============================================================================
-- MIG520 · El informe técnico no viaja cojo a revisión
-- ============================================================================
--
-- LO QUE VIO MANUEL (04-09-2026)
-- En la OT-202608-00009, al aprobar el informe técnico IT-202608-00005:
-- «Ocurrió un error». El error real (tapado por la UI, arreglada en el mismo
-- PR) era: «Faltan campos mínimos (trabajo_realizado_resumen, estado_salida)».
--
-- POR QUÉ
-- rpc_aprobar_informe_intervencion exige el resumen del trabajo y el estado
-- de salida (MIG191), pero rpc_enviar_informe_revision NO los pide: el
-- informe llega vacío a la bandeja del aprobador, que no puede editarlo (en
-- pendiente_revision solo se observa o aprueba) — un callejón: para
-- completarlo hay que devolverlo con una observación.
--
-- QUÉ SE HACE
-- El envío a revisión valida los MISMOS campos mínimos que la aprobación,
-- con un mensaje que dice qué falta. El que redacta lo completa cuando
-- todavía puede editar; el aprobador recibe informes aprobables.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.rpc_enviar_informe_revision(p_informe_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE v_row public.informes_intervencion;
BEGIN
    IF NOT public.fn_ii_puede('edit') THEN RAISE EXCEPTION 'No autorizado' USING ERRCODE='42501'; END IF;
    SELECT * INTO v_row FROM public.informes_intervencion WHERE id=p_informe_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Informe no existe' USING ERRCODE='P0002'; END IF;
    IF v_row.estado NOT IN ('borrador','observado') THEN RAISE EXCEPTION 'Estado % no permite envío a revisión', v_row.estado USING ERRCODE='42501'; END IF;
    -- [MIG520] Lo que la aprobación va a exigir se exige ACÁ, donde todavía
    -- se puede editar. Si no, el informe llega cojo a una bandeja donde nadie
    -- puede completarlo.
    IF COALESCE(v_row.trabajo_realizado_resumen,'')='' OR COALESCE(v_row.estado_salida,'')='' THEN
        RAISE EXCEPTION 'Antes de enviar a revisión completa: %',
            trim(both ', ' from
                 CASE WHEN COALESCE(v_row.trabajo_realizado_resumen,'')='' THEN 'el resumen del trabajo realizado, ' ELSE '' END ||
                 CASE WHEN COALESCE(v_row.estado_salida,'')='' THEN 'el estado de salida del equipo' ELSE '' END)
            USING ERRCODE='P0001';
    END IF;
    UPDATE public.informes_intervencion SET estado='pendiente_revision', updated_at=now() WHERE id=p_informe_id;
END; $fn$;

-- ── Verificación con rollback: el informe cojo real ya no viaja ─────────────
DO $mig$
DECLARE v_admin UUID; v_inf UUID := '42dddc1d-2f56-4120-a947-3a02ce40ee6a';
BEGIN
    SELECT id INTO v_admin FROM usuarios_perfil WHERE rol='administrador' AND activo LIMIT 1;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, TRUE);

    -- El informe atascado sigue en pendiente_revision: se simula devolverlo y
    -- reenviarlo vacío — debe rebotar con el mensaje claro.
    BEGIN
        PERFORM rpc_observar_informe(v_inf, 'Prueba MIG520: falta completar el informe');
        PERFORM rpc_enviar_informe_revision(v_inf);
        RAISE EXCEPTION 'FALLO_REAL: el informe vacío viajó a revisión igual';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE 'FALLO_REAL%' THEN
            RAISE EXCEPTION '%', SQLERRM;
        ELSIF SQLERRM LIKE 'Antes de enviar a revisión completa%' THEN
            RAISE NOTICE 'prueba OK (revertida): «%»', SQLERRM;
        ELSE
            RAISE EXCEPTION 'FALLO: rebotó con otro error: %', SQLERRM;
        END IF;
    END;
    -- El bloque de excepción revirtió el observar de prueba: el informe sigue
    -- tal cual estaba (pendiente_revision).
    IF (SELECT estado FROM informes_intervencion WHERE id = v_inf) <> 'pendiente_revision' THEN
        RAISE EXCEPTION 'FALLO: la prueba dejó el informe en otro estado';
    END IF;
    RAISE NOTICE 'MIG520 OK · el informe técnico no viaja cojo a revisión';
END
$mig$;

COMMIT;
