import { useEffect } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  getBacklog, getCumplimientoPmMes,
  getCoberturaResumen, getActivosSinPlan,
  crearTallerTecnico, desactivarTallerTecnico,
  rpcAgregarTareaLibre, rpcEliminarTarea,
  rpcAgregarJornadaOT,
  rpcQuitarJornada, rpcConfirmarPlanSemanal,
  rpcV3SetTiempo, rpcV3SetExcluido, rpcV3AgregarItem, rpcV3EliminarCustom,
  rpcAdminSembrarPlanesFaltantes,
} from '@/lib/services/taller-plan-semanal'
// Capa offline del Kanban del jefe: lecturas cacheadas + cola de mutaciones
// que se sincroniza al recuperar internet.
import {
  getOrCreatePlanOffline, getPlanOffline, getDiasOffline, getJornadasOffline,
  getKpiOffline, getTecnicosOffline, getUsuariosOffline, getChecklistV3Offline,
  iniciarEjecucionOffline, pausarEjecucionOffline, reanudarEjecucionOffline,
  finalizarEjecucionOffline, moverJornadaOffline, asignarResponsableOffline,
  editarJornadaOffline, syncTallerPlanPending, getPlanPendingCount,
  descargarSemanaOffline,
} from '@/lib/offline/taller-plan-offline'
import { getRecursosOT, validarRecurso, agregarRecursoJefe } from '@/lib/services/ot-recursos'
import { subirFirmaTicket, crearTicket } from '@/lib/services/bodega-tickets'

const KEY = (...parts: (string | null | undefined)[]) => ['taller', ...parts.filter(Boolean)] as const

// ── Queries ────────────────────────────────────────────────────────────────
export function usePlanSemanalTaller(id: string | null) {
  return useQuery({
    queryKey: KEY('plan', id ?? 'none'),
    enabled: !!id,
    networkMode: 'always',
    queryFn: () => getPlanOffline(id!),
  })
}
export function useDiasPlanSemanalTaller(id: string | null) {
  return useQuery({
    queryKey: KEY('dias', id ?? 'none'),
    enabled: !!id,
    networkMode: 'always',
    queryFn: () => getDiasOffline(id!),
  })
}
export function useJornadasPlanSemanalTaller(id: string | null) {
  return useQuery({
    queryKey: KEY('jornadas', id ?? 'none'),
    enabled: !!id,
    networkMode: 'always',
    queryFn: () => getJornadasOffline(id!),
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
    networkMode: 'always',
    queryFn: () => getKpiOffline(id!),
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
    networkMode: 'always',
    queryFn: () => getUsuariosOffline(),
    staleTime: 5 * 60_000,
  })
}
export function useTallerTecnicos(operacion?: string | null) {
  return useQuery({
    queryKey: KEY('tecnicos', operacion),
    networkMode: 'always',
    queryFn: () => getTecnicosOffline(operacion),
    staleTime: 5 * 60_000,
  })
}
export function useCrearTecnico() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: crearTallerTecnico,
    onSuccess: () => qc.invalidateQueries({ queryKey: ['taller', 'tecnicos'] }),
  })
}
export function useDesactivarTecnico() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (id: string) => desactivarTallerTecnico(id),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['taller', 'tecnicos'] }),
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
    networkMode: 'always',
    mutationFn: ({ fechaInicio, faenaId }: { fechaInicio: string; faenaId?: string | null }) =>
      getOrCreatePlanOffline(fechaInicio, faenaId),
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
export function useAgregarTareaLibreTaller(planId: string | null) {
  const invalidate = useInvalidatePlan(planId)
  return useMutation({
    mutationFn: rpcAgregarTareaLibre,
    onSuccess: () => invalidate(),
  })
}
export function useEliminarTareaTaller(planId: string | null) {
  const invalidate = useInvalidatePlan(planId)
  return useMutation({
    mutationFn: (planOtId: string) => rpcEliminarTarea(planOtId),
    onSuccess: () => invalidate(),
  })
}
export function useMoverJornadaTaller(planId: string | null) {
  const invalidate = useInvalidatePlan(planId)
  return useMutation({
    networkMode: 'always',
    mutationFn: (p: { planOtId: string; fechaDestino: string; responsableId?: string | null; motivo?: string | null }) =>
      moverJornadaOffline(p),
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
    networkMode: 'always',
    mutationFn: (p: { planOtId: string; responsableId: string | null; responsableNombre?: string | null; cuadrilla?: string | null; motivo?: string | null }) =>
      asignarResponsableOffline(p),
    onSuccess: () => invalidate(),
  })
}
export function useEditarJornadaTaller(planId: string | null) {
  const invalidate = useInvalidatePlan(planId)
  return useMutation({
    networkMode: 'always',
    mutationFn: editarJornadaOffline,
    onSuccess: () => invalidate(),
  })
}

// ── Checklist V03 a medida por OT ───────────────────────────────────────────
export function useChecklistV3Taller(otId: string | null) {
  return useQuery({
    queryKey: KEY('checklist-v3', otId ?? 'none'),
    enabled: !!otId,
    networkMode: 'always',
    queryFn: () => getChecklistV3Offline(otId!),
  })
}

function useInvalidateV3(planId: string | null, otId: string | null) {
  const qc = useQueryClient()
  const invalidate = useInvalidatePlan(planId)
  return () => {
    invalidate()
    qc.invalidateQueries({ queryKey: KEY('checklist-v3', otId ?? 'none') })
  }
}

