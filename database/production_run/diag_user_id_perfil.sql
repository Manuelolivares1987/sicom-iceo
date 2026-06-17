-- Verificacion final: las 3 funciones resuelven el perfil por usuarios_perfil.id
-- (no por user_id). ok=true significa corregida.
SELECT p.proname AS funcion,
       (position('WHERE id = v_user' IN pg_get_functiondef(p.oid)) > 0) AS ok_id,
       (pg_get_functiondef(p.oid) ILIKE '%where user_id%')             AS aun_buggy
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.prokind = 'f'
   AND p.proname IN (
       'rpc_taller_iniciar_ejecucion_ot',
       'rpc_registrar_recirculacion_combustible',
       'rpc_registrar_traspaso_combustible')
 ORDER BY 1;
