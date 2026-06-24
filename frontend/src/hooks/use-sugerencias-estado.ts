import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { getSugerenciasEstadoGps, confirmarEstadoDia } from '@/lib/services/sugerencias-estado'

export function useSugerenciasEstado(fecha: string) {
  return useQuery({
    queryKey: ['sugerencias-estado', fecha],
    queryFn: () => getSugerenciasEstadoGps(fecha),
    enabled: !!fecha,
    staleTime: 30_000,
  })
}

export function useConfirmarEstado() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ activoId, fecha, estado }: { activoId: string; fecha: string; estado: string }) =>
      confirmarEstadoDia(activoId, fecha, estado),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['sugerencias-estado'] })
      qc.invalidateQueries({ queryKey: ['matriz-estados-flota'] })
      qc.invalidateQueries({ queryKey: ['fiabilidad-detalle'] })
      // La categoría del activo cambió → refrescar agregados por categoría.
      qc.invalidateQueries({ queryKey: ['fiabilidad-flota'] })
      qc.invalidateQueries({ queryKey: ['fiabilidad-activo'] })
      qc.invalidateQueries({ queryKey: ['oee-fiabilidad-activo'] })
      qc.invalidateQueries({ queryKey: ['activos'] })
      qc.invalidateQueries({ queryKey: ['flota-vehicular'] })
    },
  })
}
