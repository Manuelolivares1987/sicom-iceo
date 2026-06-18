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
  checklist_total: number | null
  checklist_completados: number | null
  tiempo_estimado_total_min: number | null
  ejecucion_activa_id: string | null
  ejecucion_activa_estado: string | null
  ultima_ejecucion_avance: number | null
  created_at: string
  updated_at: string
}

export type ChecklistOtItem = {
  id: string
  ot_id: string
  orden: number
  descripcion: string
  obligatorio: boolean
  requiere_foto: boolean
  tiempo_estimado_min: number | null
  resultado: string | null
  observacion: string | null
  foto_url: string | null
  seccion: string | null
}

// Checklist V03 efectivo de una OT (parte del maestro, con overrides a medida)
export type ChecklistV3Item = {
  instance_item_id: string
  instance_id: string
  ot_id: string
  instance_estado: string | null
  bloque: string
  bloque_orden: number
  orden: number
  codigo: string | null
  descripcion: string
  tiempo_min: number | null
  tiempo_editado: boolean
  requiere_foto: boolean
  obligatorio: boolean
  critico: boolean
  categoria_calidad: string | null
  resultado: string | null
  observacion: string | null
  foto_url: string | null
  excluido: boolean
  es_custom: boolean
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

// Jornadas (días + cuadrilla) en que una OT está programada en el plan semanal.
// Permite que al revisar la OT se vea el responsable/cuadrilla concordante con el plan.
export type JornadaDeOT = {
  dia_fecha: string; dia_nombre: string | null; cuadrilla: string | null
  responsable: string | null; jornada_estado: string | null; horas_planificadas: number | null
}
export async function getJornadasDeOT(otId: string): Promise<JornadaDeOT[]> {
  const { data, error } = await supabase
    .from('v_taller_plan_semanal_ots_full')
    .select('dia_fecha, dia_nombre, cuadrilla, responsable, jornada_estado, horas_planificadas')
    .eq('ot_id', otId)
    .order('dia_fecha', { ascending: true })
  if (error) throw error
  return (data ?? []) as JornadaDeOT[]
}

// Jornadas de una semana (rango de fechas) — para repetir las OT por día en el Panel Taller.
export async function getJornadasSemana(desde: string, hasta: string) {
  const { data, error } = await supabase
    .from('v_taller_plan_semanal_ots_full')
    .select('ot_id, ot_folio, ot_tipo, ot_estado, ot_prioridad, activo_nombre, activo_codigo, activo_patente, cuadrilla, responsable, dia_fecha, horas_planificadas')
    .gte('dia_fecha', desde).lte('dia_fecha', hasta)
    .order('dia_fecha', { ascending: true })
  if (error) throw error
  return data ?? []
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

export async function rpcAsignarResponsable(planOtId: string, responsableId: string | null, cuadrilla?: string | null) {
  const { data, error } = await supabase.rpc('rpc_taller_asignar_responsable', {
    p_plan_ot_id: planOtId,
    p_responsable_id: responsableId,
    p_cuadrilla: cuadrilla ?? null,
  })
  if (error) throw error
  return data as { success: boolean }
}

// Editar la jornada completa (jefe de taller): responsable, cuadrilla, horas,
// meta de avance y observaciones. El responsable se sincroniza con la OT.
export async function rpcEditarJornada(params: {
  planOtId: string
  responsableId?: string | null
  cuadrilla?: string | null
  horasPlanificadas?: number | null
  avanceObjetivo?: number | null
  observaciones?: string | null
}) {
  const { data, error } = await supabase.rpc('rpc_taller_editar_jornada', {
    p_plan_ot_id: params.planOtId,
    p_responsable_id: params.responsableId ?? null,
    p_cuadrilla: params.cuadrilla ?? null,
    p_horas_planificadas: params.horasPlanificadas ?? null,
    p_avance_objetivo: params.avanceObjetivo ?? null,
    p_observaciones: params.observaciones ?? null,
  })
  if (error) throw error
  return data as { success: boolean; plan_ot_id: string; ot_id: string }
}

// Checklist de la OT (pauta o inspección)
export async function getChecklistOt(otId: string): Promise<ChecklistOtItem[]> {
  const { data, error } = await supabase
    .from('checklist_ot')
    .select('id, ot_id, orden, descripcion, obligatorio, requiere_foto, tiempo_estimado_min, resultado, observacion, foto_url, seccion')
    .eq('ot_id', otId).order('orden')
  if (error) throw error
  return (data ?? []) as ChecklistOtItem[]
}

export async function rpcChecklistUpsertItem(params: {
  otId: string
  itemId?: string | null
  descripcion?: string | null
  orden?: number | null
  obligatorio?: boolean
  requiereFoto?: boolean
  tiempoEstimadoMin?: number | null
  seccion?: string | null
}) {
  const { data, error } = await supabase.rpc('rpc_taller_checklist_upsert_item', {
    p_ot_id: params.otId,
    p_item_id: params.itemId ?? null,
    p_descripcion: params.descripcion ?? null,
    p_orden: params.orden ?? null,
    p_obligatorio: params.obligatorio ?? true,
    p_requiere_foto: params.requiereFoto ?? false,
    p_tiempo_estimado_min: params.tiempoEstimadoMin ?? null,
    p_seccion: params.seccion ?? null,
  })
  if (error) throw error
  return data as { success: boolean; item_id: string }
}

export async function rpcChecklistEliminarItem(itemId: string) {
  const { data, error } = await supabase.rpc('rpc_taller_checklist_eliminar_item', { p_item_id: itemId })
  if (error) throw error
  return data as { success: boolean; item_id: string }
}

// ── Checklist V03 a medida por OT ───────────────────────────────────────────
export async function getChecklistV3OT(otId: string): Promise<ChecklistV3Item[]> {
  const { data, error } = await supabase
    .from('v_taller_ot_checklist_v3').select('*')
    .eq('ot_id', otId)
    .order('bloque_orden').order('orden')
  if (error) throw error
  return (data ?? []) as ChecklistV3Item[]
}

export async function rpcV3SetTiempo(itemId: string, tiempoMin: number | null) {
  const { data, error } = await supabase.rpc('rpc_taller_v3_set_tiempo', {
    p_item_id: itemId, p_tiempo_min: tiempoMin,
  })
  if (error) throw error
  return data as { success: boolean }
}

export async function rpcV3SetExcluido(itemId: string, excluido: boolean) {
  const { data, error } = await supabase.rpc('rpc_taller_v3_set_excluido', {
    p_item_id: itemId, p_excluido: excluido,
  })
  if (error) throw error
  return data as { success: boolean }
}

export async function rpcV3AgregarItem(otId: string, descripcion: string, tiempoMin: number | null) {
  const { data, error } = await supabase.rpc('rpc_taller_v3_agregar_item', {
    p_ot_id: otId, p_descripcion: descripcion, p_tiempo_min: tiempoMin,
  })
  if (error) throw error
  return data as { success: boolean; item_id: string; instance_id: string }
}

export async function rpcV3EliminarCustom(itemId: string) {
  const { data, error } = await supabase.rpc('rpc_taller_v3_eliminar_custom', { p_item_id: itemId })
  if (error) throw error
  return data as { success: boolean }
}

// Handoff jefe -> ejecutor: liberar / reabrir la preparación del checklist
export async function rpcLiberarEjecucion(otId: string) {
  const { data, error } = await supabase.rpc('rpc_taller_liberar_ejecucion', { p_ot_id: otId })
  if (error) throw error
  return data as { success: boolean; ot_id: string }
}

export async function rpcReabrirPreparacion(otId: string) {
  const { data, error } = await supabase.rpc('rpc_taller_reabrir_preparacion', { p_ot_id: otId })
  if (error) throw error
  return data as { success: boolean; ot_id: string }
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
