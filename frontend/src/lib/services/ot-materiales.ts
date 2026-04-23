import { supabase } from '@/lib/supabase'

export type EstadoMaterialOT = 'faltante' | 'suficiente' | 'despachado' | 'cancelado'

export interface MaterialOT {
  id: string
  ot_id: string
  producto_id: string
  cantidad_plan: number
  cantidad_entregada: number
  estado: EstadoMaterialOT
  bodega_id: string | null
  movimiento_id: string | null
  comentario: string | null
  planificado_por: string | null
  despachado_por: string | null
  despachado_en: string | null
  created_at: string
  updated_at: string
  producto?: {
    codigo: string
    nombre: string
    unidad_medida: string
  }
  bodega?: {
    nombre: string
  }
}

export interface MaterialPendienteDespacho {
  material_id: string
  estado: EstadoMaterialOT
  cantidad_plan: number
  cantidad_entregada: number
  bodega_id: string | null
  bodega: string | null
  producto_id: string
  producto_codigo: string
  producto_nombre: string
  unidad_medida: string
  stock_actual: number | null
  ot_id: string
  ot_folio: string
  ot_prioridad: string
  ot_fecha: string | null
  faena_id: string | null
  faena: string | null
  activo_id: string | null
  activo_patente: string | null
  activo_codigo: string | null
  planificado_por: string | null
  planificado_por_nombre: string | null
  comentario: string | null
  created_at: string
}

// ── RPCs ─────────────────────────────────────────────────

export async function agregarMaterialOT(
  otId: string,
  productoId: string,
  cantidad: number,
  comentario?: string,
) {
  const { data, error } = await supabase.rpc('fn_agregar_material_ot', {
    p_ot_id: otId,
    p_producto_id: productoId,
    p_cantidad: cantidad,
    p_comentario: comentario ?? null,
  })
  return { data, error }
}

export async function despacharMaterialOT(materialId: string, cantidad?: number) {
  const { data, error } = await supabase.rpc('fn_despachar_material_ot', {
    p_material_id: materialId,
    p_cantidad: cantidad ?? null,
  })
  return { data, error }
}

export async function cancelarMaterialOT(materialId: string) {
  const { error } = await supabase
    .from('ot_materiales_planeados')
    .update({ estado: 'cancelado' })
    .eq('id', materialId)
  return { error }
}

// ── Lectura ──────────────────────────────────────────────

export async function getMaterialesPorOT(otId: string) {
  const { data, error } = await supabase
    .from('ot_materiales_planeados')
    .select('*, producto:productos(codigo, nombre, unidad_medida), bodega:bodegas(nombre)')
    .eq('ot_id', otId)
    .order('created_at')
  return { data: data as MaterialOT[] | null, error }
}

export async function getMaterialesPendientesDespacho() {
  const { data, error } = await supabase
    .from('v_materiales_pendientes_despacho')
    .select('*')
    .order('ot_prioridad')
  return { data: data as MaterialPendienteDespacho[] | null, error }
}

// ── Buscar productos (autocomplete) ──────────────────────

export async function buscarProductos(query: string, limit = 20) {
  const q = query.trim()
  if (!q) return { data: [], error: null }
  const { data, error } = await supabase
    .from('productos')
    .select('id, codigo, nombre, unidad_medida, categoria')
    .or(`codigo.ilike.%${q}%,nombre.ilike.%${q}%`)
    .eq('activo', true)
    .limit(limit)
  return { data, error }
}
