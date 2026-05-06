'use client'

import { useEffect } from 'react'
import { useRouter, usePathname } from 'next/navigation'
import AppShell from '@/components/layout/app-shell'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { usePermissions } from '@/hooks/use-permissions'
import { Spinner } from '@/components/ui/spinner'

export default function DashboardLayout({
  children,
}: {
  children: React.ReactNode
}) {
  const { loading } = useRequireAuth()
  const { esOperadorCalamaSolo, esSupervisorCalamaSolo } = usePermissions()
  const router = useRouter()
  const pathname = usePathname()

  // Guards de ruta:
  //  - OOCC: cualquier /dashboard/* → /m/calama.
  //  - Supervisor Calama: cualquier /dashboard/* fuera de /dashboard/operacion-calama → /dashboard/operacion-calama.
  useEffect(() => {
    if (loading) return
    if (esOperadorCalamaSolo()) {
      router.replace('/m/calama')
      return
    }
    if (esSupervisorCalamaSolo() && !pathname.startsWith('/dashboard/operacion-calama')) {
      router.replace('/dashboard/operacion-calama')
    }
  }, [loading, pathname, esOperadorCalamaSolo, esSupervisorCalamaSolo, router])

  if (loading) {
    return (
      <div className="flex h-screen items-center justify-center">
        <Spinner size="lg" className="text-gray-400" />
      </div>
    )
  }

  // Mientras se ejecuta el redirect, no rendereamos children prohibidos.
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
