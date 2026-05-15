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

// ── MIG50: tablero en vivo + cierre del dia ─────────────────────────────────

export type CategoriaVivo =
  | 'corriendo'
  | 'pausada'
  | 'cerrada_hoy'
  | 'en_faena_sin_iniciar'
  | 'pendiente_inicio'

export type JornadaEnVivo = {
  plan_semanal_ot_id: string
  ot_id: string
  folio: string
  titulo: string | null
  avance_pct: number | null
  descripcion: string | null
  estado_plan: string
  fecha_jornada: string | null
  nombre_dia: string | null
  llegada_faena_at: string | null
  cierre_jornada_at: string | null
  responsable_id: string | null
  responsable_nombre: string | null
  responsable_email: string | null
  // Ejecucion en vivo
  ejecucion_id: string | null
  ejecucion_estado: 'en_ejecucion' | 'pausada' | null
  ejecucion_started_at: string | null
  last_event_at: string | null
  tiempo_total_segundos: number | null
  tiempo_pausado_segundos: number | null
  tiempo_efectivo_segundos: number | null
  tiempo_colacion_segundos: number | null
  ejecutor_nombre: string | null
  ejecutor_email: string | null
  // Tiempos finales (post cierre)
  tiempo_en_faena_segundos: number | null
  tiempo_operativo_bruto_segundos: number | null
  tiempo_efectivo_trabajo_segundos: number | null
  tiempo_interferencia_mandante_segundos: number | null
  // Ultima evidencia / evento
  ultima_evidencia_url: string | null
  ultima_evidencia_contexto: string | null
  ultima_evidencia_momento: string | null
  ultima_evidencia_lat: number | null
  ultima_evidencia_lng: number | null
  ultima_evidencia_at: string | null
  ultimo_evento_tipo: string | null
  ultimo_evento_motivo: string | null
  evento_at: string | null
  // Conteos
  evid_antes: number
  evid_durante: number
  evid_despues: number
  evid_llegada: number
  firmas_operador: number
  // Clasificacion
  categoria_vivo: CategoriaVivo
  planificacion_codigo: string
  planificacion_id: string
}

export type ResumenHoy = {
  total_jornadas: number
  corriendo: number
  pausadas: number
  en_faena_sin_iniciar: number
  pendientes_inicio: number
  cerradas_hoy: number
  pendientes_supervision: number
  aceptadas_hoy: number
  requieren_correccion: number
  total_seg_efectivo_cerradas: number
  total_seg_efectivo_en_vivo: number
  total_seg_interferencia: number
}

export async function getJornadasEnVivo(planificacionId?: string | null) {
  let q = supabase
    .from('v_calama_jornadas_en_vivo')
    .select('*')
    .order('categoria_vivo')
    .order('last_event_at', { ascending: false, nullsFirst: false })
  if (planificacionId) q = q.eq('planificacion_id', planificacionId)
  const { data, error } = await q
  return { data: (data ?? []) as unknown as JornadaEnVivo[], error }
}

export async function getResumenHoy() {
  const { data, error } = await supabase
    .from('v_calama_resumen_hoy')
    .select('*')
    .maybeSingle()
  return { data: data as ResumenHoy | null, error }
}
