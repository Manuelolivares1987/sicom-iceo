import { supabase } from '@/lib/supabase'

// ============================================================================
// Horas por equipo y próximo preventivo (MIG597)
// ----------------------------------------------------------------------------
// v_equipo_horas: horómetro GPS, uso medido (ayer / 7 / 30 días), ritmo de los
// últimos 30 días y el peldaño de la escalera que toca primero, con fecha
// estimada. v_activo_horas_dia: el detalle día a día de un equipo.
// ============================================================================

export type EstadoPreventiva =
  | 'vencida' | 'proxima' | 'atento' | 'al_dia' | 'revisar_base' | 'sin_plan'

export type EquipoHoras = {
  activo_id: string
  patente: string | null
  codigo: string | null
  nombre: string | null
  tipo: string | null
  tipo_equipamiento: string | null
  faena: string | null
  horometro: number | null
  odometro: number | null
  gps_ultima_senal: string | null
  ultima_lectura: string | null
  horas_ayer: number | null
  horas_7d: number | null
  horas_30d: number | null
  km_30d: number | null
  dias_con_uso_30d: number | null
  horas_por_dia: number | null
  plan_id: string | null
  proxima_pauta: string | null
  frecuencia_horas: number | null
  horas_faltan: number | null
  ultima_preventiva_fecha: string | null
  ultima_preventiva_horas: number | null
  fecha_estimada: string | null
  estado_preventiva: EstadoPreventiva
  ot_abierta: string | null
}

export type HorasDia = {
  fecha: string
  horometro_fin: number | null
  horas: number | null
  km: number | null
}

export async function getEquiposHoras() {
  const { data, error } = await supabase.from('v_equipo_horas').select('*')
  if (error) throw new Error(error.message)
  return (data ?? []) as EquipoHoras[]
}

export async function getHorasDia(activoId: string, desde: string) {
  const { data, error } = await supabase
    .from('v_activo_horas_dia')
    .select('fecha, horometro_fin, horas, km')
    .eq('activo_id', activoId)
    .gte('fecha', desde)
    .order('fecha')
  if (error) throw new Error(error.message)
  return (data ?? []) as HorasDia[]
}
