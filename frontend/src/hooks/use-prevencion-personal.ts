import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  getControlDocumental,
  actualizarExamen,
  type ActualizarExamenInput,
} from '@/lib/services/prevencion-personal'

export function useControlDocumental(faena?: string | null) {
  return useQuery({
    queryKey: ['prevencion-control-documental', faena ?? 'todas'],
    queryFn: () => getControlDocumental(faena),
    // Corto: es una pantalla donde se corrige un vencimiento y se espera verlo.
    staleTime: 60_000,
  })
}

export function useActualizarExamen(faena?: string | null) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (input: ActualizarExamenInput) => actualizarExamen(input),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['prevencion-control-documental', faena ?? 'todas'] })
    },
  })
}
