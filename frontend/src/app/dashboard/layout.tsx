'use client'

import AppShell from '@/components/layout/app-shell'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { Spinner } from '@/components/ui/spinner'

export default function DashboardLayout({
  children,
}: {
  children: React.ReactNode
}) {
  const { loading } = useRequireAuth()

  if (loading) {
    return (
      <div className="flex h-screen items-center justify-center">
        <Spinner size="lg" className="text-gray-400" />
      </div>
    )
  }

  return <AppShell>{children}</AppShell>
}
