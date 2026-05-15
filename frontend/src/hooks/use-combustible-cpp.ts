import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  getResumenCombustible, getControlEstanques, getMovimientosValorizados,
  listarEstanquesActivos, listarProveedoresCombustible, listarFaenas, listarActivos,
  registrarIngresoCombustible, registrarSalidaCombustible,
  registrarDespachoConSellos, listarDespachosConSellos,
  getIngresosAnulables, anularIngresoCombustible,
  type FiltrosMovimientos, type IngresoCombustiblePayload, type SalidaCombustiblePayload,
  type DespachoSellosPayload,
} from '@/lib/services/combustible-cpp'

const STALE = 30_000

export function useResumenCombustible() {
  return useQuery({
    queryKey: ['combustible', 'resumen'],
    queryFn: async () => {
      const { data, error } = await getResumenCombustible()
      if (error) throw error
      return data!
    },
    staleTime: STALE,
  })
}

export function useControlEstanques() {
  return useQuery({
    queryKey: ['combustible', 'control'],
    queryFn: async () => {
      const { data, error } = await getControlEstanques()
      if (error) throw error
      return data ?? []
    },
    staleTime: STALE,
  })
}

export function useMovimientosCombustible(filtros?: FiltrosMovimientos) {
  return useQuery({
    queryKey: ['combustible', 'movimientos', filtros],
    queryFn: async () => {
      const { data, error } = await getMovimientosValorizados(filtros)
      if (error) throw error
      return data ?? []
    },
    staleTime: STALE,
  })
}

export function useEstanquesActivos() {
  return useQuery({
    queryKey: ['combustible', 'estanques-activos'],
    queryFn: async () => {
      const { data, error } = await listarEstanquesActivos()
      if (error) throw error
      return data ?? []
    },
    staleTime: 5 * 60_000,
  })
}

export function useProveedoresCombustible() {
  return useQuery({
    queryKey: ['combustible', 'proveedores'],
    queryFn: async () => {
      const { data, error } = await listarProveedoresCombustible()
      if (error) throw error
      return data ?? []
    },
    staleTime: 5 * 60_000,
  })
}

export function useFaenas() {
  return useQuery({
    queryKey: ['combustible', 'faenas'],
    queryFn: async () => {
      const { data, error } = await listarFaenas()
      if (error) throw error
      return data ?? []
    },
    staleTime: 5 * 60_000,
  })
}

export function useActivos() {
  return useQuery({
    queryKey: ['combustible', 'activos'],
    queryFn: async () => {
      const { data, error } = await listarActivos()
      if (error) throw error
      return data ?? []
    },
    staleTime: 5 * 60_000,
  })
}

export function useRegistrarIngresoCombustible() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (payload: IngresoCombustiblePayload) => {
      const { data, error } = await registrarIngresoCombustible(payload)
      if (error) throw error
      return data!
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['combustible'] })
    },
  })
}

export function useRegistrarSalidaCombustible() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (payload: SalidaCombustiblePayload) => {
      const { data, error } = await registrarSalidaCombustible(payload)
      if (error) throw error
      return data!
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['combustible'] })
    },
  })
}

export function useRegistrarDespachoConSellos() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (payload: DespachoSellosPayload) => {
      const { data, error } = await registrarDespachoConSellos(payload)
      if (error) throw error
      return data!
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['combustible'] })
    },
  })
}

export function useDespachosConSellos(limit = 50) {
  return useQuery({
    queryKey: ['combustible', 'despachos-sellos', limit],
    queryFn: async () => {
      const { data, error } = await listarDespachosConSellos(limit)
      if (error) throw error
      return data ?? []
    },
    staleTime: 30_000,
  })
}

// MIG49 - anulación de ingresos mal cargados

export function useIngresosAnulables(estanqueId?: string | null) {
  return useQuery({
    queryKey: ['combustible', 'ingresos-anulables', estanqueId ?? null],
    queryFn: async () => {
      const { data, error } = await getIngresosAnulables(estanqueId)
      if (error) throw error
      return data
    },
    staleTime: STALE,
  })
}

export function useAnularIngresoCombustible() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({ kardexId, motivo }: { kardexId: string; motivo: string }) => {
      const { data, error } = await anularIngresoCombustible(kardexId, motivo)
      if (error) throw error
      return data!
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['combustible'] })
    },
  })
}
