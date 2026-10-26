'use client'

// Envío automático de la cola «Por enviar» de la app ENEX. Corre en todas las
// pantallas de /m/enex: al abrir, cada minuto, al volver la red y al volver a
// la app desde otra. Antes solo se intentaba al abrir la lista o con el evento
// «online», que no salta cuando el teléfono pasa de antena sin datos a antena
// con datos: lo que quedaba con error se quedaba ahí.

import { useEffect } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { syncEnexPending, protegerAlmacenamiento } from '@/lib/offline/enex-offline'

const REINTENTO_MS = 60_000

export function EnexSyncAgent() {
  const qc = useQueryClient()

  useEffect(() => {
    // Sin esto el navegador puede vaciar lo guardado si le falta espacio.
    void protegerAlmacenamiento()

    let vivo = true
    const intentar = async () => {
      if (!vivo || (typeof navigator !== 'undefined' && !navigator.onLine)) return
      const r = await syncEnexPending().catch(() => ({ ok: 0, failed: 0 }))
      if (r.ok > 0 || r.failed > 0) {
        qc.invalidateQueries({ queryKey: ['enex-terreno'] })
        qc.invalidateQueries({ queryKey: ['enex-servicio'] })
      }
      qc.invalidateQueries({ queryKey: ['enex-pending-count'] })
      qc.invalidateQueries({ queryKey: ['enex-bandeja'] })
    }
    const alVolver = () => { if (document.visibilityState === 'visible') void intentar() }

    void intentar()
    const t = setInterval(() => void intentar(), REINTENTO_MS)
    window.addEventListener('online', intentar)
    document.addEventListener('visibilitychange', alVolver)
    return () => {
      vivo = false
      clearInterval(t)
      window.removeEventListener('online', intentar)
      document.removeEventListener('visibilitychange', alVolver)
    }
  }, [qc])

  return null
}
