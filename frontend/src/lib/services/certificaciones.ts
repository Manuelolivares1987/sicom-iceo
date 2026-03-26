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

// Get all certifications with activo info
export async function getAllCertificaciones(filters?: {
  estado?: string
  tipo?: string
  faena_id?: string
}) {
  let query = supabase
    .from('certificaciones')
    .select('*, activo:activos(id, codigo, nombre, tipo, faena_id, faena:faenas(nombre))')
    .order('fecha_vencimiento', { ascending: true })

  if (filters?.estado) query = query.eq('estado', filters.estado)
  if (filters?.tipo) query = query.eq('tipo', filters.tipo)
  if (filters?.faena_id) query = query.eq('activo.faena_id', filters.faena_id)

  const { data, error } = await query
  return { data, error }
}

// Get certification stats
export async function getCertificacionStats() {
  const { data, error } = await supabase
    .from('certificaciones')
    .select('estado')

  if (error || !data) return { data: null, error }

  const stats = {
    total: data.length,
    vigentes: data.filter(c => c.estado === 'vigente').length,
    por_vencer: data.filter(c => c.estado === 'por_vencer').length,
    vencidas: data.filter(c => c.estado === 'vencido').length,
  }
  return { data: stats, error: null }
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
