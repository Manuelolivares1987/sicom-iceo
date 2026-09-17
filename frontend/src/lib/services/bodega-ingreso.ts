// ============================================================================
// Ingreso de mercadería a bodega contra factura o guía (MIG566)
// ----------------------------------------------------------------------------
// La OC la emite un externo en Softland. Bodega recibe con la factura (o la
// guía) en la mano y lo único que necesita es subir el stock. Sin OC en SICOM:
// proveedor + documento + productos → capa FIFO + stock.
//
// Las búsquedas van al servidor: hay 1.845 productos y 2.300 proveedores, y
// PostgREST devuelve 1.000 filas como máximo (cargar "todo" deja la mitad
// fuera sin avisar).
// ============================================================================

import { supabase } from '@/lib/supabase'

export type DocTipo = 'factura' | 'guia' | 'boleta' | 'vale' | 'otro'

export interface ProveedorBusqueda {
  id: string
  codigo: string
  nombre: string
  rut: string | null
  tipo: string
}

export interface ProductoBusqueda {
  id: string
  codigo: string
  codigo_barras: string | null
  nombre: string
  categoria: string
  unidad_medida: string
  costo_unitario_actual: number
  tiene_vencimiento: boolean
}

export interface BodegaMini {
  id: string
  codigo: string
  nombre: string
  tipo: string
  faena_id: string
}

export interface IngresoItemInput {
  producto_id: string
  cantidad: number
  costo_unitario: number | null   // null / 0 = documento sin precio → costo provisional
  unidad?: string | null
  lote?: string | null
  vencimiento?: string | null
  observacion?: string | null
}

export interface IngresoPayload {
  proveedor_id: string
  bodega_id: string
  doc_tipo: DocTipo
  doc_numero: string
  doc_fecha: string | null
  items: IngresoItemInput[]
  evidencia_url?: string | null
  observacion?: string | null
}

export interface IngresoResult {
  success: boolean
  folio: string
  recepcion_id: string
  items: number
  items_costo_provisional: number
  solicitudes_atendidas: Array<{ ot_folio: string | null; descripcion: string; cantidad: number }>
}

export interface IngresoReciente {
  id: string
  folio_recepcion: string
  created_at: string
  documento_proveedor_tipo: DocTipo
  documento_proveedor_numero: string
  documento_proveedor_fecha: string | null
  evidencia_url: string | null
  observacion: string | null
  orden_compra_id: string | null
  proveedor: { nombre: string; rut: string | null } | null
  bodega: { codigo: string; nombre: string } | null
  items: Array<{ cantidad_recibida: number; costo_unitario_clp: number; producto: { nombre: string } | null }>
}

const esc = (s: string) => s.replace(/[%,()]/g, ' ').trim()

export async function buscarProveedores(q: string, limit = 15): Promise<ProveedorBusqueda[]> {
  const t = esc(q)
  if (!t) return []
  const rutNorm = t.replace(/[^0-9kK]/g, '')
  let query = supabase.from('proveedores').select('id, codigo, nombre, rut, tipo').eq('activo', true)
  // Si escribió un RUT (solo dígitos), buscar por código (= RUT sin DV) o por el RUT formateado.
  if (rutNorm.length >= 5 && /^[0-9kK]+$/.test(t.replace(/[.\-\s]/g, ''))) {
    const sinDv = rutNorm.length >= 8 ? rutNorm.slice(0, -1) : rutNorm
    query = query.or(`codigo.ilike.${sinDv}%,codigo.ilike.${rutNorm}%,nombre.ilike.%${t}%`)
  } else {
    query = query.ilike('nombre', `%${t}%`)
  }
  const { data, error } = await query.order('nombre').limit(limit)
  if (error) throw error
  return (data ?? []) as ProveedorBusqueda[]
}

export async function crearProveedorRapido(nombre: string, rut: string | null, tipo = 'otros') {
  const { data, error } = await supabase.rpc('rpc_proveedor_rapido', {
    p_nombre: nombre, p_rut: rut, p_tipo: tipo,
  })
  if (error) throw error
  return data as { success: boolean; proveedor_id: string; existia: boolean; codigo?: string }
}

export async function getProveedorById(id: string): Promise<ProveedorBusqueda | null> {
  const { data } = await supabase.from('proveedores').select('id, codigo, nombre, rut, tipo').eq('id', id).maybeSingle()
  return (data as ProveedorBusqueda | null) ?? null
}

export async function buscarProductos(q: string, limit = 20): Promise<ProductoBusqueda[]> {
  const t = esc(q)
  if (!t) return []
  const { data, error } = await supabase
    .from('productos')
    .select('id, codigo, codigo_barras, nombre, categoria, unidad_medida, costo_unitario_actual, tiene_vencimiento')
    .neq('categoria', 'combustible')
    .or(`nombre.ilike.%${t}%,codigo.ilike.%${t}%,codigo_barras.eq.${t}`)
    .order('nombre')
    .limit(limit)
  if (error) throw error
  return (data ?? []).map((p) => ({ ...p, costo_unitario_actual: Number(p.costo_unitario_actual ?? 0) })) as ProductoBusqueda[]
}

