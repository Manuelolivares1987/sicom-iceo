import { supabase } from '@/lib/supabase'

// ============================================================================
// Costos de operación (MIG594-599)
// El petróleo NO entra: se compra para revender, es mercadería (MIG598).
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
  asignado_equipo: number
  asignado_equipo_anterior: number
  epp: number
  neumaticos: number
  lineas: number
  lineas_sin_precio: number
  equipos_con_gasto: number
  sin_cc: number
  flota_horas: number | null
  flota_costo_medido: number | null
  flota_costo_hora: number | null
  equipos_medidos: number
  dias_medidos_mediana: number | null
}

export type CostoMes = {
  mes: string
  total: number
  asignado_equipo: number | null
}

export type CostoEquipo = {
  codi_cc: string               // uno o varios, separados por coma
  activo_id: string | null
  patente: string | null
  activo_codigo: string | null
  tipo_equipo: string | null
  descripcion: string | null
  faena: string | null
  total: number
  neumaticos: number | null
  lubricantes: number | null
  repuestos: number | null
  total_anterior: number | null
  // Costo por hora: ventana entre dos lecturas de horómetro creíbles (MIG599)
  horas: number | null
  dias_medidos: number | null
  medido_desde: string | null
  medido_hasta: string | null
  fuente_ini: string | null
  fuente_fin: string | null
  costo_medido: number | null
  costo_hora: number | null
  mediana_tipo: number | null
  n_tipo: number | null
}

export type CostoCc = {
  codi_cc: string
  area: AreaCosto
  descripcion: string | null
  total: number
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
  por_area: { area: AreaCosto; total: number }[]
  por_zona: { zona: string; total: number }[]
  por_familia: CostoFamilia[]
  por_equipo: CostoEquipo[]
  costo_hora_tipo: { tipo_equipo: string; n: number; mediana: number }[]
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
