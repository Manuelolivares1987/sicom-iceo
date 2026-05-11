import { supabase } from '@/lib/supabase'

// ── Tipos ───────────────────────────────────────────────────────────────────

export type EstadoOC = 'abierta' | 'parcial' | 'cerrada' | 'anulada'
export type EstadoOCItem = 'pendiente' | 'parcial' | 'completo'

export interface OrdenCompraRow {
  id: string
  numero_oc: string
  proveedor_id: string
  fecha_oc: string
  estado: EstadoOC
  monto_total_clp: number
  observacion: string | null
  created_at: string
  updated_at: string
  created_by: string | null
}

export interface OrdenCompraItemRow {
  id: string
  orden_compra_id: string
  producto_id: string | null
  descripcion: string
  unidad: string
  cantidad_comprada: number
  cantidad_recibida: number
  cantidad_pendiente: number
  precio_unitario_clp: number
  estado: EstadoOCItem
  observacion: string | null
  created_at: string
}

export interface OrdenCompraConRelaciones extends OrdenCompraRow {
  proveedor: { id: string; codigo: string; nombre: string } | null
  items_count: number
  items_recibidos_pct: number
}

export interface OrdenCompraDetalle extends OrdenCompraRow {
  proveedor: { id: string; codigo: string; nombre: string } | null
  items: Array<OrdenCompraItemRow & {
    producto: { id: string; codigo: string; nombre: string; unidad_medida: string } | null
  }>
}

// ── Filtros ─────────────────────────────────────────────────────────────────

export interface FiltrosOC {
  estado?: EstadoOC | 'todos'
  proveedor_id?: string
  search?: string  // busca por numero_oc
  desde?: string
  hasta?: string
}

// ── Lectura ─────────────────────────────────────────────────────────────────

export async function listarOC(filtros?: FiltrosOC) {
  let q = supabase
    .from('ordenes_compra')
    .select(`
      id, numero_oc, proveedor_id, fecha_oc, estado, monto_total_clp,
      observacion, created_at, updated_at, created_by,
      proveedor:proveedores!ordenes_compra_proveedor_id_fkey ( id, codigo, nombre ),
      items:ordenes_compra_items ( id, cantidad_comprada, cantidad_recibida )
    `)

  if (filtros?.estado && filtros.estado !== 'todos') {
    q = q.eq('estado', filtros.estado)
  }
  if (filtros?.proveedor_id) q = q.eq('proveedor_id', filtros.proveedor_id)
  if (filtros?.search) q = q.ilike('numero_oc', `%${filtros.search}%`)
  if (filtros?.desde) q = q.gte('fecha_oc', filtros.desde)
  if (filtros?.hasta) q = q.lte('fecha_oc', filtros.hasta)

  const { data, error } = await q.order('fecha_oc', { ascending: false }).order('created_at', { ascending: false })
  if (error) return { data: null, error }

  // Supabase devuelve relaciones FK como array aunque sean 1-a-1.
  type Row = OrdenCompraRow & {
    proveedor: Array<{ id: string; codigo: string; nombre: string }>
    items: Array<{ id: string; cantidad_comprada: number; cantidad_recibida: number }>
  }
  const rows: OrdenCompraConRelaciones[] = (data as unknown as Row[]).map((r) => {
    const total = r.items.reduce((s, it) => s + Number(it.cantidad_comprada || 0), 0)
    const recib = r.items.reduce((s, it) => s + Number(it.cantidad_recibida || 0), 0)
    return {
      id: r.id,
      numero_oc: r.numero_oc,
      proveedor_id: r.proveedor_id,
      fecha_oc: r.fecha_oc,
      estado: r.estado,
      monto_total_clp: Number(r.monto_total_clp ?? 0),
      observacion: r.observacion,
      created_at: r.created_at,
      updated_at: r.updated_at,
      created_by: r.created_by,
      proveedor: r.proveedor?.[0] ?? null,
      items_count: r.items.length,
      items_recibidos_pct: total > 0 ? Math.round((recib / total) * 100) : 0,
    }
  })

  return { data: rows, error: null }
}

