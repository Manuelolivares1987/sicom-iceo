import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  rpcIniciarJornada, rpcRegistrarEventoJornada, rpcFinalizarJornada,
  rpcRegistrarAceptacionJornada, rpcRegistrarRechazoJornada,
  rpcReprogramarSaldoOT, rpcAgregarJornadaOT,
  getFirmasJornada, getRechazosJornada, getEvidenciasJornada,
} from '@/lib/services/calama-jornada'

const KEY = {
  firmas:      (planOtId: string) => ['calama-firmas', planOtId] as const,
  rechazos:    (planOtId: string) => ['calama-rechazos', planOtId] as const,
  evidencias:  (planOtId: string) => ['calama-evidencias', planOtId] as const,
}

function invalidateOtAndPlanCaches(qc: ReturnType<typeof useQueryClient>, otId: string, planSemanalId?: string) {
  qc.invalidateQueries({ queryKey: ['calama', 'ot', otId] })
  qc.invalidateQueries({ queryKey: ['calama-mis-ots'] })
  qc.invalidateQueries({ queryKey: ['calama-ejec-activa', otId] })
  qc.invalidateQueries({ queryKey: ['calama-ejec', otId] })
  if (planSemanalId) qc.invalidateQueries({ queryKey: ['calama-plan-sem-ots', planSemanalId] })
}

// ── Queries ──────────────────────────────────────────────────────────────────

export function useFirmasJornada(planOtId: string | null | undefined) {
  return useQuery({
    queryKey: KEY.firmas(planOtId ?? ''),
    queryFn: async () => {
      const { data, error } = await getFirmasJornada(planOtId!)
      if (error) throw error
      return data
    },
    enabled: !!planOtId,
  })
}

export function useRechazosJornada(planOtId: string | null | undefined) {
  return useQuery({
    queryKey: KEY.rechazos(planOtId ?? ''),
    queryFn: async () => {
      const { data, error } = await getRechazosJornada(planOtId!)
      if (error) throw error
      return data
    },
    enabled: !!planOtId,
  })
}

export function useEvidenciasJornada(planOtId: string | null | undefined) {
  return useQuery({
    queryKey: KEY.evidencias(planOtId ?? ''),
    queryFn: async () => {
      const { data, error } = await getEvidenciasJornada(planOtId!)
      if (error) throw error
      return data
    },
    enabled: !!planOtId,
  })
}

// ── Mutations ────────────────────────────────────────────────────────────────

export function useIniciarJornada() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (params: Parameters<typeof rpcIniciarJornada>[0] & { ot_id: string; plan_semanal_id?: string }) => {
      const { ot_id, plan_semanal_id, ...payload } = params
      const { data, error } = await rpcIniciarJornada(payload)
      if (error) throw error
      return { data, ot_id, plan_semanal_id }
    },
    onSuccess: ({ ot_id, plan_semanal_id }, vars) => {
      invalidateOtAndPlanCaches(qc, ot_id, plan_semanal_id)
      qc.invalidateQueries({ queryKey: KEY.evidencias(vars.plan_semanal_ot_id) })
    },
  })
}

export function useRegistrarEventoJornada() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (params: Parameters<typeof rpcRegistrarEventoJornada>[0] & { ot_id: string; plan_semanal_id?: string }) => {
      const { ot_id, plan_semanal_id, ...payload } = params
      const { data, error } = await rpcRegistrarEventoJornada(payload)
      if (error) throw error
      return { data, ot_id, plan_semanal_id }
    },
    onSuccess: ({ ot_id, plan_semanal_id }, vars) => {
      invalidateOtAndPlanCaches(qc, ot_id, plan_semanal_id)
      qc.invalidateQueries({ queryKey: KEY.evidencias(vars.plan_semanal_ot_id) })
    },
  })
}

export function useFinalizarJornada() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (params: Parameters<typeof rpcFinalizarJornada>[0] & { ot_id: string; plan_semanal_id?: string }) => {
      const { ot_id, plan_semanal_id, ...payload } = params
      const { data, error } = await rpcFinalizarJornada(payload)
      if (error) throw error
      return { data, ot_id, plan_semanal_id }
    },
    onSuccess: ({ ot_id, plan_semanal_id }, vars) => {
      invalidateOtAndPlanCaches(qc, ot_id, plan_semanal_id)
      qc.invalidateQueries({ queryKey: KEY.firmas(vars.plan_semanal_ot_id) })
      qc.invalidateQueries({ queryKey: KEY.evidencias(vars.plan_semanal_ot_id) })
    },
  })
}

export function useAceptarJornada() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (params: Parameters<typeof rpcRegistrarAceptacionJornada>[0] & { ot_id: string; plan_semanal_id?: string }) => {
      const { ot_id, plan_semanal_id, ...payload } = params
      const { data, error } = await rpcRegistrarAceptacionJornada(payload)
      if (error) throw error
      return { data, ot_id, plan_semanal_id }
    },
    onSuccess: ({ ot_id, plan_semanal_id }, vars) => {
      invalidateOtAndPlanCaches(qc, ot_id, plan_semanal_id)
      qc.invalidateQueries({ queryKey: KEY.firmas(vars.plan_semanal_ot_id) })
    },
  })
}

export function useRechazarJornada() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (params: Parameters<typeof rpcRegistrarRechazoJornada>[0] & { ot_id: string; plan_semanal_id?: string }) => {
      const { ot_id, plan_semanal_id, ...payload } = params
      const { data, error } = await rpcRegistrarRechazoJornada(payload)
      if (error) throw error
      return { data, ot_id, plan_semanal_id }
    },
    onSuccess: ({ ot_id, plan_semanal_id }, vars) => {
      invalidateOtAndPlanCaches(qc, ot_id, plan_semanal_id)
      qc.invalidateQueries({ queryKey: KEY.firmas(vars.plan_semanal_ot_id) })
      qc.invalidateQueries({ queryKey: KEY.rechazos(vars.plan_semanal_ot_id) })
      qc.invalidateQueries({ queryKey: KEY.evidencias(vars.plan_semanal_ot_id) })
    },
  })
}

export function useReprogramarSaldoOT() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (params: Parameters<typeof rpcReprogramarSaldoOT>[0] & { ot_id: string }) => {
      const { ot_id, ...payload } = params
      const { data, error } = await rpcReprogramarSaldoOT(payload)
      if (error) throw error
      return { data, ot_id, plan_semanal_id: payload.plan_semanal_id }
    },
    onSuccess: ({ ot_id, plan_semanal_id }) => {
      invalidateOtAndPlanCaches(qc, ot_id, plan_semanal_id)
    },
  })
}

export function useAgregarJornadaOT() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (params: Parameters<typeof rpcAgregarJornadaOT>[0]) => {
      const { data, error } = await rpcAgregarJornadaOT(params)
      if (error) throw error
      return { data, plan_semanal_id: params.plan_semanal_id, ot_id: params.ot_id }
    },
    onSuccess: ({ ot_id, plan_semanal_id }) => {
      invalidateOtAndPlanCaches(qc, ot_id, plan_semanal_id)
    },
  })
}
