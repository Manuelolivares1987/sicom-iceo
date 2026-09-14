// ============================================================================
// Reportes Excel por faena (MIG557) — réplicas de los formatos reales
// ----------------------------------------------------------------------------
//   · Centinela: «Estadísticas para confección reporte E200 sub contratos
//     ESM-ENEX» — HH/dotación POR INSTALACIÓN + accidentabilidad del mes.
//   · Franke 4.4: «Reporte de insumos mensual EECC» (SGA-MLC-24), I a VII.
//   · Franke 4.5: «Registro de retiro de residuos» — un bloque por retiro
//     semanal + total del mes.
// Todo sale de lo que cargaron los supervisores + la ficha de la faena.
// ============================================================================

import ExcelJS from 'exceljs'
import type {
  AmbientalRegistroDetalle, DotacionInstalacion, FaenaConfigDatos, IndicadoresFila,
} from '@/lib/services/prevencion-reportabilidad'

const MESES = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio',
  'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre']

const AZUL = 'FF1F4E78'
const GRIS = 'FFF2F2F2'
const bordeFino = { style: 'thin' as const, color: { argb: 'FF999999' } }
const BORDES = { top: bordeFino, left: bordeFino, bottom: bordeFino, right: bordeFino }

function xlsxBlob(wb: ExcelJS.Workbook): Promise<Blob> {
  return wb.xlsx.writeBuffer().then((b) =>
    new Blob([b], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' }))
}

// ── Centinela: Estadística RRHH y accidentabilidad ESM-ENEX ─────────────────

export async function generarEstadisticaEsmExcel(params: {
  config: FaenaConfigDatos
  porInstalacion: DotacionInstalacion[]
  indicadores: IndicadoresFila | null
  anio: number
  mes: number
}): Promise<Blob> {
  const { config, porInstalacion, indicadores, anio, mes } = params
  const exp = config.experto ?? {}
  const instalaciones = ((config as any).instalaciones ?? []) as string[]

  const wb = new ExcelJS.Workbook()
  const ws = wb.addWorksheet('Estadísticas SSCC ESM - ENEX')
  ws.columns = [{ width: 26 }, { width: 34 }, { width: 12 }, { width: 12 }, { width: 12 }, { width: 12 }, { width: 22 }]

  let f = 1
  ws.mergeCells(f, 1, f, 7)
  ws.getCell(f, 1).value = 'Nota: Debe llevar estadísticas según cada área donde haya prestado servicios durante el mes.'
  ws.getCell(f, 1).font = { italic: true, size: 9 }
  f += 2

  ws.mergeCells(f, 1, f, 7)
  ws.getCell(f, 1).value = `ESTADÍSTICAS PARA CONFECCIÓN REPORTE E200 SUB CONTRATOS ESM - ENEX ${anio}`
  ws.getCell(f, 1).font = { bold: true, size: 12, color: { argb: 'FFFFFFFF' } }
  ws.getCell(f, 1).fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: AZUL } }
  ws.getCell(f, 1).alignment = { horizontal: 'center' }
  f++

  ws.getCell(f, 1).value = 'NOMBRE EMPRESA'; ws.getCell(f, 2).value = 'PILLADO'
  ws.getCell(f, 4).value = 'MES QUE REPORTA'
  ws.getCell(f, 6).value = MESES[mes - 1].toUpperCase(); ws.getCell(f, 7).value = anio
  for (const c of [1, 4]) ws.getCell(f, c).font = { bold: true }
  f++

  const enc = ['Nombre Faena', 'Nombre de Instalación', 'HH HOMBRE', 'HH MUJER', 'DOT. HOMBRE', 'DOT MUJER', 'INDIQUE N° DE CONTRATO']
  enc.forEach((h, i) => {
    const c = ws.getCell(f, i + 1)
    c.value = h; c.font = { bold: true, size: 9 }
    c.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: GRIS } }
    c.border = BORDES; c.alignment = { wrapText: true }
  })
  f++

  // Una fila por instalación del catálogo; lo reportado se cruza por nombre.
  // El formato «Grupo — Instalación» se abre en las dos primeras columnas.
  const reportado = new Map(porInstalacion.map((d) => [d.instalacion, d]))
  const filasInst = instalaciones.length
    ? instalaciones
    : porInstalacion.map((d) => d.instalacion || '(sin instalación)')
  let totHH_H = 0, totHH_M = 0, totDot_H = 0, totDot_M = 0
  for (const nombre of filasInst) {
    const d = reportado.get(nombre)
    const [grupo, inst] = nombre.includes('—')
      ? [nombre.split('—')[0].trim(), nombre.split('—').slice(1).join('—').trim()]
      : ['Centinela', nombre]
    const vals = [grupo, inst, d ? d.hh_hombres : 0, d ? d.hh_mujeres : 0,
      d ? d.dotacion_max_hombres : 0, d ? d.dotacion_max_mujeres : 0,
      (config.contrato as any)?.numero ?? '']
    vals.forEach((v, i) => {
      const c = ws.getCell(f, i + 1); c.value = v as any; c.border = BORDES; c.font = { size: 9 }
    })
    if (d) { totHH_H += d.hh_hombres; totHH_M += d.hh_mujeres; totDot_H += d.dotacion_max_hombres; totDot_M += d.dotacion_max_mujeres }
    f++
  }
  f++
  ws.getCell(f, 2).value = 'Totales del mes'
  ;['HH HOMBRE', 'HH MUJER', 'DOT. HOMBRE', 'DOT MUJER'].forEach((h, i) => {
    const c = ws.getCell(f, i + 3); c.value = h; c.font = { bold: true, size: 9 }
    c.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: GRIS } }; c.border = BORDES
  })
  f++
  ;[totHH_H, totHH_M, totDot_H, totDot_M].forEach((v, i) => {
    const c = ws.getCell(f, i + 3); c.value = v; c.font = { bold: true }; c.border = BORDES
  })
  f += 2

  ws.mergeCells(f, 1, f, 7)
  ws.getCell(f, 1).value = `ESTADÍSTICAS DE ACCIDENTABILIDAD ${anio}`
  ws.getCell(f, 1).font = { bold: true, size: 12, color: { argb: 'FFFFFFFF' } }
  ws.getCell(f, 1).fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: AZUL } }
  ws.getCell(f, 1).alignment = { horizontal: 'center' }
  f++
  const encAcc = ['Indicador', 'Detalle', '', 'Mes', 'Acumulado']
  encAcc.forEach((h, i) => {
    if (!h) return
    const c = ws.getCell(f, i + 1); c.value = h; c.font = { bold: true, size: 9 }
    c.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: GRIS } }; c.border = BORDES
  })
  f++
  const hhMes = totHH_H + totHH_M || Number(indicadores?.hh_total ?? 0)
  const ind = indicadores
  const filasAcc: Array<[string, string, number | string, number | string]> = [
    ['Horas hombre trabajadas', '', hhMes, Number(ind?.acum_hh ?? '') || ''],
    ['Total trabajadores', '', (ind?.dotacion_total ?? totDot_H + totDot_M) || 0, ''],
    ['Días perdidos', '', ind?.dias_perdidos ?? 0, ind?.acum_dias_perdidos ?? ''],
    ['Fatalidades', '', 0, ''],
    ['Casos con tiempo perdido (CTP)', 'Evento que origina licencia médica', ind?.accidentes_ctp ?? 0, ind?.acum_ctp ?? ''],
    ['Enfermedad ocupacional', 'Evento que origina licencia médica', ind?.enfermedades_prof ?? 0, ''],
    ['Tasa de frecuencia', 'TF = N° CTP x 1.000.000 / HH trabajadas', Number(ind?.indice_frecuencia ?? 0), Number(ind?.acum_indice_frecuencia ?? '') || ''],
    ['Tasa de accidentabilidad', 'TA = N° CTP x 100 / Prom trabajadores', Number(ind?.tasa_accidentabilidad ?? 0), ''],
    ['Tasa de siniestralidad', 'TST = TSIT + TSIM', '', ''],
    ['Tasa de gravedad', 'TG = N° Días Perdidos x 1.000.000 / HH Trabajadas', Number(ind?.indice_gravedad ?? 0), Number(ind?.acum_indice_gravedad ?? '') || ''],
  ]
  for (const [a, b, m, ac] of filasAcc) {
    ws.getCell(f, 1).value = a; ws.getCell(f, 1).font = { size: 9 }
    ws.mergeCells(f, 2, f, 3)
    ws.getCell(f, 2).value = b; ws.getCell(f, 2).font = { size: 8, italic: true }
    ws.getCell(f, 4).value = m as any; ws.getCell(f, 5).value = ac as any
    for (const c of [1, 2, 4, 5]) ws.getCell(f, c).border = BORDES
    f++
  }
  f += 2
  ws.getCell(f, 2).value = 'Nombre reportador:'; ws.getCell(f, 3).value = exp.nombre ?? ''
  f += 2
  ws.getCell(f, 2).value = 'Cargo reportador:'; ws.getCell(f, 3).value = exp.cargo ?? ''

  return xlsxBlob(wb)
}

