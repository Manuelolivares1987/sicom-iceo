import { supabase } from '@/lib/supabase'

// Notas con foto del operador como anexo de la OT (MIG249). Se guardan en
// evidencias_ot con tipo='nota'; el jefe las ve en la pestaña Evidencias.

export type OTNota = {
  id: string
  ot_id: string
  texto: string
  fotos: string[]
  autor: string | null
  origen: string | null
  created_at: string
  client_uuid?: string | null
}

/** Notas (tipo='nota') de una OT, más recientes primero. */
export async function getNotasOT(otId: string): Promise<OTNota[]> {
  const { data, error } = await supabase
    .from('evidencias_ot')
    .select('id, ot_id, descripcion, archivo_url, metadata, created_at')
    .eq('ot_id', otId)
    .eq('tipo', 'nota')
    .order('created_at', { ascending: false })
  if (error) throw error
  return (data ?? []).map(mapNota)
}

/** Notas de VARIAS OT (bandeja NC: el jefe ve los anexos de todo el equipo). */
export async function getNotasOTs(otIds: string[]): Promise<OTNota[]> {
  const ids = Array.from(new Set(otIds.filter(Boolean)))
  if (ids.length === 0) return []
  const { data, error } = await supabase
    .from('evidencias_ot')
    .select('id, ot_id, descripcion, archivo_url, metadata, created_at')
    .in('ot_id', ids)
    .eq('tipo', 'nota')
    .order('created_at', { ascending: false })
  if (error) throw error
  return (data ?? []).map(mapNota)
}

function mapNota(r: any): OTNota {
  const meta = (r.metadata ?? {}) as Record<string, unknown>
  const fotos = Array.isArray(meta.fotos) ? (meta.fotos as string[]).filter(Boolean) : []
  return {
    id: r.id,
    ot_id: r.ot_id,
    texto: r.descripcion ?? '',
    fotos: fotos.length ? fotos : (r.archivo_url ? [r.archivo_url] : []),
    autor: (meta.autor as string) ?? null,
    origen: (meta.origen as string) ?? null,
    created_at: r.created_at,
    client_uuid: (meta.client_uuid as string) ?? null,
  }
}

/** Sube una foto de la nota (mismo bucket de evidencias del checklist). */
export async function subirFotoNota(otId: string, file: File | Blob): Promise<string> {
  const BUCKET = 'evidencias-verificacion'
  const ext = (file as File).name?.split('.').pop()?.toLowerCase() ?? 'jpg'
  const path = `ot-notas/${otId}/${Date.now()}_${Math.floor(Math.random() * 1e6)}.${ext}`
  const { error } = await supabase.storage
    .from(BUCKET)
    .upload(path, file, { upsert: false, contentType: (file as File).type || 'image/jpeg' })
  if (error) throw error
  return supabase.storage.from(BUCKET).getPublicUrl(path).data.publicUrl
}

/** Agrega una nota vía RPC SECURITY DEFINER (idempotente por client_uuid). */
export async function agregarNotaOT(params: {
  otId: string
  texto: string
  fotos?: string[]
  autor?: string | null
  clientUuid?: string | null
}) {
  const { data, error } = await supabase.rpc('rpc_ot_nota_agregar', {
    p_ot_id: params.otId,
    p_texto: params.texto,
    p_fotos: params.fotos ?? [],
    p_autor: params.autor ?? null,
    p_client_uuid: params.clientUuid ?? null,
  })
  if (error) throw error
  return data as { ok: boolean; id: string; duplicado?: boolean }
}
