// ============================================================================
// [MIG580 · MIG732] El Excel del bono, con fórmulas
// ----------------------------------------------------------------------------
// Para entender un cobro hay que poder rehacerlo. Desde el 26-11-2026 (Manuel:
// «todo venga con fórmulas») el Excel no trae montos escritos: cada número
// calculado es una fórmula que parte de los datos de la OT y de la hoja
// «Parámetros» (los mismos que usó el motor en ese corte, MIG732). Al lado
// queda lo que calculó SICOM y una columna «Diferencia» que debe dar $0.
//
// Hojas: Resumen · Trabajos · Parámetros · Cómo se calcula · OT sin dueño (si hay).
// ============================================================================

import ExcelJS from 'exceljs'
import type { BonoLinea, BonoTrabajoExcel, OTSinDueno } from '@/lib/services/taller-bono'

export type ParametrosBonoExcel = {
  nombre: string | null
  conceptos: { concepto: string; descripcion: string; dias_optimizado: number; dias_normal: number; dias_demora: number; coef_optimizado: number; coef_por_dia: number }[]
  cargos: { cargo: string; plan_tope: number; kpi_base: number }[]
  tramos_kpi: { desde_pct: number; factor: number; etiqueta: string }[]
}

export type BonoExcelInput = {
  corteNombre: string
  desde: string
  hasta: string
  cerrado: boolean
  disponibilidadPct: number | null
  lineas: BonoLinea[]
  trabajos: BonoTrabajoExcel[]
  sinDueno: OTSinDueno[]
  parametros: ParametrosBonoExcel
}

const CLP = '"$"#,##0'
const FECHA = 'dd-mm-yyyy'
const FECHA_HORA = 'dd-mm-yyyy hh:mm'
const AZUL = 'FF1E40AF'
const GRIS_DATO = 'FFF3F4F6'      // celdas que son dato de SICOM (no fórmula)
const P = "'Parámetros'"

function fechaCorta(iso: string): string {
  const [y, m, d] = iso.split('-')
  return `${d}-${m}-${y}`
}
/** Fecha de calendario (YYYY-MM-DD) como fecha de Excel, sin desfase de zona. */
function fechaExcel(iso: string): Date {
  const [y, m, d] = iso.slice(0, 10).split('-').map(Number)
  return new Date(Date.UTC(y, m - 1, d))
}

function encabezado(ws: ExcelJS.Worksheet, fila = 1) {
  const r = ws.getRow(fila)
  r.font = { bold: true, color: { argb: 'FFFFFFFF' } }
  r.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: AZUL } }
  r.alignment = { vertical: 'middle', horizontal: 'center', wrapText: true }
  r.height = 42
}
function marcarDato(cell: ExcelJS.Cell) {
  cell.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: GRIS_DATO } }
}

const num = (v: number | string | null | undefined) => (v == null || v === '' ? null : Number(v))
const fecha = (v: string | null) => (v ? new Date(v) : null)
const f = (formula: string) => ({ formula })

