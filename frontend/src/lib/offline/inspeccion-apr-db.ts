// ============================================================================
// Inspección de terreno APR — borrador en el teléfono (MIG685)
// ----------------------------------------------------------------------------
// En faena no siempre hay señal. La inspección completa (respuestas, cuadrilla,
// encuesta de fatiga y FOTOS) vive en IndexedDB hasta que el APR la envía.
// La plantilla y el estado documental se copian al borrador al crearlo (en
// Calama, con señal), así el formulario funciona entero sin conexión.
//
// Stores:
//   borradores: BorradorInspeccion (PK cliente_uuid)
//   fotos:      FotoLocal (PK id) — Blob comprimido pendiente de subir
// ============================================================================

import { openDB, type IDBPDatabase } from 'idb'
import type { EvidenciaArchivo } from '@/lib/services/prevencion-reportabilidad'
import type {
  FatigaRespuestas, Habilitacion, PuntoPlantilla, Respuesta,
} from '@/lib/services/prevencion-inspeccion'

export interface FotoRef {
  /** Foto ya subida al bucket. */
  subida?: EvidenciaArchivo
  /** Foto local pendiente (id en el store `fotos`). */
  local_id?: string
  nombre: string
}

export interface RespuestaLocal {
  respuesta: Respuesta | null
  observacion: string
  fotos: FotoRef[]
  // Desviación (obligatoria si «no cumple»)
  desv_descripcion: string
  desv_accion: string
  desv_responsable: string
  desv_fecha: string
  desv_criticidad: 'alta' | 'media' | 'baja'
}

export interface PersonaLocal {
  personal_id: string
  nombre: string
  es_conductor: boolean
  fatiga: FatigaRespuestas
}

export interface BorradorInspeccion {
  cliente_uuid: string
  servidor_id: string | null
  faena_id: string
  faena_nombre: string
  grupo: string
  fecha: string
  hora_inicio: string
  instalacion: string
  area_sector: string
  trabajo: string
  supervisor: string
  trabajo_cruzado: boolean
  empresas_cruzadas: string
  observacion: string
  personas: PersonaLocal[]
  respuestas: Record<string, RespuestaLocal>
  plantilla: PuntoPlantilla[]
  habilitacion: Habilitacion
  /** Lo que respondió la base en el último envío. */
  ultimo_envio: { at: string, estado: string, resultado: string } | null
  created_at: string
  updated_at: string
}

interface FotoLocal {
  id: string
  cliente_uuid: string
  blob: Blob
  nombre: string
  created_at: string
}

const DB_NAME = 'sicom-inspeccion-apr'
const DB_VERSION = 1
let dbPromise: Promise<IDBPDatabase> | null = null

function getDB(): Promise<IDBPDatabase> {
  if (typeof window === 'undefined') throw new Error('IndexedDB solo disponible en navegador')
  if (!dbPromise) {
    dbPromise = openDB(DB_NAME, DB_VERSION, {
      upgrade(db) {
        if (!db.objectStoreNames.contains('borradores')) {
          db.createObjectStore('borradores', { keyPath: 'cliente_uuid' })
        }
        if (!db.objectStoreNames.contains('fotos')) {
          const s = db.createObjectStore('fotos', { keyPath: 'id' })
          s.createIndex('cliente_uuid', 'cliente_uuid')
        }
      },
    })
  }
  return dbPromise
}

export function respuestaVacia(): RespuestaLocal {
  return {
    respuesta: null, observacion: '', fotos: [],
    desv_descripcion: '', desv_accion: '', desv_responsable: '',
    desv_fecha: '', desv_criticidad: 'media',
  }
}

export async function guardarBorrador(b: BorradorInspeccion): Promise<void> {
  const db = await getDB()
  b.updated_at = new Date().toISOString()
  await db.put('borradores', b)
}

export async function leerBorrador(id: string): Promise<BorradorInspeccion | undefined> {
  const db = await getDB()
  return db.get('borradores', id)
}

export async function listarBorradores(): Promise<BorradorInspeccion[]> {
  const db = await getDB()
  const todos = (await db.getAll('borradores')) as BorradorInspeccion[]
  return todos.sort((a, b) => b.updated_at.localeCompare(a.updated_at))
}

export async function borrarBorrador(id: string): Promise<void> {
  const db = await getDB()
  await db.delete('borradores', id)
  const tx = db.transaction('fotos', 'readwrite')
  let cur = await tx.store.index('cliente_uuid').openCursor(IDBKeyRange.only(id))
  while (cur) { await cur.delete(); cur = await cur.continue() }
  await tx.done
}

export async function guardarFotoLocal(clienteUuid: string, blob: Blob, nombre: string): Promise<string> {
  const db = await getDB()
  const id = crypto.randomUUID()
  await db.put('fotos', { id, cliente_uuid: clienteUuid, blob, nombre, created_at: new Date().toISOString() })
  return id
}

export async function leerFotoLocal(id: string): Promise<Blob | undefined> {
  const db = await getDB()
  const f = (await db.get('fotos', id)) as FotoLocal | undefined
  return f?.blob
}

export async function borrarFotoLocal(id: string): Promise<void> {
  const db = await getDB()
  await db.delete('fotos', id)
}

/** Cuántas fotos del borrador siguen solo en el teléfono. */
export function fotosPendientes(b: BorradorInspeccion): number {
  return Object.values(b.respuestas).reduce(
    (n, r) => n + r.fotos.filter((f) => !f.subida).length, 0)
}
