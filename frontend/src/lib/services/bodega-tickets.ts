import { supabase } from '@/lib/supabase'

const FIRMA_BUCKET = 'calama-firmas'

export type TicketEmitible = {
  ot_id: string
  ot_folio: string
  activo_codigo: string | null
  activo_nombre: string | null
  activo_patente: string | null
  n_materiales: number
}

export type EstadoTicket = 'emitido' | 'parcial' | 'entregado' | 'anulado'

export type BodegaTicket = {
  id: string
  folio: string
  qr_code: string | null
  ot_id: string | null
  activo_id: string | null
  bodega_id: string | null
  estado: EstadoTicket
  emitido_por: string | null
  firma_jefe_url: string | null
  observacion: string | null
  entregado_por: string | null
  entregado_at: string | null
  created_at: string
  /** De dónde nació: de los hallazgos de una OT, pedido a mano, o de oficina. */
  origen: 'ot' | 'manual' | 'oficina'
  motivo: string | null
  /** [MIG375] El centro de costo, cuando el vale no va contra un equipo. */
  ceco_id: string | null
  ceco_codigo: string | null
  ceco_nombre: string | null
  ot_folio: string | null
  faena_id: string | null
  activo_codigo: string | null
  activo_nombre: string | null
  activo_patente: string | null
  emitido_por_nombre: string | null
  entregado_por_nombre: string | null
  n_items: number
  n_entregados: number
  /** Ítems escritos a mano que bodega todavía no amarró a un producto. */
  n_sin_producto: number
}

export type BodegaTicketItem = {
  id: string
  ticket_id: string
  producto_id: string | null
  descripcion: string | null
  unidad: string | null
  cantidad_solicitada: number
  cantidad_entregada: number
  pendiente: number
  nc_id: string | null
  comentario: string | null
  producto_codigo: string | null
  producto_nombre: string | null
  unidad_medida: string | null
  /** Fotos del recurso pedido (o la foto de la NC de origen). MIG212. */
  fotos: string[] | null
  solicitado_nombre: string | null
  nc_descripcion: string | null
}

export type BodegaSimple = { id: string; nombre: string; faena_id: string | null }

// ── Firma ────────────────────────────────────────────────────────────────────
function dataUrlToBlob(dataUrl: string): Blob {
  const [meta, b64] = dataUrl.split(',')
  const mime = meta.match(/:(.*?);/)?.[1] ?? 'image/png'
  const bin = atob(b64)
  const arr = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) arr[i] = bin.charCodeAt(i)
  return new Blob([arr], { type: mime })
}

export async function subirFirmaTicket(dataUrl: string, prefijo = 'ticket'): Promise<string> {
  const path = `bodega-tickets/${prefijo}_${Date.now()}.png`
  const { error } = await supabase.storage.from(FIRMA_BUCKET).upload(path, dataUrlToBlob(dataUrl), { contentType: 'image/png' })
  if (error) throw error
  return supabase.storage.from(FIRMA_BUCKET).getPublicUrl(path).data.publicUrl
}

// ── Queries ──────────────────────────────────────────────────────────────────
export async function getEmitibles(): Promise<TicketEmitible[]> {
  const { data, error } = await supabase.from('v_bodega_tickets_emitibles').select('*')
  if (error) throw error
  return (data ?? []) as TicketEmitible[]
}

export async function getTickets(estado?: EstadoTicket): Promise<BodegaTicket[]> {
  let q = supabase.from('v_bodega_ticket').select('*').order('created_at', { ascending: false }).limit(200)
  if (estado) q = q.eq('estado', estado)
  const { data, error } = await q
  if (error) throw error
  return (data ?? []) as BodegaTicket[]
}

export async function getTicketById(id: string): Promise<BodegaTicket | null> {
  const { data, error } = await supabase.from('v_bodega_ticket').select('*')
    .eq('id', id).maybeSingle()
  if (error) throw error
  return (data as BodegaTicket | null) ?? null
}

/** Vales del equipo (por sus OT) — para reimprimir/anular desde la bandeja NC. */
export async function getTicketsOts(otIds: string[]): Promise<BodegaTicket[]> {
  if (otIds.length === 0) return []
  const { data, error } = await supabase.from('v_bodega_ticket').select('*')
    .in('ot_id', otIds).order('created_at', { ascending: false }).limit(20)
  if (error) throw error
  return (data ?? []) as BodegaTicket[]
}

export async function getTicketByFolio(folio: string): Promise<BodegaTicket | null> {
  const { data, error } = await supabase.from('v_bodega_ticket').select('*')
    .eq('folio', folio.trim().toUpperCase()).maybeSingle()
  if (error) throw error
  return (data as BodegaTicket | null) ?? null
}

