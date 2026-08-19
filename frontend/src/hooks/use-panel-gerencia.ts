import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  getPanelGerencia,
  guardarComentario,
  corregirResumenCombustible,
  corregirFluctuacionPunto,
  cambiarEstadoCompromiso,
  type GuardarComentarioInput,
  type CorregirResumenInput,
  type CorregirFluctuacionInput,
} from '@/lib/services/panel-gerencia'

/**
 * Panel de Gerencia de una semana.
 *
 * staleTime bajo (60 s) a propósito: el global del proyecto son 5 minutos, y en
 * un tablero donde el jefe escribe un plan de acción y espera verlo reflejado,
 * cinco minutos de caché se leen como "no se guardó".
 */
export function usePanelGerencia(semana?: string) {
  return useQuery({
    queryKey: ['panel-gerencia', semana ?? 'actual'],
    queryFn: () => getPanelGerencia(semana),
    staleTime: 60_000,
    // Sin permiso no sirve reintentar: el resultado va a ser el mismo.
    retry: (intentos, err) => err?.name !== 'PanelNoAutorizadoError' && intentos < 2,
  })
}

export function useGuardarComentario(semana?: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (input: GuardarComentarioInput) => guardarComentario(input),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['panel-gerencia', semana ?? 'actual'] })
    },
  })
}

/** Corrección manual del cierre mensual de combustible de una faena. */
export function useCorregirResumenCombustible(semana?: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (input: CorregirResumenInput) => corregirResumenCombustible(input),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['panel-gerencia', semana ?? 'actual'] })
    },
  })
}

/** Marca un compromiso como cumplido / anulado, o lo reabre. */
export function useEstadoCompromiso(semana?: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (v: { id: string, estado: 'pendiente' | 'cumplido' | 'anulado' }) =>
      cambiarEstadoCompromiso(v.id, v.estado),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['panel-gerencia', semana ?? 'actual'] })
    },
  })
}

/** Corrección (o carga inicial) de la fluctuación de un estanque. */
export function useCorregirFluctuacion(semana?: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (input: CorregirFluctuacionInput) => corregirFluctuacionPunto(input),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['panel-gerencia', semana ?? 'actual'] })
    },
  })
}
