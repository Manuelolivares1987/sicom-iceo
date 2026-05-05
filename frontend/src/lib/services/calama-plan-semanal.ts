import { supabase } from '@/lib/supabase'

// ============================================================================
// Tipos
// ============================================================================

export type EstadoPlanSemanal = 'borrador' | 'confirmado' | 'en_ejecucion' | 'cerrado' | 'cancelado'

export type CalamaPlanSemanal = {
  id: string
  planificacion_id: string
  faena_calama_id: string | null
  fecha_inicio_semana: string
  fecha_fin_semana: string
  estado: EstadoPlanSemanal
  creado_por: string | null
  confirmado_por: string | null
  confirmado_at: string | null
  observaciones: string | null
  created_at: string
  updated_at: string
}

export type CalamaPlanDia = {
  id: string
  plan_semanal_id: string
  fecha: string
  nombre_dia: string
  orden: number
  estado: 'borrador' | 'confirmado' | 'en_ejecucion' | 'cerrado'
  observaciones: string | null
}

export type EstadoPlanOT =
  | 'planificada' | 'asignada' | 'liberada' | 'en_ejecucion'
  | 'pausada' | 'finalizada' | 'no_ejecutada' | 'bloqueada'

export type CalamaPlanOT = {
  id: string
  plan_semanal_id: string
  plan_dia_id: string
  ot_id: string
  zona_proyecto_id: string | null
  responsable_id: string | null
  prioridad: number
  estado_plan: EstadoPlanOT
  observaciones: string | null
  created_by: string | null
  created_at: string
  updated_at: string
}

export type CalamaEjecucion = {
  id: string
  ot_id: string
  plan_semanal_ot_id: string | null
  ejecutor_id: string
  estado: 'en_ejecucion' | 'pausada' | 'finalizada' | 'cancelada'
  started_at: string
  finished_at: string | null
  last_event_at: string
  tiempo_total_segundos: number
  tiempo_pausado_segundos: number
  tiempo_colacion_segundos: number
  tiempo_efectivo_segundos: number
  avance_final: number | null
  observacion_inicio: string | null
  observacion_cierre: string | null
}

export type CalamaEjecucionEvento = {
  id: string
  ejecucion_id: string
  ot_id: string
  tipo: 'start' | 'pause' | 'resume' | 'finish' | 'cancel' | 'avance' | 'comentario'
  motivo: string | null
  comentario: string | null
  avance: number | null
  created_at: string
}

// ============================================================================
// Helpers fechas
// ============================================================================

export function lunesDe(fecha: Date | string): string {
  const d = typeof fecha === 'string' ? new Date(fecha) : new Date(fecha)
  const dow = d.getDay()
  const diff = (dow === 0 ? -6 : 1) - dow
  d.setDate(d.getDate() + diff)
  return d.toISOString().slice(0, 10)
}

export function semanaActualIso(): string {
  return lunesDe(new Date())
}

// ============================================================================
// Plan semanal
// ============================================================================

export async function getOrCreatePlanSemanal(planificacionId: string, fechaInicio: string) {
  const { data, error } = await supabase.rpc('rpc_calama_get_or_create_plan_semanal', {
    p_planificacion_id: planificacionId,
    p_fecha_inicio: fechaInicio,
  })
  if (error) return { data: null, error }
  return { data: data as { plan_semanal_id: string; fecha_inicio: string; fecha_fin: string }, error: null }
}

export async function getPlanSemanalById(id: string) {
  const { data, error } = await supabase
    .from('calama_planes_semanales')
    .select('*')
    .eq('id', id)
    .single()
  return { data: data as CalamaPlanSemanal | null, error }
}

export async function getDiasPlanSemanal(planSemanalId: string) {
  const { data, error } = await supabase
    .from('calama_plan_semanal_dias')
    .select('*')
    .eq('plan_semanal_id', planSemanalId)
    .order('orden')
  return { data: (data ?? []) as CalamaPlanDia[], error }
}

export async function getOTsPlanSemanal(planSemanalId: string) {
  const { data, error } = await supabase
    .from('calama_plan_semanal_ots')
    .select('*')
    .eq('plan_semanal_id', planSemanalId)
  return { data: (data ?? []) as CalamaPlanOT[], error }
}

