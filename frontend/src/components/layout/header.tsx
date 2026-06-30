'use client'

import { useMemo, useState } from 'react'
import Link from 'next/link'
import { usePathname, useRouter } from 'next/navigation'
import {
  Menu,
  Search,
  Bell,
  ChevronRight,
  LogOut,
  User,
} from 'lucide-react'
import { cn } from '@/lib/utils'
import { useAuth } from '@/contexts/auth-context'
import { useConteoNoLeidas, useAlertasNoLeidas, useMarcarLeida } from '@/hooks/use-alertas'

// Adónde lleva una alerta según su entidad.
function rutaAlerta(entidadTipo: string | null): string {
  switch (entidadTipo) {
    case 'no_conformidad': return '/dashboard/mantenimiento/no-conformidades'
    case 'activo':         return '/dashboard/flota/gps'
    case 'ot':             return '/dashboard/ordenes-trabajo'
    default:               return '/dashboard'
  }
}

const breadcrumbMap: Record<string, string> = {
  '/dashboard': 'Dashboard',
  '/dashboard/contratos': 'Contratos',
  '/dashboard/activos': 'Activos',
  '/dashboard/ordenes-trabajo': 'Órdenes de Trabajo',
  '/dashboard/mantenimiento': 'Mantenimiento',
  '/dashboard/inventario': 'Inventario',
  '/dashboard/abastecimiento': 'Abastecimiento',
  '/dashboard/cumplimiento': 'Cumplimiento',
  '/dashboard/kpi': 'KPI',
  '/dashboard/iceo': 'ICEO',
  '/dashboard/reportes': 'Reportes',
  '/dashboard/auditoria': 'Auditoría',
  '/dashboard/admin': 'Administración',
}

interface HeaderProps {
  onMenuToggle: () => void
}

