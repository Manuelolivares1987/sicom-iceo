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

/** [MIG635] Consumo por día desde la ECU (solo GPS de fábrica Renault). */
export type ConsumoDia = {
  fecha: string
  horas: number | null
  km: number | null
  litros: number | null
  litros_ralenti: number | null
  horas_ralenti: number | null
  litros_hora: number | null
  km_litro: number | null
  pct_ralenti: number | null
}

export async function getConsumoDia(activoId: string, desde: string) {
  const { data, error } = await supabase
    .from('v_activo_consumo_dia')
    .select('fecha, horas, km, litros, litros_ralenti, horas_ralenti, litros_hora, km_litro, pct_ralenti')
    .eq('activo_id', activoId)
    .gte('fecha', desde)
    .order('fecha')
  if (error) throw new Error(error.message)
  return (data ?? []) as ConsumoDia[]
}

/** [MIG640] Pautas por horas del equipo, con su última ejecución. */
export type PautaEquipo = {
  id: string
  nombre: string
  frecuencia_horas: number
  ultima_ejecucion_fecha: string | null
  ultima_ejecucion_horas: number | null
  ultima_ejecucion_km: number | null
}

export async function getPautasEquipo(activoId: string) {
  const { data, error } = await supabase
    .from('planes_mantenimiento')
    .select('id, nombre, frecuencia_horas, ultima_ejecucion_fecha, ultima_ejecucion_horas, ultima_ejecucion_km')
    .eq('activo_id', activoId)
    .eq('activo_plan', true)
    .not('frecuencia_horas', 'is', null)
    .order('frecuencia_horas')
  if (error) throw new Error(error.message)
  return (data ?? []) as PautaEquipo[]
}

/** Registra una preventiva ya hecha; deja al día los peldaños menores. */
export async function registrarPreventivaRealizada(v: {
  planId: string; fecha: string; horas: number; km: number | null; nota: string
}) {
  const { data, error } = await supabase.rpc('rpc_preventiva_registrar_realizada', {
    p_plan_id: v.planId, p_fecha: v.fecha, p_horas: v.horas, p_km: v.km, p_nota: v.nota.trim(),
  })
  if (error) throw new Error(error.message)
  return data as { plan: string; absorbidos: number }
}
