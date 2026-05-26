import { supabase } from '@/lib/supabase'

export interface SugerenciaEstado {
  activo_id: string
  patente: string
  equipamiento: string | null
  estado_actual: string | null
  estado_sugerido: string | null
  zona: string | null
  gps_ts: string | null
  coincide: boolean
}

// Sugerencias de estado por GPS/geocerca para una fecha (NO aplica nada).
export async function getSugerenciasEstadoGps(fecha: string): Promise<SugerenciaEstado[]> {
  const { data, error } = await supabase.rpc('fn_sugerencias_estado_gps', { p_fecha: fecha })
  if (error) throw error
  return (data ?? []) as SugerenciaEstado[]
}

// El planificador confirma (aplica) un estado para esa fecha.
export async function confirmarEstadoDia(activoId: string, fecha: string, estado: string) {
  const { error } = await supabase.rpc('rpc_confirmar_estado_dia', {
    p_activo_id: activoId,
    p_fecha: fecha,
    p_estado: estado,
  })
  if (error) throw error
}
