import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  getIncentivosDelPeriodo,
  calcularIncentivos,
  getKPIDrillDown,
  cerrarPeriodoKPI,
  getSnapshotsMensuales,
} from '@/lib/services/incentivos'

export function useIncentivos(contratoId?: string, periodoInicio?: string) {
  return useQuery({
    queryKey: ['incentivos', contratoId, periodoInicio],
    queryFn: async () => {
      const { data, error } = await getIncentivosDelPeriodo(contratoId!, periodoInicio)
      if (error) throw error
      return data
    },
    enabled: !!contratoId,
  })
}

export function useCalcularIncentivos() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: async ({ contratoId, periodoInicio, periodoFin }: { contratoId: string; periodoInicio?: string; periodoFin?: string }) => {
      const { data, error } = await calcularIncentivos(contratoId, periodoInicio, periodoFin)
      if (error) throw error
      return data
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['incentivos'] })
    },
  })
}

export function useKPIDrillDown(kpiCodigo?: string, contratoId?: string, faenaId?: string, periodo?: string) {
  return useQuery({
    queryKey: ['kpi-drill-down', kpiCodigo, contratoId, periodo],
    queryFn: async () => {
      const { data, error } = await getKPIDrillDown(kpiCodigo!, contratoId!, faenaId)
      if (error) throw error
      return data
    },
    enabled: !!kpiCodigo && !!contratoId,
  })
}

export function useCerrarPeriodo() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: async ({ contratoId, periodo, usuarioId }: { contratoId: string; periodo?: string; usuarioId?: string }) => {
      const { data, error } = await cerrarPeriodoKPI(contratoId, periodo, usuarioId)
      if (error) throw error
      return data
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['snapshots'] })
      queryClient.invalidateQueries({ queryKey: ['incentivos'] })
    },
  })
}

export function useSnapshots(contratoId?: string) {
  return useQuery({
    queryKey: ['snapshots', contratoId],
    queryFn: async () => {
      const { data, error } = await getSnapshotsMensuales(contratoId!)
      if (error) throw error
      return data
    },
    enabled: !!contratoId,
  })
}
