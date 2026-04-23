import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  iniciarInformeRecepcion,
  cerrarInspeccionRecepcion,
  emitirInformeRecepcion,
  getInformeRecepcion,
  getHallazgosInforme,
  getCostosInforme,
  getInformesRecepcionLista,
  getTarifasHH,
  agregarHallazgo,
  actualizarHallazgo,
  eliminarHallazgo,
  agregarCosto,
  actualizarCosto,
  eliminarCosto,
  type EstadoInformeRecepcion,
  type InformeHallazgo,
  type InformeCosto,
} from '@/lib/services/informe-recepcion'

// ── Queries ──────────────────────────────────────────────

export function useInformeRecepcion(id?: string) {
  return useQuery({
    queryKey: ['informe-recepcion', id],
    queryFn: async () => {
      const { data, error } = await getInformeRecepcion(id!)
      if (error) throw error
      return data
    },
    enabled: !!id,
  })
}

export function useHallazgosInforme(informeId?: string) {
  return useQuery({
    queryKey: ['informe-hallazgos', informeId],
    queryFn: async () => {
      const { data, error } = await getHallazgosInforme(informeId!)
      if (error) throw error
      return data ?? []
    },
    enabled: !!informeId,
  })
}

export function useCostosInforme(informeId?: string) {
  return useQuery({
    queryKey: ['informe-costos', informeId],
    queryFn: async () => {
      const { data, error } = await getCostosInforme(informeId!)
      if (error) throw error
      return data ?? []
    },
    enabled: !!informeId,
  })
}

export function useInformesRecepcionLista(estado?: EstadoInformeRecepcion) {
  return useQuery({
    queryKey: ['informes-recepcion-lista', estado ?? 'todos'],
    queryFn: async () => {
      const { data, error } = await getInformesRecepcionLista(estado)
      if (error) throw error
      return data ?? []
    },
    staleTime: 30_000,
  })
}

export function useTarifasHH() {
  return useQuery({
    queryKey: ['tarifas-hh'],
    queryFn: async () => {
      const { data, error } = await getTarifasHH()
      if (error) throw error
      return data ?? []
    },
    staleTime: 5 * 60_000,
  })
}

// ── Mutations ────────────────────────────────────────────

export function useIniciarInformeRecepcion() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (args: { activoId: string; motivo?: string }) => {
      const { data, error } = await iniciarInformeRecepcion(args.activoId, args.motivo)
      if (error) throw error
      return data
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['informes-recepcion-lista'] })
      qc.invalidateQueries({ queryKey: ['ordenes-trabajo'] })
    },
  })
}

export function useCerrarInspeccionRecepcion() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (args: { informeId: string; firmaTecnicoUrl: string }) => {
      const { data, error } = await cerrarInspeccionRecepcion(args.informeId, args.firmaTecnicoUrl)
      if (error) throw error
      return data
    },
    onSuccess: (_d, vars) => {
      qc.invalidateQueries({ queryKey: ['informe-recepcion', vars.informeId] })
      qc.invalidateQueries({ queryKey: ['informes-recepcion-lista'] })
      qc.invalidateQueries({ queryKey: ['ordenes-trabajo'] })
    },
  })
}

export function useEmitirInformeRecepcion() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (args: {
      informeId: string
      firmaEncargadoUrl: string
      pdfUrl: string
      observaciones?: string
    }) => {
      const { data, error } = await emitirInformeRecepcion(args)
      if (error) throw error
      return data
    },
    onSuccess: (_d, vars) => {
      qc.invalidateQueries({ queryKey: ['informe-recepcion', vars.informeId] })
      qc.invalidateQueries({ queryKey: ['informes-recepcion-lista'] })
    },
  })
}

export function useAgregarHallazgo() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (payload: Parameters<typeof agregarHallazgo>[0]) => {
      const { data, error } = await agregarHallazgo(payload)
      if (error) throw error
      return data
    },
    onSuccess: (_d, vars) => {
      qc.invalidateQueries({ queryKey: ['informe-hallazgos', vars.informe_id] })
    },
  })
}

export function useActualizarHallazgo() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (args: { id: string; informeId: string; patch: Partial<InformeHallazgo> }) => {
      const { data, error } = await actualizarHallazgo(args.id, args.patch)
      if (error) throw error
      return data
    },
    onSuccess: (_d, vars) => {
      qc.invalidateQueries({ queryKey: ['informe-hallazgos', vars.informeId] })
    },
  })
}

export function useEliminarHallazgo() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (args: { id: string; informeId: string }) => {
      const { error } = await eliminarHallazgo(args.id)
      if (error) throw error
    },
    onSuccess: (_d, vars) => {
      qc.invalidateQueries({ queryKey: ['informe-hallazgos', vars.informeId] })
    },
  })
}

export function useAgregarCosto() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (payload: Parameters<typeof agregarCosto>[0]) => {
      const { data, error } = await agregarCosto(payload)
      if (error) throw error
      return data
    },
    onSuccess: (_d, vars) => {
      qc.invalidateQueries({ queryKey: ['informe-costos', vars.informe_id] })
      qc.invalidateQueries({ queryKey: ['informe-recepcion', vars.informe_id] })
    },
  })
}

export function useActualizarCosto() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (args: { id: string; informeId: string; patch: Partial<InformeCosto> }) => {
      const { data, error } = await actualizarCosto(args.id, args.patch)
      if (error) throw error
      return data
    },
    onSuccess: (_d, vars) => {
      qc.invalidateQueries({ queryKey: ['informe-costos', vars.informeId] })
      qc.invalidateQueries({ queryKey: ['informe-recepcion', vars.informeId] })
    },
  })
}

export function useEliminarCosto() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (args: { id: string; informeId: string }) => {
      const { error } = await eliminarCosto(args.id)
      if (error) throw error
    },
    onSuccess: (_d, vars) => {
      qc.invalidateQueries({ queryKey: ['informe-costos', vars.informeId] })
      qc.invalidateQueries({ queryKey: ['informe-recepcion', vars.informeId] })
    },
  })
}
