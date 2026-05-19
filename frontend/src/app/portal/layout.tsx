'use client'

import Link from 'next/link'
import Image from 'next/image'
import { usePathname, useRouter } from 'next/navigation'
import { LogOut, BarChart3, List, Mail, Phone, Globe } from 'lucide-react'
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

  const enDashboard     = pathname?.includes('/portal/dashboard')
  const enTransacciones = pathname?.includes('/portal/transacciones')

  if (esLogin) {
    return <div className="min-h-screen">{children}</div>
  }

  return (
    <div className="flex min-h-screen flex-col bg-pillado-green-50/30">
      {/* Header institucional */}
      <header className="border-b-4 border-pillado-orange-500 bg-white shadow-sm">
        <div className="bg-gradient-to-r from-pillado-green-700 via-pillado-green-600 to-pillado-green-500">
          <div className="mx-auto flex max-w-7xl items-center justify-between px-4 py-2">
            <div className="text-xs text-white/90">
              <span className="hidden sm:inline">Portal Cliente · Gestión de Combustible</span>
            </div>
            <div className="flex items-center gap-3 text-xs text-white/90">
              {email && <span className="hidden sm:inline">{email}</span>}
              <button onClick={handleLogout}
                      className="flex items-center gap-1 rounded bg-white/10 px-2 py-1 hover:bg-white/20 transition-colors">
                <LogOut className="h-3.5 w-3.5" /> Salir
              </button>
            </div>
          </div>
        </div>
        <div className="mx-auto flex max-w-7xl items-center justify-between gap-4 px-4 py-3">
          <Link href="/portal/dashboard" className="flex items-center gap-3">
            <Image src="/images/logo.jpg" alt="Pillado" width={48} height={48}
                   className="rounded-lg shadow-sm" priority />
            <div>
              <div className="text-lg font-bold tracking-tight text-pillado-green-700">PILLADO</div>
              <div className="text-[10px] uppercase tracking-wider text-gray-500">Servicios Mineros · Chile</div>
            </div>
          </Link>
          <nav className="hidden gap-1 sm:flex">
            <Link href="/portal/dashboard">
              <button className={`flex items-center gap-1.5 rounded-md px-4 py-2 text-sm font-medium transition-colors ${
                enDashboard
                  ? 'bg-pillado-green-500 text-white shadow-md'
                  : 'text-gray-700 hover:bg-pillado-green-50 hover:text-pillado-green-700'
              }`}>
                <BarChart3 className="h-4 w-4" /> Dashboard
              </button>
            </Link>
            <Link href="/portal/transacciones">
              <button className={`flex items-center gap-1.5 rounded-md px-4 py-2 text-sm font-medium transition-colors ${
                enTransacciones
                  ? 'bg-pillado-green-500 text-white shadow-md'
                  : 'text-gray-700 hover:bg-pillado-green-50 hover:text-pillado-green-700'
              }`}>
                <List className="h-4 w-4" /> Transacciones
              </button>
            </Link>
          </nav>
        </div>
        {/* Nav móvil */}
        <nav className="flex gap-1 border-t border-pillado-green-100 bg-pillado-green-50/40 px-3 py-2 sm:hidden">
          <Link href="/portal/dashboard" className="flex-1">
            <button className={`flex w-full items-center justify-center gap-1.5 rounded-md px-2 py-1.5 text-xs font-semibold transition-colors ${
              enDashboard ? 'bg-pillado-green-500 text-white' : 'text-gray-700 bg-white'
            }`}>
              <BarChart3 className="h-4 w-4" /> Dashboard
            </button>
          </Link>
          <Link href="/portal/transacciones" className="flex-1">
            <button className={`flex w-full items-center justify-center gap-1.5 rounded-md px-2 py-1.5 text-xs font-semibold transition-colors ${
              enTransacciones ? 'bg-pillado-green-500 text-white' : 'text-gray-700 bg-white'
            }`}>
              <List className="h-4 w-4" /> Transacciones
            </button>
          </Link>
        </nav>
      </header>

      <main className="mx-auto w-full max-w-7xl flex-1">{children}</main>

      {/* Footer institucional */}
      <footer className="mt-8 border-t bg-white">
        <div className="mx-auto flex max-w-7xl flex-col gap-3 px-4 py-5 sm:flex-row sm:items-center sm:justify-between">
          <div className="flex items-center gap-3">
            <Image src="/images/logo.jpg" alt="Pillado" width={32} height={32} className="rounded" />
            <div className="text-xs">
              <div className="font-bold text-pillado-green-700">Pillado Empresas</div>
              <div className="text-gray-500">Servicios mineros e industriales</div>
            </div>
          </div>
          <div className="flex flex-wrap items-center gap-4 text-[11px] text-gray-500">
            <span className="flex items-center gap-1"><Mail className="h-3 w-3" /> contacto@pillado.cl</span>
            <span className="flex items-center gap-1"><Globe className="h-3 w-3" /> www.pillado.cl</span>
            <span className="flex items-center gap-1"><Phone className="h-3 w-3" /> +56 9 0000 0000</span>
          </div>
          <div className="text-[10px] text-gray-400">
            © {new Date().getFullYear()} Pillado Empresas · Todos los derechos reservados
          </div>
        </div>
      </footer>
    </div>
  )
}
