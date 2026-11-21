'use client'

import { useRequireAuth } from '@/hooks/use-require-auth'
import { Spinner } from '@/components/ui/spinner'
import { VolverAlPanel } from '@/components/layout/volver-al-panel'
import { GuardFaenaMovil } from '@/components/layout/guard-faena-movil'
import { CalamaAlDia } from '@/components/calama-mobile/calama-al-dia'

export default function MobileCalamaLayout({
  children,
}: {
  children: React.ReactNode
}) {
  const { loading } = useRequireAuth()

  if (loading) {
    return (
      <div className="flex h-screen items-center justify-center bg-white">
        <Spinner size="lg" className="text-amber-600" />
      </div>
    )
  }

  return (
    <div className="min-h-screen bg-gray-50">
      <div className="mx-auto max-w-md sm:max-w-lg pb-24">
        {children}
      </div>
      <VolverAlPanel />
      {/* [MIG714] quien está acotado a su faena no entra a otras apps */}
      <GuardFaenaMovil />
      {/* [21-11-2026] Baja jornadas y sube lo pendiente solo, con señal. */}
      <CalamaAlDia />
    </div>
  )
}
