#!/usr/bin/env node
// ============================================================================
// psql-cli.mjs
// ----------------------------------------------------------------------------
// REPL/one-shot para ejecutar SQL ad-hoc contra Supabase. Util para diagnostico
// rapido (ver columnas, contar filas, validar resultados de migracion).
//
// Uso one-shot:
//   node psql-cli.mjs "SELECT * FROM combustible_recirculaciones LIMIT 5"
//   node psql-cli.mjs -f query.sql
//
// Uso REPL (vacio):
//   node psql-cli.mjs
//     sicom> SELECT count(*) FROM combustible_estanques;
//     sicom> \q
// ============================================================================

import { readFileSync, existsSync } from 'node:fs'
import { resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { createInterface } from 'node:readline'
import pg from 'pg'
import dotenv from 'dotenv'

const __dirname = dirname(fileURLToPath(import.meta.url))
const ENV_PATH  = resolve(__dirname, '../../.env.supabase-admin.local')

if (!existsSync(ENV_PATH)) {
  console.error(`ERROR: no existe ${ENV_PATH}`); process.exit(2)
}
dotenv.config({ path: ENV_PATH })

function buildClientConfig() {
  const url = (process.env.SUPABASE_DB_URL || '').trim()
  if (url) {
    if (url.includes('[YOUR-PASSWORD]')) {
      console.error('ERROR: SUPABASE_DB_URL aun tiene "[YOUR-PASSWORD]" literal.')
      process.exit(2)
    }
    return { connectionString: url, ssl: { rejectUnauthorized: false } }
  }
  const host = process.env.SUPABASE_DB_HOST
  const user = process.env.SUPABASE_DB_USER
  const pass = process.env.SUPABASE_DB_PASSWORD
  if (host && user && pass) {
    return {
      host,
      port: Number(process.env.SUPABASE_DB_PORT || 5432),
      user,
      password: pass,
      database: process.env.SUPABASE_DB_NAME || 'postgres',
      ssl: { rejectUnauthorized: false },
    }
  }
  console.error('ERROR: ni SUPABASE_DB_URL ni SUPABASE_DB_HOST/USER/PASSWORD configurados.')
  process.exit(2)
}
const clientConfig = buildClientConfig()

const args = process.argv.slice(2)
let oneShotSql = null
if (args[0] === '-f' && args[1]) {
  oneShotSql = readFileSync(resolve(process.cwd(), args[1]), 'utf8')
} else if (args.length > 0) {
  oneShotSql = args.join(' ')
}

const client = new pg.Client(clientConfig)
client.on('notice', (m) => console.log(`[${m.severity || 'NOTICE'}] ${m.message}`))

await client.connect()

async function run(sql) {
  const t0 = Date.now()
  try {
    const r = await client.query(sql)
    const ms = Date.now() - t0
    if (Array.isArray(r)) {
      r.forEach((q, i) => printResult(q, `[${i + 1}/${r.length}]`))
    } else {
      printResult(r)
    }
    console.log(`(${ms} ms)\n`)
  } catch (e) {
    console.error(`✗ ${e.message}`)
    if (e.position) console.error(`  position: ${e.position}`)
    if (e.hint) console.error(`  hint: ${e.hint}`)
  }
}

function printResult(r, prefix = '') {
  if (!r) return
  if (r.rows && r.rows.length > 0) {
    console.log(prefix, JSON.stringify(r.rows, null, 2))
  } else {
    console.log(prefix, `${r.command} OK (${r.rowCount ?? 0} filas)`)
  }
}

if (oneShotSql) {
  await run(oneShotSql)
  await client.end()
  process.exit(0)
}

const rl = createInterface({ input: process.stdin, output: process.stdout })
const ask = () => rl.question('sicom> ', async (line) => {
  const t = line.trim()
  if (t === '\\q' || t === 'exit' || t === 'quit') {
    await client.end(); rl.close(); return
  }
  if (t === '') { ask(); return }
  await run(t)
  ask()
})
ask()
