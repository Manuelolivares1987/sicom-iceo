// Tipos para la capa offline de Operacion Calama (/m/calama).
// Cada registro local lleva client_uuid para idempotencia con el backend.

export type SyncStatus = 'synced' | 'pending' | 'error' | 'conflict'

export type LocalJornada = {
  // local_id = mismo plan_semanal_ot_id (server) cuando ya viene del backend.
  // Para futuro multi-device generamos uuid local en su lugar.
  local_id: string
  server_id: string | null
  ot_id: string
  plan_semanal_id: string | null
  folio: string
  titulo: string
  fecha_jornada: string | null
  zona_codigo: string | null
  responsable_id: string | null
  estado_plan_server: string
  estado_plan_local: string
  llegada_faena_at: string | null
  inicio_at: string | null
  cierre_at: string | null
  avance_pct: number
  // Comentario del planificador, observaciones, etc.
  observaciones: string | null
  visible_en_kanban: boolean
  desprogramada: boolean
  downloaded_at: string
  updated_local_at: string
  sync_status: SyncStatus
}

export type LocalEvidencia = {
  local_id: string             // uuid local
  client_uuid: string           // = local_id (para idempotencia con backend)
  server_id: string | null
  jornada_id: string            // plan_semanal_ot_id
  ot_id: string
  contexto: 'jornada_antes' | 'jornada_durante' | 'jornada_despues'
           | 'jornada_rechazo' | 'interferencia_mandante' | 'llegada_faena'
  momento: 'antes' | 'durante' | 'despues' | 'rechazo' | 'interferencia' | 'llegada' | 'firma' | 'generico'
  blob_id: string | null         // referencia al Blob en tabla `blobs`
  storage_path: string | null    // poblado tras subir a Storage
  archivo_url: string | null     // poblado tras subir
  mime_type: string | null
  tamano_bytes: number | null
  descripcion: string | null
  gps_lat: number | null
  gps_lng: number | null
  gps_accuracy: number | null
  geolocation_status: string | null
  tomada_en: string
  sync_status: SyncStatus
  retries: number
  last_error: string | null
}

export type LocalFirma = {
  local_id: string
  client_uuid: string
  server_id: string | null
  jornada_id: string
  ot_id: string
  firmante_tipo: 'operador' | 'mandante' | 'supervisor'
  firmante_nombre: string | null
  firmante_rut: string | null
  contexto: 'inicio' | 'cierre_operador' | 'aceptacion' | 'rechazo'
  blob_id: string | null         // PNG firma
  storage_path: string | null
  firma_url: string | null
  observacion: string | null
  gps_lat: number | null
  gps_lng: number | null
  gps_accuracy: number | null
  geolocation_status: string | null
  firmado_en: string
  sync_status: SyncStatus
  retries: number
  last_error: string | null
}

export type LocalEvento = {
  local_id: string
  client_uuid: string
  jornada_id: string
  ot_id: string
  // tipo del RPC: iniciar_jornada, evento_jornada (pause/resume/avance/interferencia),
  // finalizar_jornada, llegada_faena, aceptacion, rechazo, reprogramar.
  rpc_tipo:
    | 'iniciar_jornada'
    | 'evento_jornada'
    | 'finalizar_jornada'
    | 'llegada_faena'
    | 'aceptacion'
    | 'rechazo'
    | 'reprogramar'
  // Payload exacto que se enviara al backend (sin URLs todavia si las fotos
  // estan offline). El sync layer reemplaza los placeholders por las URLs
  // reales tras subir blobs.
  payload: Record<string, unknown>
  // Referencias a blobs locales que deben subirse antes del RPC.
  // {keyPayload: 'foto_antes_url', evidencia_local_id: 'xxx'} indica que en
  // payload[keyPayload] tras la subida deben ir las URLs.
  blob_refs: Array<{
    payload_url_key: string         // ej. 'foto_antes_url'
    payload_path_key: string        // ej. 'foto_antes_storage_path'
    evidencia_local_id?: string     // si referencia a una entrada en evidencias
    firma_local_id?: string          // si referencia a una entrada en firmas
  }>
  created_at: string
  sync_status: SyncStatus
  retries: number
  last_error: string | null
}

// Item en cola de sincronizacion. Apunta al evento via local_id.
export type SyncQueueItem = {
  id?: number
  evento_local_id: string
  status: SyncStatus
  retries: number
  last_error: string | null
  created_at: string
  updated_at: string
}

export type LocalBlob = {
  blob_id: string
  blob: Blob
  mime: string
  size: number
}

export type OfflineSettings = {
  key: 'state'
  last_download_at: string | null
  user_id: string | null
  user_email: string | null
}
