'use client'

// [22-11-2026] La venta de Franke solo subía con su pantalla abierta y al evento
// «online». Ahora, como el resto de Franke: al abrir, al confirmarse la señal,
// al volver a la app y cada 2 minutos.
import { useEffect } from 'react'
import { estaEnLinea, EVENTO_CONECTIVIDAD } from '@/lib/conectividad'
import { syncFrankePending } from '@/lib/offline/franke-ventas-sync'

export function SincronizadorVentas() {
  useEffect(() => {
    const correr = () => { if (estaEnLinea()) void syncFrankePending().catch(() => undefined) }
    const alConectar = (e: Event) => { if ((e as CustomEvent<{ enLinea: boolean }>).detail?.enLinea) correr() }
    const alVolver = () => { if (document.visibilityState === 'visible') correr() }
    correr()
    const t = setInterval(correr, 2 * 60_000)
    window.addEventListener(EVENTO_CONECTIVIDAD, alConectar)
    document.addEventListener('visibilitychange', alVolver)
    return () => {
      clearInterval(t)
      window.removeEventListener(EVENTO_CONECTIVIDAD, alConectar)
      document.removeEventListener('visibilitychange', alVolver)
    }
  }, [])
  return null
}
