import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import {
  getProductos,
  getProductoByBarcode,
  getStockBodega,
  getValorizacionTotal,
  getBodegas,
  registrarSalida,
  registrarEntrada,
  getMovimientos,
  getKardex,
} from '@/lib/services/inventario'

// ── Queries ──────────────────────────────────────────────

export function useProductos(filters?: Record<string, unknown>) {
  return useQuery({
    queryKey: ['productos', filters],
    queryFn: async () => {
      const { data, error } = await getProductos(filters)
      if (error) throw error
      return data
    },
  })
}

export function useProductoByBarcode(codigo: string | undefined) {
  return useQuery({
    queryKey: ['producto-barcode', codigo],
    queryFn: async () => {
      const { data, error } = await getProductoByBarcode(codigo!)
      if (error) throw error
      return data
    },
    enabled: !!codigo,
  })
}

export function useStockBodega(filters?: Record<string, unknown>) {
  return useQuery({
    queryKey: ['stock-bodega', filters],
    queryFn: async () => {
      const { data, error } = await getStockBodega(filters)
      if (error) throw error
      return data
    },
  })
}

export function useValorizacionTotal(faenaId?: string) {
  return useQuery({
    queryKey: ['valorizacion-total', faenaId],
    queryFn: async () => {
      const { data, error } = await getValorizacionTotal(faenaId)
      if (error) throw error
      return data
    },
  })
}

export function useBodegas(faenaId?: string) {
  return useQuery({
    queryKey: ['bodegas', faenaId],
    queryFn: async () => {
      const { data, error } = await getBodegas(faenaId)
      if (error) throw error
      return data
    },
  })
}

export function useMovimientos(filters?: Record<string, unknown>) {
  return useQuery({
    queryKey: ['movimientos', filters],
    queryFn: async () => {
      const { data, error } = await getMovimientos(filters)
      if (error) throw error
      return data
    },
  })
}

export function useKardex(
  bodegaId: string | undefined,
  productoId: string | undefined
) {
  return useQuery({
    queryKey: ['kardex', bodegaId, productoId],
    queryFn: async () => {
      const { data, error } = await getKardex(bodegaId!, productoId!)
      if (error) throw error
      return data
    },
    enabled: !!bodegaId && !!productoId,
  })
}

// ── Mutations ────────────────────────────────────────────

/**
 * Registrar salida de inventario.
 * Critical: invalidates stock-bodega, movimientos, AND orden-trabajo
 * because salidas are validated against the OT (must be en_ejecucion).
 */
export function useRegistrarSalida() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: async (payload: {
      bodega_id: string
      producto_id: string
      cantidad: number
      ot_id: string | null
      activo_id?: string | null
      lote?: string | null
      motivo?: string | null
      usuario_id: string
    }) => {
      const { data, error } = await registrarSalida(payload)
      if (error) throw error
      return data
    },
    onSuccess: (_data, variables) => {
      queryClient.invalidateQueries({ queryKey: ['stock-bodega'] })
      queryClient.invalidateQueries({ queryKey: ['movimientos'] })
      queryClient.invalidateQueries({ queryKey: ['valorizacion-total'] })
      queryClient.invalidateQueries({ queryKey: ['kardex'] })
      // Also invalidate the OT if linked, since material costs update
      if (variables.ot_id) {
        queryClient.invalidateQueries({
          queryKey: ['orden-trabajo', variables.ot_id],
        })
        queryClient.invalidateQueries({ queryKey: ['materiales-ot', variables.ot_id] })
      }
    },
  })
}

export function useRegistrarEntrada() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: async (payload: {
      bodega_id: string
      producto_id: string
      cantidad: number
      costo_unitario: number
      documento_referencia: string
      usuario_id: string
      lote?: string | null
      fecha_vencimiento?: string | null
    }) => {
      const { data, error } = await registrarEntrada(payload)
      if (error) throw error
      return data
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['stock-bodega'] })
      queryClient.invalidateQueries({ queryKey: ['movimientos'] })
      queryClient.invalidateQueries({ queryKey: ['valorizacion-total'] })
      queryClient.invalidateQueries({ queryKey: ['kardex'] })
    },
  })
}
