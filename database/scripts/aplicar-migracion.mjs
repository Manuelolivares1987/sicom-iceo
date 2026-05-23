#!/usr/bin/env node
// ============================================================================
// aplicar-migracion.mjs
// ----------------------------------------------------------------------------
// Aplica un archivo SQL contra Supabase via connection string directa.
//
// Caracteristicas:
//   - Envuelve el SQL en BEGIN/COMMIT (rollback automatico si falla)
//   - Captura y muestra NOTICE / RAISE / errores en consola
//   - Imprime el resultado de la ultima SELECT (validacion)
//   - Modo --dry-run que solo conecta y valida sin ejecutar
//   - Modo --no-tx para migraciones que no soportan transaccion (ej: CONCURRENTLY)
//
// Uso:
//   node aplicar-migracion.mjs <ruta_sql> [--dry-run] [--no-tx]
//
// Ejemplo:
//   node aplicar-migracion.mjs ../production_run/75_combustible_recirculacion.sql
// ============================================================================

import { readFileSync, existsSync } from 'node:fs'
import { resolve, basename } from 'node:path'
import { fileURLToPath } from 'node:url'
import { dirname } from 'node:path'
import pg from 'pg'
import dotenv from 'dotenv'

const __dirname = dirname(fileURLToPath(import.meta.url))
const ENV_PATH  = resolve(__dirname, '../../.env.supabase-admin.local')

// Cargar credenciales
if (!existsSync(ENV_PATH)) {
  console.error(`ERROR: no existe ${ENV_PATH}`)
  console.error('Crea ese archivo con SUPABASE_DB_URL=postgresql://...')
  process.exit(2)
}
dotenv.config({ path: ENV_PATH })

// Permite dos formas de conexion:
//   A) SUPABASE_DB_URL = postgresql://user:pass@host:port/db   (URI completa)
//   B) Variables separadas: SUPABASE_DB_HOST + _PORT + _USER + _PASSWORD + _NAME
//      -> evita url-encoding de passwords con simbolos especiales
function buildClientConfig() {
  const url = (process.env.SUPABASE_DB_URL || '').trim()
  if (url) {
    if (url.includes('[YOUR-PASSWORD]')) {
      console.error('ERROR: SUPABASE_DB_URL aun tiene "[YOUR-PASSWORD]" literal.')
      console.error('       Reemplaza ese texto por tu password real de la BD.')
      process.exit(2)
    }
    return { connectionString: url, ssl: { rejectUnauthorized: false }, statement_timeout: 600_000 }
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
      statement_timeout: 600_000,
    }
  }
  console.error('ERROR: ni SUPABASE_DB_URL ni SUPABASE_DB_HOST/USER/PASSWORD configurados.')
  console.error('       Edita .env.supabase-admin.local')
  process.exit(2)
}
const clientConfig = buildClientConfig()

// Parseo args
const args = process.argv.slice(2)
const sqlPath = args.find((a) => !a.startsWith('--'))
const dryRun  = args.includes('--dry-run')
const noTx    = args.includes('--no-tx')

if (!sqlPath) {
  console.error('Uso: node aplicar-migracion.mjs <ruta_sql> [--dry-run] [--no-tx]')
  process.exit(2)
}

const absSqlPath = resolve(process.cwd(), sqlPath)
if (!existsSync(absSqlPath)) {
  console.error(`ERROR: archivo SQL no existe: ${absSqlPath}`)
  process.exit(2)
}

const sql = readFileSync(absSqlPath, 'utf8')
const sqlBytes = Buffer.byteLength(sql, 'utf8')
const fileName = basename(absSqlPath)

console.log('═'.repeat(72))
console.log(`Archivo:    ${fileName}`)
console.log(`Tamano:     ${sqlBytes.toLocaleString()} bytes`)
console.log(`Transaccion: ${noTx ? 'NO (--no-tx)' : 'SI'}`)
console.log(`Modo:       ${dryRun ? 'DRY-RUN (no ejecuta)' : 'APLICAR'}`)
console.log('═'.repeat(72))

const client = new pg.Client(clientConfig)

// Captura RAISE NOTICE y los muestra en consola
client.on('notice', (msg) => {
  const tag = msg.severity ? `[${msg.severity}]` : '[NOTICE]'
  console.log(`  ${tag} ${msg.message}`)
})

let lastResult = null
const t0 = Date.now()

try {
  await client.connect()
  console.log('✓ conectado a Postgres')

  if (dryRun) {
    console.log('DRY-RUN: NO se ejecuta SQL. Conexion OK.')
    await client.end()
    process.exit(0)
  }

  if (!noTx) {
    await client.query('BEGIN')
    console.log('▶ BEGIN')
  }

  console.log('▶ ejecutando SQL...')
  // pg.Client.query con un string ejecuta el batch completo y devuelve la
  // ultima respuesta. Para multi-statement SQL esto vale.
  lastResult = await client.query(sql)

  if (!noTx) {
    await client.query('COMMIT')
    console.log('▶ COMMIT')
  }

  console.log('═'.repeat(72))
  console.log(`✓ APLICADO OK en ${Date.now() - t0} ms`)

  // Mostrar resultado de la ultima SELECT (validacion) si hubo
  if (lastResult && lastResult.rows && lastResult.rows.length > 0) {
    console.log('─ Resultado ultima SELECT ─'.padEnd(72, '─'))
    console.log(JSON.stringify(lastResult.rows, null, 2))
  }

} catch (err) {
  console.error('═'.repeat(72))
  console.error('✗ ERROR aplicando migracion:')
  console.error(`  mensaje: ${err.message}`)
  if (err.code) console.error(`  code:    ${err.code}`)
  if (err.detail) console.error(`  detail:  ${err.detail}`)
  if (err.hint) console.error(`  hint:    ${err.hint}`)
  if (err.where) console.error(`  where:   ${err.where}`)
  if (err.position) console.error(`  position:${err.position}`)
  if (err.internalQuery) console.error(`  query:   ${err.internalQuery}`)

  if (!noTx) {
    try { await client.query('ROLLBACK'); console.error('▶ ROLLBACK ejecutado') }
    catch { /* ignore */ }
  } else {
    console.error('  (sin transaccion: cambios parciales pueden haberse aplicado)')
  }

  await client.end()
  process.exit(1)
} finally {
  try { await client.end() } catch { /* ignore */ }
}
