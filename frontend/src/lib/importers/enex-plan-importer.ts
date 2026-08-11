/**
 * Importer del Excel del plan semanal ENEX (formato "PLAN 07.08.xlsx").
 *
 * SOLO LECTURA: devuelve un preview para que el planificador lo revise antes de
 * guardar. El Excel que llega de faena es una tabla plana:
 *
 *   DIA              | AREA    | PUNTOS | AREA           | COMENTARIO
 *   LUNES 10/08      | LOMAS 2 | 1.1    |                | ASEO DE ESTANTES…
 *   MIERCOLES 13/08  | LOMAS 1 | 5.1    | RACK 1/ RACK 2 |
 *
 * La segunda columna "AREA" es en realidad el ALCANCE dentro del área (qué
 * racks). El encabezado repetido es del original y no se corrige en faena, así
 * que aquí se reconoce por posición además de por nombre.
 */

import ExcelJS from 'exceljs'

export type PlanFilaPreview = {
  fila: number
  fecha: string | null        // yyyy-mm-dd
  fechaTexto: string          // "LUNES 10/08" tal como venía
  area: string | null         // "LOMAS 2"
  codigoItem: string | null   // "1.1"
  alcance: string | null      // "RACK 1/ RACK 2"
  comentario: string | null
  problema: string | null     // por qué no se puede cargar esta fila
}

export type PlanPreview = {
  filas: PlanFilaPreview[]
  validas: number
  conProblema: number
  fechas: string[]            // días distintos, ordenados
  areas: string[]
  advertencias: string[]
}

const norm = (v: unknown): string => {
  if (v == null) return ''
  if (typeof v === 'object') {
    const o = v as { result?: unknown; text?: string; richText?: { text: string }[] }
    if (o.richText) return o.richText.map((r) => r.text).join('').trim()
    if (o.text) return String(o.text).trim()
    if (o.result != null) return String(o.result).trim()
  }
  return String(v).replace(/\s+/g, ' ').trim()
}

/**
 * "LUNES 10/08" → 2026-08-10. El Excel de faena no trae año: se toma el del
 * período que se está planificando, y si el mes cae muy lejos se asume que la
 * planilla es del año anterior (planes de fin de diciembre).
 */
export function parseDiaTexto(txt: string, anioRef: number, hoy = new Date()): string | null {
  const m = txt.match(/(\d{1,2})\s*[/-]\s*(\d{1,2})(?:\s*[/-]\s*(\d{2,4}))?/)
  if (m) {
    const d = Number(m[1]), mes = Number(m[2])
    let anio = m[3] ? Number(m[3]) : anioRef
    if (anio < 100) anio += 2000
    if (!m[3]) {
      // Sin año: si la diferencia con hoy pasa de medio año, es del otro.
      const cand = new Date(anio, mes - 1, d)
      const diff = (cand.getTime() - hoy.getTime()) / 86_400_000
      if (diff < -200) anio += 1
      else if (diff > 200) anio -= 1
    }
    if (mes < 1 || mes > 12 || d < 1 || d > 31) return null
    return `${anio}-${String(mes).padStart(2, '0')}-${String(d).padStart(2, '0')}`
  }
  // Fecha real de Excel ya formateada (2026-08-10T...)
  const iso = txt.match(/(\d{4})-(\d{2})-(\d{2})/)
  return iso ? `${iso[1]}-${iso[2]}-${iso[3]}` : null
}

/** Un código de actividad de la pauta: 1.1, 2.10, 5.8… */
const esCodigoItem = (s: string) => /^\d+\.\d+[a-z]?$/i.test(s.trim())

