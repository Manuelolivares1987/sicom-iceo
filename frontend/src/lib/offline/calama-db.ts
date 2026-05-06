// IndexedDB schema (Dexie) para Operacion Calama offline.
// Crea / migra la base local 'sicom-calama-terreno'.

import Dexie, { type Table } from 'dexie'
import type {
  LocalJornada, LocalEvidencia, LocalFirma, LocalEvento,
  SyncQueueItem, LocalBlob, OfflineSettings,
} from './calama-offline-types'

class CalamaTerrenoDB extends Dexie {
  jornadas!: Table<LocalJornada, string>
  evidencias!: Table<LocalEvidencia, string>
  firmas!: Table<LocalFirma, string>
  eventos!: Table<LocalEvento, string>
  sync_queue!: Table<SyncQueueItem, number>
  blobs!: Table<LocalBlob, string>
  settings!: Table<OfflineSettings, string>

  constructor() {
    super('sicom-calama-terreno')
    this.version(1).stores({
      jornadas:    'local_id, server_id, ot_id, plan_semanal_id, sync_status, fecha_jornada',
      evidencias:  'local_id, client_uuid, server_id, jornada_id, ot_id, sync_status',
      firmas:      'local_id, client_uuid, server_id, jornada_id, ot_id, sync_status',
      eventos:     'local_id, client_uuid, jornada_id, ot_id, sync_status, created_at',
      sync_queue:  '++id, evento_local_id, status, created_at',
      blobs:       'blob_id',
      settings:    'key',
    })
  }
}

let _db: CalamaTerrenoDB | null = null

export function calamaDB(): CalamaTerrenoDB {
  if (typeof window === 'undefined') {
    // Evitar crear Dexie en SSR.
    throw new Error('calamaDB() solo puede usarse en cliente')
  }
  if (!_db) _db = new CalamaTerrenoDB()
  return _db
}

// Borrar TODA la BD local (logout, "borrar datos offline").
export async function clearCalamaDB(): Promise<void> {
  if (typeof window === 'undefined') return
  if (_db) {
    await _db.delete()
    _db = null
  } else {
    try { await Dexie.delete('sicom-calama-terreno') } catch { /* noop */ }
  }
}
