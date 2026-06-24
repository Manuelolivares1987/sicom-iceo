// Genera un Excel AUDITABLE con los ejemplos de KPI de fiabilidad.
// Cada hoja trae la línea de tiempo día-a-día en celdas y TODOS los KPI como
// fórmulas (COUNTIF + columna auxiliar de episodios). Cambiar un día recalcula.
// Uso (desde frontend/):  node scripts/generar-ejemplos-kpi.mjs
import ExcelJS from 'exceljs'

const COLOR = {
  A: 'FF16A34A', C: 'FF15803D', L: 'FF4F46E5', U: 'FF0891B2', D: 'FF2563EB',
  H: 'FFA855F7', R: 'FF06B6D4', M: 'FFF59E0B', T: 'FFFB923C', F: 'FFDC2626', V: 'FF9333EA',
}
const LABEL = {
  A: 'Arrendado', C: 'En contrato', L: 'Leasing', U: 'Uso interno', D: 'Disponible',
  V: 'Venta', H: 'Habilitación', R: 'Recepción', M: 'Mantención (>1d)', T: 'Taller (<1d)',
  F: 'Fuera de servicio',
}
const ORDEN = ['A', 'C', 'L', 'U', 'D', 'V', 'H', 'R', 'M', 'T', 'F']

// ── Construcción de las líneas de tiempo (30 días) ──
const rep = (estado, n) => Array(n).fill(estado)
const ejemploA = [
  ...rep('A', 14), ...rep('M', 2), ...rep('A', 11), ...rep('D', 3),
] // 25 A, 2 M (1 falla), 3 D
const ejemploB = [
  ...rep('A', 10), ...rep('M', 4), ...rep('D', 2), ...rep('A', 6),
  ...rep('T', 1), ...rep('H', 2), ...rep('R', 2), ...rep('F', 3),
] // 16 A, 4 M, 2 D, 1 T, 2 H, 2 R, 3 F → 3 fallas (M, T, F)

function construirHoja(wb, nombre, dias, subtitulo) {
  const ws = wb.addWorksheet(nombre, { views: [{ state: 'frozen', ySplit: 3 }] })
  ws.columns = [
    { width: 6 }, { width: 10 }, { width: 12 }, { width: 2 },
    { width: 34 }, { width: 14 },
  ]

  ws.mergeCells('A1:F1')
  ws.getCell('A1').value = `Ejemplo de KPI de Fiabilidad — ${nombre}`
  ws.getCell('A1').font = { bold: true, size: 14, color: { argb: 'FF0B2A4A' } }
  ws.mergeCells('A2:F2')
  ws.getCell('A2').value = subtitulo
  ws.getCell('A2').font = { italic: true, color: { argb: 'FF64748B' } }

  // ── Encabezados de la línea de tiempo ──
  const hRow = 3
  ws.getCell(`A${hRow}`).value = 'Día'
  ws.getCell(`B${hRow}`).value = 'Estado'
  ws.getCell(`C${hRow}`).value = 'Inicio falla'
  for (const col of ['A', 'B', 'C']) {
    const c = ws.getCell(`${col}${hRow}`)
    c.font = { bold: true, color: { argb: 'FFFFFFFF' } }
    c.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF0B2A4A' } }
    c.alignment = { horizontal: 'center' }
  }

  const first = hRow + 1            // fila 4
  const last = first + dias.length - 1
  dias.forEach((estado, i) => {
    const r = first + i
    ws.getCell(`A${r}`).value = i + 1
    const ce = ws.getCell(`B${r}`)
    ce.value = estado
    ce.alignment = { horizontal: 'center' }
    ce.font = { bold: true, color: { argb: 'FFFFFFFF' } }
    ce.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: COLOR[estado] ?? 'FF9CA3AF' } }
    // Columna auxiliar: 1 si HOY es M/T/F y AYER no lo era → inicio de episodio (falla)
    ws.getCell(`C${r}`).value = {
      formula: `IF(AND(OR(B${r}="M",B${r}="T",B${r}="F"),NOT(OR(B${r - 1}="M",B${r - 1}="T",B${r - 1}="F"))),1,0)`,
    }
    ws.getCell(`C${r}`).alignment = { horizontal: 'center' }
  })

  const estRange = `$B$${first}:$B$${last}`
  const auxRange = `$C$${first}:$C$${last}`

  // ── Bloque de conteos (col E/F) con COUNTIF ──
  let r = first
  const put = (label, valueOrFormula, opts = {}) => {
    ws.getCell(`E${r}`).value = label
    const cell = ws.getCell(`F${r}`)
    cell.value = valueOrFormula
    if (opts.bold) { ws.getCell(`E${r}`).font = { bold: true }; cell.font = { bold: true } }
    if (opts.fmt) cell.numFmt = opts.fmt
    if (opts.fill) {
      for (const col of ['E', 'F']) ws.getCell(`${col}${r}`).fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: opts.fill } }
    }
    r++
  }

  ws.getCell(`E${r}`).value = 'CONTEO DE DÍAS POR ESTADO'
  ws.getCell(`E${r}`).font = { bold: true, color: { argb: 'FF0B2A4A' } }
  r++
  for (const e of ORDEN) {
    put(`${e} — ${LABEL[e]}`, { formula: `COUNTIF(${estRange},"${e}")` })
  }
  const fTotal = r
  put('Total días', { formula: `COUNTA(${estRange})` }, { bold: true, fill: 'FFF1F5F9' })

  // Mapa de filas de conteo: el título va en `first`, los conteos arrancan en first+1.
  const filaConteo = {}
  ORDEN.forEach((e, i) => { filaConteo[e] = first + 1 + i })
  const fa = `F${filaConteo.A}`, fc = `F${filaConteo.C}`, fl = `F${filaConteo.L}`
  const fu = `F${filaConteo.U}`, fd = `F${filaConteo.D}`, fv = `F${filaConteo.V}`
  const fh = `F${filaConteo.H}`, fr = `F${filaConteo.R}`, fm = `F${filaConteo.M}`
  const ft = `F${filaConteo.T}`, ff = `F${filaConteo.F}`
  const totRef = `F${fTotal}`

  r += 1
  ws.getCell(`E${r}`).value = 'INDICADORES (KPI)'
  ws.getCell(`E${r}`).font = { bold: true, color: { argb: 'FF0B2A4A' } }
  r++

  const rUP = r; put('UP (operativo) = A+C+L+U+D+V', { formula: `${fa}+${fc}+${fl}+${fu}+${fd}+${fv}` })
  const rDOWN = r; put('DOWN (no disp.) = M+T+F+R+H', { formula: `${fm}+${ft}+${ff}+${fr}+${fh}` })
  const rFallas = r; put('Fallas (episodios M/T/F)', { formula: `SUM(${auxRange})` })
  const rFis = r; put('Disp. Física = UP / Total', { formula: `F${rUP}/${totRef}`, }, { fmt: '0.0%' })
  const rMtbf = r; put('MTBF = UP / Fallas (días)', { formula: `IF(F${rFallas}=0,F${rUP},F${rUP}/F${rFallas})` }, { fmt: '0.0' })
  const rMttr = r; put('MTTR = (M+T) / Fallas (días)', { formula: `IF(F${rFallas}=0,0,(${fm}+${ft})/F${rFallas})` }, { fmt: '0.0' })
  const rInh = r; put('Disp. Inherente = MTBF/(MTBF+MTTR)', { formula: `IF((F${rMtbf}+F${rMttr})=0,1,F${rMtbf}/(F${rMtbf}+F${rMttr}))` }, { fmt: '0.0%' })
  const rUtil = r; put('Utilización = (A+L+C) / Total', { formula: `(${fa}+${fl}+${fc})/${totRef}` }, { fmt: '0.0%' })
  const rRep = r; put('Rep/mes (reincidencia) = Fallas−1', { formula: `MAX(F${rFallas}-1,0)` })
  const rCal = r; put('Calidad del trabajo = 1 / Fallas', { formula: `IF(F${rFallas}=0,1,1/F${rFallas})` }, { fmt: '0.0%' })
  put('OEE = Disp. Física × Calidad', { formula: `F${rFis}*F${rCal}` }, { bold: true, fmt: '0.0%', fill: 'FFFEF3C7' })
  void rDOWN; void rInh; void rUtil; void rRep

  return ws
}

