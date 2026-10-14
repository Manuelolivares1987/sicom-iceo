import { supabase } from '@/lib/supabase'

// ============================================================================
// Costos de operación (MIG594-595)
// ----------------------------------------------------------------------------
// Salidas de bodega Softland copiadas a SICOM una vez al día por
// database/scripts/softland-sync.ps1. Todo el panel llega en una llamada a
// rpc_costos_operacion_panel; la autorización vive en la base
// (fn_costos_operacion_puede_ver) y un 42501 se traduce a "no autorizado", no
// a un panel vacío.
// ============================================================================

export type AreaCosto =
  | 'equipo' | 'operacion' | 'taller' | 'proyectos' | 'generico'
  | 'administracion' | 'comercial' | 'sin_clasificar'

export const AREAS_OPERACION: AreaCosto[] = [
  'equipo', 'operacion', 'taller', 'proyectos', 'generico', 'sin_clasificar',
]

export const NOMBRE_AREA: Record<AreaCosto, string> = {
  equipo: 'Equipos',
  operacion: 'Operación de faena',
  taller: 'Taller',
  proyectos: 'Proyectos',
  generico: 'Sin equipo (genérico)',
  administracion: 'Administración',
  comercial: 'Comercial',
  sin_clasificar: 'Sin clasificar',
}

export type KpiCostos = {
  total: number
  total_anterior: number
  sin_petroleo: number
  sin_petroleo_anterior: number
  petroleo_total: number
  petroleo_litros: number
  petroleo_litros_anterior: number
  petroleo_total_anterior: number
  petroleo_sin_equipo_litros: number
  asignado_equipo: number
  epp: number
  lineas: number
  lineas_sin_precio: number
  equipos_con_gasto: number
}

export type CostoMes = {
  mes: string
  sin_petroleo: number | null
  petroleo: number | null
  litros: number | null
  asignado_equipo: number | null
  total: number
}

export type CostoEquipo = {
  codi_cc: string
  activo_id: string | null
  patente: string | null
  activo_codigo: string | null
  tipo_equipo: string | null
  descripcion: string | null
  faena: string | null
  total: number
  sin_petroleo: number | null
  neumaticos: number | null
  lubricantes: number | null
  repuestos: number | null
  litros: number | null
  total_anterior: number | null
}

export type CostoCc = {
  codi_cc: string
  area: AreaCosto
  descripcion: string | null
  total: number
  petroleo: number | null
  litros: number | null
}

export type CostoFamilia = {
  familia: string
  nombre: string
  grupo: string
  total: number
  total_anterior: number | null
}

export type PanelCostos = {
  periodo: { desde: string; hasta: string; meses: number; anterior_desde: string }
  kpi: KpiCostos
  por_mes: CostoMes[]
  por_area: { area: AreaCosto; total: number; sin_petroleo: number | null }[]
  por_zona: { zona: string; total: number; sin_petroleo: number | null }[]
  por_bodega: { bodega: string; total: number }[]
  por_familia: CostoFamilia[]
  por_equipo: CostoEquipo[]
  por_cc_no_equipo: CostoCc[]
  sync: { ultima: string | null; docs: number; max_fecha: string | null }
}

export type LineaCosto = {
  fecha: string
  folio: number | null
  concepto: string
  bodega: string
  codi_cc: string | null
  cod_prod: string
  des_prod: string | null
  cantidad: number
  precio_unit: number
  total: number
  glosa: string | null
}

export class CostosNoAutorizadoError extends Error {
  constructor() {
    super('No tienes permiso para ver los costos de operación.')
    this.name = 'CostosNoAutorizadoError'
  }
}

function traducir(error: { code?: string; message: string }): never {
  if (error.code === '42501') throw new CostosNoAutorizadoError()
  throw new Error(error.message)
}

export async function getPanelCostos(desde: string, hasta: string, areas: AreaCosto[] | null) {
  const { data, error } = await supabase.rpc('rpc_costos_operacion_panel', {
    p_desde: desde, p_hasta: hasta, p_areas: areas,
  })
  if (error) traducir(error)
  return data as PanelCostos
}

export async function getDetalleCostos(v: {
  desde: string; hasta: string; codiCc?: string | null; familia?: string | null
}) {
  const { data, error } = await supabase.rpc('rpc_costos_operacion_detalle', {
    p_desde: v.desde, p_hasta: v.hasta,
    p_codi_cc: v.codiCc ?? null, p_familia: v.familia ?? null, p_limite: 500,
  })
  if (error) traducir(error)
  return (data ?? []) as LineaCosto[]
}
