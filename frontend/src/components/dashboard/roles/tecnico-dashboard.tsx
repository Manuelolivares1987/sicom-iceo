'use client'

import Link from 'next/link'
import { useMemo } from 'react'
import { ClipboardList, Wrench, Camera, ArrowRight, Package } from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Spinner } from '@/components/ui/spinner'
import { Badge } from '@/components/ui/badge'
import { useAuth } from '@/contexts/auth-context'
import { useOrdenesTrabajo } from '@/hooks/use-ordenes-trabajo'
import { formatDate, getEstadoOTColor, getEstadoOTLabel } from '@/lib/utils'

/**
 * Dashboard tecnico_mantenimiento.
 * Foco: Mis OTs activas, evidencias pendientes, accesos rapidos al trabajo.
 */
export function TecnicoDashboard() {
  const { user } = useAuth()
  const { data: ots, isLoading } = useOrdenesTrabajo({ responsable_id: user?.id })

  const misOTs = useMemo(() => {
    if (!ots) return { activas: [], porIniciar: [], total: 0 }
    const activas = ots.filter((o: any) =>
      ['asignada', 'en_ejecucion', 'pausada'].includes(o.estado)
    )
    const porIniciar = ots.filter((o: any) => o.estado === 'asignada')
    return { activas, porIniciar, total: ots.length }
  }, [ots])

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Mi Día de Trabajo</h1>
        <p className="text-sm text-gray-500">OTs asignadas y tareas pendientes</p>
      </div>

      {/* KPIs */}
      <div className="grid grid-cols-3 gap-4">
        <KPI
          label="OTs Activas"
          value={isLoading ? null : misOTs.activas.length}
          icon={<Wrench className="h-5 w-5 text-blue-600" />}
        />
        <KPI
          label="Por Iniciar"
          value={isLoading ? null : misOTs.porIniciar.length}
          icon={<ClipboardList className="h-5 w-5 text-amber-600" />}
          accent="amber"
        />
        <KPI
          label="Total Asignadas"
          value={isLoading ? null : misOTs.total}
          icon={<ClipboardList className="h-5 w-5 text-gray-500" />}
        />
      </div>

      {/* OTs activas */}
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2 text-base">
            <Wrench className="h-5 w-5" />
            Mis OTs activas
          </CardTitle>
        </CardHeader>
        <CardContent>
          {isLoading ? (
            <div className="flex justify-center py-6">
              <Spinner />
            </div>
          ) : misOTs.activas.length === 0 ? (
            <p className="text-sm text-gray-400 py-4 text-center">
              No tienes OTs activas. Pasa al planificador si esperas trabajo.
            </p>
          ) : (
            <ul className="divide-y">
              {misOTs.activas.slice(0, 5).map((ot: any) => (
                <li key={ot.id}>
                  <Link
                    href={`/dashboard/ordenes-trabajo/${ot.id}`}
                    className="flex items-center justify-between py-3 hover:bg-gray-50 -mx-3 px-3 rounded"
                  >
                    <div>
                      <p className="font-semibold text-sm text-gray-900">{ot.folio}</p>
                      <p className="text-xs text-gray-500">
                        {ot.activo?.nombre || ot.activo?.codigo || '—'} ·{' '}
                        {ot.fecha_programada ? formatDate(ot.fecha_programada) : 'Sin fecha'}
                      </p>
                    </div>
                    <Badge className={getEstadoOTColor(ot.estado)}>
                      {getEstadoOTLabel(ot.estado)}
                    </Badge>
                  </Link>
                </li>
              ))}
            </ul>
          )}
          <Link
            href="/dashboard/mis-ots"
            className="mt-3 text-sm font-medium text-pillado-green-600 hover:underline flex items-center gap-1"
          >
            Ver todas mis OTs <ArrowRight className="h-4 w-4" />
          </Link>
        </CardContent>
      </Card>

      {/* Acciones rápidas */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base">Acciones rápidas</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-2">
            <QuickLink href="/dashboard/mis-ots" icon={<ClipboardList className="h-4 w-4" />} label="Mis OTs" />
            <QuickLink href="/dashboard/activos" icon={<Wrench className="h-4 w-4" />} label="Equipos" />
            <QuickLink href="/dashboard/inventario" icon={<Package className="h-4 w-4" />} label="Inventario" />
            <QuickLink href="/dashboard/inventario/scanner" icon={<Camera className="h-4 w-4" />} label="Scanner QR" />
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
  accent?: 'amber'
}) {
  const colorClass = accent === 'amber' ? 'text-amber-600' : 'text-gray-900'
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

function QuickLink({
  href,
  icon,
  label,
}: {
  href: string
  icon: React.ReactNode
  label: string
}) {
  return (
    <Link
      href={href}
      className="rounded-md border border-gray-200 bg-white px-3 py-3 text-sm text-gray-700 text-center hover:bg-gray-50 hover:border-pillado-green-400 flex flex-col items-center gap-1"
    >
      {icon}
      <span>{label}</span>
    </Link>
  )
}
