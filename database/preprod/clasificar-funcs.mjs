// Clasifica (solo lectura) las funciones public SECURITY DEFINER ejecutables por
// anon que ESCRIBEN y NO validan sesión/rol. Sección 7 del gate.
import pg from 'pg'
import dotenv from 'dotenv'
import { writeFileSync } from 'node:fs'
dotenv.config({ path: 'C:/Users/Manuel Olivares/sicom-iceo/.env.supabase-admin.local' })
const c = new pg.Client({ connectionString: (process.env.SUPABASE_DB_URL||'').trim(), ssl:{rejectUnauthorized:false} })
await c.connect()

const CRIT = ['activos','contratos','ordenes_trabajo','usuarios_perfil','rol_permisos_modulo',
  'estado_diario_flota','combustible_estanques','combustible_kardex_valorizado','combustible_movimientos',
  'no_conformidades','planes_mantenimiento','historico_estado_activo','pagos','abastecimiento']

const rows = (await c.query(`
  SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS args,
         pg_get_functiondef(p.oid) AS def
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
  WHERE p.prosecdef AND p.prokind='f' AND p.prorettype <> 'trigger'::regtype
    AND has_function_privilege('anon', p.oid, 'EXECUTE')
    AND pg_get_functiondef(p.oid) ~* 'insert into|update .* set|delete from'
    AND pg_get_functiondef(p.oid) !~* 'auth\\.uid\\(\\) is null|no autenticado|fn_user_rol|fn_tiene_permiso'
`)).rows

function classify(def) {
  const d = def.toLowerCase()
  const escribeCrit = CRIT.filter(t => new RegExp(`(insert into|update|delete from)\\s+(public\\.)?${t}\\b`).test(d))
  const borra = /delete from/.test(d)
  const soloTrigHelper = /trigger/.test(d) && !/insert into|update|delete/.test(d)
  // ¿la llama pg_cron/trigger interno? heurística: nombre sugiere job interno
  let prio, motivo
  if (escribeCrit.length && borra) { prio='P0'; motivo='DELETE/UPDATE sobre tabla crítica' }
  else if (escribeCrit.length) { prio='P0'; motivo='escribe tabla crítica: '+escribeCrit.join(',') }
  else if (/insert into/.test(d)) { prio='P1'; motivo='INSERT ilimitado (no crítico)' }
  else { prio='P2'; motivo='escritura de impacto limitado' }
  return { prio, motivo, escribeCrit }
}

const out = rows.map(r => {
  const { prio, motivo, escribeCrit } = classify(r.def)
  // ¿realmente sin ninguna barrera? algunas validan por otras vías (p.ej. token)
  const tieneOtraBarrera = /x-cron-secret|p_token|request\.header|current_setting\('request/i.test(r.def)
  return { fn: r.proname, args: r.args.slice(0,60), prio: tieneOtraBarrera ? 'P3' : prio,
           motivo: tieneOtraBarrera ? 'valida por token/header (revisar)' : motivo, critTables: escribeCrit.join('|') }
}).sort((a,b)=> a.prio.localeCompare(b.prio) || a.fn.localeCompare(b.fn))

const byPrio = out.reduce((m,r)=>{ (m[r.prio]=m[r.prio]||[]).push(r); return m }, {})
console.log('Total sin validación:', out.length)
for (const p of ['P0','P1','P2','P3']) {
  console.log(`\n### ${p} (${(byPrio[p]||[]).length})`)
  for (const r of (byPrio[p]||[])) console.log(`  ${r.fn}  [${r.critTables||'-'}]  ${r.motivo}`)
}
writeFileSync('clasificacion_funcs.json', JSON.stringify(out,null,2))
await c.end()
