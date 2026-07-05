#!/usr/bin/env node
// Pruebas de control del ejecutor de migraciones (frentes 4/5) incl. bootstrap,
// advisory lock (concurrencia) y registro tras error. Sale != 0 si algo falla.
// Requiere SUPABASE_DB_URL a un Postgres de prueba (local/CI).
import { spawnSync } from 'node:child_process'
import { writeFileSync, mkdtempSync, copyFileSync, appendFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { resolve, dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import pg from 'pg'

const __dirname = dirname(fileURLToPath(import.meta.url))
const MIGRATE = resolve(__dirname, 'db-migrate.mjs')
const M190 = resolve(__dirname, '../production_run/190_schema_migrations.sql')
const tmp = mkdtempSync(join(tmpdir(), 'dbmig-'))
const URL = (process.env.SUPABASE_DB_URL || '').trim()
const local = /127\.0\.0\.1|localhost/.test(URL)
let fallos = 0
function run(args) { return spawnSync('node', [MIGRATE, ...args], { encoding: 'utf8', env: process.env }) }
function runAsync(args) { return new Promise((res) => { const p = spawnSync('node', [MIGRATE, ...args], { encoding: 'utf8', env: process.env }); res(p) }) }
function ok(cond, msg) { if (cond) console.log('  ✓ ' + msg); else { console.error('  ✗ ' + msg); fallos++ } }
async function db() { const c = new pg.Client({ connectionString: URL, ssl: local ? false : { rejectUnauthorized: false } }); await c.connect(); return c }
async function reset() { const c = await db(); await c.query('DROP TABLE IF EXISTS public.schema_migrations, public.backup_ejecuciones CASCADE'); await c.end() }
async function rows() { const c = await db(); const r = await c.query(`SELECT to_regclass('public.schema_migrations') t`); if (!r.rows[0].t) { await c.end(); return -1 } const n = (await c.query('SELECT count(*)::int c FROM public.schema_migrations')).rows[0].c; await c.end(); return n }

console.log('Pruebas del ejecutor de migraciones (bootstrap + concurrencia + registro):')

// T1: base SIN schema_migrations
await reset()
ok((await rows()) === -1, 'T1 base sin schema_migrations')

// T0: sin registro, una migración NO-bootstrap → bloqueada
const noBoot = join(tmp, '999_no_boot.sql'); writeFileSync(noBoot, 'CREATE TABLE IF NOT EXISTS _x999(x int);\n')
let r = run(['--apply', noBoot])
ok(r.status !== 0 && /bootstrap/i.test(r.stderr), 'T0 sin registro, migración no-bootstrap es bloqueada (exige 190)')

// T2: aplicación inicial de 190 (bootstrap)
r = run(['--apply', M190])
ok(r.status === 0 && /aplicada y registrada/.test(r.stdout), 'T2 aplica 190 (bootstrap)')

// T3: --status
r = run(['--status'])
ok(r.status === 0 && /registro: presente/.test(r.stdout), 'T3 status muestra registro presente')

// Verificar registro coherente (version/hash/commit/ambiente/duración)
{ const c = await db(); const m = (await c.query(`SELECT * FROM public.schema_migrations WHERE version='190'`)).rows[0]; await c.end()
  ok(m && m.sha256 && m.git_commit !== undefined && m.environment && Number(m.execution_ms) >= 0 && m.success === true, 'T2b registro con version/hash/commit/ambiente/duración') }

// T4: reintento hash idéntico → omitido
r = run(['--apply', M190])
ok(r.status === 0 && /ya aplicada \(mismo hash\)/.test(r.stdout), 'T4 reintento con hash idéntico se omite')

// T5: reintento hash distinto → rechazado
const drift = join(tmp, '190_drift.sql'); copyFileSync(M190, drift); appendFileSync(drift, '\n-- cambia hash\n')
r = run(['--apply', drift])
ok(r.status !== 0 && /drift/i.test(r.stderr), 'T5 reintento con hash distinto es rechazado (drift)')

// T6/T7: error durante migración → registrado como fallo, coherente
const bad = join(tmp, '800_bad.sql'); writeFileSync(bad, 'CREATE TABLE _t800(x int);\nSELECT 1/0;\n')
r = run(['--apply', bad])
{ const c = await db(); const m = (await c.query(`SELECT success, error_message FROM public.schema_migrations WHERE version='800'`)).rows[0]
  const t800 = (await c.query(`SELECT to_regclass('public._t800') t`)).rows[0].t; await c.end()
  ok(r.status !== 0, 'T6 error durante migración retorna != 0')
  ok(m && m.success === false && m.error_message, 'T7 fallo registrado (success=false + causa)')
  ok(t800 === null, 'T7b la tabla de la migración fallida fue revertida (rollback)') }

// T8: concurrencia — dos ejecutores aplicando 190 en base FRESCA
await reset()
const [a, b] = await Promise.all([runAsync(['--apply', M190]), runAsync(['--apply', M190])])
const nrows = await rows()
const exitosos = [a, b].filter(p => p.status === 0).length
ok(nrows === 1 && exitosos === 2, `T8 dos ejecutores concurrentes → 1 registro, ambos exit 0 (filas=${nrows}, exit0=${exitosos})`)

console.log(fallos === 0 ? '\n✓ TODAS las pruebas del ejecutor pasaron' : `\n✗ ${fallos} prueba(s) fallaron`)
process.exit(fallos === 0 ? 0 : 1)
