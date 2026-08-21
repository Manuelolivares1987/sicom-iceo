// ============================================================================
// El vocabulario de estados de flota, en un solo lugar.
// ----------------------------------------------------------------------------
// Antes cada pantalla escribía su propia tabla de códigos. Cuando MIG306 sumó
// 'S' (siniestrado / robado) el listado de Sugerencias lo mostró como una
// píldora gris "S · S" porque su tabla local no lo tenía. Este módulo es la
// única definición: si mañana entra otro código, entra aquí y aparece en
// Sugerencias, en Activos y en la ficha a la vez.
//
// Este es el estado que confirma el planificador cada día en
// /dashboard/flota/sugerencias y que queda en estado_diario_flota. Es el que
// manda: la ficha del equipo (activos.estado) se sincroniza desde él (MIG307).
// ============================================================================

export type EstadoFlotaCodigo =
  | 'A' | 'C' | 'D' | 'H' | 'R' | 'M' | 'T' | 'F' | 'V' | 'U' | 'L' | 'S'

export const ESTADO_FLOTA_COLOR: Record<string, string> = {
  A: '#16A34A', // Arrendado
  C: '#15803D', // En contrato
  L: '#4F46E5', // Leasing
  U: '#0891B2', // Uso interno
  D: '#2563EB', // Disponible
  H: '#A855F7', // Habilitación
  R: '#06B6D4', // Recepción
  M: '#F59E0B', // Mantención
  T: '#FB923C', // Taller
  F: '#DC2626', // Fuera de servicio
  V: '#9333EA', // Venta
  S: '#7F1D1D', // Siniestrado / robado (MIG306)
}

export const ESTADO_FLOTA_LABEL: Record<string, string> = {
  A: 'Arrendado',
  C: 'En contrato',
  D: 'Disponible',
  H: 'Habilitación',
  R: 'Recepción',
  M: 'Mantención',
  T: 'Taller',
  F: 'Fuera de servicio',
  V: 'Venta',
  U: 'Uso interno',
  L: 'Leasing',
  S: 'Siniestrado / robado',
}

// Orden en que se ofrecen al planificador: primero lo comercial, después lo
// transitorio, al final lo excepcional.
export const ESTADO_FLOTA_OPCIONES: EstadoFlotaCodigo[] =
  ['A', 'C', 'D', 'H', 'R', 'M', 'T', 'F', 'U', 'L', 'V', 'S']

// Cómo se traduce el estado del planificador al estado operativo de la ficha.
// Mismo mapeo que rpc_confirmar_estado_dia y rpc_actualizar_estado_diario_manual
// en la base (MIG307). Se replica aquí sólo para explicarlo en pantalla.
export const ESTADO_FLOTA_A_FICHA: Record<string, 'operativo' | 'en_mantenimiento' | 'fuera_servicio'> = {
  M: 'en_mantenimiento', T: 'en_mantenimiento', H: 'en_mantenimiento',
  F: 'fuera_servicio', S: 'fuera_servicio',
}

export function estadoFlotaLabel(codigo: string | null | undefined): string {
  if (!codigo) return 'Sin estado'
  return ESTADO_FLOTA_LABEL[codigo] ?? codigo
}

export function estadoFlotaColor(codigo: string | null | undefined): string {
  if (!codigo) return '#9CA3AF'
  return ESTADO_FLOTA_COLOR[codigo] ?? '#9CA3AF'
}
