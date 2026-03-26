'use client'

import { useMemo } from 'react'
import Image from 'next/image'
import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { useAuth } from '@/contexts/auth-context'
import {
  LayoutDashboard,
  FileText,
  Cog,
  ClipboardList,
  Wrench,
  Package,
  Fuel,
  ShieldCheck,
  BarChart3,
  Gauge,
  FileSpreadsheet,
  Eye,
  Settings,
  LogOut,
  ChevronLeft,
  ChevronRight,
} from 'lucide-react'
import { cn } from '@/lib/utils'

const navItems = [
  { label: 'Dashboard', href: '/dashboard', icon: LayoutDashboard },
  { label: 'Contratos', href: '/dashboard/contratos', icon: FileText },
  { label: 'Activos', href: '/dashboard/activos', icon: Cog },
  { label: 'Órdenes de Trabajo', href: '/dashboard/ordenes-trabajo', icon: ClipboardList },
  { label: 'Mantenimiento', href: '/dashboard/mantenimiento', icon: Wrench },
  { label: 'Inventario', href: '/dashboard/inventario', icon: Package },
  { label: 'Abastecimiento', href: '/dashboard/abastecimiento', icon: Fuel },
  { label: 'Cumplimiento', href: '/dashboard/cumplimiento', icon: ShieldCheck },
  { label: 'KPI', href: '/dashboard/kpi', icon: BarChart3 },
  { label: 'ICEO', href: '/dashboard/iceo', icon: Gauge },
  { label: 'Reportes', href: '/dashboard/reportes', icon: FileSpreadsheet },
  { label: 'Auditoría', href: '/dashboard/auditoria', icon: Eye },
  { label: 'Administración', href: '/dashboard/admin', icon: Settings },
]

interface SidebarProps {
  collapsed: boolean
  onToggle: () => void
  onClose?: () => void
}

export default function Sidebar({ collapsed, onToggle, onClose }: SidebarProps) {
  const pathname = usePathname()
  const { perfil, signOut } = useAuth()

  const displayName = perfil?.nombre_completo ?? 'Usuario'
  const displayRole = perfil?.cargo ?? perfil?.rol ?? ''
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

  const isActive = (href: string) => {
    if (href === '/dashboard') return pathname === '/dashboard'
    return pathname.startsWith(href)
  }

  return (
    <aside
      className={cn(
        'flex h-full flex-col bg-gray-900 text-white transition-all duration-300',
        collapsed ? 'w-[72px]' : 'w-64'
      )}
    >
      {/* Logo area */}
      <div className="flex h-16 items-center gap-3 border-b border-white/10 px-4">
        <Image
          src="/images/logo_empresa_2.png"
          alt="Logo"
          width={32}
          height={32}
          className="h-8 w-8 shrink-0 object-contain"
        />
        {!collapsed && (
          <span className="truncate text-sm font-bold tracking-wide">
            SICOM-ICEO
          </span>
        )}
        {/* Collapse toggle — visible only on desktop */}
        <button
          onClick={onToggle}
          className="ml-auto hidden rounded-md p-1 text-gray-400 hover:bg-white/10 hover:text-white lg:inline-flex"
          aria-label={collapsed ? 'Expandir menú' : 'Colapsar menú'}
        >
          {collapsed ? (
            <ChevronRight className="h-4 w-4" />
          ) : (
            <ChevronLeft className="h-4 w-4" />
          )}
        </button>
      </div>

      {/* Navigation */}
      <nav className="flex-1 space-y-0.5 overflow-y-auto px-2 py-3">
        {navItems.map((item) => {
          const Icon = item.icon
          const active = isActive(item.href)
          return (
            <Link
              key={item.href}
              href={item.href}
              onClick={onClose}
              title={collapsed ? item.label : undefined}
              className={cn(
                'flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm font-medium transition-colors',
                active
                  ? 'bg-pillado-green-500 text-white'
                  : 'text-gray-300 hover:bg-white/10 hover:text-white'
              )}
            >
              <Icon className="h-5 w-5 shrink-0" />
              {!collapsed && <span className="truncate">{item.label}</span>}
            </Link>
          )
        })}
      </nav>

      {/* User area */}
      <div className="border-t border-white/10 p-3">
        <div className="flex items-center gap-3">
          <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-pillado-green-500 text-sm font-bold">
            {initials}
          </div>
          {!collapsed && (
            <div className="min-w-0 flex-1">
              <p className="truncate text-sm font-medium">{displayName}</p>
              <p className="truncate text-xs text-gray-400">
                {displayRole}
              </p>
            </div>
          )}
          {!collapsed && (
            <button
              onClick={() => signOut()}
              className="rounded-md p-1.5 text-gray-400 hover:bg-white/10 hover:text-white"
              title="Cerrar sesión"
            >
              <LogOut className="h-4 w-4" />
            </button>
          )}
        </div>
      </div>
    </aside>
  )
}
