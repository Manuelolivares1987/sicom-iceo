import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  getCertificaciones,
  getCertificacionesVencidas,
  getProximosVencimientos,
  getAllCertificaciones,
  getCertificacionStats,
  createCertificacion,
} from '@/lib/services/certificaciones'
import type { Certificacion } from '@/types/database'

// ── Queries ──────────────────────────────────────────────

export function useCertificaciones(activoId?: string) {
  return useQuery({
    queryKey: ['certificaciones', activoId],
    queryFn: async () => {
      const { data, error } = await getCertificaciones(activoId)
      if (error) throw error
      return data
    },
  })
}

export function useCertificacionesVencidas() {
  return useQuery({
    queryKey: ['certificaciones-vencidas'],
    queryFn: async () => {
      const { data, error } = await getCertificacionesVencidas()
      if (error) throw error
      return data
    },
  })
}

export function useProximosVencimientos(dias?: number) {
  return useQuery({
    queryKey: ['proximos-vencimientos', dias],
    queryFn: async () => {
      const { data, error } = await getProximosVencimientos(dias)
      if (error) throw error
      return data
    },
  })
}

export function useAllCertificaciones(filters?: {
  estado?: string
  tipo?: string
  faena_id?: string
}) {
  return useQuery({
    queryKey: ['all-certificaciones', filters],
    queryFn: async () => {
      const { data, error } = await getAllCertificaciones(filters)
      if (error) throw error
      return data
    },
  })
}

export function useCertificacionStats() {
  return useQuery({
    queryKey: ['certificacion-stats'],
    queryFn: async () => {
      const { data, error } = await getCertificacionStats()
      if (error) throw error
      return data
    },
  })
}

// ── Mutations ────────────────────────────────────────────

export function useCreateCertificacion() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: async (
      payload: Omit<Certificacion, 'id' | 'created_at' | 'updated_at'>
    ) => {
      const { data, error } = await createCertificacion(payload)
      if (error) throw error
      return data
    },
    onSuccess: (_data, variables) => {
      queryClient.invalidateQueries({ queryKey: ['certificaciones'] })
      queryClient.invalidateQueries({
        queryKey: ['certificaciones', variables.activo_id],
      })
      queryClient.invalidateQueries({ queryKey: ['certificaciones-vencidas'] })
      queryClient.invalidateQueries({ queryKey: ['proximos-vencimientos'] })
    },
  })
}
