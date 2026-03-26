import { supabase } from '@/lib/supabase'

export async function getRutasDespacho(filters?: {
  faena_id?: string
  estado?: string
  fecha_desde?: string
  fecha_hasta?: string
}) {
  let query = supabase
    .from('rutas_despacho')
    .select(`
      *,
      faena:faenas(nombre),
      activo:activos(codigo, nombre, tipo),
      operador:usuarios_perfil(nombre_completo),
      ot:ordenes_trabajo(folio)
    `)
    .order('fecha_programada', { ascending: false })

  if (filters?.faena_id) query = query.eq('faena_id', filters.faena_id)
  if (filters?.estado) query = query.eq('estado', filters.estado)
  if (filters?.fecha_desde) query = query.gte('fecha_programada', filters.fecha_desde)
  if (filters?.fecha_hasta) query = query.lte('fecha_programada', filters.fecha_hasta)

  const { data, error } = await query
  return { data, error }
}

export async function getAbastecimientos(rutaId?: string) {
  let query = supabase
    .from('abastecimientos')
    .select(`
      *,
      producto:productos(nombre, unidad_medida),
      operador:usuarios_perfil(nombre_completo),
      ot:ordenes_trabajo(folio)
    `)
    .order('fecha_hora', { ascending: false })

  if (rutaId) query = query.eq('ruta_despacho_id', rutaId)

  const { data, error } = await query.limit(100)
  return { data, error }
}

export async function getRutaStats(faenaId?: string) {
  let query = supabase
    .from('rutas_despacho')
    .select('estado')

  if (faenaId) query = query.eq('faena_id', faenaId)

  const { data, error } = await query
  if (error || !data) return { data: null, error }

  return {
    data: {
      total: data.length,
      programadas: data.filter(r => r.estado === 'programada').length,
      completadas: data.filter(r => r.estado === 'completada').length,
      incompletas: data.filter(r => r.estado === 'incompleta').length,
    },
    error: null,
  }
}
