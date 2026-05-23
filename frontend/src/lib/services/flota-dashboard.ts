import { supabase } from '@/lib/supabase'

// ============================================================================
// Vista unificada de flota (MIG85)
// ============================================================================

export type FlotaDashboardActivo = {
  activo_id: string
  activo_codigo: string
  activo_nombre: string
  patente: string | null
  activo_tipo: string | null
  estado_operacional: string
  estado_comercial: string
  operacion: string | null
  modelo_id: string | null
  modelo_nombre: string | null
  modelo_marca: string | null
  contrato_id: string | null
  contrato_codigo: string | null
  contrato_cliente: string | null
  faena_id: string | null
  faena_nombre: string | null
  kilometraje_actual: number | null
  horas_uso_actual: number | null
  anio_fabricacion: number | null

  estado_ultima_fecha: string | null
  estado_codigo_hoy: string | null
  horas_op_ultimo_dia: number | null
  km_ultimo_dia: number | null

  // Plan PM
  pm_planes_total: number
  pm_planes_vencidos: number
  pm_planes_proxima_semana: number
  pm_proxima_fecha: string | null
  pm_status: 'sin_planes' | 'vencido' | 'proximo' | 'al_dia'

  ots_correctivas_abiertas: number

  alertas_activas: number
  alertas_criticas: number

  // GPS
  gps_device_id: string | null
  gps_device_nombre: string | null
  gps_ultima_senal: string | null
  gps_minutos_offline: number | null
  gps_lat: number | null
  gps_lng: number | null
  gps_velocidad_kmh: number | null
  gps_ignicion: boolean | null
  gps_movimiento: string | null
  gps_conexion: string | null
  gps_bateria_pct: number | null
  gps_estado_pin: 'sin_gps' | 'sin_datos' | 'sin_senal_24h' | 'offline' | 'en_ruta' | 'detenido_motor_on' | 'detenido'

  // Geocerca
  geocerca_esperada_id: string | null
  geocerca_esperada: string | null
  en_zona_esperada: boolean | null

  activo_creado_at: string
  activo_actualizado_at: string
}

export type FlotaKpiResumen = {
  total_activos: number
  arrendados: number
  disponibles: number
  uso_interno: number
  leasing: number
  en_mantenimiento: number
  fuera_servicio: number

  pm_sin_planes: number
  pm_vencidos: number
  pm_proximos_7d: number
  pm_al_dia: number
  pm_cumplimiento_pct: number | null

  correctivas_abiertas_total: number

  alertas_activas_total: number
  alertas_criticas_total: number
  activos_con_alerta_critica: number

  gps_mapeados: number
  gps_sin_senal_24h: number
  gps_en_ruta: number
  gps_detenido_motor_on: number
  gps_detenido: number
  gps_offline: number
  sin_gps: number

  en_zona_esperada: number
  fuera_zona_esperada: number
  sin_dato_zona: number
}

export type FlotaAlertaResumen = {
  activo_id: string
  activo_codigo: string
  patente: string | null
  criticas: number
  warnings: number
  infos: number
  tipos_activos: string[] | null
  ultima_alerta_at: string
}

export async function getFlotaDashboard(): Promise<FlotaDashboardActivo[]> {
  const { data, error } = await supabase
    .from('v_flota_dashboard_unificado').select('*').limit(500)
  if (error) throw error
  return (data ?? []) as FlotaDashboardActivo[]
}

export async function getFlotaKpiResumen(): Promise<FlotaKpiResumen | null> {
  const { data, error } = await supabase
    .from('v_flota_kpi_resumen').select('*').maybeSingle()
  if (error) throw error
  return data as FlotaKpiResumen | null
}

export async function getFlotaAlertasResumen(): Promise<FlotaAlertaResumen[]> {
  const { data, error } = await supabase
    .from('v_flota_alertas_resumen').select('*')
    .order('criticas', { ascending: false })
    .order('warnings', { ascending: false })
    .limit(50)
  if (error) throw error
  return (data ?? []) as FlotaAlertaResumen[]
}
