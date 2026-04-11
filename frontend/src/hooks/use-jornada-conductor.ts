import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  registrarActividad,
  getActividadActual,
  getResumenDia,
  getResumenMes,
  getConductoresTiempoReal,
  getHistorialActividades,
  type ActividadConductor,
} from '@/lib/services/jornada-conductor'

export function useRegistrarActividad() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (params: {
      conductor_id: string
      activo_id?: string
      actividad: ActividadConductor
      ubicacion_texto?: string
      latitud?: number
      longitud?: number
    }) => {
      const { data, error } = await registrarActividad(params)
      if (error) throw error
      return data
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['actividad-actual'] })
      qc.invalidateQueries({ queryKey: ['resumen-dia'] })
      qc.invalidateQueries({ queryKey: ['resumen-mes'] })
      qc.invalidateQueries({ queryKey: ['conductores-tiempo-real'] })
      qc.invalidateQueries({ queryKey: ['conductores'] })
    },
  })
}

export function useActividadActual(conductorId?: string) {
  return useQuery({
    queryKey: ['actividad-actual', conductorId],
    queryFn: async () => {
      const { data, error } = await getActividadActual(conductorId!)
      if (error) throw error
      return data
    },
    enabled: !!conductorId,
    refetchInterval: 30000, // Refrescar cada 30 segundos
  })
}

export function useResumenDia(conductorId?: string, fecha?: string) {
  return useQuery({
    queryKey: ['resumen-dia', conductorId, fecha],
    queryFn: async () => {
      const { data, error } = await getResumenDia(conductorId!, fecha)
      if (error) throw error
      return data
    },
    enabled: !!conductorId,
  })
}

export function useResumenMes(conductorId?: string) {
  return useQuery({
    queryKey: ['resumen-mes', conductorId],
    queryFn: async () => {
      const { data, error } = await getResumenMes(conductorId!)
      if (error) throw error
      return data
    },
    enabled: !!conductorId,
  })
}

export function useConductoresTiempoReal() {
  return useQuery({
    queryKey: ['conductores-tiempo-real'],
    queryFn: async () => {
      const { data, error } = await getConductoresTiempoReal()
      if (error) throw error
      return data
    },
    refetchInterval: 60000, // Cada minuto
  })
}

export function useHistorialActividades(conductorId?: string, fechaInicio?: string, fechaFin?: string) {
  return useQuery({
    queryKey: ['historial-actividades', conductorId, fechaInicio, fechaFin],
    queryFn: async () => {
      const { data, error } = await getHistorialActividades(conductorId!, fechaInicio!, fechaFin!)
      if (error) throw error
      return data
    },
    enabled: !!conductorId && !!fechaInicio && !!fechaFin,
  })
}
