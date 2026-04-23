import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  iniciarVerificacion,
  aprobarVerificacion,
  getVerificacionPorOT,
  getChecklistOT,
  updateChecklistItem,
  getVerificacionesPendientes,
  getVerificacionActivoVigente,
  getEquiposDisponiblesArriendo,
  getEquiposPendientesVerif,
  type AprobarVerificacionParams,
} from '@/lib/services/verificacion'

// ── Mutations ────────────────────────────────────────────

export function useIniciarVerificacion() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (args: { activoId: string; motivo?: string }) => {
      const { data, error } = await iniciarVerificacion(args.activoId, args.motivo)
      if (error) throw error
      return data
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['verificaciones-pendientes'] })
      qc.invalidateQueries({ queryKey: ['ordenes-trabajo'] })
      qc.invalidateQueries({ queryKey: ['verificacion-activo-vigente'] })
    },
  })
}

export function useAprobarVerificacion() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (params: AprobarVerificacionParams) => {
      const { data, error } = await aprobarVerificacion(params)
      if (error) throw error
      return data
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['verificaciones-pendientes'] })
      qc.invalidateQueries({ queryKey: ['ordenes-trabajo'] })
      qc.invalidateQueries({ queryKey: ['verificacion-por-ot'] })
      qc.invalidateQueries({ queryKey: ['verificacion-activo-vigente'] })
      qc.invalidateQueries({ queryKey: ['equipos-disponibles-arriendo'] })
      qc.invalidateQueries({ queryKey: ['flota-vehicular'] })
    },
  })
}

export function useUpdateChecklistItem() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (args: {
      itemId: string
      otId: string
      resultado?: 'ok' | 'no_ok' | 'na' | null
      observacion?: string | null
      foto_url?: string | null
    }) => {
      const { data, error } = await updateChecklistItem(args.itemId, {
        resultado: args.resultado,
        observacion: args.observacion,
        foto_url: args.foto_url,
      })
      if (error) throw error
      return data
    },
    onSuccess: (_data, vars) => {
      qc.invalidateQueries({ queryKey: ['checklist-ot', vars.otId] })
    },
  })
}

// ── Queries ──────────────────────────────────────────────

export function useVerificacionPorOT(otId?: string) {
  return useQuery({
    queryKey: ['verificacion-por-ot', otId],
    queryFn: async () => {
      const { data, error } = await getVerificacionPorOT(otId!)
      if (error) throw error
      return data
    },
    enabled: !!otId,
  })
}

export function useChecklistOT(otId?: string) {
  return useQuery({
    queryKey: ['checklist-ot', otId],
    queryFn: async () => {
      const { data, error } = await getChecklistOT(otId!)
      if (error) throw error
      return data ?? []
    },
    enabled: !!otId,
  })
}

export function useVerificacionesPendientes() {
  return useQuery({
    queryKey: ['verificaciones-pendientes'],
    queryFn: async () => {
      const { data, error } = await getVerificacionesPendientes()
      if (error) throw error
      return data ?? []
    },
  })
}

export function useEquiposDisponiblesArriendo() {
  return useQuery({
    queryKey: ['equipos-disponibles-arriendo'],
    queryFn: async () => {
      const { data, error } = await getEquiposDisponiblesArriendo()
      if (error) throw error
      return data ?? []
    },
    staleTime: 30_000,
  })
}

export function useEquiposPendientesVerif() {
  return useQuery({
    queryKey: ['equipos-pendientes-verif'],
    queryFn: async () => {
      const { data, error } = await getEquiposPendientesVerif()
      if (error) throw error
      return data ?? []
    },
    staleTime: 30_000,
  })
}

export function useVerificacionActivoVigente(activoId?: string) {
  return useQuery({
    queryKey: ['verificacion-activo-vigente', activoId],
    queryFn: async () => {
      const { data, error } = await getVerificacionActivoVigente(activoId!)
      if (error) throw error
      return data
    },
    enabled: !!activoId,
  })
}
