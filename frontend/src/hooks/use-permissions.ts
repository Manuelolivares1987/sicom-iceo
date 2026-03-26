'use client'

import { useAuth } from '@/contexts/auth-context'
import type { RolUsuario } from '@/types/database'

export type Module = 'contratos' | 'activos' | 'ordenes_trabajo' | 'inventario' | 'mantenimiento' | 'abastecimiento' | 'cumplimiento' | 'kpi' | 'iceo' | 'reportes' | 'auditoria' | 'admin'

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
  },
}

export function usePermissions() {
  const { perfil } = useAuth()
  const rol = perfil?.rol as RolUsuario | undefined

  function can(module: Module, permission: Permission): boolean {
    if (!rol) return false
    const modulePerms = PERMISSIONS[rol]?.[module]
    return modulePerms?.includes(permission) ?? false
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

  // Get visible sidebar modules for current role
  function getVisibleModules(): Module[] {
    if (!rol) return []
    return (Object.keys(PERMISSIONS[rol]) as Module[]).filter(m => PERMISSIONS[rol][m].includes('view'))
  }

  return { can, canView, canCreate, canEdit, canDelete, canApprove, canExport, isAdmin, isSupervisor, isReadOnly, getVisibleModules, rol }
}
