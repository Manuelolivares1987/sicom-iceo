// Geometría del Gantt del taller: compartida por el planificador y el televisor.
// Solo fechas y posiciones, sin datos ni pantalla, para poder probarla.

export type VistaBarra = 'ok' | 'por_aprobar' | 'falta' | 'atraso' | 'hoy' | 'plan'

export interface BarraBase {
  id: string
  inicio: string // YYYY-MM-DD
  fin: string
}

export interface BarraColocada<T extends BarraBase> {
  barra: T
  /** Primera columna, desde 0 */
  col: number
  /** Cuántas columnas ocupa */
  largo: number
  /** Fila dentro del camión cuando dos barras se topan */
  carril: number
  /** Viene de antes del rango visible */
  cortadaInicio: boolean
  /** Sigue después del rango visible */
  cortadaFin: boolean
}

const aDate = (iso: string) => new Date(`${iso.slice(0, 10)}T12:00:00`)
const aIso = (d: Date) =>
  `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`

/** Días de lunes a sábado: el taller no trabaja el domingo y le quitaría ancho a todo. */
export function diasVisibles(desde: string, hasta: string): string[] {
  const out: string[] = []
  for (const d = aDate(desde); d <= aDate(hasta); d.setDate(d.getDate() + 1)) {
    if (d.getDay() !== 0) out.push(aIso(d))
  }
  return out
}

/** Lunes de la semana de una fecha, más `semanas` semanas. */
export function lunesDe(fecha: string, semanas = 0): string {
  const d = aDate(fecha)
  const dow = d.getDay()
  d.setDate(d.getDate() + (dow === 0 ? -6 : 1 - dow) + semanas * 7)
  return aIso(d)
}

export function sumarDias(fecha: string, dias: number): string {
  const d = aDate(fecha)
  d.setDate(d.getDate() + dias)
  return aIso(d)
}

export function diasEntre(desde: string, hasta: string): number {
  return Math.round((aDate(hasta).getTime() - aDate(desde).getTime()) / 86_400_000)
}

/**
 * Ubica cada barra en columnas y carriles. Lo atrasado de antes del rango se
 * pega al borde izquierdo en vez de desaparecer: si no se ve, nadie lo reprograma.
 * Lo que queda entero después del rango no se dibuja.
 */
export function colocarBarras<T extends BarraBase>(barras: T[], dias: string[]): BarraColocada<T>[] {
  if (dias.length === 0) return []
  const primero = dias[0]
  const ultimo = dias[dias.length - 1]
  const ordenadas = [...barras].sort((a, b) => a.inicio.localeCompare(b.inicio) || a.fin.localeCompare(b.fin))
  const finCarril: number[] = []
  const out: BarraColocada<T>[] = []
  for (const barra of ordenadas) {
    const inicio = barra.inicio.slice(0, 10)
    const fin = barra.fin.slice(0, 10)
    if (inicio > ultimo) continue
    // Un domingo cae en el primer día visible siguiente o anterior.
    const iniIdx = inicio < primero ? 0 : dias.findIndex((d) => d >= inicio)
    let finIdx = fin > ultimo ? dias.length - 1 : dias.length - 1 - [...dias].reverse().findIndex((d) => d <= fin)
    if (fin < primero) finIdx = 0
    const col = iniIdx
    const largo = Math.max(1, finIdx - iniIdx + 1)
    let carril = finCarril.findIndex((f) => f < col)
    if (carril === -1) carril = finCarril.length
    finCarril[carril] = col + largo - 1
    out.push({ barra, col, largo, carril, cortadaInicio: inicio < primero, cortadaFin: fin > ultimo })
  }
  return out
}

export const carrilesDe = (colocadas: { carril: number }[]) =>
  colocadas.reduce((max, c) => Math.max(max, c.carril + 1), 1)

/** «RT vence en 30 días», en el largo que cabe en un televisor. */
export function textoPapel(nombre: string, estado: string, dias: number | null): string {
  if (estado === 'sin_fecha') return `${nombre}: falta la fecha`
  if (dias === null) return nombre
  if (dias < 0) return `${nombre} venció hace ${-dias} d`
  if (dias === 0) return `${nombre} vence hoy`
  return `${nombre} vence en ${dias} d`
}

/** Nombre corto del papel: en una TV no caben «Revisión técnica» ni «Permiso de circulación». */
export function papelCorto(tipo: string, etiqueta?: string | null): string {
  const cortos: Record<string, string> = {
    revision_tecnica: 'RT', permiso_circulacion: 'Permiso', soap: 'SOAP', tc8_sec: 'TC8',
    hermeticidad: 'Hermeticidad', analisis_gases: 'Gases',
  }
  return cortos[tipo] ?? (etiqueta && etiqueta !== tipo ? etiqueta : tipo.replace(/_/g, ' '))
}

export function etiquetaEstadoBarra(vista: VistaBarra, evidencia?: string | null, origen?: string): string {
  switch (vista) {
    case 'ok': return '✓ Evidencia OK'
    case 'por_aprobar': return 'Por aprobar'
    case 'falta':
      if (origen === 'ot') return 'Falta cierre'
      return evidencia === 'certificado' ? 'Falta certif.' : 'Falta foto'
    case 'atraso': return '! Atrasada'
    case 'hoy': return 'En curso'
    default: return ''
  }
}
