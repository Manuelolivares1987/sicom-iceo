import { supabase } from '@/lib/supabase'
import type {
  OrdenTrabajo,
  TipoOT,
  EstadoOT,
  Prioridad,
} from '@/types/database'
import type { Database } from '@/types/database'

// ── Filters ──────────────────────────────────────────────────────────

export interface OTFilters {
  tipo?: TipoOT
  estado?: EstadoOT
  faena_id?: string
  responsable_id?: string
  fecha_desde?: string
  fecha_hasta?: string
  prioridad?: Prioridad
}

// ── Select strings ───────────────────────────────────────────────────

const OT_LIST_SELECT = `
  *,
  activo:activos(id, codigo, nombre, tipo),
  faena:faenas(id, codigo, nombre),
  responsable:usuarios_perfil(id, nombre_completo, cargo)
`

const OT_DETAIL_SELECT = `
  *,
  activo:activos(*, modelo:modelos(*, marca:marcas(*))),
  faena:faenas(*),
  responsable:usuarios_perfil(id, nombre_completo, cargo, email)
`

// ── CRUD ─────────────────────────────────────────────────────────────

export async function getOrdenesTrabajo(filters?: OTFilters) {
  let query = supabase
    .from('ordenes_trabajo')
    .select(OT_LIST_SELECT)

  if (filters?.tipo) query = query.eq('tipo', filters.tipo)
  if (filters?.estado) query = query.eq('estado', filters.estado)
  if (filters?.faena_id) query = query.eq('faena_id', filters.faena_id)
  if (filters?.responsable_id) query = query.eq('responsable_id', filters.responsable_id)
  if (filters?.prioridad) query = query.eq('prioridad', filters.prioridad)
  if (filters?.fecha_desde) query = query.gte('fecha_programada', filters.fecha_desde)
  if (filters?.fecha_hasta) query = query.lte('fecha_programada', filters.fecha_hasta)

  const { data, error } = await query.order('fecha_programada', { ascending: false })

  return { data: data as OrdenTrabajo[] | null, error }
}

export async function getOrdenTrabajoById(id: string) {
  const { data, error } = await supabase
    .from('ordenes_trabajo')
    .select(OT_DETAIL_SELECT)
    .eq('id', id)
    .single()

  return { data: data as OrdenTrabajo | null, error }
}

export interface CreateOTParams {
  tipo: TipoOT
  contrato_id: string
  faena_id: string
  activo_id: string
  prioridad: Prioridad
  fecha_programada: string
  responsable_id: string
  plan_mantenimiento_id?: string | null
  usuario_id: string
}

export async function createOrdenTrabajo(params: CreateOTParams) {
  const { data, error } = await supabase.rpc('rpc_crear_ot', {
    p_tipo: params.tipo,
    p_contrato_id: params.contrato_id,
    p_faena_id: params.faena_id,
    p_activo_id: params.activo_id,
    p_prioridad: params.prioridad,
    p_fecha_programada: params.fecha_programada,
    p_responsable_id: params.responsable_id,
    p_plan_mantenimiento_id: params.plan_mantenimiento_id ?? null,
    p_usuario_id: params.usuario_id,
  })

  return { data, error }
}

export async function updateOrdenTrabajo(
  id: string,
  data: Database['public']['Tables']['ordenes_trabajo']['Update']
) {
  const { data: updated, error } = await supabase
    .from('ordenes_trabajo')
    .update(data)
    .eq('id', id)
    .select(OT_DETAIL_SELECT)
    .single()

  return { data: updated as OrdenTrabajo | null, error }
}

// ── State transitions (via RPC) ─────────────────────────────────────

export async function iniciarOT(id: string, userId: string) {
  const { data, error } = await supabase.rpc('rpc_transicion_ot', {
    p_ot_id: id,
    p_nuevo_estado: 'en_ejecucion',
    p_usuario_id: userId,
  })

  return { data, error }
}

export async function pausarOT(id: string, userId: string, motivo?: string) {
  const { data, error } = await supabase.rpc('rpc_transicion_ot', {
    p_ot_id: id,
    p_nuevo_estado: 'pausada',
    p_usuario_id: userId,
    p_observaciones: motivo ?? null,
  })

  return { data, error }
}

export async function finalizarOT(id: string, userId: string, observaciones?: string) {
  const { data, error } = await supabase.rpc('rpc_transicion_ot', {
    p_ot_id: id,
    p_nuevo_estado: 'ejecutada_ok',
    p_usuario_id: userId,
    p_observaciones: observaciones ?? null,
  })

  return { data, error }
}

