// Planificación ENEX — cálculo de avance y lectura de la planilla diaria (MIG590).
//
// Todo puro (sin Supabase) para poder probarlo. Lo usa
// /dashboard/enex/planificacion. El mantenedor no pasa por aquí: /m/enex lee
// las mismas programaciones por fecha, como siempre.
//
// Definiciones (una programación = un servicio comprometido):
//   · Plan a la fecha: % de servicios cuya fecha planificada ya llegó.
//   · Real: % cumplido con firma del mandante (lo que vale para el KPI).
//   · Ejecutado: % hecho en terreno, firmado o no (avance físico).
//   · Proyectado según plan: cierre si lo pendiente con fecha futura se hace
//     en su día. Lo atrasado y lo no realizado NO suman: hay que reprogramarlo.
//   · Proyectado según ritmo: cierre si se sigue al ritmo actual
//     (SPI = ejecutado ÷ plan a la fecha).
//   · [MIG658] Justificada: ESM la cambió por otra tarea y el ADC lo autorizó
//     por correo (Consideración 1 del KPI V8). No cuenta en ningún %.

export type ProgAvance = {
  programacion_id: string
  periodo_anio: number
  periodo_mes: number
  fecha_programada: string | null
  fecha_ejecucion: string | null
  estado: 'ejecutada' | 'cumplida' | 'no_realizada' | null
  cumplida: boolean
  justificada?: boolean | null
}

export type EstadoProg = 'justificada' | 'cumplida' | 'sin_firma' | 'no_realizada' | 'atrasada' | 'hoy' | 'programada'

/** Lo que cuenta para el KPI: todo menos lo justificado por el ADC. */
export const enKpi = <T extends ProgAvance>(rows: T[]): T[] => rows.filter((r) => !r.justificada)

const pad = (n: number) => String(n).padStart(2, '0')
export const isoDe = (d: Date) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
export const fechaDeIso = (iso: string) => { const [y, m, d] = iso.slice(0, 10).split('-').map(Number); return new Date(y, m - 1, d) }
export const sumarDias = (iso: string, n: number) => { const d = fechaDeIso(iso); d.setDate(d.getDate() + n); return isoDe(d) }
export const ultimoDiaMes = (anio: number, mes: number) => isoDe(new Date(anio, mes, 0))

export type Ventana = { desde: string; hasta: string; meses: { anio: number; mes: number }[] }

/** Tres meses corridos desde (anio, mesInicio). Cruza el año sin problema (Nov–Ene). */
export function ventanaTrimestre(anio: number, mesInicio: number): Ventana {
  const meses = [0, 1, 2].map((k) => {
    const m0 = mesInicio - 1 + k
    return { anio: anio + Math.floor(m0 / 12), mes: (m0 % 12) + 1 }
  })
  return {
    desde: `${meses[0].anio}-${pad(meses[0].mes)}-01`,
    hasta: ultimoDiaMes(meses[2].anio, meses[2].mes),
    meses,
  }
}

/** Ventana de la Gantt: desde un día cualquiera hasta el fin del mes n-1 después (mira hacia adelante). */
export function ventanaDesde(desde: string, nMeses: number): Ventana {
  const [y, m] = desde.split('-').map(Number)
  const meses = Array.from({ length: nMeses }, (_, k) => {
    const m0 = m - 1 + k
    return { anio: y + Math.floor(m0 / 12), mes: (m0 % 12) + 1 }
  })
  const ult = meses[meses.length - 1]
  return { desde, hasta: ultimoDiaMes(ult.anio, ult.mes), meses }
}

/**
 * Primer mes del trimestre del contrato que contiene la fecha, como fn_enex_trimestre_inicio.
 * [MIG658] El trimestre depende del contrato (enex_faenas.trimestre_ancla):
 *   ancla 2 = Centinela: Feb-Abr, May-Jul, Ago-Oct, Nov-Ene (por omisión, como antes).
 *   ancla 1 = Spence y Lomas: trimestre calendario (Ene-Mar … Oct-Dic).
 */
