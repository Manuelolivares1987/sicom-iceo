import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  getActivos,
  getActivoById,
  createActivo,
  updateActivo,
  getOTsByActivo,
  getPlanesByActivo,
  getCertificacionesByActivo,
  getCostosByActivo,
  actualizarMetricasActivo,
  getFichaActivo,
  generarQRActivo,
  getHistorialMantenimiento,
  getKPIActivo,
  getRankingActivos,
} from '@/lib/services/activos'
import type { Activo } from '@/types/database'

// ── Queries ──────────────────────────────────────────────

export function useActivos(filters?: Record<string, unknown>) {
  return useQuery({
    queryKey: ['activos', filters],
    queryFn: async () => {
      const { data, error } = await getActivos(filters)
      if (error) throw error
      return data
    },
  })
}

export function useActivo(id: string | undefined) {
  return useQuery({
    queryKey: ['activo', id],
    queryFn: async () => {
      const { data, error } = await getActivoById(id!)
      if (error) throw error
      return data
    },
    enabled: !!id,
  })
}

export function useOTsByActivo(activoId?: string) {
  return useQuery({
    queryKey: ['ots-activo', activoId],
    queryFn: async () => {
      const { data, error } = await getOTsByActivo(activoId!)
      if (error) throw error
      return data
    },
    enabled: !!activoId,
  })
}

export function usePlanesByActivo(activoId?: string) {
  return useQuery({
    queryKey: ['planes-activo', activoId],
    queryFn: async () => {
      const { data, error } = await getPlanesByActivo(activoId!)
      if (error) throw error
      return data
    },
    enabled: !!activoId,
  })
}

export function useCertificacionesByActivo(activoId?: string) {
  return useQuery({
    queryKey: ['certificaciones-activo', activoId],
    queryFn: async () => {
      const { data, error } = await getCertificacionesByActivo(activoId!)
      if (error) throw error
      return data
    },
    enabled: !!activoId,
  })
}

export function useCostosByActivo(activoId?: string) {
  return useQuery({
    queryKey: ['costos-activo', activoId],
    queryFn: async () => {
      const { data, error } = await getCostosByActivo(activoId!)
      if (error) throw error
      return data
    },
    enabled: !!activoId,
  })
}

// ── Mutations ────────────────────────────────────────────

export function useCreateActivo() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: async (
      payload: Omit<Activo, 'id' | 'created_at' | 'updated_at'>
    ) => {
      const { data, error } = await createActivo(payload)
      if (error) throw error
      return data
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['activos'] })
    },
  })
}

export function useUpdateActivo() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: async ({
      id,
      updates,
    }: {
      id: string
      updates: Partial<Omit<Activo, 'id'>>
    }) => {
      const { data, error } = await updateActivo(id, updates)
      if (error) throw error
      return data
    },
    onSuccess: (_data, { id }) => {
      queryClient.invalidateQueries({ queryKey: ['activo', id] })
      queryClient.invalidateQueries({ queryKey: ['activos'] })
    },
  })
}

export function useActualizarMetricas() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: async (payload: {
      activo_id: string
      kilometraje?: number
      horas_uso?: number
      ciclos?: number
      usuario_id?: string
    }) => {
      const { data, error } = await actualizarMetricasActivo(payload)
      if (error) throw error
      return data
    },
    onSuccess: (_data, { activo_id }) => {
      queryClient.invalidateQueries({ queryKey: ['activo', activo_id] })
      queryClient.invalidateQueries({ queryKey: ['activos'] })
      queryClient.invalidateQueries({ queryKey: ['planes-mantenimiento'] })
      queryClient.invalidateQueries({ queryKey: ['proximas-mantenimientos'] })
    },
  })
}

export function useFichaActivo(activoId?: string) {
  return useQuery({
    queryKey: ['ficha-activo', activoId],
    queryFn: async () => {
      const { data, error } = await getFichaActivo(activoId!)
      if (error) throw error
      return data
    },
    enabled: !!activoId,
  })
}

export function useHistorialMantenimiento(activoId?: string) {
  return useQuery({
    queryKey: ['historial-mantenimiento', activoId],
    queryFn: async () => {
      const { data, error } = await getHistorialMantenimiento(activoId!)
      if (error) throw error
      return data
    },
    enabled: !!activoId,
  })
}

export function useGenerarQR() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: async (activoId: string) => {
      const { data, error } = await generarQRActivo(activoId)
      if (error) throw error
      return data
    },
    onSuccess: (_data, activoId) => {
      queryClient.invalidateQueries({ queryKey: ['activo', activoId] })
      queryClient.invalidateQueries({ queryKey: ['ficha-activo', activoId] })
    },
  })
}

export function useKPIActivo(activoId?: string) {
  return useQuery({
    queryKey: ['kpi-activo', activoId],
    queryFn: async () => {
      const { data, error } = await getKPIActivo(activoId!)
      if (error) throw error
      return data
    },
    enabled: !!activoId,
  })
}

export function useRankingActivos() {
  return useQuery({
    queryKey: ['ranking-activos'],
    queryFn: async () => {
      const { data, error } = await getRankingActivos()
      if (error) throw error
      return data
    },
  })
}
