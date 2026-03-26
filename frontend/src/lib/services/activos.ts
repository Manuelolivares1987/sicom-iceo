import { supabase } from '@/lib/supabase'
import type { Activo, TipoActivo, EstadoActivo, Criticidad } from '@/types/database'
import type { Database } from '@/types/database'

export interface ActivoFilters {
  faena_id?: string
  tipo?: TipoActivo
  estado?: EstadoActivo
  criticidad?: Criticidad
}

export async function getActivos(filters?: ActivoFilters) {
  let query = supabase
    .from('activos')
    .select('*, modelo:modelos(*, marca:marcas(*)), faena:faenas(*)')

  if (filters?.faena_id) {
    query = query.eq('faena_id', filters.faena_id)
  }
  if (filters?.tipo) {
    query = query.eq('tipo', filters.tipo)
  }
  if (filters?.estado) {
    query = query.eq('estado', filters.estado)
  }
  if (filters?.criticidad) {
    query = query.eq('criticidad', filters.criticidad)
  }

  const { data, error } = await query.order('codigo')

  return { data: data as Activo[] | null, error }
}

export async function getActivoById(id: string) {
  const { data, error } = await supabase
    .from('activos')
    .select('*, modelo:modelos(*, marca:marcas(*)), faena:faenas(*)')
    .eq('id', id)
    .single()

  return { data: data as Activo | null, error }
}

export async function getActivosByFaena(faenaId: string) {
  return getActivos({ faena_id: faenaId })
}

export async function updateActivo(
  id: string,
  data: Partial<Omit<Activo, 'id' | 'created_at' | 'updated_at'>>
) {
  const { data: updated, error } = await supabase
    .from('activos')
    .update(data)
    .eq('id', id)
    .select('*, modelo:modelos(*, marca:marcas(*)), faena:faenas(*)')
    .single()

  return { data: updated as Activo | null, error }
}

export async function createActivo(
  data: Database['public']['Tables']['activos']['Insert']
) {
  const { data: created, error } = await supabase
    .from('activos')
    .insert(data)
    .select('*, modelo:modelos(*, marca:marcas(*)), faena:faenas(*)')
    .single()

  return { data: created as Activo | null, error }
}

// Get OT history for an asset
export async function getOTsByActivo(activoId: string) {
  const { data, error } = await supabase
    .from('ordenes_trabajo')
    .select('id, folio, tipo, estado, prioridad, fecha_programada, fecha_inicio, fecha_termino, costo_total, responsable:usuarios_perfil!ordenes_trabajo_responsable_id_fkey(nombre_completo)')
    .eq('activo_id', activoId)
    .order('created_at', { ascending: false })
  return { data, error }
}

// Get maintenance plans for an asset
export async function getPlanesByActivo(activoId: string) {
  const { data, error } = await supabase
    .from('planes_mantenimiento')
    .select('*, pauta:pautas_fabricante(id, nombre, tipo_plan, frecuencia_dias, frecuencia_km, frecuencia_horas, frecuencia_ciclos, items_checklist, materiales_estimados)')
    .eq('activo_id', activoId)
    .eq('activo_plan', true)
    .order('proxima_ejecucion_fecha', { ascending: true })
  return { data, error }
}

// Get certifications for an asset
export async function getCertificacionesByActivo(activoId: string) {
  const { data, error } = await supabase
    .from('certificaciones')
    .select('*')
    .eq('activo_id', activoId)
    .order('fecha_vencimiento', { ascending: true })
  return { data, error }
}

// Get cost summary for an asset (total spent on OTs)
export async function getCostosByActivo(activoId: string) {
  const { data, error } = await supabase
    .from('movimientos_inventario')
    .select('costo_unitario, cantidad, tipo, created_at, producto:productos(nombre), ot:ordenes_trabajo(folio)')
    .eq('activo_id', activoId)
    .in('tipo', ['salida', 'merma'])
    .order('created_at', { ascending: false })
  return { data, error }
}

// Update asset metrics (km, hours, cycles) — may trigger PM OTs
export async function actualizarMetricasActivo(data: {
  activo_id: string
  kilometraje?: number
  horas_uso?: number
  ciclos?: number
  usuario_id?: string
}) {
  const { data: result, error } = await supabase.rpc('rpc_actualizar_metricas_activo', {
    p_activo_id: data.activo_id,
    p_kilometraje: data.kilometraje ?? null,
    p_horas_uso: data.horas_uso ?? null,
    p_ciclos: data.ciclos ?? null,
    p_usuario_id: data.usuario_id ?? null,
  })
  return { data: result, error }
}

// Get asset ficha via RPC (for QR scan)
export async function getFichaActivo(activoId: string) {
  const { data, error } = await supabase.rpc('rpc_ficha_activo', {
    p_activo_id: activoId,
  })
  return { data, error }
}

// Generate QR code for asset
export async function generarQRActivo(activoId: string) {
  const { data, error } = await supabase.rpc('rpc_generar_qr_activo', {
    p_activo_id: activoId,
  })
  return { data, error }
}

// Get maintenance history via view
export async function getHistorialMantenimiento(activoId: string) {
  const { data, error } = await supabase
    .from('v_historial_mantenimiento_activo')
    .select('*')
    .eq('activo_id', activoId)
    .order('fecha_programada', { ascending: false })
  return { data, error }
}

// Get KPIs per asset via RPC
export async function getKPIActivo(activoId: string) {
  const { data, error } = await supabase.rpc('rpc_kpi_activo', {
    p_activo_id: activoId,
  })
  return { data, error }
}

// Get asset ranking by health score
export async function getRankingActivos() {
  const { data, error } = await supabase
    .from('v_ranking_activos')
    .select('*')
    .limit(50)
  return { data, error }
}
