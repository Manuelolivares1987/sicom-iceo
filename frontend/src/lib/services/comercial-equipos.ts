import { supabase } from '@/lib/supabase'

export interface ComercialEquipo {
  activo_id: string
  patente: string
  equipamiento: string | null
  estado_actual: string | null
  cliente_actual: string | null
  dias_arrendado: number
  ultimo_cliente: string | null
  fecha_ultimo_arriendo: string | null
  dias_sin_arriendo: number | null
}

// Días arrendado por equipo + último contrato antes de dejar de estar arrendado.
export async function getComercialEquipos(ini: string, fin: string): Promise<ComercialEquipo[]> {
  const { data, error } = await supabase.rpc('fn_comercial_equipos', { p_ini: ini, p_fin: fin })
  if (error) throw error
  return (data ?? []) as ComercialEquipo[]
}
