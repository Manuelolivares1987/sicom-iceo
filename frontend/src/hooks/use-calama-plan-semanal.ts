import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  getOrCreatePlanSemanal, getPlanSemanalById, getDiasPlanSemanal, getOTsPlanSemanal,
  moverOTplanSemanal, moverJornada, quitarOTplanSemanal, quitarJornada,
  asignarResponsable, confirmarPlanSemanal,
  getMisOTsAsignadas, getEjecucionActivaPorOT, getEjecucionesPorOT,
  iniciarEjecucion, pausarEjecucion, reanudarEjecucion, finalizarEjecucion,
  getUsuariosAsignables, actualizarComentarioPlanOT,
  getAvancePorArea, getResumenGeneral,
} from '@/lib/services/calama-plan-semanal'

const KEY = {
  planSemanal: (id: string) => ['calama-plan-sem', id] as const,
  diasPlan: (id: string) => ['calama-plan-sem-dias', id] as const,
  otsPlan: (id: string) => ['calama-plan-sem-ots', id] as const,
  misOts: ['calama-mis-ots'] as const,
  ejecucionActiva: (otId: string) => ['calama-ejec-activa', otId] as const,
  ejecuciones: (otId: string) => ['calama-ejec', otId] as const,
  usuarios: ['calama-usuarios-asignables'] as const,
}

// ── Plan semanal queries ──────────────────────────────────────────────────────

export function usePlanSemanal(id: string | null | undefined) {
  return useQuery({
    queryKey: KEY.planSemanal(id ?? ''),
    queryFn: async () => {
      const { data, error } = await getPlanSemanalById(id!)
      if (error) throw error
      return data
    },
    enabled: !!id,
  })
}

export function useDiasPlanSemanal(id: string | null | undefined) {
  return useQuery({
    queryKey: KEY.diasPlan(id ?? ''),
    queryFn: async () => {
      const { data, error } = await getDiasPlanSemanal(id!)
      if (error) throw error
      return data
    },
    enabled: !!id,
  })
}

export function useOTsPlanSemanal(id: string | null | undefined) {
  return useQuery({
    queryKey: KEY.otsPlan(id ?? ''),
    queryFn: async () => {
      const { data, error } = await getOTsPlanSemanal(id!)
      if (error) throw error
      return data
    },
    enabled: !!id,
  })
}

export function useMisOTsAsignadas(opts?: { todas?: boolean }) {
  const todas = !!opts?.todas
  return useQuery({
    queryKey: [...KEY.misOts, todas ? 'todas' : 'propias'] as const,
    queryFn: async () => {
      const { data, error } = await getMisOTsAsignadas({ todas })
      if (error) throw error
      return data ?? []
    },
  })
}

export function useUsuariosAsignables() {
  return useQuery({
    queryKey: KEY.usuarios,
    queryFn: async () => {
      const { data, error } = await getUsuariosAsignables()
      if (error) throw error
      return data
    },
  })
}

// ── Plan semanal mutations ────────────────────────────────────────────────────

export function useGetOrCreatePlanSemanal() {
  return useMutation({
    mutationFn: async (params: { planificacionId: string; fechaInicio: string }) => {
      const { data, error } = await getOrCreatePlanSemanal(params.planificacionId, params.fechaInicio)
      if (error) throw error
      return data!
    },
  })
}

export function useMoverOTplanSemanal() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (payload: Parameters<typeof moverOTplanSemanal>[0]) => {
      const { data, error } = await moverOTplanSemanal(payload)
      if (error) throw error
      return data
    },
    onSuccess: (_, vars) => {
      qc.invalidateQueries({ queryKey: KEY.otsPlan(vars.planSemanalId) })
    },
  })
}

// MIG31: mueve una jornada especifica (multidia-safe).
export function useMoverJornada() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (payload: Parameters<typeof moverJornada>[0] & { planSemanalId: string }) => {
      const { planSemanalId: _ps, ...rest } = payload
      void _ps
      const { data, error } = await moverJornada(rest)
      if (error) throw error
      return data
    },
    onSuccess: (_, vars) => {
      qc.invalidateQueries({ queryKey: KEY.otsPlan(vars.planSemanalId) })
      qc.invalidateQueries({ queryKey: KEY.misOts })
    },
  })
}

export function useQuitarOTplanSemanal() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (params: { planSemanalId: string; otId: string }) => {
      const { data, error } = await quitarOTplanSemanal(params.planSemanalId, params.otId)
      if (error) throw error
      return data
    },
    onSuccess: (_, vars) => {
      qc.invalidateQueries({ queryKey: KEY.otsPlan(vars.planSemanalId) })
    },
  })
}

// MIG31: quita una jornada especifica.
export function useQuitarJornada() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (params: { planSemanalId: string; planOtId: string }) => {
      const { data, error } = await quitarJornada(params.planOtId)
      if (error) throw error
      return data
    },
    onSuccess: (_, vars) => {
      qc.invalidateQueries({ queryKey: KEY.otsPlan(vars.planSemanalId) })
      qc.invalidateQueries({ queryKey: KEY.misOts })
    },
  })
}

