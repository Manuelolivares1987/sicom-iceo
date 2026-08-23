// ============================================================================
// El cierre del turno se llena sin señal (MIG317)
// ----------------------------------------------------------------------------
// En Romeral la señal es mala y el recorrido de varillaje pasa por cuatro
// estaciones y tres camiones. Quien mide no puede quedarse esperando una barra
// de conexión con la varilla en la mano.
//
// Regla de la casa: cada número se guarda en el teléfono en el instante en que
// se escribe. La subida es un evento aparte y reintentable. Nunca se pierde
// una medición porque se cortó la red, se apagó la pantalla o se cerró la app.
//
// Base propia (no la del despacho) para no versionar el Dexie que ya usa la
// pantalla de terreno en producción.
// ============================================================================

import Dexie, { type Table } from 'dexie'
import {
  getPuntosMedicion, getCierreAnterior, guardarCierre, subirFotoMedicion,
  getPendientesAbiertos, getResumenDelDia, registrarRecepcion,
  type PuntoMedicion, type LecturaPunto, type LecturaMedidor, type CierreInput,
  type Pendiente, type ResumenDelDia,
} from '@/lib/services/combustible-cierre'
import { compressImage } from '@/lib/image/compress'

/** El turno completo tal como está en el teléfono. */
export type BorradorCierre = {
  clave: string                 // faenaId|fecha|turno
  faena_id: string
  fecha: string
  turno: string
  medido_por: string
  puntos: Record<string, LecturaPunto>
  medidores: Record<string, LecturaMedidor>
  observacion: string
  client_uuid: string
  actualizado_at: string
  sync_status: 'local' | 'subido' | 'error'
  ultimo_error?: string | null
  // El turno se cierra en el teléfono aunque no haya señal. Queda marcado
  // para firmar, y sube cuando vuelve la conexión — no cuando alguien se
  // acuerde de entrar a la pantalla.
  firma_pendiente?: boolean
  verificacion?: { despachos: number; litros: number } | null
  pendientes?: { pendiente_id: string; respuesta: string; comentario?: string | null }[] | null
  firmado_local_at?: string | null
}

type CacheRow = { key: string; value: unknown; updated_at: string }
type BlobRow = { blob_id: string; blob: Blob; mime: string }

class CierreDB extends Dexie {
  cache!: Table<CacheRow, string>
  borradores!: Table<BorradorCierre, string>
  blobs!: Table<BlobRow, string>
  constructor() {
    super('sicom-combustible-cierre')
    this.version(1).stores({
      cache: 'key, updated_at',
      borradores: 'clave, sync_status, actualizado_at',
    })
    // v2: la foto de cada medición espera en el teléfono hasta que haya señal.
    // Se saca junto con el número, no después: si se deja para la oficina deja
    // de ser la foto de esa medición.
    this.version(2).stores({
      cache: 'key, updated_at',
      borradores: 'clave, sync_status, actualizado_at',
      blobs: 'blob_id',
    })
  }
}

let _db: CierreDB | null = null
function db(): CierreDB {
  if (!_db) _db = new CierreDB()
  return _db
}

const uuid = () =>
  typeof crypto !== 'undefined' && 'randomUUID' in crypto
    ? crypto.randomUUID()
    : `${Date.now()}-${Math.random().toString(36).slice(2)}`

export const claveCierre = (faenaId: string, fecha: string, turno: string) =>
  `${faenaId}|${fecha}|${turno}`

/**
 * Guarda una foto en el teléfono y devuelve una referencia local.
 * Se marca con el prefijo `local:` para que el resto del código sepa que
 * todavía no es una URL: al subir el turno se cambia por la definitiva.
 */
export async function guardarFotoLocal(file: File | Blob): Promise<string> {
  // La foto se comprime ANTES de guardarla en el teléfono, no antes de
  // subirla. La diferencia importa: un turno completo sin señal son unas cien
  // fotos, y a 4 MB cada una son 400 MB en el IndexedDB del aparato. El
  // navegador desaloja o tira QuotaExceededError, y el operador pierde el día
  // entero sin enterarse. A 1600 px y calidad 0,75 la misma foto pesa unos
  // 250 kB: el día completo cabe en 25 MB y sube por señal de faena.
  //
  // compressImage falla seguro: si el aparato no puede procesar la imagen,
  // devuelve el original. Perder calidad es aceptable; perder la foto no.
  const blob = await compressImage(file, { maxDim: 1600, quality: 0.75 })
  const blob_id = uuid()
  await db().blobs.put({ blob_id, blob, mime: 'image/jpeg' })
  return `local:${blob_id}`
}

