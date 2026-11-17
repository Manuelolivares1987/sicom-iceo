import { CostosNoAutorizadoError, rpcCostos } from '@/lib/services/costos-operacion'

// ============================================================================
// Presupuesto de Operaciones 2027-2029 (MIG670)
// ----------------------------------------------------------------------------
// El cálculo vive en la base (fn_ppto_recalcular) y corre solo cuando alguien lo
// pide: la pantalla lee lo guardado. El real sale de las mismas OC que el panel.
// ============================================================================

export type AnioReal = '2023' | '2024' | '2025' | '2026'
export type AnioPpto = '2027' | '2028' | '2029'

export type LineaPpto = {
  codigo: string
  bloque: string
  bloque_nombre: string
  nombre: string
  metodo: string
  real: Record<AnioReal, number>
  cierre_2026: number
  ppto: Record<AnioPpto, number>
}

export type SupuestoPpto = { clave: string; nombre: string; valor: number; unidad: 'pct' | 'clp' | 'horas' | 'h/d' | 'UF'; nota: string | null }

// Base comercial (MIG698): 13 UF por mes arrendado frente a la mantención de SICOM, 2027.
export type ComercialPpto = {
  uf: number
  uf_mes: number
  cuota: number
  meses_total: number
  lineas: { codigo: string; nombre: string; metodo: string; grupo: 'mantencion' | 'aparte' | 'excluido'; monto: number }[]
  meses: { mes: number; camiones: number; comercial: number; sicom: number }[]
  camiones: {
    patente: string
    codigo: string | null
    tipo: string | null
    area: string
    fuente: 'excel' | 'contrato' | null
    modelo: string | null
    anio_fab: number | null
    meses: number
    lista: number[]
    ingreso: number
    comercial: number
    preventivo: number
    correctivo: number
    neumaticos: number
    mayores: number
  }[]
}

export type ProgramaPpto = {
  id: number
  anio: number
  tipo: 'opex' | 'capex' | 'overhaul'
  patente: string | null
  descripcion: string
  monto: number
  gatillo: string | null
}

export type ResumenPpto = {
  hoy: string
  calculado_at: string | null
  meta: { corte: string; kit_pct_precio_real: number; cuota_seguro: number; provision_mayores: number } | null
  puede_editar: boolean
  congelada: { id: number; nombre: string; calculado_at: string } | null
  lineas: LineaPpto[]
  supuestos: SupuestoPpto[]
  programas: ProgramaPpto[]
}

export type CamionPpto = {
  patente: string
  modelo: string | null
  anio_fab: number | null
  faena: string | null
  estado_comercial: string | null
  con_pauta: boolean
  horometro: number | null
  ritmo: number | null
  ritmo_fuente: string | null
  real_2025: number
  real_2026: number
  preventivo: number
  correctivo: number
  neumaticos: number
  mayores: number
  total_2027: number
  total_2028: number
  total_2029: number
  visitas_2027: number
  visitas_2028: number
  visitas_2029: number
  proxima: string | null
}

export type VisitaPpto = {
  patente: string
  fecha: string
  mes: number
  horas: number | null
  nivel: string
  tipo: 'pauta' | 'componente' | 'anual'
  costo_kit: number
}

export type DetalleLineaPpto = {
  productos: { cod_prod: string; descripcion: string | null; total: number; lineas: number }[]
  partidas: { nombre: string; descripcion: string | null; t27: number; t28: number; t29: number }[]
}

export type RealVsPpto = {
  version: string
  congelada: boolean
  lineas: { codigo: string; nombre: string; bloque: string; ppto: Record<string, number>; real: Record<string, number> }[]
}

async function llamar<T>(fn: string, args: Record<string, unknown> = {}): Promise<T> {
  const { data, error } = await rpcCostos(fn, args)
  if (error) {
    if (error.code === '42501') throw new CostosNoAutorizadoError()
    throw new Error(error.message)
  }
  return data as T
}

export const getResumenPpto = () => llamar<ResumenPpto>('rpc_ppto_resumen')
export const getCamionesPpto = () => llamar<CamionPpto[]>('rpc_ppto_camiones')
export const getVisitasPpto = (anio: number) => llamar<VisitaPpto[]>('rpc_ppto_visitas', { p_anio: anio })
export const getDetalleLineaPpto = (linea: string) => llamar<DetalleLineaPpto>('rpc_ppto_detalle_linea', { p_linea: linea })
export const getComercialPpto = () => llamar<ComercialPpto>('rpc_ppto_comercial')

