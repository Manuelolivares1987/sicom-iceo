// Genera un .xlsx con el plan semanal (Calama o Taller). Una hoja "Resumen"
// con KPI agregados y una hoja "Detalle" con una fila por jornada.

import ExcelJS from 'exceljs'

export type JornadaExcelRow = {
  fecha: string             // ISO YYYY-MM-DD
  dia_nombre: string
  folio: string
  tipo: string              // preventivo / correctivo / inspeccion / OT calama
  prioridad?: string | null
  activo?: string | null    // codigo - patente
  pm_nombre?: string | null
  responsable?: string | null
  cuadrilla?: string | null
  horas_planificadas?: number | null
  avance_objetivo?: number | null
  secuencia_jornada?: number | null
  estado_jornada: string
  estado_ot?: string | null
  avance_final?: number | null
  faena?: string | null
  cliente?: string | null
  observaciones?: string | null
}

export type ResumenKpi = {
  jornadas_planificadas: number
  jornadas_finalizadas: number
  jornadas_en_ejecucion: number
  jornadas_pendientes: number
  jornadas_atrasadas: number
  cumplimiento_pct: number
  horas_planificadas: number
  horas_reales: number
}

export type PlanSemanalExcelInput = {
  titulo: string                // "Plan semanal taller" | "Plan semanal Calama"
  fechaInicio: string           // ISO
  fechaFin: string              // ISO
  jornadas: JornadaExcelRow[]
  resumen?: ResumenKpi | null
  scopeNombre?: string | null   // ej: faena, planificacion, cliente — info contextual
  generadoPor?: string | null
}

function fmtDate(iso: string): string {
  const d = new Date(iso + 'T12:00:00')
  return d.toLocaleDateString('es-CL')
}

