import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  getReporteDiario,
  getReportesHistoricos,
  regenerarReporteDiario,
  getTendenciaReporte,
  getCambiosEstadoDia,
} from '@/lib/services/reporte-diario'

export function useReporteDiario(fecha?: string) {
  return useQuery({
    queryKey: ['reporte-diario', fecha],
    queryFn: async () => {
      const { data, error } = await getReporteDiario(fecha)
      if (error) throw error
      return data
    },
  })
}

export function useReportesHistoricos(limit?: number) {
  return useQuery({
    queryKey: ['reportes-historicos', limit],
    queryFn: async () => {
      const { data, error } = await getReportesHistoricos(limit)
      if (error) throw error
      return data
    },
  })
}

export function useRegenerarReporteDiario() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (fecha?: string) => {
      const { data, error } = await regenerarReporteDiario(fecha)
      if (error) throw error
      return data
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['reporte-diario'] })
      qc.invalidateQueries({ queryKey: ['reportes-historicos'] })
      qc.invalidateQueries({ queryKey: ['tendencia-reporte'] })
      qc.invalidateQueries({ queryKey: ['cambios-estado-dia'] })
    },
  })
}

export function useTendenciaReporte(dias = 30) {
  return useQuery({
    queryKey: ['tendencia-reporte', dias],
    queryFn: async () => {
      const { data, error } = await getTendenciaReporte(dias)
      if (error) throw error
      return data ?? []
    },
  })
}

export function useCambiosEstadoDia(fecha?: string) {
  return useQuery({
    queryKey: ['cambios-estado-dia', fecha],
    queryFn: async () => {
      const { data, error } = await getCambiosEstadoDia(fecha)
      if (error) throw error
      return data ?? []
    },
  })
}
