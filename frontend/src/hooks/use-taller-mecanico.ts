'use client'

import { useEffect } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useNetworkStatus } from '@/hooks/use-calama-offline'
import { supabase } from '@/lib/supabase'
import type { MedicionItem } from '@/lib/services/taller-plan-semanal'
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
      mediciones?: MedicionItem
      valor_numerico?: number | null
      /** [MIG496] Firmas del cierre de recepción (B11.07). */
      firmas?: { campo: 'firma_operador_url' | 'firma_taller_url'; blob: Blob }[]
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
      /** [MIG472] Por qué se cierra con tareas obligatorias sin hacer. */
      motivoPendientes?: string | null
    }) => queueTiming(otId, p.accion, p.userId, {
      observaciones: p.observaciones, conObservaciones: p.conObservaciones, firma: p.firma,
      tecnicoId: p.tecnicoId, motivoPendientes: p.motivoPendientes,
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
  /** [MIG471] Totalizador del surtidor. Sólo en aljibes de combustible. */
  cuenta_litros: number | null
  exige_kilometraje: boolean
  exige_cuenta_litros: boolean
  anotado_por_persona: boolean
}

export function useMedidoresOT(otId: string | null) {
  return useQuery({
    queryKey: ['mec-medidores', otId],
    enabled: !!otId,
    queryFn: async (): Promise<MedidoresOT | null> => {
      const { data, error } = await supabase
        .from('checklist_v2_instance')
        .select('id, horometro, kilometraje, cuenta_litros, medidores_por, activo_id, activos!activo_id(tipo, tipo_equipamiento)')
        .eq('ot_id', otId!)
        .order('created_at', { ascending: false })
        .limit(1)
        .maybeSingle()
      if (error) throw error
      if (!data) return null
      const act = (data as unknown as { activos?: { tipo?: string; tipo_equipamiento?: string } }).activos
      const tipo = act?.tipo ?? ''
      return {
        instance_id: (data as { id: string }).id,
        horometro: (data as { horometro: number | null }).horometro,
        kilometraje: (data as { kilometraje: number | null }).kilometraje,
        cuenta_litros: (data as { cuenta_litros: number | null }).cuenta_litros,
        exige_kilometraje: ['camion', 'camion_cisterna', 'camioneta', 'lubrimovil'].includes(tipo),
        // [MIG471] El totalizador del surtidor sólo existe en los aljibes de
        // combustible. Pedirlo donde no existe enseña a inventar números.
        exige_cuenta_litros: act?.tipo_equipamiento === 'aljibe_combustible',
        anotado_por_persona: (data as { medidores_por: string | null }).medidores_por != null,
      }
    },
  })
}

export function useGuardarMedidores(otId: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (v: {
      horometro: number | null; kilometraje: number | null
      cuentaLitros?: number | null; confirmado?: boolean
    }) => {
      const { data, error } = await supabase.rpc('rpc_taller_registrar_medidores', {
        p_ot_id: otId,
        p_horometro: v.horometro,
        p_kilometraje: v.kilometraje,
        p_confirmado: v.confirmado ?? false,
        p_cuenta_litros: v.cuentaLitros ?? null,
      })
      if (error) throw error
      return data as { success: boolean; requiere_confirmacion?: boolean; motivo?: string }
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['mec-medidores', otId] })
      // [MIG496] El servidor llena solo el «próximo horómetro de pauta»
      // (B11.04 = horómetro + 300): refrescar el checklist para que se vea.
      qc.invalidateQueries({ queryKey: ['mec-checklist', otId] })
    },
  })
}

export type { MecanicoOT }
