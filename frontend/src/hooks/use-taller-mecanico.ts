'use client'

import { useEffect } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useNetworkStatus } from '@/hooks/use-calama-offline'
import { supabase } from '@/lib/supabase'
import {
  getOTs, getChecklistMecanico, queueItem, queueTiming, syncTallerPending, getPendingCount,
  prepareTallerOffline, getRecursosMecanico, queueRecurso,
  getNotasMecanico, queueNota, type MecanicoOT,
} from '@/lib/offline/taller-mecanico-sync'

export { useNetworkStatus }

const KEY_OTS = ['mec-ots'] as const
const KEY_PENDING = ['mec-pending'] as const
const keyChecklist = (otId: string) => ['mec-checklist', otId] as const
const keyRecursos = (otId: string) => ['mec-recursos', otId] as const
const keyNotas = (otId: string) => ['mec-notas', otId] as const

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
      resultado?: 'ok' | 'no_ok' | 'na'; observacion?: string | null
      file?: File | null; files?: (File | Blob)[]
      mediciones?: { pos: string; mm: number | null }[]
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
      tecnicoId?: string | null
    }) => queueTiming(otId, p.accion, p.userId, {
      observaciones: p.observaciones, conObservaciones: p.conObservaciones, firma: p.firma,
      tecnicoId: p.tecnicoId,
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
      fotos?: (File | Blob)[]; instanceItemId?: string | null
    }) => queueRecurso({ otId, ...p }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: keyRecursos(otId) })
      qc.invalidateQueries({ queryKey: KEY_PENDING })
    },
  })
}

export function useNotasOT(otId: string | null) {
  return useQuery({
    queryKey: otId ? keyNotas(otId) : ['mec-notas', 'none'],
    queryFn: () => getNotasMecanico(otId!),
    enabled: !!otId,
    networkMode: 'always',
  })
}

export function useAgregarNota(otId: string) {
  const qc = useQueryClient()
  return useMutation({
    networkMode: 'always',
    mutationFn: (p: { texto: string; autor?: string | null; fotos?: (File | Blob)[] }) =>
      queueNota({ otId, ...p }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: keyNotas(otId) })
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


// ── Medidores del equipo (MIG397) ───────────────────────────────────────────
// Con cuánto uso volvió el equipo. De este número salen la próxima preventiva y
// lo que se le cobra al cliente por el uso; si no queda escrito acá, no queda
// escrito en ninguna parte. Antes las columnas existían pero el mecánico no
// tenía dónde llenarlas: 46 de 120 recepciones quedaron sin ningún medidor.

export type MedidoresOT = {
  instance_id: string
  horometro: number | null
  kilometraje: number | null
  exige_kilometraje: boolean
  anotado_por_persona: boolean
}

export function useMedidoresOT(otId: string | null) {
  return useQuery({
    queryKey: ['mec-medidores', otId],
    enabled: !!otId,
    queryFn: async (): Promise<MedidoresOT | null> => {
      const { data, error } = await supabase
        .from('checklist_v2_instance')
        .select('id, horometro, kilometraje, medidores_por, activo_id, activos!activo_id(tipo)')
        .eq('ot_id', otId!)
        .order('created_at', { ascending: false })
        .limit(1)
        .maybeSingle()
      if (error) throw error
      if (!data) return null
      const tipo = (data as unknown as { activos?: { tipo?: string } }).activos?.tipo ?? ''
      return {
        instance_id: (data as { id: string }).id,
        horometro: (data as { horometro: number | null }).horometro,
        kilometraje: (data as { kilometraje: number | null }).kilometraje,
        exige_kilometraje: ['camion', 'camion_cisterna', 'camioneta', 'lubrimovil'].includes(tipo),
        anotado_por_persona: (data as { medidores_por: string | null }).medidores_por != null,
      }
    },
  })
}

export function useGuardarMedidores(otId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (v: { horometro: number | null; kilometraje: number | null; confirmado?: boolean }) => {
      const { data, error } = await supabase.rpc('rpc_taller_registrar_medidores', {
        p_ot_id: otId,
        p_horometro: v.horometro,
        p_kilometraje: v.kilometraje,
        p_confirmado: v.confirmado ?? false,
      })
      if (error) throw error
      return data as { success: boolean; requiere_confirmacion?: boolean; motivo?: string }
    },
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['mec-medidores', otId] }) },
  })
}

export type { MecanicoOT }