export async function exportarBonoTrabajosExcel(input: BonoExcelInput): Promise<Blob> {
  const wb = new ExcelJS.Workbook()
  wb.creator = 'SICOM-Pillado'
  wb.created = new Date()
  wb.calcProperties.fullCalcOnLoad = true

  const wsR = wb.addWorksheet('Resumen')
  const wsT = wb.addWorksheet('Trabajos')
  const wsP = wb.addWorksheet('Parámetros')

  // ── Parámetros ─────────────────────────────────────────────────────────────
  wsP.getCell('A1').value = `Parámetros del bono · ${input.parametros.nombre ?? ''}`
  wsP.getCell('A1').font = { size: 14, bold: true }
  const meta: [string, ExcelJS.CellValue, string?][] = [
    ['Corte desde', fechaExcel(input.desde), FECHA],
    ['Corte hasta', fechaExcel(input.hasta), FECHA],
    ['Disponibilidad de flota', input.disponibilidadPct != null ? input.disponibilidadPct / 100 : null, '0.00%'],
    ['Días del mes comercial (prorrateo)', 30],
  ]
  meta.forEach(([k, v, fmt], i) => {
    wsP.getCell(`A${i + 3}`).value = k
    wsP.getCell(`A${i + 3}`).font = { bold: true }
    const c = wsP.getCell(`B${i + 3}`); c.value = v; if (fmt) c.numFmt = fmt
  })
  const DESDE = `${P}!$B$3`, HASTA = `${P}!$B$4`, DISP = `${P}!$B$5`, MES = `${P}!$B$6`

  // Conceptos
  let fila = 9
  wsP.getRow(fila - 1).values = ['Concepto', 'Descripción', 'Plazo optimizado (días)', 'Plazo normal (días)', 'Plazo demora (días)', 'Coef. optimizado', 'Coef. por día']
  encabezado(wsP, fila - 1)
  const concIni = fila
  for (const c of input.parametros.conceptos) {
    wsP.getRow(fila++).values = [c.concepto, c.descripcion, num(c.dias_optimizado), num(c.dias_normal), num(c.dias_demora), num(c.coef_optimizado), num(c.coef_por_dia)]
  }
  const concFin = Math.max(concIni, fila - 1)
  for (let r = concIni; r <= concFin; r++) { wsP.getCell(`F${r}`).numFmt = '0.000000'; wsP.getCell(`G${r}`).numFmt = '0.000000' }
  const CONC = `${P}!$A$${concIni}:$G$${concFin}`

  // Cargos
  fila += 2
  wsP.getRow(fila - 1).values = ['Cargo', 'Tope plan de incentivo', 'Base KPI disponibilidad']
  encabezado(wsP, fila - 1)
  const cargIni = fila
  for (const c of input.parametros.cargos) wsP.getRow(fila++).values = [c.cargo, num(c.plan_tope), num(c.kpi_base)]
  const cargFin = Math.max(cargIni, fila - 1)
  for (let r = cargIni; r <= cargFin; r++) { wsP.getCell(`B${r}`).numFmt = CLP; wsP.getCell(`C${r}`).numFmt = CLP }
  const CARG = `${P}!$A$${cargIni}:$C$${cargFin}`

  // Tramos KPI (ordenados de menor a mayor: BUSCAR toma el último ≤ disponibilidad)
  fila += 2
  wsP.getRow(fila - 1).values = ['Disponibilidad desde', 'Factor KPI', 'Tramo']
  encabezado(wsP, fila - 1)
  const tramIni = fila
  for (const t of [...input.parametros.tramos_kpi].sort((a, b) => a.desde_pct - b.desde_pct)) {
    wsP.getRow(fila++).values = [num(t.desde_pct), num(t.factor), t.etiqueta]
  }
  const tramFin = Math.max(tramIni, fila - 1)
  for (let r = tramIni; r <= tramFin; r++) { wsP.getCell(`A${r}`).numFmt = '0%'; wsP.getCell(`B${r}`).numFmt = '0%' }
  const TRAM_DESDE = `${P}!$A$${tramIni}:$A$${tramFin}`, TRAM_FACTOR = `${P}!$B$${tramIni}:$B$${tramFin}`
  wsP.columns = [30, 36, 14, 14, 14, 14, 14].map((width) => ({ width }))
  wsP.getCell(`A${fila + 1}`).value = 'Cambie un valor de esta hoja y todo el libro se recalcula.'
  wsP.getCell(`A${fila + 1}`).font = { italic: true, color: { argb: 'FF6B7280' } }

  // ── Trabajos ───────────────────────────────────────────────────────────────
  const COLS: [string, number][] = [
    ['Técnico', 20], ['Cargo', 12], ['OT', 17], ['Tipo OT', 12], ['Equipo', 20], ['Concepto', 9], ['Descripción concepto', 28],
    ['Inicio OT', 16], ['Término OT', 16],
    ['Duración (horas calendario)', 11], ['Días acumulados (tramo)', 10], ['Días en el corte (prorrateo)', 10],
    ['Plazo optimizado (días)', 10], ['Plazo normal (días)', 10], ['Plazo demora (días)', 10],
    ['Coef. optimizado', 11], ['Coef. por día', 11], ['Tramo', 14], ['% del tramo', 9], ['Prorrateo del corte', 10],
    ['Tope del cargo', 12], ['Valor OT en plazo para su cargo (100%)', 14], ['Participación', 11],
    ['Monto planilla (sin corregir)', 14], ['Monto pagado', 13], ['Monto según SICOM', 13], ['Diferencia', 11],
    ['Rol en la OT', 11], ['Jornadas asignadas', 10], ['Horas medidas (reloj)', 10], ['Cuadrilla completa', 50],
    ['Base del reparto', 18], ['Falta / aviso', 40],
  ]
  wsT.columns = COLS.map(([header, width]) => ({ header, width }))
  encabezado(wsT)
  input.trabajos.forEach((t, i) => {
    const r = i + 2
    const sinFechas = !t.fecha_inicio || !t.fecha_termino
    wsT.getRow(r).values = [
      t.tecnico, t.cargo, t.ot_folio, t.ot_tipo, t.equipo, t.concepto, t.concepto_nombre,
      fecha(t.fecha_inicio), fecha(t.fecha_termino),
      // J horas · K días acumulados · L días en el corte (de las fechas; si falta una, el dato de SICOM)
      sinFechas ? num(t.horas_calendario) : f(`ROUND((I${r}-H${r})*24,1)`),
      sinFechas ? num(t.dias) : f(`MAX(1,ROUNDUP(ROUND(I${r}-H${r},6),0))`),
      sinFechas ? num(t.dias_en_corte) : f(`MAX(0,MIN(INT(I${r}),${HASTA})-MAX(INT(H${r}),${DESDE})+1)`),
      // M-Q plazos y coeficientes del concepto
      f(`IFERROR(VLOOKUP($F${r},${CONC},3,FALSE),"")`),
      f(`IFERROR(VLOOKUP($F${r},${CONC},4,FALSE),"")`),
      f(`IFERROR(VLOOKUP($F${r},${CONC},5,FALSE),"")`),
      f(`IFERROR(VLOOKUP($F${r},${CONC},6,FALSE),"")`),
      f(`IFERROR(VLOOKUP($F${r},${CONC},7,FALSE),"")`),
      // R tramo · S % del tramo · T prorrateo
      f(`IF(M${r}="","",IF(K${r}<=M${r},"optimizado",IF(K${r}<=N${r},"normal",IF(K${r}<=O${r},"con demora","fuera de plazo"))))`),
      f(`IF(M${r}="","",IF(K${r}<=M${r},1,IF(K${r}<=N${r},1-0.4*(K${r}-M${r})/(N${r}-M${r}),IF(K${r}<=O${r},0.6-0.6*(K${r}-N${r})/(O${r}-N${r}),0))))`),
      f(`MIN(1,L${r}/K${r})`),
      // U tope · V valor OT en plazo · W participación (dato)
      f(`IFERROR(VLOOKUP($B${r},${CARG},2,FALSE),"")`),
      f(`IFERROR(ROUND(U${r}*P${r}*M${r},0),"")`),
      num(t.participacion),
      // X planilla literal · Y pagado · Z SICOM (dato) · AA diferencia
      f(`IFERROR(ROUND(W${r}*U${r}*IF(K${r}<=M${r},P${r}*M${r},IF(K${r}<=N${r},K${r}*Q${r},(O${r}-K${r})*Q${r})),0),0)`),
      f(`IFERROR(ROUND(W${r}*U${r}*P${r}*M${r}*T${r}*S${r},0),0)`),
      num(t.monto_propuesto) ?? 0,
      f(`Y${r}-Z${r}`),
      t.rol, num(t.jornadas), num(t.horas_medidas), t.cuadrilla, t.base_reparto,
      [t.falta, t.aviso].filter(Boolean).join(' · ') || null,
    ]
    for (const c of ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'W', 'Z']) marcarDato(wsT.getCell(`${c}${r}`))
    if (sinFechas) for (const c of ['J', 'K', 'L']) marcarDato(wsT.getCell(`${c}${r}`))
  })
  const nT = input.trabajos.length
  const finT = Math.max(2, nT + 1)
  const filaTotT = nT + 2
  wsT.getCell(`A${filaTotT}`).value = 'TOTAL'
  for (const c of ['X', 'Y', 'Z', 'AA']) wsT.getCell(`${c}${filaTotT}`).value = f(`SUM(${c}2:${c}${finT})`)
  wsT.getRow(filaTotT).font = { bold: true }
  for (let r = 2; r <= filaTotT; r++) {
    wsT.getCell(`H${r}`).numFmt = FECHA_HORA
    wsT.getCell(`I${r}`).numFmt = FECHA_HORA
    for (const c of ['P', 'Q']) wsT.getCell(`${c}${r}`).numFmt = '0.000000'
    for (const c of ['U', 'V', 'X', 'Y', 'Z', 'AA']) wsT.getCell(`${c}${r}`).numFmt = CLP
    for (const c of ['S', 'T', 'W']) wsT.getCell(`${c}${r}`).numFmt = '0%'
  }
  wsT.autoFilter = { from: { row: 1, column: 1 }, to: { row: 1, column: COLS.length } }
  wsT.views = [{ state: 'frozen', ySplit: 1, xSplit: 3 }]
  const TR = (c: string) => `Trabajos!$${c}$2:$${c}$${finT}`

  // ── Resumen ────────────────────────────────────────────────────────────────
  wsR.getCell('A1').value = `Bono del taller · ${input.corteNombre}`
  wsR.getCell('A1').font = { size: 16, bold: true }
  const metaR: [string, string][] = [
    ['Corte', `${fechaCorta(input.desde)} al ${fechaCorta(input.hasta)}`],
    ['Estado', input.cerrado ? 'CERRADO (montos congelados)' : 'BORRADOR (se mueve con cada OT que se cierre)'],
    ['Generado', new Date().toLocaleString('es-CL')],
    ['Cómo leerlo', 'Todo lo calculado es fórmula (hoja Parámetros + Trabajos). Gris = dato de SICOM. «Diferencia» debe dar $0.'],
  ]
  metaR.forEach(([k, v], i) => {
    wsR.getCell(`A${i + 3}`).value = k
    wsR.getCell(`A${i + 3}`).font = { bold: true }
    wsR.getCell(`B${i + 3}`).value = v
  })
  wsR.getCell('A7').value = 'Disponibilidad de flota'
  wsR.getCell('A7').font = { bold: true }
  wsR.getCell('B7').value = f(DISP)
  wsR.getCell('B7').numFmt = '0.00%'

  const ini = 9
  wsR.getRow(ini).values = ['Técnico', 'Cargo', 'OT pagadas', 'Planilla (sin corregir)', 'Corregida', 'Días de cargo en el corte',
    'Prorrateo (días ÷ 30)', 'Tope del cargo', 'Pagado por trabajos', 'Cobra KPI', 'Base KPI', 'Factor KPI',
    'KPI disponibilidad', 'Total', 'Total según SICOM', 'Diferencia', 'Falta / aviso']
  encabezado(wsR, ini)
  input.lineas.forEach((l, i) => {
    const r = ini + 1 + i
    // [MIG729] Quien ya no está en el taller cobra sus trabajos, sin KPI.
    const cobraKpi = /ya no está en el taller/i.test(l.aviso ?? '') ? 'No' : 'Sí'
    wsR.getRow(r).values = [
      l.tecnico, l.cargo ?? null,
      f(`COUNTIFS(${TR('A')},$A${r})`),
      f(`SUMIFS(${TR('X')},${TR('A')},$A${r})`),
      f(`SUMIFS(${TR('Y')},${TR('A')},$A${r})`),
      num(l.dias_cargo),
      f(`MIN(1,ROUND(F${r}/${MES},4))`),
      f(`IFERROR(ROUND(VLOOKUP($B${r},${CARG},2,FALSE)*G${r},0),0)`),
      f(`MIN(E${r},H${r})`),
      cobraKpi,
      f(`IFERROR(VLOOKUP($B${r},${CARG},3,FALSE),0)`),
      f(`IF(${DISP}="",0,LOOKUP(${DISP},${TRAM_DESDE},${TRAM_FACTOR}))`),
      f(`IF(J${r}="Sí",ROUND(K${r}*L${r}*MIN(1,F${r}/${MES}),0),0)`),
      f(`I${r}+M${r}`),
      num(l.total) ?? 0,
      f(`N${r}-O${r}`),
      [l.falta, l.aviso].filter(Boolean).join(' · ') || null,
    ]
    for (const c of ['A', 'B', 'F', 'J', 'O']) marcarDato(wsR.getCell(`${c}${r}`))
  })
  const filaTot = ini + 1 + input.lineas.length
  const finR = Math.max(ini + 1, filaTot - 1)
  const suma = (c: string) => f(`SUM(${c}${ini + 1}:${c}${finR})`)
  wsR.getRow(filaTot).values = ['TOTAL', null, suma('C'), suma('D'), suma('E'), null, null, null,
    suma('I'), null, null, null, suma('M'), suma('N'), suma('O'), suma('P'), null]
  wsR.getRow(filaTot).font = { bold: true }
  for (let r = ini + 1; r <= filaTot; r++) {
    for (const c of ['D', 'E', 'H', 'I', 'K', 'M', 'N', 'O', 'P']) wsR.getCell(`${c}${r}`).numFmt = CLP
    wsR.getCell(`G${r}`).numFmt = '0.00%'
    wsR.getCell(`L${r}`).numFmt = '0%'
  }
  wsR.columns = [24, 14, 9, 14, 13, 10, 11, 13, 14, 8, 12, 9, 14, 14, 14, 11, 40].map((width) => ({ width }))
  wsR.getColumn(2).width = 14
  wsR.getCell('B6').alignment = { wrapText: true }

  // ── Cómo se calcula ────────────────────────────────────────────────────────
  const wsC = wb.addWorksheet('Cómo se calcula')
  wsC.getColumn(1).width = 110
  const texto = [
    'CÓMO SE CALCULA EL BONO (Estructura KPI 2025, acta del 01-09-2026; cada uno cobra su línea completa desde el 25-11-2026)',
    '',
    'Todo lo calculado en este libro es fórmula. Las celdas grises son datos de SICOM (fechas de la OT, cargo, participación, días de cargo).',
    'Los parámetros (plazos, coeficientes, topes, bases y tramos) están en la hoja «Parámetros»: si cambia uno, el libro se recalcula.',
    '',
    'POR TRABAJO (hoja Trabajos):',
    '1. Sólo cuentan OT ejecutadas dentro del corte, hechas por el taller (no por externos) y sin cierre con pendientes por validar.',
    '2. Días acumulados = de inicio a término de la OT, redondeado hacia arriba (mínimo 1). Deciden el TRAMO.',
    '3. % del tramo: hasta «Plazo optimizado» 100 %; hasta «Plazo normal» baja lineal a 60 %; hasta «Plazo demora» baja lineal a 0 %; más = 0 %.',
    '4. Valor OT en plazo para su cargo = Tope del cargo × coef. optimizado × plazo optimizado.',
    '5. Prorrateo del corte = días en el corte ÷ días acumulados (máximo 1): una OT que viene de antes paga sólo su parte.',
    '6. Monto pagado = Tope × coef. optimizado × plazo optimizado × prorrateo × % del tramo × participación.',
    '   Desde el 25-11-2026 (MIG728) no hay reparto: cada persona de la cuadrilla cobra su línea completa (participación 100 %).',
    '7. «Monto planilla» = la fórmula de la planilla original, literal (puede dar negativo). Sólo para comparar; se paga el «Monto pagado».',
    '',
    'POR TÉCNICO (hoja Resumen):',
    '8. Tope del cargo = tope del plan × prorrateo (días de cargo en el corte ÷ 30, máximo 1). Pagado por trabajos = menor entre lo corregido y el tope.',
    '9. KPI disponibilidad = base KPI del cargo × factor del tramo de disponibilidad × días de cargo ÷ 30 (máximo 1).',
    '   Quien ya no está en el taller cobra sus trabajos, sin KPI (MIG729).',
    '10. Total = pagado por trabajos + KPI. «Diferencia» compara con lo que calculó SICOM y debe dar $0.',
  ]
  texto.forEach((t, i) => {
    wsC.getCell(`A${i + 1}`).value = t
    if (i === 0) wsC.getCell('A1').font = { bold: true, size: 13 }
  })

  // ── OT sin dueño ───────────────────────────────────────────────────────────
  if (input.sinDueno.length > 0) {
    const wsS = wb.addWorksheet('OT sin dueño')
    wsS.columns = [
      { header: 'OT',        key: 'ot_folio',      width: 18 },
      { header: 'Estado',    key: 'estado',        width: 18 },
      { header: 'Término',   key: 'fecha_termino', width: 18 },
      { header: 'Por qué no le paga a nadie', key: 'motivo', width: 60 },
    ]
    encabezado(wsS)
    for (const o of input.sinDueno) wsS.addRow({ ...o, fecha_termino: fecha(o.fecha_termino) })
    for (let r = 2; r <= input.sinDueno.length + 1; r++) wsS.getCell(`C${r}`).numFmt = FECHA_HORA
  }

  const buffer = await wb.xlsx.writeBuffer()
  return new Blob([buffer], {
    type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  })
}
