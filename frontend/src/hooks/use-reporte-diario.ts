import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  getReporteDiario,
  getReportesHistoricos,
  regenerarReporteDiario,
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
    },
  })
}
