import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  getGembaPlantillas,
  getGembaKpi,
  getGembaRecorridos,
  getGembaRecorrido,
  getGembaRespuestas,
  getGembaHallazgos,
  createGembaRecorrido,
  updateGembaRespuesta,
  createGembaHallazgo,
  updateGembaHallazgo,
  cerrarGembaRecorrido,
  getFaenasActivas,
  getGembaReporte,
} from '@/lib/services/gemba'

export function useGembaPlantillas() {
  return useQuery({
    queryKey: ['gemba-plantillas'],
    queryFn: async () => {
      const { data, error } = await getGembaPlantillas()
      if (error) throw error
      return data
    },
  })
}

export function useGembaKpi() {
  return useQuery({
    queryKey: ['gemba-kpi'],
    queryFn: async () => {
      const { data, error } = await getGembaKpi()
      if (error) throw error
      return data
    },
  })
}

export function useGembaRecorridos(limit?: number) {
  return useQuery({
    queryKey: ['gemba-recorridos', limit],
    queryFn: async () => {
      const { data, error } = await getGembaRecorridos(limit)
      if (error) throw error
      return data
    },
  })
}

export function useGembaRecorrido(id: string | undefined) {
  return useQuery({
    queryKey: ['gemba-recorrido', id],
    enabled: !!id,
    queryFn: async () => {
      const { data, error } = await getGembaRecorrido(id!)
      if (error) throw error
      return data
    },
  })
}

export function useGembaRespuestas(recorridoId: string | undefined) {
  return useQuery({
    queryKey: ['gemba-respuestas', recorridoId],
    enabled: !!recorridoId,
    queryFn: async () => {
      const { data, error } = await getGembaRespuestas(recorridoId!)
      if (error) throw error
      return data
    },
  })
}

export function useGembaHallazgos(recorridoId?: string, soloAbiertos = false) {
  return useQuery({
    queryKey: ['gemba-hallazgos', recorridoId ?? 'todos', soloAbiertos],
    queryFn: async () => {
      const { data, error } = await getGembaHallazgos(recorridoId, soloAbiertos)
      if (error) throw error
      return data
    },
  })
}

/** Reporte de avance del mes (MIG292). */
export function useGembaReporte(anio: number, mes: number) {
  return useQuery({
    queryKey: ['gemba-reporte', anio, mes],
    queryFn: async () => {
      const { data, error } = await getGembaReporte(anio, mes)
      if (error) throw error
      return data
    },
    staleTime: 60_000,
  })
}

export function useFaenasActivas() {
  return useQuery({
    queryKey: ['faenas-activas'],
    queryFn: async () => {
      const { data, error } = await getFaenasActivas()
      if (error) throw error
      return data
    },
  })
}

export function useCreateGembaRecorrido() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: Parameters<typeof createGembaRecorrido>[0]) => {
      const { data, error } = await createGembaRecorrido(input)
      if (error) throw error
      return data
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['gemba-recorridos'] })
      qc.invalidateQueries({ queryKey: ['gemba-kpi'] })
    },
  })
}

export function useUpdateGembaRespuesta(recorridoId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({
      id,
      ...cambios
    }: { id: string } & Parameters<typeof updateGembaRespuesta>[1]) => {
      const { data, error } = await updateGembaRespuesta(id, cambios)
      if (error) throw error
      return data
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['gemba-respuestas', recorridoId] })
    },
  })
}

export function useCreateGembaHallazgo() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: Parameters<typeof createGembaHallazgo>[0]) => {
      const { data, error } = await createGembaHallazgo(input)
      if (error) throw error
      return data
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['gemba-hallazgos'] })
      qc.invalidateQueries({ queryKey: ['gemba-kpi'] })
    },
  })
}

export function useUpdateGembaHallazgo() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({
      id,
      ...cambios
    }: { id: string } & Parameters<typeof updateGembaHallazgo>[1]) => {
      const { data, error } = await updateGembaHallazgo(id, cambios)
      if (error) throw error
      return data
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['gemba-hallazgos'] })
      qc.invalidateQueries({ queryKey: ['gemba-kpi'] })
    },
  })
}

export function useCerrarGembaRecorrido() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({ id, observaciones }: { id: string; observaciones?: string }) => {
      const { data, error } = await cerrarGembaRecorrido(id, observaciones)
      if (error) throw error
      return data
    },
    onSuccess: (_data, vars) => {
      qc.invalidateQueries({ queryKey: ['gemba-recorrido', vars.id] })
      qc.invalidateQueries({ queryKey: ['gemba-recorridos'] })
      qc.invalidateQueries({ queryKey: ['gemba-kpi'] })
    },
  })
}
