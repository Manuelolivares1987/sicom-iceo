'use client'

import { useMemo } from 'react'
import Image from 'next/image'
import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { useAuth } from '@/contexts/auth-context'
import { usePermissions, type Module, type ExtendedModule } from '@/hooks/use-permissions'
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
  ClipboardCheck,
  FileSpreadsheet,
  Eye,
  Settings,
  LogOut,
  ChevronLeft,
  ChevronRight,
  Truck,
  Timer,
  HardHat,
  Briefcase,
  CalendarClock,
  Activity,
  Layers,
  QrCode,
  AlertTriangle,
  Scale,
} from 'lucide-react'
import { cn } from '@/lib/utils'

type NavItem = {
  label: string
  href: string
  icon: any
  module?: Module
  extendedModule?: ExtendedModule
  badge?: string                  // 'Legacy' | 'Nuevo' | etc.
  tooltip?: string                // texto descriptivo opcional
}

type NavSubsection = {
  label: string                   // subheader pequeno dentro del grupo
  items: NavItem[]
}

type NavGroup = {
  label?: string
  items?: NavItem[]               // grupo flat (compatibilidad)
  subsections?: NavSubsection[]   // grupo con sub-secciones
}

// Grupos lógicos en la sidebar. Separador visual entre cada grupo.
const navGroups: NavGroup[] = [
  // Inicio
  {
    items: [
      { label: 'Dashboard', href: '/dashboard', icon: LayoutDashboard },
      { label: 'Reporte Diario', href: '/dashboard/reporte-diario', icon: CalendarClock, module: 'reporte_diario' },
    ],
  },
  // Trabajo diario
  {
    label: 'Operación',
    items: [
      { label: 'Mis OTs', href: '/dashboard/mis-ots', icon: ClipboardCheck, module: 'ordenes_trabajo' as Module },
      { label: 'Órdenes de Trabajo', href: '/dashboard/ordenes-trabajo', icon: ClipboardList, module: 'ordenes_trabajo' },
      { label: 'Mantenimiento', href: '/dashboard/mantenimiento', icon: Wrench, module: 'mantenimiento' },
    ],
  },
  // Operación Calama (planificación + ejecución para faenas Calama)
  {
    label: 'Operación Calama',
    items: [
      { label: 'Panel Calama',     href: '/dashboard/operacion-calama',                 icon: Activity,        extendedModule: 'operacion_calama' },
      { label: 'Plan semanal',     href: '/dashboard/operacion-calama/plan-semanal',    icon: CalendarClock,   extendedModule: 'operacion_calama' },
      { label: 'Mis OTs Calama',   href: '/dashboard/operacion-calama/mis-ots',         icon: ClipboardCheck,  extendedModule: 'operacion_calama' },
      { label: 'Vista movil',      href: '/m/calama',                                   icon: ClipboardCheck,  extendedModule: 'operacion_calama' },
      { label: 'Órdenes Calama',   href: '/dashboard/operacion-calama/ots',             icon: ClipboardList,   extendedModule: 'operacion_calama' },
      { label: 'Planificaciones',  href: '/dashboard/operacion-calama/planificaciones', icon: Layers,          extendedModule: 'operacion_calama' },
      { label: 'Importar Excel',   href: '/dashboard/operacion-calama/importar',        icon: FileSpreadsheet, extendedModule: 'operacion_calama' },
      { label: 'Reportes',         href: '/dashboard/operacion-calama/reportes',        icon: BarChart3,       extendedModule: 'operacion_calama' },
      { label: 'Pruebas terreno',  href: '/dashboard/operacion-calama/pruebas',         icon: Eye,             extendedModule: 'operacion_calama' },
      { label: 'Aceptaciones',     href: '/dashboard/operacion-calama/aceptaciones',    icon: ClipboardCheck,  extendedModule: 'operacion_calama' },
    ],
  },
  // Mantención QR (checklist preoperacional de equipos / flota Pillado)
  {
    label: 'Mantención QR',
    items: [
      { label: 'Mantención',         href: '/dashboard/mantencion',         icon: Wrench,        extendedModule: 'mantencion_qr' },
      { label: 'Alertas tempranas',  href: '/dashboard/mantencion/alertas', icon: AlertTriangle, extendedModule: 'mantencion_qr' },
      { label: 'Equipos / QR',       href: '/dashboard/activos',            icon: QrCode,        module: 'activos' },
      { label: 'Plantillas QR',      href: '/dashboard/admin/checklist-templates', icon: ClipboardCheck, module: 'admin' },
    ],
  },
  // Flota
  {
    label: 'Flota',
    items: [
      { label: 'Flota', href: '/dashboard/flota', icon: Truck, module: 'flota' },
      { label: 'Fiabilidad', href: '/dashboard/fiabilidad', icon: Activity, module: 'flota' },
      { label: 'Informes Recepción', href: '/dashboard/flota/recepcion', icon: FileText, module: 'flota' },
      { label: 'Jornada', href: '/dashboard/flota/jornada', icon: Timer, module: 'flota' },
      { label: 'Activos', href: '/dashboard/activos', icon: Cog, module: 'activos' },
    ],
  },
  // Negocio
  {
    label: 'Negocio',
    items: [
      { label: 'Contratos', href: '/dashboard/contratos', icon: FileText, module: 'contratos' },
      { label: 'Comercial', href: '/dashboard/comercial', icon: Briefcase, module: 'comercial' },
    ],
  },
  // Bodega / Insumos (proceso: OC -> recepcion FIFO -> salida con CECO)
  {
    label: 'Bodega / Insumos',
    subsections: [
      {
        label: 'Panel',
        items: [
          { label: 'Panel Bodega',          href: '/dashboard/inventario',                icon: Package,         extendedModule: 'bodega',
            tooltip: 'Stock por bodega + valorización + alertas' },
          { label: 'Abastecimiento',        href: '/dashboard/abastecimiento',            icon: Briefcase,       module: 'abastecimiento',
            tooltip: 'Vista global abastecimiento' },
        ],
      },
      {
        label: 'Ingresos',
        items: [
          { label: 'Órdenes de Compra',     href: '/dashboard/abastecimiento/oc',         icon: FileText,        module: 'inventario',
            tooltip: 'Listado OCs internas y externas' },
          { label: 'Importar OC',           href: '/dashboard/abastecimiento/oc/importar', icon: FileSpreadsheet, module: 'inventario',
            tooltip: 'Cargar PDF de OC externa (texto-first)' },
          { label: 'Recepcionar OC',        href: '/dashboard/abastecimiento/oc',         icon: ClipboardCheck,  module: 'inventario',
            tooltip: 'Abre el listado de OCs — desde el detalle recepcionás stock o servicios' },
        ],
      },
      {
        label: 'Egresos',
        items: [
          { label: 'Salida de insumos a OT', href: '/dashboard/inventario/salida-ot/nueva', icon: Truck,         module: 'inventario',
            tooltip: 'FIFO + CECO obligatorio + OT' },
          { label: 'Despachos OT',          href: '/dashboard/abastecimiento/despachos',  icon: ClipboardCheck,  module: 'inventario',
            tooltip: 'Despachos directos a OT' },
        ],
      },
      {
        label: 'Control',
        items: [
          { label: 'Reconciliación Stock/FIFO', href: '/dashboard/inventario/reconciliacion', icon: Scale,       module: 'inventario',
            tooltip: 'Cuadre stock legacy vs capas FIFO' },
          { label: 'Kardex / Capas FIFO',   href: '/dashboard/inventario/reportes',       icon: Layers,          module: 'inventario',
            tooltip: 'Tab Kardex dentro de Reportes' },
          { label: 'Pistola Scanner',       href: '/dashboard/inventario/scanner',        icon: BarChart3,       module: 'inventario' },
          { label: 'Cargar Maestro',        href: '/dashboard/inventario/cargar-maestro', icon: FileSpreadsheet, module: 'inventario' },
        ],
      },
      {
        label: 'Reportes',
        items: [
          { label: 'Reportes Bodega',       href: '/dashboard/inventario/reportes',       icon: BarChart3,       module: 'inventario',
            tooltip: 'Stock valorizado, costos OT/CECO, kardex, mermas' },
        ],
      },
      {
        label: 'Legacy',
        items: [
          { label: 'Salidas / Conteo',      href: '/dashboard/inventario/salida',         icon: ClipboardCheck,  module: 'inventario',
            badge: 'Legacy',
            tooltip: 'Uso solo autorizado. Para nuevas salidas usar Salida de insumos a OT.' },
        ],
      },
    ],
  },
  // Combustible (proceso: ingreso CPP -> salida / despacho con sellos)
  {
    label: 'Combustible',
    subsections: [
      {
        label: 'Panel',
        items: [
          { label: 'Panel Combustible',     href: '/dashboard/combustible',               icon: Fuel,            module: 'inventario',
            tooltip: 'Stock valorizado por CPP móvil' },
        ],
      },
      {
        label: 'Ingresos',
        items: [
          { label: 'Ingreso combustible',   href: '/dashboard/combustible/ingreso',       icon: Fuel,            module: 'inventario',
            tooltip: 'Ingreso valorizado con CPP móvil' },
        ],
      },
      {
        label: 'Egresos',
        items: [
          { label: 'Salida combustible',    href: '/dashboard/combustible/salida',        icon: Fuel,            module: 'inventario',
            tooltip: 'Salida al CPP vigente con destino (equipo/OT/CECO/faena/...)' },
          { label: 'Despacho con sellos',   href: '/dashboard/combustible/despacho',      icon: ShieldCheck,     module: 'inventario',
            tooltip: 'Salida valorizada + sellos antifraude (inicial y final)' },
        ],
      },
      {
        label: 'Control',
        items: [
          { label: 'Control kardex vs varillaje', href: '/dashboard/combustible/control', icon: Gauge,           module: 'inventario',
            tooltip: 'Estado por estanque: teórico vs físico vs último kardex' },
        ],
      },
      {
        label: 'Legacy',
        items: [
          { label: 'Combustible (legacy)',  href: '/dashboard/inventario/combustible',    icon: Fuel,            module: 'inventario',
            badge: 'Legacy',
            tooltip: 'Flujo legacy sin CPP móvil. Para nuevos movimientos usar Panel Combustible.' },
        ],
      },
    ],
  },
  // Compliance
  {
    label: 'Compliance',
    items: [
      { label: 'Prevención', href: '/dashboard/prevencion', icon: HardHat, module: 'prevencion' },
      { label: 'Cumplimiento', href: '/dashboard/cumplimiento', icon: ShieldCheck, module: 'cumplimiento' },
    ],
  },
  // KPIs
  {
    label: 'Indicadores',
    items: [
      { label: 'ICEO', href: '/dashboard/iceo', icon: Gauge, module: 'iceo' },
      { label: 'Reportes', href: '/dashboard/reportes', icon: FileSpreadsheet, module: 'reportes' },
    ],
  },
  // Admin
  {
    label: 'Administración',
    items: [
      { label: 'Auditoría', href: '/dashboard/auditoria', icon: Eye, module: 'auditoria' },
      { label: 'Administración', href: '/dashboard/admin', icon: Settings, module: 'admin' },
      { label: 'GPS', href: '/dashboard/admin/gps', icon: Truck, module: 'admin' },
    ],
  },
]