export async function exportarPlanSemanalExcel(input: PlanSemanalExcelInput): Promise<Blob> {
  const wb = new ExcelJS.Workbook()
  wb.creator = 'SICOM-Pillado'
  wb.created = new Date()

  // ── Hoja 1: Resumen ────────────────────────────────────────────────────────
  const wsR = wb.addWorksheet('Resumen')
  wsR.columns = [
    { width: 32 },
    { width: 28 },
  ]

  let row = 1
  wsR.getCell(`A${row}`).value = input.titulo
  wsR.getCell(`A${row}`).font = { size: 16, bold: true }
  row += 2

  const meta: [string, string | number | null | undefined][] = [
    ['Semana', `${fmtDate(input.fechaInicio)} → ${fmtDate(input.fechaFin)}`],
    ['Generado', new Date().toLocaleString('es-CL')],
    ['Ámbito', input.scopeNombre ?? '—'],
    ['Generado por', input.generadoPor ?? '—'],
  ]
  for (const [k, v] of meta) {
    wsR.getCell(`A${row}`).value = k
    wsR.getCell(`A${row}`).font = { bold: true }
    wsR.getCell(`B${row}`).value = v ?? '—'
    row++
  }
  row++

  if (input.resumen) {
    wsR.getCell(`A${row}`).value = 'KPI'
    wsR.getCell(`A${row}`).font = { bold: true, size: 13 }
    row++
    const kpis: [string, number | string][] = [
      ['Jornadas planificadas', input.resumen.jornadas_planificadas],
      ['Finalizadas', input.resumen.jornadas_finalizadas],
      ['En ejecución', input.resumen.jornadas_en_ejecucion],
      ['Pendientes', input.resumen.jornadas_pendientes],
      ['Atrasadas', input.resumen.jornadas_atrasadas],
      ['Cumplimiento %', `${input.resumen.cumplimiento_pct}%`],
      ['Horas planificadas', input.resumen.horas_planificadas],
      ['Horas reales', input.resumen.horas_reales],
    ]
    for (const [k, v] of kpis) {
      wsR.getCell(`A${row}`).value = k
      wsR.getCell(`B${row}`).value = v
      if (k === 'Atrasadas' && typeof v === 'number' && v > 0) {
        wsR.getCell(`B${row}`).font = { color: { argb: 'FFB91C1C' }, bold: true }
      }
      if (k === 'Cumplimiento %') {
        wsR.getCell(`B${row}`).font = { bold: true }
      }
      row++
    }
  }
  row++

  // Resumen por día (cuenta jornadas por fecha)
  const porDia = new Map<string, { fecha: string; dia: string; count: number; finalizadas: number; horasPlan: number }>()
  for (const j of input.jornadas) {
    if (!porDia.has(j.fecha)) {
      porDia.set(j.fecha, { fecha: j.fecha, dia: j.dia_nombre, count: 0, finalizadas: 0, horasPlan: 0 })
    }
    const g = porDia.get(j.fecha)!
    g.count++
    if (j.estado_jornada === 'finalizada') g.finalizadas++
    if (j.horas_planificadas) g.horasPlan += Number(j.horas_planificadas)
  }
  if (porDia.size > 0) {
    wsR.getCell(`A${row}`).value = 'Por día'
    wsR.getCell(`A${row}`).font = { bold: true, size: 13 }
    row++
    wsR.getCell(`A${row}`).value = 'Fecha'
    wsR.getCell(`B${row}`).value = 'Día'
    wsR.getCell(`C${row}`).value = 'Jornadas'
    wsR.getCell(`D${row}`).value = 'Finalizadas'
    wsR.getCell(`E${row}`).value = 'Horas plan.'
    wsR.getRow(row).font = { bold: true }
    row++
    const ordenadas = Array.from(porDia.values()).sort((a, b) => a.fecha.localeCompare(b.fecha))
    for (const g of ordenadas) {
      wsR.getCell(`A${row}`).value = fmtDate(g.fecha)
      wsR.getCell(`B${row}`).value = g.dia
      wsR.getCell(`C${row}`).value = g.count
      wsR.getCell(`D${row}`).value = g.finalizadas
      wsR.getCell(`E${row}`).value = g.horasPlan
      row++
    }
  }

  // ── Hoja 2: Detalle ────────────────────────────────────────────────────────
  const wsD = wb.addWorksheet('Detalle jornadas')
  wsD.columns = [
    { header: 'Fecha',          key: 'fecha',          width: 12 },
    { header: 'Día',            key: 'dia_nombre',     width: 12 },
    { header: 'Folio OT',       key: 'folio',          width: 18 },
    { header: 'Tipo',           key: 'tipo',           width: 14 },
    { header: 'Prioridad',      key: 'prioridad',      width: 12 },
    { header: 'Activo',         key: 'activo',         width: 22 },
    { header: 'Plan PM',        key: 'pm_nombre',      width: 35 },
    { header: 'Responsable',    key: 'responsable',    width: 22 },
    { header: 'Cuadrilla',      key: 'cuadrilla',      width: 16 },
    { header: 'Hs plan.',       key: 'horas_planificadas', width: 10 },
    { header: 'Avance obj. %',  key: 'avance_objetivo',width: 12 },
    { header: 'Jornada N°',     key: 'secuencia_jornada', width: 10 },
    { header: 'Estado jornada', key: 'estado_jornada', width: 18 },
    { header: 'Estado OT',      key: 'estado_ot',      width: 18 },
    { header: 'Avance final %', key: 'avance_final',   width: 12 },
    { header: 'Faena',          key: 'faena',          width: 20 },
    { header: 'Cliente',        key: 'cliente',        width: 22 },
    { header: 'Observaciones',  key: 'observaciones',  width: 40 },
  ]

  // Header style
  wsD.getRow(1).font = { bold: true, color: { argb: 'FFFFFFFF' } }
  wsD.getRow(1).fill = {
    type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF1E40AF' },
  }
  wsD.getRow(1).alignment = { vertical: 'middle', horizontal: 'center' }

  for (const j of input.jornadas) {
    wsD.addRow({
      ...j,
      fecha: j.fecha,  // ExcelJS lo convertirá si es Date; aquí lo dejamos como string ISO
    })
  }
  wsD.autoFilter = { from: { row: 1, column: 1 }, to: { row: 1, column: wsD.columns.length } }
  wsD.views = [{ state: 'frozen', ySplit: 1 }]

  // ── Buffer ─────────────────────────────────────────────────────────────────
  const buffer = await wb.xlsx.writeBuffer()
  return new Blob([buffer], {
    type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  })
}

// Helper para gatillar descarga en el navegador
export function descargarBlob(blob: Blob, filename: string) {
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  document.body.appendChild(a)
  a.click()
  a.remove()
  setTimeout(() => URL.revokeObjectURL(url), 10_000)
}
