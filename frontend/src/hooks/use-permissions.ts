'use client'

import { useQuery } from '@tanstack/react-query'
import { useAuth, type RolCalama } from '@/contexts/auth-context'
import { supabase } from '@/lib/supabase'
import type { RolUsuario } from '@/types/database'

export type Module = 'contratos' | 'activos' | 'ordenes_trabajo' | 'inventario' | 'mantenimiento' | 'abastecimiento' | 'cumplimiento' | 'kpi' | 'iceo' | 'reportes' | 'auditoria' | 'admin' | 'flota' | 'prevencion' | 'comercial' | 'reporte_diario'

// Modulos extendidos (overlay) que NO requieren todos los CRUD permissions.
// Se mantienen separados de PERMISSIONS para no romper la matriz por-rol existente.
export type ExtendedModule = 'operacion_calama' | 'bodega' | 'mantencion_qr'

const EXTENDED_VIEW: Record<ExtendedModule, RolUsuario[]> = {
  operacion_calama: [
    'administrador', 'gerencia', 'subgerente_operaciones', 'jefe_operaciones',
    'planificador', 'supervisor', 'auditor',
  ],
  bodega: [
    'administrador', 'gerencia', 'subgerente_operaciones', 'jefe_operaciones',
    'planificador', 'supervisor', 'bodeguero', 'operador_abastecimiento', 'auditor',
  ],
  mantencion_qr: [
    'administrador', 'gerencia', 'subgerente_operaciones', 'jefe_operaciones',
    'jefe_mantenimiento', 'planificador', 'supervisor', 'tecnico_mantenimiento', 'auditor',
    'auditor_calidad',
  ],
}

export type Permission = 'view' | 'create' | 'edit' | 'delete' | 'approve' | 'export'

