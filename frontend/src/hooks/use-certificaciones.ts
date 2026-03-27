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
    queryKey: ['certificaciones', filters],
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
    mutationFn: async ({
      data,
      file,
    }: {
      data: Omit<Certificacion, 'id' | 'created_at' | 'updated_at' | 'archivo_url'> & {
        archivo_url?: string | null
      }
      file?: File
    }) => {
      const { data: created, error } = await createCertificacion(data, file)
      if (error) throw error
      return created
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['certificaciones'] })
      queryClient.invalidateQueries({ queryKey: ['certificacion-stats'] })
      queryClient.invalidateQueries({ queryKey: ['certificaciones-vencidas'] })
      queryClient.invalidateQueries({ queryKey: ['proximos-vencimientos'] })
    },
  })
}
