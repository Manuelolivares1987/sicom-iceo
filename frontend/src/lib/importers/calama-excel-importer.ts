/**
 * Importer del Excel base de Operacion Calama (Carta Gantt VA 25_042 ...).
 *
 * SOLO LECTURA / PREVIEW. No inserta nada en Supabase.
 * Disenado defensivo: hojas faltantes -> advertencia (no error fatal).
 *
 * Hojas reconocidas (cualquier subconjunto):
 *   - "Detalle"            jerarquia zonas/actividades/subtareas + estado/fecha real
 *   - "Carta Gantt"        calendario diario plan/real ('x' = plan, 'R' = real)
 *   - "Analisi carta gantt" duplicado de Carta Gantt (se ignora)
 *   - "Itemizado materiale" listado de materiales con costos
 *   - "OBS."               porcentaje avance + observaciones por codigo
 *   - "Hoja1"              contactos por codigo (mandante/turno/telefono)
 */

import ExcelJS from 'exceljs'

// ============================================================================
// Tipos del preview
// ============================================================================

export type LineaNegocioCalama = 'combustibles' | 'lubricantes' | 'mejoras_civiles'

export type CalamaPreviewZona = {
  codigo: string
  nombre: string
  origen_hoja: string
}

export type CalamaPreviewTarea = {
  codigo: string
  nombre: string
  zona_codigo: string | null
  duracion_plan_dias: number | null
  duracion_real_dias: number | null
  fecha_inicio_plan: string | null
  fecha_fin_plan: string | null
  fecha_inicio_real: string | null
  fecha_fin_real: string | null
  ot_referencia: string | null
  verif: string | null
  avance_excel_pct: number | null
  origen_hoja: string
}

export type CalamaPreviewSubtarea = {
  codigo: string
  descripcion: string
  tarea_codigo: string | null
  estado: string | null
  fecha_real: string | null
  origen_hoja: string
}

export type CalamaPreviewMaterial = {
  actividad_relacionada: string | null
  descripcion: string
  unidad: string | null
  cantidad: number | null
  precio_clp: number | null
  valor_uf: number | null
  porcentaje: number | null
  observacion: string | null
  zona_codigo: string | null
  zona_nombre: string | null
  origen_hoja: string
}

export type CalamaPreviewContacto = {
  codigo_actividad: string | null
  descripcion: string
  telefono: string | null
  rol: string | null
  faena_sugerida: string | null
  origen_hoja: string
}

export type CalamaPreviewFechaPlan = {
  codigo_tarea: string
  nombre_tarea: string
  fecha_inicio_plan: string | null
  fecha_fin_plan: string | null
  duracion_dias: number | null
  origen_hoja: string
}

export type CalamaPreviewAvance = {
  codigo: string
  nombre: string
  avance_pct: number | null
  origen_hoja: string
}

export type CalamaPreviewObservacion = {
  codigo_relacionado: string | null
  texto: string
  origen_hoja: string
}

export type CalamaPreviewMapeoError = {
  hoja: string
  fila: number | null
  columna: string | null
  detalle: string
}

export type CalamaPreviewAdvertencia = {
  hoja: string | null
  detalle: string
}

export type CalamaImportPreview = {
  archivo: string
  hojas_detectadas: string[]
  faenas_detectadas: Array<{ codigo: string; nombre: string; razon: string }>
  lineas_negocio_detectadas: Array<{ codigo: LineaNegocioCalama; razon: string }>
  zonas_detectadas: CalamaPreviewZona[]
  tareas_detectadas: CalamaPreviewTarea[]
  subtareas_detectadas: CalamaPreviewSubtarea[]
  materiales_detectados: CalamaPreviewMaterial[]
  contactos_detectados: CalamaPreviewContacto[]
  fechas_planificadas_detectadas: CalamaPreviewFechaPlan[]
  avances_detectados: CalamaPreviewAvance[]
  observaciones_detectadas: CalamaPreviewObservacion[]
  errores_de_mapeo: CalamaPreviewMapeoError[]
  advertencias: CalamaPreviewAdvertencia[]
  resumen: {
    total_zonas: number
    total_tareas: number
    total_subtareas: number
    total_materiales: number
    total_contactos: number
    total_fechas: number
    total_observaciones: number
    total_advertencias: number
    total_errores: number
  }
}

