import { rpcCostos } from '@/lib/services/costos-operacion'
import type { InsumoConsumo } from '@/lib/insumos-consumo'

// Consumos por insumo (MIG681): histórico de Softland y proyección por pauta.

export type FuenteInsumo = 'bodega' | 'oc'

export type DetalleInsumo = {
  historico: { mes: string; cantidad: number; monto: number }[]
  proyeccion: { mes: string; cantidad: number }[]
  proveedores: { proveedor: string; cantidad: number; monto: number; precio: number | null; ultima: string }[]
  camiones: { patente: string; grupo: string; visitas: number; cantidad: number }[]
}

export async function getConsumoInsumos(fuente: FuenteInsumo, desde: string, hasta: string) {
  const { data, error } = await rpcCostos('rpc_insumos_consumo', { p_fuente: fuente, p_desde: desde, p_hasta: hasta })
  if (error) throw new Error(error.message)
  return data as { calculado_at: string | null; items: InsumoConsumo[] }
}

export async function getDetalleInsumo(fuente: FuenteInsumo, clave: string) {
  const { data, error } = await rpcCostos('rpc_insumo_detalle', { p_fuente: fuente, p_clave: clave })
  if (error) throw new Error(error.message)
  return data as DetalleInsumo
}