// ── Franke 4.4: Reporte de insumos mensual (SGA-MLC-24) ─────────────────────

export async function generarFrankeInsumosExcel(params: {
  config: FaenaConfigDatos
  detalle: AmbientalRegistroDetalle[]   // registros ambientales del mes
  anio: number
  mes: number
}): Promise<Blob> {
  const { config, detalle, anio, mes } = params
  const con = config.contrato ?? {}
  const emp = config.empresa ?? {}

  const insumos = new Map<string, number>()
  for (const r of detalle.filter((d) => d.grupo === 'insumo')) {
    insumos.set(r.codigo, (insumos.get(r.codigo) ?? 0) + r.cantidad)
  }

  const wb = new ExcelJS.Workbook()
  const ws = wb.addWorksheet('Hoja1')
  ws.columns = [{ width: 34 }, { width: 22 }, { width: 26 }, { width: 20 }]

  let f = 1
  ws.mergeCells(f, 1, f, 3)
  ws.getCell(f, 1).value = 'REPORTE DE INSUMOS MENSUAL EECC'
  ws.getCell(f, 1).font = { bold: true, size: 13 }
  ws.getCell(f, 4).value = MESES[mes - 1]
  ws.getCell(f, 4).font = { bold: true, size: 12 }
  f += 2
  ws.getCell(f, 1).value = 'COD: SGA-MLC-24'
  ws.getCell(f, 2).value = 'Versión: 0'
  ws.getCell(f, 3).value = `Fecha de reporte: ${new Date().toLocaleDateString('es-CL')}`
  ws.getRow(f).font = { size: 9 }
  f += 2

  const sec = (t: string) => {
    ws.mergeCells(f, 1, f, 4)
    const c = ws.getCell(f, 1)
    c.value = t; c.font = { bold: true, size: 10, color: { argb: 'FFFFFFFF' } }
    c.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: AZUL } }
    f++
  }
  const par = (a: string, b: string, c2?: string, d?: string) => {
    ws.getCell(f, 1).value = a; ws.getCell(f, 2).value = b
    if (c2 !== undefined) { ws.getCell(f, 3).value = c2; ws.getCell(f, 4).value = d ?? '' }
    for (const c of [1, 2, 3, 4]) ws.getCell(f, c).border = BORDES
    ws.getCell(f, 1).font = { size: 9 }; ws.getCell(f, 3).font = { size: 9 }
    ws.getCell(f, 2).font = { size: 9, bold: true }; ws.getCell(f, 4).font = { size: 9, bold: true }
    f++
  }

  sec('I. Antecedentes Empresa Contratista')
  par('Nombre empresa', `: ${emp.razon_social ?? ''}`, 'Fecha de inicio de contrato', `: ${con.inicio ?? ''}`)
  par('Nombre Contrato', ': Servicio de abastecimiento de combustible', 'Fecha de término de contrato', `: ${con.vigencia ?? ''}`)
  par('N° Contrato', `: ${con.numero ?? ''}`, 'Número de trabajadores', ': ')
  par('Administrador de contrato EECC', `: ${con.administrador ?? ''}`, 'Faena a la que pertenece', `: ${config.faena_nombre ?? 'Franke'}`)
  par('Administrador de contrato MLC', `: ${con.operador_mandante ?? con.admin_mandante ?? ''}`, 'Ubicación Instalación de Faena', ': Patio de contratistas')

  // I..VII en el orden del formato (los códigos vienen del catálogo MIG554)
  const ORDEN: Array<[string, string, string]> = [
    ['AGUA_POTABLE', 'I. Consumo de agua potable', 'Litros'],
    ['COMBUSTIBLE', 'II. Consumo de combustible', 'Litros'],
    ['RES_IND_NP', 'III. Generación de residuos industriales no peligrosos', 'Mt3'],
    ['RES_PEL', 'IV. Generación de residuos peligrosos', 'Mt3'],
    ['RES_DOM', 'V. Generación de residuos asimilables a domésticos', 'Mt3'],
    ['RES_PLAST', 'VI. Generación de residuos plásticos (reciclables)', 'Mt3'],
    ['AGUA_IND', 'VII. Consumo de agua industrial (riego)', 'Litros'],
  ]
  for (const [codigo, titulo, unidad] of ORDEN) {
    sec(titulo)
    const v = insumos.get(codigo)
    par('Cantidad', `: ${v === undefined ? 'SIN REPORTE' : v}`, 'Unidad de medida', `: ${unidad}`)
  }

  sec('VIII. Registro de firma')
  f += 2
  ws.getCell(f, 1).value = `   ${con.administrador ?? ''}`
  f += 2
  ws.getCell(f, 1).value = 'Firma y fecha Administrador Contrato EE.CC.'
  ws.getCell(f, 3).value = 'Firma y fecha Superintendencia MLC'
  ws.getRow(f).font = { size: 9, bold: true }

  return xlsxBlob(wb)
}