// ============================================================================
// Helpers de celdas
// ============================================================================

type CellLike =
  | string
  | number
  | boolean
  | Date
  | null
  | undefined
  | { result?: unknown; text?: unknown; formula?: unknown }
  | { richText?: Array<{ text?: unknown }> }

function unwrapCell(v: unknown): unknown {
  if (v === null || v === undefined) return null
  if (typeof v === 'object') {
    const o = v as Record<string, unknown>
    if ('result' in o) return unwrapCell(o.result)
    if ('text' in o && typeof o.text !== 'object') return o.text
    if ('richText' in o && Array.isArray(o.richText)) {
      return (o.richText as Array<{ text?: unknown }>).map((r) => String(r.text ?? '')).join('')
    }
    if (v instanceof Date) return v
  }
  return v
}

function cellText(v: CellLike): string | null {
  const u = unwrapCell(v)
  if (u === null || u === undefined) return null
  if (u instanceof Date) return u.toISOString().slice(0, 10)
  const s = String(u).trim()
  return s.length > 0 ? s : null
}

function cellNum(v: CellLike): number | null {
  const u = unwrapCell(v)
  if (u === null || u === undefined || u === '') return null
  const n = typeof u === 'number' ? u : Number(String(u).replace(/[^\d.\-,]/g, '').replace(',', '.'))
  return Number.isFinite(n) ? n : null
}

function cellDate(v: CellLike): string | null {
  const u = unwrapCell(v)
  if (u instanceof Date) return u.toISOString().slice(0, 10)
  const s = cellText(v)
  if (!s) return null
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(s)
  if (m) return `${m[1]}-${m[2]}-${m[3]}`
  const m2 = /^(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{2,4})/.exec(s)
  if (m2) {
    const yyyy = m2[3].length === 2 ? `20${m2[3]}` : m2[3]
    const mm = m2[2].padStart(2, '0')
    const dd = m2[1].padStart(2, '0')
    return `${yyyy}-${mm}-${dd}`
  }
  return null
}

/**
 * Normaliza un porcentaje: acepta 0..1 (decimal), 0..100 (entero/decimal) o
 * string "50%". Devuelve numero entre 0 y 100, o null si no se puede.
 */
function cellPct(v: CellLike): number | null {
  const u = unwrapCell(v)
  if (u === null || u === undefined || u === '') return null
  let n: number
  if (typeof u === 'number') {
    n = u
  } else {
    const s = String(u).replace(/%/g, '').trim()
    if (!s) return null
    n = Number(s.replace(',', '.'))
  }
  if (!Number.isFinite(n)) return null
  // 0..1 -> escalar a 0..100
  if (n >= 0 && n <= 1) n = n * 100
  if (n < 0) n = 0
  if (n > 100) n = 100
  return Math.round(n * 10) / 10
}

function normTel(v: CellLike): string | null {
  const u = unwrapCell(v)
  if (u === null || u === undefined) return null
  const raw = typeof u === 'number' ? u.toFixed(0) : String(u)
  const digits = raw.replace(/[^\d]/g, '')
  if (!digits) return null
  return digits.length >= 9 ? `+${digits}` : digits
}

function readCell(ws: ExcelJS.Worksheet, row: number, col: number): unknown {
  return ws.getRow(row).getCell(col).value
}

// ============================================================================
// Sugerencias automaticas
// ============================================================================

const FAENA_HINTS: Array<{ codigo: string; nombre: string; patron: RegExp }> = [
  { codigo: 'CENTINELA', nombre: 'Minera Centinela', patron: /centinela|amsa|antofagasta minerals/i },
  { codigo: 'LOMAS_BAYAS', nombre: 'Lomas Bayas', patron: /lomas\s*bayas|glencore/i },
  { codigo: 'SPENCE', nombre: 'Spence (Pampa Norte)', patron: /spence|bhp|pampa norte/i },
]

