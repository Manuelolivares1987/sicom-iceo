'use client'

/**
 * RoleDashboardRouter — entrega el dashboard correspondiente al rol del
 * usuario autenticado. Si no hay rol o el rol no tiene dashboard especifico
 * todavia, se cae al `LegacyDashboard` generico (mantiene comportamiento previo).
 *
 * FASE 5.6: dashboards prioritarios implementados:
 *   - administrador, gerencia, subgerente_operaciones (via ExecutiveDashboard
 *     existente como fallback temporal, mas bloque admin para admin)
 *   - jefe_mantenimiento / supervisor / planificador → MantenimientoDashboard
 *   - tecnico_mantenimiento → TecnicoDashboard
 *   - bodeguero → BodegueroDashboard
 *   - operador_abastecimiento → AbastecimientoDashboard
 *   - comercial → CommercialDashboard (existente)
 *
 * Otros roles (auditor, prevencionista, rrhh_incentivos) caen a Legacy con
 * vista de KPI/alertas. Se documentan como pendientes en DASHBOARDS_POR_ROL.md.
 */

import { useAuth } from '@/contexts/auth-context'
import { ExecutiveDashboard } from './executive-dashboard'
import { CommercialDashboard } from './commercial-dashboard'
import { OperationsDashboard } from './operations-dashboard'
import { AdminDashboard } from './roles/admin-dashboard'
import { MantenimientoDashboard } from './roles/mantenimiento-dashboard'
import { TecnicoDashboard } from './roles/tecnico-dashboard'
import { BodegueroDashboard } from './roles/bodeguero-dashboard'
import { AbastecimientoDashboard } from './roles/abastecimiento-dashboard'

interface RoleDashboardRouterProps {
  fallback: React.ReactNode
}

export function RoleDashboardRouter({ fallback }: RoleDashboardRouterProps) {
  const { perfil } = useAuth()
  const rol = perfil?.rol

  if (!rol) return <>{fallback}</>

  switch (rol) {
    case 'administrador':
      return <AdminDashboard />

    case 'gerencia':
    case 'subgerente_operaciones':
    case 'jefe_operaciones':
      return <ExecutiveDashboard />

    case 'jefe_mantenimiento':
    case 'supervisor':
    case 'planificador':
      return <MantenimientoDashboard />

    case 'tecnico_mantenimiento':
      return <TecnicoDashboard />

    case 'bodeguero':
      return <BodegueroDashboard />

    case 'operador_abastecimiento':
      return <AbastecimientoDashboard />

    case 'comercial':
      return <CommercialDashboard />

    case 'auditor':
    case 'prevencionista':
    case 'rrhh_incentivos':
    case 'colaborador':
    default:
      // Roles secundarios: usar OperationsDashboard como vista neutra
      // o el fallback (LegacyDashboard) si se prefiere.
      return <OperationsDashboard />
  }
}
