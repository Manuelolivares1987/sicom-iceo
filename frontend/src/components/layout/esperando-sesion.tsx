'use client'

// Ruedita de «verificando sesión» de las apps de terreno, con salida (20-11-2026).
// Antes era SOLO un spinner: si el teléfono quedaba con una versión vieja o la
// señal no alcanzaba, la persona miraba la ruedita para siempre (Franke).
// A los 6 s aparecen «Entrar de nuevo» (navegación completa al login) y
// «Reparar app» (borra la caché de la app; no toca lo guardado sin señal).

import { useEffect, useState } from 'react'
import { usePathname } from 'next/navigation'
import { Spinner } from '@/components/ui/spinner'
import { repararApp } from '@/components/layout/redireccion-segura'

export function EsperandoSesion() {
  const pathname = usePathname()
  const [ayuda, setAyuda] = useState(false)
  useEffect(() => {
    const t = window.setTimeout(() => setAyuda(true), 6000)
    return () => window.clearTimeout(t)
  }, [])
  const login = `/login/?next=${encodeURIComponent(pathname || '/')}`
  return (
    <div className="flex min-h-screen flex-col items-center justify-center gap-6 bg-gray-50 px-6 text-center">
      <Spinner className="h-8 w-8 text-gray-400" />
      {ayuda && (
        <div className="max-w-xs space-y-3">
          <p className="text-sm text-gray-600">Está tardando más de lo normal. Puede ser la señal o una versión antigua de la app.</p>
          <a href={login} className="block rounded-lg bg-gray-900 px-4 py-3 text-sm font-semibold text-white active:bg-gray-700">
            Entrar de nuevo
          </a>
          <button type="button" onClick={() => repararApp(pathname || '/')}
                  className="block w-full rounded-lg border border-gray-300 bg-white px-4 py-3 text-sm font-medium text-gray-700 active:bg-gray-100">
            Reparar app
          </button>
          <p className="text-xs text-gray-400">No se borra lo guardado sin señal. No cierre sesión.</p>
        </div>
      )}
    </div>
  )
}
