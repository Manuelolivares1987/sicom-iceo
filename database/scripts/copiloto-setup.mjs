#!/usr/bin/env node
// ============================================================================
// copiloto-setup.mjs — configura el proyecto Supabase "copiloto-corpus"
// usando la Management API (token en database/.env.copiloto.local, fuera de
// git). NO imprime secretos: escribe lo necesario al mismo .env local.
//
//   node copiloto-setup.mjs            # verifica, saca keys, aplica esquema
// ============================================================================
import { readFileSync, writeFileSync, existsSync } from 'node:fs'
import { resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import dotenv from 'dotenv'

const __dirname = dirname(fileURLToPath(import.meta.url))
const ENV_PATH = resolve(__dirname, '../.env.copiloto.local')
const SCHEMA_SQL = resolve(__dirname, '../copiloto/corpus_schema.sql')

dotenv.config({ path: ENV_PATH })
const TOKEN = process.env.SUPABASE_ACCESS_TOKEN
const REF = process.env.COPILOTO_PROJECT_REF
if (!TOKEN || !REF) { console.error('Faltan SUPABASE_ACCESS_TOKEN / COPILOTO_PROJECT_REF en .env.copiloto.local'); process.exit(2) }

const api = async (path, opts = {}) => {
  const res = await fetch(`https://api.supabase.com${path}`, {
    ...opts,
    headers: { Authorization: `Bearer ${TOKEN}`, 'Content-Type': 'application/json', ...(opts.headers ?? {}) },
  })
  const text = await res.text()
  let json = null
  try { json = JSON.parse(text) } catch { /* no json */ }
  return { status: res.status, json, text }
}

// 1 · Proyecto visible y sano
const proj = await api(`/v1/projects/${REF}`)
if (proj.status !== 200) {
  console.error(`✗ No puedo ver el proyecto ${REF} (HTTP ${proj.status}). ¿El token es de la cuenta correcta?`)
  process.exit(1)
}
console.log(`✓ proyecto: ${proj.json.name} · región ${proj.json.region} · estado ${proj.json.status}`)

// 2 · Service role key → al .env local (nunca a consola)
const keys = await api(`/v1/projects/${REF}/api-keys?reveal=true`)
if (keys.status !== 200 || !Array.isArray(keys.json)) {
  console.error(`✗ No pude leer las API keys (HTTP ${keys.status})`); process.exit(1)
}
const service = keys.json.find((k) => k.name === 'service_role' || k.type === 'secret')
if (!service?.api_key) { console.error('✗ No encontré la service_role key'); process.exit(1) }

let env = readFileSync(ENV_PATH, 'utf8')
const setVar = (k, v) => {
  const linea = `${k}=${v}`
  env = env.match(new RegExp(`^${k}=`, 'm')) ? env.replace(new RegExp(`^${k}=.*$`, 'm'), linea) : env + linea + '\n'
}
setVar('COPILOTO_SUPABASE_URL', `https://${REF}.supabase.co`)
setVar('COPILOTO_SUPABASE_SERVICE_KEY', service.api_key)

// 3 · Contraseña de la DB: se resetea vía API para poder armar la connection
//     string sin que nadie la pegue por chat. Pooler en sesión (IPv4 seguro).
const pass = (await import('node:crypto')).randomBytes(18).toString('base64').replace(/[+/=]/g, 'x')
const reset = await api(`/v1/projects/${REF}/database/password`, {
  method: 'PATCH', body: JSON.stringify({ password: pass }),
})
if (reset.status >= 200 && reset.status < 300) {
  setVar('COPILOTO_DB_PASSWORD', pass)
  setVar('COPILOTO_DB_URL', `postgresql://postgres.${REF}:${pass}@aws-0-${proj.json.region}.pooler.supabase.com:5432/postgres`)
  console.log('✓ contraseña de DB reseteada y connection string armada (pooler, puerto 5432)')
} else {
  console.log(`— No se pudo resetear la contraseña por API (HTTP ${reset.status}); la ingesta usará la API REST en su lugar`)
}
writeFileSync(ENV_PATH, env)
console.log(`✓ credenciales guardadas en ${ENV_PATH}`)

// 4 · Aplicar el esquema del corpus vía Management API (corre como superuser)
const sql = readFileSync(SCHEMA_SQL, 'utf8')
const q = await api(`/v1/projects/${REF}/database/query`, {
  method: 'POST', body: JSON.stringify({ query: sql }),
})
if (q.status >= 200 && q.status < 300) {
  console.log('✓ corpus_schema.sql aplicado')
  console.log(JSON.stringify(q.json, null, 2))
} else {
  console.error(`✗ Error aplicando esquema (HTTP ${q.status}): ${q.text.slice(0, 500)}`)
  process.exit(1)
}