export async function noEjecutarOT(
  id: string,
  userId: string,
  causa: string,
  detalle?: string
) {
  const { data, error } = await supabase.rpc('rpc_transicion_ot', {
    p_ot_id: id,
    p_nuevo_estado: 'no_ejecutada',
    p_usuario_id: userId,
    p_causa_no_ejecucion: causa,
    p_detalle_no_ejecucion: detalle ?? null,
  })

  return { data, error }
}

export async function cerrarOTSupervisor(id: string, supervisorId: string, observaciones?: string) {
  const { data, error } = await supabase.rpc('rpc_cerrar_ot_supervisor', {
    p_ot_id: id,
    p_supervisor_id: supervisorId,
    p_observaciones: observaciones ?? null,
  })

  return { data, error }
}

// ── Checklist ────────────────────────────────────────────────────────

export async function getChecklistOT(otId: string) {
  const { data, error } = await supabase
    .from('checklist_ot')
    .select('*')
    .eq('ot_id', otId)
    .order('orden')

  return { data, error }
}

export async function updateChecklistItem(
  id: string,
  completadoOrData: boolean | {
    resultado?: string
    observacion?: string | null
    foto_url?: string | null
    completado_en?: string
    completado_por?: string
  },
  observacion?: string
) {
  // Support both legacy (id, data) and hook (id, completado, observacion) call styles
  const data = typeof completadoOrData === 'boolean'
    ? {
        resultado: completadoOrData ? 'ok' : null,
        observacion: observacion ?? null,
        completado_en: completadoOrData ? new Date().toISOString() : null,
      }
    : completadoOrData
  const { data: updated, error } = await supabase
    .from('checklist_ot')
    .update(data)
    .eq('id', id)
    .select()
    .single()

  return { data: updated, error }
}

// ── Evidencias ───────────────────────────────────────────────────────

export async function addEvidenciaOT(
  otId: string,
  file: File,
  tipo: string,
  descripcion?: string
) {
  const fileExt = file.name.split('.').pop()
  const filePath = `${otId}/${Date.now()}.${fileExt}`

  const { error: uploadError } = await supabase.storage
    .from('evidencias-ot')
    .upload(filePath, file)

  if (uploadError) {
    return { data: null, error: uploadError }
  }

  const { data: { publicUrl } } = supabase.storage
    .from('evidencias-ot')
    .getPublicUrl(filePath)

  const { data: { user } } = await supabase.auth.getUser()

  const { data, error } = await supabase
    .from('evidencias_ot')
    .insert({
      ot_id: otId,
      tipo,
      archivo_url: publicUrl,
      descripcion: descripcion ?? null,
      created_by: user?.id ?? null,
    })
    .select()
    .single()

  return { data, error }
}

export async function getEvidenciasOT(otId: string) {
  const { data, error } = await supabase
    .from('evidencias_ot')
    .select('*')
    .eq('ot_id', otId)
    .order('created_at', { ascending: false })

  return { data, error }
}

// ── Materiales ───────────────────────────────────────────────────────

export async function getMaterialesOT(otId: string) {
  const { data, error } = await supabase
    .from('movimientos_inventario')
    .select('*, producto:productos(*)')
    .eq('ot_id', otId)
    .order('created_at', { ascending: false })

  return { data, error }
}

// ── Historial ────────────────────────────────────────────────────────

export async function getHistorialOT(otId: string) {
  const { data, error } = await supabase
    .from('historial_estado_ot')
    .select('*')
    .eq('ot_id', otId)
    .order('created_at', { ascending: true })

  return { data, error }
}

// ── Stats ────────────────────────────────────────────────────────────

export async function getOTsStats(faenaId?: string) {
  let query = supabase
    .from('ordenes_trabajo')
    .select('estado')

  if (faenaId) {
    query = query.eq('faena_id', faenaId)
  }

  const { data, error } = await query

  if (error || !data) {
    return { data: null, error }
  }

  const stats: Record<EstadoOT, number> = {
    creada: 0,
    asignada: 0,
    en_ejecucion: 0,
    pausada: 0,
    ejecutada_ok: 0,
    ejecutada_con_observaciones: 0,
    no_ejecutada: 0,
    cancelada: 0,
  }

  for (const row of data) {
    const estado = row.estado as EstadoOT
    if (estado in stats) {
      stats[estado]++
    }
  }

  return { data: stats, error: null }
}

// ── Aliases (used by hooks) ─────────────────────────────────────────

export const addEvidencia = addEvidenciaOT