export async function getFotoLocal(ref: string): Promise<Blob | null> {
  if (!ref?.startsWith('local:')) return null
  const row = await db().blobs.get(ref.slice(6))
  return row?.blob ?? null
}

export const esFotoLocal = (ref?: string | null) => !!ref?.startsWith('local:')

// ── Catálogo ────────────────────────────────────────────────────────────────
const K_PUNTOS = 'puntos-medicion'
const K_ANTERIOR = 'medicion-anterior'

// Lo que quedó pendiente y el resumen del turno se bajan CON el catálogo. Si
// se piden sólo cuando hay señal, en Romeral no se ven nunca — y un pendiente
// que no se ve es exactamente el problema que se quería resolver.
const K_PENDIENTES = 'pendientes-abiertos'
const K_RESUMEN = 'resumen-del-dia'

export async function descargarPendientes(faenaId: string) {
  const p = await getPendientesAbiertos(faenaId)
  await db().cache.put({ key: K_PENDIENTES, value: p, updated_at: new Date().toISOString() })
  return p
}

export async function getPendientesOffline(): Promise<Pendiente[]> {
  const r = await db().cache.get(K_PENDIENTES)
  return (r?.value as Pendiente[]) ?? []
}

export async function descargarResumenDia(faenaId: string, fecha: string, turno?: string) {
  const r = await getResumenDelDia(faenaId, fecha, turno)
  await db().cache.put({ key: K_RESUMEN + '|' + fecha + '|' + (turno || 'Día'), value: r,
                         updated_at: new Date().toISOString() })
  return r
}

export async function getResumenDiaOffline(fecha: string, turno?: string): Promise<ResumenDelDia | null> {
  const r = await db().cache.get(K_RESUMEN + '|' + fecha + '|' + (turno || 'Día'))
  return (r?.value as ResumenDelDia) ?? null
}

export async function descargarCatalogoCierre(faenaId: string) {
  const puntos = await getPuntosMedicion(faenaId)
  await db().cache.put({ key: K_PUNTOS, value: puntos, updated_at: new Date().toISOString() })
  return puntos
}

export async function getPuntosOffline(): Promise<PuntoMedicion[] | null> {
  const row = await db().cache.get(K_PUNTOS)
  return (row?.value as PuntoMedicion[]) ?? null
}

/**
 * La medición final del TURNO anterior, para proponer la inicial de este sin
 * que nadie la busque. Se guarda por turno: el de día y el de noche arrancan de
 * números distintos, y guardarlos bajo la misma llave haría que el segundo
 * partiera con el número del primero.
 */
export async function descargarMedicionAnterior(faenaId: string, fecha: string, turno?: string) {
  const mapa = await getCierreAnterior(faenaId, fecha, turno)
  const plano = Object.fromEntries(mapa)
  await db().cache.put({ key: K_ANTERIOR + '|' + (turno || 'Día'), value: plano,
                         updated_at: new Date().toISOString() })
  return plano as Record<string, number>
}

export async function getMedicionAnteriorOffline(turno?: string): Promise<Record<string, number>> {
  const row = await db().cache.get(K_ANTERIOR + '|' + (turno || 'Día'))
  return (row?.value as Record<string, number>) ?? {}
}

export async function ultimaDescargaCierre(): Promise<string | null> {
  const row = await db().cache.get(K_PUNTOS)
  return row?.updated_at ?? null
}

// ── Borrador del turno ──────────────────────────────────────────────────────
export async function getBorrador(faenaId: string, fecha: string, turno: string) {
  return db().borradores.get(claveCierre(faenaId, fecha, turno))
}

