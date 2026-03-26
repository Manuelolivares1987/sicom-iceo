import type { EstadoOT } from '@/types/database'

/**
 * OT State Machine - Valid transitions between OT states
 * Pure business logic, no Supabase imports.
 */
export const VALID_TRANSITIONS: Record<EstadoOT, EstadoOT[]> = {
  creada: ['asignada', 'cancelada'],
  asignada: ['en_ejecucion', 'no_ejecutada', 'cancelada'],
  en_ejecucion: ['pausada', 'ejecutada_ok', 'ejecutada_con_observaciones', 'no_ejecutada'],
  pausada: ['en_ejecucion', 'no_ejecutada', 'cancelada'],
  ejecutada_ok: [],
  ejecutada_con_observaciones: [],
  no_ejecutada: [],
  cancelada: [],
}

const TERMINAL_STATES: EstadoOT[] = [
  'ejecutada_ok',
  'ejecutada_con_observaciones',
  'no_ejecutada',
  'cancelada',
]

const ESTADO_LABELS: Record<EstadoOT, string> = {
  creada: 'Creada',
  asignada: 'Asignada',
  en_ejecucion: 'En Ejecucion',
  pausada: 'Pausada',
  ejecutada_ok: 'Ejecutada OK',
  ejecutada_con_observaciones: 'Con Observaciones',
  no_ejecutada: 'No Ejecutada',
  cancelada: 'Cancelada',
}

/**
 * Check if a transition from one state to another is valid.
 */
export function canTransition(from: EstadoOT, to: EstadoOT): boolean {
  return VALID_TRANSITIONS[from].includes(to)
}

/**
 * Get all available transitions from the given state.
 */
export function getAvailableTransitions(estado: EstadoOT): EstadoOT[] {
  return VALID_TRANSITIONS[estado]
}

/**
 * Check if the state is terminal (no further transitions possible).
 */
export function isTerminalState(estado: EstadoOT): boolean {
  return TERMINAL_STATES.includes(estado)
}

/**
 * Returns true if transitioning to this state requires a causa (reason).
 * Only `no_ejecutada` requires a causa.
 */
export function requiresCausa(estado: EstadoOT): boolean {
  return estado === 'no_ejecutada'
}

/**
 * Returns true if transitioning to this state requires evidence (photos/docs).
 * `ejecutada_ok` and `ejecutada_con_observaciones` require evidence.
 */
export function requiresEvidencia(estado: EstadoOT): boolean {
  return estado === 'ejecutada_ok' || estado === 'ejecutada_con_observaciones'
}

/**
 * Get the Spanish display label for a state.
 */
export function getTransitionLabel(estado: EstadoOT): string {
  return ESTADO_LABELS[estado]
}

/**
 * Get the action buttons that should be shown for a given OT state.
 * Returns an array of button configs ordered by relevance.
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
        { estado: 'en_ejecucion', label: 'Iniciar Ejecucion', variant: 'primary', icon: 'Play' },
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
