// ============================================================================
// [MIG580] El Excel del bono por trabajos
// ----------------------------------------------------------------------------
// Para entender un cobro hay que poder rehacerlo a mano. Por eso cada fila trae
// la OT con sus fechas, los días que acumuló (deciden el tramo), los días que
// cayeron en el corte (prorratean), los plazos del concepto, el tope del cargo,
// la cuadrilla completa y cuánto le tocó a cada uno.
//
// Hojas: Resumen · Trabajos · Cómo se calcula · OT sin dueño (si hay).
// ============================================================================

import ExcelJS from 'exceljs'
import type { BonoLinea, BonoTrabajoExcel, OTSinDueno } from '@/lib/services/taller-bono'

export type BonoExcelInput = {
  corteNombre: string
  desde: string
  hasta: string
  cerrado: boolean
  disponibilidadPct: number | null
  lineas: BonoLinea[]
  trabajos: BonoTrabajoExcel[]
  sinDueno: OTSinDueno[]
}

const CLP = '"$"#,##0'
const FECHA_HORA = 'dd-mm-yyyy hh:mm'
const AZUL = 'FF1E40AF'

function fechaCorta(iso: string): string {
  const [y, m, d] = iso.split('-')
  return `${d}-${m}-${y}`
}

function encabezado(ws: ExcelJS.Worksheet, fila = 1) {
  const r = ws.getRow(fila)
  r.font = { bold: true, color: { argb: 'FFFFFFFF' } }
  r.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: AZUL } }
  r.alignment = { vertical: 'middle', horizontal: 'center', wrapText: true }
  r.height = 32
}

const num = (v: number | string | null | undefined) => (v == null ? null : Number(v))
const fecha = (v: string | null) => (v ? new Date(v) : null)