export async function moverOTplanSemanal(payload: {
  planSemanalId: string
  otId: string
  fechaDestino: string
  responsableId?: string | null
}) {
  const { data, error } = await supabase.rpc('rpc_calama_mover_ot_plan_semanal', {
    p_plan_semanal_id: payload.planSemanalId,
    p_ot_id: payload.otId,
    p_fecha_destino: payload.fechaDestino,
    p_responsable_id: payload.responsableId ?? null,
  })
  return { data, error }
}

export async function quitarOTplanSemanal(planSemanalId: string, otId: string) {
  const { data, error } = await supabase.rpc('rpc_calama_quitar_ot_plan_semanal', {
    p_plan_semanal_id: planSemanalId,
    p_ot_id: otId,
  })
  return { data, error }
}

export async function asignarResponsable(planSemanalId: string, otId: string, responsableId: string) {
  const { data, error } = await supabase.rpc('rpc_calama_asignar_responsable_ot_semana', {
    p_plan_semanal_id: planSemanalId,
    p_ot_id: otId,
    p_responsable_id: responsableId,
  })
  return { data, error }
}

export async function confirmarPlanSemanal(planSemanalId: string) {
  const { data, error } = await supabase.rpc('rpc_calama_confirmar_plan_semanal', {
    p_plan_semanal_id: planSemanalId,
  })
  return { data, error }
}

// ============================================================================
// Mis OTs (asignadas al usuario actual)
// ============================================================================

export async function getMisOTsAsignadas() {
  const { data: user } = await supabase.auth.getUser()
  const uid = user.user?.id
  if (!uid) return { data: [], error: null }

  // Plan-OTs donde el usuario es responsable
  const { data: planOts, error } = await supabase
    .from('calama_plan_semanal_ots')
    .select('*')
    .eq('responsable_id', uid)
    .order('updated_at', { ascending: false })
  if (error) return { data: null, error }
  return { data: (planOts ?? []) as CalamaPlanOT[], error: null }
}

// ============================================================================
// Ejecuciones
// ============================================================================

export async function getEjecucionActivaPorOT(otId: string) {
  const { data, error } = await supabase
    .from('calama_ot_ejecuciones')
    .select('*')
    .eq('ot_id', otId)
    .in('estado', ['en_ejecucion', 'pausada'])
    .order('started_at', { ascending: false })
    .limit(1)
    .maybeSingle()
  return { data: data as CalamaEjecucion | null, error }
}

export async function getEjecucionesPorOT(otId: string) {
  const { data, error } = await supabase
    .from('calama_ot_ejecuciones')
    .select('*')
    .eq('ot_id', otId)
    .order('started_at', { ascending: false })
  return { data: (data ?? []) as CalamaEjecucion[], error }
}

export async function iniciarEjecucion(otId: string) {
  const { data, error } = await supabase.rpc('rpc_calama_iniciar_ejecucion_ot', { p_ot_id: otId })
  return { data, error }
}

export async function pausarEjecucion(ejecucionId: string, motivo: string = 'pausa') {
  const { data, error } = await supabase.rpc('rpc_calama_pausar_ejecucion_ot', {
    p_ejecucion_id: ejecucionId,
    p_motivo: motivo,
  })
  return { data, error }
}

export async function reanudarEjecucion(ejecucionId: string) {
  const { data, error } = await supabase.rpc('rpc_calama_reanudar_ejecucion_ot', {
    p_ejecucion_id: ejecucionId,
  })
  return { data, error }
}

export async function finalizarEjecucion(ejecucionId: string, avanceFinal: number = 100, observacion?: string) {
  const { data, error } = await supabase.rpc('rpc_calama_finalizar_ejecucion_ot', {
    p_ejecucion_id: ejecucionId,
    p_avance_final: avanceFinal,
    p_observacion: observacion ?? null,
  })
  return { data, error }
}

// ============================================================================
// Usuarios para asignar responsable
// ============================================================================

export async function getUsuariosAsignables() {
  const { data, error } = await supabase
    .from('usuarios_perfil')
    .select('id, nombre_completo, rol, cargo, email')
    .eq('activo', true)
    .order('nombre_completo')
  return { data: (data ?? []) as Array<{ id: string; nombre_completo: string | null; rol: string | null; cargo: string | null; email: string | null }>, error }
}
