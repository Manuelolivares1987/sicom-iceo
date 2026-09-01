import { supabase } from '@/lib/supabase'

// ============================================================================
// Orden de Servicio (MIG473)
// ----------------------------------------------------------------------------
// El escalón que faltaba entre la OT —la visita del equipo— y la no conformidad
// suelta. Responde quién lo hace, en cuántas horas y con qué repuestos.
//
// Lo importante del modelo no es la tabla: es que EL RELOJ SIGUE A LA PERSONA.
// Una OS la empieza uno, lo mandan a otro equipo y la retoma otro; el sistema
// guarda un tramo por persona y por vez. Y nadie puede tener dos trabajos
// corriendo a la vez — eso es un índice único, no una buena intención.
// ============================================================================

export type OrdenServicio = {
  id: string
  folio: string
  ot_id: string
  ot_folio: string
  patente: string | null
  equipo: string | null
  titulo: string
  descripcion: string | null
  estado: 'abierta' | 'en_ejecucion' | 'pausada' | 'finalizada' | 'anulada'
  prioridad: string | null
  horas_estimadas: number | null
  responsable_id: string | null
  responsable: string | null
  created_at: string
  cerrada_at: string | null
  ncs: number
  tramos_abiertos: number
  horas_reales: number
  /** Quiénes trabajaron en ella, no sólo el responsable. */
  quienes: string | null
}

export type OSPersona = {
  os_id: string
  os_folio: string
  tecnico_id: string
  tecnico: string
  tramos: number
  horas: number
  horas_estimadas: number | null
  trabajando_ahora: boolean
}

export async function getOSDeOT(otId: string): Promise<OrdenServicio[]> {
  const { data, error } = await supabase
    .from('v_taller_os').select('*').eq('ot_id', otId)
    .order('created_at', { ascending: true })
  if (error) throw new Error(error.message)
  return (data ?? []) as OrdenServicio[]
}

/** Qué actividad hizo quién, y por cuántas horas. */
export async function getPersonasDeOS(osId: string): Promise<OSPersona[]> {
  const { data, error } = await supabase
    .from('v_taller_os_personas').select('*').eq('os_id', osId)
    .order('tecnico')
  if (error) throw new Error(error.message)
  return (data ?? []) as OSPersona[]
}

// ── [MIG475] El techo de horas de la visita ─────────────────────────────────
//
// Lo pone el PLANIFICADOR en la jornada del plan, no el checklist. La suma de
// las OS no puede pasarlo sin que alguien escriba por qué.

export type PresupuestoOT = {
  /** El paraguas: lo que el plan le dio al equipo. null = no lo definió. */
  horas_plan: number | null
  /** [MIG476] Lo que ya se fue en revisar. Sale del mismo paraguas. */
  horas_revision: number
  /** Lo que queda para repartir en OS: plan menos revisión. */
  techo_os: number | null
  /** Lo que el checklist estima. Referencia, no manda. */
  horas_checklist: number
  sin_techo: boolean
  horas_en_os: number
  horas_libres: number
  excedida: boolean
  horas_reales_os: number
}

export async function getPresupuestoOT(otId: string): Promise<PresupuestoOT> {
  const { data, error } = await supabase.rpc('rpc_taller_ot_presupuesto', { p_ot_id: otId })
  if (error) throw new Error(error.message)
  return data as PresupuestoOT
}

export type CrearOSResp = {
  success: boolean
  os_id?: string; folio?: string; nc_asignadas?: number
  /** Cuando la suma pasa el techo del planificador y falta explicar por qué. */
  requiere_justificacion?: boolean
  horas_plan?: number; horas_en_os?: number; horas_con_esta?: number
  motivo?: string
  sin_techo?: boolean; excedida?: boolean
}

