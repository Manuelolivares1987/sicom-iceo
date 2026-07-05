#!/usr/bin/env node
// Pruebas de control del ejecutor de migraciones (frente 4/5). Sale != 0 si falla.
// Requiere SUPABASE_DB_URL apuntando a un Postgres de prueba (local/CI).
import { spawnSync } from 'node:child_process'
import { writeFileSync, mkdtempSync, copyFileSync, appendFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { resolve, dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const MIGRATE = resolve(__dirname, 'db-migrate.mjs')
const M190 = resolve(__dirname, '../production_run/190_schema_migrations.sql')
const tmp = mkdtempSync(join(tmpdir(), 'dbmig-'))
let fallos = 0
function run(args) { return spawnSync('node', [MIGRATE, ...args], { encoding: 'utf8', env: process.env }) }
function assert(cond, msg) { if (cond) console.log('  ✓ ' + msg); else { console.error('  ✗ ' + msg); fallos++ } }

console.log('Pruebas del ejecutor de migraciones:')

// 1. Aplicar 190 (bootstrap del registro)
let r = run(['--apply', M190])
assert(r.status === 0 && /aplicada y registrada/.test(r.stdout), 'aplica 190 y registra')

// 2. Re-aplicar 190 (mismo hash) → omitido, exit 0
r = run(['--apply', M190])
assert(r.status === 0 && /ya aplicada \(mismo hash\)/.test(r.stdout), 're-aplicación con mismo hash se omite')

// 3. Drift: v190 con hash distinto → BLOQUEADO (exit != 0)
const drift = join(tmp, '190_drift.sql'); copyFileSync(M190, drift); appendFileSync(drift, '\n-- cambia el hash\n')
r = run(['--apply', drift])
assert(r.status !== 0 && /drift/i.test(r.stderr), 'bloquea archivo v190 con hash distinto (drift)')

// 4. Destructivo sin anotación → BLOQUEADO
const destr = join(tmp, '900_destructivo.sql'); writeFileSync(destr, 'DELETE FROM ordenes_trabajo;\n')
r = run(['--apply', destr])
assert(r.status !== 0 && /destructivo/i.test(r.stderr), 'bloquea DELETE sin WHERE')

// 5. GRANT a anon → BLOQUEADO
const grant = join(tmp, '901_grant.sql'); writeFileSync(grant, 'GRANT EXECUTE ON FUNCTION public.foo() TO anon;\n')
r = run(['--apply', grant])
assert(r.status !== 0 && /anon\/PUBLIC/i.test(r.stderr), 'bloquea GRANT a anon/PUBLIC')

// 6. Destructivo CON anotación → permitido
const ok = join(tmp, '902_ok.sql'); writeFileSync(ok, '-- destructivo-ok: prueba controlada\nCREATE TABLE IF NOT EXISTS _t902(x int); TRUNCATE _t902;\n')
r = run(['--apply', ok])
assert(r.status === 0 && /aplicada y registrada/.test(r.stdout), 'permite destructivo con anotación -- destructivo-ok')

// 7. Dry-run no aplica
const dry = join(tmp, '903_dry.sql'); writeFileSync(dry, 'CREATE TABLE IF NOT EXISTS _t903(x int);\n')
r = run(['--apply', dry, '--dry-run'])
assert(r.status === 0 && /DRY-RUN/.test(r.stdout), 'dry-run valida sin aplicar')

console.log(fallos === 0 ? '\n✓ TODAS las pruebas del ejecutor pasaron' : `\n✗ ${fallos} prueba(s) fallaron`)
process.exit(fallos === 0 ? 0 : 1)