// Permission matrix by role
const PERMISSIONS: Record<RolUsuario, Record<Module, Permission[]>> = {
  administrador: {
    contratos: ['view','create','edit','delete','approve','export'],
    activos: ['view','create','edit','delete','export'],
    ordenes_trabajo: ['view','create','edit','delete','approve','export'],
    inventario: ['view','create','edit','delete','approve','export'],
    mantenimiento: ['view','create','edit','delete','export'],
    abastecimiento: ['view','create','edit','delete','export'],
    cumplimiento: ['view','create','edit','delete','export'],
    kpi: ['view','edit','export'],
    iceo: ['view','edit','export'],
    reportes: ['view','export'],
    auditoria: ['view','export'],
    admin: ['view','create','edit','delete'],
    flota: ['view','create','edit','delete','export'],
    prevencion: ['view','create','edit','delete','export'],
    comercial: ['view','create','edit','delete','export'],
    reporte_diario: ['view','export'],
  },
  gerencia: {
    contratos: ['view','export'],
    activos: ['view','export'],
    ordenes_trabajo: ['view','export'],
    inventario: ['view','export'],
    mantenimiento: ['view','export'],
    abastecimiento: ['view','export'],
    cumplimiento: ['view','export'],
    kpi: ['view','export'],
    iceo: ['view','export'],
    reportes: ['view','export'],
    auditoria: ['view','export'],
    admin: ['view'],
    flota: ['view','export'],
    prevencion: ['view','export'],
    comercial: ['view','export'],
    reporte_diario: ['view','export'],
  },
  subgerente_operaciones: {
    contratos: ['view','export'],
    activos: ['view','export'],
    ordenes_trabajo: ['view','approve','export'],
    inventario: ['view','export'],
    mantenimiento: ['view','export'],
    abastecimiento: ['view','export'],
    cumplimiento: ['view','export'],
    kpi: ['view','export'],
    iceo: ['view','export'],
    reportes: ['view','export'],
    auditoria: ['view','export'],
    admin: ['view'],
    flota: ['view','create','edit','export'],
    prevencion: ['view','export'],
    comercial: ['view','export'],
    reporte_diario: ['view','export'],
  },
  jefe_operaciones: {
    contratos: ['view'],
    activos: ['view','edit'],
    ordenes_trabajo: ['view','create','edit','approve','export'],
    inventario: ['view'],
    mantenimiento: ['view'],
    abastecimiento: ['view'],
    cumplimiento: ['view'],
    kpi: ['view','export'],
    iceo: ['view'],
    reportes: ['view','export'],
    auditoria: [],
    admin: [],
    flota: ['view','create','edit','export'],
    prevencion: ['view'],
    comercial: ['view'],
    reporte_diario: ['view','export'],
  },
  jefe_mantenimiento: {
    contratos: ['view'],
    activos: ['view','edit'],
    ordenes_trabajo: ['view','create','edit','approve','export'],
    inventario: ['view'],
    mantenimiento: ['view','create','edit','export'],
    abastecimiento: [],
    cumplimiento: ['view'],
    kpi: ['view'],
    iceo: [],
    reportes: ['view','export'],
    auditoria: [],
    admin: [],
    flota: ['view','edit'],
    prevencion: ['view'],
    comercial: [],
    reporte_diario: ['view','export'],
  },
  comercial: {
    // El perfil comercial SOLO ve la pestaña Negocio: Contratos, Comercial y
    // Consolidado Combustible (estos dos últimos bajo el módulo 'comercial').
    contratos: ['view','export'],
    activos: [],
    ordenes_trabajo: [],
    inventario: [],
    mantenimiento: [],
    abastecimiento: [],
    cumplimiento: [],
    kpi: [],
    iceo: [],
    reportes: [],
    auditoria: [],
    admin: [],
    flota: [],
    prevencion: [],
    comercial: ['view','create','edit','export'],
    reporte_diario: [],
  },
  prevencionista: {
    contratos: [],
    activos: ['view'],
    ordenes_trabajo: ['view'],
    inventario: [],
    mantenimiento: [],
    abastecimiento: [],
    cumplimiento: ['view','create','edit','export'],
    kpi: [],
    iceo: [],
    reportes: ['view','export'],
    auditoria: [],
    admin: [],
    flota: ['view'],
    prevencion: ['view','create','edit','delete','export'],
    comercial: [],
    reporte_diario: ['view','export'],
  },
  colaborador: {
    contratos: [],
    activos: ['view'],
    ordenes_trabajo: ['view'],
    inventario: [],
    mantenimiento: [],
    abastecimiento: [],
    cumplimiento: [],
    kpi: [],
    iceo: [],
    reportes: [],
    auditoria: [],
    admin: [],
    flota: ['view'],
    prevencion: [],
    comercial: [],
    reporte_diario: ['view'],
  },
  supervisor: {
    contratos: ['view'],
    activos: ['view'],
    ordenes_trabajo: ['view','create','edit','approve'],
    inventario: ['view'],
    mantenimiento: ['view','create'],
    abastecimiento: ['view'],
    cumplimiento: ['view'],
    kpi: ['view'],
    iceo: ['view'],
    reportes: ['view','export'],
    auditoria: ['view'],
    admin: [],
    flota: ['view','edit'],
    prevencion: ['view'],
    comercial: [],
    reporte_diario: ['view'],
  },
  planificador: {
    contratos: ['view'],
    activos: ['view'],
    ordenes_trabajo: ['view','create','edit'],
    inventario: ['view'],
    mantenimiento: ['view','create','edit'],
    abastecimiento: ['view'],
    cumplimiento: ['view'],
    kpi: ['view'],
    iceo: ['view'],
    reportes: ['view','export'],
    auditoria: [],
    admin: [],
    flota: ['view','edit'],
    prevencion: [],
    comercial: [],
    reporte_diario: ['view'],
  },
  tecnico_mantenimiento: {
    contratos: [],
    activos: ['view'],
    ordenes_trabajo: ['view','edit'],
    inventario: ['view'],
    mantenimiento: ['view'],
    abastecimiento: [],
    cumplimiento: [],
    kpi: [],
    iceo: [],
    reportes: [],
    auditoria: [],
    admin: [],
    flota: [],
    prevencion: [],
    comercial: [],
    reporte_diario: [],
  },
  bodeguero: {
    contratos: [],
    activos: ['view'],
    ordenes_trabajo: ['view'],
    inventario: ['view','create','edit'],
    mantenimiento: [],
    abastecimiento: [],
    cumplimiento: [],
    kpi: [],
    iceo: [],
    reportes: ['view','export'],
    auditoria: [],
    admin: [],
    flota: [],
    prevencion: [],
    comercial: [],
    reporte_diario: [],
  },
  operador_abastecimiento: {
    contratos: [],
    activos: ['view'],
    ordenes_trabajo: ['view'],
    inventario: ['view','create'],
    mantenimiento: [],
    abastecimiento: ['view','create','edit'],
    cumplimiento: [],
    kpi: [],
    iceo: [],
    reportes: [],
    auditoria: [],
    admin: [],
    flota: [],
    prevencion: [],
    comercial: [],
    reporte_diario: [],
  },
  auditor: {
    contratos: ['view'],
    activos: ['view'],
    ordenes_trabajo: ['view'],
    inventario: ['view'],
    mantenimiento: ['view'],
    abastecimiento: ['view'],
    cumplimiento: ['view'],
    kpi: ['view'],
    iceo: ['view'],
    reportes: ['view','export'],
    auditoria: ['view','export'],
    admin: [],
    flota: ['view'],
    prevencion: ['view'],
    comercial: ['view'],
    reporte_diario: ['view','export'],
  },
  rrhh_incentivos: {
    contratos: [],
    activos: [],
    ordenes_trabajo: [],
    inventario: [],
    mantenimiento: [],
    abastecimiento: [],
    cumplimiento: [],
    kpi: ['view'],
    iceo: ['view'],
    reportes: ['view','export'],
    auditoria: [],
    admin: [],
    flota: [],
    prevencion: [],
    comercial: [],
    reporte_diario: [],
  },
  // Auditor de Calidad: control de calidad del taller (Gate 1 chequeo cruzado,
  // Gate 2 auditoria pre-operativo, diferidos). 'approve' en mantenimiento
  // habilita la liberacion a operativo.
  auditor_calidad: {
    contratos: [],
    activos: ['view','edit'],
    ordenes_trabajo: ['view','edit'],
    inventario: ['view'],
    mantenimiento: ['view','create','edit','approve','export'],
    abastecimiento: [],
    cumplimiento: ['view'],
    kpi: ['view'],
    iceo: [],
    reportes: ['view','export'],
    auditoria: ['view','export'],
    admin: [],
    flota: ['view','edit'],
    prevencion: ['view'],
    comercial: [],
    reporte_diario: ['view'],
  },
}

