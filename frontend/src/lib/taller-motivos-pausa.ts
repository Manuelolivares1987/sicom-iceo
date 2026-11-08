// [MIG672] Por qué se para el trabajo en el taller.
// ----------------------------------------------------------------------------
// Hasta noviembre de 2026, de 53 pausas 46 no tenían motivo y 7 decían «otro»:
// no había forma de saber cuántas horas se pierden esperando un repuesto. El
// mecánico elige con un toque; los códigos son los que valida la base
// (rpc_taller_pausar_ejecucion / rpc_taller_os_pausar). Agregar uno es tocar
// los dos lados.
export const MOTIVOS_PAUSA = [
  { v: 'fin_jornada', label: 'Fin de jornada', emoji: '🌙' },
  { v: 'colacion', label: 'Colación', emoji: '🍽️' },
  { v: 'espera_repuesto', label: 'Espera repuesto', emoji: '📦' },
  { v: 'equipo_no_disponible', label: 'Equipo no disponible', emoji: '🚚' },
  { v: 'otro', label: 'Otro', emoji: '✏️' },
] as const

export type MotivoPausa = (typeof MOTIVOS_PAUSA)[number]['v']

export const MOTIVO_PAUSA_LABEL: Record<string, string> =
  Object.fromEntries(MOTIVOS_PAUSA.map((m) => [m.v, m.label]))
