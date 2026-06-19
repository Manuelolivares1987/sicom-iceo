// IndexedDB (Dexie) para la app del mecánico de taller offline.
// Base local 'sicom-taller-terreno': cache de OTs + checklist, cola de cambios
// pendientes (resultados/observaciones/fotos/cronómetro) y blobs de fotos.

import Dexie, { type Table } from 'dexie'

/** Cache genérico clave→valor (lista de OTs por mecánico, checklist por OT). */
export type TallerCacheRow = { key: string; value: unknown; updated_at: string }

/** Foto tomada offline, pendiente de subir. */
export type TallerBlob = { blob_id: string; blob: Blob; mime: string }

/** Cambio pendiente de sincronizar. */
export type TallerPending = {
  local_id: string
  client_uuid: string
  ot_id: string
  kind: 'item' | 'timing'
  // kind = 'item' (marcar resultado / observación / foto de una tarea)
  instance_item_id?: string
  instance_id?: string
  resultado?: 'ok' | 'no_ok' | 'na'
  observacion?: string | null
  foto_blob_id?: string | null
  // kind = 'timing' (cronómetro de jornada)
  accion?: 'iniciar' | 'pausar' | 'finalizar'
  user_id?: string
  observaciones?: string | null
  con_observaciones?: boolean
  firma_blob_id?: string | null   // firma del técnico para finalizar
  // control
  sync_status: 'pending' | 'error'
  retries: number
  last_error: string | null
  created_at: string
}

class TallerTerrenoDB extends Dexie {
  cache!: Table<TallerCacheRow, string>
  pending!: Table<TallerPending, string>
  blobs!: Table<TallerBlob, string>

  constructor() {
    super('sicom-taller-terreno')
    this.version(1).stores({
      cache:   'key, updated_at',
      pending: 'local_id, ot_id, kind, instance_item_id, sync_status, created_at',
      blobs:   'blob_id',
    })
  }
}

let _db: TallerTerrenoDB | null = null

export function tallerDB(): TallerTerrenoDB {
  if (typeof window === 'undefined') throw new Error('tallerDB() solo en cliente')
  if (!_db) _db = new TallerTerrenoDB()
  return _db
}

export async function clearTallerDB(): Promise<void> {
  if (typeof window === 'undefined') return
  if (_db) { await _db.delete(); _db = null }
  else { try { await Dexie.delete('sicom-taller-terreno') } catch { /* noop */ } }
}

export function newId(): string {
  if (typeof crypto !== 'undefined' && 'randomUUID' in crypto) return crypto.randomUUID()
  return `id_${Date.now()}_${Math.floor(Math.random() * 1e9)}`
}
