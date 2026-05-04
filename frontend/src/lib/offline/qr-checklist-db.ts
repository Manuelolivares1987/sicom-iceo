// ============================================================================
// IndexedDB layer para QR Checklist offline-first.
// Stores:
//   - checklists: ChecklistOfflineRecord (PK = cliente_uuid)
//   - blobs:      foto_blob_id -> Blob (para reintentos de upload offline)
//
// Requiere paquete `idb`. Instalar: npm install idb
// ============================================================================

import { openDB, type IDBPDatabase } from 'idb'
import type { ChecklistOfflineRecord, EstadoSyncLocal } from './qr-checklist-types'

const DB_NAME = 'sicom-qr-checklist'
const DB_VERSION = 1
const STORE_CHECKLISTS = 'checklists'
const STORE_BLOBS = 'blobs'

interface BlobRecord {
  id: string                   // foto_blob_id
  cliente_uuid: string         // referencia al checklist padre
  codigo_item: string
  blob: Blob
  mime: string
  created_at: string
}

let dbPromise: Promise<IDBPDatabase> | null = null

function getDB(): Promise<IDBPDatabase> {
  if (typeof window === 'undefined') {
    throw new Error('IndexedDB solo disponible en navegador')
  }
  if (!dbPromise) {
    dbPromise = openDB(DB_NAME, DB_VERSION, {
      upgrade(db) {
        if (!db.objectStoreNames.contains(STORE_CHECKLISTS)) {
          const store = db.createObjectStore(STORE_CHECKLISTS, {
            keyPath: 'cliente_uuid',
          })
          store.createIndex('estado', 'estado')
          store.createIndex('activo_id', 'activo_id')
          store.createIndex('updated_at', 'updated_at')
        }
        if (!db.objectStoreNames.contains(STORE_BLOBS)) {
          const blobs = db.createObjectStore(STORE_BLOBS, { keyPath: 'id' })
          blobs.createIndex('cliente_uuid', 'cliente_uuid')
        }
      },
    })
  }
  return dbPromise
}

// ── Checklists ──────────────────────────────────────────────────────

export async function dbSaveChecklist(record: ChecklistOfflineRecord): Promise<void> {
  const db = await getDB()
  record.updated_at = new Date().toISOString()
  await db.put(STORE_CHECKLISTS, record)
}

export async function dbGetChecklist(
  clienteUuid: string
): Promise<ChecklistOfflineRecord | undefined> {
  const db = await getDB()
  return db.get(STORE_CHECKLISTS, clienteUuid)
}

export async function dbDeleteChecklist(clienteUuid: string): Promise<void> {
  const db = await getDB()
  await db.delete(STORE_CHECKLISTS, clienteUuid)
  // Limpiar blobs huerfanos
  const tx = db.transaction(STORE_BLOBS, 'readwrite')
  const idx = tx.store.index('cliente_uuid')
  let cursor = await idx.openCursor(IDBKeyRange.only(clienteUuid))
  while (cursor) {
    await cursor.delete()
    cursor = await cursor.continue()
  }
  await tx.done
}

export async function dbListChecklistsByEstado(
  estado: EstadoSyncLocal
): Promise<ChecklistOfflineRecord[]> {
  const db = await getDB()
  return db.getAllFromIndex(STORE_CHECKLISTS, 'estado', estado)
}

export async function dbListChecklistsPendientes(): Promise<ChecklistOfflineRecord[]> {
  const pendientes = await dbListChecklistsByEstado('pendiente_sync')
  const errores = await dbListChecklistsByEstado('error_sync')
  return [...pendientes, ...errores]
}

export async function dbListAllChecklists(): Promise<ChecklistOfflineRecord[]> {
  const db = await getDB()
  return db.getAll(STORE_CHECKLISTS)
}

// ── Blobs (fotos) ───────────────────────────────────────────────────

export async function dbSaveBlob(
  blobId: string,
  clienteUuid: string,
  codigoItem: string,
  blob: Blob,
  mime?: string
): Promise<void> {
  const db = await getDB()
  const record: BlobRecord = {
    id: blobId,
    cliente_uuid: clienteUuid,
    codigo_item: codigoItem,
    blob,
    mime: mime || blob.type || 'image/jpeg',
    created_at: new Date().toISOString(),
  }
  await db.put(STORE_BLOBS, record)
}

export async function dbGetBlob(blobId: string): Promise<BlobRecord | undefined> {
  const db = await getDB()
  return db.get(STORE_BLOBS, blobId)
}

export async function dbDeleteBlob(blobId: string): Promise<void> {
  const db = await getDB()
  await db.delete(STORE_BLOBS, blobId)
}

export async function dbListBlobsByChecklist(
  clienteUuid: string
): Promise<BlobRecord[]> {
  const db = await getDB()
  return db.getAllFromIndex(STORE_BLOBS, 'cliente_uuid', clienteUuid)
}

// ── Util ────────────────────────────────────────────────────────────

export function dbIsAvailable(): boolean {
  return typeof window !== 'undefined' && 'indexedDB' in window
}

export function generateClienteUuid(): string {
  if (typeof crypto !== 'undefined' && 'randomUUID' in crypto) {
    return crypto.randomUUID()
  }
  // fallback v4 manual
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0
    const v = c === 'x' ? r : (r & 0x3) | 0x8
    return v.toString(16)
  })
}