const LINEA_HINTS: Array<{ codigo: LineaNegocioCalama; patron: RegExp }> = [
  { codigo: 'mejoras_civiles', patron: /pintura|refacci[oó]n|obra civil|oficina|mejora|baldosa|loseta|rejilla|fosa|pretil/i },
  { codigo: 'combustibles', patron: /combustible|estaci[oó]n\s*de\s*servicio|petrolera|petr[oó]leo|surtidor|estanque/i },
  { codigo: 'lubricantes', patron: /lubricant|aceite|grasa|lubrim[oó]vil/i },
]

function sugerirFaenas(archivo: string, textosBlob: string): Array<{ codigo: string; nombre: string; razon: string }> {
  const fuentes = `${archivo} ${textosBlob}`.toLowerCase()
  const result: Array<{ codigo: string; nombre: string; razon: string }> = []
  for (const h of FAENA_HINTS) {
    if (h.patron.test(fuentes)) {
      const enArchivo = h.patron.test(archivo)
      result.push({
        codigo: h.codigo,
        nombre: h.nombre,
        razon: enArchivo ? 'Detectada en nombre de archivo' : 'Detectada en contenido',
      })
    }
  }
  return result
}

function sugerirLineas(textosBlob: string): Array<{ codigo: LineaNegocioCalama; razon: string }> {
  const lower = textosBlob.toLowerCase()
  const result: Array<{ codigo: LineaNegocioCalama; razon: string }> = []
  for (const h of LINEA_HINTS) {
    const m = lower.match(h.patron)
    if (m) result.push({ codigo: h.codigo, razon: `keyword detectada: "${m[0]}"` })
  }
  return result
}

// ============================================================================
// Parsers por hoja
// ============================================================================

/**
 * Hoja "Detalle": jerarquia zonas (N.0.0), actividades (N.M.0), subtareas
 * (col1 vacia, col2 = N.M.K). Estado y fecha real en cols 7-8.
 */
function parseHojaDetalle(
  ws: ExcelJS.Worksheet,
  errores: CalamaPreviewMapeoError[],
): {
  zonas: CalamaPreviewZona[]
  tareas: CalamaPreviewTarea[]
  subtareas: CalamaPreviewSubtarea[]
} {
  const hoja = ws.name
  const zonas: CalamaPreviewZona[] = []
  const tareas: CalamaPreviewTarea[] = []
  const subtareas: CalamaPreviewSubtarea[] = []

  let zonaActual: string | null = null
  let tareaActual: string | null = null

  const last = ws.actualRowCount
  for (let r = 2; r <= last; r++) {
    const c1 = cellText(readCell(ws, r, 1) as CellLike)
    const c2 = cellText(readCell(ws, r, 2) as CellLike)
    const c3 = cellText(readCell(ws, r, 3) as CellLike)
    const c7 = cellText(readCell(ws, r, 7) as CellLike)
    const c8 = readCell(ws, r, 8) as CellLike

    if (!c1 && !c2 && !c3) continue

    if (c1 && /\.\d+\.0$/.test(c1) && c1.endsWith('.0.0')) {
      zonaActual = c1
      tareaActual = null
      if (c2) zonas.push({ codigo: c1, nombre: c2, origen_hoja: hoja })
      continue
    }

    if (c1 && /\.\d+\.0$/.test(c1) && !c1.endsWith('.0.0')) {
      tareaActual = c1
      if (c2) {
        tareas.push({
          codigo: c1,
          nombre: c2,
          zona_codigo: zonaActual,
          duracion_plan_dias: null,
          duracion_real_dias: null,
          fecha_inicio_plan: null,
          fecha_fin_plan: null,
          fecha_inicio_real: null,
          fecha_fin_real: null,
          ot_referencia: null,
          verif: null,
          avance_excel_pct: null,
          origen_hoja: hoja,
        })
      }
      continue
    }

    if (!c1 && c2 && /^\d+(\.\d+){2,}$/.test(c2)) {
      const desc = c3 ?? ''
      if (!desc) {
        errores.push({
          hoja,
          fila: r,
          columna: 'descripcion (col 3)',
          detalle: `Subtarea ${c2} sin descripcion`,
        })
      }
      subtareas.push({
        codigo: c2,
        descripcion: desc,
        tarea_codigo: tareaActual,
        estado: c7,
        fecha_real: cellDate(c8),
        origen_hoja: hoja,
      })
      continue
    }
  }

  return { zonas, tareas, subtareas }
}

