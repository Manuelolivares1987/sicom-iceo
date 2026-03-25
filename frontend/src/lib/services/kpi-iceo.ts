import { supabase } from '@/lib/supabase'
import type { MedicionKPI, ICEOPeriodo } from '@/types/database'

export async function getMedicionesKPI(
  contratoId: string,
  faenaId?: string,
  periodoInicio?: string,
  periodoFin?: string
) {
  let query = supabase
    .from('mediciones_kpi')
    .select('*, kpi:kpi_definiciones(*)')
    .eq('contrato_id', contratoId)

  if (faenaId) query = query.eq('faena_id', faenaId)
  if (periodoInicio) query = query.gte('periodo_inicio', periodoInicio)
  if (periodoFin) query = query.lte('periodo_fin', periodoFin)

  const { data, error } = await query.order('periodo_inicio', { ascending: false })

  return { data, error }
}

export async function getICEOPeriodo(
  contratoId: string,
  faenaId?: string,
  periodoInicio?: string
) {
  let query = supabase
    .from('iceo_periodos')
    .select('*, detalles:iceo_detalle(*)')
    .eq('contrato_id', contratoId)

  if (faenaId) query = query.eq('faena_id', faenaId)
  if (periodoInicio) query = query.eq('periodo_inicio', periodoInicio)

  const { data, error } = await query.single()

  return { data: data as ICEOPeriodo | null, error }
}

export async function getICEOHistorico(
  contratoId: string,
  faenaId?: string,
  ultimosMeses: number = 12
) {
  let query = supabase
    .from('iceo_periodos')
    .select('*')
    .eq('contrato_id', contratoId)

  if (faenaId) query = query.eq('faena_id', faenaId)

  const { data, error } = await query
    .order('periodo_inicio', { ascending: false })
    .limit(ultimosMeses)

  return { data: data as ICEOPeriodo[] | null, error }
}

export async function calcularKPIs(
  contratoId: string,
  faenaId?: string,
  periodoInicio?: string,
  periodoFin?: string
) {
  const { data, error } = await supabase.rpc('calcular_todos_kpi', {
    p_contrato_id: contratoId,
    p_faena_id: faenaId ?? null,
    p_periodo_inicio: periodoInicio ?? new Date().toISOString().slice(0, 10),
    p_periodo_fin: periodoFin ?? new Date().toISOString().slice(0, 10),
  })

  return { data, error }
}

export async function calcularICEO(
  contratoId: string,
  faenaId?: string,
  periodoInicio?: string,
  periodoFin?: string
) {
  const { data, error } = await supabase.rpc('calcular_iceo', {
    p_contrato_id: contratoId,
    p_faena_id: faenaId ?? null,
    p_periodo_inicio: periodoInicio ?? new Date().toISOString().slice(0, 10),
    p_periodo_fin: periodoFin ?? new Date().toISOString().slice(0, 10),
  })

  return { data, error }
}

export async function getKPIDefiniciones() {
  const { data, error } = await supabase
    .from('kpi_definiciones')
    .select('*')
    .eq('activo', true)
    .order('area')
    .order('codigo')

  return { data, error }
}

export async function getBloqueantesStatus(
  contratoId: string,
  faenaId?: string,
  periodoInicio?: string
) {
  let query = supabase
    .from('mediciones_kpi')
    .select('*, kpi:kpi_definiciones!inner(*)')
    .eq('contrato_id', contratoId)
    .eq('kpi_definiciones.es_bloqueante', true)

  if (faenaId) query = query.eq('faena_id', faenaId)
  if (periodoInicio) query = query.eq('periodo_inicio', periodoInicio)

  const { data, error } = await query

  return { data, error }
}
