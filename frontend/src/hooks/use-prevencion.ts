import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  getPrevencionResumen,
  getSuspelProductos,
  getSuspelBodegas,
  getRespelTipos,
  getRespelMovimientos,
  getRespelEmpresas,
  createRespelMovimiento,
  getCertificacionesProximasVencer,
} from '@/lib/services/prevencion'

export function usePrevencionResumen() {
  return useQuery({
    queryKey: ['prevencion-resumen'],
    queryFn: async () => {
      const { data, error } = await getPrevencionResumen()
      if (error) throw error
      return data
    },
  })
}

export function useSuspelProductos() {
  return useQuery({
    queryKey: ['suspel-productos'],
    queryFn: async () => {
      const { data, error } = await getSuspelProductos(true)
      if (error) throw error
      return data
    },
  })
}

export function useSuspelBodegas() {
  return useQuery({
    queryKey: ['suspel-bodegas'],
    queryFn: async () => {
      const { data, error } = await getSuspelBodegas(true)
      if (error) throw error
      return data
    },
  })
}

export function useRespelTipos() {
  return useQuery({
    queryKey: ['respel-tipos'],
    queryFn: async () => {
      const { data, error } = await getRespelTipos()
      if (error) throw error
      return data
    },
  })
}

export function useRespelMovimientos(limit?: number) {
  return useQuery({
    queryKey: ['respel-movimientos', limit],
    queryFn: async () => {
      const { data, error } = await getRespelMovimientos(limit)
      if (error) throw error
      return data
    },
  })
}

export function useRespelEmpresas() {
  return useQuery({
    queryKey: ['respel-empresas'],
    queryFn: async () => {
      const { data, error } = await getRespelEmpresas()
      if (error) throw error
      return data
    },
  })
}

export function useCreateRespelMovimiento() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (mov: Parameters<typeof createRespelMovimiento>[0]) => {
      const { data, error } = await createRespelMovimiento(mov)
      if (error) throw error
      return data
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['respel-movimientos'] })
      qc.invalidateQueries({ queryKey: ['prevencion-resumen'] })
    },
  })
}

export function useCertificacionesProximasVencer(dias = 60) {
  return useQuery({
    queryKey: ['cert-proximas-vencer', dias],
    queryFn: async () => {
      const { data, error } = await getCertificacionesProximasVencer(dias)
      if (error) throw error
      return data
    },
  })
}
