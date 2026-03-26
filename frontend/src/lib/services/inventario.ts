import { supabase } from '@/lib/supabase'
import type { Producto, StockBodega, MovimientoInventario, TipoMovimiento } from '@/types/database'
import type { Database } from '@/types/database'

// ── Filters ──────────────────────────────────────────────────────────

export interface ProductoFilters {
  categoria?: string
  search?: string
}

export interface StockFilters {
  bodega_id?: string
  categoria?: string
  below_minimum?: boolean
}

export interface MovimientoFilters {
  bodega_id?: string
  producto_id?: string
  tipo?: TipoMovimiento
  fecha_desde?: string
  fecha_hasta?: string
}

// ── Productos ────────────────────────────────────────────────────────

export async function getProductos(filters?: ProductoFilters) {
  let query = supabase
    .from('productos')
    .select('*')

  if (filters?.categoria) {
    query = query.eq('categoria', filters.categoria)
  }
  if (filters?.search) {
    query = query.or(
      `nombre.ilike.%${filters.search}%,codigo.ilike.%${filters.search}%`
    )
  }

  const { data, error } = await query.order('nombre')

  return { data: data as Producto[] | null, error }
}

export async function getProductoById(id: string) {
  const { data, error } = await supabase
    .from('productos')
    .select('*')
    .eq('id', id)
    .single()

  return { data: data as Producto | null, error }
}

export async function getProductoByCodigoBarras(codigo: string) {
  const { data, error } = await supabase
    .from('productos')
    .select('*')
    .eq('codigo_barras', codigo)
    .single()

  return { data: data as Producto | null, error }
}

// ── Stock ────────────────────────────────────────────────────────────

export async function getStockBodega(filters?: StockFilters) {
  let query = supabase
    .from('stock_bodega')
    .select('*, producto:productos(*), bodega:bodegas(*)')

  if (filters?.bodega_id) {
    query = query.eq('bodega_id', filters.bodega_id)
  }

  const { data, error } = await query.order('producto_id')

  if (error || !data) {
    return { data: data as StockBodega[] | null, error }
  }

  let result = data as (StockBodega & { producto: Producto })[]

  if (filters?.categoria) {
    result = result.filter((s) => s.producto?.categoria === filters.categoria)
  }

  if (filters?.below_minimum) {
    result = result.filter((s) => s.cantidad < (s.producto?.stock_minimo ?? 0))
  }

  return { data: result as StockBodega[] | null, error }
}

export async function getValorizacionTotal(faenaId?: string) {
  let query = supabase
    .from('stock_bodega')
    .select('valor_total, bodega:bodegas(faena_id)')

  const { data, error } = await query

  if (error || !data) {
    return { data: null, error }
  }

  let items = data as unknown as { valor_total: number; bodega: { faena_id: string } | null }[]

  if (faenaId) {
    items = items.filter((s) => s.bodega?.faena_id === faenaId)
  }

  const total = items.reduce((sum, s) => sum + (s.valor_total ?? 0), 0)

  return { data: total, error: null }
}

// ── Bodegas ──────────────────────────────────────────────────────────

export async function getBodegas(faenaId?: string) {
  let query = supabase
    .from('bodegas')
    .select('*')

  if (faenaId) {
    query = query.eq('faena_id', faenaId)
  }

  const { data, error } = await query.order('nombre')

  return { data, error }
}

// ── Movimientos ──────────────────────────────────────────────────────

export async function registrarSalidaInventario(data: {
  bodega_id: string
  producto_id: string
  cantidad: number
  ot_id: string | null
  activo_id?: string | null
  lote?: string | null
  motivo?: string | null
  usuario_id: string
}) {
  const { data: result, error } = await supabase.rpc('rpc_registrar_salida_inventario', {
    p_bodega_id: data.bodega_id,
    p_producto_id: data.producto_id,
    p_cantidad: data.cantidad,
    p_ot_id: data.ot_id,
    p_usuario_id: data.usuario_id,
    p_activo_id: data.activo_id ?? null,
    p_lote: data.lote ?? null,
    p_motivo: data.motivo ?? null,
  })

  return { data: result, error }
}

