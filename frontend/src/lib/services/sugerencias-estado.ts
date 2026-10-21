import { supabase } from '@/lib/supabase'

export interface SugerenciaEstado {
  activo_id: string
  patente: string
  equipamiento: string | null
  estado_actual: string | null
  estado_sugerido: string | null
  estado_guardado: string | null
  zona: string | null
  gps_ts: string | null
  coincide: boolean
  /** [MIG573] Prueba de vida: última evidencia de que el equipo existe y opera. */
  evidencia_fecha: string | null
  evidencia_fuente: string | null
  evidencia_dias: number | null
  /** Severidad del incidente abierto en el Centinela, si hay. */
  centinela: 'vigilar' | 'alto' | 'critico' | null
  /** Confirmar A/C exige justificación (≥10 caracteres). */
  requiere_justificacion: boolean
}

// Sugerencias de estado por GPS/geocerca para una fecha (NO aplica nada).
export async function getSugerenciasEstadoGps(fecha: string): Promise<SugerenciaEstado[]> {
  const { data, error } = await supabase.rpc('fn_sugerencias_estado_gps', { p_fecha: fecha })
  if (error) throw error
  return (data ?? []) as SugerenciaEstado[]
}

// [MIG633] Equipos que hoy están fuera del cálculo de fiabilidad (período abierto).
export interface ExclusionFiabilidad { activo_id: string; desde: string; motivo: string }

export async function getExclusionesFiabilidad(): Promise<ExclusionFiabilidad[]> {
  const { data, error } = await supabase
    .from('activo_fiabilidad_exclusion')
    .select('activo_id, desde, motivo')
    .is('hasta', null)
  if (error) throw error
  return (data ?? []) as ExclusionFiabilidad[]
}

/** Saca el equipo del cálculo desde `desde` (vacío = su primer día en el sistema). */
export async function excluirDeFiabilidad(activoId: string, motivo: string, desde: string | null) {
  const { error } = await supabase.rpc('rpc_fiabilidad_excluir', {
    p_activo_id: activoId, p_motivo: motivo.trim(), p_desde: desde || null,
  })
  if (error) throw error
}

/** Lo da de alta: vuelve a contar desde `desde` (vacío = hoy). */
export async function incluirEnFiabilidad(activoId: string, desde: string | null) {
  const { error } = await supabase.rpc('rpc_fiabilidad_incluir', { p_activo_id: activoId, p_desde: desde || null })
  if (error) throw error
}

// El planificador confirma (aplica) un estado para esa fecha.
// [MIG573] A/C sobre un equipo sin prueba de vida exige justificación; la
// base responde con un error que empieza por PRUEBA_DE_VIDA.
export async function confirmarEstadoDia(activoId: string, fecha: string, estado: string, justificacion?: string) {
  const { error } = await supabase.rpc('rpc_confirmar_estado_dia', {
    p_activo_id: activoId,
    p_fecha: fecha,
    p_estado: estado,
    p_justificacion: justificacion?.trim() || null,
  })
  if (error) throw error
}
