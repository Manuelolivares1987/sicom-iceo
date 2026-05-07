import { supabase } from '@/lib/supabase'

// ============================================================================
// Tipos PRO terreno (jornada con evidencias + firmas + aceptacion/rechazo)
// ============================================================================

export type FirmanteTipo = 'operador' | 'mandante' | 'supervisor'
export type FirmaContexto = 'inicio' | 'cierre_operador' | 'aceptacion' | 'rechazo'
export type EvidenciaMomento = 'antes' | 'durante' | 'despues' | 'rechazo' | 'firma' | 'generico' | 'interferencia' | 'llegada'

export type CalamaFirmaJornada = {
  id: string
  plan_semanal_ot_id: string
  ot_id: string
  firmante_tipo: FirmanteTipo
  firmante_id: string | null
  firmante_nombre: string | null
  firmante_rut: string | null
  firma_url: string
  firma_storage_path: string | null
  contexto: FirmaContexto
  gps_lat: number | null
  gps_lng: number | null
  observacion: string | null
  created_at: string
}

export type CalamaRechazoJornada = {
  id: string
  plan_semanal_ot_id: string
  ot_id: string
  mandante_id: string | null
  motivo: string
  requiere_rehacer: boolean
  fotos_url: string[]
  firma_id: string | null
  observacion: string | null
  created_at: string
}

export type CalamaEvidenciaPro = {
  id: string
  contexto: string
  ot_id: string | null
  plan_semanal_ot_id: string | null
  ejecucion_id: string | null
  archivo_url: string
  storage_path: string | null
  tipo: 'foto' | 'video' | 'firma' | 'documento' | 'pdf'
  momento: EvidenciaMomento | null
  gps_lat: number | null
  gps_lng: number | null
  descripcion: string | null
  client_uuid: string | null
  sync_status: 'sincronizado' | 'pendiente' | 'error'
  created_at: string
}

// ============================================================================
// Helpers de geolocalizacion + uploads
// ============================================================================

export type GeoStatus = 'granted' | 'denied' | 'unavailable' | 'error'
export type GeoFix = {
  lat: number | null
  lng: number | null
  accuracy: number | null
  status: GeoStatus
}

export async function tryGeolocate(): Promise<GeoFix> {
  if (typeof navigator === 'undefined' || !navigator.geolocation) {
    return { lat: null, lng: null, accuracy: null, status: 'unavailable' }
  }
  return new Promise((resolve) => {
    const timeout = setTimeout(
      () => resolve({ lat: null, lng: null, accuracy: null, status: 'error' }),
      8000,
    )
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        clearTimeout(timeout)
        resolve({
          lat: pos.coords.latitude,
          lng: pos.coords.longitude,
          accuracy: pos.coords.accuracy ?? null,
          status: 'granted',
        })
      },
      (err) => {
        clearTimeout(timeout)
        // GeolocationPositionError.PERMISSION_DENIED = 1
        const status: GeoStatus = err && err.code === 1 ? 'denied' : 'error'
        resolve({ lat: null, lng: null, accuracy: null, status })
      },
      { enableHighAccuracy: true, timeout: 7000, maximumAge: 30_000 },
    )
  })
}

export async function uploadEvidenciaJornada(params: {
  blob: Blob
  otId: string
  planOtId: string
  momento: EvidenciaMomento
  ext?: string
}): Promise<{ url: string; storage_path: string }> {
  const ts = Date.now()
  const ext = params.ext ?? 'jpg'
  const path = `ot-${params.otId}/jornada-${params.planOtId}/${params.momento}-${ts}.${ext}`
  const { error } = await supabase.storage
    .from('calama-evidencias')
    .upload(path, params.blob, { upsert: false, contentType: params.blob.type || 'image/jpeg' })
  if (error) throw error
  const { data } = supabase.storage.from('calama-evidencias').getPublicUrl(path)
  return { url: data.publicUrl, storage_path: path }
}

export async function uploadFirmaJornada(params: {
  dataUrl: string
  otId: string
  planOtId: string
  contexto: FirmaContexto
}): Promise<{ url: string; storage_path: string }> {
  // dataUrl viene como data:image/png;base64,...
  const base64 = params.dataUrl.split(',')[1] ?? ''
  const bin = atob(base64)
  const buf = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i)
  const blob = new Blob([buf], { type: 'image/png' })
  const ts = Date.now()
  const path = `ot-${params.otId}/jornada-${params.planOtId}/${params.contexto}-${ts}.png`
  const { error } = await supabase.storage
    .from('calama-firmas')
    .upload(path, blob, { upsert: false, contentType: 'image/png' })
  if (error) throw error
  const { data } = supabase.storage.from('calama-firmas').getPublicUrl(path)
  return { url: data.publicUrl, storage_path: path }
}

