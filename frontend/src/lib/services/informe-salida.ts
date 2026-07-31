import { supabase } from '@/lib/supabase'
import { EVIDENCIAS_BUCKET } from '@/lib/services/verificacion'

// ============================================================================
// Informe de Salida a Arriendo (MIG263)
// ----------------------------------------------------------------------------
// La auditoría de calidad es la que libera el equipo a arriendo. Con MIG263
// deja además un documento: el informe que acompaña al camión, con la foto de
// cada punto revisado y de cada hallazgo.
// ============================================================================

/** Sube la evidencia de un ítem de auditoría y devuelve su URL pública. */
export async function subirFotoItemAuditoria(
  auditoriaId: string,
  itemId: string,
  file: File | Blob,
): Promise<string> {
  const ext = file instanceof File ? (file.name.split('.').pop() || 'jpg') : 'jpg'
  // El nombre lleva timestamp: reemplazar una foto no debe quedar tapado por la
  // caché del navegador con la imagen anterior.
  const path = `auditoria/${auditoriaId}/${itemId}-${Date.now()}.${ext}`
  const { error } = await supabase.storage
    .from(EVIDENCIAS_BUCKET)
    .upload(path, file, { upsert: true, contentType: (file as File).type || 'image/jpeg' })
  if (error) throw error
  const { data } = supabase.storage.from(EVIDENCIAS_BUCKET).getPublicUrl(path)
  return data.publicUrl
}

export type EvidenciaFaltante = { item_id: string; descripcion: string; motivo: string }

/** Puntos que no pueden quedar sin foto: los NO OK y los que el checklist exige. */
export async function getEvidenciaFaltante(auditoriaId: string): Promise<EvidenciaFaltante[]> {
  const { data, error } = await supabase.rpc('fn_auditoria_evidencia_faltante', {
    p_auditoria_id: auditoriaId,
  })
  if (error) throw error
  return (data ?? []) as EvidenciaFaltante[]
}

export type InformeSalidaItem = {
  descripcion: string
  resultado: 'ok' | 'no_ok' | 'na' | 'pendiente'
  observacion: string | null
  foto_url: string | null
  critico: boolean
  aplica_tipo: boolean
}

export type InformeSalida = {
  auditoria_id: string
  folio: string | null
  resultado: string
  fecha: string
  vigente_hasta: string | null
  dias_vigencia: number | null
  observaciones: string | null
  motivo_rechazo: string | null
  puntaje: number | null
  calidad_tecnica_ok: boolean | null
  documentacion_ok: boolean | null
  auditor: { nombre: string | null; firma_url: string | null }
  equipo: {
    id: string; patente: string | null; codigo: string | null; nombre: string | null
    tipo: string | null; tipo_equipamiento: string | null
    marca: string | null; modelo: string | null; anio: number | null
    kilometraje: number | null; horas_uso: number | null
    cliente: string | null; contrato: string | null; faena: string | null
  }
  resumen: { total: number; ok: number; no_ok: number; na: number }
  bloques: Array<{ bloque: string; orden: string; categoria: string; items: InformeSalidaItem[] }>
  hallazgos: Array<{ descripcion: string; observacion: string | null; foto_url: string | null; critico: boolean; bloque: string | null }>
  pendientes: Array<{ descripcion: string; sistema: string | null; severidad: string; diferible: boolean; plazo: string | null; estado: string }>
  documentos: Array<{ tipo: string; numero: string | null; entidad: string | null; vence: string | null; estado: string; bloqueante: boolean }>
}

export async function getInformeSalida(auditoriaId: string): Promise<InformeSalida> {
  const { data, error } = await supabase.rpc('fn_informe_salida_arriendo', {
    p_auditoria_id: auditoriaId,
  })
  if (error) throw error
  return data as InformeSalida
}

export type InformeSalidaResumen = {
  auditoria_id: string; folio: string; activo_id: string
  patente: string | null; codigo: string | null
  resultado: string; fecha_auditoria: string; vigente_hasta: string | null
  vigente: boolean; puntaje: number | null
  items_total: number; items_ok: number; items_no_ok: number; items_na: number
  fotos: number; auditor: string | null
}

export async function getInformesSalida(limit = 20): Promise<InformeSalidaResumen[]> {
  const { data, error } = await supabase
    .from('v_informes_salida_arriendo').select('*').limit(limit)
  if (error) throw error
  return (data ?? []) as InformeSalidaResumen[]
}
