// ============================================================================
// Formulario E-200 SERNAGEOMIN (MIG547, corregido)
// ----------------------------------------------------------------------------
// Manuel (2026-09-14): «sí se debe replicar el formulario E-200 del Gobierno,
// debe ser el mismo porque es estatal». Réplica FIEL del formulario oficial
// (transcrito del E-200 real de Franke agosto 2026): mismas secciones 1 a 8,
// mismos textos, mismas listas de casilleros (agente, tipo de accidente,
// actos inseguros, condición peligrosa, parte del cuerpo) para marcar con X.
// Lo que SICOM sabe se llena solo (empresa, mandante, instalación, dotación,
// HH, experto); el detalle de un accidente —si lo hubiera— se marca a mano,
// igual que en el formulario de papel.
// ============================================================================

import ExcelJS from 'exceljs'
import type { FaenaConfigDatos, IndicadoresFila } from '@/lib/services/prevencion-reportabilidad'

const MESES = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio',
  'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre']

// ── Listas oficiales del formulario (transcritas tal cual) ──────────────────

const AGENTE_ACCIDENTE: Array<[string, string]> = [
  ['Aparatos de transmisión de energía', 'Excavaciones, zanjas y túneles'],
  ['Aparatos eléctricos', 'Explosivo'],
  ['Caída de objetos', 'Herramientas de mano'],
  ['Caída de roca', 'Maquinas'],
  ['Deslizamiento de roca, barro, nieve, etc.', 'Productos y compuestos químicos'],
  ['Equipo de levante', 'Recipientes a presión'],
  ['Escalas', 'Transportadores'],
]

const TIPO_ACCIDENTE: Array<[string, string]> = [
  ['Apretada en, bajo y entre.', 'Contacto con radiaciones, sustancias toxicas y Venenosas.'],
  ['Caída de personas de diferente nivel.', 'Golpeado por o contra.'],
  ['Caída de personas en el mismo nivel.', 'Proyección de partículas.'],
  ['Contacto con corriente eléctrica.', 'Sobreesfuerzo.'],
  ['Contacto con extremo de temperatura.', 'Contacto con combustible (Petróleo)'],
]

const ACTOS_INSEGUROS: Array<[string, string]> = [
  ['Actuar sin orden o desobedecer a éstas', 'Neutralizar la operación de dispositivos de seguridad'],
  ['Bromas, jugarretas', 'No asegurar ni advertir el peligro'],
  ['Colocar, mezclar o combinar, etc en forma insegura', 'No usar equipo de protección disponible'],
  ['Colocarse en posición o postura peligrosa', 'Operar o trabajar a velocidades inseguras'],
  ['Empleo inadecuado de las manos o de las partes del cuerpo', 'Usar equipo inseguro'],
  ['Error en la conducción', 'Usar vestuario personal inseguro'],
  ['Falta de atención a superficies de apoyo o alrededores', 'Uso inadecuado de equipo'],
  ['Limpiar, aceitar, ajustar o reparar equipo en movimiento.', ''],
]

const CONDICION_PELIGROSA: Array<[string, string]> = [
  ['Agentes biológicos', 'Limpieza y orden deficiente'],
  ['Atmósfera contaminante', 'Métodos o procedimientos peligrosos'],
  ['Defecto de equipo', 'Radiación'],
  ['Defecto de las herramientas', 'Riesgos de colocación'],
  ['Defecto de materiales', 'Riesgos por la vestimenta'],
  ['Falta de resguardo o defensa inadecuada', 'Ruidos molestos'],
  ['Falta o fortificación inadecuada', 'Sustancias tóxicas'],
  ['Falta o insuficiencia de entrenamiento', 'Temperatura extrema'],
  ['Iluminación deficiente', ''],
]

const PARTE_CUERPO: Array<[string, string, string, string]> = [
  ['Brazos', 'Dedos', 'Ortejos', 'pies'],
  ['Cara y cuello', 'Manos', 'Partes múltiples', 'Tronco'],
  ['Cráneo', 'Ojos', 'Piernas', ''],
]

