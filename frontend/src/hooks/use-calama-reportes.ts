import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  getEstadoPlanificacionOTs, getReporteAtrasos, getCalidadDatos,
  getReporteSemanal, agregarJornadaOT,
} from '@/lib/services/calama-reportes'

export function useEstadoPlanificacionOTs() {
  return useQuery({
    queryKey: ['calama-estado-planif'],
    queryFn: async () => {
      const { data, error } = await getEstadoPlanificacionOTs()
      if (error) throw error
      return data
    },
  })
}

export function useReporteAtrasos() {
  return useQuery({
    queryKey: ['calama-reporte-atrasos'],
    queryFn: async () => {
      const { data, error } = await getReporteAtrasos()
      if (error) throw error
      return data
    },
  })
}

export function useCalidadDatos() {
  return useQuery({
    queryKey: ['calama-calidad-datos'],
    queryFn: async () => {
      const { data, error } = await getCalidadDatos()
      if (error) throw error
      return data
    },
  })
}

export function useReporteSemanal() {
  return useQuery({
    queryKey: ['calama-reporte-semanal'],
    queryFn: async () => {
      const { data, error } = await getReporteSemanal()
      if (error) throw error
      return data
    },
  })
}

export function useAgregarJornadaOT() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (payload: Parameters<typeof agregarJornadaOT>[0]) => {
      const { data, error } = await agregarJornadaOT(payload)
      if (error) throw error
      return data
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['calama-plan-sem-ots'] })
      qc.invalidateQueries({ queryKey: ['calama-mis-ots'] })
      qc.invalidateQueries({ queryKey: ['calama-estado-planif'] })
    },
  })
}
