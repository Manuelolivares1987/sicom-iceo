import { supabase } from '@/lib/supabase'

export type HistorialOSLegacy = {
  id: string
  activo_id: string | null
  anio: number | null
  os_numero: string
  os_cqbo: string | null
  patente_raw: string | null
  tipo_equipo: string | null
  marca_modelo: string | null
  faena: string | null
  cliente: string | null
  ubicacion: string | null
  fecha_recepcion: string | null
  fecha_entrega: string | null
  horometro: number | null
  kilometraje: number | null
  cumplimiento_pct: number | null
  responsable: string | null
  flag_mant_prev: boolean
  flag_correctivo: boolean
  flag_neumaticos: boolean
  flag_rev_tec: boolean
  flag_hab_estado: boolean
  flag_serv_externo: boolean
  num_trabajos: number | null
  horas_mo: number | null
  tipo_principal: string
}

/** OS legacy de UN activo, ordenadas por fecha desc. */
export async function getHistorialOSLegacyByActivo(activoId: string): Promise<HistorialOSLegacy[]> {
  const { data, error } = await supabase
    .from('v_historial_os_legacy_activo').select('*')
    .eq('activo_id', activoId)
    .order('fecha_recepcion', { ascending: false, nullsFirst: false })
    .limit(500)
  if (error) throw error
  return (data ?? []) as HistorialOSLegacy[]
}

/** OS legacy sin activo asociado (patentes raras tipo ESMAX, ROME-RAL). */
export async function getHistorialOSLegacySinActivo(): Promise<HistorialOSLegacy[]> {
  const { data, error } = await supabase
    .from('v_historial_os_legacy_activo').select('*')
    .is('activo_id', null)
    .order('fecha_recepcion', { ascending: false, nullsFirst: false })
    .limit(200)
  if (error) throw error
  return (data ?? []) as HistorialOSLegacy[]
}
