import { supabase } from '@/lib/supabase'

/** Un periodo de arriendo/uso reconstruido desde los cambios de estado. */
export type ArriendoPeriodo = {
  activo_id: string
  patente: string | null
  codigo: string | null
  equipo: string | null
  tipo_uso: 'arrendado' | 'leasing' | 'uso_interno'
  cliente: string | null
  lugar: string | null
  faena_id: string | null
  faena_nombre: string | null
  faena_region: string | null
  contrato_id: string | null
  fecha_inicio: string
  fecha_fin: string | null
  dias: number
  vigente: boolean
  horometro: number | null
  kilometraje: number | null
}

/** Historial de arriendos del equipo (más reciente primero). */
export async function getHistorialArriendos(activoId: string): Promise<ArriendoPeriodo[]> {
  const { data, error } = await supabase
    .from('v_historial_arriendos')
    .select('*')
    .eq('activo_id', activoId)
    .order('fecha_inicio', { ascending: false })
  if (error) throw error
  return (data ?? []) as ArriendoPeriodo[]
}

/** Último arriendo del equipo — "quién lo tuvo y dónde". */
export async function getUltimoArriendo(activoId: string): Promise<ArriendoPeriodo | null> {
  const { data, error } = await supabase
    .from('v_activo_ultimo_arriendo')
    .select('*')
    .eq('activo_id', activoId)
    .maybeSingle()
  if (error) throw error
  return (data ?? null) as ArriendoPeriodo | null
}