export function inicioTrimestreContractual(iso: string, ancla = 2): { anio: number; mes: number } {
  const [y, m] = iso.split('-').map(Number)
  const off = (m - ancla + 12) % 3        // meses desde el inicio del trimestre
  const mesIni = ((m - 1 - off) + 12) % 12 + 1
  const anio = mesIni > m ? y - 1 : y     // Nov-Ene: enero pertenece al trimestre que partió en noviembre
  return { anio, mes: mesIni }
}

/** Ventana del trimestre del contrato que contiene la fecha. */
export function trimestreContrato(iso: string, ancla = 2): Ventana {
  const t = inicioTrimestreContractual(iso, ancla)
  return ventanaTrimestre(t.anio, t.mes)
}

const MES_CORTO_TRI = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic']
/** «Oct-Dic 2026», «Nov-Ene 2026» (como fn_enex_trimestre_label). */
export const etiquetaTrimestre = (v: Ventana) =>
  `${MES_CORTO_TRI[v.meses[0].mes - 1]}-${MES_CORTO_TRI[v.meses[2].mes - 1]} ${v.meses[0].anio}`

/** Día al que pesa una programación en el plan: su fecha o, si no tiene, el último día de su mes. */
export const fechaPlan = (r: ProgAvance) => r.fecha_programada?.slice(0, 10) ?? ultimoDiaMes(r.periodo_anio, r.periodo_mes)
const ejecutada = (r: ProgAvance) => r.cumplida || r.estado === 'ejecutada' || r.estado === 'cumplida'
/** Día en que se hizo (para la curva real). */
const fechaReal = (r: ProgAvance) => r.fecha_ejecucion?.slice(0, 10) ?? fechaPlan(r)

export function estadoProg(r: ProgAvance, hoy: string): EstadoProg {
  if (r.justificada) return 'justificada'
  if (r.cumplida || r.estado === 'cumplida') return 'cumplida'
  if (r.estado === 'ejecutada') return 'sin_firma'
  if (r.estado === 'no_realizada') return 'no_realizada'
  const f = fechaPlan(r)
  if (f < hoy) return 'atrasada'
  if (f === hoy) return 'hoy'
  return 'programada'
}

export type Avance = {
  total: number
  planHoy: number
  cumplidas: number
  ejecutadas: number      // incluye cumplidas
  sinFirma: number
  atrasadas: number
  noRealizadas: number
  futuras: number         // pendientes con fecha hoy o después
  pctPlanHoy: number | null
  pctReal: number | null
  pctEjecutado: number | null
  pctProyectadoPlan: number | null
  pctProyectadoRitmo: number | null
  spi: number | null
  desviacion: number | null  // ejecutado − plan a la fecha, en puntos
}

const pct = (n: number, d: number) => (d > 0 ? Math.round((n / d) * 1000) / 10 : null)

export function calcularAvance(todas: ProgAvance[], hoy: string): Avance {
  const rows = enKpi(todas)
  let planHoy = 0, cumplidas = 0, ejecutadas = 0, sinFirma = 0, atrasadas = 0, noRealizadas = 0, futuras = 0
  for (const r of rows) {
    if (fechaPlan(r) <= hoy) planHoy++
    const e = estadoProg(r, hoy)
    if (e === 'cumplida') { cumplidas++; ejecutadas++ }
    else if (e === 'sin_firma') { sinFirma++; ejecutadas++ }
    else if (e === 'no_realizada') noRealizadas++
    else if (e === 'atrasada') atrasadas++
    else futuras++
  }
  const total = rows.length
  const spi = planHoy > 0 ? Math.round((ejecutadas / planHoy) * 100) / 100 : null
  const pctPlanHoy = pct(planHoy, total)
  const pctEjecutado = pct(ejecutadas, total)
  return {
    total, planHoy, cumplidas, ejecutadas, sinFirma, atrasadas, noRealizadas, futuras,
    pctPlanHoy,
    pctReal: pct(cumplidas, total),
    pctEjecutado,
    pctProyectadoPlan: pct(ejecutadas + futuras, total),
    pctProyectadoRitmo: spi == null ? null : Math.min(100, Math.round(spi * 1000) / 10),
    spi,
    desviacion: pctPlanHoy == null || pctEjecutado == null ? null : Math.round((pctEjecutado - pctPlanHoy) * 10) / 10,
  }
}

export type PuntoCurva = { fecha: string; plan: number; real: number | null; proyectado: number | null }