export async function leerPlanExcel(file: File | ArrayBuffer, anioRef: number): Promise<PlanPreview> {
  const wb = new ExcelJS.Workbook()
  const buf = file instanceof ArrayBuffer ? file : await file.arrayBuffer()
  await wb.xlsx.load(buf)

  const filas: PlanFilaPreview[] = []
  const advertencias: string[] = []
  const ws = wb.worksheets[0]
  if (!ws) return { filas: [], validas: 0, conProblema: 0, fechas: [], areas: [], advertencias: ['El archivo no tiene hojas.'] }
  if (wb.worksheets.length > 1) {
    advertencias.push(`El archivo trae ${wb.worksheets.length} hojas; se lee la primera ("${ws.name}").`)
  }

  // Localizar el encabezado (DIA / AREA / PUNTOS …). Puede no estar en la fila 1.
  let filaHeader = 0
  let cDia = 1, cArea = 2, cPuntos = 3, cAlcance = 4, cComent = 5
  for (let n = 1; n <= Math.min(ws.rowCount, 15); n++) {
    const celdas: string[] = []
    ws.getRow(n).eachCell({ includeEmpty: true }, (c, col) => { celdas[col] = norm(c.value).toUpperCase() })
    const iDia = celdas.findIndex((v) => v === 'DIA' || v === 'DÍA' || v === 'FECHA')
    if (iDia > 0) {
      filaHeader = n
      cDia = iDia
      const idxs = celdas.map((v, i) => ({ v, i })).filter((x) => x.v)
      cPuntos = idxs.find((x) => ['PUNTOS', 'PUNTO', 'ITEM', 'ÍTEM', 'ACTIVIDAD'].includes(x.v))?.i ?? cDia + 2
      const areas = idxs.filter((x) => x.v === 'AREA' || x.v === 'ÁREA').map((x) => x.i)
      cArea = areas[0] ?? cDia + 1
      cAlcance = areas[1] ?? (areas.length === 1 && areas[0] > cPuntos ? areas[0] : cPuntos + 1)
      cComent = idxs.find((x) => x.v.startsWith('COMENT') || x.v.startsWith('OBSERV'))?.i ?? cAlcance + 1
      break
    }
  }
  if (!filaHeader) {
    advertencias.push('No se encontró el encabezado (DIA / AREA / PUNTOS); se leyó por posición de columnas.')
  }

  // "arrastre": el Excel deja la fecha y el área en blanco cuando se repiten.
  let ultFechaTxt = '', ultArea = ''
  for (let n = (filaHeader || 1) + 1; n <= ws.rowCount; n++) {
    const row = ws.getRow(n)
    const val = (col: number) => norm(row.getCell(col).value)
    const diaTxt = val(cDia) || ultFechaTxt
    const area = val(cArea) || ultArea
    const codigo = val(cPuntos)
    const alcance = val(cAlcance)
    const comentario = val(cComent)

    // Fila vacía o de totales/notas: se ignora en silencio.
    if (!codigo && !diaTxt) continue
    if (!codigo) continue
    if (val(cDia)) ultFechaTxt = val(cDia)
    if (val(cArea)) ultArea = val(cArea)

    const fecha = diaTxt ? parseDiaTexto(diaTxt, anioRef) : null
    let problema: string | null = null
    if (!esCodigoItem(codigo)) problema = `"${codigo}" no parece un código de la pauta (ej. 1.1)`
    else if (!fecha) problema = `no se entiende la fecha "${diaTxt || '(vacía)'}"`
    else if (!area) problema = 'sin área (LOMAS 1 / LOMAS 2)'

    filas.push({
      fila: n,
      fecha,
      fechaTexto: diaTxt,
      area: area || null,
      codigoItem: codigo || null,
      alcance: alcance || null,
      comentario: comentario || null,
      problema,
    })
  }

  const validas = filas.filter((f) => !f.problema)
  return {
    filas,
    validas: validas.length,
    conProblema: filas.length - validas.length,
    fechas: Array.from(new Set(validas.map((f) => f.fecha!))).sort(),
    areas: Array.from(new Set(validas.map((f) => f.area!).filter(Boolean))),
    advertencias,
  }
}
