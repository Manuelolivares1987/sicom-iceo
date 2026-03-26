import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  getOrdenesTrabajo,
  getOrdenTrabajoById,
  getOTsStats,
  createOrdenTrabajo,
  iniciarOT,
  pausarOT,
  finalizarOT,
  noEjecutarOT,
  cerrarOTSupervisor,
  updateChecklistItem,
  addEvidencia,
  getChecklistOT,
  getEvidenciasOT,
  getMaterialesOT,
  getHistorialOT,
} from '@/lib/services/ordenes-trabajo'
import type { CreateOTParams } from '@/lib/services/ordenes-trabajo'
import type { OrdenTrabajo } from '@/types/database'

// ── Queries ──────────────────────────────────────────────

export function useOrdenesTrabajo(filters?: Record<string, unknown>) {
  return useQuery({
    queryKey: ['ordenes-trabajo', filters],
    queryFn: async () => {
      const { data, error } = await getOrdenesTrabajo(filters)
      if (error) throw error
      return data
    },
  })
}

export function useOrdenTrabajo(id: string | undefined) {
  return useQuery({
    queryKey: ['orden-trabajo', id],
    queryFn: async () => {
      const { data, error } = await getOrdenTrabajoById(id!)
      if (error) throw error
      return data
    },
    enabled: !!id,
  })
}

export function useOTsStats(faenaId?: string) {
  return useQuery({
    queryKey: ['ots-stats', faenaId],
    queryFn: async () => {
      const { data, error } = await getOTsStats(faenaId)
      if (error) throw error
      return data
    },
  })
}

export function useChecklistOT(otId: string | undefined) {
  return useQuery({
    queryKey: ['checklist-ot', otId],
    queryFn: async () => {
      const { data, error } = await getChecklistOT(otId!)
      if (error) throw error
      return data
    },
    enabled: !!otId,
  })
}

export function useEvidenciasOT(otId: string | undefined) {
  return useQuery({
    queryKey: ['evidencias-ot', otId],
    queryFn: async () => {
      const { data, error } = await getEvidenciasOT(otId!)
      if (error) throw error
      return data
    },
    enabled: !!otId,
  })
}

export function useMaterialesOT(otId: string | undefined) {
  return useQuery({
    queryKey: ['materiales-ot', otId],
    queryFn: async () => {
      const { data, error } = await getMaterialesOT(otId!)
      if (error) throw error
      return data
    },
    enabled: !!otId,
  })
}

export function useHistorialOT(otId: string | undefined) {
  return useQuery({
    queryKey: ['historial-ot', otId],
    queryFn: async () => {
      const { data, error } = await getHistorialOT(otId!)
      if (error) throw error
      return data
    },
    enabled: !!otId,
  })
}

// ── Mutations ────────────────────────────────────────────

export function useCreateOT() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: async (payload: CreateOTParams) => {
      const { data, error } = await createOrdenTrabajo(payload)
      if (error) throw error
      return data
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['ordenes-trabajo'] })
    },
  })
}

export function useIniciarOT() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: async ({ id, userId }: { id: string; userId: string }) => {
      const { data, error } = await iniciarOT(id, userId)
      if (error) throw error
      return data
    },
    onSuccess: (_data, { id }) => {
      queryClient.invalidateQueries({ queryKey: ['orden-trabajo', id] })
      queryClient.invalidateQueries({ queryKey: ['ordenes-trabajo'] })
    },
  })
}

export function usePausarOT() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: async ({ id, userId, motivo }: { id: string; userId: string; motivo?: string }) => {
      const { data, error } = await pausarOT(id, userId, motivo)
      if (error) throw error
      return data
    },
    onSuccess: (_data, { id }) => {
      queryClient.invalidateQueries({ queryKey: ['orden-trabajo', id] })
      queryClient.invalidateQueries({ queryKey: ['ordenes-trabajo'] })
    },
  })
}

export function useFinalizarOT() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: async ({
      id,
      userId,
      observaciones,
    }: {
      id: string
      userId: string
      observaciones?: string
    }) => {
      const { data, error } = await finalizarOT(id, userId, observaciones)
      if (error) throw error
      return data
    },
    onSuccess: (_data, { id }) => {
      queryClient.invalidateQueries({ queryKey: ['orden-trabajo', id] })
      queryClient.invalidateQueries({ queryKey: ['ordenes-trabajo'] })
      queryClient.invalidateQueries({ queryKey: ['ots-stats'] })
    },
  })
}

export function useNoEjecutarOT() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: async ({
      id,
      userId,
      causa,
      detalle,
    }: {
      id: string
      userId: string
      causa: string
      detalle?: string
    }) => {
      const { data, error } = await noEjecutarOT(id, userId, causa, detalle)
      if (error) throw error
      return data
    },
    onSuccess: (_data, { id }) => {
      queryClient.invalidateQueries({ queryKey: ['orden-trabajo', id] })
      queryClient.invalidateQueries({ queryKey: ['ordenes-trabajo'] })
      queryClient.invalidateQueries({ queryKey: ['ots-stats'] })
    },
  })
}

export function useCerrarOTSupervisor() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: async ({
      id,
      supervisorId,
      observaciones,
    }: {
      id: string
      supervisorId: string
      observaciones?: string
    }) => {
      const { data, error } = await cerrarOTSupervisor(id, supervisorId, observaciones)
      if (error) throw error
      return data
    },
    onSuccess: (_data, { id }) => {
      queryClient.invalidateQueries({ queryKey: ['orden-trabajo', id] })
      queryClient.invalidateQueries({ queryKey: ['ordenes-trabajo'] })
      queryClient.invalidateQueries({ queryKey: ['ots-stats'] })
    },
  })
}

export function useUpdateChecklistItem() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: async ({
      otId,
      itemId,
      resultado,
      observacion,
      foto_url,
      completado_por,
    }: {
      otId: string
      itemId: string
      resultado?: 'ok' | 'no_ok' | 'na' | null
      observacion?: string | null
      foto_url?: string | null
      completado_por?: string
    }) => {
      const { data, error } = await updateChecklistItem(itemId, {
        resultado,
        observacion,
        foto_url,
        completado_por,
      })
      if (error) throw error
      return data
    },
    onSuccess: (_data, { otId }) => {
      queryClient.invalidateQueries({ queryKey: ['orden-trabajo', otId] })
      queryClient.invalidateQueries({ queryKey: ['checklist-ot', otId] })
    },
  })
}

export function useAddEvidencia() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: async ({
      otId,
      archivo,
      tipo,
      descripcion,
    }: {
      otId: string
      archivo: File
      tipo: string
      descripcion?: string
    }) => {
      const { data, error } = await addEvidencia(otId, archivo, tipo, descripcion)
      if (error) throw error
      return data
    },
    onSuccess: (_data, { otId }) => {
      queryClient.invalidateQueries({ queryKey: ['orden-trabajo', otId] })
      queryClient.invalidateQueries({ queryKey: ['evidencias-ot', otId] })
    },
  })
}