/**
 * Hoja "Carta Gantt": cols 1-8 metadatos, cols 9+ calendario diario.
 * Filas 1-3 = headers calendario, fila 4 = header columnas, fila 5+ = datos.
 *
 * Estrategia: detectar la fila de header (la que tiene "Duración" y "Verif").
 * Para cada tarea, encontrar primera/ultima columna con 'x' (plan) y 'R' (real).
 * Reconstruir fechas usando R1 (mes+anio) y R3 (dia).
 */
function parseHojaCartaGantt(
  ws: ExcelJS.Worksheet,
  errores: CalamaPreviewMapeoError[],
): {
  tareas: CalamaPreviewTarea[]
  fechas: CalamaPreviewFechaPlan[]
} {
  const hoja = ws.name
  const tareas: CalamaPreviewTarea[] = []
  const fechas: CalamaPreviewFechaPlan[] = []

  const lastCol = ws.actualColumnCount
  const lastRow = ws.actualRowCount

  let headerRow = 0
  for (let r = 1; r <= Math.min(8, lastRow); r++) {
    const row = ws.getRow(r)
    const flat = (() => {
      const arr: string[] = []
      for (let c = 1; c <= Math.min(10, lastCol); c++) {
        arr.push((cellText(row.getCell(c).value as CellLike) ?? '').toLowerCase())
      }
      return arr.join(' | ')
    })()
    if (flat.includes('duración') || flat.includes('duracion')) {
      headerRow = r
      break
    }
  }
  if (headerRow === 0) {
    errores.push({ hoja, fila: null, columna: null, detalle: 'No se detecto fila de header (Duracion/Verif)' })
    return { tareas, fechas }
  }

  const calStartCol = 9

  const calMeses: Record<number, string | null> = {}
  const calDias: Record<number, number | null> = {}
  let lastMes: string | null = null
  for (let c = calStartCol; c <= lastCol; c++) {
    const m = cellText(readCell(ws, 1, c) as CellLike)
    if (m) lastMes = m
    calMeses[c] = lastMes
    calDias[c] = cellNum(readCell(ws, 3, c) as CellLike)
  }

  const colToFecha = (col: number): string | null => {
    const mes = calMeses[col]
    const dia = calDias[col]
    if (!mes || !dia) return null
    const m = /([A-Za-z]+)\s*(\d{4})/.exec(mes)
    if (!m) return null
    const monthMap: Record<string, string> = {
      enero: '01', febrero: '02', marzo: '03', abril: '04', mayo: '05', junio: '06',
      julio: '07', agosto: '08', septiembre: '09', octubre: '10', noviembre: '11', diciembre: '12',
      january: '01', february: '02', march: '03', april: '04', may: '05', june: '06',
      july: '07', august: '08', september: '09', october: '10', november: '11', december: '12',
    }
    const mm = monthMap[m[1].toLowerCase()]
    const yyyy = m[2]
    if (!mm) return null
    return `${yyyy}-${mm}-${String(dia).padStart(2, '0')}`
  }

  for (let r = headerRow + 1; r <= lastRow; r++) {
    const codigo = cellText(readCell(ws, r, 1) as CellLike)
    const nombre = cellText(readCell(ws, r, 4) as CellLike)
    if (!codigo || !nombre) continue
    if (!/^\d+(\.\d+){2}$/.test(codigo)) continue

    const duracionPlan = cellNum(readCell(ws, r, 5) as CellLike)
    const duracionReal = cellNum(readCell(ws, r, 6) as CellLike)
    const ot = cellText(readCell(ws, r, 7) as CellLike)
    const verif = cellText(readCell(ws, r, 8) as CellLike)
    // Columna C (col 3): % Cumplimiento. 1 -> 100, 0.5 -> 50, "50%" -> 50.
    const avanceExcel = cellPct(readCell(ws, r, 3) as CellLike)

    let firstPlan: number | null = null
    let lastPlan: number | null = null
    let firstReal: number | null = null
    let lastReal: number | null = null

    for (let c = calStartCol; c <= lastCol; c++) {
      const t = cellText(readCell(ws, r, c) as CellLike)
      if (!t) continue
      const lower = t.toLowerCase()
      if (lower === 'x' || lower === 'p') {
        if (firstPlan === null) firstPlan = c
        lastPlan = c
      } else if (lower === 'r') {
        if (firstReal === null) firstReal = c
        lastReal = c
      }
    }

    const fInicioPlan = firstPlan ? colToFecha(firstPlan) : null
    const fFinPlan = lastPlan ? colToFecha(lastPlan) : null
    const fInicioReal = firstReal ? colToFecha(firstReal) : null
    const fFinReal = lastReal ? colToFecha(lastReal) : null

    tareas.push({
      codigo,
      nombre,
      zona_codigo: null,
      duracion_plan_dias: duracionPlan,
      duracion_real_dias: duracionReal,
      fecha_inicio_plan: fInicioPlan,
      fecha_fin_plan: fFinPlan,
      fecha_inicio_real: fInicioReal,
      fecha_fin_real: fFinReal,
      ot_referencia: ot,
      verif,
      avance_excel_pct: avanceExcel,
      origen_hoja: hoja,
    })

    if (fInicioPlan || fFinPlan || duracionPlan != null) {
      fechas.push({
        codigo_tarea: codigo,
        nombre_tarea: nombre,
        fecha_inicio_plan: fInicioPlan,
        fecha_fin_plan: fFinPlan,
        duracion_dias: duracionPlan,
        origen_hoja: hoja,
      })
    }
  }

  return { tareas, fechas }
}