// Por camión agrupado (MIG702): familia, contrato de servicio y base del proyectado 2027.
export type VisitaResumenPpto = { tipo: 'pauta' | 'componente' | 'anual'; nivel: string; n: number; costo: number; kit: number }
export type CamionDetallePpto = {
  patente: string
  codigo: string | null
  nombre: string | null
  modelo: string | null
  anio_fab: number | null
  familia: string
  contrato: string | null
  faena: string | null
  estado_comercial: string | null
  real: Record<'2023' | '2024' | '2025' | '2026', number>
  real_neumaticos?: Record<'2023' | '2024' | '2025' | '2026', number>
  tipo_equipamiento?: string | null
  operacion?: string | null
  tc8_vence?: string | null
  preventivo: number
  correctivo: number
  neumaticos: number
  mayores: number
  /** Certificaciones por vencimiento 2027 (TC8 y pluma, línea B4). */
  certificaciones: number
  total_2028: number
  total_2029: number
  base: {
    con_pauta: boolean
    grupo_kit: string | null
    intervalo_horas: number | null
    horometro: number
    ritmo: number
    ritmo_fuente: string | null
    ritmo_18m: number | null
    ritmo_mejor_mes: number | null
    mejor_mes: string | null
    horas_2027: number
    visitas: VisitaResumenPpto[]
    correctivo_base: number
    edad_equivalente: number | null
    factor_edad: number | null
    piso_correctivo: number | null
    neumatico_base: number
    neumatico_piso: number | null
    mayores: { descripcion: string; monto: number }[]
    certificaciones: { anio: number; descripcion: string; monto: number }[]
    partidas_correctivo: { descripcion: string; monto: number }[]
  }
}
export const getCamionesDetallePpto = () => llamar<CamionDetallePpto[]>('rpc_ppto_camiones_detalle')

// Excel con fórmulas (MIG705): supuestos, curva de edad, costo de cada kit y totales por línea.
export type ParametrosExcelPpto = {
  fecha_calculo: string | null
  supuestos: Record<string, number>
  curva: { edad: number; factor: number }[]
  kits: { grupo_kit: string; nivel: string; costo: number; fl: number }[]
  intervalos: Record<string, number>
  lineas: { codigo: string; nombre: string; bloque: string; '2027': number; '2027_equipos': number; '2028': number; '2029': number }[]
}
export const getParametrosExcelPpto = () => llamar<ParametrosExcelPpto>('rpc_ppto_parametros_excel')

// Composición de un equipo (MIG706): real por componente y qué forma su correctivo y su overhaul.
type Anual = Record<string, number | null>
export type ComposicionEquipoPpto = {
  corte: string
  ventana_desde: string
  ipc_historico: number
  real: Record<'A1' | 'A2' | 'A3' | 'A4' | 'B4', Anual>
  ppto: Partial<Record<'A1' | 'A2' | 'A3' | 'A4' | 'B4', Anual>> | null
  correctivo_categorias: { categoria: string; excluida: boolean; monto: number; monto_2026: number; n: number }[]
  correctivo_compras: { fecha: string; categoria: string; excluida: boolean; proveedor: string | null; descripcion: string | null; folio: string | null; monto: number }[]
  overhaul_2027: { anio: number; descripcion: string; monto: number; gatillo: string | null }[]
  overhaul_historia: { fecha: string; proveedor: string | null; descripcion: string | null; monto: number }[]
  neumaticos_compras: { fecha: string; proveedor: string | null; descripcion: string | null; monto: number }[]
}
export const getComposicionEquipoPpto = (patente: string) =>
  llamar<ComposicionEquipoPpto | null>('rpc_ppto_equipo_composicion', { p_patente: patente })
export const getRealVsPpto =(anio: number) => llamar<RealVsPpto>('rpc_ppto_real_vs', { p_anio: anio })

export const recalcularPpto = () => llamar('rpc_ppto_recalcular')
export const guardarSupuestoPpto = (clave: string, valor: number) =>
  llamar('rpc_ppto_supuesto_guardar', { p_clave: clave, p_valor: valor })
export const guardarProgramaPpto = (p: Omit<ProgramaPpto, 'id'> & { id: number | null }) =>
  llamar('rpc_ppto_programa_guardar', {
    p_id: p.id, p_anio: p.anio, p_tipo: p.tipo, p_patente: p.patente,
    p_descripcion: p.descripcion, p_monto: p.monto, p_gatillo: p.gatillo,
  })
export const borrarProgramaPpto = (id: number) => llamar('rpc_ppto_programa_borrar', { p_id: id })
export const congelarPpto = (nombre: string) => llamar('rpc_ppto_congelar', { p_nombre: nombre })
