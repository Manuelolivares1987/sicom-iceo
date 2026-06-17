-- ============================================================================
-- SICOM-ICEO | 154 — Fix rpc_registrar_recirculacion_combustible: columna user_id
-- ============================================================================
-- Mismo bug que MIG 93 (traspaso) y MIG 153 (iniciar ejecucion taller):
-- rpc_registrar_recirculacion_combustible (MIG 75) resuelve el perfil del
-- operador con  SELECT id FROM usuarios_perfil WHERE user_id = v_user_id  pero
-- usuarios_perfil enlaza al usuario por su PK `id` (= auth.uid()); NO existe
-- columna user_id. Resultado: error 42703 "column user_id does not exist" en
-- TODA recirculacion de combustible.
--
-- FIX: trae la definicion viva de la funcion y reemplaza
--   'WHERE user_id = v_user_id' -> 'WHERE id = v_user_id'
-- (no se transcriben las ~150 lineas). Idempotente.
-- ============================================================================

DO $mig154$
DECLARE
    v_def TEXT;
BEGIN
    SELECT pg_get_functiondef(p.oid) INTO v_def
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE p.proname = 'rpc_registrar_recirculacion_combustible'
       AND n.nspname = 'public'
       AND p.prokind = 'f'
     LIMIT 1;

    IF v_def IS NULL THEN
        RAISE EXCEPTION 'rpc_registrar_recirculacion_combustible no existe';
    END IF;

    IF position('WHERE user_id = v_user_id' IN v_def) = 0 THEN
        RAISE NOTICE 'Patron no encontrado (ya corregido?). Sin cambios.';
        RETURN;
    END IF;

    v_def := replace(v_def, 'WHERE user_id = v_user_id', 'WHERE id = v_user_id');
    EXECUTE v_def;
    RAISE NOTICE 'rpc_registrar_recirculacion_combustible corregida (usuarios_perfil.id).';
END
$mig154$;
