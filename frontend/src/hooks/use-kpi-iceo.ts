import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  getMedicionesKPI,
  getICEOPeriodo,
  getICEOHistorico,
  calcularKPIs,
  calcularICEO,
  getKPIDefiniciones,
  getBloqueantesStatus,
} from '@/lib/services/kpi-iceo'

// ── Queries ──────────────────────────────────────────────

export function useMedicionesKPI(
  contratoId: string,
  faenaId?: string,
  periodo?: string
) {
  return useQuery({
    queryKey: ['mediciones-kpi', contratoId, faenaId, periodo],
    queryFn: async () => {
      const { data, error } = await getMedicionesKPI(contratoId, faenaId, periodo)
      if (error) throw error
      return data
    },
    enabled: !!contratoId,
  })
}

export function useICEOPeriodo(
  contratoId: string,
  faenaId?: string,
  periodo?: string
) {
  return useQuery({
    queryKey: ['iceo-periodo', contratoId, faenaId, periodo],
    queryFn: async () => {
      const { data, error } = await getICEOPeriodo(contratoId, faenaId, periodo)
      if (error) throw error
      return data
    },
    enabled: !!contratoId,
  })
}

export function useICEOHistorico(
  contratoId: string,
  faenaId?: string,
  meses: number = 6
) {
  return useQuery({
    queryKey: ['iceo-historico', contratoId, faenaId, meses],
    queryFn: async () => {
      const { data, error } = await getICEOHistorico(contratoId, faenaId, meses)
      if (error) throw error
      return data
    },
    enabled: !!contratoId,
  })
}

export function useKPIDefiniciones() {
  return useQuery({
    queryKey: ['kpi-definiciones'],
    queryFn: async () => {
      const { data, error } = await getKPIDefiniciones()
      if (error) throw error
      return data
    },
    staleTime: Infinity, // KPI definitions rarely change
  })
}

export function useBloqueantesStatus(
  contratoId: string,
  faenaId?: string,
  periodo?: string
) {
  return useQuery({
    queryKey: ['bloqueantes-status', contratoId, faenaId, periodo],
    queryFn: async () => {
      const { data, error } = await getBloqueantesStatus(contratoId, faenaId, periodo)
      if (error) throw error
      return data
    },
    enabled: !!contratoId,
  })
}

// ── Mutations ────────────────────────────────────────────

export function useCalcularKPIs() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: async ({
      contratoId,
      faenaId,
      periodoInicio,
      periodoFin,
    }: {
      contratoId: string
      faenaId?: string
      periodoInicio: string
      periodoFin: string
    }) => {
      const { data, error } = await calcularKPIs(
        contratoId,
        faenaId,
        periodoInicio,
        periodoFin
      )
      if (error) throw error
      return data
    },
    onSuccess: (_data, { contratoId, faenaId }) => {
      queryClient.invalidateQueries({ queryKey: ['mediciones-kpi', contratoId] })
      queryClient.invalidateQueries({
        queryKey: ['bloqueantes-status', contratoId],
      })
      if (faenaId) {
        queryClient.invalidateQueries({
          queryKey: ['mediciones-kpi', contratoId, faenaId],
        })
      }
    },
  })
}

export function useCalcularICEO() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: async ({
      contratoId,
      faenaId,
      periodoInicio,
      periodoFin,
    }: {
      contratoId: string
      faenaId?: string
      periodoInicio: string
      periodoFin: string
    }) => {
      const { data, error } = await calcularICEO(
        contratoId,
        faenaId,
        periodoInicio,
        periodoFin
      )
      if (error) throw error
      return data
    },
    onSuccess: (_data, { contratoId }) => {
      queryClient.invalidateQueries({ queryKey: ['iceo-periodo', contratoId] })
      queryClient.invalidateQueries({ queryKey: ['iceo-historico', contratoId] })
      queryClient.invalidateQueries({ queryKey: ['mediciones-kpi', contratoId] })
    },
  })
}
