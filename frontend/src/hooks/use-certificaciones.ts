import { useQuery } from '@tanstack/react-query'
import {
  getCertificaciones,
  getCertificacionesVencidas,
  getProximosVencimientos,
  getAllCertificaciones,
  getCertificacionStats,
} from '@/lib/services/certificaciones'

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

// Las mutaciones de documentación viven en lib/services/taller-planificacion.ts
// (renovarCertificacion / subirDocumentoCert / adjuntarArchivoCertificacion).
