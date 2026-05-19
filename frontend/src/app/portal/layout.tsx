'use client'

import Link from 'next/link'
import { usePathname, useRouter } from 'next/navigation'
import { Fuel, LogOut } from 'lucide-react'
import { useEffect, useState } from 'react'
import { Button } from '@/components/ui/button'
import { supabase } from '@/lib/supabase'

export default function PortalLayout({ children }: { children: React.ReactNode }) {
  const pathname = usePathname()
  const router   = useRouter()
  const [email, setEmail] = useState<string | null>(null)
  const esLogin = pathname?.endsWith('/portal/login') || pathname?.endsWith('/portal')

  useEffect(() => {
    supabase.auth.getUser().then(({ data }) => setEmail(data.user?.email ?? null))
  }, [])

  const handleLogout = async () => {
    await supabase.auth.signOut()
    router.push('/portal/login')
  }

  return (
    <div className="min-h-screen bg-gray-50">
      {!esLogin && (
        <header className="border-b bg-white shadow-sm">
          <div className="mx-auto flex max-w-7xl items-center justify-between px-4 py-3">
            <Link href="/portal/transacciones" className="flex items-center gap-2 text-blue-700">
              <Fuel className="h-6 w-6" />
              <div>
                <div className="text-base font-bold leading-tight">Portal Cliente — Combustible</div>
                <div className="text-[10px] text-gray-500">Pillado</div>
              </div>
            </Link>
            <div className="flex items-center gap-3">
              {email && <span className="text-xs text-gray-600">{email}</span>}
              <Button variant="outline" size="sm" onClick={handleLogout} className="gap-1">
                <LogOut className="h-4 w-4" /> Salir
              </Button>
            </div>
          </div>
        </header>
      )}
      <main className="mx-auto max-w-7xl">{children}</main>
    </div>
  )
}
