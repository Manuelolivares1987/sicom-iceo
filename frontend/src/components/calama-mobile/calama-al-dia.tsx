'use client'

// [21-11-2026] Calama sin «Descargar jornadas»: con señal, el teléfono sube lo
// pendiente y baja las jornadas SOLO (al abrir, al volver la señal confirmada,
// al volver a la app y cada 15 min). Vive en el layout de /m/calama.
import { useEffect } from 'react'
import { estaEnLinea, EVENTO_CONECTIVIDAD } from '@/lib/conectividad'
import { mantenerCalamaAlDia } from '@/lib/offline/calama-sync'

export function CalamaAlDia() {
  useEffect(() => {
    const correr = (forzar = false) => { if (estaEnLinea()) void mantenerCalamaAlDia(forzar) }
    const alConectar = (e: Event) => { if ((e as CustomEvent<{ enLinea: boolean }>).detail?.enLinea) correr(true) }
    const alVolver = () => { if (document.visibilityState === 'visible') correr() }
    correr()
    const t = setInterval(() => correr(), 15 * 60_000)
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
