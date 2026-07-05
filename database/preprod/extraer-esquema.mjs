// Extrae de PROD (solo lectura) el esquema pre-185 necesario para preprod.
// NO extrae datos de filas (solo estructura + definiciones de funciones).
import pg from 'pg'
import dotenv from 'dotenv'
import { writeFileSync } from 'node:fs'
dotenv.config({ path: 'C:/Users/Manuel Olivares/sicom-iceo/.env.supabase-admin.local' })

const c = new pg.Client({ connectionString: (process.env.SUPABASE_DB_URL||'').trim(), ssl:{rejectUnauthorized:false} })
await c.connect()

const TABLES = [
  'estado_diario_flota','activos','contratos','combustible_estanques',
  'combustible_kardex_valorizado','combustible_traspasos','usuarios_perfil',
  'rol_permisos_modulo','marcas','modelos','vehiculos_autorizados_externos',
  'combustible_despachos_sellos','combustible_recirculaciones','historico_contrato_activo'
]
const FUNCS = [
  'fn_user_rol','rpc_confirmar_cierre_diario','fn_propuesta_cierre_diario',
  'rpc_registrar_salida_combustible_valorizada','rpc_registrar_traspaso_combustible',
  'rpc_registrar_despacho_combustible_con_sellos','fn_reporte_fiabilidad_publico',
  'fn_generar_folio_salida_combustible'
]

let out = '-- PREPROD BASE (pre-MIG185) extraído de prod ' + '\n'
out += 'SET client_min_messages = warning;\n\n'
let outFn = '-- PREPROD FUNCIONES (pre-MIG185) extraídas de prod\nSET client_min_messages = warning;\n\n'

// Enums usados
const enums = await c.query(`
  SELECT t.typname, string_agg(quote_literal(e.enumlabel), ',' ORDER BY e.enumsortorder) AS labels
  FROM pg_type t JOIN pg_enum e ON e.enumtypid=t.oid
  JOIN pg_namespace n ON n.oid=t.typnamespace AND n.nspname='public'
  WHERE t.typname IN ('estado_comercial_enum','estado_activo_enum','rol_usuario_enum')
  GROUP BY t.typname`)
for (const r of enums.rows) out += `DO $$ BEGIN CREATE TYPE ${r.typname} AS ENUM (${r.labels}); EXCEPTION WHEN duplicate_object THEN NULL; END $$;\n`
out += '\n'

// Tablas: DDL exacta por pg_catalog
for (const t of TABLES) {
  const cols = await c.query(`
    SELECT a.attname,
           format_type(a.atttypid, a.atttypmod) AS typ,
           a.attnotnull,
           a.attgenerated,
           pg_get_expr(d.adbin, d.adrelid) AS def
    FROM pg_attribute a
    LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
    JOIN pg_class c ON c.oid=a.attrelid
    JOIN pg_namespace n ON n.oid=c.relnamespace AND n.nspname='public'
    WHERE c.relname=$1 AND a.attnum>0 AND NOT a.attisdropped
    ORDER BY a.attnum`, [t])
  if (cols.rows.length===0) { out += `-- (tabla ${t} no encontrada)\n`; continue }
  const colDefs = cols.rows.map(r => {
    let s = `  "${r.attname}" ${r.typ}`
    if (r.attgenerated === 's') { s += ` GENERATED ALWAYS AS (${r.def}) STORED`; return s }
    if (r.def) {
      const seq = /nextval\('([^']+)'/.exec(r.def)
      if (seq) out += `CREATE SEQUENCE IF NOT EXISTS ${seq[1]};\n`  // crear secuencia referenciada
      s += ` DEFAULT ${r.def}`
    }
    if (r.attnotnull) s += ' NOT NULL'
    return s
  })
  // PK + UNIQUE (no FKs para evitar orden/deps)
  const cons = await c.query(`
    SELECT pg_get_constraintdef(con.oid) AS def
    FROM pg_constraint con
    JOIN pg_class c ON c.oid=con.conrelid
    JOIN pg_namespace n ON n.oid=c.relnamespace AND n.nspname='public'
    WHERE c.relname=$1 AND con.contype IN ('p','u')`, [t])
  const consDefs = cons.rows.map(r => '  '+r.def)
  out += `CREATE TABLE IF NOT EXISTS ${t} (\n${[...colDefs, ...consDefs].join(',\n')}\n);\n\n`
}

// Funciones (definición vigente = pre-185 en prod) → archivo separado
for (const f of FUNCS) {
  const defs = await c.query(`
    SELECT pg_get_functiondef(p.oid) AS def
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
    WHERE p.proname=$1`, [f])
  for (const r of defs.rows) outFn += r.def + ';\n\n'
}

// Grants actuales de esas funciones a anon/authenticated (para reproducir el estado vulnerable)
outFn += '-- Grants pre-185 (reproducen exposición anónima real)\n'
for (const f of FUNCS) {
  const g = await c.query(`
    SELECT p.oid, pg_get_function_identity_arguments(p.oid) AS args,
           has_function_privilege('anon', p.oid, 'EXECUTE') AS anon,
           has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
    WHERE p.proname=$1`, [f])
  for (const r of g.rows) {
    if (r.anon) outFn += `GRANT EXECUTE ON FUNCTION ${f}(${r.args}) TO anon;\n`
    if (r.auth) outFn += `GRANT EXECUTE ON FUNCTION ${f}(${r.args}) TO authenticated;\n`
  }
}

// Grants de tabla a anon (reproduce el agujero de estado_diario_flota)
out += '\n-- Grants de tabla a anon (estado vulnerable real)\n'
for (const t of TABLES) {
  const g = await c.query(`
    SELECT privilege_type FROM information_schema.role_table_grants
    WHERE grantee='anon' AND table_schema='public' AND table_name=$1`, [t])
  const privs = g.rows.map(r=>r.privilege_type).filter(p=>['SELECT','INSERT','UPDATE','DELETE'].includes(p))
  if (privs.length) out += `GRANT ${privs.join(',')} ON ${t} TO anon;\n`
  // authenticated
  const g2 = await c.query(`
    SELECT privilege_type FROM information_schema.role_table_grants
    WHERE grantee='authenticated' AND table_schema='public' AND table_name=$1`, [t])
  const privs2 = g2.rows.map(r=>r.privilege_type).filter(p=>['SELECT','INSERT','UPDATE','DELETE'].includes(p))
  if (privs2.length) out += `GRANT ${privs2.join(',')} ON ${t} TO authenticated;\n`
}

// RLS status real de estas tablas (para reproducir: estado_diario_flota SIN rls)
out += '\n-- RLS status real en prod (pre-185)\n'
const rls = await c.query(`SELECT tablename, rowsecurity FROM pg_tables WHERE schemaname='public' AND tablename = ANY($1)`, [TABLES])
for (const r of rls.rows) if (r.rowsecurity) out += `ALTER TABLE ${r.tablename} ENABLE ROW LEVEL SECURITY;\n`

writeFileSync('preprod_base_prod.sql', out); writeFileSync('preprod_funcs_prod.sql', outFn)
console.log('escrito preprod_base_prod.sql,', out.length, 'bytes')
console.log('tablas:', TABLES.length, 'funcs:', FUNCS.length)
await c.end()
