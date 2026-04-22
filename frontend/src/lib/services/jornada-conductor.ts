import { supabase } from '@/lib/supabase'
import { todayISO } from '@/lib/utils'

// ── Types ────────────────────────────────────────────────

export type ActividadConductor =
  | 'conduccion'
  | 'espera'
  | 'carga_descarga'
  | 'descanso'
  | 'mantencion'
  | 'pernocte'
  | 'traslado_interno'
  | 'disponible'

export interface ActividadRegistro {
  id: string
  conductor_id: string
  activo_id?: string
  actividad: ActividadConductor
  fuente: string
  inicio: string
  fin?: string
  duracion_min?: number
  ubicacion_texto?: string
  latitud?: number
  longitud?: number
  velocidad_kmh?: number
  alerta_5hrs: boolean
  alerta_espera: boolean
  created_at: string
}

export interface ConductorTiempoReal {
  conductor_id: string
  nombre_completo: string
  rut: string
  tipo_licencia: string
  semep_vigente: boolean
  semep_vencimiento?: string
  horas_espera_mes_actual: number
  actividad_id?: string
  actividad_actual?: ActividadConductor
  actividad_inicio?: string
  minutos_en_actividad?: number
  ubicacion_texto?: string
  latitud?: number
  longitud?: number
  fuente?: string
  activo_id?: string
  patente?: string
  activo_nombre?: string
  hrs_conduccion_hoy: number
  hrs_espera_hoy: number
  hrs_conduccion_continua: number
  estado_espera_mes: string
  semep_vencido: boolean
}

export interface ResumenJornadaDia {
  actividad: ActividadConductor
  total_minutos: number
  total_horas: number
  cantidad_registros: number
  porcentaje: number
}

export interface ResumenJornadaMes {
  actividad: ActividadConductor
  total_horas: number
  dias_con_actividad: number
  limite_legal?: number
  porcentaje_limite?: number
  estado_cumplimiento: string
}

// ── Labels y colores ─────────────────────────────────────

export const ACTIVIDAD_LABELS: Record<ActividadConductor, string> = {
  conduccion: 'Conduciendo',
  espera: 'En Espera',
  carga_descarga: 'Carga/Descarga',
  descanso: 'Descanso',
  mantencion: 'Mantención',
  pernocte: 'Pernocte',
  traslado_interno: 'Traslado Interno',
  disponible: 'Disponible',
}

export const ACTIVIDAD_ICONS: Record<ActividadConductor, string> = {
  conduccion: 'Truck',
  espera: 'Clock',
  carga_descarga: 'Package',
  descanso: 'Coffee',
  mantencion: 'Wrench',
  pernocte: 'Moon',
  traslado_interno: 'ArrowRightLeft',
  disponible: 'CircleCheck',
}

export const ACTIVIDAD_COLORS: Record<ActividadConductor, string> = {
  conduccion: 'bg-green-500 text-white',
  espera: 'bg-amber-500 text-white',
  carga_descarga: 'bg-blue-500 text-white',
  descanso: 'bg-cyan-500 text-white',
  mantencion: 'bg-orange-500 text-white',
  pernocte: 'bg-indigo-500 text-white',
  traslado_interno: 'bg-purple-500 text-white',
  disponible: 'bg-gray-500 text-white',
}

export const ACTIVIDAD_BG: Record<ActividadConductor, string> = {
  conduccion: 'bg-green-50 border-green-300',
  espera: 'bg-amber-50 border-amber-300',
  carga_descarga: 'bg-blue-50 border-blue-300',
  descanso: 'bg-cyan-50 border-cyan-300',
  mantencion: 'bg-orange-50 border-orange-300',
  pernocte: 'bg-indigo-50 border-indigo-300',
  traslado_interno: 'bg-purple-50 border-purple-300',
  disponible: 'bg-gray-50 border-gray-300',
}

// ── Servicios ────────────────────────────────────────────

export async function registrarActividad(params: {
  conductor_id: string
  activo_id?: string
  actividad: ActividadConductor
  ubicacion_texto?: string
  latitud?: number
  longitud?: number
}) {
  const { data, error } = await supabase.rpc('fn_registrar_actividad_conductor', {
    p_conductor_id: params.conductor_id,
    p_activo_id: params.activo_id ?? null,
    p_actividad: params.actividad,
    p_fuente: 'app_manual',
    p_ubicacion_texto: params.ubicacion_texto ?? null,
    p_latitud: params.latitud ?? null,
    p_longitud: params.longitud ?? null,
    p_velocidad: null,
    p_origen: null,
    p_destino: null,
    p_geofence_id: null,
    p_geofence_nombre: null,
    p_gps_raw: null,
    p_usuario_id: null,
  })
  return { data, error }
}

export async function getActividadActual(conductorId: string) {
  const { data, error } = await supabase.rpc('fn_actividad_actual_conductor', {
    p_conductor_id: conductorId,
  })
  return { data: data?.[0] ?? null, error }
}

export async function getResumenDia(conductorId: string, fecha?: string) {
  const { data, error } = await supabase.rpc('fn_resumen_jornada_dia', {
    p_conductor_id: conductorId,
    p_fecha: fecha ?? todayISO(),
  })
  return { data: data as ResumenJornadaDia[] | null, error }
}

export async function getResumenMes(conductorId: string) {
  const firstOfMonth = new Date()
  firstOfMonth.setDate(1)
  const { data, error } = await supabase.rpc('fn_resumen_jornada_mes', {
    p_conductor_id: conductorId,
    p_mes: firstOfMonth.toISOString().split('T')[0],
  })
  return { data: data as ResumenJornadaMes[] | null, error }
}

export async function getConductoresTiempoReal() {
  const { data, error } = await supabase
    .from('v_conductores_tiempo_real')
    .select('*')
  return { data: data as ConductorTiempoReal[] | null, error }
}

export async function getHistorialActividades(conductorId: string, fechaInicio: string, fechaFin: string) {
  const { data, error } = await supabase
    .from('actividades_conductor')
    .select('*, activo:activos(patente, nombre)')
    .eq('conductor_id', conductorId)
    .gte('inicio', fechaInicio)
    .lte('inicio', fechaFin + 'T23:59:59')
    .order('inicio', { ascending: false })
  return { data, error }
}

// ── Geolocalización del navegador ────────────────────────

export function obtenerUbicacionActual(): Promise<{ lat: number; lon: number } | null> {
  return new Promise((resolve) => {
    if (!navigator.geolocation) {
      resolve(null)
      return
    }
    navigator.geolocation.getCurrentPosition(
      (pos) => resolve({ lat: pos.coords.latitude, lon: pos.coords.longitude }),
      () => resolve(null),
      { enableHighAccuracy: true, timeout: 10000 }
    )
  })
}
