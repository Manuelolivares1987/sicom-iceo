import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  listarPruebasTerreno, crearJornadaPrueba,
  listarEvidenciasPrueba, listarEventosPrueba,
  type CrearJornadaPruebaPayload,
} from '@/lib/services/calama-pruebas'

export function useListaPruebasTerreno() {
  return useQuery({
    queryKey: ['calama-pruebas', 'lista'],
    queryFn: async () => {
      const { data, error } = await listarPruebasTerreno()
      if (error) throw error
      return data ?? []
    },
    staleTime: 30_000,
  })
}

export function useCrearJornadaPrueba() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (payload: CrearJornadaPruebaPayload) => {
      const { data, error } = await crearJornadaPrueba(payload)
      if (error) throw error
      return data!
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['calama-pruebas'] })
      qc.invalidateQueries({ queryKey: ['calama'] })
    },
  })
}

export function useEvidenciasPrueba(otId: string | null) {
  return useQuery({
    queryKey: ['calama-pruebas', 'evidencias', otId],
    queryFn: async () => {
      const { data, error } = await listarEvidenciasPrueba(otId!)
      if (error) throw error
      return data ?? []
    },
    enabled: !!otId,
    staleTime: 15_000,
  })
}

export function useEventosPrueba(otId: string | null) {
  return useQuery({
    queryKey: ['calama-pruebas', 'eventos', otId],
    queryFn: async () => {
      const { data, error } = await listarEventosPrueba(otId!)
      if (error) throw error
      return data ?? []
    },
    enabled: !!otId,
    staleTime: 15_000,
  })
}
