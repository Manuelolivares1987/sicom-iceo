import { supabase } from '@/lib/supabase'

// ============================================================================
// No Conformidades de Recepción (MIG 138). Bandeja del Jefe de Taller:
// ver NC → asignar recursos (grupo + horas + tiempo + materiales) → planificar.
// ============================================================================

export type NcRecepcion = {
  id: string
  activo_id: string
  patente: string | null
  codigo: string | null
  equipo: string | null
  descripcion: string
  severidad: 'baja' | 'media' | 'alta' | 'critica'
  origen: string
  estado_planificacion: 'registrada' | 'con_recursos' | 'planificada' | 'en_ejecucion' | 'resuelta' | 'descartada'
  grupo_trabajo: string | null
  horas_estimadas: number | null
  tiempo_estimado_dias: number | null
  informe_recepcion_id: string | null
  plan_ot_id: string | null
  resuelto: boolean
  n_materiales: number
  created_at: string
  ot_id: string | null
  foto_url: string | null
  checklist_item_ref: string | null
  /** Insumos que el operador pidió desde el hallazgo NO OK (MIG199). */
  n_recursos_operador: number
}

export type NcMaterial = { descripcion?: string | null; producto_id?: string | null; cantidad: number; comentario?: string | null }

export async function getNcRecepcion(estado?: string): Promise<NcRecepcion[]> {
  let q = supabase.from('v_nc_recepcion').select('*').order('created_at', { ascending: false })
  if (estado) q = q.eq('estado_planificacion', estado)
  const { data, error } = await q
  if (error) throw error
  return (data ?? []) as NcRecepcion[]
}

export async function getNcMateriales(ncId: string) {
  const { data, error } = await supabase
    .from('nc_materiales').select('*').eq('no_conformidad_id', ncId)
  if (error) throw error
  return data ?? []
}

export async function asignarRecursosNc(p: {
  ncId: string; grupo?: string | null; horas?: number | null; tiempoDias?: number | null; materiales: NcMaterial[]
}) {
  const { data, error } = await supabase.rpc('fn_asignar_recursos_nc', {
    p_nc_id: p.ncId,
    p_grupo_trabajo: p.grupo ?? null,
    p_horas: p.horas ?? null,
    p_tiempo_dias: p.tiempoDias ?? null,
    p_materiales: p.materiales ?? [],
  })
  if (error) throw error
  return data
}

export async function planificarNc(ncId: string) {
  const { data, error } = await supabase.rpc('fn_planificar_nc', { p_nc_id: ncId })
  if (error) throw error
  return data
}

// Sube la foto de la NC a 'evidencias-verificacion/nc/'.
export async function subirFotoNc(file: File): Promise<string> {
  const safe = file.name.replace(/[^a-zA-Z0-9._-]/g, '_')
  const path = `nc/${Date.now()}-${safe}`
  const { error } = await supabase.storage.from('evidencias-verificacion').upload(path, file, { upsert: false })
  if (error) throw error
  const { data } = supabase.storage.from('evidencias-verificacion').getPublicUrl(path)
  return data.publicUrl
}

export async function registrarNcAdhoc(p: {
  activoId: string; descripcion: string; severidad?: string; informeId?: string | null; observacion?: string | null; fotoUrl?: string | null
}) {
  const { data, error } = await supabase.rpc('fn_registrar_nc_recepcion', {
    p_activo_id: p.activoId,
    p_descripcion: p.descripcion,
    p_severidad: p.severidad ?? 'media',
    p_informe_id: p.informeId ?? null,
    p_observacion: p.observacion ?? null,
    p_foto: p.fotoUrl ?? null,
  })
  if (error) throw error
  return data
}

export async function generarNcDesdeRecepcion(informeId: string) {
  const { data, error } = await supabase.rpc('fn_generar_nc_desde_recepcion', { p_informe_id: informeId })
  if (error) throw error
  return data
}

// Recepciones (informes) con su equipo, para "Generar NC desde recepción".
export async function getRecepcionesParaNc() {
  const { data, error } = await supabase
    .from('v_informes_recepcion_lista')
    .select('id, folio, estado, activo_id, patente, activo_codigo')
    .order('emitido_en', { ascending: false, nullsFirst: true })
    .limit(50)
  if (error) throw error
  return data ?? []
}

// Equipos para registrar NC ad-hoc.
export async function getActivosParaNc() {
  const { data, error } = await supabase
    .from('activos').select('id, patente, codigo, nombre')
    .is('fecha_baja', null).order('patente')
  if (error) throw error
  return data ?? []
}
