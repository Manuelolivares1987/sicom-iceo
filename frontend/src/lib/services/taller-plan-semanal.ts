import { supabase } from '@/lib/supabase'

// ============================================================================
// Tipos
// ============================================================================

export type EstadoPlanSemanal = 'borrador' | 'confirmado' | 'en_ejecucion' | 'cerrado' | 'cancelado'
export type EstadoJornadaTaller =
  | 'planificada' | 'asignada' | 'liberada' | 'en_ejecucion' | 'pausada'
  | 'finalizada' | 'no_ejecutada' | 'bloqueada' | 'reprogramada' | 'cancelada'

export type TallerPlanSemanal = {
  id: string
  faena_id: string | null
  fecha_inicio_semana: string  // YYYY-MM-DD
  fecha_fin_semana: string
  estado: EstadoPlanSemanal
  creado_por: string | null
  confirmado_por: string | null
  confirmado_at: string | null
  observaciones: string | null
}

export type TallerPlanDia = {
  id: string
  plan_semanal_id: string
  fecha: string
  nombre_dia: string
  orden: number
  estado: string
}

export type TallerPlanOTFull = {
  plan_ot_id: string
  plan_semanal_id: string
  plan_dia_id: string
  dia_fecha: string
  dia_nombre: string
  dia_orden: number
  fecha_inicio_semana: string
  fecha_fin_semana: string
  plan_estado: EstadoPlanSemanal
  ot_id: string
  ot_folio: string
  ot_tipo: string
  ot_estado: string
  ot_prioridad: string
  ot_fecha_programada: string | null
  plan_mantenimiento_id: string | null
  pm_nombre: string | null
  pm_proxima_fecha: string | null
  activo_id: string | null
  activo_codigo: string | null
  activo_nombre: string | null
  activo_patente: string | null
  activo_tipo: string | null
  faena_id: string | null
  faena_nombre: string | null
  contrato_id: string | null
  contrato_codigo: string | null
  contrato_cliente: string | null
  responsable_id: string | null
  responsable: string | null
  cuadrilla: string | null
  horas_planificadas: number | null
  avance_objetivo_pct: number | null
  secuencia_jornada: number
  jornada_estado: EstadoJornadaTaller
  observaciones: string | null
  ejecucion_activa_id: string | null
  ejecucion_activa_estado: string | null
  ultima_ejecucion_avance: number | null
  created_at: string
  updated_at: string
}

export type TallerOTBacklog = {
  ot_id: string
  ot_folio: string
  ot_tipo: string
  ot_estado: string
  ot_prioridad: string
  fecha_programada: string | null
  activo_id: string | null
  activo_codigo: string | null
  activo_nombre: string | null
  activo_patente: string | null
  faena_id: string | null
  faena_nombre: string | null
  contrato_id: string | null
  contrato_codigo: string | null
  contrato_cliente: string | null
  plan_mantenimiento_id: string | null
  pm_nombre: string | null
  proxima_ejecucion_fecha: string | null
  responsable_id: string | null
  responsable_actual: string | null
  observaciones: string | null
  created_at: string
}

export type TallerKpiSemanal = {
  plan_semanal_id: string
  fecha_inicio_semana: string
  fecha_fin_semana: string
  plan_estado: EstadoPlanSemanal
  jornadas_planificadas: number
  jornadas_finalizadas: number
  jornadas_en_ejecucion: number
  jornadas_pendientes: number
  jornadas_no_ejecutadas: number
  ots_unicas: number
  activos_intervenidos: number
  horas_planificadas: number
  horas_reales: number
  cumplimiento_pct: number
  jornadas_atrasadas: number
}

export type TallerCumplimientoPmMes = {
  mes: string  // YYYY-MM-DD (primer dia del mes)
  pm_total: number
  pm_completados: number
  pm_no_ejecutados: number
  correctivos_total: number
  correctivos_completados: number
  cumplimiento_pm_pct: number
}

// ============================================================================
// Helpers fecha
// ============================================================================
export function lunesDeIso(d: Date): string {
  const dia = d.getDay()  // 0=domingo, 1=lunes ... 6=sabado
  const diff = dia === 0 ? -6 : 1 - dia
  const lunes = new Date(d.getFullYear(), d.getMonth(), d.getDate() + diff)
  return lunes.toISOString().slice(0, 10)
}

