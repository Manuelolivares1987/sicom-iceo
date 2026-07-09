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
  ot_folio: string | null
  faena_id: string | null
  activo_codigo: string | null
  activo_nombre: string | null
  activo_patente: string | null
  emitido_por_nombre: string | null
  entregado_por_nombre: string | null
  n_items: number
  n_entregados: number
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