/**
 * Curva S diaria del período: plan acumulado, real (ejecutado) acumulado hasta
 * hoy y, desde hoy, la proyección = real de hoy + lo pendiente que sigue en el plan.
 */
export function curvaS(todas: ProgAvance[], desde: string, hasta: string, hoy: string): PuntoCurva[] {
  const rows = enKpi(todas)
  const total = rows.length
  if (total === 0) return []
  const planDia = new Map<string, number>()
  const realDia = new Map<string, number>()
  const proyDia = new Map<string, number>()
  let realAntes = 0      // ejecutado antes del inicio de la ventana (no debería, pero no se pierde)
  for (const r of rows) {
    const fp = fechaPlan(r) < desde ? desde : fechaPlan(r)
    planDia.set(fp, (planDia.get(fp) ?? 0) + 1)
    const e = estadoProg(r, hoy)
    if (e === 'cumplida' || e === 'sin_firma') {
      const fr = fechaReal(r)
      if (fr < desde) realAntes++
      else realDia.set(fr > hoy ? hoy : fr, (realDia.get(fr > hoy ? hoy : fr) ?? 0) + 1)
    } else if (e === 'hoy' || e === 'programada') {
      proyDia.set(fp, (proyDia.get(fp) ?? 0) + 1)
    }
  }
  const out: PuntoCurva[] = []
  let accPlan = 0, accReal = realAntes, accProy = 0
  for (let f = desde; f <= hasta; f = sumarDias(f, 1)) {
    accPlan += planDia.get(f) ?? 0
    if (f <= hoy) accReal += realDia.get(f) ?? 0
    // La proyección arranca en el real de hoy y suma lo pendiente desde hoy.
    if (f >= hoy) accProy += proyDia.get(f) ?? 0
    const p = (n: number) => Math.round((n / total) * 1000) / 10
    out.push({
      fecha: f,
      plan: p(accPlan),
      real: f <= hoy ? p(accReal) : null,
      proyectado: f >= hoy ? p(accReal + accProy) : null,
    })
  }
  return out
}

// ── [MIG658] Avance contra el universo del contrato ─────────────────────────
// El % de avance de cada contrato se mide contra lo que el contrato exige por
// trimestre, no contra lo cargado en SICOM (si falta programar, el % no se infla).
// Instalación de combustible = mantención + calibración · truck shop = mantención ·
// camión = calibración.
export type UniversoContrato = { combustible: number | null; lubricante: number | null; camiones: number | null }
export type CategoriaContrato = 'combustible' | 'lubricante' | 'camiones'
export const CATEGORIA_TXT: Record<CategoriaContrato, string> = {
  combustible: 'Instalaciones de combustible', lubricante: 'Truck shop (lubricantes)', camiones: 'Camiones',
}
const TAREAS_POR: Record<CategoriaContrato, number> = { combustible: 2, lubricante: 1, camiones: 1 }

type ProgContrato = ProgAvance & { instalacion_tipo: string; linea: string | null; cambio_destino?: string | null }

export const categoriaDe = (r: { instalacion_tipo: string; linea: string | null }): CategoriaContrato =>
  r.instalacion_tipo === 'camion' ? 'camiones' : r.linea === 'lubricante' ? 'lubricante' : 'combustible'

export type AvanceContrato = {
  universo: number | null
  categorias: { cat: CategoriaContrato; universo: number; programadas: number; ejecutadas: number; justificadas: number; porProgramar: number }[]
  programadas: number       // vigentes (sin las justificadas)
  ejecutadas: number
  cumplidas: number
  justificadas: number
  pendientesAdc: number     // cambiadas por ESM, esperando el correo del ADC
  porProgramar: number
  pctAvance: number | null  // ejecutadas ÷ (universo − justificadas)
  pctKpi: number | null     // cumplidas ÷ programadas vigentes
}

