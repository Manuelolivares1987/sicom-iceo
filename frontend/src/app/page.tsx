'use client'

import { useAuth } from '@/contexts/auth-context'
import { Spinner } from '@/components/ui/spinner'
import { RedireccionSegura } from '@/components/layout/redireccion-segura'

// [19-11-2026] La raíz (pilladoiceo.netlify.app/) mandaba al panel o al login
// con router.replace y un spinner verde sin salida: con señal débil o un build
// viejo en el teléfono quedaba girando para siempre. Ahora usa la redirección
// segura (a los 3 s navegación completa; a los 6 s botones).
export default function Home() {
  const { loading, isAuthenticated } = useAuth()

  if (!loading) {
    return <RedireccionSegura destino={isAuthenticated ? '/dashboard/' : '/login/'} />
  }

  return (
    <div className="flex min-h-screen items-center justify-center">
      <Spinner size="lg" className="text-pillado-green-500" />
    </div>
  )
}
