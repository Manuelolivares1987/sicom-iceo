import pg from 'pg'; import dotenv from 'dotenv'; import { writeFileSync } from 'node:fs'
dotenv.config({ path: 'C:/Users/Manuel Olivares/sicom-iceo/.env.supabase-admin.local' })
const c = new pg.Client({ connectionString: (process.env.SUPABASE_DB_URL||'').trim(), ssl:{rejectUnauthorized:false} })
await c.connect()

const CRIT = ['activos','contratos','ordenes_trabajo','usuarios_perfil','rol_permisos_modulo','estado_diario_flota','combustible_estanques','combustible_kardex_valorizado','combustible_movimientos','no_conformidades','planes_mantenimiento','historico_estado_activo']
const P0_A = new Set(['rpc_crear_ot','rpc_transicion_ot','rpc_cerrar_ot_supervisor','rpc_registrar_salida_inventario','rpc_cambiar_contrato_activo','rpc_confirmar_estado_dia','rpc_actualizar_metricas_activo','rpc_asignar_pauta','rpc_crear_auxiliar','rpc_generar_qr_activo','rpc_validar_sugerencia'])
const P0_B = new Set(['generar_ots_preventivas','verificar_certificaciones','fn_auto_crear_planes_activo','fn_generar_nc_desde_checklist_ot','fn_generar_nc_desde_v3_ot','fn_reconciliar_estado_ficha_desde_matriz','fn_reconciliar_comercial_ficha_desde_matriz'])
const ALLOW = new Set(['rpc_guardar_checklist_publico','rpc_checklist_cliente_guardar'])
const P0_MIG185 = 'rpc_confirmar_cierre_diario'

const rows = (await c.query(`
  SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS args, pg_get_functiondef(p.oid) AS def
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
  WHERE p.prosecdef AND p.prokind='f' AND p.prorettype <> 'trigger'::regtype
    AND has_function_privilege('anon', p.oid, 'EXECUTE')
    AND pg_get_functiondef(p.oid) ~* 'insert into|update .* set|delete from'
    AND pg_get_functiondef(p.oid) !~* 'auth\\.uid\\(\\) is null|no autenticado|fn_user_rol|fn_tiene_permiso'
  ORDER BY p.proname`)).rows

function prio(r) {
  const d = r.def.toLowerCase()
  const crit = CRIT.some(t => new RegExp(`(insert into|update|delete from)\\s+(public\\.)?${t}\\b`).test(d))
  if (P0_A.has(r.proname) || P0_B.has(r.proname) || r.proname === P0_MIG185) return 'P0'
  if (crit) return 'P0'
  if (/insert into/.test(d)) return 'P1'
  return 'P2'
}
function plan(r) {
  if (r.proname === P0_MIG185) return { corr: 'MIG185', anonAfter: false, authAfter: true, guard: 'sí (MIG185)' }
  if (P0_A.has(r.proname)) return { corr: 'MIG189 GrupoA', anonAfter: false, authAfter: true, guard: 'sí (fail-closed)' }
  if (P0_B.has(r.proname)) return { corr: 'MIG189 GrupoB', anonAfter: false, authAfter: false, guard: 'no (interno: sin PostgREST)' }
  if (ALLOW.has(r.proname)) return { corr: 'allowlist QR', anonAfter: true, authAfter: true, guard: 'no (público QR)' }
  return { corr: 'MIG189 P1/P2', anonAfter: false, authAfter: true, guard: 'no (Fase 1)' }
}

const counts = { P0: 0, P1: 0, P2: 0 }
let md = '| Función | Firma | Prio | Corrección | anon antes | anon después | auth después | Guard interno |\n|---|---|---|---|---|---|---|---|\n'
const table = rows.map(r => {
  const p = prio(r); counts[p]++
  const pl = plan(r)
  md += `| \`${r.proname}\` | ${r.args.slice(0,40)||'()'} | ${p} | ${pl.corr} | sí | ${pl.anonAfter?'**sí**':'no'} | ${pl.authAfter?'sí':'no'} | ${pl.guard} |\n`
  return { fn: r.proname, prio: p, ...pl }
})
const closed = table.filter(t => !t.anonAfter).length
const allow = table.filter(t => t.anonAfter).length
md = `# Reconciliación de las 48 funciones de escritura anónima (catálogo prod)\n\n` +
  `Conteo real: **P0=${counts.P0}, P1=${counts.P1}, P2=${counts.P2}, total=${rows.length}**.\n` +
  `MIG185 cierra 1 P0; MIG189 cierra ${closed-1} (${table.filter(t=>t.corr==='MIG189 GrupoA').length} GrupoA + ${table.filter(t=>t.corr==='MIG189 GrupoB').length} GrupoB + ${table.filter(t=>t.corr==='MIG189 P1/P2').length} P1/P2); ` +
  `allowlist QR=${allow}. Cerradas a anon: **${closed} de ${rows.length}**.\n\n` + md
writeFileSync('C:/Users/Manuel Olivares/sicom-iceo/database/preprod/reconciliacion_48.md', md)
console.log(`P0=${counts.P0} P1=${counts.P1} P2=${counts.P2} total=${rows.length} | cerradas=${closed} allowlist=${allow}`)
console.log('GrupoA:', table.filter(t=>t.corr==='MIG189 GrupoA').length, 'GrupoB:', table.filter(t=>t.corr==='MIG189 GrupoB').length, 'P1P2:', table.filter(t=>t.corr==='MIG189 P1/P2').length, 'MIG185:', table.filter(t=>t.corr==='MIG185').length)
await c.end()
