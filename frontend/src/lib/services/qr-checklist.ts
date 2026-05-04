// ============================================================================
// Servicio QR Checklist + Mantencion. Wrapper de las RPCs del backend.
// Pattern del proyecto: funciones async retornan { data, error }.
// ============================================================================

import { supabase } from '@/lib/supabase'
import type {
  ChecklistPayload,
  GuardarChecklistResponse,
  QrChecklistRpcResponse,
} from '@/lib/offline/qr-checklist-types'

// ── 1. RPCs publicas (anon + authenticated) ─────────────────────────

export async function obtenerChecklistPublicoPorQR(activoId: string) {
  const { data, error } = await supabase.rpc('rpc_obtener_checklist_publico_por_qr', {
    p_activo_id: activoId,
  })
  return { data: data as QrChecklistRpcResponse | null, error }
}

export async function guardarChecklistPublico(payload: ChecklistPayload) {
  const { data, error } = await supabase.rpc('rpc_guardar_checklist_publico', {
    p_payload: payload,
  })
  return { data: data as GuardarChecklistResponse | null, error }
}

// ── 2. RPCs autenticadas (rol mantencion) ───────────────────────────

export async function obtenerHistorialMantencionActivo(activoId: string) {
  const { data, error } = await supabase.rpc('rpc_historial_mantencion_activo', {
    p_activo_id: activoId,
  })
  return { data, error }
}

export interface RegistrarMantencionPayload {
  activo_id: string
  ot_id?: string | null
  tipo: 'preventiva' | 'correctiva' | 'inspeccion' | 'lubricacion' | 'otro'
  fecha?: string
  kilometraje_al_momento?: number | null
  horometro_al_momento?: number | null
  descripcion: string
  repuestos_usados?: Array<Record<string, unknown>>
  costo_total?: number | null
  observaciones?: string | null
  alertas_resueltas?: string[]
}

export async function registrarMantencionPreventiva(payload: RegistrarMantencionPayload) {
  const { data, error } = await supabase.rpc('rpc_registrar_mantencion_preventiva', {
    p_payload: payload,
  })
  return { data, error }
}

export async function marcarChecklistRevisado(
  respuestaId: string,
  estadoRevision: 'validado' | 'requiere_reinspeccion' | 'sin_hallazgo' | 'escalado',
  observacion?: string | null
) {
  const { data, error } = await supabase.rpc('rpc_marcar_checklist_revisado', {
    p_respuesta_id: respuestaId,
    p_estado_revision: estadoRevision,
    p_observacion: observacion ?? null,
  })
  return { data, error }
}

export async function revisarAlertaCalidad(
  alertaId: string,
  nuevoEstado: 'en_revision' | 'confirmada' | 'descartada',
  accion: string
) {
  const { data, error } = await supabase.rpc('rpc_revisar_alerta_calidad', {
    p_alerta_id: alertaId,
    p_nuevo_estado: nuevoEstado,
    p_accion: accion,
  })
  return { data, error }
}

export async function cerrarAlertaTemprana(alertaId: string, accion: string) {
  const { data, error } = await supabase.rpc('rpc_cerrar_alerta_temprana', {
    p_alerta_id: alertaId,
    p_accion: accion,
  })
  return { data, error }
}

// ── 3. Upload de evidencias a Storage ───────────────────────────────
// Bucket esperado: 'documentos' (existe segun activos.ts).
// Path: 'qr-checklist/<cliente_uuid>/<codigo_item>_<ts>.<ext>'
// Si la operacion falla (ej. policy de Storage no permite anon), retorna
// error pero NO bloquea el flujo — el caller decide.

export async function uploadEvidenciaChecklist(
  clienteUuid: string,
  codigoItem: string,
  blob: Blob,
  mime?: string
) {
  const ext = (mime || blob.type || 'image/jpeg').split('/')[1] || 'jpg'
  const ts = Date.now()
  const path = `qr-checklist/${clienteUuid}/${codigoItem}_${ts}.${ext}`

  const { error: uploadError } = await supabase.storage
    .from('documentos')
    .upload(path, blob, {
      cacheControl: '3600',
      upsert: false,
      contentType: blob.type || mime || 'image/jpeg',
    })

  if (uploadError) {
    return { data: null, error: uploadError }
  }

  const { data: { publicUrl } } = supabase.storage
    .from('documentos')
    .getPublicUrl(path)

  return { data: { url: publicUrl, path }, error: null }
}

// ── 4. Helper: detectar conexion ────────────────────────────────────
export function isOnline(): boolean {
  if (typeof navigator === 'undefined') return true
  return navigator.onLine
}
