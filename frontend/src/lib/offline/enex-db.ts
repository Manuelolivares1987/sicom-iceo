// IndexedDB (Dexie) para la app de terreno ENEX (offline-first).
// Cache de pendientes + ítems de pauta, cola de ejecuciones pendientes de
// sincronizar y blobs de fotos/firmas.

import Dexie, { type Table } from 'dexie'

export type EnexCacheRow = { key: string; value: unknown; updated_at: string }
export type EnexBlob = { blob_id: string; blob: Blob; mime: string }

/** Resultado local de un ítem (foto como blob hasta sincronizar). */
export type EnexPendItem = {
  pauta_item_id: string
  resultado?: string | null
  valor_medicion?: string | null
  observacion?: string | null
  foto_blob_id?: string | null
  // Actividades críticas (MIG238): foto del antes y del después por ítem.
  foto_antes_blob_id?: string | null
  foto_despues_blob_id?: string | null
  // [MIG265] Ahora TODO ítem lleva antes/después y admite varias fotos.
  // Las que ya están subidas viajan como URL; las nuevas, como blob local.
  fotos_antes_blob_ids?: string[]
  fotos_despues_blob_ids?: string[]
  fotos_antes_urls?: string[]
  fotos_despues_urls?: string[]
}

/** Ejecución pendiente de subir. */
export type EnexPending = {
  local_id: string
  client_uuid: string
  programacion_id: string
  con_mandante: boolean
  ot_numero?: string | null
  ejecutor?: string | null
  tecnico_nombre?: string | null
  observacion?: string | null
  firmante_mandante?: string | null
  items: EnexPendItem[]
  firma_tec_blob_id?: string | null
  firma_mand_blob_id?: string | null
  // [MIG265] Tiempo que tomó el trabajo, medido por la app.
  inicio_at?: string | null
  fin_at?: string | null
  duracion_segundos?: number | null
  // control
  sync_status: 'pending' | 'error'
  retries: number
  last_error: string | null
  created_at: string
}

class EnexTerrenoDB extends Dexie {
  cache!: Table<EnexCacheRow, string>
  pending!: Table<EnexPending, string>
  blobs!: Table<EnexBlob, string>

  constructor() {
    super('sicom-enex-terreno')
    this.version(1).stores({
      cache:   'key, updated_at',
      pending: 'local_id, programacion_id, sync_status, created_at',
      blobs:   'blob_id',
    })
  }
}

let _db: EnexTerrenoDB | null = null
export function enexDB(): EnexTerrenoDB {
  if (typeof window === 'undefined') throw new Error('enexDB() solo en cliente')
  if (!_db) _db = new EnexTerrenoDB()
  return _db
}

export function newId(): string {
  if (typeof crypto !== 'undefined' && 'randomUUID' in crypto) return crypto.randomUUID()
  return `id_${Date.now()}_${Math.floor(Math.random() * 1e9)}`
}
