#!/usr/bin/env node
// Vuelca todas las filas de una (o todas) las hojas de un Excel.
// Uso: node dump-xlsx.mjs "<ruta>" ["<hoja>"] [maxColLen]
import ExcelJS from 'exceljs'
import { resolve } from 'node:path'

const [file, sheet, maxLenArg] = process.argv.slice(2)
const MAX = Number(maxLenArg || 28)
const wb = new ExcelJS.Workbook()
await wb.xlsx.readFile(resolve(file))

const cellStr = (v) => {
  if (v == null) return ''
  if (typeof v === 'object') {
    if ('text' in v) return String(v.text)
    if ('result' in v) return String(v.result)
    if ('richText' in v) return v.richText.map((t) => t.text).join('')
    if (v instanceof Date) return v.toISOString().slice(0, 10)
  }
  return String(v)
}

for (const ws of wb.worksheets) {
  if (sheet && ws.name !== sheet) continue
  console.log(`\n##### HOJA: ${ws.name} (${ws.rowCount} filas) #####`)
  for (let r = 1; r <= ws.rowCount; r++) {
    const cells = []
    ws.getRow(r).eachCell({ includeEmpty: false }, (c, col) => {
      const s = cellStr(c.value).replace(/\s+/g, ' ').trim()
      if (s) cells.push(`[${col}]${s.slice(0, MAX)}`)
    })
    if (cells.length) console.log(`R${r}: ${cells.join(' | ')}`)
  }
}
