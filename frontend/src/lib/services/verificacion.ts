import { supabase } from '@/lib/supabase'

// ── Tipos ────────────────────────────────────────────────

export type ResultadoVerificacion = 'pendiente' | 'aprobado' | 'rechazado'

export interface VerificacionDisponibilidad {
  id: string
  activo_id: string
  ot_id: string | null
  contrato_id: string | null
  resultado: ResultadoVerificacion
  puntaje_total: number | null
  items_total: number | null
  items_ok: number | null
  items_no_ok: number | null
  items_na: number | null
  fecha_verificacion: string | null
  vigente_hasta: string | null
  dias_vigencia: number
  verificado_por: string | null
  aprobado_por: string | null
  aprobado_en: string | null
  motivo_rechazo: string | null
  horometro_inicial: number | null
  horometro_final: number | null
  km_inicial: number | null
  km_final: number | null
  road_test_minutos: number | null
  road_test_observacion: string | null
  evidencias_fotos: unknown
  firma_tecnico_url: string | null
  firma_aprobador_url: string | null
  created_at: string
  updated_at: string
}

export interface ChecklistItemOT {
  id: string
  ot_id: string
  orden: number
  descripcion: string
  obligatorio: boolean
  requiere_foto: boolean
  resultado: 'ok' | 'no_ok' | 'na' | null
  observacion: string | null
  foto_url: string | null
  completado_por: string | null
  completado_en: string | null
  seccion?: string | null
}

export interface VerificacionPendiente {
  verificacion_id: string
  activo_id: string
  patente: string
  codigo: string | null
  equipo: string | null
  ot_id: string
  ot_folio: string
  ot_estado: string
  resultado: ResultadoVerificacion
  verificado_por: string | null
  tecnico_nombre: string | null
  created_at: string
  fecha_verificacion: string | null
  checklist_progreso: {
    total: number
    ok: number
    no_ok: number
    na: number
    pendientes: number
  } | null
}

// ── RPCs ─────────────────────────────────────────────────

export async function iniciarVerificacion(activoId: string, motivo?: string) {
  const { data, error } = await supabase.rpc('fn_iniciar_verificacion_disponibilidad', {
    p_activo_id: activoId,
    p_motivo: motivo ?? null,
  })
  return {
    data: data as { success: boolean; ot_id: string; ot_folio: string; patente: string } | null,
    error,
  }
}

export interface AprobarVerificacionParams {
  ot_id: string
  horometro_inicial: number
  horometro_final: number
  km_inicial?: number | null
  km_final?: number | null
  road_test_minutos: number
  road_test_observacion?: string | null
  firma_tecnico_url?: string | null
  firma_aprobador_url?: string | null
  dias_vigencia?: number
}

export async function aprobarVerificacion(params: AprobarVerificacionParams) {
  const { data, error } = await supabase.rpc('fn_aprobar_verificacion_disponibilidad', {
    p_ot_id: params.ot_id,
    p_horometro_inicial: params.horometro_inicial,
    p_horometro_final: params.horometro_final,
    p_km_inicial: params.km_inicial ?? null,
    p_km_final: params.km_final ?? null,
    p_road_test_minutos: params.road_test_minutos,
    p_road_test_observacion: params.road_test_observacion ?? null,
    p_firma_tecnico_url: params.firma_tecnico_url ?? null,
    p_firma_aprobador_url: params.firma_aprobador_url ?? null,
    p_dias_vigencia: params.dias_vigencia ?? 3,
  })
  return {
    data: data as {
      success: boolean
      verificacion_id: string
      activo_id: string
      vigente_hasta: string
    } | null,
    error,
  }
}

// ── Lectura ──────────────────────────────────────────────

export async function getVerificacionPorOT(otId: string) {
  const { data, error } = await supabase
    .from('verificaciones_disponibilidad')
    .select('*')
    .eq('ot_id', otId)
    .maybeSingle()
  return { data: data as VerificacionDisponibilidad | null, error }
}

export async function getChecklistOT(otId: string) {
  const { data, error } = await supabase
    .from('checklist_ot')
    .select('*')
    .eq('ot_id', otId)
    .order('orden')
  return { data: data as ChecklistItemOT[] | null, error }
}

export async function updateChecklistItem(
  itemId: string,
  patch: {
    resultado?: 'ok' | 'no_ok' | 'na' | null
    observacion?: string | null
    foto_url?: string | null
  },
) {
  const update: Record<string, unknown> = { ...patch }
  if (patch.resultado !== undefined) {
    update.completado_en = patch.resultado ? new Date().toISOString() : null
  }
  const { data, error } = await supabase
    .from('checklist_ot')
    .update(update)
    .eq('id', itemId)
    .select()
    .single()
  return { data, error }
}

export async function getVerificacionesPendientes() {
  const { data, error } = await supabase
    .from('v_verificaciones_pendientes')
    .select('*')
    .order('created_at', { ascending: false })
  return { data: data as VerificacionPendiente[] | null, error }
}

export async function getVerificacionActivoVigente(activoId: string) {
  const { data, error } = await supabase
    .from('verificaciones_disponibilidad')
    .select('*')
    .eq('activo_id', activoId)
    .eq('resultado', 'aprobado')
    .gte('vigente_hasta', new Date().toISOString())
    .order('vigente_hasta', { ascending: false })
    .limit(1)
    .maybeSingle()
  return { data: data as VerificacionDisponibilidad | null, error }
}

// ── Upload de evidencias a Storage ───────────────────────

export const EVIDENCIAS_BUCKET = 'evidencias-verificacion'

export async function subirEvidenciaItem(
  otId: string,
  itemId: string,
  file: File | Blob,
) {
  const ext =
    file instanceof File ? file.name.split('.').pop() || 'jpg' : 'png'
  const path = `${otId}/checklist/${itemId}.${ext}`
  const { error: upErr } = await supabase.storage
    .from(EVIDENCIAS_BUCKET)
    .upload(path, file, { upsert: true, contentType: (file as File).type || 'image/jpeg' })
  if (upErr) return { data: null, error: upErr }
  const { data } = supabase.storage.from(EVIDENCIAS_BUCKET).getPublicUrl(path)
  return { data: data.publicUrl, error: null }
}

// Sube una firma PNG (canvas dataURL) al storage
export async function subirFirma(
  otId: string,
  quien: 'tecnico' | 'aprobador',
  dataUrl: string,
) {
  // dataURL -> Blob
  const res = await fetch(dataUrl)
  const blob = await res.blob()
  const path = `${otId}/firma-${quien}.png`
  const { error: upErr } = await supabase.storage
    .from(EVIDENCIAS_BUCKET)
    .upload(path, blob, { upsert: true, contentType: 'image/png' })
  if (upErr) return { data: null, error: upErr }
  const { data } = supabase.storage.from(EVIDENCIAS_BUCKET).getPublicUrl(path)
  return { data: data.publicUrl, error: null }
}