// ── Franke 4.5: Registro de retiro de residuos ──────────────────────────────

const CATEGORIAS_45 = ['DOMESTICO', 'INDUSTRIAL', 'PELIGROSO', 'BOTELLAS', 'ACEITE', 'FILTROS']
const NOMBRES_45: Record<string, string> = {
  DOMESTICO: 'Doméstico', INDUSTRIAL: 'Industrial', PELIGROSO: 'Peligroso',
  BOTELLAS: 'Botellas Plásticas', ACEITE: 'Aceite usado', FILTROS: 'Filtros usados',
}

export async function generarFrankeResiduosExcel(params: {
  config: FaenaConfigDatos
  detalle: AmbientalRegistroDetalle[]
  anio: number
  mes: number
}): Promise<Blob> {
  const { config, detalle, anio, mes } = params
  const emp = config.empresa ?? {}

  // Un bloque por fecha de retiro reportada.
  const retiros = detalle.filter((d) => d.grupo === 'residuo_retiro')
  const fechas = Array.from(new Set(retiros.map((r) => r.fecha))).sort()
  const porFecha = new Map<string, Map<string, number>>()
  const total = new Map<string, number>()
  for (const r of retiros) {
    if (!porFecha.has(r.fecha)) porFecha.set(r.fecha, new Map())
    porFecha.get(r.fecha)!.set(r.codigo, (porFecha.get(r.fecha)!.get(r.codigo) ?? 0) + r.cantidad)
    total.set(r.codigo, (total.get(r.codigo) ?? 0) + r.cantidad)
  }

  const wb = new ExcelJS.Workbook()
  const ws = wb.addWorksheet('Hoja1')
  ws.columns = Array.from({ length: 10 }, (_, i) => ({ width: i % 3 === 0 ? 20 : 14 }))

  let f = 1
  ws.mergeCells(f, 1, f, 9)
  ws.getCell(f, 1).value = `REGISTRO DE RETIRO DE RESIDUOS ${anio}`
  ws.getCell(f, 1).font = { bold: true, size: 13 }
  ws.getCell(f, 1).alignment = { horizontal: 'center' }
  f += 2
  const cab: Array<[string, string]> = [
    ['Nombre empresa', emp.razon_social ?? ''],
    ['Mes', MESES[mes - 1]],
    ['Faena', config.faena_nombre ?? 'SCM Franke'],
    ['Empresa Retira', 'Amffal'],
  ]
  for (const [k, v] of cab) {
    ws.getCell(f, 1).value = k; ws.getCell(f, 1).font = { bold: true, size: 9 }
    ws.getCell(f, 2).value = v; ws.getCell(f, 2).font = { size: 9 }
    f++
  }
  f++

  // Bloques de a 3 por fila de bloques + el TOTAL MES al final.
  const bloques: Array<{ titulo: string; datos: Map<string, number> | null }> =
    fechas.map((fe) => ({ titulo: `Fecha: ${fe}`, datos: porFecha.get(fe)! }))
  bloques.push({ titulo: 'TOTAL MES', datos: total })

  for (let b = 0; b < bloques.length; b += 3) {
    const grupo = bloques.slice(b, b + 3)
    grupo.forEach((blq, gi) => {
      const col = 1 + gi * 3
      ws.getCell(f, col).value = blq.titulo
      ws.getCell(f, col).font = { bold: true, size: 9 }
      ws.getCell(f + 1, col).value = 'Detalle del residuo'
      ws.getCell(f + 1, col + 1).value = 'Volumen Mt3'
      for (const c of [col, col + 1]) {
        ws.getCell(f + 1, c).font = { bold: true, size: 9 }
        ws.getCell(f + 1, c).fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: GRIS } }
        ws.getCell(f + 1, c).border = BORDES
      }
      CATEGORIAS_45.forEach((cat, i) => {
        ws.getCell(f + 2 + i, col).value = NOMBRES_45[cat]
        ws.getCell(f + 2 + i, col + 1).value = blq.datos?.get(cat) ?? 0
        ws.getCell(f + 2 + i, col).border = BORDES
        ws.getCell(f + 2 + i, col + 1).border = BORDES
        ws.getCell(f + 2 + i, col).font = { size: 9 }
      })
      ws.getCell(f + 2 + CATEGORIAS_45.length, col).value = 'Firma'
      ws.getCell(f + 2 + CATEGORIAS_45.length, col).font = { size: 9, italic: true }
    })
    f += 2 + CATEGORIAS_45.length + 2
  }

  if (!fechas.length) {
    ws.getCell(f, 1).value = 'Sin retiros reportados este mes (el supervisor los carga en «Residuos e insumos»).'
    ws.getCell(f, 1).font = { italic: true, size: 9 }
  }

  return xlsxBlob(wb)
}
