// Recursos (repuestos/materiales) que el operador de taller pide para reparar
// una OT y que el jefe valida antes de emitir el vale de bodega (MIG197).
import { supabase } from '@/lib/supabase'

export type OTRecursoEstado = 'solicitado' | 'aprobado' | 'rechazado' | 'en_vale'

export type OTRecurso = {
  id: string
  client_uuid: string | null
  ot_id: string
  producto_id: string | null
  /** Ítem NO OK del checklist que motivó el pedido (enlaza con la NC). MIG199. */
  instance_item_id: string | null
  descripcion: string | null
  unidad: string | null
  cantidad: number
  cantidad_aprobada: number | null
  comentario: string | null
  fotos: string[] | null
  estado: OTRecursoEstado
  solicitado_por: string | null
  solicitado_nombre: string | null
  agregado_por_jefe: boolean
  validado_por: string | null
  validado_at: string | null
  nota_jefe: string | null
  ticket_id: string | null
  created_at: string
  producto_codigo: string | null
  producto_nombre: string | null
  stock_total: number | null
  validado_por_nombre: string | null
  ticket_folio: string | null
  ticket_estado: string | null
}

export async function getRecursosOT(otId: string): Promise<OTRecurso[]> {
  const { data, error } = await supabase
    .from('v_ot_recursos').select('*')
    .eq('ot_id', otId)
    .order('created_at', { ascending: true })
  if (error) throw error
  return (data ?? []) as OTRecurso[]
}

export async function solicitarRecurso(params: {
  otId: string
  cantidad: number
  productoId?: string | null
  descripcion?: string | null
  unidad?: string | null
  comentario?: string | null
  solicitadoNombre?: string | null
  clientUuid?: string | null
  fotos?: string[] | null
  instanceItemId?: string | null
}) {
  const { data, error } = await supabase.rpc('rpc_ot_recurso_solicitar', {
    p_ot_id: params.otId, p_cantidad: params.cantidad,
    p_producto_id: params.productoId ?? null, p_descripcion: params.descripcion ?? null,
    p_unidad: params.unidad ?? null, p_comentario: params.comentario ?? null,
    p_solicitado_nombre: params.solicitadoNombre ?? null,
    p_client_uuid: params.clientUuid ?? null,
    p_fotos: params.fotos && params.fotos.length > 0 ? params.fotos : null,
    p_instance_item_id: params.instanceItemId ?? null,
  })
  if (error) throw error
  return data as { success: boolean; recurso_id: string; duplicado?: boolean }
}

/** Sube una foto del repuesto solicitado (mismo bucket de evidencias del checklist). */
export async function subirFotoRecurso(otId: string, file: File | Blob): Promise<string> {
  const BUCKET = 'evidencias-verificacion'
  const ext = (file as File).name?.split('.').pop()?.toLowerCase() ?? 'jpg'
  const path = `ot-recursos/${otId}/${Date.now()}_${Math.floor(Math.random() * 1e6)}.${ext}`
  const { error } = await supabase.storage
    .from(BUCKET)
    .upload(path, file, { upsert: false, contentType: (file as File).type || 'image/jpeg' })
  if (error) throw error
  return supabase.storage.from(BUCKET).getPublicUrl(path).data.publicUrl
}

export async function validarRecurso(params: {
  recursoId: string
  accion: 'aprobar' | 'rechazar'
  cantidadAprobada?: number | null
  nota?: string | null
}) {
  const { data, error } = await supabase.rpc('rpc_ot_recurso_validar', {
    p_recurso_id: params.recursoId, p_accion: params.accion,
    p_cantidad_aprobada: params.cantidadAprobada ?? null, p_nota: params.nota ?? null,
  })
  if (error) throw error
  return data as { success: boolean; recurso_id: string; estado: OTRecursoEstado }
}

export async function agregarRecursoJefe(params: {
  otId: string
  cantidad: number
  productoId?: string | null
  descripcion?: string | null
  unidad?: string | null
  comentario?: string | null
}) {
  const { data, error } = await supabase.rpc('rpc_ot_recurso_agregar', {
    p_ot_id: params.otId, p_cantidad: params.cantidad,
    p_producto_id: params.productoId ?? null, p_descripcion: params.descripcion ?? null,
    p_unidad: params.unidad ?? null, p_comentario: params.comentario ?? null,
  })
  if (error) throw error
  return data as { success: boolean; recurso_id: string }
}

export const RECURSO_ESTADO_LABEL: Record<OTRecursoEstado, { label: string; cls: string }> = {
  solicitado: { label: 'Por validar', cls: 'bg-amber-100 text-amber-800' },
  aprobado:   { label: 'Aprobado',    cls: 'bg-green-100 text-green-700' },
  rechazado:  { label: 'Rechazado',   cls: 'bg-red-100 text-red-700' },
  en_vale:    { label: 'En vale',     cls: 'bg-blue-100 text-blue-700' },
}
