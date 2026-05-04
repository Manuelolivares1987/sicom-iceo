'use client'

import Link from 'next/link'
import {
  Activity, AlertTriangle, BarChart3, Calendar, ClipboardList,
  FileSpreadsheet, Layers, Hammer, MapPin, ArrowRight, ListChecks,
} from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Spinner } from '@/components/ui/spinner'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useCalamaDashboard } from '@/hooks/use-calama'
import { CurvaSChart } from '@/components/calama/curva-s-chart'
import { EstadoBadge } from '@/components/calama/gantt-table'

export default function CalamaDashboardPage() {
  useRequireAuth()
  const { data, isLoading, error } = useCalamaDashboard()

  return (
    <div className="space-y-6">
      <div className="rounded-2xl bg-gradient-to-r from-amber-700 to-orange-600 p-6 text-white shadow-lg">
        <h1 className="text-2xl font-bold flex items-center gap-2">
          <Activity className="h-6 w-6" />
          Operacion Calama — Dashboard
        </h1>
        <p className="text-sm text-white/90 mt-1">
          Resumen ejecutivo de planificacion, OTs, avance y materiales.
        </p>
      </div>

      <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-2">
        <AccesoRapido href="/dashboard/operacion-calama/ots"             icon={<ClipboardList className="h-4 w-4" />} label="OTs" />
        <AccesoRapido href="/dashboard/operacion-calama/planificaciones" icon={<Layers className="h-4 w-4" />}        label="Planificaciones" />
        <AccesoRapido href="/dashboard/operacion-calama/importar"        icon={<FileSpreadsheet className="h-4 w-4" />} label="Importar Excel" />
      </div>

      {isLoading && (
        <div className="flex items-center gap-2 text-sm text-gray-500">
          <Spinner className="h-4 w-4" />
          Cargando KPIs…
        </div>
      )}
      {error && (
        <div className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">
          Error cargando dashboard: {error instanceof Error ? error.message : 'desconocido'}
        </div>
      )}

      {data && (
        <>
          {/* KPIs principales */}
          <div className="grid grid-cols-2 sm:grid-cols-4 lg:grid-cols-6 gap-3">
            <KPI title="Total OTs"             value={data.total_ots}             icon={<ClipboardList className="h-4 w-4" />} />
            <KPI title="OTs atrasadas"          value={data.ots_atrasadas}         tone={data.ots_atrasadas > 0 ? 'red' : 'gray'} icon={<AlertTriangle className="h-4 w-4" />} />
            <KPI title="No ejecutadas"          value={data.ots_no_ejecutadas}     tone={data.ots_no_ejecutadas > 0 ? 'amber' : 'gray'} icon={<AlertTriangle className="h-4 w-4" />} />
            <KPI title="Zonas intervenidas"     value={data.zonas_intervenidas}    icon={<MapPin className="h-4 w-4" />} />
            <KPI title="Materiales planificados" value={data.materiales_planificados} icon={<Hammer className="h-4 w-4" />} />
            <KPI title="Planificaciones"        value={data.total_planificaciones} icon={<Layers className="h-4 w-4" />} />
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
            <KPI title="Avance plan promedio" value={`${data.avance_planificado_promedio.toFixed(1)}%`} tone="indigo" icon={<BarChart3 className="h-4 w-4" />} />
            <KPI title="Avance real promedio" value={`${data.avance_real_promedio.toFixed(1)}%`}        tone="green" icon={<BarChart3 className="h-4 w-4" />} />
            <KPI
              title="Desviacion"
              value={`${data.desviacion >= 0 ? '+' : ''}${data.desviacion.toFixed(1)} pp`}
              tone={data.desviacion >= 0 ? 'green' : 'red'}
              icon={<BarChart3 className="h-4 w-4" />}
            />
          </div>

          {/* OTs por estado */}
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-base flex items-center gap-2">
                <ListChecks className="h-4 w-4" />
                OTs por estado
              </CardTitle>
            </CardHeader>
            <CardContent>
              {data.por_estado.length === 0 ? (
                <p className="text-sm text-gray-400">Sin OTs registradas.</p>
              ) : (
                <div className="flex flex-wrap gap-2">
                  {data.por_estado
                    .sort((a, b) => b.total - a.total)
                    .map((p) => (
                      <Link
                        key={p.estado}
                        href={`/dashboard/operacion-calama/ots?estado=${p.estado}`}
                        className="inline-flex items-center gap-2 rounded-lg border border-gray-200 bg-white px-3 py-1.5 hover:bg-gray-50"
                      >
                        <EstadoBadge estado={p.estado} />
                        <span className="text-sm font-semibold">{p.total}</span>
                      </Link>
                    ))}
                </div>
              )}
            </CardContent>
          </Card>

          {/* Curva S de la planificacion principal */}
          {data.planificacion_principal_id && (
            <Card>
              <CardHeader className="pb-2">
                <CardTitle className="text-base flex items-center gap-2">
                  <Calendar className="h-4 w-4" />
                  Curva S — {data.planificacion_principal_codigo}
                </CardTitle>
              </CardHeader>
              <CardContent>
                <CurvaSChart data={data.curva_s_principal} />
                <div className="mt-2 text-right">
                  <Link
                    href={`/dashboard/operacion-calama/ots?planificacionId=${data.planificacion_principal_id}`}
                    className="inline-flex items-center gap-1 text-xs text-indigo-600 hover:text-indigo-800"
                  >
                    Ver OTs de esta planificacion <ArrowRight className="h-3 w-3" />
                  </Link>
                </div>
              </CardContent>
            </Card>
          )}
        </>
      )}
    </div>
  )
}

function KPI({
  title, value, tone = 'gray', icon,
}: {
  title: string
  value: string | number
  tone?: 'gray' | 'green' | 'red' | 'amber' | 'indigo'
  icon?: React.ReactNode
}) {
  const colors: Record<string, string> = {
    gray: 'border-gray-200 text-gray-900',
    green: 'border-green-200 text-green-700 bg-green-50',
    red: 'border-red-200 text-red-700 bg-red-50',
    amber: 'border-amber-200 text-amber-700 bg-amber-50',
    indigo: 'border-indigo-200 text-indigo-700 bg-indigo-50',
  }
  return (
    <div className={`rounded-xl border bg-white p-3 ${colors[tone]}`}>
      <div className="flex items-center gap-1.5 text-xs font-medium uppercase opacity-80">
        {icon}
        {title}
      </div>
      <div className="text-2xl font-bold mt-1">{value}</div>
    </div>
  )
}

function AccesoRapido({ href, icon, label }: { href: string; icon: React.ReactNode; label: string }) {
  return (
    <Link
      href={href}
      className="flex items-center gap-2 rounded-lg border border-gray-200 bg-white px-3 py-2 text-sm hover:bg-amber-50 hover:border-amber-300"
    >
      {icon}
      <span className="font-medium">{label}</span>
      <ArrowRight className="h-3.5 w-3.5 ml-auto opacity-60" />
    </Link>
  )
}
