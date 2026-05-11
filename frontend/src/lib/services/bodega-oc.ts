import { supabase } from '@/lib/supabase'

// ── Tipos ───────────────────────────────────────────────────────────────────

export type EstadoOC = 'abierta' | 'parcial' | 'cerrada' | 'anulada'
export type EstadoOCItem = 'pendiente' | 'parcial' | 'completo'
export type OrigenOC = 'manual' | 'externa'

// MIG38 mig: 8 valores del CHECK constraint
export type TipoItemOC =
  | 'inventariable' | 'servicio' | 'combustible' | 'lubricante'
  | 'repuesto' | 'consumible' | 'activo' | 'otro'

export const TIPO_ITEM_OPCIONES: TipoItemOC[] = [
  'inventariable', 'servicio', 'combustible', 'lubricante',
  'repuesto', 'consumible', 'activo', 'otro',
]

export const TIPO_ITEM_NO_INVENTARIABLE: TipoItemOC[] = ['servicio', 'activo', 'otro']

export interface OrdenCompraRow {
  id: string
  numero_oc: string
  numero_oc_externo: string | null
  proveedor_id: string
  fecha_oc: string
  estado: EstadoOC
  origen: OrigenOC
  fecha_emision: string | null
  fecha_entrega: string | null
  proveedor_rut_snapshot: string | null
  monto_total_clp: number
  neto_clp: number | null
  iva_clp: number | null
  forma_pago: string | null
  documento_url: string | null
  documento_storage_path: string | null
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
  // MIG38
  tipo_item: TipoItemOC
  requiere_stock: boolean
  codigo_externo: string | null
  unidad_externa: string | null
  centro_costo_id: string | null
  centro_costo_codigo_externo: string | null
}

export interface OrdenCompraConRelaciones extends OrdenCompraRow {
  proveedor: { id: string; codigo: string; nombre: string } | null
  items_count: number
  items_inventariables: number
  items_servicios: number
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
      id, numero_oc, numero_oc_externo, proveedor_id, fecha_oc, estado,
      origen, fecha_emision, fecha_entrega, proveedor_rut_snapshot,
      monto_total_clp, neto_clp, iva_clp, forma_pago,
      documento_url, documento_storage_path,
      observacion, created_at, updated_at, created_by,
      proveedor:proveedores!ordenes_compra_proveedor_id_fkey ( id, codigo, nombre ),
      items:ordenes_compra_items ( id, cantidad_comprada, cantidad_recibida, tipo_item, requiere_stock )
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
    items: Array<{
      id: string
      cantidad_comprada: number
      cantidad_recibida: number
      tipo_item: TipoItemOC
      requiere_stock: boolean
    }>
  }
  const rows: OrdenCompraConRelaciones[] = (data as unknown as Row[]).map((r) => {
    const total = r.items.reduce((s, it) => s + Number(it.cantidad_comprada || 0), 0)
    const recib = r.items.reduce((s, it) => s + Number(it.cantidad_recibida || 0), 0)
    return {
      ...r,
      monto_total_clp: Number(r.monto_total_clp ?? 0),
      neto_clp: r.neto_clp != null ? Number(r.neto_clp) : null,
      iva_clp: r.iva_clp != null ? Number(r.iva_clp) : null,
      proveedor: r.proveedor?.[0] ?? null,
      items_count: r.items.length,
      items_inventariables: r.items.filter((i) => i.requiere_stock).length,
      items_servicios: r.items.filter((i) => !i.requiere_stock).length,
      items_recibidos_pct: total > 0 ? Math.round((recib / total) * 100) : 0,
    }
  })

  return { data: rows, error: null }
}