// ============================================================================
// Queries
// ============================================================================

export async function getPlanSemanalById(id: string): Promise<TallerPlanSemanal | null> {
  const { data, error } = await supabase
    .from('taller_planes_semanales').select('*').eq('id', id).maybeSingle()
  if (error) throw error
  return data as TallerPlanSemanal | null
}

export async function getDiasPlanSemanal(planSemanalId: string): Promise<TallerPlanDia[]> {
  const { data, error } = await supabase
    .from('taller_plan_semanal_dias').select('*')
    .eq('plan_semanal_id', planSemanalId).order('orden')
  if (error) throw error
  return (data ?? []) as TallerPlanDia[]
}

export async function getJornadasPlanSemanal(planSemanalId: string): Promise<TallerPlanOTFull[]> {
  const { data, error } = await supabase
    .from('v_taller_plan_semanal_ots_full').select('*')
    .eq('plan_semanal_id', planSemanalId)
    .order('dia_orden').order('secuencia_jornada')
  if (error) throw error
  return (data ?? []) as TallerPlanOTFull[]
}

export async function getBacklog(): Promise<TallerOTBacklog[]> {
  const { data, error } = await supabase
    .from('v_taller_ot_backlog').select('*').limit(500)
  if (error) throw error
  return (data ?? []) as TallerOTBacklog[]
}

export async function getKpiSemanal(planSemanalId: string): Promise<TallerKpiSemanal | null> {
  const { data, error } = await supabase
    .from('v_taller_kpi_semanal').select('*')
    .eq('plan_semanal_id', planSemanalId).maybeSingle()
  if (error) throw error
  return data as TallerKpiSemanal | null
}

export async function getCumplimientoPmMes(): Promise<TallerCumplimientoPmMes[]> {
  const { data, error } = await supabase
    .from('v_taller_cumplimiento_pm_mes').select('*').limit(12)
  if (error) throw error
  return (data ?? []) as TallerCumplimientoPmMes[]
}

export type UsuarioAsignable = {
  id: string
  nombre_completo: string | null
  rol: string | null
}

export async function getUsuariosAsignables(): Promise<UsuarioAsignable[]> {
  const { data, error } = await supabase
    .from('usuarios_perfil').select('id, nombre_completo, rol')
    .in('rol', ['administrador','supervisor','operario','jefe_mantenimiento','tecnico'])
    .order('nombre_completo')
  if (error) throw error
  return (data ?? []) as UsuarioAsignable[]
}

// ============================================================================
// Mutations / RPCs
// ============================================================================

export async function rpcGetOrCreatePlanSemanal(fechaInicio: string, faenaId?: string | null) {
  const { data, error } = await supabase.rpc('rpc_taller_get_or_create_plan_semanal', {
    p_fecha_inicio: fechaInicio,
    p_faena_id: faenaId ?? null,
  })
  if (error) throw error
  return data as { success: boolean; plan_semanal_id: string; fecha_inicio: string; fecha_fin: string; creado_nuevo: boolean }
}

export async function rpcAgregarJornadaOT(params: {
  planSemanalId: string
  otId: string
  fecha: string
  responsableId?: string | null
  cuadrilla?: string | null
  horasPlanificadas?: number | null
  avanceObjetivo?: number | null
  observaciones?: string | null
}) {
  const { data, error } = await supabase.rpc('rpc_taller_agregar_jornada_ot', {
    p_plan_semanal_id: params.planSemanalId,
    p_ot_id: params.otId,
    p_fecha: params.fecha,
    p_responsable_id: params.responsableId ?? null,
    p_cuadrilla: params.cuadrilla ?? null,
    p_horas_planificadas: params.horasPlanificadas ?? null,
    p_avance_objetivo: params.avanceObjetivo ?? null,
    p_observaciones: params.observaciones ?? null,
  })
  if (error) throw error
  return data as { success: boolean; plan_ot_id: string; secuencia: number }
}

