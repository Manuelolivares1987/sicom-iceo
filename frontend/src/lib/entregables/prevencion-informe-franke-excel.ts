// ============================================================================
// Informe de Gestión Mensual — SCM Franke (formato TA.DPR.IN.SS-0005/F-01-3)
// ----------------------------------------------------------------------------
// Replica las tres secciones del Excel que Franke exige mes a mes:
//   1. Indicadores estadísticos (mes y acumulado, IF/IG/IA calculados)
//   2. Actividades preventivas (programado/realizado + capacitaciones)
//   3. Reportabilidad de incidentes (los RIT del mes)
// Los encabezados salen de prevencion_faena_config; los números, de lo que
// cargaron supervisores y prevención. MIG547.
// ============================================================================

import ExcelJS from 'exceljs'
import type {
  FaenaConfigDatos, GestionMensualFila, IndicadoresFila, PrevencionRegistro,
} from '@/lib/services/prevencion-reportabilidad'

const MESES = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio',
  'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre']

const AZUL = 'FF1F4E78'
const GRIS = 'FFF2F2F2'

export async function generarInformeFrankeExcel(params: {
  config: FaenaConfigDatos
  indicadoresAnio: IndicadoresFila[]   // v_prevencion_indicadores del año
  gestion: GestionMensualFila[]        // consolidado del mes
  registros: PrevencionRegistro[]      // registros del mes (capacitaciones + RIT)
  anio: number
  mes: number
}): Promise<Blob> {
  const { config, indicadoresAnio, gestion, registros, anio, mes } = params
  const con = config.contrato ?? {}
  const emp = config.empresa ?? {}

  const wb = new ExcelJS.Workbook()
  wb.creator = 'SICOM — Pillado Empresas'
  const ws = wb.addWorksheet('Informe gestión', {
    pageSetup: { paperSize: 9, orientation: 'landscape', fitToPage: true, fitToWidth: 1 },
  })
  ws.columns = Array.from({ length: 18 }, (_, i) => ({ width: i === 1 ? 22 : 11 }))

  let f = 1
  const seccion = (texto: string) => {
    ws.mergeCells(f, 1, f, 18)
    const c = ws.getCell(f, 1)
    c.value = texto
    c.font = { bold: true, color: { argb: 'FFFFFFFF' }, size: 11 }
    c.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: AZUL } }
    f++
  }
  const encabezado = (celdas: string[], filaBase?: number) => {
    const ff = filaBase ?? f
    celdas.forEach((t, i) => {
      const c = ws.getCell(ff, i + 1)
      c.value = t
      c.font = { bold: true, size: 8 }
      c.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: GRIS } }
      c.alignment = { wrapText: true, vertical: 'middle', horizontal: 'center' }
    })
    if (filaBase === undefined) f++
  }

  // ── Cabecera del formato ──
  ws.mergeCells(f, 1, f, 12)
  ws.getCell(f, 1).value = 'Informe de Gestión Mensual — Empresas Colaboradoras'
  ws.getCell(f, 1).font = { bold: true, size: 14 }
  ws.getCell(f, 13).value = 'TA.DPR.IN.SS-0005/F-01-3'
  ws.getCell(f, 13).font = { size: 9 }
  f += 2

  const cab: Array<[string, string]> = [
    ['Mes de informe', `${MESES[mes - 1]} ${anio}`],
    ['Empresa', emp.razon_social ?? ''],
    ['Faena', config.faena_nombre ?? ''],
    ['Instalación', con.instalacion_informe ?? ''],
    ['Administrador', con.administrador ?? ''],
    ['Asesor prevención', con.asesor_prevencion ?? ''],
    ['N° contrato / OC', con.numero ?? ''],
    ['Administrador contrato mandante', con.admin_mandante ?? ''],
    ['Superintendencia', con.superintendencia ?? ''],
    ['Elaborado por', (config.experto as any)?.nombre ?? ''],
  ]
  for (let i = 0; i < cab.length; i += 2) {
    ws.getCell(f, 1).value = cab[i][0]
    ws.getCell(f, 1).font = { bold: true, size: 9 }
    ws.getCell(f, 2).value = cab[i][1]
    if (cab[i + 1]) {
      ws.getCell(f, 5).value = cab[i + 1][0]
      ws.getCell(f, 5).font = { bold: true, size: 9 }
      ws.getCell(f, 6).value = cab[i + 1][1]
    }
    f++
  }
  f++

  // ── 1. Indicadores estadísticos ──
  seccion('1. Indicadores estadísticos — Reactivos (mes y acumulado)')
  encabezado(['Mes', 'Fza. trabajo', 'Fza. acum.', 'HH mes', 'HH acum.', 'CTP mes',
    'CTP acum.', 'STP mes', 'Días perd.', 'Días acum.', 'IF mes', 'IF acum.',
    'IG mes', 'IG acum.'])
  let fzaAcum = 0
  for (let m = 1; m <= 12; m++) {
    const fila = indicadoresAnio.find((x) => x.mes === m)
    ws.getCell(f, 1).value = MESES[m - 1]
    if (fila) {
      fzaAcum += fila.dotacion_total ?? 0
      const vals = [
        fila.dotacion_total, fzaAcum, Number(fila.hh_total), Number(fila.acum_hh),
        fila.accidentes_ctp, fila.acum_ctp, fila.accidentes_stp,
        fila.dias_perdidos, fila.acum_dias_perdidos,
        Number(fila.indice_frecuencia), Number(fila.acum_indice_frecuencia),
        Number(fila.indice_gravedad), Number(fila.acum_indice_gravedad),
      ]
      vals.forEach((v, i) => { ws.getCell(f, i + 2).value = v as number })
      if (m === mes) {
        for (let c = 1; c <= 14; c++) {
          ws.getCell(f, c).fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FFE2EFDA' } }
        }
      }
    }
    f++
  }
  f++

  // ── 2. Actividades preventivas ──
  seccion('2. Actividades preventivas — programado vs realizado')
  encabezado(['Actividad', 'Programado', 'Realizado', '% Cumpl.', 'Abiertos', 'Cerrados'])
  for (const g of gestion) {
    ws.getCell(f, 1).value = g.tipo_nombre
    ws.getCell(f, 2).value = g.meta
    ws.getCell(f, 3).value = g.realizados
    ws.getCell(f, 4).value = g.pct_cumplimiento === null ? '—' : `${g.pct_cumplimiento}%`
    ws.getCell(f, 5).value = g.requiere_cierre ? g.abiertos : '—'
    ws.getCell(f, 6).value = g.requiere_cierre ? g.cerrados : '—'
    f++
  }
  f++

  const capacitaciones = registros.filter(
    (r) => r.tipo_codigo === 'CAPACITACION' || r.tipo_codigo === 'CHARLA',
  )
  seccion('2.1 Capacitaciones y charlas del mes')
  encabezado(['N°', 'Tema', 'Fecha', 'Relator/responsable', 'Duración (min)', 'Asistentes', 'HH capacitación'])
  capacitaciones.forEach((c, i) => {
    const hh = ((c.duracion_minutos ?? 0) * (c.asistentes ?? 0)) / 60
    ws.getCell(f, 1).value = i + 1
    ws.getCell(f, 2).value = c.titulo
    ws.getCell(f, 3).value = c.fecha_actividad
    ws.getCell(f, 4).value = c.supervisor_nombre ?? ''
    ws.getCell(f, 5).value = c.duracion_minutos ?? 0
    ws.getCell(f, 6).value = c.asistentes ?? 0
    ws.getCell(f, 7).value = Math.round(hh * 10) / 10
    f++
  })
  if (!capacitaciones.length) { ws.getCell(f, 1).value = 'Sin capacitaciones registradas en el mes.'; f++ }
  f++

  // ── 3. Reportabilidad de incidentes ──
  seccion('3. Reportabilidad de incidentes (RIT del mes)')
  encabezado(['N°', 'Título', 'Fecha', 'Reporta', 'Estado', 'Descripción'])
  const rits = registros.filter((r) => r.tipo_codigo === 'RIT')
  rits.forEach((r, i) => {
    ws.getCell(f, 1).value = i + 1
    ws.getCell(f, 2).value = r.titulo
    ws.getCell(f, 3).value = r.fecha_actividad
    ws.getCell(f, 4).value = r.supervisor_nombre ?? ''
    ws.getCell(f, 5).value = r.estado
    ws.getCell(f, 6).value = r.descripcion ?? ''
    f++
  })
  if (!rits.length) { ws.getCell(f, 1).value = 'Sin incidentes reportados en el mes.'; f++ }
  f++

  ws.mergeCells(f, 1, f, 14)
  ws.getCell(f, 1).value =
    'Generado por SICOM desde los registros cargados por supervisión y prevención — revisar antes de enviar.'
  ws.getCell(f, 1).font = { italic: true, size: 8, color: { argb: 'FF666666' } }

  const buffer = await wb.xlsx.writeBuffer()
  return new Blob([buffer], {
    type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  })
}