export function avanceContrato(rows: ProgContrato[], u: UniversoContrato): AvanceContrato {
  const cats: CategoriaContrato[] = ['combustible', 'lubricante', 'camiones']
  const definido = u.combustible != null || u.lubricante != null || u.camiones != null
  const categorias = cats.map((cat) => {
    const rc = rows.filter((r) => categoriaDe(r) === cat)
    const justificadas = rc.filter((r) => r.justificada).length
    const vig = rc.filter((r) => !r.justificada)
    const universo = (u[cat] ?? 0) * TAREAS_POR[cat]
    const ejecutadas = vig.filter((r) => r.cumplida || r.estado === 'ejecutada' || r.estado === 'cumplida').length
    return { cat, universo, programadas: vig.length, ejecutadas, justificadas,
             porProgramar: Math.max(0, universo - justificadas - vig.length) }
  }).filter((c) => c.universo > 0 || c.programadas > 0 || c.justificadas > 0)
  const vig = enKpi(rows)
  const justificadas = rows.length - vig.length
  const ejecutadas = vig.filter((r) => r.cumplida || r.estado === 'ejecutada' || r.estado === 'cumplida').length
  const cumplidas = vig.filter((r) => r.cumplida || r.estado === 'cumplida').length
  const universo = definido ? categorias.reduce((s, c) => s + c.universo, 0) : null
  // Lo hecho por sobre el universo (recobros) no lleva el avance sobre 100 %.
  const ejecDentro = categorias.reduce((s, c) => s + (definido ? Math.min(c.ejecutadas, Math.max(0, c.universo - c.justificadas)) : c.ejecutadas), 0)
  const base = universo == null ? null : universo - justificadas
  return {
    universo, categorias, programadas: vig.length, ejecutadas, cumplidas, justificadas,
    pendientesAdc: rows.filter((r) => r.cambio_destino === 'pendiente_adc' && !r.estado).length,
    porProgramar: definido ? categorias.reduce((s, c) => s + c.porProgramar, 0) : 0,
    pctAvance: base == null ? null : base > 0 ? pct(ejecDentro, base) : null,
    pctKpi: pct(cumplidas, vig.length),
  }
}

/** Tramo de multa del contrato para un % de cumplimiento (≥96 0 %, 90-95 10 %, 80-89 20 %, <80 revisión). */
export function tramoMulta(pctCumpl: number | null): { pct: number; revision: boolean; etiqueta: string } {
  if (pctCumpl == null) return { pct: 0, revision: false, etiqueta: '—' }
  if (pctCumpl >= 96) return { pct: 0, revision: false, etiqueta: 'Sin multa' }
  if (pctCumpl >= 90) return { pct: 10, revision: false, etiqueta: 'Multa 10 %' }
  if (pctCumpl >= 80) return { pct: 20, revision: false, etiqueta: 'Multa 20 %' }
  return { pct: 20, revision: true, etiqueta: 'Revisión de continuidad' }
}

// ── Códigos de celda (los mismos de la planilla) ────────────────────────────
export type ServicioDia = { tipo_servicio: 'mantencion' | 'calibracion'; esCamion: boolean }

/** CMP = calib.+mant. el mismo día · C = calibración · MP = mantención · CP/CP2/CP3 = camiones. */
export function codigoCelda(servs: ServicioDia[]): string {
  if (servs.length === 0) return ''
  const cam = servs.filter((s) => s.esCamion).length
  if (cam > 0 && cam === servs.length) return cam === 1 ? 'CP' : `CP${cam}`
  const m = servs.some((s) => !s.esCamion && s.tipo_servicio === 'mantencion')
  const c = servs.some((s) => !s.esCamion && s.tipo_servicio === 'calibracion')
  const base = m && c ? 'CMP' : c ? 'C' : 'MP'
  return cam > 0 ? `${base}+CP${cam > 1 ? cam : ''}` : base
}

