import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  getFiabilidadActivo,
  getFiabilidadFlota,
  getOEEFiabilidadActivo,
  getDetalleFiabilidadFlota,
  updateCategoriaActivo,
  type CategoriaUso,
} from '@/lib/services/fiabilidad'

export function useFiabilidadActivo(
  activoId: string | undefined,
  fechaInicio: string,
  fechaFin: string,
) {
  return useQuery({
    queryKey: ['fiabilidad-activo', activoId, fechaInicio, fechaFin],
    queryFn: async () => {
      const { data, error } = await getFiabilidadActivo(activoId!, fechaInicio, fechaFin)
      if (error) throw error
      return data ?? null
    },
    enabled: !!activoId && !!fechaInicio && !!fechaFin,
  })
}

export function useFiabilidadFlota(
  fechaInicio: string,
  fechaFin: string,
  categoria?: CategoriaUso,
) {
  return useQuery({
    queryKey: ['fiabilidad-flota', fechaInicio, fechaFin, categoria ?? 'todas'],
    queryFn: async () => {
      const { data, error } = await getFiabilidadFlota(fechaInicio, fechaFin, categoria)
      if (error) throw error
      return data ?? []
    },
    enabled: !!fechaInicio && !!fechaFin,
  })
}

export function useOEEFiabilidadActivo(
  activoId: string | undefined,
  fechaInicio: string,
  fechaFin: string,
) {
  return useQuery({
    queryKey: ['oee-fiabilidad-activo', activoId, fechaInicio, fechaFin],
    queryFn: async () => {
      const { data, error } = await getOEEFiabilidadActivo(activoId!, fechaInicio, fechaFin)
      if (error) throw error
      return data ?? null
    },
    enabled: !!activoId && !!fechaInicio && !!fechaFin,
  })
}

export function useDetalleFiabilidadFlota(fechaInicio: string, fechaFin: string) {
  return useQuery({
    queryKey: ['fiabilidad-detalle', fechaInicio, fechaFin],
    queryFn: async () => {
      const { data, error } = await getDetalleFiabilidadFlota(fechaInicio, fechaFin)
      if (error) throw error
      return data
    },
    enabled: !!fechaInicio && !!fechaFin,
    staleTime: 30_000,
  })
}

export function useUpdateCategoriaActivo() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({
      activoId,
      categoria,
    }: {
      activoId: string
      categoria: CategoriaUso | null
    }) => {
      const { data, error } = await updateCategoriaActivo(activoId, categoria)
      if (error) throw error
      return data
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['fiabilidad-flota'] })
      qc.invalidateQueries({ queryKey: ['fiabilidad-detalle'] })
      qc.invalidateQueries({ queryKey: ['activos'] })
      qc.invalidateQueries({ queryKey: ['flota-vehicular'] })
    },
  })
}
