// Restaura el backup real de prod en un PostgreSQL 17 LOCAL (esquema public real,
// no stubs). Crea el andamiaje mínimo de Supabase (roles + auth) para que las
// funciones/policies reales restauren y ejecuten. Deja el server corriendo.
import { spawnSync } from 'node:child_process'
import { rmSync, mkdirSync, writeFileSync, existsSync } from 'node:fs'
import { resolve } from 'node:path'
import pg from 'pg'

const PGBIN = 'C:/Program Files/PostgreSQL/17/bin'
const DATADIR = resolve('./pg17data')
const PORT = 55434
const DUMP = 'C:/Users/Manuel Olivares/backups-fase0/sicom-prod-20260705.dump'
const run = (exe, args, opts={}) => spawnSync(resolve(PGBIN, exe), args, { encoding: 'utf8', ...opts })

// 1. Cluster limpio
try { run('pg_ctl.exe', ['-D', DATADIR, 'stop', '-m', 'immediate']) } catch {}
if (existsSync(DATADIR)) rmSync(DATADIR, { recursive: true, force: true })
mkdirSync(DATADIR, { recursive: true })
const pwfile = resolve('./pw.txt'); writeFileSync(pwfile, 'postgres')
let r = run('initdb.exe', ['-D', DATADIR, '-U', 'postgres', '--pwfile', pwfile, '--encoding=UTF8', '--locale=C'])
if (r.status !== 0) { console.error('initdb falló:', r.stderr); process.exit(1) }
rmSync(pwfile)

// 2. Start
r = run('pg_ctl.exe', ['-D', DATADIR, '-l', resolve('./pg17.log'), '-o', `-p ${PORT}`, '-w', 'start'])
if (r.status !== 0) { console.error('start falló:', r.stdout, r.stderr); process.exit(1) }
console.log('PG17 local iniciado en puerto', PORT)

const admin = new pg.Client({ host: '127.0.0.1', port: PORT, user: 'postgres', password: 'postgres', database: 'postgres' })
await admin.connect()

// 3. Andamiaje Supabase (roles + auth + esquemas de extensiones administradas)
await admin.query(`
  DO $$ BEGIN CREATE ROLE anon NOLOGIN NOINHERIT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
  DO $$ BEGIN CREATE ROLE authenticated NOLOGIN NOINHERIT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
  DO $$ BEGIN CREATE ROLE service_role NOLOGIN NOINHERIT BYPASSRLS; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
  DO $$ BEGIN CREATE ROLE authenticator LOGIN PASSWORD 'authpw' NOINHERIT; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
  GRANT anon, authenticated, service_role TO authenticator;
  GRANT anon, authenticated, service_role TO postgres;
  -- esquemas administrados que las funciones referencian (stubs de esquema, no de dominio)
  CREATE SCHEMA IF NOT EXISTS auth;
  CREATE SCHEMA IF NOT EXISTS extensions;
  CREATE SCHEMA IF NOT EXISTS graphql; CREATE SCHEMA IF NOT EXISTS graphql_public;
  CREATE SCHEMA IF NOT EXISTS realtime; CREATE SCHEMA IF NOT EXISTS storage;
  CREATE SCHEMA IF NOT EXISTS vault; CREATE SCHEMA IF NOT EXISTS net; CREATE SCHEMA IF NOT EXISTS cron;
  CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;
  -- auth.users mínima (FKs de public la referencian) + shims auth.uid/role
  CREATE TABLE IF NOT EXISTS auth.users (id uuid PRIMARY KEY, email varchar);
  CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
    SELECT NULLIF(current_setting('request.jwt.claims', true)::jsonb->>'sub','')::uuid $$;
  CREATE OR REPLACE FUNCTION auth.role() RETURNS text LANGUAGE sql STABLE AS $$
    SELECT current_setting('request.jwt.claims', true)::jsonb->>'role' $$;
  -- net/cron stubs (para cuerpos que los referencian; plpgsql no valida en CREATE)
  CREATE OR REPLACE FUNCTION net.http_post(url text, body jsonb DEFAULT '{}', params jsonb DEFAULT '{}', headers jsonb DEFAULT '{}', timeout_milliseconds int DEFAULT 5000) RETURNS bigint LANGUAGE sql AS $$ SELECT 0::bigint $$;
  GRANT USAGE ON SCHEMA auth, extensions, net, cron, vault TO anon, authenticated, service_role, authenticator;
`)
console.log('Andamiaje creado (roles, auth, esquemas administrados)')

await admin.end()

// 4. Restaurar SOLO el esquema public (real) — continúa ante errores de deps administradas
const url = { PGHOST: '127.0.0.1', PGPORT: String(PORT), PGUSER: 'postgres', PGPASSWORD: 'postgres', PGDATABASE: 'postgres' }
r = run('pg_restore.exe', ['--schema=public', '--no-owner', '--no-privileges', '--disable-triggers', '-d', 'postgres', DUMP],
        { env: { ...process.env, ...url }, maxBuffer: 64*1024*1024 })
const errLines = (r.stderr || '').split('\n').filter(l => /error:/i.test(l))
writeFileSync(resolve('./restore_errores.log'), r.stderr || '')
console.log(`pg_restore terminó (status ${r.status}). Errores registrados: ${errLines.length} (ver restore_errores.log)`)

// 5. Reporte
const a2 = new pg.Client({ host: '127.0.0.1', port: PORT, user: 'postgres', password: 'postgres', database: 'postgres' })
await a2.connect()
const q = async (s) => (await a2.query(s)).rows[0].c
console.log(JSON.stringify({
  tablas: await q(`SELECT count(*) c FROM pg_tables WHERE schemaname='public'`),
  funciones: await q(`SELECT count(*) c FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'`),
  triggers: await q(`SELECT count(*) c FROM pg_trigger WHERE NOT tgisinternal`),
  policies: await q(`SELECT count(*) c FROM pg_policies WHERE schemaname='public'`),
  vistas: await q(`SELECT count(*) c FROM pg_views WHERE schemaname='public'`),
  secuencias: await q(`SELECT count(*) c FROM pg_sequences WHERE schemaname='public'`),
  p0_presentes: await q(`SELECT count(*) c FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public' WHERE p.proname IN ('rpc_cambiar_contrato_activo','rpc_crear_ot','rpc_transicion_ot','rpc_cerrar_ot_supervisor','rpc_registrar_salida_inventario','rpc_confirmar_estado_dia','rpc_actualizar_metricas_activo','rpc_asignar_pauta','rpc_crear_auxiliar','rpc_generar_qr_activo','rpc_validar_sugerencia')`),
}, null, 2))
// resumen de errores por tipo
const tipos = {}
for (const l of errLines) { const m = /relation|function|type|schema|role|extension|permission/i.exec(l); const k = m?m[0].toLowerCase():'otro'; tipos[k]=(tipos[k]||0)+1 }
console.log('Errores de restore por categoría:', JSON.stringify(tipos))
await a2.end()
console.log('Server sigue corriendo en', PORT)
