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
  PackageSearch,
  ArrowLeftRight,
  ShieldCheck,
  BarChart3,
  Gauge,
  Users,
  Smartphone,
  Link2,
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
  Footprints,
  ShieldAlert,
  Clock,
  Archive,
  Wallet,
  FileWarning,
} from 'lucide-react'
import { useNcPorDecidir } from '@/hooks/use-nc-por-decidir'
import { cn } from '@/lib/utils'

type NavItem = {
  label: string
  href: string
  icon: any
  module?: Module
  extendedModule?: ExtendedModule
  // Cargos que ven este item. Se usa cuando el módulo NO es el eje correcto:
  // los Recorridos Gemba, por ejemplo, exigen el mismo permiso ('prevencion')
  // para los tres cargos, pero cada uno entra por su propia pantalla —el
  // prevencionista por Prevención, taller y operaciones por Operación—.
  // Si se declaran `module` y `roles` juntos, deben cumplirse LOS DOS: el
  // módulo sigue siendo el que valida contra la base, y `roles` solo decide
  // dónde aparece el acceso.
  roles?: string[]
  // Cargos que NO ven este item aunque tengan el módulo. Se usa cuando el
  // mismo destino ya aparece en otro grupo más cercano a su trabajo: al
  // prevencionista los equipos le llegan por Prevención (control documental),
  // así que el mismo link en Flota sería un duplicado.
  excluirRoles?: string[]
  badge?: string                  // 'Legacy' | 'Nuevo' | etc.
  tooltip?: string                // texto descriptivo opcional
  // Cuenta viva de lo que espera una decisión. El jefe de taller no mira la
  // campanita —anda en terreno—, así que el número tiene que estar en el menú
  // por donde entra a trabajar.
  contador?: 'nc-por-decidir'
}

type NavSubsection = {
  label: string                   // subheader pequeno dentro del grupo
  items: NavItem[]
}

type NavGroup = {
  label?: string
  items?: NavItem[]               // grupo flat (compatibilidad)
  subsections?: NavSubsection[]   // grupo con sub-secciones
  /** Sólo para administradores globales: no pasa por permisos de módulo. */
  soloAdmin?: boolean
  /**
   * El grupo nace abierto. Se usa donde el acordeón cerrado equivale a no
   * existir: los accesos de administrador viven al final de trece grupos, y
   * un título cerrado abajo de todo no lo encuentra nadie.
   */
  defaultOpen?: boolean
}

