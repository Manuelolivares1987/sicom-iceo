import pg from 'pg'; import dotenv from 'dotenv'; import { writeFileSync } from 'node:fs'
dotenv.config({ path: 'C:/Users/Manuel Olivares/sicom-iceo/.env.supabase-admin.local' })
const c = new pg.Client({ connectionString: (process.env.SUPABASE_DB_URL||'').trim(), ssl:{rejectUnauthorized:false} })
await c.connect()
const A = ['rpc_crear_ot','rpc_transicion_ot','rpc_cerrar_ot_supervisor','rpc_registrar_salida_inventario','rpc_cambiar_contrato_activo','rpc_confirmar_estado_dia','rpc_actualizar_metricas_activo','rpc_asignar_pauta','rpc_crear_auxiliar','rpc_generar_qr_activo','rpc_validar_sugerencia']
const rows = (await c.query(`
  SELECT p.proname, pg_get_function_identity_arguments(p.oid) idargs, pg_get_functiondef(p.oid) def,
         has_function_privilege('anon',p.oid,'EXECUTE') anon
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
  WHERE p.prosecdef AND p.prokind='f' AND p.prorettype <> 'trigger'::regtype
    AND has_function_privilege('anon', p.oid, 'EXECUTE')
    AND pg_get_functiondef(p.oid) ~* 'insert into|update .* set|delete from'
    AND pg_get_functiondef(p.oid) !~* 'auth\.uid\(\) is null|no autenticado|fn_user_rol|fn_tiene_permiso'
  ORDER BY p.proname`)).rows
let out = `-- ROLLBACK MIG189 v2 — EMERGENCIA. REABRE escritura anónima no validada.\n-- Restaura los cuerpos ORIGINALES (sin guard) del Grupo A y re-otorga anon a todas.\nBEGIN;\n\n`
for (const r of rows) {
  if (A.includes(r.proname)) out += r.def + ';\n'   // cuerpo original sin guard
  out += `GRANT EXECUTE ON FUNCTION public.${r.proname}(${r.idargs}) TO anon;\n`
}
out += `\nDO $$ BEGIN RAISE NOTICE 'ROLLBACK189 v2 aplicado (VULNERABILIDAD REABIERTA).'; END $$;\nCOMMIT;\n`
writeFileSync('C:/Users/Manuel Olivares/sicom-iceo/database/rollback/rollback_189_fase01.sql', out)
console.log('rollback_189 v2:', rows.length, 'grants,', A.length, 'cuerpos restaurados')
await c.end()
