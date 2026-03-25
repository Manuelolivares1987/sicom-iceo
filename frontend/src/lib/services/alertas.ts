import { supabase } from '@/lib/supabase'
import type { Alerta } from '@/types/database'

export async function getAlertas(destinatarioId?: string, leidas?: boolean) {
  let query = supabase
    .from('alertas')
    .select('*')

  if (destinatarioId) {
    query = query.eq('destinatario_id', destinatarioId)
  }
  if (leidas !== undefined) {
    query = query.eq('leida', leidas)
  }

  const { data, error } = await query.order('created_at', { ascending: false })

  return { data: data as Alerta[] | null, error }
}

export async function getAlertasNoLeidas(destinatarioId: string) {
  const { data, error } = await supabase
    .from('alertas')
    .select('*')
    .eq('destinatario_id', destinatarioId)
    .eq('leida', false)
    .order('created_at', { ascending: false })

  return { data: data as Alerta[] | null, error }
}

export async function marcarLeida(id: string) {
  const { data, error } = await supabase
    .from('alertas')
    .update({
      leida: true,
      leida_en: new Date().toISOString(),
    })
    .eq('id', id)
    .select()
    .single()

  return { data: data as Alerta | null, error }
}

export async function getConteoNoLeidas(destinatarioId: string) {
  const { count, error } = await supabase
    .from('alertas')
    .select('*', { count: 'exact', head: true })
    .eq('destinatario_id', destinatarioId)
    .eq('leida', false)

  return { data: count ?? 0, error }
}
