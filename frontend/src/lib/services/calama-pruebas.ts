import { supabase } from '@/lib/supabase'

// ── Tipos ───────────────────────────────────────────────────────────────────

export interface PruebaTerrenoRow {
  ot_id: string
  folio: string
  titulo: string
  ot_estado: string
  avance_pct: number
  fecha_programada: string
  responsable_id: string | null
  responsable_nombre: string | null
  responsable_email: string | null
  plan_semanal_ot_id: string | null
  estado_plan: string | null
  llegada_faena_at: string | null
  cierre_jornada_at: string | null
  created_at: string
  motivo_prueba: string | null
  planificacion_codigo: string | null
  faena_nombre: string | null
  evidencias_count: number
  eventos_count: number
  firmas_count: number
}

export interface CrearJornadaPruebaPayload {
  responsable_id?: string | null
  planificacion_id?: string | null
  faena_id?: string | null
  fecha_jornada?: string | null  // YYYY-MM-DD
}

export interface CrearJornadaPruebaResult {
  success: boolean
  ot_id: string
  folio: string
  plan_semanal_ot_id: string
  plan_semanal_id: string
  plan_dia_id: string
  fecha_jornada: string
  responsable_id: string
  zona_id: string
  planificacion_id: string
  url_mobile: string
  mensaje: string
}

// ── Queries ─────────────────────────────────────────────────────────────────

export async function listarPruebasTerreno() {
  const { data, error } = await supabase
    .from('v_calama_pruebas_terreno')
    .select('*')
    .order('created_at', { ascending: false })
  return { data: data as PruebaTerrenoRow[] | null, error }
}

export async function crearJornadaPrueba(payload: CrearJornadaPruebaPayload) {
  const { data, error } = await supabase.rpc('rpc_calama_crear_jornada_prueba_terreno', {
    p_payload: {
      responsable_id:   payload.responsable_id ?? null,
      planificacion_id: payload.planificacion_id ?? null,
      faena_id:         payload.faena_id ?? null,
      fecha_jornada:    payload.fecha_jornada ?? null,
    },
  })
  if (error) return { data: null, error }
  return { data: data as CrearJornadaPruebaResult, error: null }
}

// Helper para ver evidencias / eventos / firmas de una OT de prueba
export interface EvidenciaPruebaRow {
  id: string
  contexto: string
  momento: string
  tipo: string | null
  archivo_url: string | null
  storage_path: string | null
  descripcion: string | null
  sync_status: string | null
  client_uuid: string | null
  lat: number | null
  lng: number | null
  tomada_en: string | null
  created_at: string
}

export async function listarEvidenciasPrueba(otId: string) {
  const { data, error } = await supabase
    .from('calama_evidencias')
    .select('id, contexto, momento, tipo, archivo_url, storage_path, descripcion, sync_status, client_uuid, lat, lng, tomada_en, created_at')
    .eq('ot_id', otId)
    .eq('es_prueba', true)
    .order('created_at', { ascending: false })
  return { data: data as EvidenciaPruebaRow[] | null, error }
}

export interface EventoPruebaRow {
  id: string
  tipo: string
  motivo: string | null
  comentario: string | null
  avance: number | null
  created_at: string
}

export async function listarEventosPrueba(otId: string) {
  const { data, error } = await supabase
    .from('calama_ot_ejecucion_eventos')
    .select('id, tipo, motivo, comentario, avance, created_at')
    .eq('ot_id', otId)
    .eq('es_prueba', true)
    .order('created_at', { ascending: false })
  return { data: data as EventoPruebaRow[] | null, error }
}
