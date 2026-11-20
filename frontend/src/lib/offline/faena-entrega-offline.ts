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
// [F4, MIG723 20-11-2026]
//   · Cada envío lleva su identificador (local_id): si la respuesta se perdió
//     con mala señal, el servidor reconoce el reintento y lo da por hecho.
//     Si la firmó OTRA persona, queda «no aceptada» diciendo quién y cuándo
//     (antes se daba por subida y la firma de este teléfono se perdía callada).
//   · La firma sube a una ruta fija por operación: reintentar no deja copias.
//   · ABRIR SIN SEÑAL una entrega nueva: con la plantilla que se bajó con señal
//     (precarga) se arma en el teléfono con un id propio. Al volver la señal se
//     crea en el servidor con ese id (o se usa la que otro ya abrió) y recién
//     ahí se declara y firma.
//   · Lo guardado se busca por periodo: sin señal nunca se muestra (ni se
//     firma) la entrega de otra semana.
// ============================================================================

import { haySesionServidor } from '@/lib/supabase'
import { esTransitorio, esDuplicado } from '@/lib/offline/bandeja'
import Dexie, { type Table } from 'dexie'
import {
  abrirEntrega, declararEntrega, firmarEntrega, getContextoEntrega, getPlantillaEntrega, recibirEntrega, subirFirma,
  type ContextoEntrega, type DeclaracionEntrega, type EntregaAbierta, type PlantillaEntrega,
} from '@/lib/services/faena-entrega'

type ParamsAbrir = Parameters<typeof abrirEntrega>[0]

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
  /** [MIG723] La entrega se abrió sin señal: hay que crearla antes de firmar. */
  abrir?: ParamsAbrir
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
const K = (p: Pick<ParamsAbrir, 'faenaId' | 'desde' | 'hasta' | 'turnoSaliente'>) =>
  `entrega:${p.faenaId}:${p.desde}:${p.hasta}:${p.turnoSaliente}`
const KP = (faenaId: string, desde: string, hasta: string) => `plantilla:${faenaId}:${desde}:${hasta}`

type Guardada = { entrega: EntregaAbierta; contexto: ContextoEntrega | null; abrir?: ParamsAbrir }

/** [F4] Con señal (precarga): baja la plantilla del periodo para poder abrir sin señal. */
export async function guardarPlantilla(faenaId: string, desde: string, hasta: string): Promise<void> {
  const pl = await conTimeout(getPlantillaEntrega(faenaId, desde, hasta), 20000)
  await db().cache.put({ key: KP(faenaId, desde, hasta), value: pl, updated_at: new Date().toISOString() })
}

/** La entrega armada en el teléfono a partir de la plantilla (todavía no existe en el servidor). */
export function entregaLocal(p: ParamsAbrir, id: string, pl: PlantillaEntrega): EntregaAbierta {
  return {
    entrega_id: id,
    entrega: {
      id, faena_id: p.faenaId, turno_saliente: p.turnoSaliente, turno_entrante: p.turnoEntrante,
      desde: p.desde, hasta: p.hasta, estado: 'abierta',
      stock_fisico_lt: null, stock_teorico_lt: null, ticket_verificacion: null,
      conteo_fisico_hecho: true, conteo_omitido_motivo: null, inventario_cerrado: true, inventario_observacion: null,
      observacion_entrega: null, observacion_recepcion: null, reparos: null,
      entrega_nombre: null, entrega_firma_url: null, entregado_at: null,
      recibe_nombre: null, recibe_firma_url: null, recibido_at: null,
    },
    resumen: pl.resumen, equipos: pl.equipos ?? [], pendientes: pl.pendientes ?? [],
  }
}

export async function abrirEntregaOffline(p: Parameters<typeof abrirEntrega>[0]):
  Promise<{ data: EntregaAbierta; contexto: ContextoEntrega | null; guardada_at: string; sin_senal: boolean; local?: boolean }> {
  if (isOnline()) {
    try {
      // [F4] Si se había abierto sin señal en este teléfono, se crea con ESE id:
      // lo firmado sin señal sigue apuntando a la misma entrega.
      const previa = (await db().cache.get(K(p)))?.value as Guardada | undefined
      const d = await conTimeout(abrirEntrega({ ...p, id: previa?.abrir?.id ?? p.id }), 15000)
      const contexto = await conTimeout(getContextoEntrega(d.entrega_id), 15000).catch(() => null)
      const ahora = new Date().toISOString()
      await db().cache.put({ key: K(p), value: { entrega: d, contexto } satisfies Guardada, updated_at: ahora })
      return { data: aplicarCola(d, await db().pending.toArray()), contexto, guardada_at: ahora, sin_senal: false }
    } catch (e) {
      if (esRechazo(e)) throw e
    }
  }
  const row = await db().cache.get(K(p))
  if (row) {
    const g = row.value as Guardada
    return { data: aplicarCola(g.entrega, await db().pending.toArray()), contexto: g.contexto, guardada_at: row.updated_at, sin_senal: true, local: !!g.abrir }
  }
  // [F4] Nunca abierta en este teléfono: se arma con la plantilla bajada con señal.
  const pl = await db().cache.get(KP(p.faenaId, p.desde, p.hasta))
  if (!pl) {
    throw new Error('Sin señal y este teléfono no tiene los datos de ese periodo. Abra la app con señal un momento '
      + '(se bajan solos) o abra la entrega una vez con señal antes del cambio de turno.')
  }
  const plantilla = pl.value as PlantillaEntrega
  const id = nuevoId()
  const abrir: ParamsAbrir = { faenaId: p.faenaId, desde: p.desde, hasta: p.hasta, turnoSaliente: p.turnoSaliente, turnoEntrante: p.turnoEntrante, id }
  const d = entregaLocal(p, id, plantilla)
  await db().cache.put({ key: K(p), value: { entrega: d, contexto: plantilla.contexto, abrir } satisfies Guardada, updated_at: pl.updated_at })
  return { data: d, contexto: plantilla.contexto, guardada_at: pl.updated_at, sin_senal: true, local: true }
}

