// ============================================================================
// Bodega de faena sin señal (MIG694) — mismo patrón que la pauta de Franke
// ----------------------------------------------------------------------------
// El teléfono guarda el catálogo completo (todo el maestro + el stock de la
// bodega + los equipos). Con eso el lector funciona igual con o sin señal: la
// búsqueda es local e instantánea. Cada salida/recepción/conteo se guarda en
// una cola con su client_uuid; al volver la señal sube sola (el sincronizador
// vive en el layout de Franke). El servidor es idempotente por client_uuid:
// reintentar nunca descuenta dos veces.
//
// Si el servidor RECHAZA una operación (ej. al subir ya no alcanzaba el stock),
// no se reintenta para siempre: queda «rechazada» con el motivo, a la vista, y
// la persona decide descartarla.
// ============================================================================

import Dexie, { type Table } from 'dexie'
import { supabase } from '@/lib/supabase'
import {
  BODEGA_FRANKE, registrarConteo, registrarIngreso, registrarSalida, type ItemLector, type ProductoLector,
} from '@/lib/services/bodega-faena'

export type TipoOperacion = 'salida' | 'ingreso' | 'conteo'

export type OperacionPendiente = {
  local_id: string            // = client_uuid que va al servidor
  tipo: TipoOperacion
  bodega_id: string
  created_at: string
  sync_status: 'pending' | 'rechazada'
  intentos: number
  ultimo_error?: string | null
  items: (ItemLector & { nombre: string })[]
  activo_id?: string | null
  motivo?: string
  entregado_a?: string
  origen?: string
  documento?: string
  completo?: boolean
}

export type Catalogo = {
  bodega_id: string
  generado_at: string
  puede_operar: boolean
  productos: ProductoLector[]
  equipos: { id: string; patente: string; tipo: string }[]
}

type CacheRow = { key: string; value: unknown; updated_at: string }

class BodegaDB extends Dexie {
  cache!: Table<CacheRow, string>
  pending!: Table<OperacionPendiente, string>
  constructor() {
    super('sicom-bodega-faena')
    this.version(1).stores({ cache: 'key, updated_at', pending: 'local_id, sync_status, created_at' })
  }
}
let _db: BodegaDB | null = null
export function bodegaDB(): BodegaDB {
  if (typeof window === 'undefined') throw new Error('bodegaDB() solo en cliente')
  if (!_db) _db = new BodegaDB()
  return _db
}

const isOnline = () => (typeof navigator === 'undefined' ? true : navigator.onLine)
function conTimeout<T>(p: PromiseLike<T>, ms = 10000): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const t = setTimeout(() => reject(new Error('timeout de red')), ms)
    Promise.resolve(p).then((v) => { clearTimeout(t); resolve(v) }, (e) => { clearTimeout(t); reject(e) })
  })
}
/** Error del servidor con código = regla de negocio (no se arregla reintentando). */
const esRechazo = (e: unknown) => !!e && typeof e === 'object' && 'code' in e && typeof (e as { code: unknown }).code === 'string'
  && (e as { code: string }).code !== '' && !String((e as { message?: string }).message ?? '').toLowerCase().includes('fetch')
const mensaje = (e: unknown) => (e instanceof Error ? e.message : typeof e === 'object' && e && 'message' in e ? String((e as { message: unknown }).message) : String(e))

const K_CAT = (codigoBodega: string) => `catalogo:${codigoBodega}`

type FilaCat = [string, string, string | null, string, string | null, string | null, number, number | null]

async function bajarCatalogo(codigoBodega: string): Promise<Catalogo> {
  const { data: b, error: eb } = await supabase.from('bodegas').select('id').eq('codigo', codigoBodega).single()
  if (eb) throw eb
  const { data, error } = await supabase.rpc('rpc_bodega_faena_catalogo', { p_bodega_id: b.id })
  if (error) throw error
  const d = data as { generado_at: string; puede_operar: boolean; productos: FilaCat[]; equipos: Catalogo['equipos'] }
  return {
    bodega_id: b.id, generado_at: d.generado_at, puede_operar: d.puede_operar, equipos: d.equipos,
    productos: d.productos.map(([id, codigo, barras, nombre, categoria, unidad, stock, minimo]) => ({
      producto_id: id, codigo, codigo_barras: barras, nombre, categoria, unidad, stock: Number(stock ?? 0),
      minimo: minimo == null ? null : Number(minimo), maximo: null,
      exige_equipo: ['repuesto', 'filtro', 'lubricante'].includes(categoria ?? ''), exacto: false,
    })),
  }
}

/** Con señal refresca el catálogo y lo guarda; sin señal, el último guardado. */
export async function getCatalogo(codigoBodega = BODEGA_FRANKE, forzar = false): Promise<Catalogo | null> {
  const row = await bodegaDB().cache.get(K_CAT(codigoBodega))
  const guardado = (row?.value as Catalogo) ?? null
  const reciente = row && Date.now() - new Date(row.updated_at).getTime() < 60_000
  if (isOnline() && (forzar || !reciente)) {
    try {
      const c = await conTimeout(bajarCatalogo(codigoBodega), 20000)
      await bodegaDB().cache.put({ key: K_CAT(codigoBodega), value: c, updated_at: new Date().toISOString() })
      return c
    } catch { /* sin datos reales: se usa lo guardado */ }
  }
  return guardado
}