export async function exportarBonoTrabajosExcel(input: BonoExcelInput): Promise<Blob> {
  const wb = new ExcelJS.Workbook()
  wb.creator = 'SICOM-Pillado'
  wb.created = new Date()

  // ── Resumen ────────────────────────────────────────────────────────────────
  const wsR = wb.addWorksheet('Resumen')
  wsR.getCell('A1').value = `Bono del taller · ${input.corteNombre}`
  wsR.getCell('A1').font = { size: 16, bold: true }
  const meta: [string, string][] = [
    ['Corte', `${fechaCorta(input.desde)} al ${fechaCorta(input.hasta)}`],
    ['Estado', input.cerrado ? 'CERRADO (montos congelados)' : 'BORRADOR (se mueve con cada OT que se cierre)'],
    ['Disponibilidad de flota', input.disponibilidadPct != null ? `${input.disponibilidadPct}%` : '—'],
    ['Generado', new Date().toLocaleString('es-CL')],
  ]
  meta.forEach(([k, v], i) => {
    wsR.getCell(`A${i + 3}`).value = k
    wsR.getCell(`A${i + 3}`).font = { bold: true }
    wsR.getCell(`B${i + 3}`).value = v
  })

  const ini = meta.length + 4
  const cols = ['Técnico', 'Cargo', 'OT pagadas', 'Planilla (sin corregir)', 'Corregida',
                'Tope del cargo', 'Pagado por trabajos', 'KPI disponibilidad', 'Total', 'Falta / aviso']
  wsR.getRow(ini).values = cols
  encabezado(wsR, ini)
  input.lineas.forEach((l, i) => {
    wsR.getRow(ini + 1 + i).values = [
      l.tecnico, l.cargo ?? '—', l.ots, num(l.plan_formula), num(l.plan_calculado),
      num(l.plan_tope), num(l.plan_pagado), num(l.kpi_pagado), num(l.total),
      [l.falta, l.aviso].filter(Boolean).join(' · ') || null,
    ]
  })
  const filaTot = ini + 1 + input.lineas.length
  const suma = (c: string) => ({ formula: `SUM(${c}${ini + 1}:${c}${filaTot - 1})` })
  wsR.getRow(filaTot).values = ['TOTAL', null, suma('C'), suma('D'), suma('E'), null,
                                suma('G'), suma('H'), suma('I'), null]
  wsR.getRow(filaTot).font = { bold: true }
  for (const c of ['D', 'E', 'F', 'G', 'H', 'I']) {
    for (let r = ini + 1; r <= filaTot; r++) wsR.getCell(`${c}${r}`).numFmt = CLP
  }
  wsR.columns = [24, 14, 10, 16, 14, 14, 16, 16, 14, 40].map((width) => ({ width }))

  // ── Trabajos ───────────────────────────────────────────────────────────────
  const wsT = wb.addWorksheet('Trabajos')
  wsT.columns = [
    { header: 'Técnico',                     key: 'tecnico',          width: 20 },
    { header: 'Cargo',                       key: 'cargo',            width: 12 },
    { header: 'OT',                          key: 'ot_folio',         width: 17 },
    { header: 'Tipo OT',                     key: 'ot_tipo',          width: 12 },
    { header: 'Equipo',                      key: 'equipo',           width: 20 },
    { header: 'Concepto',                    key: 'concepto',         width: 9 },
    { header: 'Descripción concepto',        key: 'concepto_nombre',  width: 30 },
    { header: 'Inicio OT',                   key: 'fecha_inicio',     width: 16 },
    { header: 'Término OT',                  key: 'fecha_termino',    width: 16 },
    { header: 'Duración (horas calendario)', key: 'horas_calendario', width: 12 },
    { header: 'Días acumulados (tramo)',     key: 'dias',             width: 11 },
    { header: 'Días en el corte (prorrateo)', key: 'dias_en_corte',   width: 11 },
    { header: 'Plazo optimizado (días)',     key: 'plazo_optimizado', width: 11 },
    { header: 'Plazo normal (días)',         key: 'plazo_normal',     width: 11 },
    { header: 'Plazo demora (días)',         key: 'plazo_demora',     width: 11 },
    { header: 'Tramo',                       key: 'tramo',            width: 14 },
    { header: 'Tope del cargo',              key: 'tope_cargo',       width: 13 },
    { header: 'Valor OT en plazo para su cargo (100%)', key: 'monto_ot_completa', width: 14 },
    { header: 'Rol en la OT',                key: 'rol',              width: 11 },
    { header: 'Jornadas asignadas',          key: 'jornadas',         width: 10 },
    { header: 'Horas medidas (reloj)',       key: 'horas_medidas',    width: 10 },
    { header: 'Cuadrilla completa',          key: 'cuadrilla',        width: 50 },
    { header: 'Participación',               key: 'participacion',    width: 12 },
    { header: 'Base del reparto',            key: 'base_reparto',     width: 18 },
    { header: 'Monto planilla (sin corregir)', key: 'monto_formula',  width: 14 },
    { header: 'Monto pagado',                key: 'monto_propuesto',  width: 13 },
    { header: 'Falta / aviso',               key: 'nota',             width: 40 },
  ]
  encabezado(wsT)
  for (const t of input.trabajos) {
    const row = wsT.addRow({
      ...t,
      fecha_inicio: fecha(t.fecha_inicio),
      fecha_termino: fecha(t.fecha_termino),
      horas_calendario: num(t.horas_calendario),
      dias: num(t.dias),
      dias_en_corte: num(t.dias_en_corte),
      plazo_optimizado: num(t.plazo_optimizado),
      plazo_normal: num(t.plazo_normal),
      plazo_demora: num(t.plazo_demora),
      tope_cargo: num(t.tope_cargo),
      monto_ot_completa: num(t.monto_ot_completa),
      jornadas: num(t.jornadas),
      horas_medidas: num(t.horas_medidas),
      participacion: num(t.participacion),
      monto_formula: num(t.monto_formula),
      monto_propuesto: num(t.monto_propuesto),
      nota: [t.falta, t.aviso].filter(Boolean).join(' · ') || null,
    })
    // Lo que pagó cero o la planilla daba negativo: que salte a la vista.
    if (t.tramo === 'fuera de plazo' || Number(t.monto_formula) < 0) {
      row.getCell('tramo').font = { color: { argb: 'FFB91C1C' }, bold: true }
    }
  }
  const nT = input.trabajos.length
  const filaTotT = nT + 2
  wsT.getCell(`A${filaTotT}`).value = 'TOTAL'
  wsT.getCell(`Y${filaTotT}`).value = { formula: `SUM(Y2:Y${nT + 1})` }
  wsT.getCell(`Z${filaTotT}`).value = { formula: `SUM(Z2:Z${nT + 1})` }
  wsT.getRow(filaTotT).font = { bold: true }
  for (let r = 2; r <= filaTotT; r++) {
    wsT.getCell(`H${r}`).numFmt = FECHA_HORA
    wsT.getCell(`I${r}`).numFmt = FECHA_HORA
    for (const c of ['Q', 'R', 'Y', 'Z']) wsT.getCell(`${c}${r}`).numFmt = CLP
    wsT.getCell(`W${r}`).numFmt = '0%'
  }
  wsT.autoFilter = { from: { row: 1, column: 1 }, to: { row: 1, column: wsT.columns.length } }
  wsT.views = [{ state: 'frozen', ySplit: 1, xSplit: 3 }]

  // ── Cómo se calcula ────────────────────────────────────────────────────────
  const wsC = wb.addWorksheet('Cómo se calcula')
  wsC.getColumn(1).width = 110
  const texto = [
    'CÓMO SE CALCULA EL BONO POR TRABAJOS (Estructura KPI 2025, acta del 01-09-2026)',
    '',
    '1. Sólo cuentan OT ejecutadas dentro del corte, hechas por el taller (no por externos) y sin cierre con pendientes por validar.',
    '2. Días acumulados = desde el inicio de la OT hasta su término, redondeado hacia arriba (mínimo 1). Deciden el TRAMO.',
    '3. Tramo según los plazos del concepto: hasta «Plazo optimizado» = optimizado (100%); hasta «Plazo normal» baja lineal a 60%;',
    '   hasta «Plazo demora» baja lineal a 0%; sobre eso = fuera de plazo (0%).',
    '4. Valor OT en plazo para su cargo = Tope del cargo × coeficiente del concepto × plazo optimizado (por eso un Mecánico A y un B ven valores distintos en la misma OT).',
    '5. Si la OT viene de antes del corte, se paga sólo la parte proporcional: días en el corte ÷ días acumulados (D5).',
    '6. El valor se reparte en la cuadrilla según «Base del reparto»:',
    '   · tiempo medido: horas de reloj de cada uno ÷ horas totales (cuando todos marcaron reloj);',
    '   · jornadas asignadas: jornadas de cada uno en el Plan Semanal ÷ jornadas totales;',
    '   · partes iguales: si no hay ni reloj ni jornadas.',
    '7. Monto pagado = Valor OT en plazo × % del tramo × prorrateo × Participación.',
    '8. La suma por persona se corta en el «Tope del cargo».',
    '',
    '«Monto planilla» es la fórmula de la planilla original, transcrita literal: puede dar negativo y no es monótona.',
    'Se muestra sólo para comparar. Lo que se paga es «Monto pagado» (curva corregida, decisión D14).',
    '',
    'El KPI de disponibilidad es aparte: base del cargo × factor del tramo de disponibilidad × días de contrato / 30.',
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
    for (const o of input.sinDueno) {
      wsS.addRow({ ...o, fecha_termino: fecha(o.fecha_termino) })
    }
    for (let r = 2; r <= input.sinDueno.length + 1; r++) wsS.getCell(`C${r}`).numFmt = FECHA_HORA
  }

  const buffer = await wb.xlsx.writeBuffer()
  return new Blob([buffer], {
    type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  })
}
