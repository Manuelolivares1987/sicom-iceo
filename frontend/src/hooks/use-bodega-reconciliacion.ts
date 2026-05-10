import { useQuery } from '@tanstack/react-query'
import {
  getReconciliacionStockFifo,
  getReconciliacionCombustible,
  getMovimientosExcepcionales,
  getReconciliacionResumen,
  type FiltrosStockFifo,
  type FiltrosCombustible,
  type FiltrosMovimientosExcepcionales,
} from '@/lib/services/bodega-reconciliacion'

const STALE = 60_000

export function useReconciliacionResumen() {
  return useQuery({
    queryKey: ['bodega-reconciliacion', 'resumen'],
    queryFn: async () => {
      const { data, error } = await getReconciliacionResumen()
      if (error) throw error
      return data!
    },
    staleTime: STALE,
  })
}

export function useReconciliacionStockFifo(filtros?: FiltrosStockFifo) {
  return useQuery({
    queryKey: ['bodega-reconciliacion', 'stock-fifo', filtros],
    queryFn: async () => {
      const { data, error } = await getReconciliacionStockFifo(filtros)
      if (error) throw error
      return data ?? []
    },
    staleTime: STALE,
  })
}

export function useReconciliacionCombustible(filtros?: FiltrosCombustible) {
  return useQuery({
    queryKey: ['bodega-reconciliacion', 'combustible', filtros],
    queryFn: async () => {
      const { data, error } = await getReconciliacionCombustible(filtros)
      if (error) throw error
      return data ?? []
    },
    staleTime: STALE,
  })
}

export function useMovimientosExcepcionales(filtros?: FiltrosMovimientosExcepcionales) {
  return useQuery({
    queryKey: ['bodega-reconciliacion', 'mov-excepcionales', filtros],
    queryFn: async () => {
      const { data, error } = await getMovimientosExcepcionales(filtros)
      if (error) throw error
      return data ?? []
    },
    staleTime: STALE,
  })
}
