import { supabase } from '@/lib/supabase'

// ── Tipos ───────────────────────────────────────────────────────────────────

export type EstadoReconciliacionStock =
  | 'cuadrado'
  | 'desviacion_cantidad'
  | 'desviacion_valor'
  | 'sin_capa_fifo'
  | 'sin_stock_legacy'

export interface ReconciliacionStockFifoRow {
  producto_id: string
  producto_codigo: string
  producto_nombre: string
  producto_categoria: string
  bodega_id: string
  bodega_codigo: string
  bodega_nombre: string
  cantidad_legacy: number
  costo_promedio_legacy: number
  valor_legacy: number
  cantidad_fifo: number
  valor_fifo: number
  capas_activas: number
  capa_mas_antigua: string | null
  capa_mas_nueva: string | null
  delta_cantidad: number
  delta_valor: number
  ultimo_movimiento_legacy: string | null
  estado_reconciliacion: EstadoReconciliacionStock
}

export type EstadoReconciliacionCombustible =
  | 'cuadrado'
  | 'sin_varillaje'
  | 'varillaje_atrasado'
  | 'desviacion_fisica'
  | 'kardex_divergente'

export interface ReconciliacionCombustibleRow {
  estanque_id: string
  estanque_codigo: string
  estanque_nombre: string
  faena_id: string | null
  capacidad_lt: number
  estanque_stock_teorico_lt: number
  estanque_cpp_lt: number
  estanque_valor_total: number
  estanque_activo: boolean
  varilla_fecha: string | null
  varilla_fisico_lt: number | null
  varilla_teorico_snapshot_lt: number | null
  varilla_diferencia_snapshot_lt: number | null
  varilla_ajuste_movimiento_id: string | null
  varilla_observaciones: string | null
  delta_fisico_vs_teorico_lt: number | null
  dias_desde_ultima_varilla: number | null
  kardex_fecha: string | null
  kardex_tipo: string | null
  kardex_stock_lt: number | null
  kardex_cpp_lt: number | null
  kardex_valor_total: number | null
  delta_estanque_vs_kardex_lt: number | null
  estado_reconciliacion: EstadoReconciliacionCombustible
}

export interface MovimientoExcepcionalRow {
  movimiento_id: string
  fecha: string
  tipo: 'ajuste' | 'merma'
  bodega_id: string
  bodega_codigo: string
  bodega_nombre: string
  producto_id: string
  producto_codigo: string
  producto_nombre: string
  producto_categoria: string
  cantidad: number
  costo_unitario: number
  costo_total: number
  ot_id: string | null
  ot_folio: string | null
  activo_id: string | null
  lote: string | null
  documento_referencia: string | null
  motivo: string | null
  usuario_id: string
  usuario_nombre: string | null
  usuario_rol: string | null
}

// ── Filtros ─────────────────────────────────────────────────────────────────

export interface FiltrosStockFifo {
  estado?: EstadoReconciliacionStock | 'todos'
  bodega_id?: string
  search?: string
}

export interface FiltrosCombustible {
  estado?: EstadoReconciliacionCombustible | 'todos'
}

export interface FiltrosMovimientosExcepcionales {
  tipo?: 'ajuste' | 'merma' | 'todos'
  bodega_id?: string
}

// ── Queries ─────────────────────────────────────────────────────────────────

export async function getReconciliacionStockFifo(filtros?: FiltrosStockFifo) {
  let q = supabase
    .from('v_bodega_reconciliacion_stock_fifo')
    .select('*')

  if (filtros?.estado && filtros.estado !== 'todos') {
    q = q.eq('estado_reconciliacion', filtros.estado)
  }
  if (filtros?.bodega_id) q = q.eq('bodega_id', filtros.bodega_id)
  if (filtros?.search) {
    q = q.or(
      `producto_nombre.ilike.%${filtros.search}%,producto_codigo.ilike.%${filtros.search}%`,
    )
  }
  const { data, error } = await q.order('estado_reconciliacion').order('producto_nombre')
  return { data: data as ReconciliacionStockFifoRow[] | null, error }
}

export async function getReconciliacionCombustible(filtros?: FiltrosCombustible) {
  let q = supabase
    .from('v_bodega_reconciliacion_combustible')
    .select('*')
  if (filtros?.estado && filtros.estado !== 'todos') {
    q = q.eq('estado_reconciliacion', filtros.estado)
  }
  const { data, error } = await q.order('estado_reconciliacion').order('estanque_codigo')
  return { data: data as ReconciliacionCombustibleRow[] | null, error }
}

export async function getMovimientosExcepcionales(filtros?: FiltrosMovimientosExcepcionales) {
  let q = supabase
    .from('v_bodega_movimientos_excepcionales')
    .select('*')
  if (filtros?.tipo && filtros.tipo !== 'todos') q = q.eq('tipo', filtros.tipo)
  if (filtros?.bodega_id) q = q.eq('bodega_id', filtros.bodega_id)
  const { data, error } = await q.order('fecha', { ascending: false })
  return { data: data as MovimientoExcepcionalRow[] | null, error }
}

// ── Resumen agregado (para tarjetas de KPI en la pagina) ────────────────────

export interface ReconciliacionResumen {
  stock_fifo: Record<EstadoReconciliacionStock, number> & { total: number; valor_delta_total: number }
  combustible: Record<EstadoReconciliacionCombustible, number> & { total: number }
  movimientos_excepcionales_60d: number
}

export async function getReconciliacionResumen(): Promise<{
  data: ReconciliacionResumen | null
  error: unknown
}> {
  const [stock, comb, mov] = await Promise.all([
    getReconciliacionStockFifo({ estado: 'todos' }),
    getReconciliacionCombustible({ estado: 'todos' }),
    getMovimientosExcepcionales({ tipo: 'todos' }),
  ])
  if (stock.error) return { data: null, error: stock.error }
  if (comb.error) return { data: null, error: comb.error }
  if (mov.error) return { data: null, error: mov.error }

  const stockRows = stock.data ?? []
  const combRows = comb.data ?? []
  const movRows = mov.data ?? []

  const stockSummary = {
    cuadrado: 0, desviacion_cantidad: 0, desviacion_valor: 0,
    sin_capa_fifo: 0, sin_stock_legacy: 0,
    total: stockRows.length,
    valor_delta_total: 0,
  } as ReconciliacionResumen['stock_fifo']
  for (const r of stockRows) {
    stockSummary[r.estado_reconciliacion] += 1
    stockSummary.valor_delta_total += Number(r.delta_valor ?? 0)
  }

  const combSummary = {
    cuadrado: 0, sin_varillaje: 0, varillaje_atrasado: 0,
    desviacion_fisica: 0, kardex_divergente: 0,
    total: combRows.length,
  } as ReconciliacionResumen['combustible']
  for (const r of combRows) combSummary[r.estado_reconciliacion] += 1

  return {
    data: {
      stock_fifo: stockSummary,
      combustible: combSummary,
      movimientos_excepcionales_60d: movRows.length,
    },
    error: null,
  }
}
