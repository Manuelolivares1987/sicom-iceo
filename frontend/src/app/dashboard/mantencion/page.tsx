'use client'

// ============================================================================
// /dashboard/mantencion — Índice del módulo de mantención.
// Muestra el badge global de alertas + accesos rápidos.
// ============================================================================

import Link from 'next/link'
import { AlertTriangle, ListChecks, Wrench } from 'lucide-react'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { Spinner } from '@/components/ui/spinner'
import { AlertasMantencionBadge } from '@/components/mantencion/alertas-mantencion-badge'

const ROLES_MANTENCION = new Set([
  'administrador', 'gerencia', 'subgerente_operaciones', 'jefe_operaciones',
  'supervisor', 'planificador', 'tecnico_mantenimiento', 'auditor',
  'jefe_mantenimiento',
])

export default function MantencionIndexPage() {
  const { perfil, loading } = useRequireAuth()
  const rolValido = perfil?.rol && ROLES_MANTENCION.has(perfil.rol)

  if (loading) {
    return (
      <div className="flex min-h-[50vh] items-center justify-center">
        <Spinner size="lg" className="text-pillado-green-600" />
      </div>
    )
  }

  if (!rolValido) {
    return (
      <div className="rounded-lg border-2 border-red-300 bg-red-50 p-4">
        <p className="font-semibold text-red-800">Acceso denegado</p>
        <p className="text-sm text-red-700 mt-1">
          Tu rol ({perfil?.rol ?? 'sin rol'}) no tiene permisos para acceder al módulo de mantención.
        </p>
      </div>
    )
  }

  return (
    <div className="space-y-6 max-w-5xl mx-auto">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Mantención</h1>
        <p className="text-sm text-gray-500 mt-0.5">
          Vista global del módulo: alertas, checklists QR y registros por equipo.
        </p>
      </div>

      {/* Badge global */}
      <AlertasMantencionBadge variant="card" />

      {/* Accesos rápidos */}
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <Link
          href="/dashboard/mantencion/alertas"
          className="rounded-2xl border-2 border-gray-200 bg-white p-5 hover:border-pillado-green-400 hover:shadow-md transition"
        >
          <div className="flex items-start gap-3">
            <AlertTriangle className="h-7 w-7 text-orange-600 shrink-0" />
            <div>
              <p className="font-bold text-gray-900">Listado de alertas</p>
              <p className="text-xs text-gray-500 mt-1">
                Ver, filtrar y resolver todas las alertas abiertas (técnicas + calidad).
              </p>
            </div>
          </div>
        </Link>

        <Link
          href="/dashboard/activos"
          className="rounded-2xl border-2 border-gray-200 bg-white p-5 hover:border-pillado-green-400 hover:shadow-md transition"
        >
          <div className="flex items-start gap-3">
            <Wrench className="h-7 w-7 text-pillado-green-600 shrink-0" />
            <div>
              <p className="font-bold text-gray-900">Equipos</p>
              <p className="text-xs text-gray-500 mt-1">
                Ir al listado de activos para entrar al detalle de mantención por equipo.
              </p>
            </div>
          </div>
        </Link>

        <Link
          href="/dashboard/ordenes-trabajo"
          className="rounded-2xl border-2 border-gray-200 bg-white p-5 hover:border-pillado-green-400 hover:shadow-md transition"
        >
          <div className="flex items-start gap-3">
            <ListChecks className="h-7 w-7 text-blue-600 shrink-0" />
            <div>
              <p className="font-bold text-gray-900">Órdenes de trabajo</p>
              <p className="text-xs text-gray-500 mt-1">
                Crear y dar seguimiento a OT preventivas y correctivas.
              </p>
            </div>
          </div>
        </Link>
      </div>

      <p className="text-xs text-gray-500">
        Este panel se actualiza automáticamente cada 60 segundos.
      </p>
    </div>
  )
}
