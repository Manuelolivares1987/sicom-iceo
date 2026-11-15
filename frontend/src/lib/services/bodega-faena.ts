// [MIG692] Bodega de faena (Franke): lector, salidas, recepción, conteo,
// mínimos por bodega, alertas y el combustible de la faena en el mismo panel.
import { supabase } from '@/lib/supabase'

export const BODEGA_FRANKE = 'BOD-FRK-F01'

export type ProductoLector = {
  producto_id: string
  codigo: string
  codigo_barras: string | null
  nombre: string
  categoria: string | null
  unidad: string | null
  stock: number
  minimo: number | null
  maximo: number | null
  exige_equipo: boolean
  exacto: boolean
}

export type EstadoStock = 'ok' | 'bajo' | 'agotado' | 'sin_minimo'
export type FilaStock = {
  producto_id: string; codigo: string; nombre: string; categoria: string | null; unidad: string | null
  stock: number; costo: number | null; valor: number; minimo: number | null; maximo: number | null
  estado: EstadoStock; ultimo_movimiento: string | null
}
export type MovBodega = {
  fecha: string; tipo: string; producto: string; codigo: string; cantidad: number; unidad: string | null
  equipo: string | null; ceco: string | null; motivo: string | null; usuario: string | null; valor: number | null
}
export type EstanqueFaena = {
  codigo: string; nombre: string; patente: string | null; capacidad: number | null; stock: number | null
  llenado_pct: number | null; estimable: boolean | null; medido_desde: string | null
}
export type DespachoFaena = {
  fecha: string; hora: string | null; turno: string | null; camion: string | null; equipo: string | null
  litros: number; operador: string | null; folio: string | null; tipo: string | null; ubicacion: string | null
}
export type PanelBodega = {
  bodega: { id: string; codigo: string; nombre: string; faena_id: string | null }
  puede_operar: boolean
  stock: FilaStock[]
  movimientos: MovBodega[]
  alertas: { producto: string; codigo: string; stock: number; minimo: number; desde: string; notificada: string | null }[]
  conteos_por_aprobar: number
  equipos: { id: string; patente: string; tipo: string }[]
  combustible: { estanques: EstanqueFaena[]; despachos: DespachoFaena[]; litros_30d: number } | null
}

export async function getBodegaPorCodigo(codigo: string) {
  const { data, error } = await supabase.from('bodegas').select('id, codigo, nombre').eq('codigo', codigo).maybeSingle()
  if (error) throw error
  return data as { id: string; codigo: string; nombre: string } | null
}

export async function getPanelBodega(bodegaId: string) {
  const { data, error } = await supabase.rpc('rpc_bodega_panel', { p_bodega_id: bodegaId })
  if (error) throw error
  return data as PanelBodega
}

export async function buscarProducto(bodegaId: string, texto: string) {
  const { data, error } = await supabase.rpc('rpc_bodega_faena_buscar', { p_bodega_id: bodegaId, p_texto: texto })
  if (error) throw error
  return (data ?? []) as ProductoLector[]
}

export type ItemLector = { producto_id: string; cantidad: number }

export async function registrarSalida(p: {
  bodegaId: string; items: ItemLector[]; activoId: string | null; motivo: string; entregadoA: string; clientUuid: string
}) {
  const { data, error } = await supabase.rpc('rpc_bodega_faena_salida', {
    p_bodega_id: p.bodegaId, p_items: p.items, p_activo_id: p.activoId, p_motivo: p.motivo,
    p_entregado_a: p.entregadoA, p_client_uuid: p.clientUuid,
  })
  if (error) throw error
  return data as { ok: boolean; items: number; costo_total: number; bajo_minimo: { producto: string; stock: number; minimo: number }[]; repetida?: boolean }
}

export async function registrarIngreso(p: { bodegaId: string; items: ItemLector[]; origen: string; documento: string; clientUuid: string }) {
  const { data, error } = await supabase.rpc('rpc_bodega_faena_ingreso', {
    p_bodega_id: p.bodegaId, p_items: p.items, p_origen: p.origen, p_documento: p.documento, p_client_uuid: p.clientUuid,
  })
  if (error) throw error
  return data as { ok: boolean; items: number; repetida?: boolean }
}

export async function registrarConteo(p: { bodegaId: string; items: ItemLector[]; completo: boolean; observacion: string; clientUuid: string }) {
  const { data, error } = await supabase.rpc('rpc_bodega_faena_conteo', {
    p_bodega_id: p.bodegaId, p_items: p.items, p_completo: p.completo, p_observacion: p.observacion, p_client_uuid: p.clientUuid,
  })
  if (error) throw error
  return data as { ok: boolean; conteo_id: string; productos: number; con_diferencia: number; repetida?: boolean }
}

export async function fijarMinimo(bodegaId: string, productoId: string, minimo: number, maximo: number | null) {
  const { error } = await supabase.rpc('rpc_bodega_set_parametro', {
    p_bodega_id: bodegaId, p_producto_id: productoId, p_minimo: minimo, p_maximo: maximo,
  })
  if (error) throw error
}

export const CATEGORIAS_NUEVO: { valor: string; texto: string }[] = [
  { valor: 'repuesto', texto: 'Repuesto' },
  { valor: 'filtro', texto: 'Filtro' },
  { valor: 'lubricante', texto: 'Lubricante' },
  { valor: 'implementos_de_seguridad', texto: 'EPP / seguridad' },
  { valor: 'ferreteria', texto: 'Ferretería / agua / insumos' },
  { valor: 'implementos_de_aseo_y_fungibles', texto: 'Aseo y fungibles' },
  { valor: 'articulos_de_oficina', texto: 'Oficina' },
]

export async function crearProductoFaena(bodegaId: string, nombre: string, categoria: string, unidad: string) {
  const { data, error } = await supabase.rpc('rpc_bodega_faena_producto_nuevo', {
    p_bodega_id: bodegaId, p_nombre: nombre, p_categoria: categoria, p_unidad: unidad,
  })
  if (error) throw error
  return data as { producto_id: string; codigo: string }
}

export const nuevoUuid = () =>
  typeof crypto !== 'undefined' && 'randomUUID' in crypto
    ? crypto.randomUUID()
    : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
        const r = (Math.random() * 16) | 0
        return (c === 'x' ? r : (r & 0x3) | 0x8).toString(16)
      })