/**
 * Hoja "Itemizado materiale": detecta fila header con "Porcentaje"/"Valor $".
 * Cada fila siguiente -> material asociado a la actividad de col 1.
 * Cols 11+ contienen sub-bloques (Herramientas/EPP/Examenes) — se exponen como
 * materiales adicionales con observacion = nombre del bloque.
 *
 * ZONA: las filas con col2 = "Total UF" funcionan como section headers — la
 * actividad de col1 (ej "Petrolera Oxidos") es la zona vigente para las filas
 * siguientes hasta el proximo section header.
 */
function parseHojaItemizado(
  ws: ExcelJS.Worksheet,
  errores: CalamaPreviewMapeoError[],
  zonas: CalamaPreviewZona[],
): { materiales: CalamaPreviewMaterial[] } {
  const hoja = ws.name
  const materiales: CalamaPreviewMaterial[] = []
  const lastRow = ws.actualRowCount
  const lastCol = ws.actualColumnCount

  let headerRow = 0
  for (let r = 1; r <= Math.min(15, lastRow); r++) {
    const flat: string[] = []
    for (let c = 1; c <= Math.min(20, lastCol); c++) {
      flat.push((cellText(readCell(ws, r, c) as CellLike) ?? '').toLowerCase())
    }
    const blob = flat.join(' | ')
    if (blob.includes('porcentaje') && blob.includes('valor')) {
      headerRow = r
      break
    }
  }
  if (headerRow === 0) {
    errores.push({ hoja, fila: null, columna: null, detalle: 'No se detecto fila header (Porcentaje/Valor)' })
    return { materiales }
  }

  const colNombre = 1
  const colPct = 4
  const colValorClp = 5
  const colValorUF = 7
  const colDescripcion = 9

  // Sub-bloques detectados desde el header (Herramientas / EPP / Examenes)
  const subBloques: Array<{ colHeader: number; colValor: number; nombre: string }> = []
  for (let c = 11; c <= Math.min(20, lastCol); c++) {
    const h = cellText(readCell(ws, headerRow - 1, c) as CellLike)
      ?? cellText(readCell(ws, headerRow + 0, c) as CellLike)
    if (h && c + 1 <= lastCol) {
      subBloques.push({ colHeader: c, colValor: c + 1, nombre: h })
      c++
    }
  }

  let zonaActualNombre: string | null = null
  let zonaActualCodigo: string | null = null

  for (let r = headerRow; r <= lastRow; r++) {
    const c1 = cellText(readCell(ws, r, 1) as CellLike)
    const c2 = cellText(readCell(ws, r, 2) as CellLike)

    // Section header (zona): col2 = "Total UF" y col1 tiene texto.
    if (c1 && c2 && /total\s*uf/i.test(c2)) {
      zonaActualNombre = c1
      zonaActualCodigo = findZonaCode(c1, zonas)
      continue
    }

    const actividad = c1
    const desc = cellText(readCell(ws, r, colDescripcion) as CellLike)
    const pct = cellNum(readCell(ws, r, colPct) as CellLike)
    const clp = cellNum(readCell(ws, r, colValorClp) as CellLike)
    const uf = cellNum(readCell(ws, r, colValorUF) as CellLike)

    if (actividad || desc || pct != null || clp != null || uf != null) {
      materiales.push({
        actividad_relacionada: actividad,
        descripcion: desc ?? actividad ?? `(fila ${r})`,
        unidad: null,
        cantidad: null,
        precio_clp: clp,
        valor_uf: uf,
        porcentaje: pct,
        observacion: null,
        zona_codigo: zonaActualCodigo,
        zona_nombre: zonaActualNombre,
        origen_hoja: hoja,
      })
    }

    for (const b of subBloques) {
      const nombreItem = cellText(readCell(ws, r, b.colHeader) as CellLike)
      const precioItem = cellNum(readCell(ws, r, b.colValor) as CellLike)
      if (nombreItem || precioItem != null) {
        materiales.push({
          actividad_relacionada: actividad,
          descripcion: nombreItem ?? '(sin nombre)',
          unidad: null,
          cantidad: null,
          precio_clp: precioItem,
          valor_uf: null,
          porcentaje: null,
          observacion: b.nombre,
          zona_codigo: zonaActualCodigo,
          zona_nombre: zonaActualNombre,
          origen_hoja: hoja,
        })
      }
    }
  }

  return { materiales }
}

