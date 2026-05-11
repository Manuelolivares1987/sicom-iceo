import { supabase } from '@/lib/supabase'

// ── Tipos ───────────────────────────────────────────────────────────────────

export interface OTValidaSalida {
  id: string
  folio: string
  tipo: string
  estado: 'asignada' | 'en_ejecucion'
  faena_id: string
  faena_nombre: string | null
  fecha_programada: string | null
  responsable_id: string | null
  responsable_nombre: string | null
}

export interface BodegaMini {
  id: string
  codigo: string
  nombre: string
  faena_id: string
  tipo: string
}

export interface CECOMini {
  id: string
  codigo: string
  nombre: string
  area: string | null
}

export interface StockDisponibleRow {
  producto_id: string
  producto_codigo: string
  producto_nombre: string
  producto_categoria: string
  unidad_medida: string
  cantidad_disponible: number
  costo_promedio: number
  valor_total: number
}

export interface CapaPreviewRow {
  capa_id: string
  fecha_recepcion: string
  folio_recepcion: string | null
  cantidad_disponible: number
  costo_unitario: number
}

export interface SalidaFifoItemInput {
  producto_id: string
  cantidad: number
  unidad?: string | null
}

export interface SalidaFifoPayload {
  bodega_id: string
  ceco_id: string
  ot_id: string
  motivo: string
  items: SalidaFifoItemInput[]
  entregado_a?: string | null
  entregado_a_perfil_id?: string | null
  autorizado_por?: string | null
  evidencia_url?: string | null
  observacion?: string | null
}

export interface SalidaFifoItemResult {
  salida_item_id: string
  producto_id: string
  cantidad: number | string
  costo_unitario_promedio: number
  costo_total: number
  capas_consumidas: Array<{
    capa_id: string
    fecha_recepcion: string
    folio_recepcion: string | null
    cantidad: number | string
    costo_unitario: number
    costo_total: number
  }>
}

export interface SalidaFifoResult {
  success: boolean
  folio: string
  salida_id: string
  metodo_costeo: 'fifo'
  items_count: number
  items: SalidaFifoItemResult[]
}

// ── Queries ─────────────────────────────────────────────────────────────────

export async function listarOTsValidasSalida() {
  const { data, error } = await supabase
    .from('ordenes_trabajo')
    .select(`
      id, folio, tipo, estado, faena_id, fecha_programada, responsable_id,
      faena:faenas ( nombre ),
      responsable:usuarios_perfil ( nombre_completo )
    `)
    .in('estado', ['asignada', 'en_ejecucion'])
    .order('fecha_programada', { ascending: false, nullsFirst: false })
    .order('created_at', { ascending: false })
  if (error) return { data: null, error }

  type Row = {
    id: string; folio: string; tipo: string; estado: 'asignada' | 'en_ejecucion'
    faena_id: string; fecha_programada: string | null; responsable_id: string | null
    faena: Array<{ nombre: string }>
    responsable: Array<{ nombre_completo: string }>
  }
  const rows: OTValidaSalida[] = (data as unknown as Row[]).map((r) => ({
    id: r.id, folio: r.folio, tipo: r.tipo, estado: r.estado,
    faena_id: r.faena_id, fecha_programada: r.fecha_programada,
    responsable_id: r.responsable_id,
    faena_nombre: r.faena?.[0]?.nombre ?? null,
    responsable_nombre: r.responsable?.[0]?.nombre_completo ?? null,
  }))
  return { data: rows, error: null }
}

export async function listarBodegasPorFaena(faenaId: string | null) {
  let q = supabase.from('bodegas').select('id, codigo, nombre, faena_id, tipo')
  if (faenaId) q = q.eq('faena_id', faenaId)
  const { data, error } = await q.order('codigo')
  return { data: data as BodegaMini[] | null, error }
}

export async function listarCECO() {
  const { data, error } = await supabase
    .from('centros_costo')
    .select('id, codigo, nombre, area')
    .eq('activo', true)
    .order('codigo')
  return { data: data as CECOMini[] | null, error }
}

export async function listarStockDisponible(bodegaId: string | null) {
  if (!bodegaId) return { data: [], error: null }
  const { data, error } = await supabase
    .from('stock_bodega')
    .select(`
      producto_id, cantidad, costo_promedio, valor_total,
      producto:productos ( id, codigo, nombre, categoria, unidad_medida )
    `)
    .eq('bodega_id', bodegaId)
    .gt('cantidad', 0)
  if (error) return { data: null, error }

  type Row = {
    producto_id: string; cantidad: number; costo_promedio: number; valor_total: number
    producto: Array<{ id: string; codigo: string; nombre: string; categoria: string; unidad_medida: string }>
  }
  const rows: StockDisponibleRow[] = (data as unknown as Row[])
    .map((r) => {
      const p = r.producto?.[0]
      if (!p) return null
      return {
        producto_id: r.producto_id,
        producto_codigo: p.codigo,
        producto_nombre: p.nombre,
        producto_categoria: p.categoria,
        unidad_medida: p.unidad_medida,
        cantidad_disponible: Number(r.cantidad),
        costo_promedio: Number(r.costo_promedio),
        valor_total: Number(r.valor_total),
      }
    })
    .filter((x): x is StockDisponibleRow => x !== null)
    .sort((a, b) => a.producto_codigo.localeCompare(b.producto_codigo))
  return { data: rows, error: null }
}

export async function previewFIFO(productoId: string, bodegaId: string, limitCapas = 10) {
  const { data, error } = await supabase
    .from('inventario_capas')
    .select('id, fecha_recepcion, folio_recepcion, cantidad_disponible, costo_unitario')
    .eq('producto_id', productoId)
    .eq('bodega_id', bodegaId)
    .eq('estado', 'disponible')
    .gt('cantidad_disponible', 0)
    .order('fecha_recepcion', { ascending: true })
    .order('created_at', { ascending: true })
    .limit(limitCapas)
  if (error) return { data: null, error }

  type Row = {
    id: string; fecha_recepcion: string; folio_recepcion: string | null
    cantidad_disponible: number; costo_unitario: number
  }
  const rows: CapaPreviewRow[] = (data as Row[]).map((r) => ({
    capa_id: r.id,
    fecha_recepcion: r.fecha_recepcion,
    folio_recepcion: r.folio_recepcion,
    cantidad_disponible: Number(r.cantidad_disponible),
    costo_unitario: Number(r.costo_unitario),
  }))
  return { data: rows, error: null }
}

export async function registrarSalidaFifo(payload: SalidaFifoPayload) {
  const items = payload.items.map((it) => ({
    producto_id: it.producto_id,
    cantidad: it.cantidad,
    unidad: it.unidad ?? null,
  }))
  const { data, error } = await supabase.rpc('rpc_registrar_salida_bodega', {
    p_tipo_salida:           'ot',
    p_bodega_id:             payload.bodega_id,
    p_ceco_id:               payload.ceco_id,
    p_ot_id:                 payload.ot_id,
    p_motivo:                payload.motivo,
    p_items:                 items,
    p_entregado_a:           payload.entregado_a ?? null,
    p_entregado_a_perfil_id: payload.entregado_a_perfil_id ?? null,
    p_autorizado_por:        payload.autorizado_por ?? null,
    p_evidencia_url:         payload.evidencia_url ?? null,
    p_observacion:           payload.observacion ?? null,
  })
  if (error) return { data: null, error }
  return { data: data as SalidaFifoResult, error: null }
}
