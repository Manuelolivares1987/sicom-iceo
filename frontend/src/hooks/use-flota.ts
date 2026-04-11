import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  getEstadoDiario,
  upsertEstadoDiario,
  upsertEstadoDiarioBatch,
  getResumenDiario,
  calcularOEEActivo,
  calcularOEEFlota,
  getVerificacionesActivo,
  getVerificacionVigente,
  getNoConformidades,
  createNoConformidad,
  getConductores,
  ejecutarVerificacionesNormativas,
  getFlotaVehicular,
  type EstadoDiarioFilters,
} from '@/lib/services/flota'

// ── Estado Diario ──────────────────────────────────────

export function useEstadoDiario(filters?: EstadoDiarioFilters) {
  return useQuery({
    queryKey: ['estado-diario', filters],
    queryFn: async () => {
      const { data, error } = await getEstadoDiario(filters)
      if (error) throw error
      return data
    },
  })
}

export function useUpsertEstadoDiario() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (registro: Parameters<typeof upsertEstadoDiario>[0]) => {
      const { data, error } = await upsertEstadoDiario(registro)
      if (error) throw error
      return data
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['estado-diario'] })
      qc.invalidateQueries({ queryKey: ['resumen-diario'] })
      qc.invalidateQueries({ queryKey: ['oee'] })
    },
  })
}

export function useUpsertEstadoDiarioBatch() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (registros: Parameters<typeof upsertEstadoDiarioBatch>[0]) => {
      const { data, error } = await upsertEstadoDiarioBatch(registros)
      if (error) throw error
      return data
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['estado-diario'] })
      qc.invalidateQueries({ queryKey: ['resumen-diario'] })
      qc.invalidateQueries({ queryKey: ['oee'] })
    },
  })
}

// ── Resumen Diario ─────────────────────────────────────

export function useResumenDiario(fechaInicio: string, fechaFin: string, operacion?: string) {
  return useQuery({
    queryKey: ['resumen-diario', fechaInicio, fechaFin, operacion],
    queryFn: async () => {
      const { data, error } = await getResumenDiario(fechaInicio, fechaFin, operacion)
      if (error) throw error
      return data
    },
    enabled: !!fechaInicio && !!fechaFin,
  })
}

// ── OEE ────────────────────────────────────────────────

export function useOEEActivo(activoId: string | undefined, fechaInicio: string, fechaFin: string) {
  return useQuery({
    queryKey: ['oee-activo', activoId, fechaInicio, fechaFin],
    queryFn: async () => {
      const { data, error } = await calcularOEEActivo(activoId!, fechaInicio, fechaFin)
      if (error) throw error
      return data?.[0] ?? null
    },
    enabled: !!activoId && !!fechaInicio && !!fechaFin,
  })
}

export function useOEEFlota(fechaInicio: string, fechaFin: string, contratoId?: string, operacion?: string) {
  return useQuery({
    queryKey: ['oee-flota', fechaInicio, fechaFin, contratoId, operacion],
    queryFn: async () => {
      const { data, error } = await calcularOEEFlota(fechaInicio, fechaFin, contratoId, operacion)
      if (error) throw error
      return data?.[0] ?? null
    },
    enabled: !!fechaInicio && !!fechaFin,
  })
}

// ── Verificaciones ─────────────────────────────────────

export function useVerificacionesActivo(activoId?: string) {
  return useQuery({
    queryKey: ['verificaciones', activoId],
    queryFn: async () => {
      const { data, error } = await getVerificacionesActivo(activoId!)
      if (error) throw error
      return data
    },
    enabled: !!activoId,
  })
}

export function useVerificacionVigente(activoId?: string) {
  return useQuery({
    queryKey: ['verificacion-vigente', activoId],
    queryFn: async () => {
      const { data, error } = await getVerificacionVigente(activoId!)
      if (error) throw error
      return data
    },
    enabled: !!activoId,
  })
}

// ── No Conformidades ───────────────────────────────────

export function useNoConformidades(filters?: Parameters<typeof getNoConformidades>[0]) {
  return useQuery({
    queryKey: ['no-conformidades', filters],
    queryFn: async () => {
      const { data, error } = await getNoConformidades(filters)
      if (error) throw error
      return data
    },
  })
}

export function useCreateNoConformidad() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (nc: Parameters<typeof createNoConformidad>[0]) => {
      const { data, error } = await createNoConformidad(nc)
      if (error) throw error
      return data
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['no-conformidades'] })
      qc.invalidateQueries({ queryKey: ['oee'] })
    },
  })
}

// ── Conductores ────────────────────────────────────────

export function useConductores(activos?: boolean) {
  return useQuery({
    queryKey: ['conductores', activos],
    queryFn: async () => {
      const { data, error } = await getConductores(activos)
      if (error) throw error
      return data
    },
  })
}

// ── Alertas Normativas ─────────────────────────────────

export function useEjecutarVerificaciones() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async () => {
      const { data, error } = await ejecutarVerificacionesNormativas()
      if (error) throw error
      return data
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['alertas'] })
    },
  })
}

// ── Flota Vehicular ────────────────────────────────────

export function useFlotaVehicular() {
  return useQuery({
    queryKey: ['flota-vehicular'],
    queryFn: async () => {
      const { data, error } = await getFlotaVehicular()
      if (error) throw error
      return data
    },
  })
}
