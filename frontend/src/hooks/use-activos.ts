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
