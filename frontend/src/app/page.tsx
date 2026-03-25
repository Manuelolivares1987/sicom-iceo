'use client'

import { useEffect } from 'react'
import { useRouter } from 'next/navigation'
import { useAuth } from '@/contexts/auth-context'
import { Spinner } from '@/components/ui/spinner'

export default function Home() {
  const { loading, isAuthenticated } = useAuth()
  const router = useRouter()

  useEffect(() => {
    if (!loading) {
      if (isAuthenticated) {
        router.replace('/dashboard')
      } else {
        router.replace('/login')
      }
    }
  }, [loading, isAuthenticated, router])

  return (
    <div className="flex min-h-screen items-center justify-center">
      <Spinner size="lg" className="text-pillado-green-500" />
    </div>
  )
}