// Roles Calama que dan acceso al modulo Operacion Calama (UI dashboard).
const ROLES_CALAMA_DASHBOARD: RolCalama[] = [
  'jefe_sucursal', 'planificador_calama', 'supervisor_calama', 'auditor_calama',
]

// Roles globales que rompen el bloqueo Calama-solo (admins reales).
// supervisor / planificador / jefe_operaciones NO rompen el bloqueo: si tienen
// rol_calama dedicado se asume que su trabajo es solo Calama.
const ADMIN_GLOBAL_ROLES: RolUsuario[] = [
  'administrador', 'gerencia', 'subgerente_operaciones',
]

// ── Overrides de permisos configurables por el admin (MIG 126) ──────────────
// Capa sobre los defaults hardcodeados. Mapa rol -> modulo -> permisos[].
export type PermisosOverrides = Record<string, Record<string, Permission[]>>

export function useRolPermisosOverrides() {
  return useQuery({
    queryKey: ['rol-permisos-overrides'],
    queryFn: async (): Promise<PermisosOverrides> => {
      const { data, error } = await supabase
        .from('rol_permisos_modulo')
        .select('rol, modulo, permisos')
      if (error) throw error
      const map: PermisosOverrides = {}
      for (const row of (data ?? []) as Array<{ rol: string; modulo: string; permisos: string[] }>) {
        ;(map[row.rol] ??= {})[row.modulo] = (row.permisos ?? []) as Permission[]
      }
      return map
    },
    staleTime: 300_000,
  })
}

// Metadatos para la pagina de administracion de permisos.
export const ALL_PERMISSIONS: Permission[] = ['view', 'create', 'edit', 'delete', 'approve', 'export']

export const PERMISSION_LABELS: Record<Permission, string> = {
  view: 'Ver', create: 'Crear', edit: 'Editar', delete: 'Eliminar', approve: 'Aprobar', export: 'Exportar',
}

export const MODULE_CATALOG: { key: string; label: string; extendido?: boolean }[] = [
  { key: 'contratos', label: 'Contratos' },
  { key: 'activos', label: 'Activos' },
  { key: 'ordenes_trabajo', label: 'Órdenes de Trabajo' },
  { key: 'inventario', label: 'Inventario' },
  { key: 'mantenimiento', label: 'Mantenimiento (Taller)' },
  { key: 'abastecimiento', label: 'Abastecimiento' },
  { key: 'cumplimiento', label: 'Cumplimiento' },
  { key: 'kpi', label: 'KPI' },
  { key: 'iceo', label: 'ICEO' },
  { key: 'reportes', label: 'Reportes' },
  { key: 'auditoria', label: 'Auditoría' },
  { key: 'admin', label: 'Administración' },
  { key: 'flota', label: 'Flota' },
  { key: 'prevencion', label: 'Prevención' },
  { key: 'comercial', label: 'Comercial' },
  { key: 'reporte_diario', label: 'Reporte Diario' },
  { key: 'operacion_calama', label: 'Operación Calama', extendido: true },
  { key: 'bodega', label: 'Bodega', extendido: true },
  { key: 'mantencion_qr', label: 'Mantención QR', extendido: true },
]

export const ALL_ROLES: RolUsuario[] = Object.keys(PERMISSIONS) as RolUsuario[]

