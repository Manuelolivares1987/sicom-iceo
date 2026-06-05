import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  getPlanSemanalById, getDiasPlanSemanal, getJornadasPlanSemanal,
  getBacklog, getKpiSemanal, getCumplimientoPmMes, getUsuariosAsignables,
  getCoberturaResumen, getActivosSinPlan,
  rpcGetOrCreatePlanSemanal, rpcAgregarJornadaOT, rpcMoverJornada,
  rpcQuitarJornada, rpcAsignarResponsable, rpcConfirmarPlanSemanal,
  rpcIniciarEjecucion, rpcPausarEjecucion, rpcReanudarEjecucion, rpcFinalizarEjecucion,
  rpcAdminSembrarPlanesFaltantes,
} from '@/lib/services/taller-plan-semanal'

const KEY = (...parts: (string | null | undefined)[]) => ['taller', ...parts.filter(Boolean)] as const

// ── Queries ────────────────────────────────────────────────────────────────
export function usePlanSemanalTaller(id: string | null) {
  return useQuery({
    queryKey: KEY('plan', id ?? 'none'),
    enabled: !!id,
    queryFn: () => getPlanSemanalById(id!),
  })
}
export function useDiasPlanSemanalTaller(id: string | null) {
  return useQuery({
    queryKey: KEY('dias', id ?? 'none'),
    enabled: !!id,
    queryFn: () => getDiasPlanSemanal(id!),
  })
}
export function useJornadasPlanSemanalTaller(id: string | null) {
  return useQuery({
    queryKey: KEY('jornadas', id ?? 'none'),
    enabled: !!id,
    queryFn: () => getJornadasPlanSemanal(id!),
  })
}
export function useBacklogTaller() {
  return useQuery({
    queryKey: KEY('backlog'),
    queryFn: () => getBacklog(),
    staleTime: 30_000,
  })
}
export function useKpiSemanalTaller(id: string | null) {
  return useQuery({
    queryKey: KEY('kpi', id ?? 'none'),
    enabled: !!id,
    queryFn: () => getKpiSemanal(id!),
  })
}
export function useCumplimientoPmMesTaller() {
  return useQuery({
    queryKey: KEY('cumplimiento-pm'),
    queryFn: () => getCumplimientoPmMes(),
    staleTime: 5 * 60_000,
  })
}
export function useUsuariosAsignablesTaller() {
  return useQuery({
    queryKey: KEY('usuarios'),
    queryFn: () => getUsuariosAsignables(),
    staleTime: 5 * 60_000,
  })
}
export function useCoberturaPm() {
  return useQuery({
    queryKey: KEY('cobertura-pm'),
    queryFn: () => getCoberturaResumen(),
    staleTime: 60_000,
  })
}
export function useActivosSinPlan() {
  return useQuery({
    queryKey: KEY('activos-sin-plan'),
    queryFn: () => getActivosSinPlan(),
    staleTime: 60_000,
  })
}

// ── Mutations ──────────────────────────────────────────────────────────────
function useInvalidatePlan(planId?: string | null) {
  const qc = useQueryClient()
  return () => {
    qc.invalidateQueries({ queryKey: ['taller'] })
    if (planId) {
      qc.invalidateQueries({ queryKey: KEY('jornadas', planId) })
      qc.invalidateQueries({ queryKey: KEY('kpi', planId) })
    }
  }
}

export function useGetOrCreatePlanSemanalTaller() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ fechaInicio, faenaId }: { fechaInicio: string; faenaId?: string | null }) =>
      rpcGetOrCreatePlanSemanal(fechaInicio, faenaId),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['taller'] }),
  })
}

export function useAgregarJornadaTaller(planId: string | null) {
  const invalidate = useInvalidatePlan(planId)
  return useMutation({
    mutationFn: rpcAgregarJornadaOT,
    onSuccess: () => invalidate(),
  })
}
export function useMoverJornadaTaller(planId: string | null) {
  const invalidate = useInvalidatePlan(planId)
  return useMutation({
    mutationFn: ({ planOtId, fechaDestino, responsableId }: { planOtId: string; fechaDestino: string; responsableId?: string | null }) =>
      rpcMoverJornada(planOtId, fechaDestino, responsableId),
    onSuccess: () => invalidate(),
  })
}
export function useQuitarJornadaTaller(planId: string | null) {
  const invalidate = useInvalidatePlan(planId)
  return useMutation({
    mutationFn: (planOtId: string) => rpcQuitarJornada(planOtId),
    onSuccess: () => invalidate(),
  })
}
export function useAsignarResponsableTaller(planId: string | null) {
  const invalidate = useInvalidatePlan(planId)
  return useMutation({
    mutationFn: ({ planOtId, responsableId, cuadrilla }: { planOtId: string; responsableId: string | null; cuadrilla?: string | null }) =>
      rpcAsignarResponsable(planOtId, responsableId, cuadrilla),
    onSuccess: () => invalidate(),
  })
}
export function useConfirmarPlanSemanalTaller(planId: string | null) {
  const invalidate = useInvalidatePlan(planId)
  return useMutation({
    mutationFn: (planSemanalId: string) => rpcConfirmarPlanSemanal(planSemanalId),
    onSuccess: () => invalidate(),
  })
}

export function useIniciarEjecucionTaller(planId: string | null) {
  const invalidate = useInvalidatePlan(planId)
  return useMutation({
    mutationFn: ({ otId, observacion }: { otId: string; observacion?: string | null }) =>
      rpcIniciarEjecucion(otId, observacion),
    onSuccess: () => invalidate(),
  })
}
export function usePausarEjecucionTaller(planId: string | null) {
  const invalidate = useInvalidatePlan(planId)
  return useMutation({
    mutationFn: ({ ejecucionId, motivo }: { ejecucionId: string; motivo?: string | null }) =>
      rpcPausarEjecucion(ejecucionId, motivo),
    onSuccess: () => invalidate(),
  })
}
export function useReanudarEjecucionTaller(planId: string | null) {
  const invalidate = useInvalidatePlan(planId)
  return useMutation({
    mutationFn: (ejecucionId: string) => rpcReanudarEjecucion(ejecucionId),
    onSuccess: () => invalidate(),
  })
}
export function useFinalizarEjecucionTaller(planId: string | null) {
  const invalidate = useInvalidatePlan(planId)
  return useMutation({
    mutationFn: ({ ejecucionId, avanceFinal, observacion }: { ejecucionId: string; avanceFinal?: number; observacion?: string | null }) =>
      rpcFinalizarEjecucion(ejecucionId, avanceFinal ?? 100, observacion),
    onSuccess: () => invalidate(),
  })
}

export function useAdminSembrarPlanesFaltantes() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: () => rpcAdminSembrarPlanesFaltantes(),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['taller'] }),
  })
}
