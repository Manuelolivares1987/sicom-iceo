import { supabase } from '@/lib/supabase'

// Equipos hoy en mantención / taller / fuera de servicio (insumo del planificador)
export interface EquipoEnTaller {
  activo_id: string
  patente: string
  equipamiento: string | null
  estado_codigo: string        // M / T / F
  dias_mantencion: number | null
  ultimo_contrato: string | null
  motivo: string | null
}

export async function getEquiposEnTaller(): Promise<EquipoEnTaller[]> {
  const { data, error } = await supabase.rpc('fn_flota_en_mantenimiento')
  if (error) throw error
  return (data ?? []) as EquipoEnTaller[]
}

export interface OtAbierta {
  id: string
  folio: string
  tipo: string
  estado: string
  prioridad: string
  fecha_programada: string | null
  responsable_id: string | null
}

export async function getOtsAbiertasActivo(activoId: string): Promise<OtAbierta[]> {
  const { data, error } = await supabase
    .from('ordenes_trabajo')
    .select('id, folio, tipo, estado, prioridad, fecha_programada, responsable_id')
    .eq('activo_id', activoId)
    .in('estado', ['creada', 'asignada', 'en_ejecucion', 'pausada'])
    .order('created_at', { ascending: false })
  if (error) throw error
  return (data ?? []) as OtAbierta[]
}

export interface Tecnico { id: string; nombre_completo: string; cargo: string | null }

export async function getTecnicos(): Promise<Tecnico[]> {
  const { data, error } = await supabase
    .from('usuarios_perfil')
    .select('id, nombre_completo, cargo')
    .eq('activo', true)
    .eq('rol', 'tecnico_mantenimiento')
    .order('nombre_completo')
  if (error) throw error
  return (data ?? []) as Tecnico[]
}

export interface PlanActivo {
  id: string                   // id del plan_mantenimiento
  nombre: string | null
  pauta_nombre: string | null
  duracion_estimada_hrs: number | null
}

export async function getPlanesActivo(activoId: string): Promise<PlanActivo[]> {
  const { data, error } = await supabase
    .from('planes_mantenimiento')
    .select('id, nombre, pauta:pautas_fabricante(nombre, duracion_estimada_hrs)')
    .eq('activo_id', activoId)
    .eq('activo_plan', true)
    .order('proxima_ejecucion_fecha', { ascending: true, nullsFirst: false })
  if (error) throw error
  type Raw = { id: string; nombre: string | null; pauta: { nombre: string; duracion_estimada_hrs: number | null } | null }
  return ((data ?? []) as unknown as Raw[]).map((r) => ({
    id: r.id,
    nombre: r.nombre,
    pauta_nombre: r.pauta?.nombre ?? null,
    duracion_estimada_hrs: r.pauta?.duracion_estimada_hrs ?? null,
  }))
}

export type TipoOtTaller = 'correctivo' | 'preventivo' | 'inspeccion'
export type PrioridadTaller = 'emergencia' | 'alta' | 'normal' | 'baja'

export async function programarOtTaller(params: {
  activoId: string
  tipo: TipoOtTaller
  prioridad: PrioridadTaller
  fecha: string | null
  responsableId: string | null
  planId: string | null
}): Promise<{ id: string; folio: string; estado: string }> {
  const { data, error } = await supabase.rpc('rpc_programar_ot_taller', {
    p_activo_id: params.activoId,
    p_tipo: params.tipo,
    p_prioridad: params.prioridad,
    p_fecha: params.fecha,
    p_responsable_id: params.responsableId,
    p_plan_mantenimiento_id: params.planId,
  })
  if (error) throw error
  return data as { id: string; folio: string; estado: string }
}