export async function crearBorrador(
  faenaId: string, fecha: string, turno: string, medidoPor: string,
): Promise<BorradorCierre> {
  const clave = claveCierre(faenaId, fecha, turno)
  const existente = await db().borradores.get(clave)
  if (existente) return existente
  const b: BorradorCierre = {
    clave, faena_id: faenaId, fecha, turno, medido_por: medidoPor,
    puntos: {}, medidores: {}, observacion: '',
    client_uuid: uuid(), actualizado_at: new Date().toISOString(), sync_status: 'local',
  }
  await db().borradores.put(b)
  return b
}

/** Guarda en el acto. Se llama en cada cambio de campo, a propósito. */
export async function guardarBorrador(b: BorradorCierre) {
  b.actualizado_at = new Date().toISOString()
  if (b.sync_status === 'subido') b.sync_status = 'local'
  await db().borradores.put(b)
  return b
}

/**
 * Sube las fotos que todavía están en el teléfono y reemplaza la referencia
 * local por la URL definitiva. Si una falla, se deja como está y se reintenta
 * en el próximo envío: nunca se pierde ni se borra la foto local.
 */
async function subirFotosPendientes(b: BorradorCierre) {
  for (const p of Object.values(b.puntos)) {
    if (!esFotoLocal(p.foto_url)) continue
    const blob = await getFotoLocal(p.foto_url!)
    if (!blob) continue
    try { p.foto_url = await subirFotoMedicion(blob) } catch { /* se reintenta */ }
  }
  for (const m of Object.values(b.medidores)) {
    if (!esFotoLocal(m.foto_url)) continue
    const blob = await getFotoLocal(m.foto_url!)
    if (!blob) continue
    try { m.foto_url = await subirFotoMedicion(blob) } catch { /* se reintenta */ }
  }
  await db().borradores.put(b)
}

export async function subirBorrador(
  b: BorradorCierre,
  firmar: boolean,
  verificacion?: { despachos: number; litros: number } | null,
  pendientes?: { pendiente_id: string; respuesta: string; comentario?: string | null }[] | null,
) {
  await subirFotosPendientes(b)
  const input: CierreInput = {
    faenaId: b.faena_id,
    fecha: b.fecha,
    turno: b.turno || null,
    medidoPor: b.medido_por || null,
    puntos: Object.values(b.puntos),
    medidores: Object.values(b.medidores),
    observacion: b.observacion || null,
    firmar,
    clientUuid: b.client_uuid,
    verificacion: firmar ? (verificacion ?? null) : null,
    pendientes: firmar ? (pendientes ?? null) : null,
    sinSenal: b.firma_pendiente === true,
  }
  try {
    const r = await guardarCierre(input)
    b.sync_status = 'subido'
    b.firma_pendiente = false
    b.ultimo_error = null
    await db().borradores.put(b)
    return r
  } catch (e) {
    b.sync_status = 'error'
    b.ultimo_error = e instanceof Error ? e.message : String(e)
    await db().borradores.put(b)
    throw e
  }
}

/** Turnos guardados en el teléfono que todavía no subieron. */

/**
 * Cerrar el turno sin señal.
 *
 * En Romeral la señal falta más de lo que sobra. Si firmar exigiera conexión,
 * a las 18:00 —con el estanque medido y las fotos sacadas— el supervisor no
 * podría cerrar el día, y lo que pasa cuando eso ocurre es que se vuelve al
 * papel.
 *
 * Acá el turno se cierra en el teléfono y queda marcado para firmar. Sube solo
 * cuando vuelve la señal, sin que nadie tenga que acordarse de entrar.
 */
export async function firmarEnElTelefono(
  b: BorradorCierre,
  verificacion?: { despachos: number; litros: number } | null,
  pendientes?: { pendiente_id: string; respuesta: string; comentario?: string | null }[] | null,
) {
  b.firma_pendiente = true
  b.verificacion = verificacion ?? null
  b.pendientes = pendientes ?? null
  b.firmado_local_at = new Date().toISOString()
  b.sync_status = 'local'
  await db().borradores.put(b)
  return b
}

/**
 * Sube todo lo que esté esperando en el teléfono.
 *
 * Se llama sola al recuperar la señal. Antes esto no existía: `borradoresPendientes`
 * estaba escrito y no lo llamaba nadie, así que un cierre hecho sin conexión se
 * quedaba en el aparato hasta que alguien volviera a abrir la pantalla.
 */