export function useAsignarResponsable() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (params: { planSemanalId: string; otId: string; responsableId: string }) => {
      const { data, error } = await asignarResponsable(params.planSemanalId, params.otId, params.responsableId)
      if (error) throw error
      return data
    },
    onSuccess: (_, vars) => {
      qc.invalidateQueries({ queryKey: KEY.otsPlan(vars.planSemanalId) })
      qc.invalidateQueries({ queryKey: KEY.misOts })
    },
  })
}

export function useActualizarComentarioPlanOT() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (params: { planSemanalId: string; otId: string; observaciones: string }) => {
      const { data, error } = await actualizarComentarioPlanOT(params)
      if (error) throw error
      return data
    },
    onSuccess: (_, vars) => {
      qc.invalidateQueries({ queryKey: KEY.otsPlan(vars.planSemanalId) })
    },
  })
}

export function useAvancePorArea(planificacionId: string | null | undefined) {
  return useQuery({
    queryKey: ['calama-avance-area', planificacionId ?? ''],
    queryFn: async () => {
      const { data, error } = await getAvancePorArea(planificacionId!)
      if (error) throw error
      return data
    },
    enabled: !!planificacionId,
  })
}

export function useResumenGeneral(planificacionId: string | null | undefined) {
  return useQuery({
    queryKey: ['calama-resumen-general', planificacionId ?? ''],
    queryFn: async () => {
      const { data, error } = await getResumenGeneral(planificacionId!)
      if (error) throw error
      return data
    },
    enabled: !!planificacionId,
  })
}

export function useConfirmarPlanSemanal() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (planSemanalId: string) => {
      const { data, error } = await confirmarPlanSemanal(planSemanalId)
      if (error) throw error
      return data
    },
    onSuccess: (_, planSemanalId) => {
      qc.invalidateQueries({ queryKey: KEY.planSemanal(planSemanalId) })
      qc.invalidateQueries({ queryKey: KEY.otsPlan(planSemanalId) })
      qc.invalidateQueries({ queryKey: KEY.misOts })
    },
  })
}

// ── Ejecucion ─────────────────────────────────────────────────────────────────

export function useEjecucionActivaPorOT(otId: string | null | undefined) {
  return useQuery({
    queryKey: KEY.ejecucionActiva(otId ?? ''),
    queryFn: async () => {
      const { data, error } = await getEjecucionActivaPorOT(otId!)
      if (error) throw error
      return data
    },
    enabled: !!otId,
    refetchInterval: 15000,
  })
}

export function useEjecucionesPorOT(otId: string | null | undefined) {
  return useQuery({
    queryKey: KEY.ejecuciones(otId ?? ''),
    queryFn: async () => {
      const { data, error } = await getEjecucionesPorOT(otId!)
      if (error) throw error
      return data
    },
    enabled: !!otId,
  })
}

export function useIniciarEjecucion() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (otId: string) => {
      const { data, error } = await iniciarEjecucion(otId)
      if (error) throw error
      return data
    },
    onSuccess: (_, otId) => {
      qc.invalidateQueries({ queryKey: KEY.ejecucionActiva(otId) })
      qc.invalidateQueries({ queryKey: KEY.ejecuciones(otId) })
      qc.invalidateQueries({ queryKey: ['calama', 'ot', otId] })
    },
  })
}

export function usePausarEjecucion() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (params: { ejecucionId: string; motivo?: string; otId: string }) => {
      const { data, error } = await pausarEjecucion(params.ejecucionId, params.motivo ?? 'pausa')
      if (error) throw error
      return data
    },
    onSuccess: (_, vars) => {
      qc.invalidateQueries({ queryKey: KEY.ejecucionActiva(vars.otId) })
      qc.invalidateQueries({ queryKey: KEY.ejecuciones(vars.otId) })
    },
  })
}

export function useReanudarEjecucion() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (params: { ejecucionId: string; otId: string }) => {
      const { data, error } = await reanudarEjecucion(params.ejecucionId)
      if (error) throw error
      return data
    },
    onSuccess: (_, vars) => {
      qc.invalidateQueries({ queryKey: KEY.ejecucionActiva(vars.otId) })
      qc.invalidateQueries({ queryKey: KEY.ejecuciones(vars.otId) })
    },
  })
}

export function useFinalizarEjecucion() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (params: { ejecucionId: string; otId: string; avance?: number; observacion?: string }) => {
      const { data, error } = await finalizarEjecucion(params.ejecucionId, params.avance ?? 100, params.observacion)
      if (error) throw error
      return data
    },
    onSuccess: (_, vars) => {
      qc.invalidateQueries({ queryKey: KEY.ejecucionActiva(vars.otId) })
      qc.invalidateQueries({ queryKey: KEY.ejecuciones(vars.otId) })
      qc.invalidateQueries({ queryKey: ['calama', 'ot', vars.otId] })
      qc.invalidateQueries({ queryKey: KEY.misOts })
    },
  })
}
