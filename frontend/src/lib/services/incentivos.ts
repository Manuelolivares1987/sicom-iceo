import { supabase } from '@/lib/supabase'

export async function getIncentivosDelPeriodo(contratoId: string, periodoInicio?: string) {
  let query = supabase
    .from('v_reporte_incentivos')
    .select('*')
    .eq('contrato_id', contratoId) // Note: v_reporte_incentivos might not have contrato_id directly

  // Actually query the incentivos_periodo table with joins
  // since the view might not exist yet in the DB
  const periodo = periodoInicio ?? new Date().toISOString().slice(0, 8) + '01'

  const { data, error } = await supabase
    .from('incentivos_periodo')
    .select('*, usuario:usuarios_perfil(nombre_completo, rut, cargo, faena:faenas(nombre))')
    .eq('periodo_inicio', periodo)
    .order('monto_incentivo_final', { ascending: false })

  return { data, error }
}

export async function calcularIncentivos(contratoId: string, periodoInicio?: string, periodoFin?: string) {
  const { data, error } = await supabase.rpc('rpc_calcular_incentivos_periodo', {
    p_contrato_id: contratoId,
    p_periodo_inicio: periodoInicio ?? null,
    p_periodo_fin: periodoFin ?? null,
  })
  return { data, error }
}

export async function getKPIDrillDown(kpiCodigo: string, contratoId: string, faenaId?: string, periodoInicio?: string, periodoFin?: string) {
  const { data, error } = await supabase.rpc('rpc_kpi_drill_down', {
    p_kpi_codigo: kpiCodigo,
    p_contrato_id: contratoId,
    p_faena_id: faenaId ?? null,
    p_periodo_inicio: periodoInicio ?? null,
    p_periodo_fin: periodoFin ?? null,
  })
  return { data, error }
}

export async function cerrarPeriodoKPI(contratoId: string, periodo?: string, usuarioId?: string) {
  const { data, error } = await supabase.rpc('rpc_cerrar_periodo_kpi', {
    p_contrato_id: contratoId,
    p_periodo: periodo ?? null,
    p_usuario_id: usuarioId ?? null,
  })
  return { data, error }
}

export async function getSnapshotsMensuales(contratoId: string) {
  const { data, error } = await supabase
    .from('kpi_snapshots_mensuales')
    .select('*')
    .eq('contrato_id', contratoId)
    .order('periodo', { ascending: false })
    .limit(12)
  return { data, error }
}
