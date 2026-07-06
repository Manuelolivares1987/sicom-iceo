// Contrato de respuesta de fn_reporte_fiabilidad_publico (MIG186).
// Estas claves DEBEN venir siempre como arreglo; su ausencia es un error real
// (regresión tipo MIG146), no "sin datos". Centralizado para test de contrato.
export const CLAVES_REPORTE_FIABILIDAD = ['categorias', 'equipos', 'matriz', 'combustible'] as const

export function clavesFaltantesReporte(data: unknown): string[] {
  const d = (data ?? {}) as Record<string, unknown>
  return CLAVES_REPORTE_FIABILIDAD.filter((k) => !Array.isArray(d[k]))
}

export function reporteContratoValido(data: unknown): boolean {
  return clavesFaltantesReporte(data).length === 0
}
