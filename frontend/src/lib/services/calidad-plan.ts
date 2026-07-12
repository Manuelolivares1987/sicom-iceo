import { supabase } from '@/lib/supabase'

// ── Plan semanal de Calidad (MIG225) ─────────────────────────────────────────
// El encargado de calidad programa sus tareas de la semana. Lectura directa a
// la tabla; escritura vía RPCs (SECURITY DEFINER con check de rol).

export type CalidadTareaTipo = 'auditoria' | 'chequeo_cruzado' | 'inspeccion' | 'documentacion' | 'otro'
export type CalidadTareaEstado = 'pendiente' | 'en_curso' | 'hecha' | 'cancelada'

export interface CalidadPlanTarea {
  id: string
  fecha: string
  titulo: string
  descripcion: string | null
  tipo: CalidadTareaTipo
  equipo_texto: string | null
  responsable: string | null
  horas_estimadas: number | null
  estado: CalidadTareaEstado
  hecha_at: string | null
  created_at: string
}

export const CALIDAD_TIPO_LABEL: Record<CalidadTareaTipo, string> = {
  auditoria: 'Auditoría',
  chequeo_cruzado: 'Chequeo cruzado',
  inspeccion: 'Inspección',
  documentacion: 'Documentación',
  otro: 'Otro',
}

/** Lunes (ISO yyyy-mm-dd) de la semana de una fecha. */
export function lunesDeIsoCalidad(d: Date): string {
  const x = new Date(d)
  const day = (x.getDay() + 6) % 7 // 0 = lunes
  x.setDate(x.getDate() - day)
  return x.toISOString().slice(0, 10)
}

export async function getTareasSemanaCalidad(lunesIso: string): Promise<CalidadPlanTarea[]> {
  const fin = new Date(lunesIso + 'T12:00:00')
  fin.setDate(fin.getDate() + 6)
  const finIso = fin.toISOString().slice(0, 10)
  const { data, error } = await supabase
    .from('calidad_plan_tareas')
    .select('*')
    .gte('fecha', lunesIso)
    .lte('fecha', finIso)
    .order('fecha')
    .order('created_at')
  if (error) throw error
  return (data ?? []) as CalidadPlanTarea[]
}

export async function agregarTareaCalidad(input: {
  fecha: string
  titulo: string
  tipo: CalidadTareaTipo
  descripcion?: string | null
  equipoTexto?: string | null
  responsable?: string | null
  horas?: number | null
}): Promise<void> {
  const { error } = await supabase.rpc('rpc_calidad_agregar_tarea', {
    p_fecha: input.fecha,
    p_titulo: input.titulo,
    p_tipo: input.tipo,
    p_descripcion: input.descripcion ?? null,
    p_equipo_texto: input.equipoTexto ?? null,
    p_responsable: input.responsable ?? null,
    p_horas: input.horas ?? null,
  })
  if (error) throw error
}

export async function actualizarTareaCalidad(id: string, patch: {
  estado?: CalidadTareaEstado
  fecha?: string
}): Promise<void> {
  const { error } = await supabase.rpc('rpc_calidad_actualizar_tarea', {
    p_id: id,
    p_estado: patch.estado ?? null,
    p_fecha: patch.fecha ?? null,
  })
  if (error) throw error
}

export async function eliminarTareaCalidad(id: string): Promise<void> {
  const { error } = await supabase.rpc('rpc_calidad_eliminar_tarea', { p_id: id })
  if (error) throw error
}
