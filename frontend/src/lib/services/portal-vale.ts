// ============================================================================
// El portal del vale de oficina (MIG376/377)
// ----------------------------------------------------------------------------
// Todo pasa por funciones SECURITY DEFINER que validan el token: el cliente
// nunca consulta una tabla directo, y el token va en cada llamada. Si el link
// se revoca, la siguiente llamada rebota sola.
// ============================================================================

import { supabase } from '@/lib/supabase'

export type PortalPublico = { valido: boolean; portal?: string }

export type CecoPortal = { id: string; codigo: string; nombre: string }

export type SesionPortal = {
  acceso_id: string
  nombre: string
  portal: string
  cecos: CecoPortal[]
  vigencia_hrs: number
  max_items: number
  max_vales: number
}

export type ProductoPortal = {
  id: string
  codigo: string | null
  nombre: string
  unidad_medida: string | null
  /** Si bodega lo tiene hoy. Sin esto el vale se emite para algo que no existe. */
  hay_stock: boolean
}

export type ItemPortal = { producto_id: string; cantidad: number; comentario?: string | null }

/** Lo único que se sabe antes de decir quién es uno: si el link sirve. */
export async function getPortalPublico(token: string): Promise<PortalPublico> {
  const { data, error } = await supabase.rpc('fn_portal_vale_publico', { p_token: token })
  if (error) throw error
  return (data ?? { valido: false }) as PortalPublico
}

export async function entrarAlPortal(token: string, nombre: string, rut?: string): Promise<SesionPortal> {
  const { data, error } = await supabase.rpc('fn_portal_vale_ingresar', {
    p_token: token, p_nombre: nombre, p_rut: rut ?? null,
  })
  if (error) throw error
  return data as SesionPortal
}

export async function buscarEnPortal(
  token: string, accesoId: string, q: string,
): Promise<ProductoPortal[]> {
  const { data, error } = await supabase.rpc('fn_portal_vale_catalogo', {
    p_token: token, p_acceso_id: accesoId, p_q: q,
  })
  if (error) throw error
  return (data ?? []) as ProductoPortal[]
}

export async function crearValePortal(params: {
  token: string; accesoId: string; cecoId: string
  items: ItemPortal[]; motivo: string; firma: string; observacion?: string | null
}) {
  const { data, error } = await supabase.rpc('rpc_portal_vale_crear', {
    p_token: params.token,
    p_acceso_id: params.accesoId,
    p_ceco_id: params.cecoId,
    p_items: params.items,
    p_motivo: params.motivo,
    p_firma: params.firma,
    p_observacion: params.observacion ?? null,
  })
  if (error) throw error
  return data as {
    success: boolean; ticket_id: string; folio: string; qr: string
    items: number; ceco: string; ceco_nombre: string; solicitante: string
  }
}

/** [MIG377] Cuando bodega no lo tiene, el camino es que lo compren. */
export async function pedirCompraPortal(params: {
  token: string; accesoId: string; descripcion: string
  cantidad: number; unidad?: string | null; area?: string | null; observacion?: string | null
}) {
  const { data, error } = await supabase.rpc('rpc_portal_solicitud_crear', {
    p_token: params.token,
    p_acceso_id: params.accesoId,
    p_descripcion: params.descripcion,
    p_cantidad: params.cantidad,
    p_unidad: params.unidad ?? null,
    p_area: params.area ?? null,
    p_observacion: params.observacion ?? null,
  })
  if (error) throw error
  return data as { success: boolean; solicitud_id: string; solicitante: string }
}

export type MisPedidosPortal = {
  vales: Array<{
    id: string; folio: string; estado: string
    ceco_nombre: string | null; n_items: number; created_at: string
  }>
  solicitudes: Array<{
    id: string; descripcion: string; cantidad: number; unidad: string | null
    estado: string; nota_bodega: string | null; created_at: string
  }>
}

export async function getMisPedidosPortal(token: string, accesoId: string): Promise<MisPedidosPortal> {
  const { data, error } = await supabase.rpc('fn_portal_vale_mis_pedidos', {
    p_token: token, p_acceso_id: accesoId,
  })
  if (error) throw error
  return (data ?? { vales: [], solicitudes: [] }) as MisPedidosPortal
}

/** El vale para imprimir. Sólo el ingreso que lo creó puede pedirlo. */
export async function getValePortal(token: string, accesoId: string, ticketId: string) {
  const { data, error } = await supabase.rpc('fn_portal_vale_ver', {
    p_token: token, p_acceso_id: accesoId, p_ticket_id: ticketId,
  })
  if (error) throw error
  return data as { ticket: Record<string, unknown>; items: Record<string, unknown>[] }
}
