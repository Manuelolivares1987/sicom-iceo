'use client'

// Manda al login a quien abra una pantalla sin haber iniciado sesión, y lo
// devuelve a donde iba. Las apps de terreno se reparten por link: sin esto la
// pantalla cargaba vacía y parecía que no había trabajo asignado.

import { useEffect } from 'react'
import { usePathname, useRouter } from 'next/navigation'
import { useAuth } from '@/contexts/auth-context'

export function useExigirSesion(): {
  verificando: boolean
  /** Sin sesión y sin señal: mandar al login no sirve de nada, hay que decirlo. */
  sinSesionOffline: boolean
} {
  const router = useRouter()
  const pathname = usePathname()
  const { isAuthenticated, loading } = useAuth()

  const offline = typeof navigator !== 'undefined' && !navigator.onLine
  const sinSesionOffline = !loading && !isAuthenticated && offline

  useEffect(() => {
    if (loading || isAuthenticated) return
    // Sin conexión el login tampoco carga ni valida: se queda en la pantalla
    // con un aviso claro en vez de rebotar a un formulario inservible.
    if (typeof navigator !== 'undefined' && !navigator.onLine) return
    router.replace(`/login?next=${encodeURIComponent(pathname || '/')}`)
  }, [loading, isAuthenticated, pathname, router])

  return { verificando: loading || (!isAuthenticated && !sinSesionOffline), sinSesionOffline }
}