// Feriados nacionales Chile (para pintar la Gantt como la planilla).
export const FERIADOS_CL: Record<string, string> = {
  '2026-01-01': 'Año Nuevo', '2026-04-03': 'Viernes Santo', '2026-04-04': 'Sábado Santo', '2026-05-01': 'Día del Trabajo',
  '2026-05-21': 'Glorias Navales', '2026-06-21': 'Pueblos Indígenas', '2026-06-29': 'San Pedro y San Pablo',
  '2026-07-16': 'Virgen del Carmen', '2026-08-15': 'Asunción', '2026-09-18': 'Independencia', '2026-09-19': 'Glorias del Ejército',
  '2026-10-12': 'Encuentro de Dos Mundos', '2026-10-31': 'Iglesias Evangélicas', '2026-11-01': 'Todos los Santos',
  '2026-12-08': 'Inmaculada Concepción', '2026-12-25': 'Navidad',
  '2027-01-01': 'Año Nuevo', '2027-03-26': 'Viernes Santo', '2027-03-27': 'Sábado Santo', '2027-05-01': 'Día del Trabajo',
  '2027-05-21': 'Glorias Navales', '2027-06-21': 'Pueblos Indígenas', '2027-06-28': 'San Pedro y San Pablo',
  '2027-07-16': 'Virgen del Carmen', '2027-08-15': 'Asunción', '2027-09-17': 'Feriado adicional', '2027-09-18': 'Independencia',
  '2027-09-19': 'Glorias del Ejército', '2027-10-11': 'Encuentro de Dos Mundos', '2027-10-31': 'Iglesias Evangélicas',
  '2027-11-01': 'Todos los Santos', '2027-12-08': 'Inmaculada Concepción', '2027-12-25': 'Navidad',
}

// ── Lectura de la planilla diaria (una hoja por faena) ──────────────────────
export type CodigoPlanilla = { fecha: string; codigo: string; servicios: ('mantencion' | 'calibracion')[]; camiones: number }
export type FilaPlanilla = { nombre: string; fila: number; esCamiones: boolean; entradas: CodigoPlanilla[] }
export type HojaPlanilla = { filas: FilaPlanilla[]; ignorados: { codigo: string; n: number }[]; desde: string | null; hasta: string | null }

const MESES_TXT: [RegExp, number][] = [
  [/\bene/i, 1], [/\bfeb/i, 2], [/\bmar/i, 3], [/\babr/i, 4], [/\bmay/i, 5], [/\bjun/i, 6],
  [/\bjul/i, 7], [/\bago/i, 8], [/\bsep/i, 9], [/\boct/i, 10], [/\bnov/i, 11], [/\bdic/i, 12],
]
const mesEnTexto = (s: string): number | null => {
  // Gana el mes que aparece primero en el texto ("S36 · 31 ago – 06 sep" → agosto).
  let mejor: { pos: number; mes: number } | null = null
  for (const [re, m] of MESES_TXT) {
    const i = s.search(re)
    if (i >= 0 && (!mejor || i < mejor.pos)) mejor = { pos: i, mes: m }
  }
  return mejor?.mes ?? null
}

/** Traduce un código de la planilla a servicios. R/RP/D y otros no son trabajo comprometido: se ignoran. */
export function interpretarCodigo(raw: string): { servicios: ('mantencion' | 'calibracion')[]; camiones: number } | null {
  const c = raw.trim().toUpperCase()
  if (c === 'CMP') return { servicios: ['mantencion', 'calibracion'], camiones: 0 }
  if (c === 'C') return { servicios: ['calibracion'], camiones: 0 }
  if (c === 'MP' || c === 'AG') return { servicios: ['mantencion'], camiones: 0 }
  const cp = /^CP(\d)?$/.exec(c)
  if (cp) return { servicios: ['calibracion'], camiones: cp[1] ? Number(cp[1]) : 1 }
  return null
}

const texto = (v: unknown) => (v == null ? '' : String(v)).trim()

/**
 * Lee una hoja de la planilla como matriz de valores (fila 0 = fila 1 de Excel).
 * Busca la fila de días (1..31), deduce el mes de los encabezados de semana y
 * avanza de mes cuando el número de día vuelve a bajar.
 */
