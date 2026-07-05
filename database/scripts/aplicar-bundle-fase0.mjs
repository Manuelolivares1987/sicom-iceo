#!/usr/bin/env node
// ============================================================================
// aplicar-bundle-fase0.mjs — Despliegue REANUDABLE del bundle Fase 0
// ----------------------------------------------------------------------------
// El bundle (185→186→187→189) NO es atómico: son archivos y transacciones
// separadas. Este orquestador:
//   - Aplica cada migración en orden, en su propia transacción (BEGIN/COMMIT).
//   - Tras cada una ejecuta una POSTVALIDACIÓN; si falla, SE DETIENE.
//   - Registra el estado en database/scripts/.fase0_deploy_state.json.
//   - Al reanudar, SALTA las ya aplicadas y validadas.
//   - NUNCA hace rollback automático (un rollback reabre acceso anónimo).
//     Ante falla no destructiva: detener, corregir hacia adelante y reanudar.
//   - MIG188 NO forma parte del bundle (regularización aparte, desautorizada).
//
// Uso:
//   node aplicar-bundle-fase0.mjs --dry-run   # muestra el plan y valida conexión
//   node aplicar-bundle-fase0.mjs             # aplica (pide confirmación por env)
//   APLICAR_FASE0=si node aplicar-bundle-fase0.mjs
// ============================================================================
import { readFileSync, existsSync, writeFileSync } from 'node:fs'
import { resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import pg from 'pg'
import dotenv from 'dotenv'

const __dirname = dirname(fileURLToPath(import.meta.url))
dotenv.config({ path: resolve(__dirname, '../../.env.supabase-admin.local') })
const STATE = resolve(__dirname, '.fase0_deploy_state.json')
const PR = resolve(__dirname, '../production_run')
const dryRun = process.argv.includes('--dry-run')

// Bundle en orden + su postvalidación (todas SELECT/booleanas).
const BUNDLE = [
  { id: '185', file: '185_seguridad_cierre_diario.sql', check: `SELECT
      NOT has_function_privilege('anon','public.rpc_confirmar_cierre_diario(date,jsonb)','EXECUTE')
      AND (SELECT rowsecurity FROM pg_tables WHERE tablename='estado_diario_flota')
      AND EXISTS (SELECT 1 FROM pg_proc WHERE proname='fn_tiene_permiso_modulo') AS ok` },
  { id: '186', file: '186_reporte_fiabilidad_autenticado.sql', check: `SELECT
      NOT has_function_privilege('anon','public.fn_reporte_fiabilidad_publico(date,date)','EXECUTE') AS ok` },
  { id: '187', file: '187_combustible_valor_stock_en_salidas.sql', check: `SELECT
      (pg_get_functiondef(p.oid) LIKE '%valor_total_stock = v_valor_post%') AS ok
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
      WHERE p.proname='rpc_registrar_salida_combustible_valorizada'` },
  { id: '189', file: '189_fase01_revocar_anon_escritura.sql', check: `SELECT
      (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
        WHERE p.prosecdef AND p.prokind='f' AND p.prorettype <> 'trigger'::regtype
          AND has_function_privilege('anon', p.oid, 'EXECUTE')
          AND pg_get_functiondef(p.oid) ~* 'insert into|update .* set|delete from'
          AND pg_get_functiondef(p.oid) !~* 'auth.uid\\(\\) is null|no autenticado|fn_user_rol|fn_tiene_permiso'
          AND p.proname NOT IN ('rpc_guardar_checklist_publico','rpc_checklist_cliente_guardar')) = 0
      AND has_function_privilege('service_role','public.rpc_ingestar_gps_batch(text,jsonb)','EXECUTE') AS ok` },
]

const state = existsSync(STATE) ? JSON.parse(readFileSync(STATE, 'utf8')) : { aplicadas: [] }
const client = new pg.Client({ connectionString: (process.env.SUPABASE_DB_URL || '').trim(), ssl: { rejectUnauthorized: false }, statement_timeout: 600_000 })

function estadoActual() {
  const done = state.aplicadas
  if (done.length === 0) return 'Ninguna aplicada'
  return 'Aplicadas: ' + done.join(', ')
}

console.log('═'.repeat(70))
console.log('Bundle Fase 0 · estado:', estadoActual())
console.log('Pendientes:', BUNDLE.filter(m => !state.aplicadas.includes(m.id)).map(m => m.id).join(', ') || '(ninguna)')
console.log('═'.repeat(70))
if (dryRun) { console.log('DRY-RUN: no se aplica nada.'); process.exit(0) }
if (process.env.APLICAR_FASE0 !== 'si') {
  console.error('Protección: exporta APLICAR_FASE0=si para aplicar en producción.')
  console.error('(Requiere autorización explícita del gate; ver docs/auditoria/gate-preproduccion-fase-0.md)')
  process.exit(2)
}

await client.connect()
try {
  for (const mig of BUNDLE) {
    if (state.aplicadas.includes(mig.id)) { console.log(`↷ MIG${mig.id} ya aplicada, se salta.`); continue }
    const sql = readFileSync(resolve(PR, mig.file), 'utf8')
    console.log(`\n▶ Aplicando MIG${mig.id} …`)
    await client.query('BEGIN')
    try {
      await client.query(sql)
      await client.query('COMMIT')
    } catch (e) {
      await client.query('ROLLBACK')  // rollback de ESTA migración (la propia tx), no del bundle
      console.error(`✗ MIG${mig.id} falló y se revirtió su transacción: ${e.message}`)
      console.error('  DETENIDO. Corrige hacia adelante y reanuda; NO se revierten las anteriores ni se reabre anon.')
      process.exit(1)
    }
    // Postvalidación fuera de la tx (estado ya commiteado).
    const r = await client.query(mig.check)
    if (r.rows[0]?.ok !== true) {
      console.error(`✗ Postvalidación de MIG${mig.id} FALLÓ (ok=${r.rows[0]?.ok}). DETENIDO.`)
      console.error('  La migración quedó aplicada pero no validada; investigar antes de continuar.')
      process.exit(1)
    }
    state.aplicadas.push(mig.id)
    writeFileSync(STATE, JSON.stringify(state, null, 2))
    console.log(`✓ MIG${mig.id} aplicada y postvalidada.`)
  }
  console.log('\n✓ Bundle Fase 0 completo. MIG188 queda pendiente (ventana separada, autorización aparte).')
} finally {
  await client.end()
}
