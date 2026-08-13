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

/**
 * Lo que espera una decisión del usuario, aparte de lo que solo informa.
 *
 * La campanita llegó a mostrar 724 sin leer y las 11 solicitudes de repuestos
 * que el jefe de taller tenía que aprobar quedaron enterradas ahí adentro
 * (MIG283). El número de arriba cuenta lo que hay que decidir; los avisos de
 * documentos y OT vencidas siguen disponibles, pero en su propia pestaña.
 */
export async function getConteoPorDecidir(destinatarioId: string) {
  const { count, error } = await supabase
    .from('alertas')
    .select('*', { count: 'exact', head: true })
    .eq('destinatario_id', destinatarioId)
    .eq('leida', false)
    .eq('requiere_accion', true)

  return { data: count ?? 0, error }
}

/** Da por leídas de una vez las alertas informativas acumuladas. */
export async function marcarInformativasLeidas(destinatarioId: string) {
  const { error } = await supabase
    .from('alertas')
    .update({ leida: true, leida_en: new Date().toISOString() })
    .eq('destinatario_id', destinatarioId)
    .eq('leida', false)
    .eq('requiere_accion', false)

  return { error }
}