export function useV3SetTiempoTaller(planId: string | null, otId: string | null) {
  const inv = useInvalidateV3(planId, otId)
  return useMutation({
    mutationFn: ({ itemId, tiempoMin }: { itemId: string; tiempoMin: number | null }) =>
      rpcV3SetTiempo(itemId, tiempoMin),
    onSuccess: () => inv(),
  })
}

export function useV3SetExcluidoTaller(planId: string | null, otId: string | null) {
  const inv = useInvalidateV3(planId, otId)
  return useMutation({
    mutationFn: ({ itemId, excluido }: { itemId: string; excluido: boolean }) =>
      rpcV3SetExcluido(itemId, excluido),
    onSuccess: () => inv(),
  })
}

export function useV3AgregarItemTaller(planId: string | null, otId: string | null) {
  const inv = useInvalidateV3(planId, otId)
  return useMutation({
    mutationFn: ({ otId: ot, descripcion, tiempoMin }: { otId: string; descripcion: string; tiempoMin: number | null }) =>
      rpcV3AgregarItem(ot, descripcion, tiempoMin),
    onSuccess: () => inv(),
  })
}

export function useV3EliminarCustomTaller(planId: string | null, otId: string | null) {
  const inv = useInvalidateV3(planId, otId)
  return useMutation({
    mutationFn: (itemId: string) => rpcV3EliminarCustom(itemId),
    onSuccess: () => inv(),
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
    networkMode: 'always',
    mutationFn: (p: { otId: string; planOtId?: string | null; observacion?: string | null }) =>
      iniciarEjecucionOffline(p),
    onSuccess: () => invalidate(),
  })
}
export function usePausarEjecucionTaller(planId: string | null) {
  const invalidate = useInvalidatePlan(planId)
  return useMutation({
    networkMode: 'always',
    mutationFn: (p: { ejecucionId?: string | null; otId?: string | null; planOtId?: string | null; motivo?: string | null }) =>
      pausarEjecucionOffline(p),
    onSuccess: () => invalidate(),
  })
}
export function useReanudarEjecucionTaller(planId: string | null) {
  const invalidate = useInvalidatePlan(planId)
  return useMutation({
    networkMode: 'always',
    mutationFn: (p: { ejecucionId?: string | null; otId?: string | null; planOtId?: string | null }) =>
      reanudarEjecucionOffline(p),
    onSuccess: () => invalidate(),
  })
}
export function useFinalizarEjecucionTaller(planId: string | null) {
  const invalidate = useInvalidatePlan(planId)
  return useMutation({
    networkMode: 'always',
    mutationFn: (p: { ejecucionId?: string | null; otId?: string | null; planOtId?: string | null; avanceFinal?: number; observacion?: string | null }) =>
      finalizarEjecucionOffline(p),
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

// ── Offline del Kanban del jefe ─────────────────────────────────────────────
export function usePlanPendingCount(autoRefreshMs = 4000) {
  return useQuery({
    queryKey: KEY('plan-pending'),
    queryFn: getPlanPendingCount,
    networkMode: 'always',
    refetchInterval: autoRefreshMs,
  })
}

export function useSyncTallerPlan() {
  const qc = useQueryClient()
  return useMutation({
    networkMode: 'always',
    mutationFn: syncTallerPlanPending,
    onSuccess: () => qc.invalidateQueries({ queryKey: ['taller'] }),
  })
}

/** Sincroniza la cola del plan automáticamente al recuperar conexión. */
export function useAutoSyncTallerPlan() {
  const qc = useQueryClient()
  useEffect(() => {
    const trySync = async () => {
      if (typeof navigator !== 'undefined' && navigator.onLine) {
        const r = await syncTallerPlanPending()
        if (r.ok > 0 || r.failed > 0) qc.invalidateQueries({ queryKey: ['taller'] })
      }
    }
    window.addEventListener('online', trySync)
    void trySync()
    return () => window.removeEventListener('online', trySync)
  }, [qc])
}

/** Pre-descarga la semana completa (plan + jornadas + checklists) para offline. */
export function useDescargarSemanaOffline() {
  return useMutation({
    networkMode: 'always',
    mutationFn: (fechaInicio: string) => descargarSemanaOffline(fechaInicio),
  })
}

// ── Recursos solicitados por el operador → validación del jefe (MIG197) ─────
export function useRecursosOTTaller(otId: string | null) {
  return useQuery({
    queryKey: KEY('recursos', otId ?? 'none'),
    enabled: !!otId,
    queryFn: () => getRecursosOT(otId!),
    staleTime: 10_000,
  })
}

export function useValidarRecursoTaller(otId: string | null) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: validarRecurso,
    onSuccess: () => qc.invalidateQueries({ queryKey: KEY('recursos', otId ?? 'none') }),
  })
}

export function useAgregarRecursoTaller(otId: string | null) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: agregarRecursoJefe,
    onSuccess: () => qc.invalidateQueries({ queryKey: KEY('recursos', otId ?? 'none') }),
  })
}

/** Emite el vale de bodega de la OT: sube la firma del jefe y crea el ticket. */
export function useEmitirValeTaller(otId: string | null) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (p: { firmaDataUrl: string; observacion?: string | null }) => {
      const firmaUrl = await subirFirmaTicket(p.firmaDataUrl, 'vale')
      return crearTicket({ otId: otId!, firmaJefeUrl: firmaUrl, observacion: p.observacion ?? null })
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: KEY('recursos', otId ?? 'none') })
      qc.invalidateQueries({ queryKey: ['tickets'] })
      qc.invalidateQueries({ queryKey: ['tickets-emitibles'] })
    },
  })
}
