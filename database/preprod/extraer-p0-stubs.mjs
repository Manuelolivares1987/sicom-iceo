// Emite STUBS (firma exacta, cuerpo trivial) para las 46 funciones que toca
// MIG189, + grants anon/authenticated (reproduce estado vulnerable). Para Grupo A
// el 189 hará CREATE OR REPLACE con el cuerpo REAL guardado; los stubs solo
// garantizan que las firmas existan para REVOKE/GRANT y que el guard sea testeable.
import pg from 'pg'; import dotenv from 'dotenv'; import { writeFileSync } from 'node:fs'
dotenv.config({ path: 'C:/Users/Manuel Olivares/sicom-iceo/.env.supabase-admin.local' })
const c = new pg.Client({ connectionString: (process.env.SUPABASE_DB_URL||'').trim(), ssl:{rejectUnauthorized:false} })
await c.connect()

let rows = (await c.query(`
  SELECT p.proname,
         pg_get_function_identity_arguments(p.oid) AS idargs,
         pg_get_function_arguments(p.oid) AS args,   -- con defaults, para CREATE
         pg_get_function_result(p.oid) AS ret,
         has_function_privilege('anon',p.oid,'EXECUTE') AS anon,
         has_function_privilege('authenticated',p.oid,'EXECUTE') AS auth
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
  WHERE p.prosecdef AND p.prokind='f' AND p.prorettype <> 'trigger'::regtype
    AND has_function_privilege('anon', p.oid, 'EXECUTE')
    AND pg_get_functiondef(p.oid) ~* 'insert into|update .* set|delete from'
    AND pg_get_functiondef(p.oid) !~* 'auth\\.uid\\(\\) is null|no autenticado|fn_user_rol|fn_tiene_permiso'
  ORDER BY p.proname`)).rows

const P0 = new Set(['rpc_crear_ot','rpc_transicion_ot','rpc_cerrar_ot_supervisor','rpc_registrar_salida_inventario','rpc_cambiar_contrato_activo','rpc_confirmar_estado_dia','rpc_actualizar_metricas_activo','rpc_asignar_pauta','rpc_crear_auxiliar','rpc_generar_qr_activo','rpc_validar_sugerencia','generar_ots_preventivas','verificar_certificaciones','fn_auto_crear_planes_activo','fn_generar_nc_desde_checklist_ot','fn_generar_nc_desde_v3_ot','fn_reconciliar_estado_ficha_desde_matriz','fn_reconciliar_comercial_ficha_desde_matriz'])
const rowsAll = rows
rows = rows.filter(r => P0.has(r.proname))
let sql = '-- STUBS de las 18 funciones P0 que toca MIG189 (firma exacta). SOLO preprod.\nSET client_min_messages=warning;\n\n'
// tipos enum/compuestos usados en firmas que quizá no existan en preprod → los creamos laxos
// Volcar TODOS los enums public de prod (garantiza que cualquier tipo referenciado exista).
const allEnums = (await c.query(`
  SELECT ty.typname, string_agg(quote_literal(e.enumlabel), ',' ORDER BY e.enumsortorder) v
  FROM pg_type ty JOIN pg_enum e ON e.enumtypid=ty.oid
  JOIN pg_namespace n ON n.oid=ty.typnamespace AND n.nspname='public'
  GROUP BY ty.typname ORDER BY ty.typname`)).rows
let typesNeeded = new Set(allEnums.map(e => e.typname))
for (const e of allEnums) {
  sql += `DO $$ BEGIN CREATE TYPE ${e.typname} AS ENUM (${e.v}); EXCEPTION WHEN duplicate_object THEN NULL; END $$;\n`
}
sql += '\n'

for (const r of rows) {
  const ret = r.ret.startsWith('TABLE') ? r.ret : r.ret  // RETURNS TABLE(...) es válido
  sql += `CREATE OR REPLACE FUNCTION public.${r.proname}(${r.idargs})\n RETURNS ${ret}\n LANGUAGE plpgsql SECURITY DEFINER AS $stub$ BEGIN RAISE EXCEPTION 'stub preprod'; END $stub$;\n`
  sql += `GRANT EXECUTE ON FUNCTION public.${r.proname}(${r.idargs}) TO anon, authenticated;\n`
}
writeFileSync('preprod_p0_stubs.sql', sql)
console.log('stubs:', rows.length, 'tipos enum laxos:', typesNeeded.size)
await c.end()
