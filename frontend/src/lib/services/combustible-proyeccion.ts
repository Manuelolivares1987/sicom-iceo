import { supabase } from '@/lib/supabase'

export type CombustibleProyeccion = {
  estanque_id: string
  estanque_codigo: string
  estanque_nombre: string
  capacidad_lt: number
  stock_actual: number
  stock_minimo: number
  litros_hoy: number
  despachos_hoy: number
  litros_ultimos_7d: number
  despachos_ultimos_7d: number
  litros_ultimos_30d: number
  despachos_ultimos_30d: number
  promedio_diario_7d: number
  promedio_diario_30d: number
  dias_cobertura: number | null
  fecha_agotamiento_estimada: string | null
  dias_hasta_minimo: number | null
  demanda_base_diaria: number
  ventana_usada: '7d' | '30d' | 'sin_datos'
  severidad: 'agotado' | 'critico' | 'urgente' | 'atencion' | 'ok'
}

export async function getCombustibleProyeccion(): Promise<CombustibleProyeccion[]> {
  const { data, error } = await supabase
    .from('v_combustible_proyeccion_stock').select('*')
    .order('severidad', { ascending: true })
    .order('estanque_codigo')
  if (error) throw error
  return (data ?? []) as CombustibleProyeccion[]
}

export type DemandaDiariaPorEmpresa = {
  fecha: string
  empresa: string
  estanque_codigo: string
  despachos: number
  litros: number
}

export async function getCombustibleDemandaDiariaEmpresa(): Promise<DemandaDiariaPorEmpresa[]> {
  const { data, error } = await supabase
    .from('v_combustible_demanda_externa_diaria').select('*')
    .order('fecha', { ascending: false })
    .limit(500)
  if (error) throw error
  return (data ?? []) as DemandaDiariaPorEmpresa[]
}
