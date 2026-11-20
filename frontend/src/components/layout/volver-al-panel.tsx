'use client'

import Link from 'next/link'
import { ArrowLeft } from 'lucide-react'
import { usePermissions } from '@/hooks/use-permissions'
import { useAuth } from '@/contexts/auth-context'

/**
 * La puerta de vuelta desde una app de terreno.
 *
 * Las seis apps de /m se hicieron para un teléfono en faena, donde salir es
 * cerrar sesión: no tenían —o tenían con ícono de logout— cómo volver al
 * panel. Quien administra entra a mirar lo mismo que ve su gente y quedaba
 * atrapado: el único botón visible lo dejaba fuera del sistema.
 *
 * No se muestra a quien vive en la app —el mecánico, el operador del camión,
 * el operador de Calama—: para ellos el panel no existe y un link al
 * dashboard sólo los perdería.
 *
 * Va en bottom-20 y no bottom-4 porque Romeral y la venta de Franke tienen su
 * barra de acción fija abajo, y el botón quedaba encima de ella.
 */
export function VolverAlPanel() {
  const { esOperadorTallerSolo, esOperadorCombustibleSolo, esOperadorCalamaSolo } = usePermissions()
  const { perfil } = useAuth()

  if (esOperadorTallerSolo() || esOperadorCombustibleSolo() || esOperadorCalamaSolo()) return null
  // [19-11-2026] El mecánico de una faena con app (Franke) tampoco tiene panel:
  // el panel lo devuelve a su app, así que el botón no llevaba a ningún lado.
  if (perfil?.rol === 'tecnico_mantenimiento' && perfil?.faena?.app_movil) return null

  return (
    <Link
      href="/dashboard"
      className="fixed bottom-20 left-4 z-40 flex items-center gap-1.5 rounded-full border border-gray-300
                 bg-white/95 px-3 py-2 text-xs font-medium text-gray-700 shadow-lg backdrop-blur
                 hover:bg-gray-50 active:bg-gray-100"
    >
      <ArrowLeft className="h-4 w-4" />
      Volver al panel
    </Link>
  )
}

export default VolverAlPanel