export default function Header({ onMenuToggle }: HeaderProps) {
  const pathname = usePathname()
  const router = useRouter()
  const [showUserMenu, setShowUserMenu] = useState(false)
  const [showNotif, setShowNotif] = useState(false)
  const { perfil, signOut } = useAuth()
  const { data: unreadCount = 0 } = useConteoNoLeidas()
  const { data: alertasData } = useAlertasNoLeidas()
  const alertas = alertasData ?? []
  const marcarLeida = useMarcarLeida()

  const sevDot: Record<string, string> = {
    critical: 'bg-red-500', warning: 'bg-amber-500', info: 'bg-blue-500',
  }

  function abrirAlerta(id: string, entidadTipo: string | null) {
    marcarLeida.mutate(id)
    setShowNotif(false)
    router.push(rutaAlerta(entidadTipo))
  }

  const displayName = perfil?.nombre_completo ?? 'Usuario'
  const displayEmail = perfil?.email ?? ''
  const initials = useMemo(
    () =>
      displayName
        .split(' ')
        .map((w) => w[0])
        .join('')
        .slice(0, 2)
        .toUpperCase(),
    [displayName]
  )

  const currentLabel = breadcrumbMap[pathname] || 'Dashboard'

  return (
    <header className="flex h-16 shrink-0 items-center gap-4 border-b border-gray-200 bg-white px-4 shadow-sm sm:px-6">
      {/* Hamburger — mobile */}
      <button
        onClick={onMenuToggle}
        className="rounded-md p-2 text-gray-500 hover:bg-gray-100 hover:text-gray-700 lg:hidden"
        aria-label="Abrir menú"
      >
        <Menu className="h-5 w-5" />
      </button>

      {/* Breadcrumbs */}
      <nav className="hidden items-center gap-1.5 text-sm text-gray-500 sm:flex">
        <span className="font-medium text-gray-400">SICOM-ICEO</span>
        <ChevronRight className="h-3.5 w-3.5 text-gray-300" />
        <span className="font-medium text-gray-900">{currentLabel}</span>
      </nav>

      {/* Spacer */}
      <div className="flex-1" />

      {/* Search */}
      <div className="hidden max-w-xs flex-1 md:block">
        <div className="relative">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400" />
          <input
            type="text"
            placeholder="Buscar equipos, OTs, documentos..."
            className="w-full rounded-lg border border-gray-200 bg-gray-50 py-2 pl-10 pr-4 text-sm text-gray-700 placeholder-gray-400 transition-colors focus:border-pillado-green-400 focus:bg-white focus:outline-none focus:ring-2 focus:ring-pillado-green-500/20"
          />
        </div>
      </div>

      {/* Notifications */}
      <div className="relative">
        <button
          onClick={() => setShowNotif((v) => !v)}
          className="relative rounded-md p-2 text-gray-500 hover:bg-gray-100 hover:text-gray-700"
          aria-label="Notificaciones"
        >
          <Bell className="h-5 w-5" />
          {unreadCount > 0 && (
            <span className="absolute -right-0.5 -top-0.5 flex h-5 w-5 items-center justify-center rounded-full bg-pillado-orange-500 text-[10px] font-bold text-white">
              {unreadCount}
            </span>
          )}
        </button>

        {showNotif && (
          <>
            <div className="fixed inset-0 z-40" onClick={() => setShowNotif(false)} />
            <div className="absolute right-0 top-12 z-50 w-80 rounded-lg border border-gray-200 bg-white shadow-lg">
              <div className="flex items-center justify-between border-b border-gray-100 px-4 py-2.5">
                <p className="text-sm font-semibold text-gray-900">Notificaciones</p>
                <span className="text-xs text-gray-400">{unreadCount} sin leer</span>
              </div>
              <div className="max-h-96 overflow-y-auto">
                {alertas.length === 0 ? (
                  <p className="px-4 py-6 text-center text-sm text-gray-400">Sin notificaciones nuevas.</p>
                ) : (
                  alertas.slice(0, 20).map((a) => (
                    <button
                      key={a.id}
                      onClick={() => abrirAlerta(a.id, a.entidad_tipo)}
                      className="flex w-full items-start gap-2 border-b border-gray-50 px-4 py-2.5 text-left hover:bg-gray-50"
                    >
                      <span className={cn('mt-1.5 h-2 w-2 shrink-0 rounded-full', sevDot[a.severidad] ?? 'bg-gray-400')} />
                      <span className="flex-1">
                        <span className="block text-sm font-medium text-gray-800">{a.titulo}</span>
                        {a.mensaje && <span className="block text-xs text-gray-500 line-clamp-2">{a.mensaje}</span>}
                      </span>
                    </button>
                  ))
                )}
              </div>
            </div>
          </>
        )}
      </div>

      {/* User avatar dropdown */}
      <div className="relative">
        <button
          onClick={() => setShowUserMenu(!showUserMenu)}
          className="flex h-9 w-9 items-center justify-center rounded-full bg-pillado-green-500 text-sm font-bold text-white hover:bg-pillado-green-600"
        >
          {initials}
        </button>

        {showUserMenu && (
          <>
            <div
              className="fixed inset-0 z-40"
              onClick={() => setShowUserMenu(false)}
            />
            <div className="absolute right-0 top-12 z-50 w-56 rounded-lg border border-gray-200 bg-white py-1 shadow-lg">
              <div className="border-b border-gray-100 px-4 py-3">
                <p className="text-sm font-medium text-gray-900">{displayName}</p>
                <p className="text-xs text-gray-500">{displayEmail}</p>
              </div>
              <Link
                href="/dashboard/admin"
                onClick={() => setShowUserMenu(false)}
                className="flex w-full items-center gap-2 px-4 py-2.5 text-sm text-gray-700 hover:bg-gray-50"
              >
                <User className="h-4 w-4" />
                Mi Perfil
              </Link>
              <button
                onClick={() => { setShowUserMenu(false); signOut() }}
                className="flex w-full items-center gap-2 px-4 py-2.5 text-sm text-red-600 hover:bg-red-50"
              >
                <LogOut className="h-4 w-4" />
                Cerrar Sesión
              </button>
            </div>
          </>
        )}
      </div>
    </header>
  )
}
