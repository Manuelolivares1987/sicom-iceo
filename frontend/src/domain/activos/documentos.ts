/**
 * Estado y vigencia de la documentación de un equipo.
 *
 * Renovar un papel NO pisa la fila anterior: inserta una versión nueva y la
 * anterior queda como histórico. Por eso todo lo que cuente vencidos tiene que
 * mirar solo la última versión de cada (equipo, tipo) — si cuenta el histórico,
 * el equipo queda marcado vencido para siempre aunque el papel esté al día.
 *
 * Estas reglas son el espejo exacto de la vista `v_certificacion_actual`
 * (MIG273). Si cambia una, cambia la otra.
 */

export type EstadoDocumento = 'vigente' | 'por_vencer' | 'vencido' | 'permanente'

/** Los documentos sin vencimiento real se cargaron con fecha 2099-12-31. */
const FECHA_PERMANENTE = '2099-01-01'

/** Días de anticipación con que un documento pasa a "por vencer". */
export const DIAS_POR_VENCER = 30

export interface DocumentoEquipo {
  id?: string
  activo_id?: string
  tipo: string
  fecha_vencimiento: string | null
  created_at?: string | null
}

/** Estado real del documento, calculado desde la fecha (no desde la columna
 *  `estado`, que la refresca un job diario y puede ir un día atrasada). */
export function estadoDocumento(fechaVencimiento: string | null | undefined): EstadoDocumento {
  if (!fechaVencimiento || fechaVencimiento >= FECHA_PERMANENTE) return 'permanente'

  const hoy = new Date()
  hoy.setHours(0, 0, 0, 0)
  const limite = new Date(hoy)
  limite.setDate(limite.getDate() + DIAS_POR_VENCER)

  const venc = new Date(`${fechaVencimiento}T00:00:00`)
  if (venc < hoy) return 'vencido'
  if (venc <= limite) return 'por_vencer'
  return 'vigente'
}

/** Días que faltan para el vencimiento (negativo si ya venció). */
export function diasParaVencer(fechaVencimiento: string | null | undefined): number | null {
  if (!fechaVencimiento || fechaVencimiento >= FECHA_PERMANENTE) return null
  const hoy = new Date()
  hoy.setHours(0, 0, 0, 0)
  const venc = new Date(`${fechaVencimiento}T00:00:00`)
  return Math.round((venc.getTime() - hoy.getTime()) / 86_400_000)
}

/** Clave de agrupación: un documento es "el mismo papel" por equipo y tipo. */
function claveDocumento(d: DocumentoEquipo): string {
  return `${d.activo_id ?? ''}|${d.tipo}`
}

/** La versión que rige hoy de cada documento: la de vencimiento más lejano y,
 *  a igualdad, la cargada más tarde. Igual que `v_certificacion_actual`. */
export function documentosVigentes<T extends DocumentoEquipo>(docs: T[] | null | undefined): T[] {
  if (!docs?.length) return []
  const porClave = new Map<string, T>()
  for (const d of docs) {
    const k = claveDocumento(d)
    const previo = porClave.get(k)
    if (!previo || ganaComoActual(d, previo)) porClave.set(k, d)
  }
  return Array.from(porClave.values())
}

function ganaComoActual(a: DocumentoEquipo, b: DocumentoEquipo): boolean {
  const va = a.fecha_vencimiento ?? ''
  const vb = b.fecha_vencimiento ?? ''
  if (va !== vb) return va > vb
  return (a.created_at ?? '') > (b.created_at ?? '')
}

/** Las versiones anteriores, ya reemplazadas por una renovación. */
export function documentosReemplazados<T extends DocumentoEquipo>(docs: T[] | null | undefined): T[] {
  if (!docs?.length) return []
  const vigentes = new Set(documentosVigentes(docs).map((d) => d.id))
  return docs.filter((d) => !vigentes.has(d.id))
}
