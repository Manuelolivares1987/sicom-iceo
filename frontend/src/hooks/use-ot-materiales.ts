import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  agregarMaterialOT,
  despacharMaterialOT,
  cancelarMaterialOT,
  getMaterialesPorOT,
  getMaterialesPendientesDespacho,
  buscarProductos,
} from '@/lib/services/ot-materiales'

export function useMaterialesPorOT(otId?: string) {
  return useQuery({
    queryKey: ['ot-materiales', otId],
    queryFn: async () => {
      const { data, error } = await getMaterialesPorOT(otId!)
      if (error) throw error
      return data ?? []
    },
    enabled: !!otId,
  })
}

export function useMaterialesPendientesDespacho() {
  return useQuery({
    queryKey: ['materiales-pendientes-despacho'],
    queryFn: async () => {
      const { data, error } = await getMaterialesPendientesDespacho()
      if (error) throw error
      return data ?? []
    },
    staleTime: 20_000,
  })
}

export function useAgregarMaterialOT() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (args: {
      otId: string
      productoId: string
      cantidad: number
      comentario?: string
    }) => {
      const { data, error } = await agregarMaterialOT(
        args.otId, args.productoId, args.cantidad, args.comentario,
      )
      if (error) throw error
      return data
    },
    onSuccess: (_data, vars) => {
      qc.invalidateQueries({ queryKey: ['ot-materiales', vars.otId] })
      qc.invalidateQueries({ queryKey: ['materiales-pendientes-despacho'] })
    },
  })
}

export function useDespacharMaterialOT() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (args: { materialId: string; cantidad?: number; otId: string }) => {
      const { data, error } = await despacharMaterialOT(args.materialId, args.cantidad)
      if (error) throw error
      return data
    },
    onSuccess: (_data, vars) => {
      qc.invalidateQueries({ queryKey: ['ot-materiales', vars.otId] })
      qc.invalidateQueries({ queryKey: ['materiales-pendientes-despacho'] })
      qc.invalidateQueries({ queryKey: ['stock-bodega'] })
    },
  })
}

export function useCancelarMaterialOT() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (args: { materialId: string; otId: string }) => {
      const { error } = await cancelarMaterialOT(args.materialId)
      if (error) throw error
    },
    onSuccess: (_data, vars) => {
      qc.invalidateQueries({ queryKey: ['ot-materiales', vars.otId] })
      qc.invalidateQueries({ queryKey: ['materiales-pendientes-despacho'] })
    },
  })
}

export function useBuscarProductos(query: string) {
  return useQuery({
    queryKey: ['buscar-productos', query],
    queryFn: async () => {
      const { data, error } = await buscarProductos(query)
      if (error) throw error
      return data ?? []
    },
    enabled: query.trim().length >= 2,
    staleTime: 30_000,
  })
}
