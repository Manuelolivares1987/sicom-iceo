import { supabase } from '@/lib/supabase'

// ============================================================================
// MIG47 - Supervision interna de jornadas (OK supervisor sin firma cliente)
// ============================================================================

export type JornadaPendienteSupervision = {
  plan_semanal_ot_id: string
  ot_id: string
  folio: string
  titulo: string | null
  linea_negocio: string
  avance_pct: number | null
  estado_plan: string
  plan_dia_id: string | null
  fecha_jornada: string | null
  nombre_dia: string | null
  llegada_faena_at: string | null
  cierre_jornada_at: string | null
  responsable_id: string | null
  responsable_email: string | null
  tiempo_en_faena_segundos: number | null
  tiempo_operativo_bruto_segundos: number | null
  tiempo_pausado_segundos: number | null
  tiempo_colacion_segundos: number | null
  tiempo_interferencia_mandante_segundos: number | null
  tiempo_efectivo_trabajo_segundos: number | null
  evid_antes: number
  evid_durante: number
  evid_despues: number
  firmas_operador: number
  planificacion_id: string
  planificacion_codigo: string
}

export type JornadasFiltro = {
  planificacionId?: string
  fechaDesde?: string
  fechaHasta?: string
}

export async function getJornadasPendientesSupervision(filtro?: JornadasFiltro) {
  let query = supabase
    .from('v_calama_jornadas_pendientes_supervision')
    .select('*')
    .order('cierre_jornada_at', { ascending: false, nullsFirst: false })
    .order('fecha_jornada', { ascending: false, nullsFirst: false })

  if (filtro?.planificacionId) query = query.eq('planificacion_id', filtro.planificacionId)
  if (filtro?.fechaDesde) query = query.gte('fecha_jornada', filtro.fechaDesde)
  if (filtro?.fechaHasta) query = query.lte('fecha_jornada', filtro.fechaHasta)

  const { data, error } = await query
  return { data: (data ?? []) as JornadaPendienteSupervision[], error }
}

export type EvidenciaJornada = {
  id: string
  contexto: string
  momento: string | null
  tipo: string
  archivo_url: string
  storage_path: string | null
  descripcion: string | null
  gps_lat: number | null
  gps_lng: number | null
  gps_accuracy: number | null
  geolocation_status: string | null
  client_uuid: string | null
  sync_status: string | null
  created_at: string
  created_by: string | null
}

export async function getEvidenciasPorOT(otId: string) {
  const { data, error } = await supabase
    .from('calama_evidencias')
    .select('*')
    .eq('ot_id', otId)
    .order('created_at', { ascending: true })
  return { data: (data ?? []) as unknown as EvidenciaJornada[], error }
}

export type FirmaJornada = {
  id: string
  plan_semanal_ot_id: string | null
  firmante_tipo: string
  firmante_nombre: string | null
  firmante_rut: string | null
  firma_url: string
  contexto: string | null
  gps_lat: number | null
  gps_lng: number | null
  observacion: string | null
  created_at: string
}

export async function getFirmasPorJornada(planSemanalOtId: string) {
  const { data, error } = await supabase
    .from('calama_firmas_jornada')
    .select('*')
    .eq('plan_semanal_ot_id', planSemanalOtId)
    .order('created_at', { ascending: true })
  return { data: (data ?? []) as unknown as FirmaJornada[], error }
}

export async function supervisarJornada(payload: {
  plan_semanal_ot_id: string
  comentario?: string
}) {
  const { data, error } = await supabase.rpc('rpc_calama_supervisar_jornada', {
    p_payload: payload,
  })
  return { data, error }
}

export async function devolverJornadaCorreccion(payload: {
  plan_semanal_ot_id: string
  motivo: string
  observacion?: string
}) {
  const { data, error } = await supabase.rpc('rpc_calama_devolver_jornada_correccion', {
    p_payload: payload,
  })
  return { data, error }
}
