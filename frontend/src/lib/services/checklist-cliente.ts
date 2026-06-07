import { supabase } from '@/lib/supabase'

// ============================================================================
// Checklist semanal del CLIENTE (publico por QR) — MIG 127.
// Flujo anonimo: RPCs SECURITY DEFINER + storage bajo 'checklist-cliente/'.
// ============================================================================

export type ChecklistClienteItemTpl = {
  orden: number
  categoria: string
  descripcion: string
  obligatorio: boolean
  requiere_foto_si_falla: boolean
}

export type ChecklistClienteActivo = {
  id: string
  codigo: string | null
  patente: string | null
  nombre: string | null
  cliente: string | null
  contrato_id: string | null
  contrato_codigo: string | null
  estado_comercial: string | null
}

// ── Publico (anon) ──────────────────────────────────────────────────────────

export async function getChecklistCliente(activoId: string) {
  const { data, error } = await supabase.rpc('rpc_checklist_cliente_obtener', { p_activo_id: activoId })
  return { data: data as { activo?: ChecklistClienteActivo; items?: ChecklistClienteItemTpl[]; error?: string } | null, error }
}

export async function guardarChecklistCliente(payload: Record<string, unknown>) {
  const { data, error } = await supabase.rpc('rpc_checklist_cliente_guardar', { p_payload: payload })
  return { data, error }
}

function dataUrlToBlob(dataUrl: string): Blob {
  const [head, body] = dataUrl.split(',')
  const mime = head.match(/:(.*?);/)?.[1] ?? 'image/png'
  const bin = atob(body)
  const u8 = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) u8[i] = bin.charCodeAt(i)
  return new Blob([u8], { type: mime })
}

/** Sube una foto/firma bajo el prefijo 'checklist-cliente/' (anon permitido). */
export async function subirEvidenciaChecklistCliente(activoId: string, key: string, blobOrDataUrl: Blob | string) {
  const blob = typeof blobOrDataUrl === 'string' ? dataUrlToBlob(blobOrDataUrl) : blobOrDataUrl
  const ext = (blob.type || 'image/jpeg').split('/')[1] || 'jpg'
  const ts = typeof window !== 'undefined' ? Date.now() : 0
  const path = `checklist-cliente/${activoId}/${key}_${ts}.${ext}`
  const { error } = await supabase.storage.from('documentos').upload(path, blob, {
    cacheControl: '3600', upsert: false, contentType: blob.type || 'image/jpeg',
  })
  if (error) return { data: null, error }
  const { data } = supabase.storage.from('documentos').getPublicUrl(path)
  return { data: data.publicUrl, error: null }
}

// ── Compania (autenticado) ──────────────────────────────────────────────────

export async function getCumplimientoCliente() {
  const { data, error } = await supabase
    .from('v_checklist_cliente_cumplimiento')
    .select('*')
    .order('estado_cumplimiento', { ascending: true })
    .order('dias_desde_ultimo', { ascending: false, nullsFirst: true })
  return { data, error }
}

export async function getChecklistClienteDetalle(id: string) {
  const [{ data: header, error: e1 }, { data: items, error: e2 }] = await Promise.all([
    supabase.from('checklist_cliente_semanal').select('*').eq('id', id).single(),
    supabase.from('checklist_cliente_semanal_items').select('*').eq('checklist_id', id).order('orden'),
  ])
  return { data: { header, items: items ?? [] }, error: e1 || e2 }
}

export async function getUltimoChecklistClientePorActivo(activoId: string) {
  const { data, error } = await supabase
    .from('checklist_cliente_semanal')
    .select('*')
    .eq('activo_id', activoId)
    .order('fecha', { ascending: false })
    .limit(1)
    .maybeSingle()
  return { data, error }
}

export async function generarOtDesdeChecklistCliente(checklistId: string) {
  const { data, error } = await supabase.rpc('fn_generar_ot_desde_checklist_cliente', { p_checklist_id: checklistId })
  return { data, error }
}