/**
 * Match aproximado de un nombre contra el listado de zonas detectadas.
 * "Petrolera Oxidos" -> "1.0.0 Petrolera Oxidos" (matchea por substring).
 */
function findZonaCode(nombre: string, zonas: CalamaPreviewZona[]): string | null {
  if (!nombre) return null
  const target = nombre.toLowerCase().trim().replace(/\.$/, '')
  for (const z of zonas) {
    const zn = z.nombre.toLowerCase().trim().replace(/\.$/, '')
    if (zn === target) return z.codigo
    if (zn.includes(target) || target.includes(zn)) return z.codigo
  }
  return null
}

/**
 * Hoja "OBS.": codigo (col1), pct avance (col2), nombre (col3), observacion (col4).
 */
function parseHojaObs(ws: ExcelJS.Worksheet): {
  avances: CalamaPreviewAvance[]
  observaciones: CalamaPreviewObservacion[]
} {
  const hoja = ws.name
  const avances: CalamaPreviewAvance[] = []
  const observaciones: CalamaPreviewObservacion[] = []
  const lastRow = ws.actualRowCount

  let headerRow = 0
  for (let r = 1; r <= Math.min(8, lastRow); r++) {
    const c1 = (cellText(readCell(ws, r, 1) as CellLike) ?? '').toLowerCase()
    const c4 = (cellText(readCell(ws, r, 4) as CellLike) ?? '').toLowerCase()
    if (c1.includes('cod') || c4.includes('obs')) {
      headerRow = r
      break
    }
  }

  for (let r = (headerRow || 1) + 1; r <= lastRow; r++) {
    const codigo = cellText(readCell(ws, r, 1) as CellLike)
    const pctRaw = cellNum(readCell(ws, r, 2) as CellLike)
    const nombre = cellText(readCell(ws, r, 3) as CellLike)
    const obs = cellText(readCell(ws, r, 4) as CellLike)

    if (!codigo && !nombre && !obs && pctRaw == null) continue

    if (codigo) {
      const pct = pctRaw != null ? (pctRaw <= 1 ? pctRaw * 100 : pctRaw) : null
      avances.push({
        codigo,
        nombre: nombre ?? '',
        avance_pct: pct,
        origen_hoja: hoja,
      })
    }
    if (obs) {
      observaciones.push({
        codigo_relacionado: codigo,
        texto: obs,
        origen_hoja: hoja,
      })
    }
  }

  return { avances, observaciones }
}

/**
 * Hoja "Hoja1": contactos por codigo. Sin header.
 * Cols: codigo | descripcion | telefono | rol
 */
