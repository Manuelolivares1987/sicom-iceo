-- ============================================================================
-- 93_fix_traspaso_usuarios_perfil_columna.sql
-- ----------------------------------------------------------------------------
-- BUG: rpc_registrar_traspaso_combustible (MIG76) busca el perfil del operador
-- con  SELECT id FROM usuarios_perfil WHERE user_id = v_user_id  pero la tabla
-- usuarios_perfil enlaza al usuario por su PK 'id' (= auth.uid()), NO existe
-- columna 'user_id'. Resultado: error 42703 "column user_id does not exist"
-- en TODO traspaso.
--
-- FIX: reemplaza 'WHERE user_id = v_user_id' por 'WHERE id = v_user_id' en el
-- cuerpo de la funcion (trae la definicion viva y la re-aplica corregida, para
-- no transcribir las ~250 lineas a mano). Idempotente.
-- ============================================================================

DO $mig93$
DECLARE
    v_def TEXT;
BEGIN
    SELECT pg_get_functiondef(p.oid) INTO v_def
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE p.proname = 'rpc_registrar_traspaso_combustible'
       AND n.nspname = 'public'
     LIMIT 1;

    IF v_def IS NULL THEN
        RAISE EXCEPTION 'rpc_registrar_traspaso_combustible no existe';
    END IF;

    IF position('WHERE user_id = v_user_id' IN v_def) = 0 THEN
        RAISE NOTICE 'Patron no encontrado (ya corregido?). Sin cambios.';
        RETURN;
    END IF;

    v_def := replace(v_def, 'WHERE user_id = v_user_id', 'WHERE id = v_user_id');
    EXECUTE v_def;
    RAISE NOTICE 'rpc_registrar_traspaso_combustible corregida (usuarios_perfil.id).';
END
$mig93$;
