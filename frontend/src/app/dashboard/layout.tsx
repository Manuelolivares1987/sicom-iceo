'use client'

import { useEffect } from 'react'
import { useRouter } from 'next/navigation'
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
  const { esOperadorCalamaSolo } = usePermissions()
  const router = useRouter()

  // OOCC dedicado a Calama no debe acceder a /dashboard/* — redirigir a app movil.
  useEffect(() => {
    if (loading) return
    if (esOperadorCalamaSolo()) {
      router.replace('/m/calama')
    }
  }, [loading, esOperadorCalamaSolo, router])

  if (loading) {
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

  return <AppShell>{children}</AppShell>
}
