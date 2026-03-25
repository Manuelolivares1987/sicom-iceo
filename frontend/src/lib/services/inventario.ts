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
  // CRITICAL: OT is mandatory for salidas
  if (!data.ot_id) {
    return {
      data: null,
      error: { message: 'No se permite salida sin OT asociada', details: '', hint: '', code: 'VALIDATION' },
    }
  }
  if (!data.producto_id) {
    return {
      data: null,
      error: { message: 'producto_id es obligatorio', details: '', hint: '', code: 'VALIDATION' },
    }
  }
  if (!data.usuario_id) {
    return {
      data: null,
      error: { message: 'usuario_id es obligatorio', details: '', hint: '', code: 'VALIDATION' },
    }
  }
  if (data.cantidad <= 0) {
    return {
      data: null,
      error: { message: 'La cantidad debe ser mayor a 0', details: '', hint: '', code: 'VALIDATION' },
    }
  }

  // Verify stock availability and get costo_promedio
  const { data: stock, error: stockError } = await supabase
    .from('stock_bodega')
    .select('cantidad, costo_promedio')
    .eq('bodega_id', data.bodega_id)
    .eq('producto_id', data.producto_id)
    .single()

  if (stockError) {
    return {
      data: null,
      error: { message: 'No se encontro stock para este producto en la bodega', details: stockError.message, hint: '', code: 'NOT_FOUND' },
    }
  }

  if (stock.cantidad < data.cantidad) {
    return {
      data: null,
      error: { message: `Stock insuficiente. Disponible: ${stock.cantidad}`, details: '', hint: '', code: 'INSUFFICIENT_STOCK' },
    }
  }

  const { data: movimiento, error } = await supabase
    .from('movimientos_inventario')
    .insert({
      bodega_id: data.bodega_id,
      producto_id: data.producto_id,
      tipo: 'salida' as const,
      cantidad: data.cantidad,
      costo_unitario: stock.costo_promedio,
      ot_id: data.ot_id,
      activo_id: data.activo_id ?? null,
      lote: data.lote ?? null,
      motivo: data.motivo ?? null,
      usuario_id: data.usuario_id,
    })
    .select()
    .single()

  return { data: movimiento as MovimientoInventario | null, error }
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
  const { data: movimiento, error } = await supabase
    .from('movimientos_inventario')
    .insert({
      bodega_id: data.bodega_id,
      producto_id: data.producto_id,
      tipo: 'entrada' as const,
      cantidad: data.cantidad,
      costo_unitario: data.costo_unitario,
      documento_referencia: data.documento_referencia,
      usuario_id: data.usuario_id,
      lote: data.lote ?? null,
      fecha_vencimiento: data.fecha_vencimiento ?? null,
    })
    .select()
    .single()

  return { data: movimiento as MovimientoInventario | null, error }
}

export async function registrarAjuste(data: {
  bodega_id: string
  producto_id: string
  cantidad: number
  tipo: 'ajuste_positivo' | 'ajuste_negativo'
  motivo: string
  ot_id?: string | null
  usuario_id: string
}) {
  if (!data.motivo) {
    return {
      data: null,
      error: { message: 'El motivo es obligatorio para ajustes', details: '', hint: '', code: 'VALIDATION' },
    }
  }

  // Negative adjustments require OT
  if (data.tipo === 'ajuste_negativo' && !data.ot_id) {
    return {
      data: null,
      error: { message: 'Ajustes negativos requieren OT asociada', details: '', hint: '', code: 'VALIDATION' },
    }
  }

  // Get costo_promedio for the adjustment
  const { data: stock } = await supabase
    .from('stock_bodega')
    .select('costo_promedio')
    .eq('bodega_id', data.bodega_id)
    .eq('producto_id', data.producto_id)
    .single()

  const { data: movimiento, error } = await supabase
    .from('movimientos_inventario')
    .insert({
      bodega_id: data.bodega_id,
      producto_id: data.producto_id,
      tipo: data.tipo,
      cantidad: data.cantidad,
      costo_unitario: stock?.costo_promedio ?? 0,
      motivo: data.motivo,
      ot_id: data.ot_id ?? null,
      usuario_id: data.usuario_id,
    })
    .select()
    .single()

  return { data: movimiento as MovimientoInventario | null, error }
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
