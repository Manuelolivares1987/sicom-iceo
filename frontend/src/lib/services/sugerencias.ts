import { supabase } from '@/lib/supabase'

export type EstadoSugerencia = 'nueva' | 'en_proceso' | 'aplicada' | 'descartada'

export type Sugerencia = {
  id: string
  texto: string
  contexto_url: string | null
  contexto_titulo: string | null
  usuario_id: string | null
  usuario_nombre: string | null
  usuario_rol: string | null
  prompt_generado: string | null
  estado: EstadoSugerencia
  email_enviado_at: string | null
  created_at: string
}

export const ESTADO_SUGERENCIA_LABEL: Record<EstadoSugerencia, string> = {
  nueva: 'Nueva',
  en_proceso: 'En proceso',
  aplicada: 'Aplicada',
  descartada: 'Descartada',
}

export async function getSugerencias(estado?: EstadoSugerencia | null): Promise<Sugerencia[]> {
  let q = supabase
    .from('sugerencias')
    .select('id, texto, contexto_url, contexto_titulo, usuario_id, usuario_nombre, usuario_rol, prompt_generado, estado, email_enviado_at, created_at')
    .order('created_at', { ascending: false })
  if (estado) q = q.eq('estado', estado)
  const { data, error } = await q
  if (error) throw error
  return (data ?? []) as Sugerencia[]
}

export async function updateSugerenciaEstado(id: string, estado: EstadoSugerencia): Promise<void> {
  const { error } = await supabase.from('sugerencias').update({ estado }).eq('id', id)
  if (error) throw error
}
