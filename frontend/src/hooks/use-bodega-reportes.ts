import { useQuery } from '@tanstack/react-query'
import {
  getResumenFinanciero, getStockValorizado, getCostosPorOT,
  getCostosPorCECO, getKardexProducto, getMermasAjustes,
  type FiltrosStockValorizado,
} from '@/lib/services/bodega-reportes'

const STALE = 60_000

export function useResumenFinanciero() {
  return useQuery({
    queryKey: ['bodega-reportes', 'resumen'],
    queryFn: async () => {
      const { data, error } = await getResumenFinanciero()
      if (error) throw error
      return data!
    },
    staleTime: STALE,
  })
}

export function useStockValorizado(filtros?: FiltrosStockValorizado) {
  return useQuery({
    queryKey: ['bodega-reportes', 'stock-valorizado', filtros],
    queryFn: async () => {
      const { data, error } = await getStockValorizado(filtros)
      if (error) throw error
      return data ?? []
    },
    staleTime: STALE,
  })
}

export function useCostosPorOT() {
  return useQuery({
    queryKey: ['bodega-reportes', 'costos-ot'],
    queryFn: async () => {
      const { data, error } = await getCostosPorOT()
      if (error) throw error
      return data ?? []
    },
    staleTime: STALE,
  })
}

export function useCostosPorCECO() {
  return useQuery({
    queryKey: ['bodega-reportes', 'costos-ceco'],
    queryFn: async () => {
      const { data, error } = await getCostosPorCECO()
      if (error) throw error
      return data ?? []
    },
    staleTime: STALE,
  })
}

export function useKardexProducto(productoId: string | null, bodegaId?: string | null) {
  return useQuery({
    queryKey: ['bodega-reportes', 'kardex', productoId, bodegaId ?? null],
    queryFn: async () => {
      const { data, error } = await getKardexProducto(productoId!, bodegaId ?? null)
      if (error) throw error
      return data ?? []
    },
    enabled: !!productoId,
    staleTime: STALE,
  })
}

export function useMermasAjustes(tipo: 'todos' | 'merma' | 'ajuste_negativo' | 'ajuste_positivo' = 'todos') {
  return useQuery({
    queryKey: ['bodega-reportes', 'mermas-ajustes', tipo],
    queryFn: async () => {
      const { data, error } = await getMermasAjustes(tipo)
      if (error) throw error
      return data ?? []
    },
    staleTime: STALE,
  })
}
