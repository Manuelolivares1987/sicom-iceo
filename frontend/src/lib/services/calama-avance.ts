import { supabase } from '@/lib/supabase'

// ============================================================================
// Avance real de OTs Calama (MIG22)
// ============================================================================

export type FuenteAvance = 'excel' | 'operador' | 'planificador' | 'supervisor' | 'sistema'

export type CalamaAvanceEvento = {
  id: string
  ot_id: string
  plan_semanal_ot_id: string | null
  ejecucion_id: string | null
  avance_anterior: number | null
  avance_nuevo: number
  fuente: FuenteAvance
  motivo: string | null
  comentario: string | null
  created_by: string | null
  created_at: string
}

export type ActualizarAvanceManual = {
  ot_id: string
  avance_nuevo: number
  fuente?: 'planificador' | 'supervisor'
  motivo?: string
  comentario?: string
}

export async function actualizarAvanceManual(payload: ActualizarAvanceManual) {
  const { data, error } = await supabase.rpc('rpc_calama_actualizar_avance_ot', {
    p_payload: payload,
  })
  return { data, error }
}

export type MarcarCompletadaOperador = {
  ot_id: string
  ejecucion_id?: string
  comentario?: string
}

export async function marcarOTCompletadaOperador(payload: MarcarCompletadaOperador) {
  const { data, error } = await supabase.rpc('rpc_calama_marcar_ot_completada_operador', {
    p_payload: payload,
  })
  return { data, error }
}

export type RegistrarAvanceParcialOperador = {
  ot_id: string
  avance_nuevo: number
  comentario?: string
}

export async function registrarAvanceParcialOperador(payload: RegistrarAvanceParcialOperador) {
  const { data, error } = await supabase.rpc('rpc_calama_registrar_avance_operador', {
    p_payload: payload,
  })
  return { data, error }
}

export async function getEventosAvancePorOT(otId: string) {
  const { data, error } = await supabase
    .from('calama_ot_avance_eventos')
    .select('*')
    .eq('ot_id', otId)
    .order('created_at', { ascending: false })
  return { data: (data ?? []) as CalamaAvanceEvento[], error }
}
