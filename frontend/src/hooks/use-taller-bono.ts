'use client'

import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  getCartola, getResumenBono, getDisponibilidadPeriodo, getPeriodos,
  cerrarPeriodo, reabrirPeriodo, acusarRecibo, getOTSinDueno,
} from '@/lib/services/taller-bono'

const KEY_PERIODOS = ['bono-periodos'] as const

export function useCartolaBono(desde: string, hasta: string, tecnicoId?: string | null) {
  return useQuery({
    queryKey: ['bono-cartola', desde, hasta, tecnicoId ?? 'yo'],
    queryFn: () => getCartola(desde, hasta, tecnicoId),
    networkMode: 'always',
    staleTime: 30_000,
    retry: false,
  })
}

export function useResumenBono(desde: string, hasta: string, disponibilidad?: number | null) {
  return useQuery({
    queryKey: ['bono-resumen', desde, hasta, disponibilidad ?? 'auto'],
    queryFn: () => getResumenBono(desde, hasta, disponibilidad),
    staleTime: 30_000,
    retry: false,
  })
}

export function useDisponibilidadPeriodo(desde: string, hasta: string) {
  return useQuery({
    queryKey: ['bono-disponibilidad', desde, hasta],
    queryFn: () => getDisponibilidadPeriodo(desde, hasta),
    staleTime: 60_000,
  })
}

export function useOTSinDueno(desde: string, hasta: string) {
  return useQuery({
    queryKey: ['bono-ot-sin-dueno', desde, hasta],
    queryFn: () => getOTSinDueno(desde, hasta),
    staleTime: 30_000,
    retry: false,
  })
}

export function usePeriodosBono() {
  return useQuery({ queryKey: KEY_PERIODOS, queryFn: getPeriodos, staleTime: 30_000 })
}

export function useCerrarPeriodo() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: cerrarPeriodo,
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: KEY_PERIODOS })
      qc.invalidateQueries({ queryKey: ['bono-cartola'] })
      qc.invalidateQueries({ queryKey: ['bono-resumen'] })
    },
  })
}

export function useReabrirPeriodo() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (v: { periodoId: string; motivo: string }) => reabrirPeriodo(v.periodoId, v.motivo),
    onSuccess: () => qc.invalidateQueries({ queryKey: KEY_PERIODOS }),
  })
}

export function useAcusarRecibo() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (v: { lineaId: string; comentario?: string | null }) =>
      acusarRecibo(v.lineaId, v.comentario),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['bono-cartola'] }),
  })
}
