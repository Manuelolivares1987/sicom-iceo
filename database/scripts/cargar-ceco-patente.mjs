#!/usr/bin/env node
// Lee "ceco x patente.xlsx" y: (1) crea los CECO faltantes en centros_costo,
// (2) asocia activos.ceco_id por patente. Idempotente. Requiere MIG162 aplicada.
//
// Uso: node cargar-ceco-patente.mjs "<ruta_xlsx>" [--dry-run]

import ExcelJS from 'exceljs'
import pg from 'pg'
import dotenv from 'dotenv'
import { resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { existsSync } from 'node:fs'

const __dirname = dirname(fileURLToPath(import.meta.url))
dotenv.config({ path: resolve(__dirname, '../../.env.supabase-admin.local') })

const file = process.argv[2] || 'C:/Users/Manuel Olivares/Desktop/ceco x patente.xlsx'
const dryRun = process.argv.includes('--dry-run')
if (!existsSync(file)) { console.error('No existe:', file); process.exit(2) }

const wb = new ExcelJS.Workbook()
await wb.xlsx.readFile(file)
const ws = wb.worksheets[0]
const rows = []
ws.eachRow((row, n) => {
  if (n === 1) return
  const pat = String(row.getCell(1).value ?? '').trim()
  const ceco = String(row.getCell(2).value ?? '').trim()
  const marca = String(row.getCell(3).value ?? '').trim()
  const modelo = String(row.getCell(4).value ?? '').trim()
  const eq = String(row.getCell(5).value ?? '').trim()
  if (pat && ceco) rows.push({ pat, ceco, marca, modelo, eq })
})
console.log(`Filas: ${rows.length} | CECOs: ${new Set(rows.map(r => r.ceco)).size}`)

const url = (process.env.SUPABASE_DB_URL || '').trim()
const client = new pg.Client({ connectionString: url, ssl: { rejectUnauthorized: false }, statement_timeout: 600_000 })
await client.connect()
console.log('✓ conectado')

let cecosCreados = 0, cecosExisten = 0, activosOk = 0, activosNoMatch = []
try {
  await client.query('BEGIN')
  for (const r of rows) {
    // 1. CECO
    const ex = await client.query('SELECT id FROM centros_costo WHERE codigo=$1', [r.ceco])
    if (ex.rows.length === 0) {
      await client.query(
        `INSERT INTO centros_costo (id, codigo, nombre, area, activo)
         VALUES (gen_random_uuid(), $1, $2, 'Flota', true)`,
        [r.ceco, `${r.pat} · ${r.eq}`.slice(0, 120)],
      )
      cecosCreados++
    } else { cecosExisten++ }
    // 2. activo por patente (normalizado)
    const up = await client.query(
      `UPDATE activos a SET ceco_id = c.id
         FROM centros_costo c
        WHERE c.codigo = $1
          AND regexp_replace(upper(a.patente), '[^A-Z0-9]', '', 'g') = regexp_replace(upper($2), '[^A-Z0-9]', '', 'g')`,
      [r.ceco, r.pat],
    )
    if (up.rowCount > 0) activosOk += up.rowCount
    else activosNoMatch.push(r.pat)
  }
  if (dryRun) { await client.query('ROLLBACK'); console.log('DRY-RUN: rollback') }
  else { await client.query('COMMIT'); console.log('✓ COMMIT') }
} catch (e) {
  await client.query('ROLLBACK')
  console.error('✗ ERROR:', e.message)
  process.exit(1)
} finally { await client.end() }

console.log('─'.repeat(50))
console.log(`CECOs creados: ${cecosCreados} | ya existían: ${cecosExisten}`)
console.log(`Activos asociados: ${activosOk}`)
if (activosNoMatch.length) console.log(`Patentes sin activo en BD (${activosNoMatch.length}): ${activosNoMatch.join(', ')}`)
