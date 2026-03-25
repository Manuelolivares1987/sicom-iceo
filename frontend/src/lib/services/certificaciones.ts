import { supabase } from '@/lib/supabase'
import type { Certificacion } from '@/types/database'

export async function getCertificaciones(activoId?: string) {
  let query = supabase
    .from('certificaciones')
    .select('*, activo:activos(id, codigo, nombre, tipo)')

  if (activoId) {
    query = query.eq('activo_id', activoId)
  }

  const { data, error } = await query.order('fecha_vencimiento', { ascending: true })

  return { data: data as Certificacion[] | null, error }
}

export async function getCertificacionesVencidas() {
  const { data, error } = await supabase
    .from('certificaciones')
    .select('*, activo:activos(id, codigo, nombre, tipo)')
    .in('estado', ['vencido', 'por_vencer'])
    .order('fecha_vencimiento', { ascending: true })

  return { data: data as Certificacion[] | null, error }
}

export async function createCertificacion(
  data: Omit<Certificacion, 'id' | 'created_at' | 'updated_at' | 'archivo_url'> & {
    archivo_url?: string | null
  },
  file?: File
) {
  let archivoUrl: string | null = data.archivo_url ?? null

  if (file) {
    const fileExt = file.name.split('.').pop()
    const filePath = `certificaciones/${data.activo_id}/${Date.now()}.${fileExt}`

    const { error: uploadError } = await supabase.storage
      .from('certificaciones')
      .upload(filePath, file)

    if (uploadError) {
      return { data: null, error: uploadError }
    }

    const { data: { publicUrl } } = supabase.storage
      .from('certificaciones')
      .getPublicUrl(filePath)

    archivoUrl = publicUrl
  }

  const { data: created, error } = await supabase
    .from('certificaciones')
    .insert({ ...data, archivo_url: archivoUrl })
    .select('*, activo:activos(id, codigo, nombre, tipo)')
    .single()

  return { data: created as Certificacion | null, error }
}

export async function getProximosVencimientos(dias: number = 30) {
  const hoy = new Date().toISOString().split('T')[0]
  const limite = new Date()
  limite.setDate(limite.getDate() + dias)
  const limiteFecha = limite.toISOString().split('T')[0]

  const { data, error } = await supabase
    .from('certificaciones')
    .select('*, activo:activos(id, codigo, nombre, tipo)')
    .gte('fecha_vencimiento', hoy)
    .lte('fecha_vencimiento', limiteFecha)
    .order('fecha_vencimiento', { ascending: true })

  return { data: data as Certificacion[] | null, error }
}
