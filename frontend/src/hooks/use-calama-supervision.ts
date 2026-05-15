import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  getJornadasPendientesSupervision, getEvidenciasPorOT, getFirmasPorJornada,
  supervisarJornada, devolverJornadaCorreccion,
  getJornadasEnVivo, getResumenHoy,
  type JornadasFiltro,
} from '@/lib/services/calama-supervision'

const KEY = {
  pendientes: (f?: JornadasFiltro) => ['calama', 'supervision', 'pendientes', f ?? {}] as const,
  evidencias: (otId: string) => ['calama', 'supervision', 'evid', otId] as const,
  firmas:     (planOtId: string) => ['calama', 'supervision', 'firmas', planOtId] as const,
  enVivo:     (planId?: string | null) => ['calama', 'supervision', 'en-vivo', planId ?? null] as const,
  resumenHoy: ['calama', 'supervision', 'resumen-hoy'] as const,
}

export function useJornadasPendientesSupervision(filtro?: JornadasFiltro) {
  return useQuery({
    queryKey: KEY.pendientes(filtro),
    queryFn: async () => {
      const { data, error } = await getJornadasPendientesSupervision(filtro)
      if (error) throw error
      return data
    },
  })
}

export function useEvidenciasPorOT(otId: string | null | undefined) {
  return useQuery({
    queryKey: KEY.evidencias(otId ?? ''),
    queryFn: async () => {
      const { data, error } = await getEvidenciasPorOT(otId!)
      if (error) throw error
      return data
    },
    enabled: !!otId,
  })
}

export function useFirmasPorJornada(planSemanalOtId: string | null | undefined) {
  return useQuery({
    queryKey: KEY.firmas(planSemanalOtId ?? ''),
    queryFn: async () => {
      const { data, error } = await getFirmasPorJornada(planSemanalOtId!)
      if (error) throw error
      return data
    },
    enabled: !!planSemanalOtId,
  })
}

export function useSupervisarJornada() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (payload: { plan_semanal_ot_id: string; comentario?: string }) => {
      const { data, error } = await supervisarJornada(payload)
      if (error) throw error
      return data
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['calama', 'supervision', 'pendientes'] })
      qc.invalidateQueries({ queryKey: ['calama', 'ots'] })
      qc.invalidateQueries({ queryKey: ['calama', 'dashboard'] })
    },
  })
}

export function useDevolverJornadaCorreccion() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (payload: { plan_semanal_ot_id: string; motivo: string; observacion?: string }) => {
      const { data, error } = await devolverJornadaCorreccion(payload)
      if (error) throw error
      return data
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['calama', 'supervision', 'pendientes'] })
      qc.invalidateQueries({ queryKey: ['calama', 'ots'] })
      qc.invalidateQueries({ queryKey: ['calama', 'dashboard'] })
    },
  })
}

// MIG50 - tablero en vivo + cierre del dia. Auto-refresh 30s.

export function useJornadasEnVivo(planificacionId?: string | null) {
  return useQuery({
    queryKey: KEY.enVivo(planificacionId),
    queryFn: async () => {
      const { data, error } = await getJornadasEnVivo(planificacionId)
      if (error) throw error
      return data
    },
    refetchInterval: 30_000,
    refetchIntervalInBackground: false,
    staleTime: 25_000,
  })
}

export function useResumenHoy() {
  return useQuery({
    queryKey: KEY.resumenHoy,
    queryFn: async () => {
      const { data, error } = await getResumenHoy()
      if (error) throw error
      return data
    },
    refetchInterval: 30_000,
    refetchIntervalInBackground: false,
    staleTime: 25_000,
  })
}
