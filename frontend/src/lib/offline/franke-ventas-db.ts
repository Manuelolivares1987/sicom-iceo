// IndexedDB (Dexie) para la app del vendedor Franke offline.
// Base local 'sicom-franke-ventas': ventas pendientes + blobs (fotos/firma) +
// cache de camiones para operar sin conexion.

import Dexie, { type Table } from 'dexie'

export type LocalVentaFranke = {
  local_id: string
  client_uuid: string            // idempotencia (dedup en el RPC)
  payload: Record<string, unknown>
  blob_refs: Array<{ key: string; blob_id: string }>  // key del payload <- blob
  sync_status: 'pending' | 'synced' | 'error'
  retries: number
  last_error: string | null
  resumen: { cliente: string; litros: number; camion: string }  // para UI
  created_at: string
  synced_at: string | null
  server_folio: string | null
}

export type LocalBlobVF = { blob_id: string; blob: Blob; mime: string }
export type CacheVF = { key: string; value: unknown; updated_at: string }

class FrankeVentasDB extends Dexie {
  ventas!: Table<LocalVentaFranke, string>
  blobs!: Table<LocalBlobVF, string>
  cache!: Table<CacheVF, string>

  constructor() {
    super('sicom-franke-ventas')
    this.version(1).stores({
      ventas: 'local_id, client_uuid, sync_status, created_at',
      blobs:  'blob_id',
      cache:  'key',
    })
  }
}

let _db: FrankeVentasDB | null = null
export function frankeDB(): FrankeVentasDB {
  if (typeof window === 'undefined') throw new Error('frankeDB() solo en cliente')
  if (!_db) _db = new FrankeVentasDB()
  return _db
}

export async function clearFrankeDB(): Promise<void> {
  if (typeof window === 'undefined') return
  if (_db) { await _db.delete(); _db = null }
  else { try { await Dexie.delete('sicom-franke-ventas') } catch { /* noop */ } }
}
