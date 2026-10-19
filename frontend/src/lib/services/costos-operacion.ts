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
  periodo: {
    desde: string; hasta: string; meses: number
    anterior_desde: string; anterior_hasta: string; compara_anio_anterior: boolean
  }
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

// [MIG620] El panel abierto desde el correo (/reporte-costos/panel?t=…) no tiene
// sesión: manda el token del link en `x-reporte-token` y la base lo acepta en
// fn_costos_operacion_puede_ver. Con sesión, el token queda en null.
let tokenReporte: string | null = null
export function usarTokenReporteCostos(token: string | null) { tokenReporte = token }

/** rpc de costos: agrega el token del link cuando la página se abrió sin sesión. */
export function rpcCostos(fn: string, args: Record<string, unknown>) {
  const q = supabase.rpc(fn, args)
  return tokenReporte ? q.setHeader('x-reporte-token', tokenReporte) : q
}

export async function getPanelCostos(desde: string, hasta: string, areas: AreaCosto[] | null) {
  const { data, error } = await rpcCostos('rpc_costos_operacion_panel', {
    p_desde: desde, p_hasta: hasta, p_areas: areas,
  })
  if (error) traducir(error)
  return data as PanelCostos
}

export async function getDetalleCostos(v: {
  desde: string; hasta: string; codiCc?: string | null; familia?: string | null
}) {
  const { data, error } = await rpcCostos('rpc_costos_operacion_detalle', {
    p_desde: v.desde, p_hasta: v.hasta,
    p_codi_cc: v.codiCc ?? null, p_familia: v.familia ?? null, p_limite: 500,
  })
  if (error) traducir(error)
  return (data ?? []) as LineaCosto[]
}

// ---------------------------------------------------------------------------
// Por faena (MIG600): el gasto de un equipo va a la faena donde estaba el día
// del gasto (estado_diario_flota); cada faena suma además sus CC propios.
// ---------------------------------------------------------------------------

export type FaenaCosto = {
  faena: string
  total: number
  equipos_costo: number | null
  directo: number | null
  neumaticos: number | null
  lubricantes: number | null
  repuestos: number | null
  seguridad_epp: number | null
  dias_equipo: number | null
  equipos: number | null
  costo_equipo_dia: number | null
  horas: number | null
  costo_medido: number | null
  costo_hora: number | null
}

export type CostosPorFaena = {
  periodo: { desde: string; hasta: string }
  faenas: FaenaCosto[]
  subfaenas: (FaenaCosto & { subfaena: string })[]
  por_mes: { mes: string; faena: string; total: number }[]
  equipos: { faena: string; activo_id: string; patente: string | null; total: number }[]
  directos: { faena: string; codi_cc: string | null; descripcion: string | null; total: number }[]
}

export async function getCostosPorFaena(desde: string, hasta: string) {
  const { data, error } = await rpcCostos('rpc_costos_por_faena', { p_desde: desde, p_hasta: hasta })
  if (error) traducir(error)
  return data as CostosPorFaena
}

export type SubfaenaCosto = FaenaCosto & { subfaena: string }

// ---------------------------------------------------------------------------
// Pareto (MIG601): ranking descendente con % acumulado, con bajada en cadena.
// ---------------------------------------------------------------------------

export type DimensionPareto =
  | 'faena' | 'subfaena' | 'equipo' | 'familia' | 'producto' | 'centro_costo' | 'mes' | 'linea'

export type FiltrosPareto = Partial<{
  faena: string
  subfaena: string
  activo_id: string
  familia: string
  grupo_prod: string
  cod_prod: string
  codi_cc: string
  area: string
  mes: string
  tipo_equipo: string
}>

export type ItemPareto = {
  clave: string
  etiqueta: string
  total: number
  cantidad: number | null
  lineas: number
  pct: number
  pct_acum: number
}

export type ResultadoPareto = {
  dimension: DimensionPareto
  total: number
  n: number
  vitales: number
  items: ItemPareto[]
  resto: { n: number; total: number }
}

export type LineaPareto = {
  fecha: string
  folio: number | null
  concepto: string
  bodega: string
  codi_cc: string | null
  cod_prod: string
  des_prod: string | null
  cantidad: number
  precio_unit: number | null
  total: number
  glosa: string | null
  patente: string | null
  subfaena: string | null
}

export async function getPareto(v: {
  desde: string; hasta: string; filtros: FiltrosPareto; dimension: DimensionPareto; conAdmin?: boolean
}) {
  const { data, error } = await rpcCostos('rpc_costos_pareto', {
    p_desde: v.desde, p_hasta: v.hasta, p_filtros: v.filtros,
    p_dimension: v.dimension, p_con_admin: v.conAdmin ?? false,
  })
  if (error) traducir(error)
  return data as ResultadoPareto & { lineas?: LineaPareto[] }
}

// ---------------------------------------------------------------------------
// Conciliación de ubicación (MIG602): ficha vs estado diario vs GPS.
// ---------------------------------------------------------------------------

export type UbicacionCamion = {
  activo_id: string
  patente: string | null
  tipo: string | null
  faena_ficha: string | null
  grupo_ficha: string | null
  estado_ubicacion: string | null
  estado_fecha: string | null
  grupo_estado: string | null
  gps_geocerca: string | null
  gps_km: number | null
  gps_fecha: string | null
  grupo_gps: string | null
  subfaena_gps: string | null
  grupo_usado: string | null
  subfaena_usada: string | null
  fuente_usada: string | null
}

export async function getConciliacionUbicacion() {
  const { data, error } = await supabase.from('v_flota_ubicacion_conciliacion').select('*')
  if (error) throw new Error(error.message)
  return (data ?? []) as UbicacionCamion[]
}
