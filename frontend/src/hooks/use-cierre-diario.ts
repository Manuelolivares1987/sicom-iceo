import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  getPropuestaCierre,
  getContratosActivos,
  confirmarCierre,
  type CierreItem,
} from '@/lib/services/cierre-diario'

export function usePropuestaCierre(fecha: string) {
  return useQuery({
    queryKey: ['propuesta-cierre', fecha],
    queryFn: () => getPropuestaCierre(fecha),
    enabled: !!fecha,
    staleTime: 30_000,
  })
}

export function useContratosActivos() {
  return useQuery({
    queryKey: ['contratos-activos'],
    queryFn: getContratosActivos,
    staleTime: 5 * 60_000,
  })
}

export function useConfirmarCierre() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ fecha, items }: { fecha: string; items: CierreItem[] }) =>
      confirmarCierre(fecha, items),
    onSuccess: (_d, vars) => {
      qc.invalidateQueries({ queryKey: ['propuesta-cierre', vars.fecha] })
      qc.invalidateQueries({ queryKey: ['matriz-estados-flota'] })
      qc.invalidateQueries({ queryKey: ['fiabilidad-flota'] })
      qc.invalidateQueries({ queryKey: ['fiabilidad-detalle'] })
      qc.invalidateQueries({ queryKey: ['activos'] })
      qc.invalidateQueries({ queryKey: ['flota-vehicular'] })
    },
  })
}
