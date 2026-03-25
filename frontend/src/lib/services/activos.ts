import { supabase } from '@/lib/supabase'
import type { Activo, TipoActivo, EstadoActivo, Criticidad } from '@/types/database'
import type { Database } from '@/types/database'

export interface ActivoFilters {
  faena_id?: string
  tipo?: TipoActivo
  estado?: EstadoActivo
  criticidad?: Criticidad
}

export async function getActivos(filters?: ActivoFilters) {
  let query = supabase
    .from('activos')
    .select('*, modelo:modelos(*, marca:marcas(*)), faena:faenas(*)')

  if (filters?.faena_id) {
    query = query.eq('faena_id', filters.faena_id)
  }
  if (filters?.tipo) {
    query = query.eq('tipo', filters.tipo)
  }
  if (filters?.estado) {
    query = query.eq('estado', filters.estado)
  }
  if (filters?.criticidad) {
    query = query.eq('criticidad', filters.criticidad)
  }

  const { data, error } = await query.order('codigo')

  return { data: data as Activo[] | null, error }
}

export async function getActivoById(id: string) {
  const { data, error } = await supabase
    .from('activos')
    .select('*, modelo:modelos(*, marca:marcas(*)), faena:faenas(*)')
    .eq('id', id)
    .single()

  return { data: data as Activo | null, error }
}

export async function getActivosByFaena(faenaId: string) {
  return getActivos({ faena_id: faenaId })
}

export async function updateActivo(
  id: string,
  data: Partial<Omit<Activo, 'id' | 'created_at' | 'updated_at'>>
) {
  const { data: updated, error } = await supabase
    .from('activos')
    .update(data)
    .eq('id', id)
    .select('*, modelo:modelos(*, marca:marcas(*)), faena:faenas(*)')
    .single()

  return { data: updated as Activo | null, error }
}

export async function createActivo(
  data: Database['public']['Tables']['activos']['Insert']
) {
  const { data: created, error } = await supabase
    .from('activos')
    .insert(data)
    .select('*, modelo:modelos(*, marca:marcas(*)), faena:faenas(*)')
    .single()

  return { data: created as Activo | null, error }
}
