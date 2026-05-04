import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  getPlanificaciones, getPlanificacionById, getZonasPorPlanificacion,
  getFaenasCalama, getOTs, getOTById, getSubtareasPorOT, getObservacionesPorOT,
  getMaterialesPorPlan, getContactosPorFaena, getPrecheckPorOT,
  upsertPrecheck, liberarOT, iniciarEjecucionOT, finalizarOT,
  registrarAvanceOT, reportarNoEjecucionOT, getCurvaS,
  getDashboardKPIs, getResumenPlanificaciones,
  type OTFilters, type PrecheckUpdatePayload,
} from '@/lib/services/calama'

const KEY = {
  dashboard: ['calama', 'dashboard'] as const,
  planificaciones: ['calama', 'planificaciones'] as const,
  resumenPlan: ['calama', 'resumen-plan'] as const,
  planificacion: (id: string) => ['calama', 'planificacion', id] as const,
  zonasPlan: (id: string) => ['calama', 'zonas', id] as const,
  faenas: ['calama', 'faenas'] as const,
  ots: (filters?: OTFilters) => ['calama', 'ots', filters ?? {}] as const,
  ot: (id: string) => ['calama', 'ot', id] as const,
  subtareas: (otId: string) => ['calama', 'subtareas', otId] as const,
  observaciones: (otId: string) => ['calama', 'observaciones', otId] as const,
  precheck: (otId: string) => ['calama', 'precheck', otId] as const,
  materiales: (planId: string, zonaId?: string) => ['calama', 'materiales', planId, zonaId ?? null] as const,
  contactos: (faenaId: string, planId?: string) => ['calama', 'contactos', faenaId, planId ?? null] as const,
  curvaS: (planId: string) => ['calama', 'curva-s', planId] as const,
}

// ── Dashboard ─────────────────────────────────────────────────────────────────

export function useCalamaDashboard() {
  return useQuery({
    queryKey: KEY.dashboard,
    queryFn: async () => {
      const { data, error } = await getDashboardKPIs()
      if (error) throw error
      return data!
    },
  })
}

export function useCalamaResumenPlanificaciones() {
  return useQuery({
    queryKey: KEY.resumenPlan,
    queryFn: async () => {
      const { data, error } = await getResumenPlanificaciones()
      if (error) throw error
      return data!
    },
  })
}

// ── Planificaciones ───────────────────────────────────────────────────────────

export function useCalamaPlanificaciones() {
  return useQuery({
    queryKey: KEY.planificaciones,
    queryFn: async () => {
      const { data, error } = await getPlanificaciones()
      if (error) throw error
      return data ?? []
    },
  })
}

export function useCalamaPlanificacion(id: string | null | undefined) {
  return useQuery({
    queryKey: KEY.planificacion(id ?? ''),
    queryFn: async () => {
      const { data, error } = await getPlanificacionById(id!)
      if (error) throw error
      return data
    },
    enabled: !!id,
  })
}

export function useCalamaZonas(planificacionId: string | null | undefined) {
  return useQuery({
    queryKey: KEY.zonasPlan(planificacionId ?? ''),
    queryFn: async () => {
      const { data, error } = await getZonasPorPlanificacion(planificacionId!)
      if (error) throw error
      return data ?? []
    },
    enabled: !!planificacionId,
  })
}

// ── Faenas ────────────────────────────────────────────────────────────────────

export function useCalamaFaenas() {
  return useQuery({
    queryKey: KEY.faenas,
    queryFn: async () => {
      const { data, error } = await getFaenasCalama()
      if (error) throw error
      return data ?? []
    },
  })
}

// ── OTs ───────────────────────────────────────────────────────────────────────

export function useCalamaOTs(filters?: OTFilters) {
  return useQuery({
    queryKey: KEY.ots(filters),
    queryFn: async () => {
      const { data, error } = await getOTs(filters)
      if (error) throw error
      return data ?? []
    },
  })
}

export function useCalamaOT(id: string | null | undefined) {
  return useQuery({
    queryKey: KEY.ot(id ?? ''),
    queryFn: async () => {
      const { data, error } = await getOTById(id!)
      if (error) throw error
      return data
    },
    enabled: !!id,
  })
}

export function useCalamaSubtareas(otId: string | null | undefined) {
  return useQuery({
    queryKey: KEY.subtareas(otId ?? ''),
    queryFn: async () => {
      const { data, error } = await getSubtareasPorOT(otId!)
      if (error) throw error
      return data ?? []
    },
    enabled: !!otId,
  })
}

export function useCalamaObservaciones(otId: string | null | undefined) {
  return useQuery({
    queryKey: KEY.observaciones(otId ?? ''),
    queryFn: async () => {
      const { data, error } = await getObservacionesPorOT(otId!)
      if (error) throw error
      return data ?? []
    },
    enabled: !!otId,
  })
}

