import { useQuery } from '@tanstack/react-query'
import {
  getPlanesMantenmiento,
  getPautasFabricante,
  getProximasMantenimientos,
  getMantenimientosVencidos,
} from '@/lib/services/mantenimiento'

export function usePlanes(filters?: { faena_id?: string; tipo_plan?: string }) {
  return useQuery({
    queryKey: ['planes-mantenimiento', filters],
    queryFn: async () => {
      const { data, error } = await getPlanesMantenmiento(filters)
      if (error) throw error
      return data
    },
  })
}

export function useProximasMantenimientos(dias?: number) {
  return useQuery({
    queryKey: ['proximas-mantenimientos', dias],
    queryFn: async () => {
      const { data, error } = await getProximasMantenimientos(dias)
      if (error) throw error
      return data
    },
  })
}

export function useMantenimientosVencidos() {
  return useQuery({
    queryKey: ['mantenimientos-vencidos'],
    queryFn: async () => {
      const { data, error } = await getMantenimientosVencidos()
      if (error) throw error
      return data
    },
  })
}

export function usePautasFabricante(modeloId?: string) {
  return useQuery({
    queryKey: ['pautas-fabricante', modeloId],
    queryFn: async () => {
      const { data, error } = await getPautasFabricante(modeloId)
      if (error) throw error
      return data
    },
  })
}
