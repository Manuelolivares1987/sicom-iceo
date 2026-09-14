// ============================================================================
// Hoja de datos para el E-200 SERNAGEOMIN (MIG547)
// ----------------------------------------------------------------------------
// OJO (Manuel, 2026-09-14): el E-200 es un formulario DEL GOBIERNO y se
// presenta tal cual — en SIMIN o en el formato oficial. SICOM NO genera un
// E-200: genera esta HOJA DE DATOS con todo lo que el formulario pide
// (secciones 1 a 7, en su mismo orden), para que quien declara transcriba a
// SIMIN sin andar juntando dotación, HH y coordenadas a mano. El comprobante
// oficial de SIMIN es lo que se adjunta después como respaldo de la entrega.
// ============================================================================

import ExcelJS from 'exceljs'
import type { FaenaConfigDatos, IndicadoresFila } from '@/lib/services/prevencion-reportabilidad'

const MESES = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio',
  'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre']

const AZUL = 'FF1F4E78'
const GRIS = 'FFF2F2F2'

export async function generarE200Excel(params: {
  config: FaenaConfigDatos
  indicadores: IndicadoresFila | null
  anio: number
  mes: number
  faenaNombre: string
}): Promise<Blob> {
  const { config, indicadores, anio, mes } = params
  const emp = config.empresa ?? {}
  const man = config.mandante ?? {}
  const inst = config.instalacion ?? {}
  const exp = config.experto ?? {}

  const wb = new ExcelJS.Workbook()
  wb.creator = 'SICOM — Pillado Empresas'
  const ws = wb.addWorksheet('E-200', {
    pageSetup: { paperSize: 9, orientation: 'portrait', fitToPage: true, fitToWidth: 1, fitToHeight: 0 },
  })
  ws.columns = [{ width: 22 }, { width: 20 }, { width: 20 }, { width: 20 }, { width: 20 }, { width: 20 }]

  let fila = 1
  const titulo = (texto: string) => {
    ws.mergeCells(fila, 1, fila, 6)
    const c = ws.getCell(fila, 1)
    c.value = texto
    c.font = { bold: true, color: { argb: 'FFFFFFFF' }, size: 11 }
    c.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: AZUL } }
    c.alignment = { horizontal: 'left' }
    fila++
  }
  const par = (pares: Array<[string, string | number | null | undefined]>) => {
    let col = 1
    for (const [k, v] of pares) {
      const ck = ws.getCell(fila, col)
      ck.value = k
      ck.font = { bold: true, size: 9 }
      ck.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: GRIS } }
      const cv = ws.getCell(fila, col + 1)
      cv.value = v ?? ''
      cv.font = { size: 9 }
      col += 2
      if (col > 6) { col = 1; fila++ }
    }
    if (col !== 1) fila++
  }
  const espacio = () => { fila++ }

  // ── Cabecera ──
  ws.mergeCells(fila, 1, fila, 6)
  ws.getCell(fila, 1).value = 'HOJA DE DATOS — FORMULARIO E-200 SERNAGEOMIN'
  ws.getCell(fila, 1).font = { bold: true, size: 14 }
  ws.getCell(fila, 1).alignment = { horizontal: 'center' }
  fila++
  ws.mergeCells(fila, 1, fila, 6)
  ws.getCell(fila, 1).value =
    'NO ES EL FORMULARIO OFICIAL: la declaración se hace en SIMIN (o en el formato oficial del Servicio) ' +
    'transcribiendo estos datos. Se declara todos los meses aunque no haya accidentes (DS 132 art. 36).'
  ws.getCell(fila, 1).font = { italic: true, bold: true, size: 9, color: { argb: 'FFC00000' } }
  ws.getCell(fila, 1).alignment = { horizontal: 'center', wrapText: true }
  ws.getRow(fila).height = 26
  fila += 2

  // ── 1. Empresa contratista ──
  titulo('1. IDENTIFICACIÓN DE LA EMPRESA CONTRATISTA')
  par([['Mes informado', `${MESES[mes - 1]} de ${anio}`]])
  par([['RUT', emp.rut], ['Razón social', emp.razon_social], ['Categoría', emp.categoria]])
  par([['Nombre de fantasía', emp.nombre_fantasia], ['Dirección', emp.direccion], ['Región', emp.region]])
  par([['Provincia', emp.provincia], ['Comuna', emp.comuna], ['Teléfono', emp.telefono]])
  par([['E-mail', emp.email]])
  par([['Representante legal', emp.rep_legal], ['RUT rep. legal', emp.rep_legal_rut]])
  par([['Teléfono rep. legal', emp.rep_legal_telefono], ['E-mail rep. legal', emp.rep_legal_email]])
  espacio()

  // ── 2. Mandante ──
  titulo('2. IDENTIFICACIÓN DE LA EMPRESA MANDANTE')
  par([['RUT mandante', man.rut], ['Razón social', man.razon_social]])
  par([['Nombre de fantasía', man.nombre_fantasia], ['Región', man.region]])
  espacio()

  // ── 3. Faena ──
  titulo('3. IDENTIFICACIÓN DE LA FAENA DE LA EMPRESA MANDANTE')
  par([['Nombre de la faena', config.faena_nombre || params.faenaNombre]])
  espacio()

  // ── 4. Instalación + dotación/HH ──
  titulo('4. IDENTIFICACIÓN DE LAS INSTALACIONES A DECLARAR')
  par([['Instalación', inst.nombre], ['Estado', inst.estado], ['Tipo', inst.tipo]])
  par([['Región', inst.region], ['Provincia', inst.provincia], ['Comuna', inst.comuna]])
  par([['Datum', inst.datum], ['Huso', inst.huso], ['Cota (m.s.n.m.)', inst.cota]])
  par([['Coordenada Norte', inst.coord_norte], ['Coordenada Este', inst.coord_este]])
  espacio()

  const sinDatos = !indicadores
  par([
    ['Hombres — Dotación', sinDatos ? 'SIN CARGAR' : indicadores!.dotacion_hombres],
    ['Hombres — HH', sinDatos ? 'SIN CARGAR' : Number(indicadores!.hh_hombres)],
  ])
  par([
    ['Mujeres — Dotación', sinDatos ? 'SIN CARGAR' : indicadores!.dotacion_mujeres],
    ['Mujeres — HH', sinDatos ? 'SIN CARGAR' : Number(indicadores!.hh_mujeres)],
  ])
  par([['Subcontratistas', 'Sin subcontratos (completar si aplica)']])
  espacio()

  // ── 5. Accidentes ──
  titulo('5. DESCRIPCIÓN DE ACCIDENTES')
  const ctp = indicadores?.accidentes_ctp ?? 0
  if (ctp === 0) {
    ws.mergeCells(fila, 1, fila, 6)
    ws.getCell(fila, 1).value = 'SIN ACCIDENTES CON TIEMPO PERDIDO EN EL MES.'
    ws.getCell(fila, 1).font = { bold: true, size: 10 }
    fila++
  } else {
    ws.mergeCells(fila, 1, fila, 6)
    ws.getCell(fila, 1).value =
      `⚠ El mes registra ${ctp} accidente(s) CTP y ${indicadores?.dias_perdidos ?? 0} días perdidos. ` +
      'Completar en SIMIN el detalle por accidentado (agente, tipo, parte del cuerpo, mutual).'
    ws.getCell(fila, 1).font = { bold: true, size: 10, color: { argb: 'FFC00000' } }
    ws.getCell(fila, 1).alignment = { wrapText: true }
    ws.getRow(fila).height = 30
    fila++
  }
  espacio()

  // ── 6/7. Arrastres + experto ──
  titulo('6. ADMINISTRAR ARRASTRES (accidentes de meses anteriores)')
  par([['Arrastres', 'Sin arrastres (completar si aplica)']])
  espacio()

  titulo('7. EXPERTO EN SEGURIDAD MINERA CONTRATISTA')
  par([['Nombre', exp.nombre], ['RUN', exp.run], ['Registro SNGM', exp.registro_sngm]])
  par([['Cargo', exp.cargo], ['Teléfono', exp.telefono], ['E-mail', exp.email]])
  par([['Fecha', new Date().toLocaleDateString('es-CL')]])
  espacio()

  ws.mergeCells(fila, 1, fila, 6)
  ws.getCell(fila, 1).value =
    'Declarar en SIMIN [http://simin.sernageomin.cl/simin/] transcribiendo estos datos al formulario oficial. ' +
    'Hoja generada por SICOM desde los indicadores del mes — revisar antes de declarar y adjuntar el comprobante SIMIN como respaldo.'
  ws.getCell(fila, 1).font = { italic: true, size: 8, color: { argb: 'FF666666' } }
  ws.getCell(fila, 1).alignment = { wrapText: true }

  const buffer = await wb.xlsx.writeBuffer()
  return new Blob([buffer], {
    type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  })
}
