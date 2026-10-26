'use client'

// Envío automático de la cola «Por enviar» de la app ENEX. Corre en todas las
// pantallas de /m/enex: al abrir, cada minuto, al volver la red y al volver a
// la app desde otra. Antes solo se intentaba al abrir la lista o con el evento
// «online», que no salta cuando el teléfono pasa de antena sin datos a antena
// con datos: lo que quedaba con error se quedaba ahí.

import { useEffect } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { syncEnexPending, protegerAlmacenamiento, guardarPantallasOffline } from '@/lib/offline/enex-offline'
import { despacharCorreosEnex } from '@/lib/offline/enex-correo'

const REINTENTO_MS = 60_000

export function EnexSyncAgent() {
  const qc = useQueryClient()

  useEffect(() => {
    // Sin esto el navegador puede vaciar lo guardado si le falta espacio.
    void protegerAlmacenamiento()

    // La primera vez en un teléfono (recién hecho el login) el service worker
    // todavía no controla la página y la descarga de las pantallas no queda
    // guardada. Se repite apenas toma el control: sin que nadie apriete nada.
    const sw = typeof navigator !== 'undefined' ? navigator.serviceWorker : undefined
    const alTomarControl = () => { void guardarPantallasOffline() }
    if (sw?.controller) alTomarControl()
    sw?.addEventListener('controllerchange', alTomarControl)

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
      // [MIG649] Informe + correo a la jefatura de lo que ya llegó.
      await despacharCorreosEnex().catch(() => 0)
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
      sw?.removeEventListener('controllerchange', alTomarControl)
    }
  }, [qc])

  return null
}
