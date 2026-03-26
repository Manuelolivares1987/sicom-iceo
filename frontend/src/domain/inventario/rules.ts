import type { TipoMovimiento, EstadoOT } from '@/types/database'

/**
 * Inventory business rules - pure logic, no Supabase imports.
 */

/** Movement types that require an associated OT */
export const TIPOS_REQUIEREN_OT: TipoMovimiento[] = ['salida', 'merma']

/** Movement types that require supervisor authorization */
export const TIPOS_REQUIEREN_AUTORIZACION: TipoMovimiento[] = ['ajuste_negativo', 'merma']

/** OT states that allow material withdrawal */
export const ESTADOS_OT_PERMITEN_RETIRO: EstadoOT[] = ['asignada', 'en_ejecucion']

/**
 * Check if an OT in the given state allows material withdrawal.
 */
export function canRetirarMaterial(estadoOT: EstadoOT): boolean {
  return ESTADOS_OT_PERMITEN_RETIRO.includes(estadoOT)
}

/**
 * Check if this movement type requires an associated OT.
 */
export function requiresOT(tipo: TipoMovimiento): boolean {
  return TIPOS_REQUIEREN_OT.includes(tipo)
}

/**
 * Check if this movement type requires supervisor authorization.
 */
export function requiresAutorizacion(tipo: TipoMovimiento): boolean {
  return TIPOS_REQUIEREN_AUTORIZACION.includes(tipo)
}

/**
 * Calculate Costo Promedio Ponderado (Weighted Average Cost).
 * Used when new stock enters to update the average unit cost.
 *
 * @param stockActual - Current quantity in stock
 * @param costoActual - Current average unit cost
 * @param cantidadNueva - Quantity being added
 * @param costoNuevo - Unit cost of incoming stock
 * @returns New weighted average cost per unit
 */
export function calculateCPP(
  stockActual: number,
  costoActual: number,
  cantidadNueva: number,
  costoNuevo: number
): number {
  const totalQuantity = stockActual + cantidadNueva
  if (totalQuantity <= 0) return 0

  const valorActual = stockActual * costoActual
  const valorNuevo = cantidadNueva * costoNuevo

  return (valorActual + valorNuevo) / totalQuantity
}

const MOVIMIENTO_LABELS: Record<TipoMovimiento, string> = {
  entrada: 'Entrada',
  salida: 'Salida',
  ajuste_positivo: 'Ajuste (+)',
  ajuste_negativo: 'Ajuste (-)',
  transferencia_entrada: 'Transferencia (Entrada)',
  transferencia_salida: 'Transferencia (Salida)',
  merma: 'Merma',
  devolucion: 'Devolucion',
}

const MOVIMIENTO_COLORS: Record<TipoMovimiento, string> = {
  entrada: 'bg-green-100 text-green-700',
  salida: 'bg-red-100 text-red-700',
  ajuste_positivo: 'bg-blue-100 text-blue-700',
  ajuste_negativo: 'bg-orange-100 text-orange-700',
  transferencia_entrada: 'bg-cyan-100 text-cyan-700',
  transferencia_salida: 'bg-purple-100 text-purple-700',
  merma: 'bg-red-100 text-red-700',
  devolucion: 'bg-yellow-100 text-yellow-700',
}

/**
 * Get the Spanish display label for a movement type.
 */
export function getMovimientoLabel(tipo: TipoMovimiento): string {
  return MOVIMIENTO_LABELS[tipo]
}

/**
 * Get the Tailwind color classes for a movement type badge.
 */
export function getMovimientoColor(tipo: TipoMovimiento): string {
  return MOVIMIENTO_COLORS[tipo]
}
