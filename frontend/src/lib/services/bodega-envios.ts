// [MIG712] Envíos entre bodegas (Coquimbo → faena) y mínimos por días de consumo.
//   Enviar  → sale de la bodega origen por FIFO y queda «en camino».
//   Recibir → la faena confirma lo que llegó; entra con el costo del envío.
//   Anular  → un envío en camino vuelve a la bodega origen.
import { supabase } from '@/lib/supabase'

export const BODEGA_COQUIMBO = 'BOD-CQB-F01'

export type EstadoEnvio = 'en_camino' | 'recibido' | 'recibido_con_diferencias' | 'anulado'
export type ItemEnvio = {
  producto_id: string; codigo: string; nombre: string; unidad: string | null
  enviada: number; recibida: number | null; costo_unitario: number
}
export type Envio = {
  id: string; folio: string; estado: EstadoEnvio; guia: string | null; observacion: string | null
  created_at: string; recibido_at: string | null; observacion_recepcion: string | null
  origen: { id: string; codigo: string; nombre: string }; destino: { id: string; codigo: string; nombre: string }
  creado_por: string | null; recibido_por: string | null; valor: number | null; items: ItemEnvio[]
}
export type Sugerido = {
  producto_id: string; codigo: string; nombre: string; unidad: string | null
  stock_destino: number; en_camino: number; minimo: number; maximo: number; consumo_diario: number | null
  stock_origen: number; sugerido: number; falta: number; urgente: boolean
}

export const ESTADO_ENVIO: Record<EstadoEnvio, { txt: string; cls: string }> = {
  en_camino: { txt: 'En camino', cls: 'bg-blue-100 text-blue-800' },
  recibido: { txt: 'Recibido', cls: 'bg-emerald-100 text-emerald-800' },
  recibido_con_diferencias: { txt: 'Recibido con diferencias', cls: 'bg-amber-100 text-amber-900' },
  anulado: { txt: 'Anulado', cls: 'bg-gray-100 text-gray-600' },
}

export async function getEnvios(bodegaId: string, soloEnCamino = false) {
  const { data, error } = await supabase.rpc('rpc_bodega_envios', { p_bodega_id: bodegaId, p_solo_en_camino: soloEnCamino })
  if (error) throw error
  return (data ?? []) as Envio[]
}

export async function getSugerido(origenId: string, destinoId: string) {
  const { data, error } = await supabase.rpc('rpc_bodega_envio_sugerido', { p_origen_id: origenId, p_destino_id: destinoId })
  if (error) throw error
  return (data ?? []) as Sugerido[]
}

export async function crearEnvio(p: {
  origenId: string; destinoId: string; items: { producto_id: string; cantidad: number }[]; guia: string; observacion: string; clientUuid: string
}) {
  const { data, error } = await supabase.rpc('rpc_bodega_envio_crear', {
    p_origen_id: p.origenId, p_destino_id: p.destinoId, p_items: p.items, p_guia: p.guia,
    p_observacion: p.observacion, p_client_uuid: p.clientUuid,
  })
  if (error) throw error
  return data as { ok: boolean; envio_id: string; folio: string; items: number; costo_total: number; repetida?: boolean }
}

export async function recibirEnvio(envioId: string, items: { producto_id: string; cantidad: number }[], observacion: string, clientUuid: string) {
  const { data, error } = await supabase.rpc('rpc_bodega_envio_recibir', {
    p_envio_id: envioId, p_items: items, p_observacion: observacion, p_client_uuid: clientUuid,
  })
  if (error) throw error
  return data as { ok: boolean; folio: string; items: number; con_diferencia: number; repetida?: boolean }
}

export async function anularEnvio(envioId: string, motivo: string) {
  const { data, error } = await supabase.rpc('rpc_bodega_envio_anular', { p_envio_id: envioId, p_motivo: motivo })
  if (error) throw error
  return data as { ok: boolean; folio: string; items: number }
}

export async function recalcularMinimos(bodegaId: string) {
  const { data, error } = await supabase.rpc('rpc_bodega_recalcular_minimos', { p_bodega_id: bodegaId })
  if (error) throw error
  return data as { ok: boolean; dias: number; fuente: 'auto_sicom' | 'auto_softland'; ventana_dias: number; productos_calculados: number; sin_minimo: number }
}
