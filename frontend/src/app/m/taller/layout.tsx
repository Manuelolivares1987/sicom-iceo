'use client'

import { useRequireAuth } from '@/hooks/use-require-auth'
import { Spinner } from '@/components/ui/spinner'

export default function MobileTallerLayout({ children }: { children: React.ReactNode }) {
  const { loading } = useRequireAuth()

  if (loading) {
    return (
      <div className="flex h-screen items-center justify-center bg-white">
        <Spinner size="lg" className="text-orange-600" />
      </div>
    )
  }

  return (
    <div className="min-h-screen bg-gray-50">
      <div className="mx-auto max-w-md sm:max-w-lg pb-24">{children}</div>
    </div>
  )
}
