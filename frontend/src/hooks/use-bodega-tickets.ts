'use client'

import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  getEmitibles, getTickets, getTicketItems, getBodegas, getStockProductos,
  crearTicket, entregarTicket, anularTicket,
  type EstadoTicket,
} from '@/lib/services/bodega-tickets'

export function useTicketsEmitibles() {
  return useQuery({ queryKey: ['tickets-emitibles'], queryFn: getEmitibles, staleTime: 20_000 })
}

export function useTickets(estado?: EstadoTicket) {
  return useQuery({ queryKey: ['tickets', estado ?? 'all'], queryFn: () => getTickets(estado), staleTime: 15_000 })
}

export function useTicketItems(ticketId: string | null) {
  return useQuery({
    queryKey: ['ticket-items', ticketId ?? 'none'],
    queryFn: () => getTicketItems(ticketId!),
    enabled: !!ticketId,
  })
}

export function useBodegasTaller() {
  return useQuery({ queryKey: ['bodegas-tickets'], queryFn: getBodegas, staleTime: 5 * 60_000 })
}

export function useStockProductos(bodegaId: string | null, productoIds: string[]) {
  return useQuery({
    queryKey: ['stock-productos', bodegaId ?? 'none', [...productoIds].sort().join(',')],
    queryFn: () => getStockProductos(bodegaId!, productoIds),
    enabled: !!bodegaId && productoIds.length > 0,
    // El stock cambia con cada despacho: siempre refetch al montar/reabrir el vale.
    staleTime: 0,
    refetchOnMount: 'always',
  })
}

export function useCrearTicket() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: crearTicket,
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['tickets-emitibles'] })
      qc.invalidateQueries({ queryKey: ['tickets'] })
    },
  })
}

export function useEntregarTicket() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: entregarTicket,
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['tickets'] })
      qc.invalidateQueries({ queryKey: ['ticket-items'] })
      // La entrega rebaja stock (FIFO): refrescar el saldo que muestra el vale.
      qc.invalidateQueries({ queryKey: ['stock-productos'] })
    },
  })
}

export function useAnularTicket() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ ticketId, motivo }: { ticketId: string; motivo?: string }) => anularTicket(ticketId, motivo),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['tickets'] })
      qc.invalidateQueries({ queryKey: ['tickets-emitibles'] })
    },
  })
}
