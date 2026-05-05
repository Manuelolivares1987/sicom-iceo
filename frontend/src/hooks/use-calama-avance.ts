import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  actualizarAvanceManual, marcarOTCompletadaOperador,
  registrarAvanceParcialOperador, getEventosAvancePorOT,
  type ActualizarAvanceManual, type MarcarCompletadaOperador,
  type RegistrarAvanceParcialOperador,
} from '@/lib/services/calama-avance'

const KEY = {
  eventos: (otId: string) => ['calama-avance-eventos', otId] as const,
}

function invalidateOT(qc: ReturnType<typeof useQueryClient>, otId: string) {
  qc.invalidateQueries({ queryKey: KEY.eventos(otId) })
  qc.invalidateQueries({ queryKey: ['calama', 'ot', otId] })
  qc.invalidateQueries({ queryKey: ['calama', 'ots'] })
  qc.invalidateQueries({ queryKey: ['calama-mis-ots'] })
  qc.invalidateQueries({ queryKey: ['calama-avance-area'] })
  qc.invalidateQueries({ queryKey: ['calama-resumen-general'] })
  qc.invalidateQueries({ queryKey: ['calama', 'dashboard'] })
}

export function useEventosAvanceOT(otId: string | null | undefined) {
  return useQuery({
    queryKey: KEY.eventos(otId ?? ''),
    queryFn: async () => {
      const { data, error } = await getEventosAvancePorOT(otId!)
      if (error) throw error
      return data
    },
    enabled: !!otId,
  })
}

export function useActualizarAvanceManual() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (payload: ActualizarAvanceManual) => {
      const { data, error } = await actualizarAvanceManual(payload)
      if (error) throw error
      return data
    },
    onSuccess: (_, vars) => invalidateOT(qc, vars.ot_id),
  })
}

export function useMarcarOTCompletadaOperador() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (payload: MarcarCompletadaOperador) => {
      const { data, error } = await marcarOTCompletadaOperador(payload)
      if (error) throw error
      return data
    },
    onSuccess: (_, vars) => invalidateOT(qc, vars.ot_id),
  })
}

export function useRegistrarAvanceParcialOperador() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (payload: RegistrarAvanceParcialOperador) => {
      const { data, error } = await registrarAvanceParcialOperador(payload)
      if (error) throw error
      return data
    },
    onSuccess: (_, vars) => invalidateOT(qc, vars.ot_id),
  })
}
