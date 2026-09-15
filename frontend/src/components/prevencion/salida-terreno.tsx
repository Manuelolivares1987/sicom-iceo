'use client'

import { useRouter } from 'next/navigation'
import { LogOut } from 'lucide-react'
import { useAuth } from '@/contexts/auth-context'
import { usePermissions } from '@/hooks/use-permissions'
import { VolverAlPanel } from '@/components/layout/volver-al-panel'

/**
 * Las dos salidas de la app de prevención.
 *
 * El supervisor de terreno entra desde el teléfono, carga sus registros y
 * se va: para él salir es CERRAR SESIÓN. Hasta hoy el único botón visible
 * era «Volver al panel», que a un supervisor de Calama lo mandaba a un
 * escritorio que no es suyo (Manuel, 15-09-2026: «no tengo cómo salir de la
 * aplicación, me indica volver a panel y no es correcto»).
 *
 * «Volver al panel» se queda sólo para quien tiene panel de verdad: la
 * administración, prevención, las jefaturas, y el supervisor de una faena
 * con panel propio (Romeral). «Cerrar sesión» lo ven todos.
 */
export function SalidaTerrenoPrevencion() {
  const { perfil, signOut } = useAuth()
  const { faenaExclusiva } = usePermissions()
  const router = useRouter()

  const salir = async () => {
    try { await signOut() } catch { /* la sesión local igual se limpia abajo */ }
    router.replace('/login')
  }

  const tienePanel = perfil?.rol !== 'supervisor' || !!faenaExclusiva()?.panel_web

  return (
    <>
      {tienePanel && <VolverAlPanel />}
      <button
        type="button"
        onClick={salir}
        className="fixed bottom-20 right-4 z-40 flex items-center gap-1.5 rounded-full border border-gray-300
                   bg-white/95 px-3 py-2 text-xs font-medium text-gray-700 shadow-lg backdrop-blur
                   hover:bg-gray-50 active:bg-gray-100"
      >
        <LogOut className="h-4 w-4" />
        Cerrar sesión
      </button>
    </>
  )
}

export default SalidaTerrenoPrevencion
