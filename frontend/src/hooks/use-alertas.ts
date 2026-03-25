import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  getAlertas,
  getAlertasNoLeidas,
  getConteoNoLeidas,
  marcarLeida,
} from '@/lib/services/alertas'
import { useAuth } from '@/contexts/auth-context'

// ── Queries ──────────────────────────────────────────────

export function useAlertas(leidas?: boolean) {
  const { user } = useAuth()
  const destinatarioId = user?.id

  return useQuery({
    queryKey: ['alertas', destinatarioId, leidas],
    queryFn: async () => {
      const { data, error } = await getAlertas(destinatarioId, leidas)
      if (error) throw error
      return data
    },
    enabled: !!destinatarioId,
  })
}

export function useAlertasNoLeidas() {
  const { user } = useAuth()
  const destinatarioId = user?.id

  return useQuery({
    queryKey: ['alertas-no-leidas', destinatarioId],
    queryFn: async () => {
      if (!destinatarioId) return []
      const { data, error } = await getAlertasNoLeidas(destinatarioId)
      if (error) throw error
      return data
    },
    enabled: !!destinatarioId,
    refetchInterval: 30_000,
  })
}

export function useConteoNoLeidas() {
  const { user } = useAuth()
  const destinatarioId = user?.id

  return useQuery({
    queryKey: ['alertas-conteo-no-leidas', destinatarioId],
    queryFn: async () => {
      if (!destinatarioId) return 0
      const { data, error } = await getConteoNoLeidas(destinatarioId)
      if (error) throw error
      return data
    },
    enabled: !!destinatarioId,
    refetchInterval: 30_000,
  })
}

// ── Mutations ────────────────────────────────────────────

export function useMarcarLeida() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: async (alertaId: string) => {
      const { data, error } = await marcarLeida(alertaId)
      if (error) throw error
      return data
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['alertas'] })
      queryClient.invalidateQueries({ queryKey: ['alertas-no-leidas'] })
      queryClient.invalidateQueries({ queryKey: ['alertas-conteo-no-leidas'] })
    },
  })
}
