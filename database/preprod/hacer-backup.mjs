// Backup real de prod en formato custom. NO imprime credenciales.
// Uso: node hacer-backup.mjs <archivo_salida.dump>
import { spawnSync } from 'node:child_process'
import { statSync, createReadStream } from 'node:fs'
import { createHash } from 'node:crypto'
import dotenv from 'dotenv'
dotenv.config({ path: 'C:/Users/Manuel Olivares/sicom-iceo/.env.supabase-admin.local' })

const BIN = 'C:/Program Files/PostgreSQL/17/bin/pg_dump.exe'
const out = process.argv[2]
if (!out) { console.error('falta archivo salida'); process.exit(2) }

const url = new URL((process.env.SUPABASE_DB_URL || '').trim())
const env = {
  ...process.env,
  PGHOST: url.hostname,
  PGPORT: url.port || '5432',
  PGUSER: decodeURIComponent(url.username),
  PGPASSWORD: decodeURIComponent(url.password),
  PGDATABASE: url.pathname.replace(/^\//, '') || 'postgres',
  PGSSLMODE: 'require',
}
console.log(`Conectando a host ${env.PGHOST.slice(0,12)}… db ${env.PGDATABASE} (credenciales NO impresas)`)

const t0 = Date.now()
const r = spawnSync(BIN, ['-Fc', '--no-owner', '--no-privileges', '-f', out], { env, stdio: ['ignore', 'inherit', 'inherit'] })
const secs = ((Date.now() - t0) / 1000).toFixed(1)
if (r.status !== 0) { console.error('pg_dump falló, status', r.status); process.exit(1) }

const size = statSync(out).size
const hash = createHash('sha256')
await new Promise((res, rej) => createReadStream(out).on('data', d => hash.update(d)).on('end', res).on('error', rej))
console.log(JSON.stringify({ archivo: out, bytes: size, mb: (size/1048576).toFixed(1), duracion_s: Number(secs), sha256: hash.digest('hex') }, null, 2))