function hojaDefiniciones(wb) {
  const ws = wb.addWorksheet('Definiciones')
  ws.columns = [{ width: 28 }, { width: 70 }]
  ws.mergeCells('A1:B1')
  ws.getCell('A1').value = 'Definiciones de los KPI'
  ws.getCell('A1').font = { bold: true, size: 14, color: { argb: 'FF0B2A4A' } }
  const filas = [
    ['Estados UP (operativo)', 'A, C, L, U, D, V'],
    ['Estados DOWN (no disponible)', 'M, T, F, R, H  (Habilitación y Recepción bajan la disponibilidad)'],
    ['Falla', 'Cada episodio (racha de días consecutivos) en M, T o F'],
    ['Disp. Física', 'UP ÷ Total'],
    ['MTBF', 'UP ÷ nº fallas'],
    ['MTTR', '(M + T) ÷ nº fallas  — solo reparación con HH; F (sin HH) no es reparación'],
    ['Disp. Inherente', 'MTBF ÷ (MTBF + MTTR)  — solo reparación activa; difiere de la física por F/R/H'],
    ['Utilización', '(A + L + C) ÷ Total  — comercial, NO entra al OEE'],
    ['Calidad del trabajo', 'fallas primarias ÷ fallas totales  — castiga reincidencia (en el ejemplo, 1 mes ⇒ 1 ÷ fallas)'],
    ['Rep/mes', 'Fallas que se repiten dentro del mismo mes'],
    ['OEE', 'Disp. Física × Calidad del trabajo'],
  ]
  let r = 3
  for (const [k, v] of filas) {
    ws.getCell(`A${r}`).value = k
    ws.getCell(`A${r}`).font = { bold: true, color: { argb: 'FF0B2A4A' } }
    ws.getCell(`B${r}`).value = v
    ws.getCell(`B${r}`).alignment = { wrapText: true }
    r++
  }
}

const wb = new ExcelJS.Workbook()
wb.creator = 'SICOM-ICEO'
hojaDefiniciones(wb)
construirHoja(wb, 'Ejemplo A - Sano', ejemploA, 'Equipo sano: 1 sola mantención, sin fallas repetidas → OEE alto.')
construirHoja(wb, 'Ejemplo B - Problema', ejemploB, 'Equipo problema: 3 fallas el mismo mes + días F/R/H → OEE bajo.')

const out = '../EJEMPLOS_KPI_FIABILIDAD.xlsx'
await wb.xlsx.writeFile(out)
console.log(`✓ Generado: ${out}`)