// Los Recorridos Gemba son una práctica de tres cargos, pero cada uno entra
// por SU pantalla: prevención vive en Prevención, y taller y operaciones en
// Operación. Es el mismo módulo y el mismo permiso —lo que cambia es dónde
// aparece el acceso, para que el prevencionista no tenga que pasar por
// Operación ni al revés.
const GEMBA_OPERACION = [
  'administrador', 'subgerente_operaciones', 'jefe_mantenimiento', 'jefe_operaciones',
]
const GEMBA_PREVENCION = ['administrador', 'prevencionista']

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
        label: 'Gerencia',
        items: [
          // Sin `module`: la autorización la resuelve la base
          // (fn_panel_gerencia_puede_ver, MIG295). Quien no tenga el permiso
          // entra y ve el aviso, no datos.
          {
            label: 'Panel de Gerencia', href: '/dashboard/gerencia', icon: Building2,
            badge: 'Nuevo',
            tooltip: 'Cuadrantes Coquimbo y Calama, semana a semana',
          },
        ],
      },
      {
        label: 'Órdenes de Trabajo',
        items: [
          { label: 'Mis OTs', href: '/dashboard/mis-ots', icon: ClipboardCheck, module: 'ordenes_trabajo' as Module },
          { label: 'Todas las OTs', href: '/dashboard/ordenes-trabajo', icon: ClipboardList, module: 'ordenes_trabajo' },
        ],
      },
      {
        // Los recorridos NO son un módulo de prevención: son una práctica de
        // tres cargos (jefe de taller a diario, jefe de operaciones quincenal,
        // prevención diaria y mensual). Mientras vivieron dentro de
        // /dashboard/prevencion no aparecían en el menú y acumularon 0
        // recorridos en dos meses: nadie hace una caminata diaria si tiene que
        // acordarse de una URL.
        //
        // El módulo es 'prevencion' porque es el mismo permiso que exige la
        // base (fn_gemba_puede_gestionar, MIG288) y los tres cargos lo tienen
        // con create. Si menú y base se separan, aparece el peor error: el
        // botón se ve y la base rechaza al guardar.
        label: 'Recorridos de terreno',
        items: [
          { label: 'Recorridos Gemba', href: '/dashboard/gemba', icon: Footprints, module: 'prevencion',
            roles: GEMBA_OPERACION, badge: 'Nuevo',
            tooltip: 'Tu checklist de terreno: diario para el jefe de taller, quincenal para el jefe de operaciones' },
          { label: 'Cumplimiento de recorridos', href: '/dashboard/gemba/reporte', icon: BarChart3,
            module: 'prevencion', roles: GEMBA_OPERACION,
            tooltip: 'Quién hizo su recorrido y qué hallazgos siguen abiertos' },
        ],
      },
      {
        label: 'Taller',
        items: [
          { label: 'Panel Taller', href: '/dashboard/mantenimiento', icon: Wrench, module: 'mantenimiento' },
          // El acceso a la app del mecánico estaba sólo en el grupo de
          // administrador, al final del menú: quien planifica el taller no
          // tenía cómo mirar lo mismo que ve el operador en su teléfono.
          { label: 'Terreno (móvil)', href: '/m/taller', icon: Smartphone, module: 'mantenimiento',
            tooltip: 'Lo que ve el operador en su teléfono: sus OT, la pauta, el horómetro y el pedido de insumos' },
          { label: 'Plan semanal', href: '/dashboard/mantenimiento/plan-semanal-taller', icon: CalendarClock, module: 'mantenimiento' },
          { label: 'No Conformidades', href: '/dashboard/mantenimiento/no-conformidades', icon: AlertTriangle, module: 'mantenimiento', contador: 'nc-por-decidir',
            tooltip: 'Hallazgos por planificar y repuestos que el operador pide aprobar' },
          { label: 'Equipos auxiliares', href: '/dashboard/mantenimiento/auxiliares', icon: Layers, module: 'mantenimiento' },
          // [MIG452-456] El bono deja de ser discrecional: se calcula, se cierra
          // y el trabajador lo revisa en su teléfono.
          // [MIG460] El cálculo del bono no se muestra al taller hasta que la
          // marcha blanca lo valide. El candado de verdad está en el RPC
          // (`taller_bono_acceso`); esta lista sólo evita mostrar una puerta
          // que se va a cerrar en la cara.
          { label: 'Bono del taller', href: '/dashboard/mantenimiento/bono-taller', icon: Wallet, module: 'mantenimiento', badge: 'NUEVO',
            roles: ['administrador', 'subgerente_operaciones', 'jefe_operaciones', 'jefe_mantenimiento'],
            tooltip: 'Plan de incentivo por trabajo + KPI de disponibilidad, y el cierre del corte' },
          // [MIG399] Los tres tramos del trabajo medidos con los relojes que el
          // sistema ya guardaba: checklist, repuesto y no conformidad.
          { label: 'Cuánto nos demoramos', href: '/dashboard/mantenimiento/tiempos', icon: Clock, module: 'mantenimiento', badge: 'NUEVO',
            tooltip: 'Cuánto toma el checklist, conseguir un repuesto y resolver una NC' },
          // [MIG406] Elegir la patente y pasar todo lo suyo a historia, para
          // empezar limpio después del mes de prueba.
          { label: 'Guardar en el historial', href: '/dashboard/mantenimiento/historial-equipos', icon: Archive, module: 'mantenimiento', badge: 'NUEVO',
            tooltip: 'Elegir patentes y pasar sus NC, OT, vales y checklists a historia. No borra: se puede deshacer' },
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
      { label: 'Terreno (móvil)',  href: '/m/calama',                                   icon: ClipboardCheck,  extendedModule: 'operacion_calama' },
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
      { label: 'Recobros y reprogramación', href: '/dashboard/enex/recobros', icon: CalendarClock, badge: 'Nuevo',
        tooltip: 'Repeticiones facturables del mismo punto/patente en el trimestre + registros de reprogramación para ENEX' },
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
      // [MIG409/410] Los papeles de cada camión, con lo que el lector sacó del
      // archivo. Lo que se arregla acá se ve al tiro en el QR del equipo.
      { label: 'Control documental', href: '/dashboard/flota/control-documental', icon: FileWarning, module: 'flota', badge: 'NUEVO',
        tooltip: 'Papeles vencidos y sin fecha de toda la flota, camión por camión' },
      { label: 'Fiabilidad', href: '/dashboard/fiabilidad', icon: Activity, module: 'flota' },
      { label: 'Informes Recepción', href: '/dashboard/flota/recepcion', icon: FileText, module: 'flota' },
      { label: 'Jornada', href: '/dashboard/flota/jornada', icon: Timer, module: 'flota' },
      { label: 'Mapa GPS', href: '/dashboard/flota/mapa', icon: Satellite, module: 'flota', badge: 'Nuevo' },
      { label: 'Sugerencias estado (GPS)', href: '/dashboard/flota/sugerencias', icon: Satellite, module: 'flota', badge: 'Nuevo' },
      { label: 'Check-List Entrega', href: '/dashboard/flota/checklist-salida', icon: ClipboardCheck, module: 'flota', badge: 'V02' },
      { label: 'Estado Flota', href: '/dashboard/flota/estado-flota', icon: ShieldCheck, module: 'flota', badge: 'Nuevo' },
      { label: 'Equipos y Bitácora (QR)', href: '/dashboard/activos', icon: QrCode, module: 'activos',
        // Al prevencionista este mismo destino le llega por Prevención, con el
        // nombre de lo que va a buscar ahí (Documentos de equipos).
        excluirRoles: ['prevencionista'],
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
      // Sin gate de módulo a propósito: quien pide un tóner es de
      // administración, de prevención o de comercial, y ninguno tiene el
      // permiso de bodega. Es la única entrada que tiene oficina (MIG374).
      { label: 'Pedir a bodega', href: '/dashboard/bodega/pedir', icon: PackageSearch, badge: 'Nuevo',
        tooltip: 'Pedir útiles, tóner, insumos de aseo o cualquier artículo que no venga de un hallazgo ni de una orden de trabajo' },
      { label: 'Panel Bodega', href: '/dashboard/inventario', icon: Package, extendedModule: 'bodega',
        tooltip: 'Stock, compras, salidas, combustible y reportes — todo en un solo panel' },
      { label: 'Pedidos a bodega', href: '/dashboard/bodega/tickets', icon: Ticket, extendedModule: 'bodega', badge: 'Nuevo',
        tooltip: 'Todo el pedido del taller en un lugar: vales por despachar (con fotos), solicitudes de material e historial' },
      { label: 'Seguimiento repuestos', href: '/dashboard/bodega/seguimiento-repuestos', icon: ShoppingCart, extendedModule: 'bodega', badge: 'Nuevo',
        tooltip: 'Repuestos pedidos por el taller sin stock: solicitar la OC (la emite Softland), ver en qué está cada compra y cuándo llega' },
    ],
  },
  // Faena — el combustible de faena no es de la bodega de Coquimbo: se compra
  // distinto, se mide distinto y se le rinde a otro mandante (MIG366). Tenerlo
  // colgando de Bodega hacía que el stock de bodega dijera cuarenta y cinco
  // veces más de lo que hay. Acá vive lo que pasa en faena, y por acá entra el
  // supervisor de turno — que antes no tenía por dónde llegar a su entrega.
  {
    label: 'Faena',
    items: [
      { label: 'Combustible Romeral', href: '/dashboard/combustible/romeral', icon: Fuel, extendedModule: 'bodega',
        tooltip: 'Cierre de volumen y de imputación, excepciones y CECO por confirmar — faena Romeral' },
      { label: 'Combustible Franke', href: '/dashboard/combustible/franke', icon: Fuel, extendedModule: 'bodega',
        tooltip: 'Camiones petroleros, cargas, trasvasije y cuadre diario — faena Franke' },
      { label: 'Entrega de turno', href: '/m/franke/entrega', icon: ArrowLeftRight, extendedModule: 'bodega', badge: 'Nuevo',
        tooltip: 'Cambio de turno 7×7 de Franke: camiones, litros, pendientes y bodega, con firma de quien entrega y de quien recibe' },
      { label: 'Informe de gestión', href: '/dashboard/combustible/franke/informe', icon: FileText, extendedModule: 'bodega', badge: 'Nuevo',
        tooltip: 'El informe mensual del contrato FRK 220/2024, calculado: litros por concepto, tickets y folios, deriva del cuentalitros y balance del periodo' },
      { label: 'Revisión en faena', href: '/dashboard/mantenimiento/pauta-faena', icon: ClipboardList, extendedModule: 'bodega', badge: 'Nuevo',
        tooltip: 'La pauta diaria del mecánico de faena: qué revisó, qué salió NO OK y cuánto falta para la próxima mantención' },
    ],
  },
  // Compliance
  {
    label: 'Compliance',
    items: [
      { label: 'Prevención', href: '/dashboard/prevencion', icon: HardHat, module: 'prevencion' },
      // Sin `roles`: lo ve todo el que tenga el módulo, incluido el jefe de
      // operaciones —es quien responde por la gente que entra a faena—.
      { label: 'Control documental personal', href: '/dashboard/prevencion/personal',
        icon: ShieldAlert, module: 'prevencion', badge: 'Nuevo',
        tooltip: 'Exámenes ocupacionales y licencias con vencimiento — requerido por auditoría' },
      // El Gemba de prevención vive acá, no en Operación: son sus dos
      // checklists (caminata diaria e inspección planificada mensual) y el
      // prevencionista no tiene por qué entrar al menú de taller para hacerlos.
      { label: 'Recorridos Gemba', href: '/dashboard/gemba', icon: Footprints,
        module: 'prevencion', roles: GEMBA_PREVENCION, badge: 'Nuevo',
        tooltip: 'Caminata diaria de seguridad e inspección planificada mensual' },
      { label: 'Cumplimiento de recorridos', href: '/dashboard/gemba/reporte', icon: BarChart3,
        module: 'prevencion', roles: GEMBA_PREVENCION,
        tooltip: 'Historial de recorridos y hallazgos abiertos' },
      // Control documental de EQUIPOS: se entra por el listado y la ficha de
      // cada activo tiene la pestaña Documentos, con alertas de vencimiento y
      // carga del respaldo. Es el complemento del control documental de
      // personal —los dos frentes que pide auditoría—.
      { label: 'Documentos de equipos', href: '/dashboard/activos', icon: QrCode,
        module: 'activos', roles: GEMBA_PREVENCION,
        tooltip: 'Listado de equipos; entra a uno y abre la pestaña Documentos (SOAP, revisión técnica, TC8, hermeticidad)' },
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
  // Las pantallas de terreno. Cada perfil entra a la suya por redirección y no
  // necesita este menú; quien administra sí, para poder ver lo mismo que ve la
  // gente sin pedirle el teléfono prestado. De las seis apps, el menú sólo
  // enlazaba tres: había que saberse las URL de memoria.
  {
    label: 'Vistas de terreno',
    soloAdmin: true,
    defaultOpen: true,
    items: [
      { label: 'Taller', href: '/m/taller', icon: Wrench,
        tooltip: 'Lo que ve el operador del taller: sus OT, la pauta y el pedido de insumos' },
      { label: 'Romeral', href: '/m/romeral', icon: Fuel,
        tooltip: 'Despacho, cierre de turno, recepción, trasvasije y momento cero' },
      { label: 'Franke', href: '/m/franke', icon: Fuel,
        tooltip: 'Pauta del mecánico, despacho, carga en EDS y entrega de turno' },
      { label: 'Franke — venta', href: '/m/franke-venta', icon: Fuel,
        tooltip: 'La venta de combustible de Franke' },
      { label: 'Calama', href: '/m/calama', icon: Activity,
        tooltip: 'Lo que ve el operador de obras civiles en Calama' },
      { label: 'ENEX', href: '/m/enex', icon: Building2,
        tooltip: 'Ejecución en terreno de las pautas del contrato ENEX' },
    ],
  },
  // Lo que ve gente de afuera. Los portales con token no se enlazan acá porque
  // el link ES la credencial: se copian desde su tarjeta, que además dice quién
  // lo ha usado y permite revocarlo.
  {
    label: 'Lo que ve el cliente',
    soloAdmin: true,
    defaultOpen: true,
    items: [
      { label: 'Portal del cliente', href: '/portal/login', icon: Briefcase,
        tooltip: 'Donde entra el arrendatario con su cuenta' },
      { label: 'Reporte de flota', href: '/reporte-flota', icon: Share2,
        tooltip: 'Reporte público, sin cuenta' },
      { label: 'Reporte de fiabilidad', href: '/reporte-fiabilidad', icon: BarChart3,
        tooltip: 'El informe que se manda por correo' },
      { label: 'Link de bodega (oficina)', href: '/dashboard/bodega/tickets', icon: Link2,
        tooltip: 'Copiar o revocar el link con el que oficina pide sin cuenta — pestaña Solicitudes' },
      { label: 'Portales de prevención', href: '/dashboard/prevencion', icon: ShieldCheck,
        tooltip: 'Copiar o revocar los links de documentación que se dan al mandante' },
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
  const {
    canView, canViewExtended, esOperadorCalamaSolo, esSupervisorCalamaSolo,
    esComercialSolo, faenaExclusiva, isAdminGlobal,
  } = usePermissions()
  const faenaSolo = faenaExclusiva()
  const esAdminGlobal = isAdminGlobal()
  const operadorCalamaSolo = esOperadorCalamaSolo()
  const supervisorCalamaSolo = esSupervisorCalamaSolo()
  const comercialSolo = esComercialSolo()

  /**
   * [MIG385] El menú de quien responde por una faena.
   *
   * Se arma con el perfil, no con una constante: la faena declara su panel y su
   * app de terreno, así que cuando Franke tenga el suyo aparece solo. Lo que
   * lleva es lo que esa persona necesita para responder por la faena completa —
   * el combustible, sus equipos y su gente— y nada más.
   */
  const grupoFaena = useMemo(() => {
    if (!faenaSolo) return null
    const corto = faenaSolo.nombre.replace(/^.*—\s*/, '').trim() || faenaSolo.nombre
    const items: NavItem[] = []

    if (faenaSolo.panel_web) {
      items.push({ label: `Panel ${corto}`, href: faenaSolo.panel_web, icon: Fuel })
      // El cuadre con Orpak sólo existe donde hay Orpak. No se ofrece un link
      // que lleve a una pantalla que no está.
      if (faenaSolo.codigo === 'FAE-CMP-ROMERAL') {
        items.push({ label: 'Cuadre Orpak', href: `${faenaSolo.panel_web}/orpak`, icon: Gauge })
      }
    }

    items.push(
      { label: 'Equipos de la faena', href: '/dashboard/activos', icon: Truck },
      { label: 'OTs de la faena', href: '/dashboard/ordenes-trabajo', icon: ClipboardList },
      { label: 'Plan de mantención', href: '/dashboard/mantenimiento/plan-semanal-taller', icon: CalendarClock },
      { label: 'Personal acreditado', href: '/dashboard/prevencion/personal', icon: Users },
    )

    if (faenaSolo.app_movil) {
      items.push({ label: 'Vista de terreno', href: faenaSolo.app_movil, icon: Smartphone })
    }

    const g: NavGroup = { label: `Operación ${corto}`, items }
    return g
  }, [faenaSolo])

  // ── Acordeón: grupos colapsables, persistido en localStorage ──
  // Se guarda abierto/cerrado POR GRUPO y no la lista de abiertos: con una
  // lista, un grupo que nace abierto no se puede cerrar —la ausencia significa
  // las dos cosas a la vez—.
  const [groupState, setGroupState] = useState<Record<string, boolean>>({})
  const [hydrated, setHydrated] = useState(false)
  useEffect(() => {
    try {
      const saved = localStorage.getItem('sidebar-open-groups')
      if (saved) {
        const parsed = JSON.parse(saved) as unknown
        // Compatibilidad con el formato viejo (arreglo de grupos abiertos).
        if (Array.isArray(parsed)) {
          setGroupState(Object.fromEntries((parsed as string[]).map((l) => [l, true])))
        } else if (parsed && typeof parsed === 'object') {
          setGroupState(parsed as Record<string, boolean>)
        }
      }
    } catch { /* ignore */ }
    setHydrated(true)
  }, [])
  useEffect(() => {
    if (hydrated) localStorage.setItem('sidebar-open-groups', JSON.stringify(groupState))
  }, [groupState, hydrated])

  const toggleGroup = (label: string, abierto: boolean) =>
    setGroupState((prev) => ({ ...prev, [label]: !abierto }))

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
        {(grupoFaena ? [grupoFaena] : navGroups).map((group, idx) => {
          // Los grupos de administrador no pasan por permisos de módulo: son
          // atajos a pantallas que ya existen, no un permiso nuevo.
          if (group.soloAdmin && !esAdminGlobal) return null
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
            // El menú de faena ya viene acotado: sus items no vuelven a pasar
            // por los permisos de módulo, o una planificadora sin el módulo de
            // mantenimiento se quedaría sin ver sus propias OT.
            if (grupoFaena) return true
            if (group.soloAdmin) return true
            if (operadorCalamaSolo) return item.href === '/m/calama'
            if (supervisorCalamaSolo) {
              return item.extendedModule === 'operacion_calama' && item.href !== '/m/calama'
            }
            // `roles` acota POR CARGO dónde aparece el acceso; el módulo sigue
            // siendo el que decide si la persona puede o no. Si el item declara
            // los dos, tienen que cumplirse ambos.
            if (item.roles && !item.roles.includes(perfil?.rol ?? '')) return false
            if (item.excluirRoles?.includes(perfil?.rol ?? '')) return false
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
          //
          // [MIG385] El menú de faena va SIEMPRE abierto. Es el único grupo que
          // esa persona tiene, y `activeGroupLabel` lo busca en navGroups —donde
          // no está—, así que ni siquiera se abría al estar parada en él:
          // Catalina entraba y veía un menú con un título y nada debajo.
          // Un acordeón de un solo grupo no es un acordeón, es una puerta cerrada.
          const isOpen =
            collapsed || !group.label || !!grupoFaena ||
            group.label === activeGroupLabel ||
            (groupState[group.label] ?? !!group.defaultOpen)

          return (
            <div key={idx}>
              {!collapsed && group.label && (
                <button
                  onClick={() => toggleGroup(group.label!, isOpen)}
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
  const { data: porDecidir = 0 } = useNcPorDecidir()
  const n = item.contador === 'nc-por-decidir' ? porDecidir : 0
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
          {n > 0 && (
            <span title={`${n} esperando tu decisión`}
                  className="rounded-full bg-pillado-orange-500 px-1.5 py-0.5 text-[10px] font-bold text-white">
              {n}
            </span>
          )}
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
