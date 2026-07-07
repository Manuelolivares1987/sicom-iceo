// Recursos (repuestos/materiales) que el operador de taller pide para reparar
// una OT y que el jefe valida antes de emitir el vale de bodega (MIG197).
import { supabase } from '@/lib/supabase'

export type OTRecursoEstado = 'solicitado' | 'aprobado' | 'rechazado' | 'en_compra' | 'recibido' | 'en_vale'

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
  // Seguimiento de compra (MIG201)
  oc_id: string | null
  oc_item_id: string | null
  oc_numero: string | null
  /** N° de la OC oficial emitida por el área especialista en Softland. */
  oc_numero_externo: string | null
  oc_estado: string | null
  oc_fecha_entrega: string | null
  oc_proveedor: string | null
  oc_cantidad_recibida: number | null
}

/** Fila del tablero de seguimiento (v_ot_recursos_seguimiento). */
export type OTRecursoSeguimiento = OTRecurso & {
  ot_folio: string
  activo_codigo: string | null
  activo_patente: string | null
  activo_nombre: string | null
  dias_desde_solicitud: number
  /** Aprobado, sin OC y sin stock (o fuera de catálogo): hay que comprarlo. */
  por_comprar: boolean
}

export async function getSeguimientoRecursos(): Promise<OTRecursoSeguimiento[]> {
  const { data, error } = await supabase
    .from('v_ot_recursos_seguimiento').select('*')
    .order('created_at', { ascending: false })
    .limit(500)
  if (error) throw error
  return (data ?? []) as OTRecursoSeguimiento[]
}

export async function asignarProductoRecurso(recursoId: string, productoId: string) {
  const { data, error } = await supabase.rpc('rpc_ot_recurso_asignar_producto', {
    p_recurso_id: recursoId, p_producto_id: productoId,
  })
  if (error) throw error
  return data as { success: boolean }
}

export async function crearProductoRapido(params: {
  nombre: string; categoria?: string; unidad?: string; codigo?: string | null
}) {
  const { data, error } = await supabase.rpc('rpc_producto_rapido', {
    p_nombre: params.nombre, p_categoria: params.categoria ?? 'repuesto',
    p_unidad: params.unidad ?? 'unidad', p_codigo: params.codigo ?? null,
  })
  if (error) throw error
  return data as { success: boolean; producto_id: string; codigo: string }
}

/** Registra el N° de la OC oficial emitida en Softland. */
export async function registrarNumeroOcExterno(ocId: string, numero: string) {
  const { data, error } = await supabase.rpc('rpc_oc_registrar_numero_externo', {
    p_oc_id: ocId, p_numero: numero,
  })
  if (error) throw error
  return data as { success: boolean }
}

export async function generarOcRecursos(params: {
  recursoIds: string[]; proveedorId: string
  numeroOc?: string | null; fechaEntrega?: string | null; observacion?: string | null
}) {
  const { data, error } = await supabase.rpc('rpc_ot_recursos_generar_oc', {
    p_recurso_ids: params.recursoIds, p_proveedor_id: params.proveedorId,
    p_numero_oc: params.numeroOc ?? null, p_fecha_entrega: params.fechaEntrega ?? null,
    p_observacion: params.observacion ?? null,
  })
  if (error) throw error
  return data as { success: boolean; orden_compra_id: string; numero_oc: string; items: number }
}

/** Insumos que el operador pidió desde un hallazgo NO OK (para la NC). */
export async function getRecursosPorHallazgo(instanceItemId: string): Promise<OTRecurso[]> {
  const { data, error } = await supabase
    .from('v_ot_recursos').select('*')
    .eq('instance_item_id', instanceItemId)
    .order('created_at', { ascending: true })
  if (error) throw error
  return (data ?? []) as OTRecurso[]
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
  /** Hallazgo NO OK al que se amarra el ítem (p.ej. al agregar desde la NC). */
  instanceItemId?: string | null
}) {
  const { data, error } = await supabase.rpc('rpc_ot_recurso_agregar', {
    p_ot_id: params.otId, p_cantidad: params.cantidad,
    p_producto_id: params.productoId ?? null, p_descripcion: params.descripcion ?? null,
    p_unidad: params.unidad ?? null, p_comentario: params.comentario ?? null,
    p_instance_item_id: params.instanceItemId ?? null,
  })
  if (error) throw error
  return data as { success: boolean; recurso_id: string }
}

export const RECURSO_ESTADO_LABEL: Record<OTRecursoEstado, { label: string; cls: string }> = {
  solicitado: { label: 'Por validar', cls: 'bg-amber-100 text-amber-800' },
  aprobado:   { label: 'Aprobado',    cls: 'bg-green-100 text-green-700' },
  rechazado:  { label: 'Rechazado',   cls: 'bg-red-100 text-red-700' },
  en_compra:  { label: 'OC solicitada', cls: 'bg-purple-100 text-purple-700' },
  recibido:   { label: 'Recibido — por entregar', cls: 'bg-teal-100 text-teal-700' },
  en_vale:    { label: 'En vale',     cls: 'bg-blue-100 text-blue-700' },
}
