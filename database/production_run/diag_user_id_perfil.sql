-- Reproduce el play del taller en una transaccion que se hace ROLLBACK.
-- Captura el mensaje y el CONTEXT (stack) del error real.
DO $diag$
DECLARE
  v_ot   uuid;
  v_user uuid;
  v_err  text;
  v_ctx  text;
BEGIN
  SELECT t.ot_id INTO v_ot
    FROM taller_plan_semanal_ots t
    JOIN taller_plan_semanal_dias d ON d.id = t.plan_dia_id
   WHERE t.estado_plan IN ('planificada','asignada','liberada','pausada')
   ORDER BY d.fecha DESC LIMIT 1;

  SELECT id INTO v_user FROM usuarios_perfil WHERE activo = true ORDER BY 1 LIMIT 1;

  RAISE NOTICE 'ot=% user=%', v_ot, v_user;

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user)::text, true);

  BEGIN
    PERFORM rpc_taller_iniciar_ejecucion_ot(v_ot, 'diag rollback');
    RAISE NOTICE 'SIN ERROR: la funcion corrio OK';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT, v_ctx = PG_EXCEPTION_CONTEXT;
    RAISE NOTICE 'ERROR_MSG: %', v_err;
    RAISE NOTICE 'ERROR_CTX: %', v_ctx;
  END;

  RAISE EXCEPTION 'rollback diagnostico (intencional, no persistir)';
END
$diag$;
