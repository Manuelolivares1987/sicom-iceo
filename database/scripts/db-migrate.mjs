#!/usr/bin/env node
// ============================================================================
// db-migrate.mjs — Ejecutor de migraciones con registro y hash (frente 4).
// ----------------------------------------------------------------------------
// - Registra cada aplicación en schema_migrations (version, sha256, ambiente,
//   commit, duración, éxito/error).
// - BLOQUEA re-ejecución de una versión ya aplicada con éxito.
// - BLOQUEA un archivo cuyo hash cambió después de aplicarse (drift).
// - Ejecuta en transacción; registra éxito y error; se detiene ante fallo.
// - Integra el verificador de SQL destructivo.
// - --dry-run, --status, --apply <archivo>. Detecta saltos y versiones dobles.
// - NO guarda credenciales.
//
// Uso:
//   node db-migrate.mjs --status
//   node db-migrate.mjs --apply database/production_run/190_schema_migrations.sql
//   node db-migrate.mjs --apply <archivo> --dry-run
// Env: DB_ENV (dev|staging|prod, default 'dev'); conexión desde .env.supabase-admin.local
// ============================================================================
import { readFileSync, existsSync, readdirSync } from 'node:fs'
import { resolve, dirname, basename } from 'node:path'
import { fileURLToPath } from 'node:url'
import { createHash } from 'node:crypto'
import { execSync } from 'node:child_process'
import pg from 'pg'
import dotenv from 'dotenv'

const __dirname = dirname(fileURLToPath(import.meta.url))
dotenv.config({ path: resolve(__dirname, '../../.env.supabase-admin.local') })
const PR = resolve(__dirname, '../production_run')
const args = process.argv.slice(2)
const has = (f) => args.includes(f)
const applyIdx = args.indexOf('--apply')
const applyFile = applyIdx >= 0 ? args[applyIdx + 1] : null
const dryRun = has('--dry-run')
const ENV = process.env.DB_ENV || 'dev'

function sha256(txt) { return createHash('sha256').update(txt.replace(/\r\n/g, '\n')).digest('hex') }
function gitCommit() { try { return execSync('git rev-parse HEAD', { cwd: __dirname }).toString().trim() } catch { return null } }
function versionOf(fn) { const m = /^(\d+)/.exec(basename(fn)); return m ? m[1] : basename(fn).replace(/\.sql$/, '') }