const OTRAS_INFORMACIONES =
  'El punto 4, debe ser llenado para cada una de las instalaciones en que la Empresa Contratista preste ' +
  'servicios o realice trabajos, en caso de que existiese un accidente en dicha instalación se debe completar ' +
  'por cada accidentado el punto 5.\n\n' +
  'Este documento debe ser enviado al sistema computacional del servicio Nacional de Geología y Minería ' +
  'denominado SIMIN en la siguiente URL [http://simin.sernageomin.cl/simin/].\n\n' +
  'En caso de no disponer de un sistema computacional el documento debe ser enviado a la Dirección Regional ' +
  'del Servicio que le corresponda, informando del hecho a la Empresa Mandante.\n\n' +
  'El documento debe ser completado con letra clara y sin enmiendas u errores.\n\n' +
  'En conformidad con el Artículo 36 del Reglamento de Seguridad Minera, los productores mineros y ' +
  'compradores de minerales, y de productos beneficiados deberán confeccionar mensualmente las informaciones ' +
  'estadísticas de producción, compras y accidentes en los formularios establecidos por el Servicio.'

// ─────────────────────────────────────────────────────────────────────────────

const NEGRO = 'FF000000'
const GRISCLARO = 'FFF2F2F2'

/** Separa "77.316.540-8" en ["77.316.540", "8"] como lo pide el formulario. */
function rutPartes(rut?: string): [string, string] {
  if (!rut) return ['', '']
  const limpio = rut.trim()
  const idx = limpio.lastIndexOf('-')
  if (idx < 0) return [limpio, '']
  return [limpio.slice(0, idx), limpio.slice(idx + 1)]
}

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
  const mutual = (config.mutual as string) ?? ''

  const wb = new ExcelJS.Workbook()
  wb.creator = 'Pillado y Cía. Ltda.'
  const ws = wb.addWorksheet('E-200', {
    pageSetup: { paperSize: 9, orientation: 'portrait', fitToPage: true, fitToWidth: 1, fitToHeight: 0 },
  })
  // 10 columnas angostas: las listas van [texto | X | texto | X] y los datos
  // en pares etiqueta/valor. Ancho total ≈ una hoja carta.
  ws.columns = [
    { width: 24 }, { width: 12 }, { width: 12 }, { width: 4 },
    { width: 22 }, { width: 12 }, { width: 12 }, { width: 4 },
    { width: 14 }, { width: 4 },
  ]

  let f = 1
  const bordeFino = { style: 'thin' as const, color: { argb: NEGRO } }
  const bordes = { top: bordeFino, left: bordeFino, bottom: bordeFino, right: bordeFino }

  const seccion = (texto: string) => {
    ws.mergeCells(f, 1, f, 10)
    const c = ws.getCell(f, 1)
    c.value = texto
    c.font = { bold: true, size: 10 }
    c.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: GRISCLARO } }
    c.border = bordes
    f++
  }

  // Fila de pares etiqueta/valor. `pares` = [[etiqueta, valor, colSpanValor?]]
  const filaDatos = (pares: Array<[string, string | number]>, anchoPar = 2) => {
    let col = 1
    for (const [k, v] of pares) {
      const ck = ws.getCell(f, col)
      ck.value = k
      ck.font = { size: 8 }
      ck.border = bordes
      const c1 = col + 1
      const c2 = Math.min(col + anchoPar, 10)
      if (c2 > c1) ws.mergeCells(f, c1, f, c2)
      const cv = ws.getCell(f, c1)
      cv.value = v
      cv.font = { bold: true, size: 9 }
      cv.border = bordes
      col = c2 + 1
      if (col > 10) break
    }
    f++
  }

  const listaConX = (titulo: string, filas: Array<[string, string]>, nota: string) => {
    ws.mergeCells(f, 1, f, 10)
    const c = ws.getCell(f, 1)
    c.value = `${titulo}   ${nota}`
    c.font = { bold: true, size: 8 }
    c.border = bordes
    c.alignment = { wrapText: true }
    f++
    for (const [izq, der] of filas) {
      ws.mergeCells(f, 1, f, 3)
      const ci = ws.getCell(f, 1)
      ci.value = izq
      ci.font = { size: 8 }
      ci.border = bordes
      ws.getCell(f, 4).border = bordes           // casillero X izquierdo
      ws.mergeCells(f, 5, f, 7)
      const cd = ws.getCell(f, 5)
      cd.value = der
      cd.font = { size: 8 }
      cd.border = bordes
      ws.mergeCells(f, 8, f, 10)
      ws.getCell(f, 8).border = bordes           // casillero X derecho
      f++
    }
  }

  const bloqueAccidentado = (n: 1 | 2) => {
    ws.mergeCells(f, 1, f, 10)
    const t = ws.getCell(f, 1)
    t.value = `Datos Accidentado ${n}`
    t.font = { bold: true, size: 9 }
    t.border = bordes
    f++
    filaDatos([['Rut', ''], ['Nombre Completo', '']], 3)
    filaDatos([['Género', ''], ['Edad (Años)', ''], ['Cargo', '']])
    filaDatos([['Experiencia en el cargo (Meses)', ''], ['Experiencia en la Minería (Meses)', '']], 3)
    ws.mergeCells(f, 1, f, 10)
    ws.getCell(f, 1).value = 'Marque con "X" la Mutual al cual la Empresa está adherida.'
    ws.getCell(f, 1).font = { italic: true, size: 8 }
    ws.getCell(f, 1).border = bordes
    f++
    filaDatos([
      ['ACHS', mutual === 'ACHS' ? 'X' : ''],
      ['Mutual C.CH.C.', mutual === 'Mutual C.CH.C.' ? 'X' : ''],
      ['IST', mutual === 'IST' ? 'X' : ''],
      ['INP', mutual === 'INP' ? 'X' : ''],
    ], 1)

    ws.mergeCells(f, 1, f, 10)
    const d = ws.getCell(f, 1)
    d.value = `Detalle Accidente ${n}`
    d.font = { bold: true, size: 9 }
    d.border = bordes
    f++
    filaDatos([['Fecha Accidente', ''], ['Hora', ''], ['Gravedad', ''], ['Días Perdidos', '']], 1)
    listaConX('AGENTE DEL ACCIDENTE.', AGENTE_ACCIDENTE,
      'Identifica el objeto marcando con una "X", sustancia o alrededor del cual existía condición peligrosa.')
    listaConX('TIPO DE ACCIDENTE.', TIPO_ACCIDENTE,
      'Identifica el evento que directamente dio como resultado la lesión.')
    listaConX('ACTOS INSEGUROS.', ACTOS_INSEGUROS,
      'Identificar la violación de un procedimiento seguro generalmente aceptado, que directamente permitió la ocurrencia del tipo de accidente.')
    listaConX('CONDICIÓN PELIGROSA.', CONDICION_PELIGROSA,
      'Es la condición que pudo haberse controlado para evitar la ocurrencia del accidente.')

    ws.mergeCells(f, 1, f, 10)
    const p = ws.getCell(f, 1)
    p.value = 'PARTE DEL CUERPO LESIONADO.   Identifica la parte del cuerpo marcando con una "X"'
    p.font = { bold: true, size: 8 }
    p.border = bordes
    f++
    for (const partes of PARTE_CUERPO) {
      const cols = [[1, 2], [3, 4], [5, 6], [7, 8]] as const
      partes.forEach((texto, i) => {
        const [cTxt, cX] = cols[i]
        if (cTxt === 1) ws.mergeCells(f, 1, f, 1)
        const ct = ws.getCell(f, cTxt)
        ct.value = texto
        ct.font = { size: 8 }
        ct.border = bordes
        ws.getCell(f, cX).border = bordes
      })
      ws.mergeCells(f, 9, f, 10)
      ws.getCell(f, 9).border = bordes
      f++
    }
  }

  // ══ CABECERA OFICIAL ══
  ws.mergeCells(f, 1, f, 10)
  ws.getCell(f, 1).value = 'DECLARACIÓN DE ACCIDENTABILIDAD AL SERNAGEOMIN'
  ws.getCell(f, 1).font = { bold: true, size: 13 }
  ws.getCell(f, 1).alignment = { horizontal: 'center' }
  ws.getCell(f, 1).border = bordes
  f++
  ws.mergeCells(f, 1, f, 10)
  ws.getCell(f, 1).value = 'ACCIDENTES DE EMPRESAS CONTRATISTAS Y SUBCONTRATISTAS'
  ws.getCell(f, 1).font = { bold: true, size: 11 }
  ws.getCell(f, 1).alignment = { horizontal: 'center' }
  ws.getCell(f, 1).border = bordes
  f++
  ws.mergeCells(f, 1, f, 10)
  ws.getCell(f, 1).value =
    'Este formulario debe ser respondido todos los meses aunque no se registren accidentes, entregando un ' +
    'por cada instalación que posea la faena.'
  ws.getCell(f, 1).font = { size: 8, italic: true }
  ws.getCell(f, 1).alignment = { horizontal: 'center', wrapText: true }
  ws.getCell(f, 1).border = bordes
  f += 2

  // ══ 1. EMPRESA CONTRATISTA ══
  const [rutEmp, dvEmp] = rutPartes(emp.rut)
  const [rutRep, dvRep] = rutPartes(emp.rep_legal_rut)
  seccion('1. IDENTIFICACIÓN DE LA EMPRESA CONTRATISTA')
  filaDatos([['Mes al cual se refiere la información:', `${MESES[mes - 1]} de ${anio}`]], 4)
  filaDatos([['RUT', `${rutEmp}  ${dvEmp}`], ['Nombre del dueño o razón social', emp.razon_social ?? '']], 3)
  filaDatos([['Categoría de Empresa', emp.categoria ?? ''], ['Nombre de fantasía de Empresa', emp.nombre_fantasia ?? '']], 3)
  filaDatos([['Dirección — Calle y Número', emp.direccion ?? ''], ['Región', emp.region ?? '']], 3)
  filaDatos([['Provincia', emp.provincia ?? ''], ['Comuna', emp.comuna ?? ''], ['Teléfono', emp.telefono ?? '']])
  filaDatos([['e-mail', emp.email ?? '']], 4)
  filaDatos([['Representante Legal', emp.rep_legal ?? ''], ['RUT', `${rutRep}  ${dvRep}`]], 3)
  filaDatos([['Teléfono Representante Legal', emp.rep_legal_telefono ?? ''], ['e-mail Representante Legal', emp.rep_legal_email ?? '']], 3)
  f++

  // ══ 2. MANDANTE ══
  const [rutMan, dvMan] = rutPartes(man.rut)
  seccion('2. IDENTIFICACIÓN DE LA EMPRESA MANDANTE EN QUE PRESTA SERVICIOS EL CONTRATISTA')
  filaDatos([['RUT de la Empresa Mandante', `${rutMan}  ${dvMan}`], ['Nombre del dueño o razón social', man.razon_social ?? '']], 3)
  filaDatos([['Región', man.region ?? ''], ['Nombre de fantasía de Empresa', man.nombre_fantasia ?? '']], 3)
  f++

  // ══ 3. FAENA ══
  seccion('3. IDENTIFICACIÓN DE LA FAENA DE LA EMPRESA MANDANTE')
  filaDatos([['Nombre de la faena', config.faena_nombre || params.faenaNombre]], 6)
  f++

  // ══ 4. INSTALACIONES ══
  seccion('4. IDENTIFICACIÓN DE LAS INSTALACIONES A DECLARAR')
  ws.mergeCells(f, 1, f, 10)
  ws.getCell(f, 1).value =
    '(Los datos solicitados se refieren a la instalación dentro de la faena, dentro de la cual se presta servicios)'
  ws.getCell(f, 1).font = { size: 8, italic: true }
  ws.getCell(f, 1).border = bordes
  f++
  filaDatos([['Nombre de la Instalación Minera', inst.nombre ?? ''], ['Estado de la Instalación', inst.estado ?? '']], 3)
  filaDatos([['Región', inst.region ?? ''], ['Provincia', inst.provincia ?? ''], ['Comuna', inst.comuna ?? ''], ['Tipo de Instalación', inst.tipo ?? '']], 1)
  filaDatos([['Datum', inst.datum ?? ''], ['Huso', inst.huso ?? ''], ['Cota (m.s.n.m.)', inst.cota ?? '']])
  filaDatos([['Coordenada Norte', inst.coord_norte ?? ''], ['Coordenada Este', inst.coord_este ?? '']], 3)
  filaDatos([
    ['Hombres Contratistas — Dotación (N°)', indicadores ? indicadores.dotacion_hombres : ''],
    ['HH', indicadores ? Number(indicadores.hh_hombres) : ''],
  ], 3)
  filaDatos([
    ['Mujeres Contratistas — Dotación (N°)', indicadores ? indicadores.dotacion_mujeres : ''],
    ['HH', indicadores ? Number(indicadores.hh_mujeres) : ''],
  ], 3)
  ws.mergeCells(f, 1, f, 10)
  ws.getCell(f, 1).value =
    'Número de Empresas Sub Contratistas (completar sólo en caso que la empresa contratista posea sub-contratos)'
  ws.getCell(f, 1).font = { size: 8 }
  ws.getCell(f, 1).border = bordes
  f++
  filaDatos([['Hombres Sub-Contratistas — Dotación (N°)', 0], ['HH', 0]], 3)
  filaDatos([['Mujeres Sub-Contratistas — Dotación (N°)', 0], ['HH', 0]], 3)
  f++

  // ══ 5. ACCIDENTES ══
  seccion('5.- DESCRIPCIÓN DE ACCIDENTES (Si existen accidentes completar lo siguiente, por cada accidentado durante el mes)')
  const ctp = indicadores?.accidentes_ctp ?? 0
  if (ctp > 0) {
    ws.mergeCells(f, 1, f, 10)
    ws.getCell(f, 1).value =
      `El mes registra ${ctp} accidente(s) CTP y ${indicadores?.dias_perdidos ?? 0} días perdidos según los ` +
      'indicadores de SICOM: completar el detalle por accidentado marcando los casilleros.'
    ws.getCell(f, 1).font = { bold: true, size: 8, color: { argb: 'FFC00000' } }
    ws.getCell(f, 1).alignment = { wrapText: true }
    ws.getCell(f, 1).border = bordes
    f++
  }
  bloqueAccidentado(1)
  f++
  bloqueAccidentado(2)
  f++

  // ══ 6. ARRASTRES ══
  seccion('6. ADMINISTRAR ARRASTRES. (accidentes originados de meses anteriores)')
  filaDatos([['Mes', ''], ['Año', '']], 3)
  for (const n of [1, 2]) {
    filaDatos([
      [`RUT Accidentado ${n}`, ''], ['Nombre Accidentado', ''], ['Fecha Accidente', ''],
    ])
    filaDatos([['Genero', ''], ['Gravedad', ''], ['Días Perdidos', '']])
  }
  f++

  // ══ 7. EXPERTO + 8. OTRAS INFORMACIONES ══
  seccion('7. EXPERTO SEGURIDAD MINERA CONTRATISTA')
  const [runExp, dvExp] = rutPartes(exp.run)
  filaDatos([['RUN', `${runExp}  ${dvExp}`], ['Registro SNGM', exp.registro_sngm ?? '']], 3)
  filaDatos([['Nombre', exp.nombre ?? '']], 6)
  filaDatos([['Cargo', exp.cargo ?? '']], 6)
  filaDatos([['Fecha', new Date().toLocaleDateString('es-CL')], ['Teléfono', exp.telefono ?? '']], 3)
  filaDatos([['email', exp.email ?? '']], 6)
  // Espacio de firma, como en el formulario.
  ws.mergeCells(f, 1, f + 3, 10)
  const firma = ws.getCell(f, 1)
  firma.value = '\n\n\nFirma y timbre de Empresa'
  firma.alignment = { horizontal: 'center', vertical: 'bottom', wrapText: true }
  firma.font = { size: 9 }
  firma.border = bordes
  f += 4
  f++

  seccion('8. OTRAS INFORMACIONES IMPORTANTES')
  ws.mergeCells(f, 1, f + 9, 10)
  const info = ws.getCell(f, 1)
  info.value = OTRAS_INFORMACIONES
  info.font = { size: 8 }
  info.alignment = { wrapText: true, vertical: 'top' }
  info.border = bordes
  f += 10

  const buffer = await wb.xlsx.writeBuffer()
  return new Blob([buffer], {
    type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  })
}