export function useCalamaMateriales(planificacionId: string | null | undefined, zonaProyectoId?: string) {
  return useQuery({
    queryKey: KEY.materiales(planificacionId ?? '', zonaProyectoId),
    queryFn: async () => {
      const { data, error } = await getMaterialesPorPlan(planificacionId!, zonaProyectoId)
      if (error) throw error
      return data ?? []
    },
    enabled: !!planificacionId,
  })
}

export function useCalamaContactos(faenaCalamaId: string | null | undefined, planificacionId?: string) {
  return useQuery({
    queryKey: KEY.contactos(faenaCalamaId ?? '', planificacionId),
    queryFn: async () => {
      const { data, error } = await getContactosPorFaena(faenaCalamaId!, planificacionId)
      if (error) throw error
      return data ?? []
    },
    enabled: !!faenaCalamaId,
  })
}

// ── Precheck ──────────────────────────────────────────────────────────────────

export function useCalamaPrecheck(otId: string | null | undefined) {
  return useQuery({
    queryKey: KEY.precheck(otId ?? ''),
    queryFn: async () => {
      const { data, error } = await getPrecheckPorOT(otId!)
      if (error) throw error
      return data
    },
    enabled: !!otId,
  })
}

export function useUpsertPrecheck() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (payload: PrecheckUpdatePayload) => {
      const { data, error } = await upsertPrecheck(payload)
      if (error) throw error
      return data
    },
    onSuccess: (_, vars) => {
      qc.invalidateQueries({ queryKey: KEY.precheck(vars.ot_id) })
      qc.invalidateQueries({ queryKey: KEY.ot(vars.ot_id) })
    },
  })
}

export function useLiberarOT() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (otId: string) => {
      const { data, error } = await liberarOT(otId)
      if (error) throw error
      if (!data) throw new Error('OT no estaba en estado planificada o no se pudo liberar')
      return data
    },
    onSuccess: (_, otId) => {
      qc.invalidateQueries({ queryKey: KEY.ot(otId) })
      qc.invalidateQueries({ queryKey: ['calama', 'ots'] })
    },
  })
}

// ── RPCs de ejecucion ─────────────────────────────────────────────────────────

export function useIniciarEjecucionOT() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (otId: string) => {
      const { data, error } = await iniciarEjecucionOT(otId)
      if (error) throw error
      return data
    },
    onSuccess: (_, otId) => {
      qc.invalidateQueries({ queryKey: KEY.ot(otId) })
      qc.invalidateQueries({ queryKey: ['calama', 'ots'] })
      qc.invalidateQueries({ queryKey: KEY.dashboard })
    },
  })
}

export function useFinalizarOT() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (payload: Parameters<typeof finalizarOT>[0]) => {
      const { data, error } = await finalizarOT(payload)
      if (error) throw error
      return data
    },
    onSuccess: (_, vars) => {
      qc.invalidateQueries({ queryKey: KEY.ot(vars.ot_id) })
      qc.invalidateQueries({ queryKey: ['calama', 'ots'] })
      qc.invalidateQueries({ queryKey: KEY.dashboard })
    },
  })
}

export function useRegistrarAvance() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (payload: Parameters<typeof registrarAvanceOT>[0]) => {
      const { data, error } = await registrarAvanceOT(payload)
      if (error) throw error
      return data
    },
    onSuccess: (_, vars) => {
      qc.invalidateQueries({ queryKey: KEY.ot(vars.ot_id) })
      qc.invalidateQueries({ queryKey: KEY.subtareas(vars.ot_id) })
      qc.invalidateQueries({ queryKey: ['calama', 'ots'] })
    },
  })
}

export function useReportarNoEjecucion() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (payload: Parameters<typeof reportarNoEjecucionOT>[0]) => {
      const { data, error } = await reportarNoEjecucionOT(payload)
      if (error) throw error
      return data
    },
    onSuccess: (_, vars) => {
      qc.invalidateQueries({ queryKey: KEY.ot(vars.ot_id) })
      qc.invalidateQueries({ queryKey: ['calama', 'ots'] })
      qc.invalidateQueries({ queryKey: KEY.dashboard })
    },
  })
}

// ── Curva S ───────────────────────────────────────────────────────────────────

export function useCalamaCurvaS(planificacionId: string | null | undefined) {
  return useQuery({
    queryKey: KEY.curvaS(planificacionId ?? ''),
    queryFn: async () => {
      const { data, error } = await getCurvaS(planificacionId!)
      if (error) throw error
      return data ?? []
    },
    enabled: !!planificacionId,
  })
}
