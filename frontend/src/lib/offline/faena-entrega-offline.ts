// ============================================================================
// Entrega de turno sin señal (MIG696) — Franke
// ----------------------------------------------------------------------------
// La entrega de MIG362 exigía señal en los tres pasos y se usó una sola vez.
// Ahora:
//   · ABRIR: con señal se abre y queda guardada en el teléfono. Sin señal se
//     usa la última abierta (por eso conviene abrirla el día antes, con señal).
//   · FIRMAR la entrega y FIRMAR la recepción: la firma y las respuestas se
//     guardan en el teléfono y suben solas al volver la señal (sincronizador
//     del layout). Las RPCs del servidor son las de siempre.
// ============================================================================

import { haySesionServidor } from '@/lib/supabase'
import { esTransitorio, esDuplicado } from '@/lib/offline/bandeja'
import Dexie, { type Table } from 'dexie'
import {
  abrirEntrega, declararEntrega, firmarEntrega, getContextoEntrega, recibirEntrega, subirFirma,
  type ContextoEntrega, type DeclaracionEntrega, type EntregaAbierta,
} from '@/lib/services/faena-entrega'

type ParamsFirmar = Omit<Parameters<typeof firmarEntrega>[0], 'firmaUrl'>
type ParamsRecibir = Omit<Parameters<typeof recibirEntrega>[0], 'firmaUrl'>
export type OpEntrega = {
  local_id: string
  tipo: 'firmar' | 'recibir'
  created_at: string
  sync_status: 'pending' | 'rechazada'
  intentos: number
  ultimo_error?: string | null
  firma: Blob
  params: ParamsFirmar | ParamsRecibir
  /** [MIG697] Litros por camión, terceros y seguridad: se declaran antes de firmar. */
  declaracion?: DeclaracionEntrega
}
type CacheRow = { key: string; value: unknown; updated_at: string }

class EntregaDB extends Dexie {
  cache!: Table<CacheRow, string>
  pending!: Table<OpEntrega, string>
  constructor() {
    super('sicom-faena-entrega')
    this.version(1).stores({ cache: 'key, updated_at', pending: 'local_id, sync_status, created_at' })
  }
}
let _db: EntregaDB | null = null
const db = () => { if (!_db) _db = new EntregaDB(); return _db }
const isOnline = () => (typeof navigator === 'undefined' ? true : navigator.onLine)
const nuevoId = () => (typeof crypto !== 'undefined' && 'randomUUID' in crypto ? crypto.randomUUID() : `${Date.now()}-${Math.random().toString(36).slice(2)}`)
function conTimeout<T>(p: PromiseLike<T>, ms = 12000): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const t = setTimeout(() => reject(new Error('timeout de red')), ms)
    Promise.resolve(p).then((v) => { clearTimeout(t); resolve(v) }, (e) => { clearTimeout(t); reject(e) })
  })
}
// [F3, 20-11-2026] Un error de señal o de sesión (42501 «No autorizado», JWT
// vencido, red) NO es un rechazo: antes quedaba «rechazada» para siempre.
const esRechazo = (e: unknown) => !esTransitorio(e) && !esDuplicado(e) && !!e && typeof e === 'object' && 'code' in e
  && typeof (e as { code: unknown }).code === 'string' && (e as { code: string }).code !== ''
const mensaje = (e: unknown) => (e instanceof Error ? e.message : typeof e === 'object' && e && 'message' in e ? String((e as { message: unknown }).message) : String(e))
const K = (faenaId: string) => `entrega:${faenaId}`

type Guardada = { entrega: EntregaAbierta; contexto: ContextoEntrega | null }

export async function abrirEntregaOffline(p: Parameters<typeof abrirEntrega>[0]):
  Promise<{ data: EntregaAbierta; contexto: ContextoEntrega | null; guardada_at: string; sin_senal: boolean }> {
  if (isOnline()) {
    try {
      const d = await conTimeout(abrirEntrega(p), 15000)
      const contexto = await conTimeout(getContextoEntrega(d.entrega_id), 15000).catch(() => null)
      const ahora = new Date().toISOString()
      await db().cache.put({ key: K(p.faenaId), value: { entrega: d, contexto } satisfies Guardada, updated_at: ahora })
      return { data: aplicarCola(d, await db().pending.toArray()), contexto, guardada_at: ahora, sin_senal: false }
    } catch (e) {
      if (esRechazo(e)) throw e
    }
  }
  const row = await db().cache.get(K(p.faenaId))
  if (!row) throw new Error('Sin señal y sin entrega guardada en este teléfono. Ábrala una vez con señal (ideal: el martes, antes del cambio del miércoles).')
  const g = row.value as Guardada
  return { data: aplicarCola(g.entrega, await db().pending.toArray()), contexto: g.contexto, guardada_at: row.updated_at, sin_senal: true }
}

