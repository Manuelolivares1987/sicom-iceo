import { supabase } from '@/lib/supabase'
import type { Faena, Contrato } from '@/types/database'

export async function getFaenas(contratoId?: string) {
  let query = supabase
    .from('faenas')
    .select('*')

  if (contratoId) {
    query = query.eq('contrato_id', contratoId)
  }

  const { data, error } = await query.order('nombre')

  return { data: data as Faena[] | null, error }
}

export async function getFaenaById(id: string) {
  const { data, error } = await supabase
    .from('faenas')
    .select('*, contrato:contratos(*)')
    .eq('id', id)
    .single()

  return { data: data as (Faena & { contrato: Contrato }) | null, error }
}
