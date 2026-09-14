import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  getActividadTipos,
  getFaenasPrevencion,
  getRegistros,
  getMisRegistros,
  createRegistro,
  cerrarRegistro,
  deleteRegistro,
  getConsolidadoMes,
  upsertMeta,
  getIndicadoresAnio,
  upsertIndicadores,
  marcarEnviada,
  desmarcarEnvio,
  getFaenaConfig,
  upsertFaenaConfig,
  getMonitoreoMes,
  getSupervisoresFaena,
  getSupervisoresAsignables,
  asignarSupervisorFaena,
  quitarSupervisorFaena,
  type FaenaConfigDatos,
  type SupervisorAsignable,
  type IndicadoresFila,
  type MonitoreoSupervisor,
  type PrevencionRegistro,
} from '@/lib/services/prevencion-reportabilidad'

// Claves compartidas para invalidar en bloque cuando cambia un registro:
// el consolidado, el listado y «mis registros» muestran lo mismo desde
// ángulos distintos (regla de la casa: staleTime 5 min engaña — invalidar).
const K = {
  consolidado: 'prev-repo-consolidado',
  registros: 'prev-repo-registros',
  mis: 'prev-repo-mis-registros',
  indicadores: 'prev-repo-indicadores',
}

export function useActividadTipos() {
  return useQuery({
    queryKey: ['prev-repo-tipos'],
    queryFn: async () => {
      const { data, error } = await getActividadTipos()
      if (error) throw error
      return data
    },
  })
}

export function useFaenasPrevencion() {
  return useQuery({
    queryKey: ['prev-repo-faenas'],
    queryFn: async () => {
      const { data, error } = await getFaenasPrevencion()
      if (error) throw error
      return data
    },
  })
}

export function useConsolidadoMes(faenaId: string | null, anio: number, mes: number) {
  return useQuery({
    queryKey: [K.consolidado, faenaId, anio, mes],
    enabled: !!faenaId,
    queryFn: async () => {
      const { data, error } = await getConsolidadoMes(faenaId!, anio, mes)
      if (error) throw error
      return data
    },
  })
}

export function useRegistros(params: Parameters<typeof getRegistros>[0], enabled = true) {
  return useQuery({
    queryKey: [K.registros, params],
    enabled,
    queryFn: async () => {
      const { data, error } = await getRegistros(params)
      if (error) throw error
      return (data ?? []) as PrevencionRegistro[]
    },
  })
}

export function useMisRegistros(limit = 30) {
  return useQuery({
    queryKey: [K.mis, limit],
    queryFn: async () => {
      const { data, error } = await getMisRegistros(limit)
      if (error) throw error
      return (data ?? []) as PrevencionRegistro[]
    },
  })
}

function useInvalidarRegistros() {
  const qc = useQueryClient()
  return () => {
    qc.invalidateQueries({ queryKey: [K.consolidado] })
    qc.invalidateQueries({ queryKey: [K.registros] })
    qc.invalidateQueries({ queryKey: [K.mis] })
  }
}

export function useCreateRegistro() {
  const invalidar = useInvalidarRegistros()
  return useMutation({
    mutationFn: async (reg: Parameters<typeof createRegistro>[0]) => {
      const { data, error } = await createRegistro(reg)
      if (error) throw error
      return data
    },
    onSuccess: invalidar,
  })
}

export function useCerrarRegistro() {
  const invalidar = useInvalidarRegistros()
  return useMutation({
    mutationFn: async ({ id, observacion }: { id: string; observacion?: string }) => {
      const { data, error } = await cerrarRegistro(id, observacion)
      if (error) throw error
      return data
    },
    onSuccess: invalidar,
  })
}

export function useDeleteRegistro() {
  const invalidar = useInvalidarRegistros()
  return useMutation({
    mutationFn: async (id: string) => {
      const { error } = await deleteRegistro(id)
      if (error) throw error
    },
    onSuccess: invalidar,
  })
}

export function useUpsertMeta() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (params: Parameters<typeof upsertMeta>[0]) => {
      const { error } = await upsertMeta(params)
      if (error) throw error
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: [K.consolidado] }),
  })
}

export function useIndicadoresAnio(faenaId: string | null, anio: number) {
  return useQuery({
    queryKey: [K.indicadores, faenaId, anio],
    enabled: !!faenaId,
    queryFn: async () => {
      const { data, error } = await getIndicadoresAnio(faenaId!, anio)
      if (error) throw error
      return (data ?? []) as IndicadoresFila[]
    },
  })
}

export function useUpsertIndicadores() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (fila: IndicadoresFila) => {
      const { error } = await upsertIndicadores(fila)
      if (error) throw error
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: [K.indicadores] })
      qc.invalidateQueries({ queryKey: [K.consolidado] })
    },
  })
}

export function useMarcarEnviada() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (params: Parameters<typeof marcarEnviada>[0]) => {
      const { error } = await marcarEnviada(params)
      if (error) throw error
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: [K.consolidado] }),
  })
}

// ── Fase 2 (MIG547) ──────────────────────────────────────────────────────────

export function useFaenaConfig(faenaId: string | null) {
  return useQuery({
    queryKey: ['prev-repo-config', faenaId],
    enabled: !!faenaId,
    queryFn: async () => {
      const { data, error } = await getFaenaConfig(faenaId!)
      if (error) throw error
      return (data?.datos ?? {}) as FaenaConfigDatos
    },
  })
}

export function useUpsertFaenaConfig() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({ faenaId, datos }: { faenaId: string; datos: FaenaConfigDatos }) => {
      const { error } = await upsertFaenaConfig(faenaId, datos)
      if (error) throw error
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['prev-repo-config'] }),
  })
}

export function useMonitoreoMes(faenaId: string | null, anio: number, mes: number) {
  return useQuery({
    queryKey: ['prev-repo-monitoreo', faenaId, anio, mes],
    enabled: !!faenaId,
    queryFn: async () => {
      const { data, error } = await getMonitoreoMes(faenaId!, anio, mes)
      if (error) throw error
      return (data ?? []) as MonitoreoSupervisor[]
    },
  })
}

export function useSupervisoresFaena(faenaId: string | null) {
  return useQuery({
    queryKey: ['prev-repo-supervisores', faenaId],
    enabled: !!faenaId,
    queryFn: async () => {
      const { data, error } = await getSupervisoresFaena(faenaId!)
      if (error) throw error
      return (data ?? []) as Array<{ usuario_id: string; nombre: string; email: string }>
    },
  })
}

export function useSupervisoresAsignables(faenaId: string | null, enabled = true) {
  return useQuery({
    queryKey: ['prev-repo-sup-asignables', faenaId],
    enabled: !!faenaId && enabled,
    queryFn: async () => {
      const { data, error } = await getSupervisoresAsignables(faenaId!)
      if (error) throw error
      return (data ?? []) as SupervisorAsignable[]
    },
  })
}

export function useToggleSupervisorFaena() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({ usuarioId, faenaId, asignar }: {
      usuarioId: string
      faenaId: string
      asignar: boolean
    }) => {
      const { error } = asignar
        ? await asignarSupervisorFaena(usuarioId, faenaId)
        : await quitarSupervisorFaena(usuarioId, faenaId)
      if (error) throw error
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['prev-repo-sup-asignables'] })
      qc.invalidateQueries({ queryKey: ['prev-repo-supervisores'] })
    },
  })
}

export function useDesmarcarEnvio() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({ itemId, anio, mes }: { itemId: string; anio: number; mes: number }) => {
      const { error } = await desmarcarEnvio(itemId, anio, mes)
      if (error) throw error
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: [K.consolidado] }),
  })
}
