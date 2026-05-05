import { supabase } from '@/lib/supabase'

// ============================================================================
// Servicios de reportabilidad Calama (MIG28)
// ============================================================================

export type EstadoPlanificacion =
  | 'no_planificada' | 'planificada' | 'parcial_sin_proxima_jornada'
  | 'vencida' | 'ejecutada' | 'cancelada'

export type EstadoPlanRow = {
  ot_id: string
  folio: string
  estado_ejecucion: string
  avance_pct: number
  avance_excel_pct: number
  fecha_programada: string | null
  responsable_actual: string | null
  total_jornadas: number
  jornadas_futuras: number
  jornadas_hoy: number
  jornadas_vencidas: number
  ultima_fecha_planificada: string | null
  proxima_fecha_planificada: string | null
  estado_planificacion: EstadoPlanificacion
}

export type ReporteAtrasoRow = {
  plan_ot_id: string
  ot_id: string
  folio: string
  codigo_zona: string | null
  lugar_fisico: string | null
  titulo: string
  fecha_jornada: string
  dias_atraso: number
  responsable_id: string | null
  responsable_nombre: string | null
  avance_actual: number
  ultimo_comentario: string | null
  estado_jornada: string
  estado_ejecucion: string
}

export type CalidadDatoRow = {
  check_id: string
  valor: number
  descripcion: string
}

export type ReporteSemanalRow = {
  plan_semanal_id: string
  planificacion: string
  fecha_inicio_semana: string
  fecha_fin_semana: string
  estado_plan: string
  jornadas_total: number
  jornadas_ejecutadas: number
  jornadas_no_ejecutadas: number
  jornadas_pendientes: number
  ots_distintas: number
  responsables_asignados: number
  horas_planificadas: number
  horas_reales: number
  cumplimiento_pct: number
}

export async function getEstadoPlanificacionOTs() {
  const { data, error } = await supabase
    .from('v_calama_estado_planificacion_ots')
    .select('*')
    .order('folio')
  return { data: (data ?? []) as EstadoPlanRow[], error }
}

export async function getReporteAtrasos() {
  const { data, error } = await supabase
    .from('v_calama_reporte_atrasos')
    .select('*')
  return { data: (data ?? []) as ReporteAtrasoRow[], error }
}

export async function getCalidadDatos() {
  const { data, error } = await supabase
    .from('v_calama_calidad_datos')
    .select('*')
  return { data: (data ?? []) as CalidadDatoRow[], error }
}

export async function getReporteSemanal() {
  const { data, error } = await supabase
    .from('v_calama_reporte_semanal')
    .select('*')
  return { data: (data ?? []) as ReporteSemanalRow[], error }
}

export async function agregarJornadaOT(payload: {
  plan_semanal_id: string
  ot_id: string
  fecha: string
  responsable_id?: string
  horas_planificadas?: number
  avance_objetivo_pct?: number
  comentario?: string
}) {
  const { data, error } = await supabase.rpc('rpc_calama_agregar_jornada_ot', { p_payload: payload })
  return { data, error }
}
