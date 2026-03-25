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
  responsable:usuario_perfiles(id, nombre_completo, cargo)
`

const OT_DETAIL_SELECT = `
  *,
  activo:activos(*, modelo:modelos(*, marca:marcas(*))),
  faena:faenas(*),
  responsable:usuario_perfiles(id, nombre_completo, cargo, email)
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

export async function createOrdenTrabajo(
  data: Database['public']['Tables']['ordenes_trabajo']['Insert']
) {
  const { data: created, error } = await supabase
    .from('ordenes_trabajo')
    .insert(data)
    .select(OT_DETAIL_SELECT)
    .single()

  return { data: created as OrdenTrabajo | null, error }
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

// ── State transitions ────────────────────────────────────────────────

export async function iniciarOT(id: string) {
  return updateOrdenTrabajo(id, {
    estado: 'en_ejecucion',
    fecha_inicio: new Date().toISOString(),
  })
}

export async function pausarOT(id: string, motivo?: string) {
  return updateOrdenTrabajo(id, {
    estado: 'pausada',
    ...(motivo ? { observaciones: motivo } : {}),
  })
}

export async function finalizarOT(id: string, observaciones?: string) {
  const estado: EstadoOT = observaciones
    ? 'ejecutada_con_observaciones'
    : 'ejecutada_ok'

  return updateOrdenTrabajo(id, {
    estado,
    fecha_termino: new Date().toISOString(),
    observaciones: observaciones ?? null,
  })
}

export async function noEjecutarOT(
  id: string,
  causa: string,
  detalle?: string
) {
  if (!causa) {
    return {
      data: null,
      error: { message: 'La causa de no ejecucion es obligatoria', details: '', hint: '', code: 'VALIDATION' },
    }
  }

  return updateOrdenTrabajo(id, {
    estado: 'no_ejecutada',
    causa_no_ejecucion: causa,
    detalle_no_ejecucion: detalle ?? null,
  })
}

export async function cerrarOTSupervisor(id: string, observaciones?: string) {
  const { data: { user } } = await supabase.auth.getUser()

  return updateOrdenTrabajo(id, {
    fecha_cierre_supervisor: new Date().toISOString(),
    supervisor_cierre_id: user?.id ?? null,
    observaciones_supervisor: observaciones ?? null,
  })
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
      subido_por: user?.id ?? null,
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