export async function rpcMoverJornada(planOtId: string, fechaDestino: string, responsableId?: string | null) {
  const { data, error } = await supabase.rpc('rpc_taller_mover_jornada', {
    p_plan_ot_id: planOtId,
    p_fecha_destino: fechaDestino,
    p_responsable_id: responsableId ?? null,
  })
  if (error) throw error
  return data as { success: boolean }
}

export async function rpcQuitarJornada(planOtId: string) {
  const { data, error } = await supabase.rpc('rpc_taller_quitar_jornada', { p_plan_ot_id: planOtId })
  if (error) throw error
  return data as { success: boolean }
}

export async function rpcAsignarResponsable(planOtId: string, responsableId: string, cuadrilla?: string | null) {
  const { data, error } = await supabase.rpc('rpc_taller_asignar_responsable', {
    p_plan_ot_id: planOtId,
    p_responsable_id: responsableId,
    p_cuadrilla: cuadrilla ?? null,
  })
  if (error) throw error
  return data as { success: boolean }
}

export async function rpcConfirmarPlanSemanal(planSemanalId: string) {
  const { data, error } = await supabase.rpc('rpc_taller_confirmar_plan_semanal', { p_plan_semanal_id: planSemanalId })
  if (error) throw error
  return data as { success: boolean; ots_confirmadas: number }
}

export async function rpcIniciarEjecucion(otId: string, observacion?: string | null) {
  const { data, error } = await supabase.rpc('rpc_taller_iniciar_ejecucion_ot', {
    p_ot_id: otId, p_observacion: observacion ?? null,
  })
  if (error) throw error
  return data as { success: boolean; ejecucion_id: string; plan_ot_id: string | null }
}

export async function rpcPausarEjecucion(ejecucionId: string, motivo?: string | null) {
  const { data, error } = await supabase.rpc('rpc_taller_pausar_ejecucion', {
    p_ejecucion_id: ejecucionId, p_motivo: motivo ?? null,
  })
  if (error) throw error
  return data as { success: boolean; delta_segundos: number }
}

export async function rpcReanudarEjecucion(ejecucionId: string) {
  const { data, error } = await supabase.rpc('rpc_taller_reanudar_ejecucion', { p_ejecucion_id: ejecucionId })
  if (error) throw error
  return data as { success: boolean; colacion: boolean }
}

export async function rpcFinalizarEjecucion(ejecucionId: string, avanceFinal = 100, observacion?: string | null) {
  const { data, error } = await supabase.rpc('rpc_taller_finalizar_ejecucion', {
    p_ejecucion_id: ejecucionId,
    p_avance_final: avanceFinal,
    p_observacion: observacion ?? null,
  })
  if (error) throw error
  return data as { success: boolean; tiempo_efectivo_seg: number; tiempo_pausado_seg: number; tiempo_colacion_seg: number; avance_final: number }
}

// Admin: forzar sembrado de planes faltantes en toda la flota (MIG80)
export async function rpcAdminSembrarPlanesFaltantes() {
  const { data, error } = await supabase.rpc('rpc_admin_sembrar_planes_faltantes')
  if (error) throw error
  return data as { success: boolean; activos_revisados: number; planes_creados: number }
}

export type CoberturaResumen = {
  activos_totales: number
  activos_con_modelo: number
  activos_con_pautas_disponibles: number
  activos_con_plan: number
  activos_sin_plan: number
  cobertura_pct: number
  pautas_disponibles: number
  planes_activos: number
}

export async function getCoberturaResumen(): Promise<CoberturaResumen | null> {
  const { data, error } = await supabase
    .from('v_mantenimiento_cobertura_resumen').select('*').maybeSingle()
  if (error) throw error
  return data as CoberturaResumen | null
}

export type ActivoSinPlan = {
  activo_id: string
  activo_codigo: string
  activo_nombre: string
  patente: string | null
  modelo_nombre: string | null
  modelo_marca: string | null
  contrato_codigo: string | null
  contrato_cliente: string | null
  faena_nombre: string | null
  pautas_disponibles: number
  planes_asignados: number
  pautas_sin_cubrir: number
}

export async function getActivosSinPlan(): Promise<ActivoSinPlan[]> {
  const { data, error } = await supabase
    .from('v_activos_sin_plan_preventivo').select('*').limit(500)
  if (error) throw error
  return (data ?? []) as ActivoSinPlan[]
}
