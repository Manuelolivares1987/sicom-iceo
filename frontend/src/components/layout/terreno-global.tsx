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

import { useEffect } from 'react'
import { usePathname } from 'next/navigation'
import { useAuth } from '@/contexts/auth-context'

export const ULTIMA_APP_KEY = 'sicom-app-terreno'

export function TerrenoGlobal() {
  const pathname = usePathname() || '/'
  const { sesionPerdida } = useAuth()

  useEffect(() => {
    const m = /^\/m\/([a-z0-9-]+)\//.exec(pathname.endsWith('/') ? pathname : `${pathname}/`)
    if (m) { try { localStorage.setItem(ULTIMA_APP_KEY, `/m/${m[1]}/`) } catch { /* noop */ } }
  }, [pathname])

  if (!sesionPerdida || !pathname.startsWith('/m/')) return null
  return (
    <div className="sticky top-0 z-40 flex items-center justify-between gap-2 bg-amber-100 px-3 py-2 text-xs text-amber-900 shadow-sm">
      <span>Sesión por renovar. Lo que registre queda guardado en el teléfono y se sube al volver a entrar.</span>
      <a href={`/login/?next=${encodeURIComponent(pathname)}`} className="shrink-0 rounded bg-amber-600 px-2 py-1 font-semibold text-white">Entrar</a>
    </div>
  )
}
