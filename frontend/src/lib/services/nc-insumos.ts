import { supabase } from '@/lib/supabase'

// ============================================================================
// Insumos de una NC — UNA sola lista (MIG254).
//
// Antes había tres caminos distintos para pedirle algo a bodega desde una NC
// (materiales de la NC, toggle «no hay» y los insumos del taller) y el jefe
// tenía que adivinar cuál usar. Ahora la vista v_nc_insumos los junta y
// rpc_nc_insumo_agregar decide sola dónde guardar cada línea: los tres caminos
// terminan igual, en el vale de bodega del equipo.
// ============================================================================

export type NcInsumoEstado =
  | 'solicitado'   // lo pidió el operador y espera el visto bueno del jefe
  | 'aprobado'     // entra al próximo vale
  | 'rechazado'
  | 'en_vale'
  | 'entregado'
  | 'en_compra'    // sin stock: bodega lo compra

export type NcInsumo = {
  id: string
  fuente: 'recurso' | 'material' | 'compra'
  nc_id: string
  ot_id: string | null
  producto_id: string | null
  descripcion: string | null
  unidad: string | null
  cantidad: number
  cantidad_pedida: number
  estado: NcInsumoEstado
  comentario: string | null
  fotos: string[] | null
  solicitado_nombre: string | null
  lo_agrego_el_jefe: boolean
  ticket_id: string | null
  ticket_folio: string | null
  created_at: string
}

export const INSUMO_ESTADO: Record<NcInsumoEstado, { txt: string; cls: string }> = {
  solicitado: { txt: 'Por aprobar',  cls: 'bg-amber-100 text-amber-800' },
  aprobado:   { txt: 'Va en el próximo vale', cls: 'bg-green-100 text-green-800' },
  rechazado:  { txt: 'Rechazado',    cls: 'bg-gray-200 text-gray-500' },
  en_vale:    { txt: 'En vale',      cls: 'bg-blue-100 text-blue-800' },
  entregado:  { txt: 'Entregado',    cls: 'bg-green-600 text-white' },
  en_compra:  { txt: 'En compra',    cls: 'bg-violet-100 text-violet-800' },
}

/** Todos los insumos de la NC, vengan de donde vengan. */
export async function getInsumosNc(ncId: string): Promise<NcInsumo[]> {
  const { data, error } = await supabase
    .from('v_nc_insumos')
    .select('*')
    .eq('nc_id', ncId)
    .order('created_at')
  if (error) throw error
  return (data ?? []) as NcInsumo[]
}

export type ProductoConStock = {
  id: string
  codigo: string | null
  nombre: string
  unidad_medida: string | null
  stock: number
}

/** Busca en bodega mostrando cuánto queda: el jefe ya no adivina si hay. */
export async function buscarInsumosConStock(q: string, limit = 8): Promise<ProductoConStock[]> {
  if (q.trim().length < 2) return []
  const { data, error } = await supabase.rpc('rpc_buscar_insumos', { p_q: q.trim(), p_limit: limit })
  if (error) throw error
  return (data ?? []) as ProductoConStock[]
}

/** Agrega un insumo a la NC. El sistema elige el circuito según tenga OT o no. */
export async function agregarInsumoNc(p: {
  ncId: string
  cantidad: number
  productoId?: string | null
  descripcion?: string | null
  unidad?: string | null
  comentario?: string | null
  fotos?: string[] | null
}): Promise<{ ok: boolean; id: string; fuente: string; stock: number; sin_stock: boolean }> {
  const { data, error } = await supabase.rpc('rpc_nc_insumo_agregar', {
    p_nc_id: p.ncId,
    p_cantidad: p.cantidad,
    p_producto_id: p.productoId ?? null,
    p_descripcion: p.descripcion ?? null,
    p_unidad: p.unidad ?? null,
    p_comentario: p.comentario ?? null,
    p_fotos: p.fotos ?? null,
  })
  if (error) throw error
  return data as any
}

/** Quita una línea (solo si todavía no viaja en un vale). */
export async function quitarInsumoNc(id: string, fuente: NcInsumo['fuente']) {
  const { data, error } = await supabase.rpc('rpc_nc_insumo_quitar', { p_id: id, p_fuente: fuente })
  if (error) throw error
  return data
}