export async function crearOS(p: {
  otId: string; titulo: string; ncIds?: string[]
  responsableId?: string | null; horasEstimadas?: number | null
  descripcion?: string | null; prioridad?: string | null
  justificacion?: string | null
}) {
  const { data, error } = await supabase.rpc('rpc_taller_os_crear', {
    p_ot_id: p.otId,
    p_titulo: p.titulo,
    p_nc_ids: p.ncIds?.length ? p.ncIds : null,
    p_responsable_id: p.responsableId ?? null,
    p_horas_estimadas: p.horasEstimadas ?? null,
    p_descripcion: p.descripcion ?? null,
    p_prioridad: p.prioridad ?? null,
    p_justificacion: p.justificacion ?? null,
  })
  if (error) throw new Error(error.message)
  return data as CrearOSResp
}

// ── [MIG474] Al operador lo mueve el jefe ───────────────────────────────────
//
// Asignar es la decisión del jefe: a quién le toca esta OS. Mover a alguien es
// reasignarlo, y eso además le para el reloj donde estaba. El operador sólo
// puede empezar y pausar lo que ya le asignaron.

export type AsignacionVigente = {
  tecnico_id: string; tecnico: string
  os_id: string; os_folio: string; titulo: string
  ot_folio: string; patente: string | null
  asignado_desde: string; asignado_por: string | null; motivo: string | null
  trabajando: boolean
}

/** A qué está asignado cada mecánico ahora, y si está trabajando o no. */
export async function getAsignacionesVigentes(): Promise<AsignacionVigente[]> {
  const { data, error } = await supabase
    .from('v_taller_os_asignacion_vigente').select('*').order('tecnico')
  if (error) throw new Error(error.message)
  return (data ?? []) as AsignacionVigente[]
}

/** La acción del jefe. `arrancar` deja al mecánico andando de inmediato. */
export async function asignarOS(p: {
  osId: string; tecnicoId: string; motivo?: string | null; arrancar?: boolean
}) {
  const { data, error } = await supabase.rpc('rpc_taller_os_asignar', {
    p_os_id: p.osId, p_tecnico_id: p.tecnicoId,
    p_motivo: p.motivo ?? null, p_arrancar: p.arrancar ?? false,
  })
  if (error) throw new Error(error.message)
  return data as { success: boolean; ya_estaba?: boolean; aviso?: string | null; arrancada?: boolean }
}

export async function desasignarTecnico(tecnicoId: string, motivo?: string | null) {
  const { error } = await supabase.rpc('rpc_taller_os_desasignar', {
    p_tecnico_id: tecnicoId, p_motivo: motivo ?? null,
  })
  if (error) throw new Error(error.message)
}

export async function iniciarOS(osId: string, tecnicoId: string) {
  const { data, error } = await supabase.rpc('rpc_taller_os_iniciar', {
    p_os_id: osId, p_tecnico_id: tecnicoId,
  })
  if (error) throw new Error(error.message)
  return data as { success: boolean; ya_estaba?: boolean; aviso?: string | null }
}

export async function pausarOS(osId: string, tecnicoId: string, motivo?: string | null) {
  const { error } = await supabase.rpc('rpc_taller_os_pausar', {
    p_os_id: osId, p_tecnico_id: tecnicoId, p_motivo: motivo ?? null,
  })
  if (error) throw new Error(error.message)
}

export async function finalizarOS(osId: string, observacion?: string | null) {
  const { data, error } = await supabase.rpc('rpc_taller_os_finalizar', {
    p_os_id: osId, p_observacion: observacion ?? null,
  })
  if (error) throw new Error(error.message)
  return data as { success: boolean; horas_reales: number }
}

export type OSEnCurso = {
  tecnico_id: string; tecnico: string; os_id: string; os_folio: string
  titulo: string; patente: string | null; desde: string; horas: number
}

/** En qué anda cada mecánico ahora mismo. Uno solo por persona, por diseño. */
export async function getOSEnCurso(): Promise<OSEnCurso[]> {
  const { data, error } = await supabase.rpc('rpc_taller_os_en_curso')
  if (error) throw new Error(error.message)
  return (data ?? []) as OSEnCurso[]
}

export const ESTADO_OS_LABEL: Record<string, string> = {
  abierta: 'Por empezar',
  en_ejecucion: 'En ejecución',
  pausada: 'Pausada',
  finalizada: 'Terminada',
  anulada: 'Anulada',
}
