// ============================================================================
// Tipos compartidos del modulo QR Checklist offline-first.
// Coinciden con el payload de las RPCs del backend (14B + 14B2).
// ============================================================================

export type SemaforoTecnico = 'verde' | 'amarillo' | 'naranja' | 'rojo'
export type ClasificacionCalidad = 'alta' | 'media' | 'baja' | 'sospechoso'
export type TipoRespuesta = 'ok_obs_falla' | 'si_no' | 'numerico' | 'texto' | 'control_aleatorio'
export type CriticidadItem = 'amarillo' | 'naranja' | 'rojo' | null

export type EstadoSyncLocal =
  | 'borrador'
  | 'pendiente_sync'
  | 'sincronizando'
  | 'sincronizado'
  | 'error_sync'

export interface QrTemplateItem {
  id: string
  seccion: string
  orden: number
  codigo_item: string
  descripcion: string
  tipo_respuesta: TipoRespuesta
  criticidad_si_falla: CriticidadItem
  requiere_foto: boolean
  requiere_foto_si_falla: boolean
  requiere_foto_siempre: boolean
  requiere_observacion_si_falla: boolean
  solo_camara: boolean
  es_control_aleatorio: boolean
  obligatorio: boolean
  valor_min: number | null
  valor_max: number | null
  unidad: string | null
}

export interface QrTemplate {
  id: string
  codigo: string
  nombre: string
  descripcion: string | null
  es_universal: boolean
  duracion_minima_segundos: number
  cantidad_controles_aleatorios: number
  nivel_asignacion: 'activo' | 'modelo' | 'marca' | 'tipo' | 'familia' | 'universal'
  declaracion_obligatoria: string
}

export interface QrActivoSummary {
  id: string
  codigo: string
  nombre: string | null
  tipo: string
  criticidad: string
  kilometraje_actual: number
  horometro_actual: number
  modelo: string | null
  marca: string | null
}

export interface QrChecklistRpcResponse {
  activo: QrActivoSummary
  template: QrTemplate
  items: QrTemplateItem[]
  items_aleatorios: QrTemplateItem[]
  error?: string
}

// ── Local state per item ────────────────────────────────────────────
export interface FotoMetadata {
  timestamp: string
  origen: 'camera' | 'galeria' | 'desconocido'
  lat: number | null
  lng: number | null
  item_id: string | null
  activo_id: string | null
  size_bytes?: number
  mime?: string
}

export interface RespuestaItemLocal {
  template_item_id: string | null
  seccion: string
  orden: number
  codigo_item: string
  descripcion: string | null
  respuesta_tipo: TipoRespuesta
  respuesta_valor: string | null
  es_falla: boolean
  es_observacion: boolean
  motivo: string | null
  // Foto
  foto_blob_id: string | null     // referencia a IndexedDB store de blobs
  foto_url: string | null         // URL una vez subida
  foto_metadata: FotoMetadata | null
  // Trazabilidad
  respondido_en: string | null
  orden_respuesta: number | null
  tiempo_desde_inicio_segundos: number | null
  cambio_respuesta: boolean
  respuesta_original: string | null
  es_control_aleatorio: boolean
}

// ── Checklist completo en IndexedDB ─────────────────────────────────
export interface ChecklistOfflineRecord {
  cliente_uuid: string                    // PK local + idempotencia server
  activo_id: string
  template_id: string
  template_snapshot: QrTemplate           // copia inmutable del template
  items_snapshot: QrTemplateItem[]        // items + aleatorios mezclados
  // Datos del operador
  operador_nombre: string | null
  operador_telefono: string | null
  operador_email: string | null
  operador_empresa: string | null
  rut_operador: string | null
  // Lecturas
  kilometraje_reportado: number | null
  horometro_reportado: number | null
  // Tiempos
  iniciado_en: string                     // ISO
  terminado_en: string | null
  duracion_segundos: number | null
  // GPS
  gps_inicial_lat: number | null
  gps_inicial_lng: number | null
  gps_inicial_precision_m: number | null
  gps_final_lat: number | null
  gps_final_lng: number | null
  gps_final_precision_m: number | null
  gps_no_disponible: boolean
  // Firma
  firma_declaracion: string | null
  firma_url: string | null
  // Dispositivo
  dispositivo_info: Record<string, unknown> | null
  // Items
  respuestas: Record<string, RespuestaItemLocal>  // key = codigo_item
  // Texto libre
  observacion_general: string | null
  // Sync
  estado: EstadoSyncLocal
  intentos_sync: number
  ultimo_error_sync: string | null
  // Resultado server (post-sync)
  servidor_respuesta_id: string | null
  servidor_semaforo: SemaforoTecnico | null
  servidor_score_calidad: number | null
  servidor_clasificacion_calidad: ClasificacionCalidad | null
  servidor_sospechoso: boolean | null
  servidor_alertas_tecnicas: number | null
  servidor_alertas_calidad: number | null
  // Audit
  created_at: string
  updated_at: string
}

// ── Payload que se envia al RPC rpc_guardar_checklist_publico ───────
export interface ChecklistPayload {
  cliente_uuid: string
  activo_id: string
  template_id: string
  operador_nombre: string | null
  operador_telefono: string | null
  operador_email: string | null
  operador_empresa: string | null
  rut_operador: string | null
  kilometraje_reportado: number | null
  horometro_reportado: number | null
  observacion_general: string | null
  iniciado_en: string
  terminado_en: string
  gps_inicial_lat: number | null
  gps_inicial_lng: number | null
  gps_inicial_precision_m: number | null
  gps_final_lat: number | null
  gps_final_lng: number | null
  gps_final_precision_m: number | null
  gps_no_disponible: boolean
  firma_url: string | null
  firma_declaracion: string | null
  dispositivo_info: Record<string, unknown> | null
  scan_lat: number | null
  scan_lng: number | null
  created_offline_at: string | null
  items: ChecklistPayloadItem[]
}

export interface ChecklistPayloadItem {
  template_item_id: string | null
  seccion: string
  orden: number
  codigo_item: string
  descripcion: string | null
  respuesta_tipo: TipoRespuesta
  respuesta_valor: string | null
  es_falla: boolean
  es_observacion: boolean
  motivo: string | null
  foto_url: string | null
  foto_metadata: FotoMetadata | null
  respondido_en: string | null
  orden_respuesta: number | null
  tiempo_desde_inicio_segundos: number | null
  cambio_respuesta: boolean
  respuesta_original: string | null
  es_control_aleatorio: boolean
}

export interface GuardarChecklistResponse {
  success: boolean
  ya_existia: boolean
  respuesta_id: string
  semaforo: SemaforoTecnico
  score_calidad: number
  clasificacion_calidad: ClasificacionCalidad
  sospechoso: boolean
  duracion_segundos: number
  duracion_minima_segundos: number
  items_falla: number
  items_observacion: number
  alertas_tecnicas_generadas: number
  alertas_calidad_generadas: number
}