export async function getTicketItems(ticketId: string): Promise<BodegaTicketItem[]> {
  const { data, error } = await supabase.from('v_bodega_ticket_items').select('*').eq('ticket_id', ticketId)
  if (error) throw error
  return (data ?? []) as BodegaTicketItem[]
}

export async function getBodegas(): Promise<BodegaSimple[]> {
  const { data, error } = await supabase.from('bodegas').select('id, nombre, faena_id').order('nombre')
  if (error) throw error
  return (data ?? []) as BodegaSimple[]
}

// Stock disponible (suma de capas FIFO) por producto en una bodega.
export async function getStockProductos(bodegaId: string, productoIds: string[]): Promise<Record<string, number>> {
  if (!bodegaId || productoIds.length === 0) return {}
  const { data, error } = await supabase
    .from('inventario_capas')
    .select('producto_id, cantidad_disponible')
    .eq('bodega_id', bodegaId).eq('estado', 'disponible')
    .in('producto_id', productoIds)
  if (error) throw error
  const out: Record<string, number> = {}
  for (const r of (data ?? []) as { producto_id: string; cantidad_disponible: number }[]) {
    out[r.producto_id] = (out[r.producto_id] ?? 0) + Number(r.cantidad_disponible)
  }
  return out
}

// ── Mutations ────────────────────────────────────────────────────────────────
export async function crearTicket(params: {
  otId: string; firmaJefeUrl: string; observacion?: string | null; bodegaId?: string | null
}) {
  const { data, error } = await supabase.rpc('rpc_crear_ticket_bodega', {
    p_ot_id: params.otId, p_firma_jefe_url: params.firmaJefeUrl,
    p_observacion: params.observacion ?? null, p_bodega_id: params.bodegaId ?? null,
  })
  if (error) throw error
  return data as { success: boolean; ticket_id: string; folio: string; qr: string; items: number }
}

/**
 * [MIG371] Pedido manual: se elige la patente y se escribe lo que hace falta,
 * sin esperar a que haya un hallazgo ni una OT abierta.
 *
 * Por dentro el vale igual cuelga de una OT de abastecimiento del equipo —el
 * kardex exige OT en toda salida— pero eso no se le pregunta a nadie: se
 * reutiliza la del equipo si ya existe.
 */
export type ItemValeManual = {
  /** Del catálogo. Sin él, bodega tendrá que amarrarlo antes de despachar. */
  producto_id?: string | null
  descripcion?: string | null
  cantidad: number
  unidad?: string | null
  comentario?: string | null
}

export async function crearValeManual(params: {
  activoId: string
  items: ItemValeManual[]
  motivo: string
  firmaJefeUrl: string
  bodegaId?: string | null
  observacion?: string | null
}) {
  const { data, error } = await supabase.rpc('rpc_crear_vale_manual', {
    p_activo_id: params.activoId,
    p_items: params.items,
    p_motivo: params.motivo,
    p_firma_jefe_url: params.firmaJefeUrl,
    p_bodega_id: params.bodegaId ?? null,
    p_observacion: params.observacion ?? null,
  })
  if (error) throw error
  return data as {
    success: boolean; ticket_id: string; folio: string; qr: string
    items: number
    /** Cuántos quedaron sin producto de catálogo: bodega los tendrá que amarrar. */
    items_sin_catalogo: number
    bodega_id: string | null
    ot_id: string; ot_folio: string; ot_reutilizada: boolean
  }
}

export type EquipoParaVale = {
  id: string; codigo: string; nombre: string | null; patente: string | null; estado: string | null
}

/**
 * Los equipos a los que se les puede pedir material. Consulta liviana a
 * propósito: es para un buscador, no para una ficha.
 */
export async function getEquiposParaVale(): Promise<EquipoParaVale[]> {
  const { data, error } = await supabase
    .from('activos')
    .select('id, codigo, nombre, patente, estado')
    .is('fecha_baja', null)
    .order('patente', { nullsFirst: false })
  if (error) throw error
  return (data ?? []) as EquipoParaVale[]
}

export type CecoLite = { id: string; codigo: string; nombre: string; area: string | null }

/**
 * Los centros de costo a los que puede cargar un pedido de oficina: los de
 * área, no los de equipo. Cada patente tiene su propio CECO y ésos se imputan
 * solos por el vale del taller — ofrecerlos acá sólo daría por dónde
 * equivocarse.
 */
