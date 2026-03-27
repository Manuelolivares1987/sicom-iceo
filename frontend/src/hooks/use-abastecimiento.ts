import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  getRutasDespacho,
  getAbastecimientos,
  getRutaStats,
  createRutaDespacho,
  updateRutaEstado,
  createAbastecimiento,
  getPuntosPorFaena,
} from '@/lib/services/abastecimiento'

// ── Queries ──────────────────────────────────────────────

export function useRutasDespacho(filters?: Record<string, string>) {
  return useQuery({
    queryKey: ['rutas-despacho', filters],
    queryFn: async () => {
      const { data, error } = await getRutasDespacho(filters)
      if (error) throw error
      return data
    },
  })
}

export function useAbastecimientos(rutaId?: string) {
  return useQuery({
    queryKey: ['abastecimientos', rutaId],
    queryFn: async () => {
      const { data, error } = await getAbastecimientos(rutaId)
      if (error) throw error
      return data
    },
  })
}

export function useRutaStats(faenaId?: string) {
  return useQuery({
    queryKey: ['ruta-stats', faenaId],
    queryFn: async () => {
      const { data, error } = await getRutaStats(faenaId)
      if (error) throw error
      return data
    },
  })
}

export function usePuntosPorFaena(faenaId: string | undefined) {
  return useQuery({
    queryKey: ['puntos-faena', faenaId],
    queryFn: async () => {
      const { data, error } = await getPuntosPorFaena(faenaId!)
      if (error) throw error
      return data
    },
    enabled: !!faenaId,
  })
}

// ── Mutations ────────────────────────────────────────────

export function useCreateRuta() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: async (payload: {
      faena_id: string
      fecha_programada: string
      puntos_programados?: number
      km_programados?: number
    }) => {
      const { data, error } = await createRutaDespacho(payload)
      if (error) throw error
      return data
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['rutas-despacho'] })
      queryClient.invalidateQueries({ queryKey: ['ruta-stats'] })
    },
  })
}

export function useUpdateRutaEstado() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: async ({ id, estado }: { id: string; estado: string }) => {
      const { data, error } = await updateRutaEstado(id, estado)
      if (error) throw error
      return data
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['rutas-despacho'] })
      queryClient.invalidateQueries({ queryKey: ['ruta-stats'] })
    },
  })
}

export function useCreateAbastecimiento() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: async (payload: {
      ruta_despacho_id?: string
      producto_id: string
      cantidad_programada?: number
      cantidad_real?: number
    }) => {
      const { data, error } = await createAbastecimiento(payload)
      if (error) throw error
      return data
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['abastecimientos'] })
    },
  })
}