export async function registrarEntradaInventario(data: {
  bodega_id: string
  producto_id: string
  cantidad: number
  costo_unitario: number
  documento_referencia: string
  usuario_id: string
  lote?: string | null
  fecha_vencimiento?: string | null
}) {
  const { data: result, error } = await supabase.rpc('rpc_registrar_entrada_inventario', {
    p_bodega_id: data.bodega_id,
    p_producto_id: data.producto_id,
    p_cantidad: data.cantidad,
    p_costo_unitario: data.costo_unitario,
    p_documento_referencia: data.documento_referencia,
    p_usuario_id: data.usuario_id,
    p_lote: data.lote ?? null,
    p_fecha_vencimiento: data.fecha_vencimiento ?? null,
  })

  return { data: result, error }
}

export async function registrarAjuste(data: {
  bodega_id: string
  producto_id: string
  cantidad: number
  motivo: string
  ot_id?: string | null
  usuario_id: string
  autorizado_por?: string | null
}) {
  const { data: result, error } = await supabase.rpc('rpc_registrar_ajuste_inventario', {
    p_bodega_id: data.bodega_id,
    p_producto_id: data.producto_id,
    p_cantidad: data.cantidad,
    p_motivo: data.motivo,
    p_usuario_id: data.usuario_id,
    p_ot_id: data.ot_id ?? null,
    p_autorizado_por: data.autorizado_por ?? null,
  })

  return { data: result, error }
}

export async function getMovimientos(filters?: MovimientoFilters) {
  let query = supabase
    .from('movimientos_inventario')
    .select('*, producto:productos(*), bodega:bodegas(*), ot:ordenes_trabajo(id, folio, tipo)')

  if (filters?.bodega_id) query = query.eq('bodega_id', filters.bodega_id)
  if (filters?.producto_id) query = query.eq('producto_id', filters.producto_id)
  if (filters?.tipo) query = query.eq('tipo', filters.tipo)
  if (filters?.fecha_desde) query = query.gte('created_at', filters.fecha_desde)
  if (filters?.fecha_hasta) query = query.lte('created_at', filters.fecha_hasta)

  const { data, error } = await query.order('created_at', { ascending: false })

  return { data, error }
}

// ── Kardex ───────────────────────────────────────────────────────────

export async function getKardex(bodegaId: string, productoId: string) {
  const { data, error } = await supabase
    .from('kardex')
    .select('*')
    .eq('bodega_id', bodegaId)
    .eq('producto_id', productoId)
    .order('fecha', { ascending: false })

  return { data, error }
}

// ── Conteos ──────────────────────────────────────────────────────────

export async function crearConteo(data: {
  bodega_id: string
  tipo: string
  responsable_id: string
  observaciones?: string | null
}) {
  const { data: conteo, error } = await supabase
    .from('conteos_inventario')
    .insert(data)
    .select()
    .single()

  return { data: conteo, error }
}

export async function registrarConteoDetalle(data: {
  conteo_id: string
  producto_id: string
  bodega_id: string
  cantidad_contada: number
  observacion?: string | null
}) {
  // Get stock_sistema from stock_bodega
  const { data: stock } = await supabase
    .from('stock_bodega')
    .select('cantidad')
    .eq('bodega_id', data.bodega_id)
    .eq('producto_id', data.producto_id)
    .single()

  const { data: detalle, error } = await supabase
    .from('conteo_detalle')
    .insert({
      conteo_id: data.conteo_id,
      producto_id: data.producto_id,
      stock_sistema: stock?.cantidad ?? 0,
      cantidad_contada: data.cantidad_contada,
      observacion: data.observacion ?? null,
    })
    .select()
    .single()

  return { data: detalle, error }
}

export async function getConteos(bodegaId?: string) {
  let query = supabase
    .from('conteos_inventario')
    .select('*')

  if (bodegaId) {
    query = query.eq('bodega_id', bodegaId)
  }

  const { data, error } = await query.order('created_at', { ascending: false })

  return { data, error }
}

// ── Aliases (used by hooks) ─────────────────────────────────────────

export const registrarSalida = registrarSalidaInventario
export const registrarEntrada = registrarEntradaInventario
export const getProductoByBarcode = getProductoByCodigoBarras