export async function getCecosArea(): Promise<CecoLite[]> {
  const { data, error } = await supabase
    .from('centros_costo')
    .select('id, codigo, nombre, area')
    .like('codigo', 'CECO-%')
    .eq('activo', true)
    .order('nombre')
  if (error) throw error
  return (data ?? []) as CecoLite[]
}

/**
 * [MIG375] Vale de oficina: sale el mismo papel con folio y QR que el del
 * taller, pero cargado a un centro de costo en vez de a un equipo.
 *
 * Lo firma quien retira —no el jefe de taller— porque el control acá es otro:
 * el gasto queda con nombre y con centro de costo.
 */
export async function crearValeOficina(params: {
  cecoId: string
  items: ItemValeManual[]
  motivo: string
  firmaUrl: string
  bodegaId?: string | null
  observacion?: string | null
}) {
  const { data, error } = await supabase.rpc('rpc_crear_vale_oficina', {
    p_ceco_id: params.cecoId,
    p_items: params.items,
    p_motivo: params.motivo,
    p_firma_url: params.firmaUrl,
    p_bodega_id: params.bodegaId ?? null,
    p_observacion: params.observacion ?? null,
  })
  if (error) throw error
  return data as {
    success: boolean; ticket_id: string; folio: string; qr: string
    items: number; items_sin_catalogo: number
    bodega_id: string | null; ceco: string; ceco_nombre: string
  }
}

/**
 * Los vales que uno mismo emitió, para seguirlos sin llamar a bodega.
 *
 * `origen` acota a un solo camino: en la pantalla de oficina, mezclar los vales
 * que la misma persona emitió desde el taller es ruido —son de otro flujo, de
 * otro papel y de otro costo—.
 */
export async function getMisVales(origen?: 'ot' | 'manual' | 'oficina'): Promise<BodegaTicket[]> {
  const { data: u } = await supabase.auth.getUser()
  if (!u?.user) return []
  let q = supabase.from('v_bodega_ticket').select('*').eq('emitido_por', u.user.id)
  if (origen) q = q.eq('origen', origen)
  const { data, error } = await q.order('created_at', { ascending: false }).limit(20)
  if (error) throw error
  return (data ?? []) as BodegaTicket[]
}

/** Bodega amarra un ítem escrito a mano con su producto del catálogo. */
/**
 * Amarra el ítem a un producto del catálogo — o corrige el código si ya tenía
 * uno. [MIG394] El catálogo tiene familias con varios códigos (tallas, colores,
 * variantes), así que bodega necesita poder cambiarlo, no sólo ponerlo la
 * primera vez. El RPC rechaza el cambio si el vale ya se entregó/anuló o si el
 * ítem tiene entrega parcial, y sincroniza el recurso de taller de origen.
 */
export async function asignarProductoItem(itemId: string, productoId: string) {
  const { data, error } = await supabase.rpc('rpc_ticket_item_producto', {
    p_item_id: itemId, p_producto_id: productoId,
  })
  if (error) throw error
  return data as {
    success: boolean; producto: string
    codigo: string | null
    /** true si se cambió un código existente; false si era el primer amarre. */
    reasignado?: boolean
    sin_cambio?: boolean
  }
}

export async function entregarTicket(params: {
  ticketId: string; bodegaId: string
  entregas: { ticket_item_id: string; cantidad: number }[]
  entregadoA?: string | null; firmaBodegueroUrl?: string | null
}) {
  const { data, error } = await supabase.rpc('rpc_entregar_ticket_bodega', {
    p_ticket_id: params.ticketId, p_bodega_id: params.bodegaId,
    p_entregas: params.entregas, p_entregado_a: params.entregadoA ?? null,
    p_firma_bodeguero_url: params.firmaBodegueroUrl ?? null,
  })
  if (error) throw error
  return data as { success: boolean; despacho_folio: string | null; estado: EstadoTicket }
}

export async function anularTicket(ticketId: string, motivo?: string) {
  const { data, error } = await supabase.rpc('rpc_anular_ticket_bodega', { p_ticket_id: ticketId, p_motivo: motivo ?? null })
  if (error) throw error
  return data as { success: boolean }
}

/** Lo que bodega NO puede entregar se manda a comprar: entra al tablero de
 *  Seguimiento repuestos y avisa a adquisiciones (MIG218). */
export async function enviarItemACompra(ticketItemId: string, motivo?: string | null) {
  const { data, error } = await supabase.rpc('rpc_ticket_item_a_compra', {
    p_ticket_item_id: ticketItemId, p_motivo: motivo ?? null,
  })
  if (error) throw error
  return data as { success: boolean; recurso_id: string; cantidad: number; vale: string }
}
