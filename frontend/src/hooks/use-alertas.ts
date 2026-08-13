import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  getAlertas,
  getAlertasNoLeidas,
  getConteoNoLeidas,
  getConteoPorDecidir,
  marcarInformativasLeidas,
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

/** Solo lo que espera una decisión: es el número que va en la campanita. */
export function useConteoPorDecidir() {
  const { user } = useAuth()
  const destinatarioId = user?.id

  return useQuery({
    queryKey: ['alertas-conteo-por-decidir', destinatarioId],
    queryFn: async () => {
      if (!destinatarioId) return 0
      const { data, error } = await getConteoPorDecidir(destinatarioId)
      if (error) throw error
      return data
    },
    enabled: !!destinatarioId,
    refetchInterval: 30_000,
  })
}

// ── Mutations ────────────────────────────────────────────

export function useMarcarInformativasLeidas() {
  const queryClient = useQueryClient()
  const { user } = useAuth()

  return useMutation({
    mutationFn: async () => {
      if (!user?.id) return
      const { error } = await marcarInformativasLeidas(user.id)
      if (error) throw error
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['alertas'] })
      queryClient.invalidateQueries({ queryKey: ['alertas-no-leidas'] })
      queryClient.invalidateQueries({ queryKey: ['alertas-conteo-no-leidas'] })
      queryClient.invalidateQueries({ queryKey: ['alertas-conteo-por-decidir'] })
    },
  })
}

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
      queryClient.invalidateQueries({ queryKey: ['alertas-conteo-por-decidir'] })
    },
  })
}
