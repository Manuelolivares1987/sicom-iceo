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

export async function createRutaDespacho(data: {
  faena_id: string
  fecha_programada: string
  puntos_programados?: number
  km_programados?: number
}) {
  const { data: result, error } = await supabase
    .from('rutas_despacho')
    .insert({
      ...data,
      estado: 'programada',
      puntos_completados: 0,
      km_reales: 0,
      litros_despachados: 0,
    })
    .select(`
      *,
      faena:faenas(nombre),
      activo:activos(codigo, nombre, tipo),
      operador:usuarios_perfil(nombre_completo),
      ot:ordenes_trabajo(folio)
    `)
    .single()

  return { data: result, error }
}

export async function updateRutaEstado(id: string, estado: string) {
  const { data, error } = await supabase
    .from('rutas_despacho')
    .update({ estado })
    .eq('id', id)
    .select(`
      *,
      faena:faenas(nombre),
      activo:activos(codigo, nombre, tipo),
      operador:usuarios_perfil(nombre_completo),
      ot:ordenes_trabajo(folio)
    `)
    .single()

  return { data, error }
}

export async function createAbastecimiento(data: {
  ruta_despacho_id?: string
  producto_id: string
  cantidad_programada?: number
  cantidad_real?: number
}) {
  const { data: result, error } = await supabase
    .from('abastecimientos')
    .insert({
      ...data,
      fecha_hora: new Date().toISOString(),
    })
    .select(`
      *,
      producto:productos(nombre, unidad_medida),
      operador:usuarios_perfil(nombre_completo),
      ot:ordenes_trabajo(folio)
    `)
    .single()

  return { data: result, error }
}

export async function getPuntosPorFaena(faenaId: string) {
  // 1. Get activos that are service points in this faena
  const { data: activos, error: activosError } = await supabase
    .from('activos')
    .select('id, codigo, nombre, tipo, modelo:modelos(nombre, especificaciones)')
    .in('tipo', ['punto_fijo', 'surtidor', 'estanque', 'bomba', 'dispensador', 'manguera'])
    .eq('faena_id', faenaId)
    .eq('estado', 'operativo')
    .order('nombre')

  if (activosError || !activos) return { data: null, error: activosError }

  // 2. For each activo, get the last abastecimiento
  const puntosConStock = await Promise.all(
    activos.map(async (activo: any) => {
      const { data: ultimoAbast } = await supabase
        .from('abastecimientos')
        .select('cantidad_real, fecha_hora, producto:productos(nombre)')
        .eq('activo_destino_id', activo.id)
        .order('fecha_hora', { ascending: false })
        .limit(1)
        .maybeSingle()

      const capacidad = activo.modelo?.especificaciones?.capacidad_litros ?? null

      return {
        ...activo,
        capacidad_litros: capacidad,
        ultimo_abastecimiento: ultimoAbast,
        cantidad_sugerida: capacidad && ultimoAbast?.cantidad_real
          ? Math.max(0, capacidad - (ultimoAbast.cantidad_real * 0.3)) // Estimate ~70% consumed
          : capacidad ?? null,
      }
    })
  )

  return { data: puntosConStock, error: null }
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
