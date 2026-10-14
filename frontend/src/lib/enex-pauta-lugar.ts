// Avance de la pauta trimestral por lugar (MIG591) — como la planilla
// "Pauta_Lomas_Trimestral_V02": cada Truck Shop tiene 33 actividades;
// % avance real = ejecutadas ÷ total, % proyectado = + las planificadas que
// aún están a tiempo. Puro, para probarlo.

import type { EnexLugarItem, EnexActividadTrimestre, EstadoActividad } from '@/lib/services/enex'

export type Marca = 'x' | 'P' | 'RP' | 'n/a' | ''

export const MARCA_DE: Record<EstadoActividad, Marca> = {
  ejecutada: 'x', planificada: 'P', reprogramada: 'RP', no_aplica: 'n/a', pendiente: '',
}

/** Fecha en la que la actividad aparece en la matriz (la de ejecución si se hizo). */
export function fechaDe(a: EnexActividadTrimestre | undefined): string | null {
  if (!a) return null
  return a.estado === 'ejecutada' ? (a.fecha_ejecucion ?? a.fecha_plan) : a.fecha_plan
}

export type AvanceArea = {
  area: string
  total: number
  ejecutadas: number
  noAplica: number
  planificadas: number      // con fecha de hoy en adelante
  atrasadas: number         // planificadas/reprogramadas con fecha pasada, sin ejecutar
  sinPlan: number           // pendientes sin fecha
  pctReal: number | null
  pctProyectado: number | null
}

const pct = (n: number, d: number) => (d > 0 ? Math.round((n / d) * 1000) / 10 : null)

export function avancePorArea(items: EnexLugarItem[], acts: EnexActividadTrimestre[], hoy: string): { areas: AvanceArea[]; total: AvanceArea } {
  const porItem = new Map(acts.map((a) => [a.lugar_item_id, a]))
  const areas = new Map<string, AvanceArea>()
  const nuevo = (area: string): AvanceArea => ({ area, total: 0, ejecutadas: 0, noAplica: 0, planificadas: 0, atrasadas: 0, sinPlan: 0, pctReal: null, pctProyectado: null })
  for (const it of items) {
    const a = areas.get(it.area) ?? nuevo(it.area)
    a.total++
    const act = porItem.get(it.lugar_item_id)
    const e = act?.estado ?? 'pendiente'
    if (e === 'ejecutada') a.ejecutadas++
    else if (e === 'no_aplica') a.noAplica++
    else if ((e === 'planificada' || e === 'reprogramada') && act?.fecha_plan) {
      if (act.fecha_plan >= hoy) a.planificadas++
      else a.atrasadas++
    } else a.sinPlan++
    areas.set(it.area, a)
  }
  const cerrar = (a: AvanceArea): AvanceArea => ({ ...a, pctReal: pct(a.ejecutadas, a.total), pctProyectado: pct(a.ejecutadas + a.planificadas, a.total) })
  const lista = Array.from(areas.values()).map(cerrar)
  const total = cerrar(lista.reduce((s, a) => ({
    ...s, total: s.total + a.total, ejecutadas: s.ejecutadas + a.ejecutadas, noAplica: s.noAplica + a.noAplica,
    planificadas: s.planificadas + a.planificadas, atrasadas: s.atrasadas + a.atrasadas, sinPlan: s.sinPlan + a.sinPlan,
  }), nuevo('Total')))
  return { areas: lista, total }
}

/** Columnas de la matriz: las fechas con alguna marca, en orden (como la planilla). */
export function columnasFecha(acts: EnexActividadTrimestre[]): string[] {
  return Array.from(new Set(acts.map(fechaDe).filter(Boolean) as string[])).sort()
}

/** Primer día del trimestre calendario que contiene la fecha. */
export function trimestreCalendario(iso: string): string {
  const [y, m] = iso.split('-').map(Number)
  return `${y}-${String(Math.floor((m - 1) / 3) * 3 + 1).padStart(2, '0')}-01`
}

export function moverTrimestre(inicio: string, delta: number): string {
  const [y, m] = inicio.split('-').map(Number)
  const t = (y * 12 + (m - 1)) + delta * 3
  return `${Math.floor(t / 12)}-${String((t % 12) + 1).padStart(2, '0')}-01`
}

const ROMANO = ['1°', '2°', '3°', '4°']
export function etiquetaTrimestre(inicio: string): string {
  const [y, m] = inicio.split('-').map(Number)
  const MES = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic']
  return `${ROMANO[Math.floor((m - 1) / 3)]}T ${y} · ${MES[m - 1]}–${MES[(m + 1) % 12]}`
}
