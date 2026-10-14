// Convierte una hoja de exceljs en matriz de valores para leerHojaPlanilla.
// Las celdas combinadas solo valen en su celda maestra: si no, un título de
// sección combinado a lo ancho ("CAMIONES — RONDA…") aparece como código en
// cada día. Las fórmulas (días "=+E5+1") se leen por su resultado.
import type { Worksheet } from 'exceljs'

export function hojaAMatriz(ws: Worksheet): unknown[][] {
  const m: unknown[][] = []
  ws.eachRow({ includeEmpty: true }, (row, r) => {
    const arr: unknown[] = []
    for (let c = 1; c <= ws.columnCount; c++) {
      const cell = row.getCell(c)
      if (cell.isMerged && cell.master.address !== cell.address) { arr.push(null); continue }
      let v: unknown = cell.value
      if (v && typeof v === 'object' && 'result' in v) v = (v as { result: unknown }).result
      if (v && typeof v === 'object' && 'richText' in v) v = (v as { richText: { text: string }[] }).richText.map((t) => t.text).join('')
      arr.push(v)
    }
    m[r - 1] = arr
  })
  return m
}
