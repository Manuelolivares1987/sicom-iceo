import type { EstadoOT } from '@/types/database'

/**
 * OT State Machine - Valid transitions between OT states
 * Pure business logic, no Supabase imports.
 *
 * DIAGRAMA:
 *   creada → asignada → en_ejecucion → ejecutada_ok → cerrada
 *     │         │          │  │             │
 *     │cancel   │cancel    │  │ no_ejec     │ supervisor
 *     ▼         ▼          ▼  ▼             ▼
 *   cancelada            pausada   ejecutada_con_obs → cerrada
 *                          │              │
 *                          └─► en_ejecucion
 *                          └─► no_ejecutada → cerrada
 */
export const VALID_TRANSITIONS: Record<EstadoOT, EstadoOT[]> = {
  creada: ['asignada', 'cancelada'],
  asignada: ['en_ejecucion', 'no_ejecutada', 'cancelada'],
  en_ejecucion: ['pausada', 'ejecutada_ok', 'ejecutada_con_observaciones', 'no_ejecutada'],
  pausada: ['en_ejecucion', 'no_ejecutada', 'cancelada'],
  ejecutada_ok: ['cerrada'],
  ejecutada_con_observaciones: ['cerrada'],
  no_ejecutada: ['cerrada'],
  cancelada: [],
  cerrada: [],
}

/** Estados terminales absolutos — no se puede salir de aquí */
const ABSOLUTE_TERMINAL: EstadoOT[] = ['cancelada', 'cerrada']

/** Estados donde la OT ya no puede ser modificada (checklist, evidencia, materiales) */
const IMMUTABLE_STATES: EstadoOT[] = [
  'ejecutada_ok', 'ejecutada_con_observaciones',
  'no_ejecutada', 'cancelada', 'cerrada',
]

/** Estados que esperan cierre supervisor */
const AWAITING_CLOSURE: EstadoOT[] = [
  'ejecutada_ok', 'ejecutada_con_observaciones', 'no_ejecutada',
]

const ESTADO_LABELS: Record<EstadoOT, string> = {
  creada: 'Creada',
  asignada: 'Asignada',
  en_ejecucion: 'En Ejecución',
  pausada: 'Pausada',
  ejecutada_ok: 'Ejecutada OK',
  ejecutada_con_observaciones: 'Con Observaciones',
  no_ejecutada: 'No Ejecutada',
  cancelada: 'Cancelada',
  cerrada: 'Cerrada',
}

const ESTADO_COLORS: Record<EstadoOT, string> = {
  creada: 'bg-gray-100 text-gray-700',
  asignada: 'bg-blue-100 text-blue-700',
  en_ejecucion: 'bg-amber-100 text-amber-700',
  pausada: 'bg-orange-100 text-orange-700',
  ejecutada_ok: 'bg-green-100 text-green-700',
  ejecutada_con_observaciones: 'bg-yellow-100 text-yellow-700',
  no_ejecutada: 'bg-red-100 text-red-700',
  cancelada: 'bg-gray-200 text-gray-500',
  cerrada: 'bg-purple-100 text-purple-700',
}

export function canTransition(from: EstadoOT, to: EstadoOT): boolean {
  return (VALID_TRANSITIONS[from] ?? []).includes(to)
}

export function getAvailableTransitions(estado: EstadoOT): EstadoOT[] {
  return VALID_TRANSITIONS[estado] ?? []
}

/** True si el estado es terminal absoluto (cancelada, cerrada) */
export function isTerminalState(estado: EstadoOT): boolean {
  return ABSOLUTE_TERMINAL.includes(estado)
}

/** True si la OT no puede ser modificada (checklist, evidencia, materiales) */
export function isImmutableState(estado: EstadoOT): boolean {
  return IMMUTABLE_STATES.includes(estado)
}

/** True si la OT espera cierre por supervisor */
export function isAwaitingClosure(estado: EstadoOT): boolean {
  return AWAITING_CLOSURE.includes(estado)
}

export function requiresCausa(estado: EstadoOT): boolean {
  return estado === 'no_ejecutada'
}

export function requiresEvidencia(estado: EstadoOT): boolean {
  return estado === 'ejecutada_ok' || estado === 'ejecutada_con_observaciones'
}

export function requiresObservaciones(estado: EstadoOT): boolean {
  return estado === 'ejecutada_con_observaciones'
}

export function getTransitionLabel(estado: EstadoOT): string {
  return ESTADO_LABELS[estado] ?? estado
}

export function getEstadoColor(estado: EstadoOT): string {
  return ESTADO_COLORS[estado] ?? 'bg-gray-100 text-gray-700'
}

/**
 * Get the action buttons for the technician based on current OT state.
 * Does NOT include supervisor actions (cerrar).
 */
export function getActionButtons(
  estado: EstadoOT
): Array<{
  estado: EstadoOT
  label: string
  variant: 'primary' | 'secondary' | 'danger'
  icon: string
}> {
  switch (estado) {
    case 'creada':
      return [
        { estado: 'asignada', label: 'Asignar', variant: 'primary', icon: 'UserPlus' },
        { estado: 'cancelada', label: 'Cancelar', variant: 'danger', icon: 'XCircle' },
      ]
    case 'asignada':
      return [
        { estado: 'en_ejecucion', label: 'Iniciar Ejecución', variant: 'primary', icon: 'Play' },
        { estado: 'no_ejecutada', label: 'No Ejecutar', variant: 'secondary', icon: 'AlertTriangle' },
        { estado: 'cancelada', label: 'Cancelar', variant: 'danger', icon: 'XCircle' },
      ]
    case 'en_ejecucion':
      return [
        { estado: 'ejecutada_ok', label: 'Finalizar OK', variant: 'primary', icon: 'CheckCircle' },
        { estado: 'ejecutada_con_observaciones', label: 'Finalizar con Obs.', variant: 'secondary', icon: 'AlertCircle' },
        { estado: 'pausada', label: 'Pausar', variant: 'secondary', icon: 'Pause' },
        { estado: 'no_ejecutada', label: 'No Ejecutar', variant: 'danger', icon: 'AlertTriangle' },
      ]
    case 'pausada':
      return [
        { estado: 'en_ejecucion', label: 'Reanudar', variant: 'primary', icon: 'Play' },
        { estado: 'no_ejecutada', label: 'No Ejecutar', variant: 'secondary', icon: 'AlertTriangle' },
        { estado: 'cancelada', label: 'Cancelar', variant: 'danger', icon: 'XCircle' },
      ]
    default:
      return []
  }
}