/** [F4] Si la entrega se abrió sin señal, la operación lleva cómo crearla en el servidor. */
async function abrirPendiente(entregaId: string): Promise<ParamsAbrir | undefined> {
  const filas = await db().cache.where('key').startsWith('entrega:').toArray()
  const g = filas.map((f) => f.value as Guardada).find((x) => x.abrir && x.entrega.entrega_id === entregaId)
  return g?.abrir
}

/** [F4] Crea en el servidor la entrega abierta sin señal y deja todo apuntando al id real. */
async function crearEnServidor(o: OpEntrega): Promise<void> {
  const abrir = o.abrir
  if (!abrir) return
  const local = o.params.entregaId
  const d = await conTimeout(abrirEntrega(abrir), 20000)
  const real = d.entrega_id
  // Todas las operaciones de esa entrega pasan al id real (si otro la abrió antes, es otro id).
  const cola = await db().pending.toArray()
  for (const x of cola) {
    if (x.params.entregaId !== local) continue
    const params = { ...x.params, entregaId: real }
    const declaracion = x.declaracion ? { ...x.declaracion, entregaId: real } : x.declaracion
    await db().pending.update(x.local_id, { params, declaracion, abrir: undefined })
  }
  o.params = { ...o.params, entregaId: real }
  if (o.declaracion) o.declaracion = { ...o.declaracion, entregaId: real }
  o.abrir = undefined
  const contexto = await conTimeout(getContextoEntrega(real), 15000).catch(() => null)
  await db().cache.put({ key: K(abrir), value: { entrega: d, contexto } satisfies Guardada, updated_at: new Date().toISOString() })
}

/** Lo firmado sin señal se ve como firmado. */
function aplicarCola(d: EntregaAbierta, cola: OpEntrega[]): EntregaAbierta {
  const e0 = d.entrega
  const mismaEntrega = (o: OpEntrega) => o.params.entregaId === d.entrega_id
    // [F4] Firmada sin señal sobre la entrega armada en el teléfono: es la misma
    // si es del mismo periodo, aunque en el servidor haya quedado con otro id.
    || (!!o.abrir && o.abrir.faenaId === e0.faena_id && o.abrir.desde === e0.desde
        && o.abrir.hasta === e0.hasta && o.abrir.turnoSaliente === e0.turno_saliente)
  const mia = cola.filter((o) => o.sync_status === 'pending' && mismaEntrega(o))
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
  const abrir = await abrirPendiente(params.entregaId)
  const op: OpEntrega = { local_id: nuevoId(), tipo, created_at: new Date().toISOString(), sync_status: 'pending', intentos: 0, firma, params, declaracion, abrir }
  await db().pending.put(op)
  if (!isOnline()) return { enviado: false }
  return subirUna(op)
}

async function subirUna(o: OpEntrega): Promise<{ enviado: boolean; rechazo?: string; resultado?: unknown }> {
  try {
    // [F4] Abierta sin señal: primero se crea en el servidor.
    if (o.abrir) await crearEnServidor(o)
    // La declaración va primero: el servidor no deja firmar sin ella (MIG697).
    if (o.tipo === 'firmar' && o.declaracion) await conTimeout(declararEntrega(o.declaracion, o.local_id), 20000)
    const firmaUrl = await conTimeout(subirFirma(o.firma, `${o.local_id}-${o.tipo}`), 30000)
    // [MIG723] Con el identificador, el reintento del mismo teléfono vuelve como
    // éxito («ya_registrada»); si firmó otra persona, vuelve como rechazo.
    const resultado = o.tipo === 'firmar'
      ? await conTimeout(firmarEntrega({ ...(o.params as ParamsFirmar), firmaUrl, clientUuid: o.local_id }), 20000)
      : await conTimeout(recibirEntrega({ ...(o.params as ParamsRecibir), firmaUrl, clientUuid: o.local_id }), 20000)
    await db().pending.delete(o.local_id)
    return { enviado: true, resultado }
  } catch (e) {
    if (esDuplicado(e)) { await db().pending.delete(o.local_id); return { enviado: true } }
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