export async function ultimaDescargaCatalogo(codigoBodega = BODEGA_FRANKE): Promise<string | null> {
  return (await bodegaDB().cache.get(K_CAT(codigoBodega)))?.updated_at ?? null
}

/** Búsqueda local: primero código exacto (lo que teclea el lector), luego nombre. */
export function buscarEnCatalogo(cat: Catalogo, texto: string): ProductoLector[] {
  const t = texto.trim().toUpperCase()
  if (t.length < 2) return []
  const exactos = cat.productos.filter((p) => p.codigo.toUpperCase() === t || (p.codigo_barras ?? '').toUpperCase() === t)
  if (exactos.length) return exactos.map((p) => ({ ...p, exacto: true }))
  if (t.length < 3) return []
  return cat.productos
    .filter((p) => p.nombre.toUpperCase().includes(t) || p.codigo.toUpperCase().startsWith(t))
    .sort((a, b) => Number(b.stock > 0) - Number(a.stock > 0) || a.nombre.localeCompare(b.nombre))
    .slice(0, 25)
}

/** Stock que se muestra: el del catálogo ± lo que está en la cola sin subir. */
export function ajustePendiente(pend: OperacionPendiente[]): Map<string, number> {
  const m = new Map<string, number>()
  for (const p of pend) {
    if (p.sync_status !== 'pending' || p.tipo === 'conteo') continue
    for (const i of p.items) m.set(i.producto_id, (m.get(i.producto_id) ?? 0) + (p.tipo === 'salida' ? -i.cantidad : i.cantidad))
  }
  return m
}

export async function guardarOperacion(op: Omit<OperacionPendiente, 'created_at' | 'sync_status' | 'intentos'>):
  Promise<{ enviado: boolean; rechazo?: string; resultado?: unknown }> {
  const pend: OperacionPendiente = { ...op, created_at: new Date().toISOString(), sync_status: 'pending', intentos: 0 }
  await bodegaDB().pending.put(pend)
  if (!isOnline()) return { enviado: false }
  const r = await subirUna(pend)
  return r
}

async function subirUna(p: OperacionPendiente): Promise<{ enviado: boolean; rechazo?: string; resultado?: unknown }> {
  const items = p.items.map(({ producto_id, cantidad }) => ({ producto_id, cantidad }))
  try {
    let resultado: unknown
    if (p.tipo === 'salida') {
      resultado = await conTimeout(registrarSalida({ bodegaId: p.bodega_id, items, activoId: p.activo_id ?? null,
        motivo: p.motivo ?? '', entregadoA: p.entregado_a ?? '', clientUuid: p.local_id }), 20000)
    } else if (p.tipo === 'ingreso') {
      resultado = await conTimeout(registrarIngreso({ bodegaId: p.bodega_id, items, origen: p.origen ?? '',
        documento: p.documento ?? '', clientUuid: p.local_id }), 20000)
    } else {
      resultado = await conTimeout(registrarConteo({ bodegaId: p.bodega_id, items, completo: !!p.completo,
        observacion: p.motivo ?? '', clientUuid: p.local_id }), 20000)
    }
    await bodegaDB().pending.delete(p.local_id)
    return { enviado: true, resultado }
  } catch (e) {
    if (esRechazo(e)) {
      await bodegaDB().pending.update(p.local_id, { sync_status: 'rechazada', intentos: p.intentos + 1, ultimo_error: mensaje(e) })
      return { enviado: false, rechazo: mensaje(e) }
    }
    await bodegaDB().pending.update(p.local_id, { intentos: p.intentos + 1, ultimo_error: mensaje(e) })
    return { enviado: false }
  }
}

export async function pendientesCount(): Promise<number> {
  return bodegaDB().pending.where('sync_status').equals('pending').count()
}
export async function pendientesBodega(): Promise<OperacionPendiente[]> {
  return bodegaDB().pending.orderBy('created_at').toArray()
}
export async function descartarOperacion(localId: string) {
  await bodegaDB().pending.delete(localId)
}

/** Sube la cola en orden. Las rechazadas no se reintentan solas. */
export async function sincronizar(): Promise<{ ok: number; error: number; rechazadas: number }> {
  if (!isOnline()) return { ok: 0, error: 0, rechazadas: 0 }
  const cola = await bodegaDB().pending.where('sync_status').equals('pending').sortBy('created_at')
  let ok = 0, error = 0, rechazadas = 0
  for (const p of cola) {
    const r = await subirUna(p)
    if (r.enviado) ok += 1
    else if (r.rechazo) rechazadas += 1
    else { error += 1; break }   // sin red real: no tiene sentido seguir intentando el resto
  }
  if (ok > 0) await getCatalogo(BODEGA_FRANKE, true).catch(() => null)
  return { ok, error, rechazadas }
}
