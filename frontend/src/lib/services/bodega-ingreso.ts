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
import { RUBROS_BODEGA } from '@/lib/bodega-rubros'

export type DocTipo = 'factura' | 'guia' | 'boleta' | 'vale' | 'otro'

export interface ProveedorBusqueda {
  id: string
  codigo: string
  nombre: string
  rut: string | null
  tipo: string
  rubro: string | null
  giro: string | null
  es_persona_natural?: boolean
  activo?: boolean
  contacto?: string | null
  telefono?: string | null
  email?: string | null
  rubro_fuente?: string | null
  rubro_confianza?: string | null
}

const PROV_COLS = 'id, codigo, nombre, rut, tipo, rubro, giro, es_persona_natural, activo, contacto, telefono, email, rubro_fuente, rubro_confianza'

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
  let query = supabase.from('proveedores').select(PROV_COLS).eq('activo', true)
  // Si escribió un RUT (solo dígitos), buscar por código (= RUT sin DV) o por el RUT formateado.
  if (rutNorm.length >= 5 && /^[0-9kK]+$/.test(t.replace(/[.\-\s]/g, ''))) {
    const sinDv = rutNorm.length >= 8 ? rutNorm.slice(0, -1) : rutNorm
    query = query.or(`codigo.ilike.${sinDv}%,codigo.ilike.${rutNorm}%,nombre.ilike.%${t}%`)
  } else {
    // Nombre o giro: "neumáticos" encuentra a la vulcanización aunque el nombre no lo diga.
    query = query.or(`nombre.ilike.%${t}%,giro.ilike.%${t}%`)
  }
  const { data, error } = await query.order('nombre').limit(limit * 2)
  if (error) throw error
  const rows = (data ?? []) as ProveedorBusqueda[]
  // Primero los que calzan por nombre y son del giro de bodega; después el resto.
  const tl = t.toLowerCase()
  const score = (p: ProveedorBusqueda) =>
    (p.nombre.toLowerCase().includes(tl) ? 0 : 2) + (RUBROS_BODEGA.has(p.rubro ?? '') ? 0 : 1)
  return rows.sort((a, b) => score(a) - score(b) || a.nombre.localeCompare(b.nombre)).slice(0, limit)
}

export async function crearProveedorRapido(nombre: string, rut: string | null, tipo = 'otros', rubro: string | null = null, giro: string | null = null) {
  const { data, error } = await supabase.rpc('rpc_proveedor_rapido', {
    p_nombre: nombre, p_rut: rut, p_tipo: tipo, p_rubro: rubro, p_giro: giro,
  })
  if (error) throw error
  return data as { success: boolean; proveedor_id: string; existia: boolean; codigo?: string }
}

export async function getProveedorById(id: string): Promise<ProveedorBusqueda | null> {
  const { data } = await supabase.from('proveedores').select(PROV_COLS).eq('id', id).maybeSingle()
  return (data as ProveedorBusqueda | null) ?? null
}

// ── Lista de proveedores (pantalla /dashboard/bodega/proveedores) ────────────

export interface FiltroProveedores {
  q?: string
  rubro?: string | null
  soloActivos?: boolean
  soloRevisar?: boolean   // confianza baja o media: lo que conviene mirar a mano
  limit?: number
  offset?: number
}

export async function listarProveedores(f: FiltroProveedores): Promise<{ rows: ProveedorBusqueda[]; total: number }> {
  let query = supabase.from('proveedores').select(PROV_COLS, { count: 'exact' })
  if (f.soloActivos !== false) query = query.eq('activo', true)
  if (f.rubro) query = query.eq('rubro', f.rubro)
  if (f.soloRevisar) query = query.in('rubro_confianza', ['baja', 'media'])
  const t = esc(f.q ?? '')
  if (t) query = query.or(`nombre.ilike.%${t}%,giro.ilike.%${t}%,rut.ilike.%${t}%,codigo.ilike.%${t}%`)
  const { data, error, count } = await query.order('nombre').range(f.offset ?? 0, (f.offset ?? 0) + (f.limit ?? 50) - 1)
  if (error) throw error
  return { rows: (data ?? []) as ProveedorBusqueda[], total: count ?? 0 }
}

export async function contarProveedoresPorRubro(): Promise<Record<string, number>> {
  // Agregado en la BD: leer las filas cortaba en 1.000 y los totales salían mal.
  const { data, error } = await supabase.from('v_proveedores_por_rubro').select('rubro, n')
  if (error) throw error
  const out: Record<string, number> = {}
  for (const r of (data ?? []) as Array<{ rubro: string; n: number }>) out[r.rubro] = r.n
  return out
}

export interface ProveedorPatch {
  nombre?: string; rut?: string | null; tipo?: string; rubro?: string; giro?: string | null
  contacto?: string | null; telefono?: string | null; email?: string | null; activo?: boolean
}

export async function actualizarProveedor(id: string, patch: ProveedorPatch) {
  const { data, error } = await supabase.rpc('rpc_proveedor_actualizar', {
    p_id: id,
    p_nombre: patch.nombre ?? null, p_rut: patch.rut ?? null, p_tipo: patch.tipo ?? null,
    p_rubro: patch.rubro ?? null, p_giro: patch.giro ?? null,
    p_contacto: patch.contacto ?? null, p_telefono: patch.telefono ?? null, p_email: patch.email ?? null,
    p_activo: patch.activo ?? null,
  })
  if (error) throw error
  return data as { success: boolean }
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