export async function getOCById(id: string) {
  const { data, error } = await supabase
    .from('ordenes_compra')
    .select(`
      id, numero_oc, proveedor_id, fecha_oc, estado, monto_total_clp,
      observacion, created_at, updated_at, created_by,
      proveedor:proveedores!ordenes_compra_proveedor_id_fkey ( id, codigo, nombre ),
      items:ordenes_compra_items (
        id, orden_compra_id, producto_id, descripcion, unidad,
        cantidad_comprada, cantidad_recibida, cantidad_pendiente,
        precio_unitario_clp, estado, observacion, created_at,
        producto:productos ( id, codigo, nombre, unidad_medida )
      )
    `)
    .eq('id', id)
    .single()
  if (error || !data) return { data: null, error }

  // Normalizar relaciones FK que Supabase devuelve como array.
  type RawItem = OrdenCompraItemRow & {
    producto: Array<{ id: string; codigo: string; nombre: string; unidad_medida: string }>
  }
  type RawData = OrdenCompraRow & {
    proveedor: Array<{ id: string; codigo: string; nombre: string }>
    items: RawItem[]
  }
  const raw = data as unknown as RawData
  const detalle: OrdenCompraDetalle = {
    ...raw,
    monto_total_clp: Number(raw.monto_total_clp ?? 0),
    proveedor: raw.proveedor?.[0] ?? null,
    items: raw.items.map((it) => ({
      ...it,
      cantidad_comprada: Number(it.cantidad_comprada),
      cantidad_recibida: Number(it.cantidad_recibida),
      cantidad_pendiente: Number(it.cantidad_pendiente),
      precio_unitario_clp: Number(it.precio_unitario_clp),
      producto: it.producto?.[0] ?? null,
    })),
  }
  return { data: detalle, error: null }
}

// ── Crear OC ────────────────────────────────────────────────────────────────

export interface CrearOCItemInput {
  producto_id?: string | null
  descripcion: string
  unidad: string
  cantidad_comprada: number
  precio_unitario_clp: number
  observacion?: string | null
}

export interface CrearOCPayload {
  proveedor_id: string
  items: CrearOCItemInput[]
  numero_oc?: string | null
  fecha_oc?: string  // YYYY-MM-DD
  observacion?: string | null
}

export interface CrearOCResult {
  success: boolean
  orden_compra_id: string
  numero_oc: string
  items_count: number
  monto_total_clp: number
}

export async function crearOC(payload: CrearOCPayload) {
  const items = payload.items.map((it) => ({
    producto_id: it.producto_id ?? null,
    descripcion: it.descripcion,
    unidad: it.unidad || 'unidad',
    cantidad_comprada: it.cantidad_comprada,
    precio_unitario_clp: it.precio_unitario_clp,
    observacion: it.observacion ?? null,
  }))

  const { data, error } = await supabase.rpc('rpc_crear_orden_compra', {
    p_proveedor_id: payload.proveedor_id,
    p_items: items,
    p_numero_oc: payload.numero_oc ?? null,
    p_fecha_oc: payload.fecha_oc ?? new Date().toISOString().slice(0, 10),
    p_observacion: payload.observacion ?? null,
  })
  if (error) return { data: null, error }
  return { data: data as CrearOCResult, error: null }
}

// ── Proveedores (helper para selector) ─────────────────────────────────────

export interface ProveedorMini {
  id: string
  codigo: string
  nombre: string
  tipo: string
}

export async function listarProveedoresActivos() {
  const { data, error } = await supabase
    .from('proveedores')
    .select('id, codigo, nombre, tipo')
    .eq('activo', true)
    .order('nombre')
  return { data: data as ProveedorMini[] | null, error }
}
