#!/usr/bin/env node
// Analisis profundo de la hoja "Detalle OS" del Historico de Mantenimiento.
// Muestra: # filas, # patentes unicas, tipos de cada columna, rango de fechas,
// muestras de valores raros.

import ExcelJS from 'exceljs'
import { resolve } from 'node:path'

const FILE = 'C:\\Users\\Manuel Olivares\\Desktop\\2026\\PILLADO\\Mantenimiento\\Historico OS Auditoria.xlsx'

const wb = new ExcelJS.Workbook()
await wb.xlsx.readFile(FILE)

const ws = wb.getWorksheet('Detalle OS')
if (!ws) { console.error('Hoja "Detalle OS" no existe'); process.exit(1) }

// Header esta en fila 2 (fila 1 es el titulo grande). Datos desde fila 3.
const headers = []
ws.getRow(2).eachCell({ includeEmpty: false }, (c, col) => {
  headers[col] = String(c.value ?? '').trim()
})
console.log(`Headers (${headers.filter(Boolean).length} cols):`)
headers.forEach((h, i) => { if (h) console.log(`  col ${i}: ${h}`) })

// Recolectar todos los valores por columna
const columnas = {}
headers.forEach((h, i) => { if (h) columnas[h] = { col: i, valores: [], nulos: 0, tipos: new Set() } })

const patentesUnicas = new Set()
const aniosUnicos = new Set()
let totalFilas = 0
let filasConPatente = 0

for (let r = 3; r <= ws.rowCount; r++) {
  const row = ws.getRow(r)
  if (row.cellCount === 0) continue
  totalFilas++

  for (const h of Object.keys(columnas)) {
    const cell = row.getCell(columnas[h].col)
    const v = cell.value
    if (v == null || v === '') {
      columnas[h].nulos++
    } else {
      columnas[h].tipos.add(typeof v === 'object'
        ? ('result' in (v ?? {}) ? 'formula' : v instanceof Date ? 'date' : 'object')
        : typeof v)
      if (columnas[h].valores.length < 3) columnas[h].valores.push(v)
    }
  }

  const patente = row.getCell(columnas['Patente']?.col ?? -1).value
  if (patente) {
    patentesUnicas.add(String(patente).trim().toUpperCase())
    filasConPatente++
  }
  const anio = row.getCell(columnas['Año']?.col ?? -1).value
  if (anio) aniosUnicos.add(anio)
}

console.log(`\nTotal filas con datos: ${totalFilas}`)
console.log(`Filas con patente: ${filasConPatente}`)
console.log(`Patentes unicas: ${patentesUnicas.size}`)
console.log(`Anios: ${Array.from(aniosUnicos).sort().join(', ')}`)

console.log('\nDetalle por columna:')
console.log('-'.repeat(80))
for (const [h, info] of Object.entries(columnas)) {
  const tipos = Array.from(info.tipos).join(', ') || '—'
  const nulosPct = totalFilas > 0 ? Math.round((info.nulos / totalFilas) * 100) : 0
  const muestraValores = info.valores.map((v) =>
    v instanceof Date ? v.toISOString().slice(0, 10) :
    typeof v === 'object' && 'result' in v ? `fmla:${v.result}` :
    typeof v === 'object' && 'text' in v ? v.text :
    String(v).slice(0, 30),
  ).join(' | ')
  console.log(`  ${h.padEnd(28)} tipos:${tipos.padEnd(14)} nulos:${String(info.nulos).padStart(3)}/${totalFilas} (${nulosPct}%)  muestra: ${muestraValores}`)
}

console.log('\nPrimeras 15 patentes unicas:')
console.log('  ' + Array.from(patentesUnicas).sort().slice(0, 15).join(', '))
