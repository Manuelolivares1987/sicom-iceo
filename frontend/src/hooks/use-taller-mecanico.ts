'use client'

import { useEffect } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useNetworkStatus } from '@/hooks/use-calama-offline'
import {
  getOTs, getChecklistMecanico, queueItem, queueTiming, syncTallerPending, getPendingCount,
  prepareTallerOffline, getRecursosMecanico, queueRecurso, type MecanicoOT,
} from '@/lib/offline/taller-mecanico-sync'

export { useNetworkStatus }

const KEY_OTS = ['mec-ots'] as const
const KEY_PENDING = ['mec-pending'] as const
const keyChecklist = (otId: string) => ['mec-checklist', otId] as const
const keyRecursos = (otId: string) => ['mec-recursos', otId] as const

export function useMecanicoOTs() {
  return useQuery({
    queryKey: KEY_OTS,
    queryFn: getOTs,
    networkMode: 'always',
    staleTime: 10_000,
  })
}

export function useMecanicoChecklist(otId: string | null) {
  return useQuery({
    queryKey: otId ? keyChecklist(otId) : ['mec-checklist', 'none'],
    queryFn: () => getChecklistMecanico(otId!),
    enabled: !!otId,
    networkMode: 'always',
  })
}

export function usePendingCount(autoRefreshMs = 4000) {
  return useQuery({
    queryKey: KEY_PENDING,
    queryFn: getPendingCount,
    networkMode: 'always',
    refetchInterval: autoRefreshMs,
  })
}

export function useMarcarItem(otId: string) {
  const qc = useQueryClient()
  return useMutation({
    networkMode: 'always',
    mutationFn: (p: {
      instanceItemId: string; instanceId: string
      resultado?: 'ok' | 'no_ok' | 'na'; observacion?: string | null; file?: File | null
    }) => queueItem({ otId, ...p }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: keyChecklist(otId) })
      qc.invalidateQueries({ queryKey: KEY_OTS })
      qc.invalidateQueries({ queryKey: KEY_PENDING })
    },
  })
}

export function useTimingMecanico(otId: string) {
  const qc = useQueryClient()
  return useMutation({
    networkMode: 'always',
    mutationFn: (p: {
      accion: 'iniciar' | 'pausar' | 'finalizar'; userId: string
      observaciones?: string | null; conObservaciones?: boolean; firma?: File | Blob | null
    }) => queueTiming(otId, p.accion, p.userId, {
      observaciones: p.observaciones, conObservaciones: p.conObservaciones, firma: p.firma,
    }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: keyChecklist(otId) })
      qc.invalidateQueries({ queryKey: KEY_OTS })
      qc.invalidateQueries({ queryKey: KEY_PENDING })
    },
  })
}

export function useRecursosOT(otId: string | null) {
  return useQuery({
    queryKey: otId ? keyRecursos(otId) : ['mec-recursos', 'none'],
    queryFn: () => getRecursosMecanico(otId!),
    enabled: !!otId,
    networkMode: 'always',
  })
}

export function useSolicitarRecurso(otId: string) {
  const qc = useQueryClient()
  return useMutation({
    networkMode: 'always',
    mutationFn: (p: {
      productoId?: string | null; productoNombre?: string | null
      descripcion?: string | null; unidad?: string | null
      cantidad: number; comentario?: string | null; solicitadoNombre?: string | null
    }) => queueRecurso({ otId, ...p }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: keyRecursos(otId) })
      qc.invalidateQueries({ queryKey: KEY_PENDING })
    },
  })
}

export function useDescargarOffline() {
  const qc = useQueryClient()
  return useMutation({
    networkMode: 'always',
    mutationFn: (otIds: string[]) => prepareTallerOffline(otIds),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: KEY_OTS })
      qc.invalidateQueries({ queryKey: ['mec-checklist'] })
    },
  })
}

export function useSyncTaller() {
  const qc = useQueryClient()
  return useMutation({
    networkMode: 'always',
    mutationFn: syncTallerPending,
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: KEY_OTS })
      qc.invalidateQueries({ queryKey: KEY_PENDING })
      qc.invalidateQueries({ queryKey: ['mec-checklist'] })
      qc.invalidateQueries({ queryKey: ['mec-recursos'] })
    },
  })
}

/** Sincroniza automáticamente al recuperar conexión. */
export function useAutoSyncTaller() {
  const qc = useQueryClient()
  useEffect(() => {
    const trySync = async () => {
      if (typeof navigator !== 'undefined' && navigator.onLine) {
        await syncTallerPending()
        qc.invalidateQueries({ queryKey: KEY_OTS })
        qc.invalidateQueries({ queryKey: KEY_PENDING })
        qc.invalidateQueries({ queryKey: ['mec-checklist'] })
        qc.invalidateQueries({ queryKey: ['mec-recursos'] })
      }
    }
    window.addEventListener('online', trySync)
    void trySync()
    return () => window.removeEventListener('online', trySync)
  }, [qc])
}

export type { MecanicoOT }