function parseHojaContactos(ws: ExcelJS.Worksheet): CalamaPreviewContacto[] {
  const hoja = ws.name
  const out: CalamaPreviewContacto[] = []
  const lastRow = ws.actualRowCount

  for (let r = 1; r <= lastRow; r++) {
    const codigo = cellText(readCell(ws, r, 1) as CellLike)
    const desc = cellText(readCell(ws, r, 2) as CellLike)
    const tel = normTel(readCell(ws, r, 3) as CellLike)
    const rol = cellText(readCell(ws, r, 4) as CellLike)

    if (!codigo && !desc && !tel && !rol) continue

    let faenaSugerida: string | null = null
    const blob = `${desc ?? ''} ${rol ?? ''}`.toLowerCase()
    if (/centinela|esperanza|encuentro|muelle/.test(blob)) faenaSugerida = 'CENTINELA'
    else if (/lomas|bayas/.test(blob)) faenaSugerida = 'LOMAS_BAYAS'
    else if (/spence/.test(blob)) faenaSugerida = 'SPENCE'

    out.push({
      codigo_actividad: codigo,
      descripcion: desc ?? '',
      telefono: tel,
      rol,
      faena_sugerida: faenaSugerida,
      origen_hoja: hoja,
    })
  }
  return out
}

// ============================================================================
// Entry point
// ============================================================================

