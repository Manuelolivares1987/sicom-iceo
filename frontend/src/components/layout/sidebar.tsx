'use client'

import { useEffect, useMemo, useState } from 'react'
import Image from 'next/image'
import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { useAuth } from '@/contexts/auth-context'
import { usePermissions, type Module, type ExtendedModule } from '@/hooks/use-permissions'
import {
  LayoutDashboard,
  FileText,
  Share2,
  ClipboardList,
  Wrench,
  Package,
  Ticket,
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
  ChevronDown,
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
  Satellite,
  Lightbulb,
  ShoppingCart,
  Building2,
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
      { label: 'Reporte Flota (público)', href: '/reporte-flota', icon: Share2, badge: 'Link' },
    ],
  },
  // Trabajo diario — agrupado en subsecciones para evitar enredo.
  {
    label: 'Operación',
    subsections: [
      {
        label: 'Órdenes de Trabajo',
        items: [
          { label: 'Mis OTs', href: '/dashboard/mis-ots', icon: ClipboardCheck, module: 'ordenes_trabajo' as Module },
          { label: 'Todas las OTs', href: '/dashboard/ordenes-trabajo', icon: ClipboardList, module: 'ordenes_trabajo' },
        ],
      },
      {
        label: 'Taller',
        items: [
          { label: 'Panel Taller', href: '/dashboard/mantenimiento', icon: Wrench, module: 'mantenimiento' },
          { label: 'Plan semanal', href: '/dashboard/mantenimiento/plan-semanal-taller', icon: CalendarClock, module: 'mantenimiento' },
          { label: 'No Conformidades', href: '/dashboard/mantenimiento/no-conformidades', icon: AlertTriangle, module: 'mantenimiento', badge: 'Nuevo' },
          { label: 'Equipos auxiliares', href: '/dashboard/mantenimiento/auxiliares', icon: Layers, module: 'mantenimiento' },
        ],
      },
      {
        label: 'Calidad',
        items: [
          { label: 'Plan semanal calidad', href: '/dashboard/mantenimiento/auditoria-calidad?tab=plan', icon: CalendarClock, module: 'mantenimiento', badge: 'Nuevo' },
          { label: 'Chequeo cruzado', href: '/dashboard/mantenimiento/chequeo-cruzado', icon: ClipboardCheck, module: 'mantenimiento' },
          { label: 'Auditoría de calidad', href: '/dashboard/mantenimiento/auditoria-calidad', icon: ShieldCheck, module: 'mantenimiento' },
        ],
      },
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
  // Contrato ENEX/ESM (Calama): mantención de EESS combustibles/lubricantes.
  {
    label: 'Contrato ENEX (Calama)',
    items: [
      { label: 'Control & KPI', href: '/dashboard/enex', icon: Building2, badge: 'Nuevo',
        tooltip: 'Programa de mantención por instalación y cumplimiento del contrato ENEX (KPI y exposición a multa)' },
      { label: 'Informes (PDF)', href: '/dashboard/enex/informes', icon: FileText, badge: 'Nuevo',
        tooltip: 'Certificados de calibración y OT de mantenimiento generados en terreno — búsqueda por mes, día e instalación' },
      { label: 'Pautas (checklists)', href: '/dashboard/enex/pautas', icon: ClipboardList, badge: 'Nuevo',
        tooltip: 'Checklists de mantención y calibración por tipo de instalación (editables)' },
      { label: 'Terreno (móvil)', href: '/m/enex', icon: ClipboardCheck, badge: 'Nuevo',
        tooltip: 'App del mantenedor: ejecuta la pauta de la instalación programada, con mediciones, fotos y firmas' },
    ],
  },
  // Checklists de estado + Alertas — misma familia: chequeo del equipo -> alerta.
  // Preoperacional (nuestros conductores) y Cliente (semanal) detectan fallas
  // temprano; ambos alimentan "Alertas tempranas".
  {
    label: 'Checklists & Alertas',
    items: [
      { label: 'Checklist preoperacional', href: '/dashboard/mantencion', icon: ClipboardCheck, extendedModule: 'mantencion_qr',
        tooltip: 'Checklist por QR de nuestros conductores, antes de operar el equipo' },
      { label: 'Checklist Cliente (semanal)', href: '/dashboard/flota/checklist-cliente', icon: ClipboardList, module: 'flota',
        tooltip: 'Checklist semanal que ejecuta el cliente del equipo arrendado' },
      { label: 'Alertas tempranas', href: '/dashboard/mantencion/alertas', icon: AlertTriangle, extendedModule: 'mantencion_qr',
        tooltip: 'Fallas detectadas por ambos checklists, antes de que sean graves' },
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
      { label: 'Mapa GPS', href: '/dashboard/flota/mapa', icon: Satellite, module: 'flota', badge: 'Nuevo' },
      { label: 'Sugerencias estado (GPS)', href: '/dashboard/flota/sugerencias', icon: Satellite, module: 'flota', badge: 'Nuevo' },
      { label: 'Check-List Entrega', href: '/dashboard/flota/checklist-salida', icon: ClipboardCheck, module: 'flota', badge: 'V02' },
      { label: 'Estado Flota', href: '/dashboard/flota/estado-flota', icon: ShieldCheck, module: 'flota', badge: 'Nuevo' },
      { label: 'Equipos y Bitácora (QR)', href: '/dashboard/activos', icon: QrCode, module: 'activos',
        tooltip: 'Listado de equipos; entra a uno para ver su QR y la bitácora completa' },
    ],
  },
  // Negocio
  {
    label: 'Negocio',
    items: [
      { label: 'Contratos', href: '/dashboard/contratos', icon: FileText, module: 'contratos' },
      { label: 'Comercial', href: '/dashboard/comercial', icon: Briefcase, module: 'comercial' },
      { label: 'Consolidado Combustible', href: '/dashboard/comercial/combustible-consolidado', icon: Fuel, module: 'comercial', badge: 'Nuevo' },
    ],
  },
  // Bodega — UNA sola entrada. El Panel Bodega centraliza TODAS las acciones
  // (compras, recepciones, salidas, combustible, control, admin) via
  // <QuickActionsGrid> agrupados por seccion. El bodeguero no tiene que
  // navegar entre multiples paneles.
  {
    label: 'Bodega',
    items: [
      { label: 'Panel Bodega', href: '/dashboard/inventario', icon: Package, extendedModule: 'bodega',
        tooltip: 'Stock, compras, salidas, combustible y reportes — todo en un solo panel' },
      { label: 'Pedidos a bodega', href: '/dashboard/bodega/tickets', icon: Ticket, extendedModule: 'bodega', badge: 'Nuevo',
        tooltip: 'Todo el pedido del taller en un lugar: vales por despachar (con fotos), solicitudes de material e historial' },
      { label: 'Seguimiento repuestos', href: '/dashboard/bodega/seguimiento-repuestos', icon: ShoppingCart, extendedModule: 'bodega', badge: 'Nuevo',
        tooltip: 'Repuestos pedidos por el taller sin stock: solicitar la OC (la emite Softland), ver en qué está cada compra y cuándo llega' },
      { label: 'Combustible Franke', href: '/dashboard/combustible/franke', icon: Fuel, extendedModule: 'bodega', badge: 'Nuevo',
        tooltip: 'Camiones petroleros, cargas, trasvasije y cuadre diario — operación Franke' },
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
      { label: 'Perfiles y Roles', href: '/dashboard/admin/perfiles-roles', icon: ShieldCheck, module: 'admin', badge: 'Nuevo' },
      { label: 'Plantillas de checklist (OT)', href: '/dashboard/admin/checklist-templates', icon: ClipboardCheck, module: 'admin' },
      { label: 'GPS', href: '/dashboard/admin/gps', icon: Truck, module: 'admin' },
      { label: 'Geocercas', href: '/dashboard/admin/geocercas', icon: AlertTriangle, module: 'admin', badge: 'Nuevo' },
      { label: 'Portal Cliente', href: '/dashboard/admin/portal-usuarios', icon: Briefcase, module: 'admin', badge: 'Nuevo' },
      { label: 'Sugerencias', href: '/dashboard/admin/sugerencias', icon: Lightbulb, module: 'admin', badge: 'Nuevo' },
    ],
  },
]

// Flat list para filtrado por permisos y retrocompatibilidad interna
const navItems: NavItem[] = navGroups.flatMap((g) => [
  ...(g.items ?? []),
  ...(g.subsections ?? []).flatMap((s) => s.items),
])

// Ámbito de vista por usuario (MIG233): filtra grupos completos del menú.
//  'calama'   → Dashboard + Operación Calama + Contrato ENEX + Flota
//  'coquimbo' → todo menos Operación Calama y Contrato ENEX
const GRUPOS_SOLO_CALAMA = ['Operación Calama', 'Contrato ENEX (Calama)']
const GRUPOS_VISTA_CALAMA = [...GRUPOS_SOLO_CALAMA, 'Flota']

interface SidebarProps {
  collapsed: boolean
  onToggle: () => void
  onClose?: () => void
}

export default function Sidebar({ collapsed, onToggle, onClose }: SidebarProps) {
  const pathname = usePathname()
  const { perfil, signOut } = useAuth()
  const { canView, canViewExtended, esOperadorCalamaSolo, esSupervisorCalamaSolo, esComercialSolo } = usePermissions()
  const operadorCalamaSolo = esOperadorCalamaSolo()
  const supervisorCalamaSolo = esSupervisorCalamaSolo()
  const comercialSolo = esComercialSolo()

  // ── Acordeón: grupos colapsables, persistido en localStorage ──
  const [openGroups, setOpenGroups] = useState<Set<string>>(new Set())
  const [hydrated, setHydrated] = useState(false)
  useEffect(() => {
    try {
      const saved = localStorage.getItem('sidebar-open-groups')
      if (saved) setOpenGroups(new Set(JSON.parse(saved) as string[]))
    } catch { /* ignore */ }
    setHydrated(true)
  }, [])
  useEffect(() => {
    if (hydrated) localStorage.setItem('sidebar-open-groups', JSON.stringify(Array.from(openGroups)))
  }, [openGroups, hydrated])

  const toggleGroup = (label: string) =>
    setOpenGroups((prev) => {
      const next = new Set(prev)
      if (next.has(label)) next.delete(label); else next.add(label)
      return next
    })

  // Grupo que contiene la ruta activa: se fuerza abierto.
  const activeGroupLabel = useMemo(() => {
    const match = (href: string) =>
      href === '/dashboard' ? pathname === '/dashboard' : pathname.startsWith(href)
    for (const g of navGroups) {
      const items = [...(g.items ?? []), ...((g.subsections ?? []).flatMap((s) => s.items))]
      if (g.label && items.some((it) => match(it.href))) return g.label
    }
    return undefined
  }, [pathname])

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
            PILLADO
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
          // Perfil comercial: solo el grupo Negocio (Contratos, Comercial, Consolidado).
          if (comercialSolo && group.label !== 'Negocio') return null
          // Ámbito de vista (MIG233): jefe Calama ve solo Calama/ENEX/Flota;
          // Coquimbo ve todo menos Calama/ENEX. 'todos' = vista completa.
          const ambito = (perfil as { ambito?: string } | null)?.ambito ?? 'todos'
          if (ambito === 'calama' && group.label && !GRUPOS_VISTA_CALAMA.includes(group.label)) return null
          if (ambito === 'coquimbo' && group.label && GRUPOS_SOLO_CALAMA.includes(group.label)) return null

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

          // Acordeón: abierto si la barra está colapsada (modo iconos), si el
          // grupo no tiene label, si el usuario lo abrió, o si contiene la ruta activa.
          const isOpen =
            collapsed || !group.label ||
            openGroups.has(group.label) || group.label === activeGroupLabel

          return (
            <div key={idx}>
              {!collapsed && group.label && (
                <button
                  onClick={() => toggleGroup(group.label!)}
                  className="mb-1 flex w-full items-center justify-between rounded px-3 py-1 text-[10px] font-semibold uppercase tracking-wider text-gray-500 transition-colors hover:bg-white/5 hover:text-gray-300"
                  aria-expanded={isOpen}
                >
                  <span>{group.label}</span>
                  <ChevronDown className={cn('h-3 w-3 transition-transform', isOpen ? '' : '-rotate-90')} />
                </button>
              )}
              {/* Items planos del grupo (compat) */}
              {isOpen && itemsVisibles.length > 0 && (
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
              {isOpen && subsectionsVisibles.map((sub, si) => (
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
