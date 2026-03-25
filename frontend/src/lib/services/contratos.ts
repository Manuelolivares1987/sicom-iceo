import { supabase } from '@/lib/supabase'
import type { Contrato } from '@/types/database'

export async function getContratos() {
  const { data, error } = await supabase
    .from('contratos')
    .select('*')
    .order('created_at', { ascending: false })

  return { data: data as Contrato[] | null, error }
}

export async function getContratoById(id: string) {
  const { data, error } = await supabase
    .from('contratos')
    .select('*, faenas(*)')
    .eq('id', id)
    .single()

  return { data: data as (Contrato & { faenas: unknown[] }) | null, error }
}

export async function getContratoActivo() {
  const { data, error } = await supabase
    .from('contratos')
    .select('*')
    .eq('estado', 'activo')
    .limit(1)
    .single()

  return { data: data as Contrato | null, error }
}
