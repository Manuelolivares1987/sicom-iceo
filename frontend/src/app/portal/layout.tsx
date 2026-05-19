'use client'

import Link from 'next/link'
import { usePathname, useRouter } from 'next/navigation'
import { Fuel, LogOut, BarChart3, List } from 'lucide-react'
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

  const enDashboard    = pathname?.includes('/portal/dashboard')
  const enTransacciones = pathname?.includes('/portal/transacciones')

  return (
    <div className="min-h-screen bg-gray-50">
      {!esLogin && (
        <header className="border-b bg-white shadow-sm">
          <div className="mx-auto flex max-w-7xl items-center justify-between px-4 py-3">
            <Link href="/portal/dashboard" className="flex items-center gap-2 text-blue-700">
              <Fuel className="h-6 w-6" />
              <div>
                <div className="text-base font-bold leading-tight">Portal Cliente — Combustible</div>
                <div className="text-[10px] text-gray-500">Pillado</div>
              </div>
            </Link>
            <nav className="hidden gap-1 sm:flex">
              <Link href="/portal/dashboard">
                <Button variant={enDashboard ? 'primary' : 'ghost'} size="sm" className="gap-1">
                  <BarChart3 className="h-4 w-4" /> Dashboard
                </Button>
              </Link>
              <Link href="/portal/transacciones">
                <Button variant={enTransacciones ? 'primary' : 'ghost'} size="sm" className="gap-1">
                  <List className="h-4 w-4" /> Transacciones
                </Button>
              </Link>
            </nav>
            <div className="flex items-center gap-3">
              {email && <span className="hidden text-xs text-gray-600 sm:inline">{email}</span>}
              <Button variant="outline" size="sm" onClick={handleLogout} className="gap-1">
                <LogOut className="h-4 w-4" /> Salir
              </Button>
            </div>
          </div>
          {/* Nav móvil */}
          <nav className="flex gap-1 border-t px-4 py-2 sm:hidden">
            <Link href="/portal/dashboard" className="flex-1">
              <Button variant={enDashboard ? 'primary' : 'ghost'} size="sm" className="w-full gap-1">
                <BarChart3 className="h-4 w-4" /> Dashboard
              </Button>
            </Link>
            <Link href="/portal/transacciones" className="flex-1">
              <Button variant={enTransacciones ? 'primary' : 'ghost'} size="sm" className="w-full gap-1">
                <List className="h-4 w-4" /> Transacciones
              </Button>
            </Link>
          </nav>
        </header>
      )}
      <main className="mx-auto max-w-7xl">{children}</main>
    </div>
  )
}
