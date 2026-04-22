import { supabase } from '@/lib/supabase'
import { todayISO } from '@/lib/utils'

export interface ReporteDiarioSnapshot {
  id: string
  fecha: string
  payload: ReporteDiarioPayload
  generado_en: string
  generado_por?: string
}

export interface ReporteDiarioPayload {
  fecha: string
  generado_en: string
  flota: {
    total_equipos: number
    por_estado_hoy?: Record<string, number>
    por_operacion?: Record<string, number>
    cambios_24h: number
  }
  oee_mes: {
    total: OEEResumen | null
    coquimbo: OEEResumen | null
    calama: OEEResumen | null
  }
  mantenimiento: {
    ots_abiertas: number
    ots_creadas_ayer: number
    ots_cerradas_ayer: number
    por_prioridad?: Record<string, number>
    tipo_correctivo_abierto: number
  }
  comercial: {
    arrendados: number
    disponibles_perdida: number
    uso_interno: number
    leasing: number
    por_cliente?: Record<string, number>
  }
  prevencion: {
    certificaciones_vencidas: number
    certificaciones_por_vencer_30d: number
    certificaciones_por_vencer_60d: number
    hds_por_revisar: number
    productos_suspel_activos: number
    bodegas_total: number
    bodegas_autorizacion_vencida: number
    bodegas_inspeccion_vencida: number
    respel_generado_mes_kg: number
    respel_retirado_mes_kg: number
    retiros_sin_sidrep: number
    conductores_semep_vencido: number
    conductores_semep_por_vencer: number
    conductores_fatiga_critica: number
    documentos_vencidos: number
    documentos_por_vencer: number
  }
  alertas: {
    criticas_activas: number
    total_activas: number
  }
  respel_mes: {
    generado_kg: number
    retirado_kg: number
    pendientes_sidrep: number
  }
}

export interface OEEResumen {
  operacion?: string
  total_equipos?: number
  disponibilidad_promedio?: number
  utilizacion_promedio?: number
  calidad_promedio?: number
  oee_promedio?: number
  clasificacion?: string
}

export async function getReporteDiario(fecha?: string) {
  let q = supabase
    .from('reportes_diarios_snapshot')
    .select('*')
    .order('fecha', { ascending: false })
    .limit(1)
  if (fecha) q = q.eq('fecha', fecha)
  const { data, error } = await q.maybeSingle()
  return { data: data as ReporteDiarioSnapshot | null, error }
}

export async function getReportesHistoricos(limit = 30) {
  const { data, error } = await supabase
    .from('reportes_diarios_snapshot')
    .select('*')
    .order('fecha', { ascending: false })
    .limit(limit)
  return { data: data as ReporteDiarioSnapshot[] | null, error }
}

export async function regenerarReporteDiario(fecha?: string) {
  const { data, error } = await supabase.rpc('fn_guardar_reporte_diario', {
    p_fecha: fecha ?? todayISO(),
  })
  return { data, error }
}

export interface TendenciaDia {
  fecha: string
  oee_promedio: number | null
  disponibilidad_promedio: number | null
  utilizacion_promedio: number | null
  calidad_promedio: number | null
  total_arrendados: number
  total_disponibles: number
  total_mantencion: number
  total_taller: number
  total_fuera_servicio: number
  total_uso_interno: number
  total_leasing: number
  cambios_24h: number
  ots_abiertas: number
  alertas_criticas: number
}

export async function getTendenciaReporte(dias = 30) {
  const { data, error } = await supabase.rpc('fn_tendencia_reporte_diario', {
    p_dias: dias,
  })
  return { data: data as TendenciaDia[] | null, error }
}

export interface CambioEstadoDia {
  fecha_hora: string
  activo_id: string
  patente: string
  equipo: string
  estado_codigo: string
  motivo: string | null
  usuario_id: string | null
  usuario_nombre: string
  usuario_rol: string
  ot_relacionada_id: string | null
  ot_folio: string | null
}

export async function getCambiosEstadoDia(fecha?: string) {
  const { data, error } = await supabase.rpc('fn_cambios_estado_dia', {
    p_fecha: fecha ?? todayISO(),
  })
  return { data: data as CambioEstadoDia[] | null, error }
}