// ── Verificador de SQL destructivo (reusa reglas del checker existente) ──
function limpiar(sql) { return sql.replace(/--[^\n]*/g, ' ').replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/'(?:[^']|'')*'/g, "''") }
function esDestructivo(rawSql) {
  const excepcion = /--\s*destructivo-ok:/.test(rawSql)
  if (excepcion) return null
  const s = limpiar(rawSql).replace(/\s+/g, ' ')
  const hits = []
  for (const m of s.matchAll(/\bDELETE\s+FROM\s+([a-zA-Z_."]+)([^]*?)(?=(\bDELETE\s+FROM\b|$))/gi))
    if (!/\bWHERE\b/i.test(m[2]) && !/^pg_|^_/.test(m[1].replace(/"/g, ''))) hits.push(`DELETE sin WHERE ${m[1]}`)
  for (const m of s.matchAll(/\bUPDATE\s+([a-zA-Z_."]+)\s+SET\b([^]*?)(?=(\bUPDATE\s+[a-zA-Z_."]+\s+SET\b|$))/gi))
    if (!/\bWHERE\b/i.test(m[2])) hits.push(`UPDATE sin WHERE ${m[1]}`)
  if (/\bTRUNCATE\b/i.test(s)) hits.push('TRUNCATE')
  for (const m of s.matchAll(/\bDROP\s+TABLE\s+(IF\s+EXISTS\s+)?([a-zA-Z_."]+)/gi)) {
    const t = m[2].replace(/"/g, '')
    if (!/^_|^tmp_|^temp_|^smoke_|_tmp$|_temp$|_bkp|_backup|_seed$/i.test(t) && !/\bTEMP\b/i.test(s)) hits.push(`DROP TABLE ${t}`)
  }
  if (/\bDISABLE\s+ROW\s+LEVEL\s+SECURITY\b/i.test(s)) hits.push('DISABLE RLS')
  if (/\bGRANT\b[^;]*\bTO\b[^;]*\b(anon|PUBLIC)\b/i.test(s)) hits.push('GRANT a anon/PUBLIC')
  if (/USING\s*\(\s*true\s*\)\s*WITH\s+CHECK\s*\(\s*true\s*\)/i.test(s)) hits.push('policy escritura abierta USING(true) WITH CHECK(true)')
  // SECURITY DEFINER sin search_path (heurística por función)
  for (const m of s.matchAll(/SECURITY\s+DEFINER([\s\S]{0,400}?)(AS\s+\$)/gi))
    if (!/SET\s+search_path/i.test(m[1])) hits.push('SECURITY DEFINER sin search_path')
  return hits.length ? hits : null
}

function buildClient() {
  const url = (process.env.SUPABASE_DB_URL || '').trim()
  const local = /127\.0\.0\.1|localhost/.test(url) || process.env.DB_NO_SSL === '1'
  const ssl = local ? false : { rejectUnauthorized: false }
  if (url) return new pg.Client({ connectionString: url, ssl, statement_timeout: 600000 })
  return new pg.Client({ host: process.env.SUPABASE_DB_HOST, port: Number(process.env.SUPABASE_DB_PORT || 5432), user: process.env.SUPABASE_DB_USER, password: process.env.SUPABASE_DB_PASSWORD, database: process.env.SUPABASE_DB_NAME || 'postgres', ssl: { rejectUnauthorized: false }, statement_timeout: 600000 })
}

async function registryExists(c) {
  const r = await c.query(`SELECT to_regclass('public.schema_migrations') IS NOT NULL AS ok`)
  return r.rows[0].ok
}

// Detección de anomalías del directorio (saltos, versiones dobles)
function scanDir() {
  const files = readdirSync(PR).filter(f => /^\d+.*\.sql$/.test(f)).sort()
  const byVer = {}
  for (const f of files) { const v = versionOf(f); (byVer[v] = byVer[v] || []).push(f) }
  const dobles = Object.entries(byVer).filter(([, fs]) => fs.length > 1)
  const nums = Object.keys(byVer).filter(v => /^\d+$/.test(v)).map(Number).sort((a, b) => a - b)
  const saltos = []
  for (let i = 1; i < nums.length; i++) if (nums[i] - nums[i - 1] > 1) saltos.push(`${nums[i - 1]}→${nums[i]}`)
  return { files, byVer, dobles, saltos }
}

async function cmdStatus(c) {
  const { byVer, dobles, saltos } = scanDir()
  const reg = await registryExists(c)
  const applied = reg ? (await c.query(`SELECT version, sha256, success FROM public.schema_migrations`)).rows : []
  const appliedMap = Object.fromEntries(applied.map(r => [r.version, r]))
  console.log(`Ambiente: ${ENV} | registro: ${reg ? 'presente' : 'AUSENTE (aplicar 190 primero)'}`)
  console.log(`Migraciones en disco: ${Object.keys(byVer).length} | aplicadas: ${applied.filter(a => a.success).length}`)
  if (dobles.length) console.log(`⚠ VERSIONES DOBLES: ${dobles.map(([v, fs]) => v + ' (' + fs.join(', ') + ')').join(' | ')}`)
  if (saltos.length) console.log(`⚠ saltos de numeración: ${saltos.join(', ')}`)
  const pend = Object.keys(byVer).filter(v => !appliedMap[v]?.success)
  console.log(`Pendientes (${pend.length}): ${pend.slice(-12).join(', ')}${pend.length > 12 ? ' …' : ''}`)
}

const ADVISORY_KEY = 749185026  // clave fija para serializar ejecutores de migración

async function cmdApply(c, file) {
  const abs = resolve(process.cwd(), file)
  if (!existsSync(abs)) { console.error('no existe:', abs); process.exit(2) }
  const raw = readFileSync(abs, 'utf8')
  const version = versionOf(abs)
  const hash = sha256(raw)
  const fn = basename(abs)
  const esBootstrap = /CREATE\s+TABLE[^;]*\bschema_migrations\b/i.test(raw)

  // Exclusión concurrente: solo un ejecutor aplica migraciones a la vez.
  // Lock de sesión; se libera al cerrar la conexión (o al terminar el proceso).
  await c.query('SELECT pg_advisory_lock($1)', [ADVISORY_KEY])

  // Anomalías de directorio (aviso, no bloqueo salvo versión doble del mismo archivo objetivo)
  const { dobles } = scanDir()
  const doble = dobles.find(([v]) => v === version)
  if (doble) { console.error(`✗ BLOQUEADO: versión ${version} tiene múltiples archivos: ${doble[1].join(', ')}`); process.exit(1) }

  // Destructivo
  const destr = esDestructivo(raw)
  if (destr) { console.error(`✗ BLOQUEADO: SQL destructivo sin anotación en ${fn}:`); destr.forEach(h => console.error('   - ' + h)); console.error('   Agregar "-- destructivo-ok: <motivo>" si es intencional.'); process.exit(1) }

  const reg = await registryExists(c)
  // Bootstrap: si no existe el registro, SOLO se admite la migración que lo crea.
  if (!reg && !esBootstrap) {
    console.error('✗ BLOQUEADO: no existe schema_migrations. Aplica primero la migración bootstrap (190).')
    process.exit(1)
  }
  if (reg) {
    const prev = (await c.query(`SELECT sha256, success FROM public.schema_migrations WHERE version=$1`, [version])).rows[0]
    if (prev?.success && prev.sha256 === hash) { console.log(`↷ ${version} ya aplicada (mismo hash). No se re-ejecuta.`); return }
    if (prev?.success && prev.sha256 !== hash) { console.error(`✗ BLOQUEADO: ${version} ya aplicada con OTRO hash (drift).`); console.error(`   registrado=${prev.sha256.slice(0, 12)} actual=${hash.slice(0, 12)}`); process.exit(1) }
  }

  if (dryRun) { console.log(`DRY-RUN ${version} (${fn}) hash=${hash.slice(0, 12)} — validaciones OK, NO se aplica.`); return }

  const t0 = Date.now()
  const commit = gitCommit()
  try {
    await c.query('BEGIN')
    await c.query(raw)
    // Registrar dentro de la misma tx (si la tabla existe; para la 190 la crea el propio archivo)
    await c.query(`INSERT INTO public.schema_migrations(version,filename,sha256,applied_by,execution_ms,success,environment,git_commit)
       VALUES ($1,$2,$3,session_user,$4,true,$5,$6)
       ON CONFLICT (version) DO UPDATE SET filename=EXCLUDED.filename, sha256=EXCLUDED.sha256, applied_at=now(), applied_by=EXCLUDED.applied_by, execution_ms=EXCLUDED.execution_ms, success=true, error_message=NULL, environment=EXCLUDED.environment, git_commit=EXCLUDED.git_commit`,
      [version, fn, hash, Date.now() - t0, ENV, commit])
    await c.query('COMMIT')
    console.log(`✓ ${version} aplicada y registrada (${Date.now() - t0} ms, ${ENV}).`)
  } catch (e) {
    await c.query('ROLLBACK').catch(() => {})
    // Registrar el fallo fuera de la tx (best-effort)
    if (reg) await c.query(`INSERT INTO public.schema_migrations(version,filename,sha256,applied_by,execution_ms,success,error_message,environment,git_commit)
       VALUES ($1,$2,$3,session_user,$4,false,$5,$6,$7) ON CONFLICT (version) DO UPDATE SET success=false, error_message=EXCLUDED.error_message, applied_at=now()`,
      [version, fn, hash, Date.now() - t0, e.message.slice(0, 500), ENV, commit]).catch(() => {})
    console.error(`✗ ${version} FALLÓ: ${e.message}`); console.error('  DETENIDO (transacción revertida).'); process.exit(1)
  }
}

const c = buildClient()
await c.connect()
try {
  if (has('--status')) await cmdStatus(c)
  else if (applyFile) await cmdApply(c, applyFile)
  else console.log('Uso: --status | --apply <archivo> [--dry-run]')
} finally { await c.end() }