export function leerHojaPlanilla(m: unknown[][], anioDefecto: number): HojaPlanilla {
  const titulo = m.slice(0, 3).map((r) => (r ?? []).map(texto).join(' ')).join(' ')
  const anio = Number(/\b(20\d\d)\b/.exec(titulo)?.[1] ?? anioDefecto)

  // Fila de días: la que tiene más celdas enteras entre 1 y 31.
  let filaDias = -1, mejor = 0
  for (let i = 0; i < Math.min(m.length, 15); i++) {
    const n = (m[i] ?? []).filter((v) => typeof v === 'number' && Number.isInteger(v) && v >= 1 && v <= 31).length
    if (n > mejor) { mejor = n; filaDias = i }
  }
  if (filaDias < 0 || mejor < 7) return { filas: [], ignorados: [], desde: null, hasta: null }

  const dias = m[filaDias] ?? []
  const encab = m[filaDias - 1] ?? []
  const colFecha = new Map<number, string>()
  let mes: number | null = null, anioCur = anio, prev = 0
  for (let c = 0; c < dias.length; c++) {
    const d = dias[c]
    if (!(typeof d === 'number' && Number.isInteger(d) && d >= 1 && d <= 31)) continue
    if (mes == null) {
      // Encabezado de la semana que cubre esta columna (celda combinada: el texto está a la izquierda).
      for (let k = c; k >= 0 && mes == null; k--) { const t = texto(encab[k]); if (t) mes = mesEnTexto(t) }
      if (mes == null) mes = mesEnTexto(titulo) ?? 1
    } else if (d < prev) {
      mes++
      if (mes > 12) { mes = 1; anioCur++ }
    }
    prev = d
    colFecha.set(c, `${anioCur}-${pad(mes)}-${pad(d)}`)
  }

  const filas: FilaPlanilla[] = []
  const ign = new Map<string, number>()
  for (let i = filaDias + 2; i < m.length; i++) {
    const r = m[i] ?? []
    const nombre = texto(r[0])
    if (!nombre) continue
    if (/^actividades por d|^leyenda/i.test(nombre)) break
    const entradas: CodigoPlanilla[] = []
    colFecha.forEach((fecha, c) => {
      const raw = texto(r[c])
      if (!raw) return
      const it = interpretarCodigo(raw)
      if (!it) { ign.set(raw.toUpperCase(), (ign.get(raw.toUpperCase()) ?? 0) + 1); return }
      entradas.push({ fecha, codigo: raw.toUpperCase(), ...it })
    })
    // Títulos de sección (RONDA…, CAMIONES —…) no tienen cuadrilla ni códigos.
    if (entradas.length === 0 && !texto(r[1])) continue
    filas.push({ nombre, fila: i + 1, esCamiones: /cami[oó]n/i.test(nombre), entradas })
  }
  const fechas = Array.from(colFecha.values()).sort()
  return {
    filas,
    ignorados: Array.from(ign.entries()).map(([codigo, n]) => ({ codigo, n })),
    desde: fechas[0] ?? null,
    hasta: fechas[fechas.length - 1] ?? null,
  }
}

// ── Emparejar nombres de la planilla con instalaciones ──────────────────────
const SINONIMOS: [RegExp, string][] = [
  [/estaci[oó]n de servicios?/g, 'eess'], [/\beds\b/g, 'eess'], [/semi ?m[oó]vil/g, 'semimovil'], [/\bsm\b/g, 'semimovil'],
  [/sulfuros?/g, 'sulfuro'], [/[oó]xidos?/g, 'oxido'],
]
export function normalizarNombre(s: string): string {
  let t = s.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '')
  for (const [re, rep] of SINONIMOS) t = t.replace(re, rep)
  return t.replace(/[^a-z0-9 ]+/g, ' ').replace(/\s+/g, ' ').trim()
}

/** Instalación más parecida por palabras en común (null si nada se parece). */
export function emparejar<T extends { id: string; nombre: string }>(nombre: string, candidatos: T[]): T | null {
  // Los números cuentan ("Semimóvil 1" ≠ "Semimóvil 2"), las letras sueltas no.
  const palabras = (s: string) => normalizarNombre(s).split(' ').filter((w) => w.length > 1 || /\d/.test(w))
  const a = new Set(palabras(nombre))
  const numsA = Array.from(a).filter((w) => /^\d+$/.test(w))
  let mejor: T | null = null, puntaje = 0
  for (const c of candidatos) {
    const b = palabras(c.nombre)
    if (b.length === 0) continue
    const numsB = b.filter((w) => /^\d+$/.test(w))
    if (numsA.length && numsB.length && !numsB.some((n) => a.has(n))) continue
    const comunes = b.filter((w) => a.has(w)).length
    const s = comunes / Math.max(a.size, b.length)
    if (s > puntaje) { puntaje = s; mejor = c }
  }
  return puntaje >= 0.5 ? mejor : null
}
