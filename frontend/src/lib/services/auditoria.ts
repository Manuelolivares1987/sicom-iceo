import { supabase } from '@/lib/supabase'

export interface AuditoriaFilters {
  tabla?: string
  registro_id?: string
  usuario_id?: string
  fecha_desde?: string
  fecha_hasta?: string
}

export async function getEventosAuditoria(filters?: AuditoriaFilters) {
  let query = supabase
    .from('auditoria_eventos')
    .select('*')

  if (filters?.tabla) query = query.eq('tabla', filters.tabla)
  if (filters?.registro_id) query = query.eq('registro_id', filters.registro_id)
  if (filters?.usuario_id) query = query.eq('usuario_id', filters.usuario_id)
  if (filters?.fecha_desde) query = query.gte('created_at', filters.fecha_desde)
  if (filters?.fecha_hasta) query = query.lte('created_at', filters.fecha_hasta)

  const { data, error } = await query
    .order('created_at', { ascending: false })
    .limit(100)

  return { data, error }
}
