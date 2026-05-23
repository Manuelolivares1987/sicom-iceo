import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  registrarRecirculacion, listarRecirculaciones,
  registrarTraspaso, listarTraspasos,
  type RecirculacionPayload, type TraspasoPayload,
} from '@/lib/services/combustible-recirculacion-traspaso'

export function useRegistrarRecirculacion() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (payload: RecirculacionPayload) => {
      const { data, error } = await registrarRecirculacion(payload)
      if (error) throw error
      return data!
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['combustible'] })
    },
  })
}

export function useRecirculaciones(limit = 50) {
  return useQuery({
    queryKey: ['combustible', 'recirculaciones', limit],
    queryFn: async () => {
      const { data, error } = await listarRecirculaciones(limit)
      if (error) throw error
      return data
    },
    staleTime: 30_000,
  })
}

export function useRegistrarTraspaso() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (payload: TraspasoPayload) => {
      const { data, error } = await registrarTraspaso(payload)
      if (error) throw error
      return data!
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['combustible'] })
    },
  })
}

export function useTraspasos(limit = 50) {
  return useQuery({
    queryKey: ['combustible', 'traspasos', limit],
    queryFn: async () => {
      const { data, error } = await listarTraspasos(limit)
      if (error) throw error
      return data
    },
    staleTime: 30_000,
  })
}