// Flat list para filtrado por permisos y retrocompatibilidad interna
const navItems: NavItem[] = navGroups.flatMap((g) => [
  ...(g.items ?? []),
  ...(g.subsections ?? []).flatMap((s) => s.items),
])

interface SidebarProps {
  collapsed: boolean
  onToggle: () => void
  onClose?: () => void
}

export default function Sidebar({ collapsed, onToggle, onClose }: SidebarProps) {
  const pathname = usePathname()
  const { perfil, signOut } = useAuth()
  const { canView, canViewExtended, esOperadorCalamaSolo, esSupervisorCalamaSolo } = usePermissions()
  const operadorCalamaSolo = esOperadorCalamaSolo()
  const supervisorCalamaSolo = esSupervisorCalamaSolo()

  // Filtrado por permisos se hace dentro del render por grupo.
  // navItems se mantiene exportado por compatibilidad interna.
  void navItems

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

      {/* Navigation agrupada */}
      <nav className="flex-1 space-y-3 overflow-y-auto px-2 py-3">
        {navGroups.map((group, idx) => {
          // Restringidos a Calama: solo mostrar grupo Operacion Calama.
          if ((operadorCalamaSolo || supervisorCalamaSolo) && group.label !== 'Operación Calama') return null

          // Filtro de visibilidad: aplica las mismas reglas de permisos a items
          // planos y a items dentro de subsections.
          const filterItem = (item: NavItem) => {
            if (operadorCalamaSolo) return item.href === '/m/calama'
            if (supervisorCalamaSolo) {
              return item.extendedModule === 'operacion_calama' && item.href !== '/m/calama'
            }
            if (item.module) return canView(item.module)
            if (item.extendedModule) return canViewExtended(item.extendedModule)
            return true
          }

          const itemsVisibles = (group.items ?? []).filter(filterItem)
          const subsectionsVisibles = (group.subsections ?? [])
            .map((s) => ({ label: s.label, items: s.items.filter(filterItem) }))
            .filter((s) => s.items.length > 0)

          if (itemsVisibles.length === 0 && subsectionsVisibles.length === 0) return null

          return (
            <div key={idx}>
              {!collapsed && group.label && (
                <div className="mb-1 px-3 text-[10px] font-semibold uppercase tracking-wider text-gray-500">
                  {group.label}
                </div>
              )}
              {/* Items planos del grupo (compat) */}
              {itemsVisibles.length > 0 && (
                <div className="space-y-0.5">
                  {itemsVisibles.map((item) => (
                    <SidebarLink
                      key={item.href}
                      item={item}
                      active={isActive(item.href)}
                      collapsed={collapsed}
                      onClick={onClose}
                    />
                  ))}
                </div>
              )}
              {/* Subsections con subheaders pequenos */}
              {subsectionsVisibles.map((sub, si) => (
                <div key={si} className={si > 0 || itemsVisibles.length > 0 ? 'mt-2' : ''}>
                  {!collapsed && (
                    <div className="mb-0.5 px-3 text-[9px] font-medium uppercase tracking-wider text-gray-600/80">
                      {sub.label}
                    </div>
                  )}
                  <div className="space-y-0.5">
                    {sub.items.map((item) => (
                      <SidebarLink
                        key={item.href + ':' + item.label}
                        item={item}
                        active={isActive(item.href)}
                        collapsed={collapsed}
                        onClick={onClose}
                      />
                    ))}
                  </div>
                </div>
              ))}
            </div>
          )
        })}
      </nav>

      {/* (SidebarLink se define al final del archivo) */}
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

// ── SidebarLink: render unificado de un item con badge opcional ─────────────

function SidebarLink({
  item, active, collapsed, onClick,
}: {
  item: NavItem
  active: boolean
  collapsed: boolean
  onClick?: () => void
}) {
  const Icon = item.icon
  const title = item.tooltip ?? item.label
  return (
    <Link
      href={item.href}
      onClick={onClick}
      title={collapsed ? item.label : title}
      className={cn(
        'flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium transition-colors',
        active
          ? 'bg-pillado-green-500 text-white'
          : item.badge === 'Legacy'
            ? 'text-gray-400 hover:bg-white/10 hover:text-white'
            : 'text-gray-300 hover:bg-white/10 hover:text-white',
      )}
    >
      <Icon className="h-5 w-5 shrink-0" />
      {!collapsed && (
        <>
          <span className="truncate flex-1">{item.label}</span>
          {item.badge && (
            <span className={cn(
              'rounded px-1.5 py-0.5 text-[9px] font-semibold uppercase tracking-wider',
              item.badge === 'Legacy'
                ? 'bg-gray-700 text-gray-300'
                : 'bg-pillado-green-500/40 text-white',
            )}>
              {item.badge}
            </span>
          )}
        </>
      )}
    </Link>
  )
}
