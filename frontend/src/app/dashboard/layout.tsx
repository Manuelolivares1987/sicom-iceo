'use client'

import { useEffect } from 'react'
import { useRouter, usePathname } from 'next/navigation'
import AppShell from '@/components/layout/app-shell'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { usePermissions } from '@/hooks/use-permissions'
import { useAuth } from '@/contexts/auth-context'
import { Spinner } from '@/components/ui/spinner'

export default function DashboardLayout({
  children,
}: {
  children: React.ReactNode
}) {
  const { loading } = useRequireAuth()
  const { perfil } = useAuth()
  const { esOperadorCalamaSolo, esSupervisorCalamaSolo, esOperadorTallerSolo,
          esOperadorCombustibleSolo } = usePermissions()
  const router = useRouter()
  const pathname = usePathname()

  // La app de terreno la declara la faena (MIG361), no el rol. Mientras Romeral
  // fue la única faena con app, mandar a todo operador de combustible a
  // /m/romeral era correcto; con Franke adentro sería mandar a un conductor de
  // Taltal al catálogo y a los camiones de otra faena.
  const appDeFaena = perfil?.faena?.app_movil ?? null

  // Guards de ruta:
  //  - OOCC: cualquier /dashboard/* → /m/calama.
  //  - Operador de Taller: cualquier /dashboard/* → /m/taller.
  //  - Operador de Combustible: cualquier /dashboard/* → la app de su faena.
  //  - Mecánico de una faena con app: su pauta está allá, no en el panel web.
  //  - Supervisor Calama: cualquier /dashboard/* fuera de /dashboard/operacion-calama → /dashboard/operacion-calama.
  useEffect(() => {
    if (loading) return
    if (esOperadorCalamaSolo()) {
      router.replace('/m/calama')
      return
    }
    if (esOperadorTallerSolo()) {
      router.replace('/m/taller')
      return
    }
    if (esOperadorCombustibleSolo()) {
      // Romeral por defecto: es donde caían antes de que las faenas declararan
      // su app, y una faena sin app no debe dejar a nadie en el limbo.
      router.replace(appDeFaena ?? '/m/romeral')
      return
    }
    // Un técnico de mantención del taller de Coquimbo sí usa el panel web; el
    // de una faena con app de terreno, no. Por eso la condición es la faena y
    // no el rol.
    if (perfil?.rol === 'tecnico_mantenimiento' && appDeFaena) {
      router.replace(appDeFaena)
      return
    }
    if (esSupervisorCalamaSolo() && !pathname.startsWith('/dashboard/operacion-calama')) {
      router.replace('/dashboard/operacion-calama')
    }
  }, [loading, pathname, esOperadorCalamaSolo, esSupervisorCalamaSolo, esOperadorTallerSolo,
      esOperadorCombustibleSolo, appDeFaena, perfil?.rol, router])

  if (loading) {
    return (
      <div className="flex h-screen items-center justify-center">
        <Spinner size="lg" className="text-gray-400" />
      </div>
    )
  }

  // Mientras se ejecuta el redirect, no rendereamos children prohibidos.
  if (esOperadorTallerSolo() || esOperadorCombustibleSolo()) {
    return (
      <div className="flex h-screen items-center justify-center">
        <Spinner size="lg" className="text-gray-400" />
      </div>
    )
  }
  if (esOperadorCalamaSolo()) {
    return (
      <div className="flex h-screen items-center justify-center">
        <Spinner size="lg" className="text-gray-400" />
      </div>
    )
  }
  if (esSupervisorCalamaSolo() && !pathname.startsWith('/dashboard/operacion-calama')) {
    return (
      <div className="flex h-screen items-center justify-center">
        <Spinner size="lg" className="text-gray-400" />
      </div>
    )
  }

  return <AppShell>{children}</AppShell>
}
