import { supabase } from '@/lib/supabase'

// ── Tipos ───────────────────────────────────────────────────────────────────

export interface ResumenFinanciero {
  valor_total_stock_fifo: number
  valor_total_stock_legacy: number
  total_salidas_mes: number
  costo_salidas_mes: number
  total_mermas_mes: number
  costo_mermas_mes: number
  productos_con_desviacion: number
  productos_sin_stock: number
  productos_bajo_minimo: number
  calculado_en: string
}

export interface StockValorizadoRow {
  producto_id: string
  producto_codigo: string
  producto_nombre: string
  categoria: string
  bodega_id: string
  bodega_codigo: string
  bodega_nombre: string
  cantidad_stock: number
  costo_promedio_legacy: number
  valor_legacy: number
  cantidad_fifo: number
  valor_fifo: number
  delta_cantidad: number
  delta_valor: number
  estado_reconciliacion: string
}

export interface CostoOTRow {
  ot_id: string
  ot_folio: string
  ot_estado: string
  faena_id: string | null
  faena: string | null
  ceco_id: string | null
  ceco_codigo: string | null
  ceco_nombre: string | null
  cantidad_salidas: number
  cantidad_items: number
  costo_total_fifo: number
  fecha_primera_salida: string | null
  fecha_ultima_salida: string | null
}

export interface CostoCECORow {
  ceco_id: string
  ceco_codigo: string
  ceco_nombre: string
  ceco_area: string | null
  cantidad_salidas: number
  cantidad_items: number
  costo_total_fifo: number
  fecha_primera: string | null
  fecha_ultima: string | null
}

export interface KardexRow {
  movimiento_id: string
  producto_id: string
  producto_codigo: string
  producto_nombre: string
  bodega_id: string
  bodega_codigo: string
  bodega_nombre: string
  fecha_movimiento: string
  tipo_movimiento: string
  referencia: string | null
  entrada_cantidad: number | null
  entrada_valor: number | null
  salida_cantidad: number | null
  salida_valor: number | null
  costo_unitario: number
  ot_id: string | null
  ot_folio: string | null
  motivo: string | null
}

export interface MermaAjusteRow {
  movimiento_id: string
  fecha: string
  tipo: 'ajuste_positivo' | 'ajuste_negativo' | 'merma'
  bodega_id: string
  bodega_codigo: string
  bodega_nombre: string
  producto_id: string
  producto_codigo: string
  producto_nombre: string
  categoria: string
  cantidad: number
  costo_unitario: number
  costo_total: number
  motivo: string | null
  usuario_id: string | null
  usuario_nombre: string | null
  usuario_rol: string | null
  ot_id: string | null
  ot_folio: string | null
}

// ── Queries ─────────────────────────────────────────────────────────────────

export async function getResumenFinanciero() {
  const { data, error } = await supabase
    .from('v_bodega_resumen_financiero')
    .select('*')
    .single()
  if (error) return { data: null, error }
  const r = data as Record<string, unknown>
  const resumen: ResumenFinanciero = {
    valor_total_stock_fifo:   Number(r.valor_total_stock_fifo ?? 0),
    valor_total_stock_legacy: Number(r.valor_total_stock_legacy ?? 0),
    total_salidas_mes:        Number(r.total_salidas_mes ?? 0),
    costo_salidas_mes:        Number(r.costo_salidas_mes ?? 0),
    total_mermas_mes:         Number(r.total_mermas_mes ?? 0),
    costo_mermas_mes:         Number(r.costo_mermas_mes ?? 0),
    productos_con_desviacion: Number(r.productos_con_desviacion ?? 0),
    productos_sin_stock:      Number(r.productos_sin_stock ?? 0),
    productos_bajo_minimo:    Number(r.productos_bajo_minimo ?? 0),
    calculado_en:             String(r.calculado_en ?? ''),
  }
  return { data: resumen, error: null }
}

export interface FiltrosStockValorizado {
  categoria?: string
  bodega_id?: string
  search?: string
  solo_con_stock?: boolean
}

export async function getStockValorizado(filtros?: FiltrosStockValorizado) {
  let q = supabase.from('v_bodega_stock_valorizado_actual').select('*')
  if (filtros?.categoria && filtros.categoria !== 'todos') q = q.eq('categoria', filtros.categoria)
  if (filtros?.bodega_id) q = q.eq('bodega_id', filtros.bodega_id)
  if (filtros?.search) {
    q = q.or(`producto_nombre.ilike.%${filtros.search}%,producto_codigo.ilike.%${filtros.search}%`)
  }
  if (filtros?.solo_con_stock) q = q.gt('cantidad_stock', 0)
  const { data, error } = await q.order('valor_fifo', { ascending: false })
  return { data: data as StockValorizadoRow[] | null, error }
}

export async function getCostosPorOT() {
  const { data, error } = await supabase
    .from('v_bodega_costo_salidas_por_ot')
    .select('*')
    .order('costo_total_fifo', { ascending: false })
  return { data: data as CostoOTRow[] | null, error }
}

export async function getCostosPorCECO() {
  const { data, error } = await supabase
    .from('v_bodega_costo_salidas_por_ceco')
    .select('*')
    .order('costo_total_fifo', { ascending: false })
  return { data: data as CostoCECORow[] | null, error }
}

export async function getKardexProducto(productoId: string, bodegaId?: string | null) {
  let q = supabase
    .from('v_bodega_kardex_valorizado_producto')
    .select('*')
    .eq('producto_id', productoId)
  if (bodegaId) q = q.eq('bodega_id', bodegaId)
  const { data, error } = await q.order('fecha_movimiento', { ascending: false }).limit(200)
  return { data: data as KardexRow[] | null, error }
}

export async function getMermasAjustes(tipo?: 'todos' | 'merma' | 'ajuste_negativo' | 'ajuste_positivo') {
  let q = supabase.from('v_bodega_mermas_ajustes').select('*')
  if (tipo && tipo !== 'todos') q = q.eq('tipo', tipo)
  const { data, error } = await q.order('fecha', { ascending: false })
  return { data: data as MermaAjusteRow[] | null, error }
}
