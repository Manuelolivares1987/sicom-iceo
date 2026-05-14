'use client'

import { useEffect, useState, useCallback } from 'react'
import {
  prepareCalamaOffline, syncCalamaPending, getOfflineCounters,
  discardFailedItems,
  type SyncResult, type DiscardResult,
} from '@/lib/offline/calama-sync'
import { clearCalamaDB } from '@/lib/offline/calama-db'

export function useNetworkStatus() {
  const [online, setOnline] = useState<boolean>(() =>
    typeof navigator !== 'undefined' ? navigator.onLine : true,
  )
  useEffect(() => {
    const on = () => setOnline(true)
    const off = () => setOnline(false)
    window.addEventListener('online', on)
    window.addEventListener('offline', off)
    return () => {
      window.removeEventListener('online', on)
      window.removeEventListener('offline', off)
    }
  }, [])
  return online
}

export type OfflineCounters = Awaited<ReturnType<typeof getOfflineCounters>>

export function useCalamaOfflineCounters(autoRefreshMs = 5000) {
  const [counters, setCounters] = useState<OfflineCounters | null>(null)
  const refresh = useCallback(async () => {
    if (typeof window === 'undefined') return
    try {
      const c = await getOfflineCounters()
      setCounters(c)
    } catch {
      // BD aun no inicializada o no soportada
      setCounters(null)
    }
  }, [])
  useEffect(() => {
    void refresh()
    const t = setInterval(refresh, autoRefreshMs)
    return () => clearInterval(t)
  }, [refresh, autoRefreshMs])
  return { counters, refresh }
}

export function useDownloadJornadas() {
  const [pending, setPending] = useState(false)
  const [lastError, setLastError] = useState<string | null>(null)
  const [lastResult, setLastResult] = useState<{ jornadas_count: number; downloaded_at: string } | null>(null)
  const run = useCallback(async () => {
    setPending(true); setLastError(null)
    try {
      const r = await prepareCalamaOffline()
      setLastResult(r)
      return r
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : 'Error al preparar offline'
      setLastError(msg)
      throw e
    } finally {
      setPending(false)
    }
  }, [])
  return { run, pending, lastError, lastResult }
}

export function useSyncPending() {
  const [pending, setPending] = useState(false)
  const [lastResult, setLastResult] = useState<SyncResult | null>(null)
  const run = useCallback(async () => {
    setPending(true)
    try {
      const r = await syncCalamaPending()
      setLastResult(r)
      return r
    } finally {
      setPending(false)
    }
  }, [])
  return { run, pending, lastResult }
}

export function useClearCalamaOfflineDB() {
  const [pending, setPending] = useState(false)
  const run = useCallback(async () => {
    setPending(true)
    try { await clearCalamaDB() } finally { setPending(false) }
  }, [])
  return { run, pending }
}

// Descarta eventos con sync_status 'error' o 'conflict' (y sus blobs).
// No toca pending ni synced.
export function useDiscardFailedItems() {
  const [pending, setPending] = useState(false)
  const [lastResult, setLastResult] = useState<DiscardResult | null>(null)
  const run = useCallback(async () => {
    setPending(true)
    try {
      const r = await discardFailedItems()
      setLastResult(r)
      return r
    } finally {
      setPending(false)
    }
  }, [])
  return { run, pending, lastResult }
}

// Auto-sync: dispara sincronizacion en dos casos
//   1. Browser pasa de offline -> online (evento 'online').
//   2. Componente que usa este hook se monta y ya estamos online con
//      pendientes/errores acumulados. Cubre el caso "el operador volvio al
//      campamento con WiFi y abrio /m/calama directamente, sin transicion
//      offline->online detectable".
// Sin bloquear UI. Devuelve el ultimo resultado.
export function useAutoSyncOnOnline() {
  const [lastResult, setLastResult] = useState<SyncResult | null>(null)
  useEffect(() => {
    if (typeof window === 'undefined') return
    let cancelled = false

    const trySync = async () => {
      try {
        const r = await syncCalamaPending()
        if (!cancelled) setLastResult(r)
      } catch {
        // silencioso, errores quedan en sync_queue
      }
    }

    // Caso 2: si al montar ya hay pendientes y estamos online, disparar.
    if (navigator.onLine) {
      void (async () => {
        try {
          const c = await getOfflineCounters()
          if (cancelled) return
          if (c.pendientes > 0 || c.errores > 0) {
            await trySync()
          }
        } catch {
          // BD no inicializada todavia, no hacer nada
        }
      })()
    }

    // Caso 1: evento online.
    window.addEventListener('online', trySync)
    return () => {
      cancelled = true
      window.removeEventListener('online', trySync)
    }
  }, [])
  return lastResult
}
