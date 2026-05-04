'use client'

import Link from 'next/link'
import { Wrench, Truck, Calendar, AlertTriangle, ClipboardList, ArrowRight } from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Spinner } from '@/components/ui/spinner'
import { Badge } from '@/components/ui/badge'
import { useOTsStats } from '@/hooks/use-ordenes-trabajo'
import { useFlotaVehicular } from '@/hooks/use-flota'
import { useMantenimientosVencidos, useProximasMantenimientos } from '@/hooks/use-mantenimiento'
import { useAlertasNoLeidas } from '@/hooks/use-alertas'

/**
 * Dashboard para jefe_mantenimiento, supervisor y planificador.
 * Foco: OTs en ejecucion, vencidas, equipos en taller, preventivos proximos.
 */
export function MantenimientoDashboard() {
  const otsStats = useOTsStats()
  const { data: flota, isLoading: loadingFlota } = useFlotaVehicular()
  const { data: pmVencidos } = useMantenimientosVencidos()
  const { data: pmProximos } = useProximasMantenimientos(15)
  const { data: alertas } = useAlertasNoLeidas()

  const stats = otsStats.data as Record<string, number> | undefined
  const otsActivas =
    (stats?.en_ejecucion ?? 0) + (stats?.asignada ?? 0) + (stats?.pausada ?? 0) + (stats?.creada ?? 0)
  const otsVencidas = stats?.no_ejecutada ?? 0
  const otsPorCerrar =
    (stats?.ejecutada_ok ?? 0) + (stats?.ejecutada_con_observaciones ?? 0)

  const enTaller =
    (flota ?? []).filter((a: any) => ['en_mantenimiento', 'fuera_servicio'].includes(a.estado)).length

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Panel de Mantenimiento</h1>
        <p className="text-sm text-gray-500">OTs, equipos en taller, planes preventivos</p>
      </div>

      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <KPI
          label="OTs Activas"
          value={otsStats.isLoading ? null : otsActivas}
          icon={<Wrench className="h-5 w-5 text-blue-600" />}
        />
        <KPI
          label="OTs Por Cerrar"
          value={otsStats.isLoading ? null : otsPorCerrar}
          icon={<ClipboardList className="h-5 w-5 text-amber-600" />}
          accent="amber"
        />
        <KPI
          label="OTs Vencidas"
          value={otsStats.isLoading ? null : otsVencidas}
          icon={<AlertTriangle className="h-5 w-5 text-red-600" />}
          accent="red"
        />
        <KPI
          label="Equipos en Taller"
          value={loadingFlota ? null : enTaller}
          icon={<Truck className="h-5 w-5 text-orange-600" />}
        />
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-base">
              <Calendar className="h-5 w-5 text-yellow-600" />
              PMs vencidos / próximos (15 días)
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="flex justify-around mb-3">
              <div className="text-center">
                <p className="text-xs text-gray-500">Vencidos</p>
                <p className="text-3xl font-bold text-red-600">{pmVencidos?.length ?? 0}</p>
              </div>
              <div className="text-center">
                <p className="text-xs text-gray-500">Próximos</p>
                <p className="text-3xl font-bold text-amber-600">{pmProximos?.length ?? 0}</p>
              </div>
            </div>
            <Link
              href="/dashboard/mantenimiento"
              className="text-sm font-medium text-pillado-green-600 hover:underline flex items-center justify-center gap-1"
            >
              Ver planes <ArrowRight className="h-4 w-4" />
            </Link>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-base">
              <AlertTriangle className="h-5 w-5 text-red-500" />
              Alertas activas
            </CardTitle>
          </CardHeader>
          <CardContent>
            {!alertas || alertas.length === 0 ? (
              <p className="text-sm text-gray-400 py-4 text-center">Sin alertas</p>
            ) : (
              <ul className="space-y-2">
                {alertas.slice(0, 4).map((a) => (
                  <li key={a.id} className="text-sm border-l-2 border-amber-300 pl-3">
                    <div className="flex items-center justify-between">
                      <strong className="text-gray-900">{a.titulo}</strong>
                      <Badge>{a.severidad}</Badge>
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Acciones de hoy</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-2">
            <QuickLink href="/dashboard/ordenes-trabajo" label="Órdenes de Trabajo" />
            <QuickLink href="/dashboard/mantenimiento" label="Mantenimiento" />
            <QuickLink href="/dashboard/flota" label="Flota" />
            <QuickLink href="/dashboard/activos" label="Activos" />
          </div>
        </CardContent>
      </Card>
    </div>
  )
}

function KPI({
  label,
  value,
  icon,
  accent,
}: {
  label: string
  value: number | null
  icon: React.ReactNode
  accent?: 'red' | 'amber'
}) {
  const colorClass =
    accent === 'red' ? 'text-red-600' : accent === 'amber' ? 'text-amber-600' : 'text-gray-900'
  return (
    <Card>
      <CardContent className="p-4">
        <div className="flex items-center justify-between">
          <p className="text-xs text-gray-500">{label}</p>
          {icon}
        </div>
        <p className={`mt-1 text-3xl font-bold ${colorClass}`}>
          {value === null ? <Spinner size="sm" /> : value}
        </p>
      </CardContent>
    </Card>
  )
}

function QuickLink({ href, label }: { href: string; label: string }) {
  return (
    <Link
      href={href}
      className="rounded-md border border-gray-200 bg-white px-3 py-2 text-sm text-gray-700 text-center hover:bg-gray-50 hover:border-pillado-green-400"
    >
      {label}
    </Link>
  )
}
