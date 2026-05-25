#!/usr/bin/env node
// Lee un Excel y muestra metadatos: hojas, headers, primeras 3 filas, total filas.
import ExcelJS from 'exceljs'
import { resolve } from 'node:path'

const file = process.argv[2]
if (!file) {
  console.error('Uso: node inspect-excel.mjs "<ruta_xlsx>"')
  process.exit(2)
}

const wb = new ExcelJS.Workbook()
await wb.xlsx.readFile(resolve(file))

console.log(`Archivo: ${file}`)
console.log(`Hojas: ${wb.worksheets.map((s) => s.name).join(' | ')}`)

for (const ws of wb.worksheets) {
  console.log(`\n=== Hoja: "${ws.name}" (${ws.rowCount} filas, ${ws.columnCount} cols) ===`)
  if (ws.rowCount === 0) continue

  // Header (fila 1)
  const header = []
  ws.getRow(1).eachCell({ includeEmpty: true }, (c, col) => {
    header.push(`[${col}] ${String(c.value ?? '').slice(0, 40)}`)
  })
  console.log('Headers:')
  header.forEach((h) => console.log('  ' + h))

  // Primeras 3 filas de datos
  console.log('\nPrimeras 3 filas:')
  for (let r = 2; r <= Math.min(4, ws.rowCount); r++) {
    const row = []
    ws.getRow(r).eachCell({ includeEmpty: true }, (c) => {
      const v = c.value
      const s = v == null ? '' :
        typeof v === 'object' && 'text' in v ? String(v.text) :
        typeof v === 'object' && 'result' in v ? String(v.result) :
        v instanceof Date ? v.toISOString().slice(0, 10) :
        String(v)
      row.push(s.slice(0, 30))
    })
    console.log(`  R${r}: ${row.join(' | ')}`)
  }
}
