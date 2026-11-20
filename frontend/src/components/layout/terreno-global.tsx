'use client'

// ============================================================================
// Piezas globales de la app de terreno (20-11-2026)
// ----------------------------------------------------------------------------
// · Recuerda la última app de terreno usada (/m/franke/, /m/enex/…): el
//   lanzador /m/ abre directo ahí, sin red y sin pasar por el panel.
// · Si la sesión del servidor se perdió (mala señal, renovación rechazada), la
//   persona sigue trabajando con lo guardado; una franja le avisa que hay que
//   volver a entrar cuando tenga señal. Nada se sube hasta entonces.
// ============================================================================

import { useEffect, useState } from 'react'
import { usePathname } from 'next/navigation'
import { useAuth } from '@/contexts/auth-context'
import { enAppTerreno, esAndroid } from '@/lib/app-terreno'

export const ULTIMA_APP_KEY = 'sicom-app-terreno'

export function TerrenoGlobal() {
  const pathname = usePathname() || '/'
  const { sesionPerdida } = useAuth()
  // [20-11-2026] En Android desde Chrome: sugerir la app instalada (no depende
  // de la configuración del navegador). Se puede cerrar y no vuelve en 7 días.
  const [sugerirApp, setSugerirApp] = useState(false)
  useEffect(() => {
    if (!pathname.startsWith('/m/') || enAppTerreno() || !esAndroid()) return
    try {
      const hasta = Number(localStorage.getItem('sicom-sugerir-app-hasta') || 0)
      if (Date.now() > hasta) setSugerirApp(true)
    } catch { /* sin storage */ }
  }, [pathname])
  const cerrarSugerencia = () => {
    setSugerirApp(false)
    try { localStorage.setItem('sicom-sugerir-app-hasta', String(Date.now() + 7 * 86_400_000)) } catch { /* noop */ }
  }

  useEffect(() => {
    const m = /^\/m\/([a-z0-9-]+)\//.exec(pathname.endsWith('/') ? pathname : `${pathname}/`)
    if (m) { try { localStorage.setItem(ULTIMA_APP_KEY, `/m/${m[1]}/`) } catch { /* noop */ } }
  }, [pathname])

  if (sugerirApp && !sesionPerdida) {
    return (
      <div className="sticky top-0 z-40 flex items-center justify-between gap-2 bg-gray-900 px-3 py-2 text-xs text-white shadow-sm">
        <span>Instale la app <b>SICOM Terreno</b>: abre al instante y funciona sin señal.</span>
        <span className="flex shrink-0 items-center gap-1">
          <a href="/instalar/" className="rounded bg-green-600 px-2 py-1 font-semibold">Instalar</a>
          <button type="button" onClick={cerrarSugerencia} aria-label="Cerrar" className="px-1.5 py-1 text-gray-300">✕</button>
        </span>
      </div>
    )
  }
  if (!sesionPerdida || !pathname.startsWith('/m/')) return null
  return (
    <div className="sticky top-0 z-40 flex items-center justify-between gap-2 bg-amber-100 px-3 py-2 text-xs text-amber-900 shadow-sm">
      <span>Sesión por renovar. Lo que registre queda guardado en el teléfono y se sube al volver a entrar.</span>
      <a href={`/login/?next=${encodeURIComponent(pathname)}`} className="shrink-0 rounded bg-amber-600 px-2 py-1 font-semibold text-white">Entrar</a>
    </div>
  )
}
