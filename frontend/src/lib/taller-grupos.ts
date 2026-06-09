// Grupos de trabajo / mecánicos del taller — única fuente de verdad.
// Se usan al planificar (Plan Semanal) y al asignar recursos a una No Conformidad.
export const MECANICOS = ['Yusedl', 'Joel', 'Sergio', 'Marco', 'Felipe L', 'Felipe'] as const
export const MAX_MECANICOS = 2

export function grupoLabel(mecanicos: string[]): string | null {
  return mecanicos.length ? mecanicos.join(', ') : null
}
