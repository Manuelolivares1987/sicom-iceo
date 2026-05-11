import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  listarOTsValidasSalida, listarBodegasPorFaena, listarCECO,
  listarStockDisponible, previewFIFO, registrarSalidaFifo,
  type SalidaFifoPayload,
} from '@/lib/services/bodega-salida-fifo'

const STALE = 30_000

export function useOTsValidasSalida() {
  return useQuery({
    queryKey: ['bodega-salida', 'ots-validas'],
    queryFn: async () => {
      const { data, error } = await listarOTsValidasSalida()
      if (error) throw error
      return data ?? []
    },
    staleTime: STALE,
  })
}

export function useBodegasPorFaena(faenaId: string | null | undefined) {
  return useQuery({
    queryKey: ['bodega-salida', 'bodegas', faenaId ?? null],
    queryFn: async () => {
      const { data, error } = await listarBodegasPorFaena(faenaId ?? null)
      if (error) throw error
      return data ?? []
    },
    enabled: !!faenaId,
    staleTime: 5 * 60_000,
  })
}

export function useCECO() {
  return useQuery({
    queryKey: ['bodega-salida', 'cecos'],
    queryFn: async () => {
      const { data, error } = await listarCECO()
      if (error) throw error
      return data ?? []
    },
    staleTime: 5 * 60_000,
  })
}

export function useStockDisponible(bodegaId: string | null | undefined) {
  return useQuery({
    queryKey: ['bodega-salida', 'stock', bodegaId ?? null],
    queryFn: async () => {
      const { data, error } = await listarStockDisponible(bodegaId ?? null)
      if (error) throw error
      return data ?? []
    },
    enabled: !!bodegaId,
    staleTime: STALE,
  })
}

export function usePreviewFIFO(productoId: string | null, bodegaId: string | null) {
  return useQuery({
    queryKey: ['bodega-salida', 'preview-fifo', productoId, bodegaId],
    queryFn: async () => {
      const { data, error } = await previewFIFO(productoId!, bodegaId!)
      if (error) throw error
      return data ?? []
    },
    enabled: !!productoId && !!bodegaId,
    staleTime: STALE,
  })
}

export function useRegistrarSalidaFifo() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (payload: SalidaFifoPayload) => {
      const { data, error } = await registrarSalidaFifo(payload)
      if (error) throw error
      return data!
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['bodega-salida'] })
      qc.invalidateQueries({ queryKey: ['bodega-reconciliacion'] })
      qc.invalidateQueries({ queryKey: ['stock-bodega'] })
      qc.invalidateQueries({ queryKey: ['movimientos'] })
      qc.invalidateQueries({ queryKey: ['kardex'] })
      qc.invalidateQueries({ queryKey: ['productos'] })
    },
  })
}
