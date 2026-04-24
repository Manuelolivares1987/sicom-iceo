import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  getEstanques,
  getEstanqueById,
  getMedidoresByEstanque,
  getAllMedidores,
  crearMedidor,
  updateMedidor,
  deleteMedidor,
  getMovimientos,
  registrarMovimiento,
  getVarillajesByEstanque,
  registrarVarillaje,
  getConsumoVehiculoMes,
  type MovimientoFiltros,
  type RegistrarMovimientoPayload,
  type RegistrarVarillajePayload,
} from '@/lib/services/combustible'

// ── Queries ──────────────────────────────────────────────

export function useEstanques() {
  return useQuery({
    queryKey: ['combustible-estanques'],
    queryFn: async () => {
      const { data, error } = await getEstanques()
      if (error) throw error
      return data ?? []
    },
  })
}

export function useEstanque(id: string | undefined) {
  return useQuery({
    queryKey: ['combustible-estanque', id],
    queryFn: async () => {
      const { data, error } = await getEstanqueById(id!)
      if (error) throw error
      return data
    },
    enabled: !!id,
  })
}

export function useMedidoresEstanque(estanqueId: string | undefined) {
  return useQuery({
    queryKey: ['combustible-medidores', estanqueId],
    queryFn: async () => {
      const { data, error } = await getMedidoresByEstanque(estanqueId!)
      if (error) throw error
      return data ?? []
    },
    enabled: !!estanqueId,
  })
}

export function useMovimientosCombustible(filtros?: MovimientoFiltros) {
  return useQuery({
    queryKey: ['combustible-movimientos', filtros],
    queryFn: async () => {
      const { data, error } = await getMovimientos(filtros)
      if (error) throw error
      return data ?? []
    },
  })
}

export function useVarillajesEstanque(estanqueId: string | undefined) {
  return useQuery({
    queryKey: ['combustible-varillajes', estanqueId],
    queryFn: async () => {
      const { data, error } = await getVarillajesByEstanque(estanqueId!)
      if (error) throw error
      return data ?? []
    },
    enabled: !!estanqueId,
  })
}

export function useConsumoVehiculoMes(mesISO?: string) {
  return useQuery({
    queryKey: ['combustible-consumo-vehiculo', mesISO],
    queryFn: async () => {
      const { data, error } = await getConsumoVehiculoMes(mesISO)
      if (error) throw error
      return data ?? []
    },
  })
}

// ── Mutations ────────────────────────────────────────────

function invalidateCombustible(qc: ReturnType<typeof useQueryClient>) {
  qc.invalidateQueries({ queryKey: ['combustible-estanques'] })
  qc.invalidateQueries({ queryKey: ['combustible-estanque'] })
  qc.invalidateQueries({ queryKey: ['combustible-medidores'] })
  qc.invalidateQueries({ queryKey: ['combustible-movimientos'] })
  qc.invalidateQueries({ queryKey: ['combustible-varillajes'] })
  qc.invalidateQueries({ queryKey: ['combustible-consumo-vehiculo'] })
}

export function useRegistrarMovimientoCombustible() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (payload: RegistrarMovimientoPayload) => {
      const { data, error } = await registrarMovimiento(payload)
      if (error) throw error
      return data
    },
    onSuccess: () => invalidateCombustible(qc),
  })
}

export function useRegistrarVarillaje() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (payload: RegistrarVarillajePayload) => {
      const { data, error } = await registrarVarillaje(payload)
      if (error) throw error
      return data
    },
    onSuccess: () => invalidateCombustible(qc),
  })
}

export function useMedidores() {
  return useQuery({
    queryKey: ['combustible-medidores-all'],
    queryFn: async () => {
      const { data, error } = await getAllMedidores()
      if (error) throw error
      return data ?? []
    },
  })
}

export function useCrearMedidor() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (payload: Parameters<typeof crearMedidor>[0]) => {
      const { data, error } = await crearMedidor(payload)
      if (error) throw error
      return data
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['combustible-medidores'] })
      qc.invalidateQueries({ queryKey: ['combustible-medidores-all'] })
      qc.invalidateQueries({ queryKey: ['combustible-estanques'] })
    },
  })
}

export function useUpdateMedidor() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({
      id,
      patch,
    }: {
      id: string
      patch: Parameters<typeof updateMedidor>[1]
    }) => {
      const { data, error } = await updateMedidor(id, patch)
      if (error) throw error
      return data
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['combustible-medidores'] })
      qc.invalidateQueries({ queryKey: ['combustible-medidores-all'] })
    },
  })
}

export function useDeleteMedidor() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (id: string) => {
      const { error } = await deleteMedidor(id)
      if (error) throw error
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['combustible-medidores'] })
      qc.invalidateQueries({ queryKey: ['combustible-medidores-all'] })
    },
  })
}