// crypto.randomUUID es estandar; fallback simple por si.
export function genClientUuid(): string {
  if (typeof crypto !== 'undefined' && 'randomUUID' in crypto) return crypto.randomUUID()
  return 'cuid-' + Math.random().toString(36).slice(2) + Date.now().toString(36)
}

// ============================================================================
// RPCs PRO jornada
// ============================================================================

type RpcResult<T = unknown> = { data: T | null; error: unknown }

type GeoFields = {
  gps_lat?: number | null
  gps_lng?: number | null
  gps_accuracy?: number | null
  geolocation_status?: GeoStatus
}

export async function rpcIniciarJornada(payload: {
  plan_semanal_ot_id: string
  foto_antes_url: string
  foto_antes_storage_path: string
  observacion?: string
  client_uuid_evidencia?: string
  client_uuid_ejecucion?: string
} & GeoFields): Promise<RpcResult> {
  const { data, error } = await supabase.rpc('rpc_calama_iniciar_jornada', { p_payload: payload })
  return { data, error }
}

export async function rpcRegistrarEventoJornada(payload: {
  plan_semanal_ot_id: string
  tipo: 'pause' | 'resume' | 'avance' | 'comentario' | 'foto_durante' | 'interferencia'
  motivo?: string
  comentario?: string
  avance?: number
  foto_url?: string
  foto_storage_path?: string
  client_uuid?: string
} & GeoFields): Promise<RpcResult> {
  const { data, error } = await supabase.rpc('rpc_calama_registrar_evento_jornada', { p_payload: payload })
  return { data, error }
}

export async function rpcFinalizarJornada(payload: {
  plan_semanal_ot_id: string
  avance_final: number
  foto_despues_url: string
  foto_despues_storage_path: string
  firma_operador_url: string
  firma_operador_storage_path: string
  observacion?: string
  client_uuid_foto?: string
  client_uuid_firma?: string
} & GeoFields): Promise<RpcResult> {
  const { data, error } = await supabase.rpc('rpc_calama_finalizar_jornada', { p_payload: payload })
  return { data, error }
}

export async function rpcRegistrarAceptacionJornada(payload: {
  plan_semanal_ot_id: string
  firma_mandante_url: string
  firma_mandante_storage_path: string
  firmante_nombre?: string
  firmante_rut?: string
  observacion?: string
  client_uuid?: string
} & GeoFields): Promise<RpcResult> {
  const { data, error } = await supabase.rpc('rpc_calama_registrar_aceptacion_jornada', { p_payload: payload })
  return { data, error }
}

export async function rpcRegistrarRechazoJornada(payload: {
  plan_semanal_ot_id: string
  motivo: string
  requiere_rehacer?: boolean
  fotos?: Array<{ url: string; storage_path?: string; client_uuid?: string }>
  firma_mandante_url: string
  firma_mandante_storage_path: string
  firmante_nombre?: string
  observacion?: string
  client_uuid_rechazo?: string
  client_uuid_firma?: string
} & GeoFields): Promise<RpcResult> {
  const { data, error } = await supabase.rpc('rpc_calama_registrar_rechazo_jornada', { p_payload: payload })
  return { data, error }
}

export async function rpcReprogramarSaldoOT(payload: {
  plan_semanal_ot_origen_id: string
  plan_semanal_id: string
  fecha_destino: string  // YYYY-MM-DD
  responsable_id?: string
  avance_objetivo_pct?: number
  horas_planificadas?: number
  motivo: string
}): Promise<RpcResult> {
  const { data, error } = await supabase.rpc('rpc_calama_reprogramar_saldo_ot', { p_payload: payload })
  return { data, error }
}

export async function rpcAgregarJornadaOT(payload: {
  plan_semanal_id: string
  ot_id: string
  fecha: string
  responsable_id?: string
  horas_planificadas?: number
  avance_objetivo_pct?: number
  comentario?: string
}): Promise<RpcResult> {
  const { data, error } = await supabase.rpc('rpc_calama_agregar_jornada_ot', { p_payload: payload })
  return { data, error }
}

// ============================================================================
// MIG32: acciones administrativas
// ============================================================================

export type DesprogramarDestino = 'backlog' | 'requiere_reprogramacion' | 'desprogramada'
export type TipoCancelacion = 'operacional' | 'prueba' | 'mandante' | 'clima' | 'otro'
export type ModoResetPrueba =
  | 'mantener_programada' | 'devolver_backlog' | 'desprogramar' | 'eliminar_logico'

export async function rpcDesprogramarJornada(payload: {
  plan_semanal_ot_id: string
  motivo: string
  observacion?: string
  destino?: DesprogramarDestino
}): Promise<RpcResult> {
  const { data, error } = await supabase.rpc('rpc_calama_desprogramar_jornada', { p_payload: payload })
  return { data, error }
}

export async function rpcCancelarJornada(payload: {
  plan_semanal_ot_id: string
  motivo: string
  observacion?: string
  tipo_cancelacion?: TipoCancelacion
}): Promise<RpcResult> {
  const { data, error } = await supabase.rpc('rpc_calama_cancelar_jornada', { p_payload: payload })
  return { data, error }
}