export async function sincronizarPendientes(): Promise<{
  subidos: number; firmados: number; errores: string[]
}> {
  const cola = await borradoresPendientes()
  let subidos = 0
  let firmados = 0
  const errores: string[] = []

  for (const b of cola) {
    try {
      await subirBorrador(b, b.firma_pendiente === true, b.verificacion, b.pendientes)
      subidos++
      if (b.firma_pendiente) firmados++
    } catch (e) {
      errores.push(`${b.fecha} ${b.turno}: ${e instanceof Error ? e.message : 'error'}`)
    }
  }
  return { subidos, firmados, errores }
}

export async function borradoresPendientes(): Promise<BorradorCierre[]> {
  return db().borradores.where('sync_status').anyOf('local', 'error').toArray()
}

export async function borrarBorrador(clave: string) {
  await db().borradores.delete(clave)
}

// ── La recepción del camión, sin señal ──────────────────────────────────────
//
// El camión de flota primaria llega a las 06:30, y en Romeral a esa hora
// muchas veces no hay señal. Un camión de 30.000 litros que no se registra es
// la diferencia más cara que puede aparecer en el cierre, así que esto no
// podía seguir dependiendo de la conexión.
//
// La foto de la guía se guarda en el teléfono igual que las del cierre, y sube
// junto con la recepción cuando vuelve la señal.

export type RecepcionPendiente = {
  client_uuid: string
  faena_id: string
  fecha: string
  destinos: { estanque_id: string; litros: number }[]
  guia: string | null
  viaje: string | null
  camion: string | null
  litros_guia: number | null
  recibido_por: string | null
  sello: string | null
  observacion: string | null
  foto_ref: string | null        // 'local:<id>' mientras espera
  sin_foto_motivo: string | null
  confirmar: boolean
  creado_at: string
  intento_error?: string | null
}

const K_RECEPCIONES = 'recepciones-pendientes'

async function colaRecepciones(): Promise<RecepcionPendiente[]> {
  const r = await db().cache.get(K_RECEPCIONES)
  return (r?.value as RecepcionPendiente[]) ?? []
}

async function guardarCola(lista: RecepcionPendiente[]) {
  await db().cache.put({ key: K_RECEPCIONES, value: lista,
                         updated_at: new Date().toISOString() })
}

export async function encolarRecepcion(r: RecepcionPendiente) {
  const lista = await colaRecepciones()
  await guardarCola([...lista.filter((x) => x.client_uuid !== r.client_uuid), r])
  return r
}

export async function recepcionesPendientes() {
  return colaRecepciones()
}

/** Sube las recepciones que estén esperando. El RPC es idempotente por
 *  client_uuid, así que reintentar no duplica. */
export async function sincronizarRecepciones(): Promise<{ subidas: number; errores: string[] }> {
  const lista = await colaRecepciones()
  if (!lista.length) return { subidas: 0, errores: [] }

  const quedan: RecepcionPendiente[] = []
  const errores: string[] = []
  let subidas = 0

  for (const r of lista) {
    try {
      let url: string | null = null
      if (r.foto_ref?.startsWith('local:')) {
        const b = await getFotoLocal(r.foto_ref)
        if (b) url = await subirFotoMedicion(b)
      } else {
        url = r.foto_ref
      }
      await registrarRecepcion({
        faenaId: r.faena_id, fecha: r.fecha, destinos: r.destinos,
        guia: r.guia, viaje: r.viaje, camion: r.camion,
        litrosGuia: r.litros_guia, recibidoPor: r.recibido_por, sello: r.sello,
        observacion: r.observacion, fotoGuia: url, sinFotoMotivo: r.sin_foto_motivo,
        confirmar: r.confirmar, clientUuid: r.client_uuid, sinSenal: true,
      })
      subidas++
    } catch (e) {
      errores.push(`${r.guia ?? r.camion ?? r.fecha}: ${e instanceof Error ? e.message : 'error'}`)
      quedan.push({ ...r, intento_error: e instanceof Error ? e.message : 'error' })
    }
  }
  await guardarCola(quedan)
  return { subidas, errores }
}
