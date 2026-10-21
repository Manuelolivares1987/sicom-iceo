import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  getSugerenciasEstadoGps, confirmarEstadoDia, getExclusionesFiabilidad, excluirDeFiabilidad, incluirEnFiabilidad,
} from '@/lib/services/sugerencias-estado'

export function useSugerenciasEstado(fecha: string) {
  return useQuery({
    queryKey: ['sugerencias-estado', fecha],
    queryFn: () => getSugerenciasEstadoGps(fecha),
    enabled: !!fecha,
    staleTime: 30_000,
  })
}

// [MIG633] Quién está fuera del cálculo de fiabilidad, y sacar / dar de alta.
export function useExclusionesFiabilidad() {
  return useQuery({ queryKey: ['fiabilidad-exclusiones'], queryFn: getExclusionesFiabilidad, staleTime: 30_000 })
}

export function useCambiarExclusionFiabilidad() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (v: { activoId: string; incluir: boolean; desde: string | null; motivo?: string }) =>
      v.incluir ? incluirEnFiabilidad(v.activoId, v.desde) : excluirDeFiabilidad(v.activoId, v.motivo ?? '', v.desde),
    onSuccess: () => {
      for (const k of ['fiabilidad-exclusiones', 'fiabilidad-excluidos', 'matriz-estados-flota', 'fiabilidad-detalle',
                       'fiabilidad-flota', 'fiabilidad-activo', 'oee-fiabilidad-activo']) {
        qc.invalidateQueries({ queryKey: [k] })
      }
    },
  })
}

export function useConfirmarEstado() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ activoId, fecha, estado, justificacion }:
      { activoId: string; fecha: string; estado: string; justificacion?: string }) =>
      confirmarEstadoDia(activoId, fecha, estado, justificacion),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['sugerencias-estado'] })
      qc.invalidateQueries({ queryKey: ['matriz-estados-flota'] })
      qc.invalidateQueries({ queryKey: ['fiabilidad-detalle'] })
      // La categoría del activo cambió → refrescar agregados por categoría.
      qc.invalidateQueries({ queryKey: ['fiabilidad-flota'] })
      qc.invalidateQueries({ queryKey: ['fiabilidad-activo'] })
      qc.invalidateQueries({ queryKey: ['oee-fiabilidad-activo'] })
      qc.invalidateQueries({ queryKey: ['activos'] })
      // MIG307: la ficha del equipo se sincroniza con lo confirmado aquí.
      qc.invalidateQueries({ queryKey: ['activo'] })
      qc.invalidateQueries({ queryKey: ['estados-planificador'] })
      qc.invalidateQueries({ queryKey: ['flota-vehicular'] })
    },
  })
}
