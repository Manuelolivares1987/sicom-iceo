'use client'

// ============================================================================
// Redirección que nunca deja a nadie pegado en la ruedita (19-11-2026)
// ----------------------------------------------------------------------------
// Los guards del panel mandan a cada uno a su pantalla con router.replace y,
// mientras tanto, mostraban SOLO un spinner. Con señal de faena, o con una
// versión vieja de la app en el teléfono (chunks que ya no existen tras un
// deploy), esa navegación interna no termina nunca y el usuario queda "con
// sesión pero cargando para siempre" (Yohan y Edison, Franke, tras MIG714).
//
// Escalera:
//   0 s  → navegación interna (rápida, sin recargar).
//   3 s  → si seguimos acá, navegación completa del navegador
//          (window.location.replace): no depende del router de Next ni de
//          chunks viejos.
//   6 s  → se muestran botones: un link normal a su pantalla y «Reparar app»,
//          que borra la caché del service worker y recarga. NO toca IndexedDB
//          ni localStorage: lo pendiente de las apps sin señal se conserva.
// ============================================================================

import { useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'
import { Spinner } from '@/components/ui/spinner'

export async function repararApp(destino?: string) {
  // Sin señal no se borra nada: la caché es lo único que abre las apps de
  // terreno offline, y sin red no se podría volver a bajar.
  if (typeof navigator !== 'undefined' && !navigator.onLine) {
    window.location.replace(destino ?? window.location.href)
    return
  }
  try {
    if ('serviceWorker' in navigator) {
      const regs = await navigator.serviceWorker.getRegistrations()
      await Promise.all(regs.map((r) => r.unregister()))
    }
  } catch { /* sigue */ }
  try {
    if ('caches' in window) {
      const keys = await caches.keys()
      await Promise.all(keys.map((k) => caches.delete(k)))
    }
  } catch { /* sigue */ }
  const url = new URL(destino ?? window.location.pathname, window.location.origin)
  url.searchParams.set('v', String(Date.now()))
  window.location.replace(url.toString())
}

export function RedireccionSegura({ destino }: { destino: string }) {
  const router = useRouter()
  const [mostrarAyuda, setMostrarAyuda] = useState(false)

  useEffect(() => {
    router.replace(destino)
    const duro = window.setTimeout(() => {
      // Si el router no llegó, el navegador sí llega.
      window.location.replace(destino)
    }, 3000)
    const ayuda = window.setTimeout(() => setMostrarAyuda(true), 6000)
    return () => {
      window.clearTimeout(duro)
      window.clearTimeout(ayuda)
    }
  }, [destino, router])

  return (
    <div className="flex h-screen flex-col items-center justify-center gap-6 px-6 text-center">
      <Spinner size="lg" className="text-gray-400" />
      {mostrarAyuda && (
        <div className="max-w-xs space-y-3">
          <p className="text-sm text-gray-600">
            Está tardando más de lo normal. Puede ser la señal o una versión antigua de la app.
          </p>
          {/* Link normal (no next/link): navegación completa del navegador. */}
          <a
            href={destino}
            className="block rounded-lg bg-gray-900 px-4 py-3 text-sm font-semibold text-white active:bg-gray-700"
          >
            Ir a mi pantalla
          </a>
          <button
            type="button"
            onClick={() => repararApp(destino)}
            className="block w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-medium text-gray-700 active:bg-gray-100"
          >
            Reparar app
          </button>
          <p className="text-xs text-gray-400">
            «Reparar app» no borra lo que tenga guardado sin señal. No cierre sesión.
          </p>
        </div>
      )}
    </div>
  )
}

export default RedireccionSegura
