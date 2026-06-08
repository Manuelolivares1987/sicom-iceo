#!/usr/bin/env node
// ============================================================================
// cargar-abastecimiento-historico.mjs
// Lee la hoja "Abastecimiento Detalle" del Excel de auditoria forense y carga
// combustible_abastecimiento_historico (upsert por fuente+cliente+equipo).
// Uso: node cargar-abastecimiento-historico.mjs ["ruta/al/Excel.xlsx"]
// ============================================================================
import { readFileSync, existsSync } from 'node:fs'
import { resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import pg from 'pg'
import ExcelJS from 'exceljs'
import dotenv from 'dotenv'

const __dirname = dirname(fileURLToPath(import.meta.url))
dotenv.config({ path: resolve(__dirname, '../../.env.supabase-admin.local') })

const XLSX = process.argv[2]
  || 'C:/Users/Manuel Olivares/Desktop/AUDITORIA/Auditoria Forense Combustible/Puntos_Carga_y_Abastecimiento.xlsx'
if (!existsSync(XLSX)) { console.error('No existe el Excel:', XLSX); process.exit(2) }

function clientConfig() {
  const url = (process.env.SUPABASE_DB_URL || '').trim()
  if (url) return { connectionString: url, ssl: { rejectUnauthorized: false }, statement_timeout: 600_000 }
  return {
    host: process.env.SUPABASE_DB_HOST, port: Number(process.env.SUPABASE_DB_PORT || 5432),
    user: process.env.SUPABASE_DB_USER, password: process.env.SUPABASE_DB_PASSWORD,
    database: process.env.SUPABASE_DB_NAME || 'postgres', ssl: { rejectUnauthorized: false }, statement_timeout: 600_000,
  }
}

const cell = (v) => {
  if (v == null) return ''
  if (typeof v === 'object' && v.result != null) return v.result
  if (typeof v === 'object' && v.text != null) return v.text
  if (typeof v === 'object' && v.richText) return v.richText.map((t) => t.text).join('')
  return v
}
const num = (v) => { const n = Number(String(cell(v)).replace(/[^0-9.-]/g, '')); return Number.isFinite(n) ? n : 0 }

const wb = new ExcelJS.Workbook()
await wb.xlsx.readFile(XLSX)
const ws = wb.getWorksheet('Abastecimiento Detalle')
if (!ws) { console.error('No se encontro la hoja "Abastecimiento Detalle"'); process.exit(2) }

const filas = []
let lastCliente = ''
ws.eachRow({ includeEmpty: false }, (row, rn) => {
  if (rn < 5) return // titulo + encabezado
  const vals = row.values || []
  const cli = String(cell(vals[1] ?? '')).trim()
  const cod = String(cell(vals[2] ?? '')).trim()
  const tipo = String(cell(vals[3] ?? '')).trim()
  const litros = num(vals[4])
  const ndesp = num(vals[5])
  if (cli) lastCliente = cli
  const cliente = lastCliente
  if (!cliente || cliente.toUpperCase().startsWith('TOTAL')) return
  if (!cod || cod.toUpperCase() === 'TOTAL') return
  filas.push({ cliente, cod, tipo, litros, ndesp })
})

console.log(`Filas parseadas: ${filas.length}`)
if (!filas.length) { console.error('Nada que cargar.'); process.exit(1) }

const client = new pg.Client(clientConfig())
await client.connect()
try {
  await client.query('BEGIN')
  let n = 0
  for (const f of filas) {
    await client.query(
      `INSERT INTO combustible_abastecimiento_historico (cliente, equipo_codigo, equipo_tipo, litros, n_despachos, fuente)
       VALUES ($1,$2,$3,$4,$5,'excel_auditoria')
       ON CONFLICT (fuente, cliente, equipo_codigo)
       DO UPDATE SET equipo_tipo=EXCLUDED.equipo_tipo, litros=EXCLUDED.litros, n_despachos=EXCLUDED.n_despachos`,
      [f.cliente, f.cod, f.tipo || null, f.litros, f.ndesp || null]
    )
    n++
  }
  await client.query('COMMIT')
  const r = await client.query('SELECT count(*) filas, round(sum(litros)) litros, count(distinct cliente) clientes FROM combustible_abastecimiento_historico')
  console.log('✓ Cargado. Total en tabla:', r.rows[0])
} catch (e) {
  await client.query('ROLLBACK').catch(() => {})
  console.error('✗ ERROR:', e.message)
  process.exit(1)
} finally { await client.end() }
