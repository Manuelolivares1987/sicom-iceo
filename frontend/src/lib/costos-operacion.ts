// ============================================================================
// Cálculos del panel de costos de operación (puros, con tests).
// ============================================================================

/** Variación porcentual contra el período anterior; null si no hay base. */
export function variacionPct(actual: number, anterior: number | null | undefined): number | null {
  if (!anterior || anterior <= 0) return null
  return ((actual - anterior) / anterior) * 100
}

/** Parte sobre total en %, null si el total es 0. */
export function pct(parte: number, total: number): number | null {
  if (!total) return null
  return (parte / total) * 100
}

/** Horas mínimas para que un costo por hora signifique algo. */
export const HORAS_MINIMAS_CPH = 100

/**
 * Costo por hora contra la mediana de su tipo de equipo. null si no se puede
 * comparar (pocas horas, sin mediana o tipo con un solo equipo).
 */
export function vsMediana(costoHora: number | null, mediana: number | null, horas: number | null,
                          nTipo: number | null): number | null {
  if (costoHora == null || !mediana || (horas ?? 0) < HORAS_MINIMAS_CPH || (nTipo ?? 0) < 2) return null
  return costoHora / mediana
}

/** Semáforo de calidad del dato: qué parte del gasto llega a un equipo. */
export function nivelAsignacion(pctAsignado: number | null): 'bien' | 'atencion' | 'mal' | null {
  if (pctAsignado == null) return null
  if (pctAsignado >= 90) return 'bien'
  if (pctAsignado >= 70) return 'atencion'
  return 'mal'
}

/** Primer día del mes, en ISO (YYYY-MM-01). */
export function inicioMes(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-01`
}

/** Suma meses a un 'YYYY-MM-01'. */
export function sumarMeses(mesIso: string, n: number): string {
  const [y, m] = mesIso.split('-').map(Number)
  const t = y * 12 + (m - 1) + n
  return `${Math.floor(t / 12)}-${String((t % 12) + 1).padStart(2, '0')}-01`
}

export type RangoPreset = 'mes' | 'ytd' | '12m' | '3m'

/** Rango [desde, hasta] por meses completos, anclado al mes de `hoy`. */
export function rangoPreset(p: RangoPreset, hoy: Date): { desde: string; hasta: string } {
  const actual = inicioMes(hoy)
  switch (p) {
    case 'mes': return { desde: actual, hasta: actual }
    case '3m':  return { desde: sumarMeses(actual, -2), hasta: actual }
    case 'ytd': return { desde: `${hoy.getFullYear()}-01-01`, hasta: actual }
    case '12m': return { desde: sumarMeses(actual, -11), hasta: actual }
  }
}

const CLP = new Intl.NumberFormat('es-CL', { style: 'currency', currency: 'CLP', maximumFractionDigits: 0 })
const NUM = new Intl.NumberFormat('es-CL', { maximumFractionDigits: 0 })

export function fmtClp(v: number | null | undefined): string {
  return v == null ? '—' : CLP.format(v)
}

/** Millones con un decimal: 12.345.678 → "$12,3 M". */
export function fmtMM(v: number | null | undefined): string {
  if (v == null) return '—'
  return `$${(v / 1e6).toLocaleString('es-CL', { minimumFractionDigits: 1, maximumFractionDigits: 1 })} M`
}

export function fmtNum(v: number | null | undefined): string {
  return v == null ? '—' : NUM.format(v)
}

export function fmtPct(v: number | null | undefined, signo = false): string {
  if (v == null) return '—'
  const s = v.toLocaleString('es-CL', { maximumFractionDigits: 1, minimumFractionDigits: 1 })
  return `${signo && v > 0 ? '+' : ''}${s} %`
}
