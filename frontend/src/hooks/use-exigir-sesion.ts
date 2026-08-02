'use client'

// Manda al login a quien abra una pantalla sin haber iniciado sesión, y lo
// devuelve a donde iba. Las apps de terreno se reparten por link: sin esto la
// pantalla cargaba vacía y parecía que no había trabajo asignado.

import { useEffect } from 'react'
import { usePathname, useRouter } from 'next/navigation'
import { useAuth } from '@/contexts/auth-context'

export function useExigirSesion(): { verificando: boolean } {
  const router = useRouter()
  const pathname = usePathname()
  const { isAuthenticated, loading } = useAuth()

  useEffect(() => {
    if (loading || isAuthenticated) return
    router.replace(`/login?next=${encodeURIComponent(pathname || '/')}`)
  }, [loading, isAuthenticated, pathname, router])

  return { verificando: loading || !isAuthenticated }
}
