import { supabase } from '@/lib/supabase'

// Get all active maintenance plans with asset and pauta info
export async function getPlanesMantenmiento(filters?: {
  faena_id?: string
  tipo_plan?: string
  vencidos?: boolean
}) {
  let query = supabase
    .from('planes_mantenimiento')
    .select(`
      *,
      activo:activos(id, codigo, nombre, tipo, faena_id, kilometraje_actual, horas_uso_actual,
        faena:faenas(id, nombre),
        modelo:modelos(nombre, marca:marcas(nombre))
      ),
      pauta:pautas_fabricante(id, nombre, tipo_plan, frecuencia_dias, frecuencia_km, frecuencia_horas, frecuencia_ciclos, duracion_estimada_hrs)
    `)
    .eq('activo_plan', true)
    .order('proxima_ejecucion_fecha', { ascending: true })

  if (filters?.faena_id) {
    // Filter through activo's faena_id - use activo.faena_id
    query = query.eq('activo.faena_id', filters.faena_id)
  }

  const { data, error } = await query
  return { data, error }
}

// Get pautas de fabricante (master templates)
export async function getPautasFabricante(modeloId?: string) {
  let query = supabase
    .from('pautas_fabricante')
    .select('*, modelo:modelos(id, nombre, tipo_activo, marca:marcas(nombre))')
    .eq('activo', true)
    .order('nombre')

  if (modeloId) query = query.eq('modelo_id', modeloId)

  const { data, error } = await query
  return { data, error }
}

// Get upcoming maintenance (next N days)
export async function getProximasMantenimientos(dias: number = 30) {
  const hoy = new Date().toISOString().slice(0, 10)
  const limite = new Date(Date.now() + dias * 24 * 60 * 60 * 1000).toISOString().slice(0, 10)

  const { data, error } = await supabase
    .from('planes_mantenimiento')
    .select(`
      *,
      activo:activos(id, codigo, nombre, tipo,
        faena:faenas(nombre),
        modelo:modelos(nombre, marca:marcas(nombre))
      ),
      pauta:pautas_fabricante(nombre, tipo_plan)
    `)
    .eq('activo_plan', true)
    .lte('proxima_ejecucion_fecha', limite)
    .order('proxima_ejecucion_fecha', { ascending: true })

  return { data, error }
}

// Get overdue maintenance (past proxima_ejecucion_fecha)
export async function getMantenimientosVencidos() {
  const hoy = new Date().toISOString().slice(0, 10)

  const { data, error } = await supabase
    .from('planes_mantenimiento')
    .select(`
      *,
      activo:activos(id, codigo, nombre, tipo,
        faena:faenas(nombre),
        modelo:modelos(nombre, marca:marcas(nombre))
      ),
      pauta:pautas_fabricante(nombre, tipo_plan)
    `)
    .eq('activo_plan', true)
    .lt('proxima_ejecucion_fecha', hoy)
    .order('proxima_ejecucion_fecha', { ascending: true })

  return { data, error }
}

// Get PM compliance stats
export async function getCumplimientoPM(faenaId?: string) {
  // Count OTs preventivas by estado
  let query = supabase
    .from('ordenes_trabajo')
    .select('estado', { count: 'exact' })
    .eq('tipo', 'preventivo')

  if (faenaId) query = query.eq('faena_id', faenaId)

  const { data, error } = await query
  return { data, error }
}