export async function getOCById(id: string) {
  const { data, error } = await supabase
    .from('ordenes_compra')
    .select(`
      id, numero_oc, numero_oc_externo, proveedor_id, fecha_oc, estado,
      origen, fecha_emision, fecha_entrega, proveedor_rut_snapshot,
      monto_total_clp, neto_clp, iva_clp, forma_pago,
      documento_url, documento_storage_path,
      observacion, created_at, updated_at, created_by,
      proveedor:proveedores!ordenes_compra_proveedor_id_fkey ( id, codigo, nombre ),
      items:ordenes_compra_items (
        id, orden_compra_id, producto_id, descripcion, unidad,
        cantidad_comprada, cantidad_recibida, cantidad_pendiente,
        precio_unitario_clp, estado, observacion, created_at,
        tipo_item, requiere_stock, codigo_externo, unidad_externa,
        centro_costo_id, centro_costo_codigo_externo,
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
    neto_clp: raw.neto_clp != null ? Number(raw.neto_clp) : null,
    iva_clp: raw.iva_clp != null ? Number(raw.iva_clp) : null,
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

// ── Importar OC externa (MIG38) ─────────────────────────────────────────────

export interface ImportarOCItemInput {
  descripcion: string
  cantidad_comprada: number
  precio_unitario_clp: number
  unidad?: string
  unidad_externa?: string | null
  codigo_externo?: string | null
  producto_id?: string | null
  tipo_item: TipoItemOC
  requiere_stock?: boolean | null  // si null, autocalc en backend
  centro_costo_codigo_externo?: string | null
  observacion?: string | null
}

export interface ImportarOCExternaPayload {
  proveedor_id: string
  numero_oc_externo: string
  items: ImportarOCItemInput[]
  fecha_emision?: string | null
  fecha_entrega?: string | null
  proveedor_rut?: string | null
  neto_clp?: number | null
  iva_clp?: number | null
  forma_pago?: string | null
  documento_url?: string | null
  documento_storage_path?: string | null
  observacion?: string | null
}

export interface ImportarOCResult {
  success: boolean
  orden_compra_id: string
  numero_oc: string
  numero_oc_externo: string
  origen: 'externa'
  items_count: number
  monto_total_clp: number
}

export async function importarOCExterna(payload: ImportarOCExternaPayload) {
  const items = payload.items.map((it) => ({
    descripcion: it.descripcion,
    cantidad_comprada: it.cantidad_comprada,
    precio_unitario_clp: it.precio_unitario_clp,
    unidad: it.unidad ?? 'unidad',
    unidad_externa: it.unidad_externa ?? null,
    codigo_externo: it.codigo_externo ?? null,
    producto_id: it.producto_id ?? null,
    tipo_item: it.tipo_item,
    requiere_stock: it.requiere_stock,
    centro_costo_codigo_externo: it.centro_costo_codigo_externo ?? null,
    observacion: it.observacion ?? null,
  }))
  const { data, error } = await supabase.rpc('rpc_importar_orden_compra_externa', {
    p_proveedor_id:           payload.proveedor_id,
    p_numero_oc_externo:      payload.numero_oc_externo,
    p_items:                  items,
    p_fecha_emision:          payload.fecha_emision ?? null,
    p_fecha_entrega:          payload.fecha_entrega ?? null,
    p_proveedor_rut:          payload.proveedor_rut ?? null,
    p_neto_clp:               payload.neto_clp ?? null,
    p_iva_clp:                payload.iva_clp ?? null,
    p_forma_pago:             payload.forma_pago ?? null,
    p_documento_url:          payload.documento_url ?? null,
    p_documento_storage_path: payload.documento_storage_path ?? null,
    p_raw_extracted_json:     null,
    p_observacion:            payload.observacion ?? null,
  })
  if (error) return { data: null, error }
  return { data: data as ImportarOCResult, error: null }
}

// ── Recepcion contra OC (MIG37 inventariable + MIG38 documental) ───────────

export type DocTipoProveedor = 'factura' | 'guia' | 'vale' | 'boleta' | 'otro'

export interface RecepcionarOCItemInput {
  oc_item_id: string
  // Si el item OC tiene producto_id, no se requiere mapear. Si es inventariable
  // sin producto_id, pasar producto_id aqui para mapear en la recepcion.
  producto_id?: string | null
  cantidad: number
  unidad?: string | null
  costo_unitario?: number | null  // si no se pasa, la RPC usa precio OC
  lote?: string | null
  vencimiento?: string | null
  observacion?: string | null
}

export interface RecepcionarOCPayload {
  orden_compra_id: string
  proveedor_id: string
  bodega_id: string
  doc_tipo: DocTipoProveedor
  doc_numero: string
  items: RecepcionarOCItemInput[]
  evidencia_url?: string | null
  observacion?: string | null
  permite_sobrecantidad?: boolean
  permite_precio_distinto?: boolean
  justificacion_override?: string | null
}

export interface RecepcionarOCResult {
  success: boolean
  folio: string
  recepcion_id: string
  items_count: number
  items_stock: number
  items_documentales: number
  capas_creadas: Array<{
    capa_id: string
    producto_id: string
    cantidad: number | string
    costo_unitario: number
  }>
}

export async function recepcionarOC(payload: RecepcionarOCPayload) {
  const items = payload.items.map((it) => ({
    oc_item_id: it.oc_item_id,
    producto_id: it.producto_id ?? null,
    cantidad: it.cantidad,
    unidad: it.unidad ?? null,
    costo_unitario: it.costo_unitario,
    lote: it.lote ?? null,
    vencimiento: it.vencimiento ?? null,
    observacion: it.observacion ?? null,
  }))
  const { data, error } = await supabase.rpc('rpc_registrar_recepcion_bodega', {
    p_proveedor_id:            payload.proveedor_id,
    p_bodega_id:               payload.bodega_id,
    p_doc_tipo:                payload.doc_tipo,
    p_doc_numero:              payload.doc_numero,
    p_items:                   items,
    p_orden_compra_id:         payload.orden_compra_id,
    p_evidencia_url:           payload.evidencia_url ?? null,
    p_observacion:             payload.observacion ?? null,
    p_permite_sobrecantidad:   payload.permite_sobrecantidad ?? false,
    p_permite_precio_distinto: payload.permite_precio_distinto ?? false,
    p_justificacion_override:  payload.justificacion_override ?? null,
  })
  if (error) return { data: null, error }
  return { data: data as RecepcionarOCResult, error: null }
}

// Subir documento OC al bucket 'documentos' con prefix bodega-oc/<tempId>/
export interface SubirDocumentoOCResult {
  url: string
  path: string
}

export async function subirDocumentoOC(file: File): Promise<{ data: SubirDocumentoOCResult | null; error: unknown }> {
  const tempId = (typeof crypto !== 'undefined' && 'randomUUID' in crypto)
    ? crypto.randomUUID()
    : Math.random().toString(36).slice(2)
  const safeName = file.name.replace(/[^a-zA-Z0-9._-]/g, '_')
  const path = `bodega-oc/${tempId}/${safeName}`

  const { error: uploadErr } = await supabase.storage
    .from('documentos')
    .upload(path, file, { upsert: false, contentType: file.type || undefined })
  if (uploadErr) return { data: null, error: uploadErr }

  const { data: publicData } = supabase.storage.from('documentos').getPublicUrl(path)
  return { data: { url: publicData.publicUrl, path }, error: null }
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
  rut: string | null
}

export async function listarProveedoresActivos() {
  const { data, error } = await supabase
    .from('proveedores')
    .select('id, codigo, nombre, tipo, rut')
    .eq('activo', true)
    .order('nombre')
  return { data: data as ProveedorMini[] | null, error }
}