/** Lo firmado sin señal se ve como firmado. */
function aplicarCola(d: EntregaAbierta, cola: OpEntrega[]): EntregaAbierta {
  const mia = cola.filter((o) => o.sync_status === 'pending' && o.params.entregaId === d.entrega_id)
  if (!mia.length) return d
  const e = { ...d.entrega }
  for (const o of mia) {
    if (o.tipo === 'firmar' && e.estado === 'abierta') { e.estado = 'entregada'; e.entrega_nombre = o.params.nombre; e.entregado_at = o.created_at }
    if (o.tipo === 'recibir') { e.estado = 'recibida'; e.recibe_nombre = o.params.nombre; e.recibido_at = o.created_at }
  }
  return { ...d, entrega: e }
}

export async function firmarOffline(params: ParamsFirmar, firma: Blob, declaracion: DeclaracionEntrega) {
  return encolar('firmar', params, firma, declaracion)
}
export async function recibirOffline(params: ParamsRecibir, firma: Blob) {
  return encolar('recibir', params, firma)
}

async function encolar(tipo: OpEntrega['tipo'], params: OpEntrega['params'], firma: Blob, declaracion?: DeclaracionEntrega):
  Promise<{ enviado: boolean; rechazo?: string; resultado?: unknown }> {
  const op: OpEntrega = { local_id: nuevoId(), tipo, created_at: new Date().toISOString(), sync_status: 'pending', intentos: 0, firma, params, declaracion }
  await db().pending.put(op)
  if (!isOnline()) return { enviado: false }
  return subirUna(op)
}

async function subirUna(o: OpEntrega): Promise<{ enviado: boolean; rechazo?: string; resultado?: unknown }> {
  try {
    // La declaración va primero: el servidor no deja firmar sin ella (MIG697).
    if (o.tipo === 'firmar' && o.declaracion) await conTimeout(declararEntrega(o.declaracion), 20000)
    const firmaUrl = await conTimeout(subirFirma(o.firma), 30000)
    const resultado = o.tipo === 'firmar'
      ? await conTimeout(firmarEntrega({ ...(o.params as ParamsFirmar), firmaUrl }), 20000)
      : await conTimeout(recibirEntrega({ ...(o.params as ParamsRecibir), firmaUrl }), 20000)
    await db().pending.delete(o.local_id)
    return { enviado: true, resultado }
  } catch (e) {
    // [F3] La firma/recepción ya había llegado (se perdió la respuesta con mala
    // señal): el servidor responde «ya está firmada/recibida». Eso es éxito.
    const m = mensaje(e)
    const yaHecho = o.tipo === 'firmar'
      ? /ya fue firmada|ya está (entregada|recibida)/i.test(m)
      : /(que está|ya está) recibida/i.test(m)
    if (yaHecho || esDuplicado(e)) { await db().pending.delete(o.local_id); return { enviado: true } }
    if (esRechazo(e)) {
      await db().pending.update(o.local_id, { sync_status: 'rechazada', intentos: o.intentos + 1, ultimo_error: mensaje(e) })
      return { enviado: false, rechazo: mensaje(e) }
    }
    await db().pending.update(o.local_id, { intentos: o.intentos + 1, ultimo_error: mensaje(e) })
    return { enviado: false }
  }
}

export async function colaEntrega(): Promise<OpEntrega[]> { return db().pending.orderBy('created_at').toArray() }
export async function pendientesCount(): Promise<number> { return db().pending.where('sync_status').equals('pending').count() }
export async function descartarEntrega(localId: string) { await db().pending.delete(localId) }

export async function sincronizar(): Promise<{ ok: number; error: number; rechazadas: number }> {
  // [20-11-2026] Sin sesión válida no se sube: el servidor lo rechazaría como anónimo.
  if (!haySesionServidor()) return { ok: 0, error: 0, rechazadas: 0 }
  if (!isOnline()) return { ok: 0, error: 0, rechazadas: 0 }
  const cola = await db().pending.where('sync_status').equals('pending').sortBy('created_at')
  let ok = 0, error = 0, rechazadas = 0
  for (const o of cola) {
    const r = await subirUna(o)
    if (r.enviado) ok += 1
    else if (r.rechazo) rechazadas += 1
    else { error += 1; break }
  }
  return { ok, error, rechazadas }
}
