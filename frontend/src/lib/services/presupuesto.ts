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

export type SupuestoPpto = { clave: string; nombre: string; valor: number; unidad: 'pct' | 'clp' | 'horas' | 'h/d'; nota: string | null }

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
export const getRealVsPpto = (anio: number) => llamar<RealVsPpto>('rpc_ppto_real_vs', { p_anio: anio })

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