export async function parseCalamaExcel(input: File | ArrayBuffer, archivoNombre?: string): Promise<CalamaImportPreview> {
  const archivo = archivoNombre ?? (input instanceof File ? input.name : 'archivo.xlsx')
  const buffer = input instanceof File ? await input.arrayBuffer() : input

  const advertencias: CalamaPreviewAdvertencia[] = []
  const errores: CalamaPreviewMapeoError[] = []

  const wb = new ExcelJS.Workbook()
  await wb.xlsx.load(buffer)

  const hojas: string[] = []
  wb.eachSheet((ws) => hojas.push(ws.name))

  const findSheet = (matchers: RegExp[]): ExcelJS.Worksheet | null => {
    for (const ws of wb.worksheets) {
      for (const rx of matchers) {
        if (rx.test(ws.name)) return ws
      }
    }
    return null
  }

  const hojaDetalle = findSheet([/^detalle$/i])
  const hojaCarta = findSheet([/^carta\s*gantt$/i])
  const hojaItem = findSheet([/^itemizado/i])
  const hojaObs = findSheet([/^obs\.?$/i])
  const hojaContactos = findSheet([/^hoja1$/i, /contactos?/i])

  const ESPERADAS: Array<{ nombre: string; ws: ExcelJS.Worksheet | null }> = [
    { nombre: 'Detalle', ws: hojaDetalle },
    { nombre: 'Carta Gantt', ws: hojaCarta },
    { nombre: 'Itemizado materiale', ws: hojaItem },
    { nombre: 'OBS.', ws: hojaObs },
    { nombre: 'Hoja1 (contactos)', ws: hojaContactos },
  ]
  for (const e of ESPERADAS) {
    if (!e.ws) advertencias.push({ hoja: null, detalle: `Hoja esperada no encontrada: "${e.nombre}". Se omite.` })
  }

  const hojasReconocidas = new Set([
    hojaDetalle?.name, hojaCarta?.name, hojaItem?.name, hojaObs?.name, hojaContactos?.name,
  ].filter(Boolean) as string[])
  for (const h of hojas) {
    if (!hojasReconocidas.has(h) && !/analisi/i.test(h)) {
      advertencias.push({ hoja: h, detalle: `Hoja desconocida no mapeada: "${h}". Su contenido no se importa.` })
    }
  }

  let zonas: CalamaPreviewZona[] = []
  let tareas: CalamaPreviewTarea[] = []
  let subtareas: CalamaPreviewSubtarea[] = []
  if (hojaDetalle) {
    const r = parseHojaDetalle(hojaDetalle, errores)
    zonas = r.zonas
    tareas = r.tareas
    subtareas = r.subtareas
  }

  let fechasPlan: CalamaPreviewFechaPlan[] = []
  if (hojaCarta) {
    const r = parseHojaCartaGantt(hojaCarta, errores)
    fechasPlan = r.fechas
    const tareasPorCodigo = new Map(tareas.map((t) => [t.codigo, t]))
    for (const tg of r.tareas) {
      const existente = tareasPorCodigo.get(tg.codigo)
      if (existente) {
        existente.duracion_plan_dias = tg.duracion_plan_dias
        existente.duracion_real_dias = tg.duracion_real_dias
        existente.fecha_inicio_plan = tg.fecha_inicio_plan
        existente.fecha_fin_plan = tg.fecha_fin_plan
        existente.fecha_inicio_real = tg.fecha_inicio_real
        existente.fecha_fin_real = tg.fecha_fin_real
        existente.ot_referencia = tg.ot_referencia
        existente.verif = tg.verif
        existente.avance_excel_pct = tg.avance_excel_pct
      } else {
        tareas.push(tg)
      }
    }
  }

  let materiales: CalamaPreviewMaterial[] = []
  if (hojaItem) materiales = parseHojaItemizado(hojaItem, errores, zonas).materiales

  // Backfill: para materiales sin zona detectada por section-header,
  // intentar via match unico de actividad_relacionada con nombre de tarea.
  if (materiales.length > 0 && tareas.length > 0) {
    for (const m of materiales) {
      if (m.zona_codigo) continue
      if (!m.actividad_relacionada) continue
      const target = m.actividad_relacionada.toLowerCase().trim()
      const matches = tareas.filter((t) => {
        const tn = (t.nombre ?? '').toLowerCase().trim()
        return tn === target || tn.includes(target) || target.includes(tn)
      })
      if (matches.length === 1 && matches[0].zona_codigo) {
        m.zona_codigo = matches[0].zona_codigo
      }
    }
  }

  let avances: CalamaPreviewAvance[] = []
  let observacionesObs: CalamaPreviewObservacion[] = []
  if (hojaObs) {
    const r = parseHojaObs(hojaObs)
    avances = r.avances
    observacionesObs = r.observaciones
  }

  let contactos: CalamaPreviewContacto[] = []
  if (hojaContactos) contactos = parseHojaContactos(hojaContactos)

  let preview = 1
  for (const t of tareas) {
    if (!t.codigo || t.codigo.length === 0) {
      t.codigo = `PREVIEW-${String(preview).padStart(3, '0')}`
      preview++
      advertencias.push({ hoja: t.origen_hoja, detalle: `Tarea sin codigo, asignado temporal: ${t.codigo}` })
    }
  }

  const blob = [
    ...zonas.map((z) => z.nombre),
    ...tareas.map((t) => t.nombre),
    ...subtareas.map((s) => s.descripcion),
    ...materiales.map((m) => `${m.actividad_relacionada ?? ''} ${m.descripcion}`),
    ...contactos.map((c) => `${c.descripcion} ${c.rol ?? ''}`),
  ].join(' ')
  const faenas = sugerirFaenas(archivo, blob)
  const lineas = sugerirLineas(blob)

  if (faenas.length === 0) {
    advertencias.push({ hoja: null, detalle: 'No se pudo sugerir faena automaticamente. Selecciona manualmente al importar.' })
  }
  if (lineas.length === 0) {
    advertencias.push({ hoja: null, detalle: 'No se pudo sugerir linea de negocio automaticamente.' })
  }

  return {
    archivo,
    hojas_detectadas: hojas,
    faenas_detectadas: faenas,
    lineas_negocio_detectadas: lineas,
    zonas_detectadas: zonas,
    tareas_detectadas: tareas,
    subtareas_detectadas: subtareas,
    materiales_detectados: materiales,
    contactos_detectados: contactos,
    fechas_planificadas_detectadas: fechasPlan,
    avances_detectados: avances,
    observaciones_detectadas: observacionesObs,
    errores_de_mapeo: errores,
    advertencias,
    resumen: {
      total_zonas: zonas.length,
      total_tareas: tareas.length,
      total_subtareas: subtareas.length,
      total_materiales: materiales.length,
      total_contactos: contactos.length,
      total_fechas: fechasPlan.length,
      total_observaciones: observacionesObs.length,
      total_advertencias: advertencias.length,
      total_errores: errores.length,
    },
  }
}
