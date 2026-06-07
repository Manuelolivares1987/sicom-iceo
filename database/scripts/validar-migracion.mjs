#!/usr/bin/env node
// ============================================================================
// validar-migracion.mjs
// Valida un SQL en SECO: BEGIN -> ejecuta -> ROLLBACK SIEMPRE.
// No persiste NADA. Sirve para verificar sintaxis y dependencias contra la BD
// real sin aplicar cambios. Uso: node validar-migracion.mjs <ruta_sql>
// ============================================================================
import { readFileSync, existsSync } from 'node:fs'
import { resolve, basename, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import pg from 'pg'
import dotenv from 'dotenv'

const __dirname = dirname(fileURLToPath(import.meta.url))
const ENV_PATH = resolve(__dirname, '../../.env.supabase-admin.local')
if (!existsSync(ENV_PATH)) { console.error(`ERROR: no existe ${ENV_PATH}`); process.exit(2) }
dotenv.config({ path: ENV_PATH })

function buildClientConfig() {
  const url = (process.env.SUPABASE_DB_URL || '').trim()
  if (url) return { connectionString: url, ssl: { rejectUnauthorized: false }, statement_timeout: 600_000 }
  const host = process.env.SUPABASE_DB_HOST, user = process.env.SUPABASE_DB_USER, pass = process.env.SUPABASE_DB_PASSWORD
  if (host && user && pass) return {
    host, port: Number(process.env.SUPABASE_DB_PORT || 5432), user, password: pass,
    database: process.env.SUPABASE_DB_NAME || 'postgres', ssl: { rejectUnauthorized: false }, statement_timeout: 600_000,
  }
  console.error('ERROR: credenciales no configuradas en .env.supabase-admin.local'); process.exit(2)
}

const sqlPath = process.argv.slice(2).find((a) => !a.startsWith('--'))
if (!sqlPath) { console.error('Uso: node validar-migracion.mjs <ruta_sql>'); process.exit(2) }
const abs = resolve(process.cwd(), sqlPath)
if (!existsSync(abs)) { console.error(`ERROR: no existe ${abs}`); process.exit(2) }
const sql = readFileSync(abs, 'utf8')

console.log('═'.repeat(72))
console.log(`VALIDACION EN SECO (BEGIN/ROLLBACK): ${basename(abs)}`)
console.log('═'.repeat(72))

const client = new pg.Client(buildClientConfig())
client.on('notice', (m) => console.log(`  [${m.severity || 'NOTICE'}] ${m.message}`))
const t0 = Date.now()
let failed = false
try {
  await client.connect()
  console.log('✓ conectado')
  await client.query('BEGIN')
  console.log('▶ BEGIN')
  const res = await client.query(sql)
  console.log(`▶ SQL ejecutado OK en ${Date.now() - t0} ms`)
  if (res && res.rows && res.rows.length) {
    console.log('─ ultima SELECT (validacion) ─')
    console.log(JSON.stringify(res.rows, null, 2))
  }
} catch (err) {
  failed = true
  console.error('✗ ERROR de validacion:')
  console.error(`  mensaje:  ${err.message}`)
  if (err.code) console.error(`  code:     ${err.code}`)
  if (err.detail) console.error(`  detail:   ${err.detail}`)
  if (err.hint) console.error(`  hint:     ${err.hint}`)
  if (err.where) console.error(`  where:    ${err.where}`)
  if (err.position) console.error(`  position: ${err.position}`)
} finally {
  try { await client.query('ROLLBACK'); console.log('▶ ROLLBACK (no se persiste nada)') } catch {}
  try { await client.end() } catch {}
}
console.log('═'.repeat(72))
console.log(failed ? '✗ VALIDACION FALLIDA' : '✓ VALIDACION OK — la migracion es aplicable')
process.exit(failed ? 1 : 0)
