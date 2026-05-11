import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  listarOC, getOCById, crearOC, listarProveedoresActivos,
  importarOCExterna, subirDocumentoOC, recepcionarOC,
  type FiltrosOC, type CrearOCPayload, type ImportarOCExternaPayload,
  type RecepcionarOCPayload,
} from '@/lib/services/bodega-oc'

const STALE = 30_000

export function useOCList(filtros?: FiltrosOC) {
  return useQuery({
    queryKey: ['bodega-oc', 'list', filtros],
    queryFn: async () => {
      const { data, error } = await listarOC(filtros)
      if (error) throw error
      return data ?? []
    },
    staleTime: STALE,
  })
}

export function useOCById(id: string | undefined) {
  return useQuery({
    queryKey: ['bodega-oc', 'detail', id],
    queryFn: async () => {
      const { data, error } = await getOCById(id!)
      if (error) throw error
      return data
    },
    enabled: !!id,
    staleTime: STALE,
  })
}

export function useCrearOC() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (payload: CrearOCPayload) => {
      const { data, error } = await crearOC(payload)
      if (error) throw error
      return data!
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['bodega-oc'] })
    },
  })
}

export function useProveedoresActivos() {
  return useQuery({
    queryKey: ['bodega-oc', 'proveedores-activos'],
    queryFn: async () => {
      const { data, error } = await listarProveedoresActivos()
      if (error) throw error
      return data ?? []
    },
    staleTime: 5 * 60_000,
  })
}

export function useImportarOCExterna() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (payload: ImportarOCExternaPayload) => {
      const { data, error } = await importarOCExterna(payload)
      if (error) throw error
      return data!
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['bodega-oc'] })
    },
  })
}

export function useSubirDocumentoOC() {
  return useMutation({
    mutationFn: async (file: File) => {
      const { data, error } = await subirDocumentoOC(file)
      if (error) throw error
      return data!
    },
  })
}

export function useRecepcionarOC() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (payload: RecepcionarOCPayload) => {
      const { data, error } = await recepcionarOC(payload)
      if (error) throw error
      return data!
    },
    onSuccess: () => {
      // Refrescar OC, reconciliacion, stock e inventario tras recepcion.
      qc.invalidateQueries({ queryKey: ['bodega-oc'] })
      qc.invalidateQueries({ queryKey: ['bodega-reconciliacion'] })
      qc.invalidateQueries({ queryKey: ['stock-bodega'] })
      qc.invalidateQueries({ queryKey: ['movimientos'] })
      qc.invalidateQueries({ queryKey: ['kardex'] })
    },
  })
}
