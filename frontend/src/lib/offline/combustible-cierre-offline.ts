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
  type PuntoMedicion, type LecturaPunto, type LecturaMedidor, type CierreInput,
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

export async function descargarCatalogoCierre(faenaId: string) {
  const puntos = await getPuntosMedicion(faenaId)
  await db().cache.put({ key: K_PUNTOS, value: puntos, updated_at: new Date().toISOString() })
  return puntos
}

export async function getPuntosOffline(): Promise<PuntoMedicion[] | null> {
  const row = await db().cache.get(K_PUNTOS)
  return (row?.value as PuntoMedicion[]) ?? null
}

/** La medición final de ayer, para proponer la inicial de hoy sin que nadie la busque. */
export async function descargarMedicionAnterior(faenaId: string, fecha: string) {
  const mapa = await getCierreAnterior(faenaId, fecha)
  const plano = Object.fromEntries(mapa)
  await db().cache.put({ key: K_ANTERIOR, value: plano, updated_at: new Date().toISOString() })
  return plano as Record<string, number>
}

export async function getMedicionAnteriorOffline(): Promise<Record<string, number>> {
  const row = await db().cache.get(K_ANTERIOR)
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

export async function subirBorrador(b: BorradorCierre, firmar: boolean) {
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
  }
  try {
    const r = await guardarCierre(input)
    b.sync_status = 'subido'
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
export async function borradoresPendientes(): Promise<BorradorCierre[]> {
  return db().borradores.where('sync_status').anyOf('local', 'error').toArray()
}

export async function borrarBorrador(clave: string) {
  await db().borradores.delete(clave)
}