export async function rpcResetearJornadaPrueba(payload: {
  plan_semanal_ot_id: string
  motivo: string
  modo: ModoResetPrueba
  confirmacion_texto: string  // debe ser 'RESET'
}): Promise<RpcResult> {
  const { data, error } = await supabase.rpc('rpc_calama_resetear_jornada_prueba', { p_payload: payload })
  return { data, error }
}

export async function rpcEliminarJornadaPrueba(payload: {
  plan_semanal_ot_id: string
  motivo: string
  confirmacion_texto: string  // debe ser 'ELIMINAR'
}): Promise<RpcResult> {
  const { data, error } = await supabase.rpc('rpc_calama_eliminar_jornada_prueba', { p_payload: payload })
  return { data, error }
}

export async function rpcRegistrarLlegadaFaena(payload: {
  plan_semanal_ot_id: string
  foto_llegada_url: string
  foto_llegada_storage_path: string
  observacion?: string
  client_uuid?: string
} & GeoFields): Promise<RpcResult> {
  const { data, error } = await supabase.rpc('rpc_calama_registrar_llegada_faena', { p_payload: payload })
  return { data, error }
}

// Ampliar uploadEvidenciaJornada para llegada (path ya soporta cualquier momento).
// La firma es la misma; solo cambia el momento que el caller envia.

// MIG33: estado completo de jornada para wizard movil multidispositivo.
export type EstadoJornadaServer = {
  plan_semanal_ot_id: string
  ot_id: string
  ot: { folio: string; titulo: string; avance_pct: number; estado: string; descripcion: string | null }
  estado_plan: string
  responsable_id: string | null
  llegada_faena_at: string | null
  llegada_tardia: boolean
  foto_antes_regularizada: boolean
  cierre_jornada_at: string | null
  ejecucion_activa: null | {
    id: string
    estado: 'en_ejecucion' | 'pausada'
    ejecutor_id: string
    ejecutor_email: string | null
    ejecutor_nombre: string | null
    iniciada_por_otro_usuario: boolean
    started_at: string
    last_event_at: string
    tiempo_total_segundos: number
    tiempo_efectivo_segundos: number
    tiempo_pausado_segundos: number
    tiempo_colacion_segundos: number
  }
  flags: {
    falta_llegada_faena: boolean
    falta_foto_antes: boolean
    falta_foto_despues: boolean
    falta_firma_operador: boolean
    pausa_activa: boolean
    puede_iniciar: boolean
    puede_reanudar: boolean
    puede_pausar: boolean
    puede_cerrar: boolean
    pausas_sin_foto: number
  }
}

export async function rpcObtenerEstadoJornada(planOtId: string): Promise<{ data: EstadoJornadaServer | null; error: unknown }> {
  const { data, error } = await supabase.rpc('rpc_calama_obtener_estado_jornada', { p_plan_ot_id: planOtId })
  return { data: (data as EstadoJornadaServer | null) ?? null, error }
}

export async function rpcRegularizarLlegadaFaena(payload: {
  plan_semanal_ot_id: string
  foto_llegada_url: string
  foto_llegada_storage_path: string
  motivo: string
  client_uuid?: string
} & GeoFields): Promise<RpcResult> {
  const { data, error } = await supabase.rpc('rpc_calama_regularizar_llegada_faena', { p_payload: payload })
  return { data, error }
}

export async function rpcRegistrarFotoAntesRegularizada(payload: {
  plan_semanal_ot_id: string
  foto_url: string
  foto_storage_path: string
  motivo: string
  client_uuid?: string
} & GeoFields): Promise<RpcResult> {
  const { data, error } = await supabase.rpc('rpc_calama_registrar_foto_antes_regularizada', { p_payload: payload })
  return { data, error }
}

// ============================================================================
// Lectura: firmas + rechazos + evidencias por plan_semanal_ot
// ============================================================================

export async function getFirmasJornada(planOtId: string) {
  const { data, error } = await supabase
    .from('calama_firmas_jornada')
    .select('*')
    .eq('plan_semanal_ot_id', planOtId)
    .order('created_at', { ascending: true })
  return { data: (data ?? []) as CalamaFirmaJornada[], error }
}

export async function getRechazosJornada(planOtId: string) {
  const { data, error } = await supabase
    .from('calama_rechazos_jornada')
    .select('*')
    .eq('plan_semanal_ot_id', planOtId)
    .order('created_at', { ascending: false })
  return { data: (data ?? []) as CalamaRechazoJornada[], error }
}

export async function getEvidenciasJornada(planOtId: string) {
  const { data, error } = await supabase
    .from('calama_evidencias')
    .select('*')
    .eq('plan_semanal_ot_id', planOtId)
    .order('created_at', { ascending: true })
  return { data: (data ?? []) as CalamaEvidenciaPro[], error }
}