export async function crearProductoRapido(nombre: string, categoria: string, unidad: string, codigo?: string | null) {
  const { data, error } = await supabase.rpc('rpc_producto_rapido', {
    p_nombre: nombre, p_categoria: categoria, p_unidad: unidad, p_codigo: codigo ?? null,
  })
  if (error) throw error
  return data as { success: boolean; producto_id: string; codigo: string }
}

export async function getBodegasParaIngreso(): Promise<BodegaMini[]> {
  const { data, error } = await supabase.from('bodegas').select('id, codigo, nombre, tipo, faena_id').order('nombre')
  if (error) throw error
  return (data ?? []) as BodegaMini[]
}

// Pedidos del taller esperando compra de estos productos (ítems de OC pendientes, MIG201).
// El ingreso se los aplica solo; acá sólo se avisa cuántos hay.
export async function getPendientesCompraPorProducto(productoIds: string[]): Promise<Record<string, number>> {
  if (productoIds.length === 0) return {}
  const { data, error } = await supabase
    .from('ordenes_compra_items')
    .select('producto_id, cantidad_comprada, cantidad_recibida, orden_compra:ordenes_compra!inner(estado)')
    .in('producto_id', productoIds)
    .neq('estado', 'completo')
    .in('orden_compra.estado', ['abierta', 'parcial'])
  if (error) throw error
  const out: Record<string, number> = {}
  for (const r of (data ?? []) as Array<{ producto_id: string; cantidad_comprada: number; cantidad_recibida: number }>) {
    const pend = Number(r.cantidad_comprada) - Number(r.cantidad_recibida)
    if (pend > 0) out[r.producto_id] = (out[r.producto_id] ?? 0) + pend
  }
  return out
}

export async function subirEvidenciaIngreso(file: File): Promise<string> {
  const tempId = (typeof crypto !== 'undefined' && 'randomUUID' in crypto)
    ? crypto.randomUUID() : Math.random().toString(36).slice(2)
  const safeName = file.name.replace(/[^a-zA-Z0-9._-]/g, '_')
  const path = `bodega-ingreso/${tempId}/${safeName}`
  const { error } = await supabase.storage.from('documentos')
    .upload(path, file, { upsert: false, contentType: file.type || undefined })
  if (error) throw error
  return supabase.storage.from('documentos').getPublicUrl(path).data.publicUrl
}

export async function registrarIngresoBodega(payload: IngresoPayload): Promise<IngresoResult> {
  const { data, error } = await supabase.rpc('rpc_ingreso_bodega_simple', {
    p_proveedor_id: payload.proveedor_id,
    p_bodega_id: payload.bodega_id,
    p_doc_tipo: payload.doc_tipo,
    p_doc_numero: payload.doc_numero,
    p_items: payload.items.map((it) => ({
      producto_id: it.producto_id,
      cantidad: it.cantidad,
      costo_unitario: it.costo_unitario ?? 0,
      unidad: it.unidad ?? null,
      lote: it.lote ?? null,
      vencimiento: it.vencimiento ?? null,
      observacion: it.observacion ?? null,
    })),
    p_doc_fecha: payload.doc_fecha,
    p_evidencia_url: payload.evidencia_url ?? null,
    p_observacion: payload.observacion ?? null,
  })
  if (error) throw error
  return data as IngresoResult
}

export async function getIngresosRecientes(limit = 15): Promise<IngresoReciente[]> {
  const { data, error } = await supabase
    .from('recepciones_bodega')
    .select(`id, folio_recepcion, created_at, documento_proveedor_tipo, documento_proveedor_numero,
             documento_proveedor_fecha, evidencia_url, observacion, orden_compra_id,
             proveedor:proveedores(nombre, rut), bodega:bodegas(codigo, nombre),
             items:recepciones_bodega_items(cantidad_recibida, costo_unitario_clp, producto:productos(nombre))`)
    .order('created_at', { ascending: false })
    .limit(limit)
  if (error) throw error
  return (data ?? []) as unknown as IngresoReciente[]
}

// Dígito verificador chileno (módulo 11), para validar el RUT antes de crear el proveedor.
export function rutValido(rut: string): boolean {
  const n = rut.replace(/[^0-9kK]/g, '').toUpperCase()
  if (n.length < 8) return false
  const cuerpo = n.slice(0, -1); const dv = n.slice(-1)
  let s = 0; let m = 2
  for (const c of cuerpo.split('').reverse()) { s += Number(c) * m; m = m === 7 ? 2 : m + 1 }
  const r = 11 - (s % 11)
  const esperado = r === 11 ? '0' : r === 10 ? 'K' : String(r)
  return esperado === dv
}

export function formatearRut(rut: string): string {
  const n = rut.replace(/[^0-9kK]/g, '').toUpperCase()
  if (n.length < 2) return n
  const cuerpo = n.slice(0, -1); const dv = n.slice(-1)
  return `${Number(cuerpo).toLocaleString('es-CL')}-${dv}`
}