/** Permisos default (hardcodeados) para un (rol, modulo), incluyendo extendidos. */
export function defaultPermsForRole(rol: RolUsuario, modulo: string): Permission[] {
  const ext = MODULE_CATALOG.find((m) => m.key === modulo)?.extendido
  if (ext) return EXTENDED_VIEW[modulo as ExtendedModule]?.includes(rol) ? ['view'] : []
  return (PERMISSIONS[rol] as Record<string, Permission[]>)?.[modulo] ?? []
}

export function usePermissions() {
  const { perfil, rolCalama } = useAuth()
  const rol = perfil?.rol as RolUsuario | undefined
  const { data: overrides } = useRolPermisosOverrides()

  // Permisos efectivos = override de BD si existe, si no el default hardcodeado.
  function effectivePerms(r: RolUsuario, modulo: string): Permission[] {
    const ov = overrides?.[r]?.[modulo]
    if (ov) return ov
    return defaultPermsForRole(r, modulo)
  }

  function isAdminGlobal(): boolean {
    return !!rol && ADMIN_GLOBAL_ROLES.includes(rol)
  }

  // Operador Calama "puro": rol_calama=operador_calama y NO admin global.
  // Solo puede ver /m/calama.
  function esOperadorCalamaSolo(): boolean {
    if (rolCalama !== 'operador_calama') return false
    return !isAdminGlobal()
  }

  // Supervisor Calama "puro": rol_calama=supervisor_calama y NO admin global.
  // Solo puede ver /dashboard/operacion-calama/*.
  function esSupervisorCalamaSolo(): boolean {
    if (rolCalama !== 'supervisor_calama') return false
    return !isAdminGlobal()
  }

  // Cualquier perfil restringido a Calama (operador o supervisor calama solos).
  function esRestringidoCalama(): boolean {
    return esOperadorCalamaSolo() || esSupervisorCalamaSolo()
  }

  // Perfil comercial: solo ve la pestaña Negocio (Contratos, Comercial,
  // Consolidado Combustible). El sidebar oculta el resto de grupos.
  function esComercialSolo(): boolean {
    return rol === 'comercial'
  }

  function tieneRolCalama(): boolean { return rolCalama !== null }
  function tieneAccesoDashboardCalama(): boolean {
    return !!rolCalama && ROLES_CALAMA_DASHBOARD.includes(rolCalama)
  }

  function can(module: Module, permission: Permission): boolean {
    if (!rol) return false
    // Override duro: usuarios restringidos a Calama no tienen permisos en modulos
    // generales. La excepcion para supervisor_calama es el modulo extendido,
    // que se concede via canViewExtended('operacion_calama').
    if (esRestringidoCalama()) return false
    return effectivePerms(rol, module).includes(permission)
  }

  function canView(module: Module): boolean { return can(module, 'view') }
  function canCreate(module: Module): boolean { return can(module, 'create') }
  function canEdit(module: Module): boolean { return can(module, 'edit') }
  function canDelete(module: Module): boolean { return can(module, 'delete') }
  function canApprove(module: Module): boolean { return can(module, 'approve') }
  function canExport(module: Module): boolean { return can(module, 'export') }

  function isAdmin(): boolean { return rol === 'administrador' }
  function isSupervisor(): boolean { return rol === 'supervisor' || rol === 'subgerente_operaciones' }
  function isReadOnly(): boolean { return rol === 'gerencia' || rol === 'auditor' || rol === 'rrhh_incentivos' }

  function getVisibleModules(): Module[] {
    if (!rol) return []
    if (esRestringidoCalama()) return []
    return (Object.keys(PERMISSIONS[rol]) as Module[]).filter(m => effectivePerms(rol, m).includes('view'))
  }

  function canViewExtended(mod: ExtendedModule): boolean {
    if (!rol) return false
    // Restringidos: solo modulo Operacion Calama; nunca bodega ni mantencion_qr.
    if (esRestringidoCalama()) return mod === 'operacion_calama'
    // Override de BD (si el admin configuro el modulo extendido para el rol).
    const ov = overrides?.[rol]?.[mod]
    if (ov) return ov.includes('view')
    // Acceso por rol global (matriz EXTENDED_VIEW).
    if (EXTENDED_VIEW[mod]?.includes(rol)) return true
    // Acceso por rol Calama del proyecto: cualquier rol_calama da acceso al dashboard Calama.
    if (mod === 'operacion_calama' && tieneAccesoDashboardCalama()) return true
    return false
  }

  return {
    can, canView, canCreate, canEdit, canDelete, canApprove, canExport,
    canViewExtended,
    isAdmin, isSupervisor, isReadOnly, isAdminGlobal,
    getVisibleModules,
    rol, rolCalama,
    esOperadorCalamaSolo, esSupervisorCalamaSolo, esRestringidoCalama,
    esComercialSolo,
    tieneRolCalama, tieneAccesoDashboardCalama,
  }
}
