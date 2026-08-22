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
  getPuntosMedicion, getCierreAnterior, guardarCierre,
  type PuntoMedicion, type LecturaPunto, type LecturaMedidor, type CierreInput,
} from '@/lib/services/combustible-cierre'

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

class CierreDB extends Dexie {
  cache!: Table<CacheRow, string>
  borradores!: Table<BorradorCierre, string>
  constructor() {
    super('sicom-combustible-cierre')
    this.version(1).stores({
      cache: 'key, updated_at',
      borradores: 'clave, sync_status, actualizado_at',
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

export async function subirBorrador(b: BorradorCierre, firmar: boolean) {
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
