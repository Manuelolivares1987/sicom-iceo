'use client'

import Link from 'next/link'
import {
  Activity, AlertTriangle, BarChart3, Calendar, ClipboardList,
  FileSpreadsheet, Layers, Hammer, MapPin, ArrowRight, ListChecks,
} from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Spinner } from '@/components/ui/spinner'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useCalamaDashboard, useCalamaPlanificaciones, useCalamaOTs } from '@/hooks/use-calama'
import { CurvaSChart } from '@/components/calama/curva-s-chart'
import { EstadoBadge } from '@/components/calama/gantt-table'
import { proyectarTermino, semaforoAvance, zonaCodeFromFolio, type CalamaOT } from '@/lib/services/calama'
import { useMemo } from 'react'

export default function CalamaDashboardPage() {
  useRequireAuth()
  const { data, isLoading, error } = useCalamaDashboard()
  const { data: planificaciones } = useCalamaPlanificaciones()
  const { data: ots } = useCalamaOTs()

  // Avance general calculado SOLO desde tareas reales (excluye estaciones via folio).
  const control = useMemo(() => {
    const tareas = (ots ?? []).filter((o) => {
      const m = /(\d+)\.(\d+)\.(\d+)$/.exec(o.folio)
      if (!m) return false
      // Excluir estaciones .0.0 (no debería haber OTs así, pero defensivo).
      return !(m[2] === '0' && m[3] === '0')
    })
    if (tareas.length === 0) {
      return null
    }
    const sumReal = tareas.reduce((acc, o) => acc + Number(o.avance_pct ?? 0), 0)
    const sumExcel = tareas.reduce((acc, o) => acc + Number((o as { avance_excel_pct?: number }).avance_excel_pct ?? 0), 0)
    const realProm = sumReal / tareas.length
    const excelProm = sumExcel / tareas.length
    const desviacion = realProm - excelProm
    const total = tareas.length
    const al100 = tareas.filter((o) => Number(o.avance_pct ?? 0) >= 100).length
    const parciales = tareas.filter((o) => {
      const a = Number(o.avance_pct ?? 0); return a > 0 && a < 100
    }).length
    const sinAvance = tareas.filter((o) => Number(o.avance_pct ?? 0) === 0).length

    // Fecha base: la más temprana de fecha_programada
    const fechas = tareas.map((o) => o.fecha_programada).filter(Boolean).sort()
    const fechaBase = fechas[0] ?? null
    const proyeccion = proyectarTermino(realProm, fechaBase)

    // Estaciones críticas: agrupar por zona (codigo X.0.0) y sacar avance promedio
    const porZona = new Map<string, CalamaOT[]>()
    for (const o of tareas) {
      const m = /(\d+)\.\d+\.\d+$/.exec(o.folio)
      if (!m) continue
      const z = `${m[1]}.0.0`
      const arr = porZona.get(z) ?? []
      arr.push(o)
      porZona.set(z, arr)
    }
    const estacionesCriticas = Array.from(porZona.entries())
      .map(([codigo, list]) => ({
        codigo,
        avancePromedio: list.reduce((a, o) => a + Number(o.avance_pct ?? 0), 0) / list.length,
        total: list.length,
      }))
      .filter((e) => e.avancePromedio < 40)
      .sort((a, b) => a.avancePromedio - b.avancePromedio)
      .slice(0, 5)

    return {
      total, al100, parciales, sinAvance,
      avanceRealPromedio: Math.round(realProm * 10) / 10,
      avanceExcelPromedio: Math.round(excelProm * 10) / 10,
      desviacion: Math.round(desviacion * 10) / 10,
      proyeccion,
      estacionesCriticas,
      fechaBase,
    }
  }, [ots])
  void planificaciones // disponible para integraciones futuras

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

      {/* Control de avance — calculado solo desde tareas (no estaciones) */}
      {control && (
        <Card className="border-amber-300 bg-amber-50/50">
          <CardHeader className="pb-2">
            <CardTitle className="text-base flex items-center gap-2">
              <BarChart3 className="h-4 w-4" /> Control de avance del proyecto
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
              <div className="rounded-lg bg-white border border-gray-200 p-3 text-center">
                <div className="text-[10px] uppercase text-gray-500">Avance Real</div>
                <div className="font-mono text-3xl font-bold text-gray-900 mt-0.5">
                  {control.avanceRealPromedio.toFixed(1)}<span className="text-base">%</span>
                </div>
                <div className="text-[10px] text-gray-500 mt-0.5">{control.total} tareas</div>
              </div>
              <div className="rounded-lg bg-white border border-gray-200 p-3 text-center">
                <div className="text-[10px] uppercase text-gray-500">Avance Excel/base</div>
                <div className="font-mono text-3xl font-semibold text-gray-600 mt-0.5">
                  {control.avanceExcelPromedio.toFixed(1)}<span className="text-base">%</span>
                </div>
                <div className="text-[10px] text-gray-500 mt-0.5">desde Analisi col C</div>
              </div>
              <div className={`rounded-lg bg-white border p-3 text-center ${
                control.desviacion >= 0 ? 'border-green-200' : 'border-red-200'
              }`}>
                <div className="text-[10px] uppercase text-gray-500">Desviacion</div>
                <div className={`font-mono text-3xl font-semibold mt-0.5 ${
                  control.desviacion >= 0 ? 'text-green-700' : 'text-red-700'
                }`}>
                  {control.desviacion >= 0 ? '+' : ''}{control.desviacion.toFixed(1)}<span className="text-base">pp</span>
                </div>
              </div>
              <div className="rounded-lg bg-white border border-gray-200 p-3 text-center">
                <div className="text-[10px] uppercase text-gray-500">Proyeccion termino</div>
                {control.proyeccion.fechaEstimadaTermino ? (
                  <>
                    <div className="font-mono text-base font-bold text-gray-900 mt-0.5">{control.proyeccion.fechaEstimadaTermino}</div>
                    <div className="text-[10px] text-gray-500 mt-0.5">{control.proyeccion.diasRestantesEstimados} dias restantes</div>
                  </>
                ) : (
                  <div className="text-xs text-gray-500 mt-2">{control.proyeccion.mensaje ?? '—'}</div>
                )}
              </div>
            </div>

            <div className="grid grid-cols-3 gap-2 text-xs">
              <div className="rounded bg-green-100 px-2 py-1 text-green-800">
                <div className="text-[10px] uppercase">Al 100%</div>
                <div className="text-lg font-bold">{control.al100}</div>
              </div>
              <div className="rounded bg-amber-100 px-2 py-1 text-amber-800">
                <div className="text-[10px] uppercase">Parciales</div>
                <div className="text-lg font-bold">{control.parciales}</div>
              </div>
              <div className="rounded bg-gray-100 px-2 py-1 text-gray-700">
                <div className="text-[10px] uppercase">Sin avance</div>
                <div className="text-lg font-bold">{control.sinAvance}</div>
              </div>
            </div>

            {control.estacionesCriticas.length > 0 && (
              <div className="rounded border border-red-200 bg-white p-2 text-xs">
                <div className="font-semibold text-red-800 mb-1 flex items-center gap-1">
                  <AlertTriangle className="h-3.5 w-3.5" />
                  Estaciones criticas (avance &lt; 40%)
                </div>
                <ul className="space-y-0.5">
                  {control.estacionesCriticas.map((e) => {
                    const sem = semaforoAvance(e.avancePromedio)
                    return (
                      <li key={e.codigo} className="flex items-center gap-2">
                        <span className={`h-2 w-2 rounded-full ${
                          sem === 'verde' ? 'bg-green-500' : sem === 'amarillo' ? 'bg-amber-500' : 'bg-red-500'
                        }`} />
                        <span className="font-mono text-gray-600 w-14">{e.codigo}</span>
                        <span className="font-mono font-bold w-12">{e.avancePromedio.toFixed(1)}%</span>
                        <span className="text-gray-500">{e.total} tareas</span>
                      </li>
                    )
                  })}
                </ul>
              </div>
            )}

            <p className="text-[10px] text-gray-500">
              * Avance por estacion y proyecto se calcula como promedio simple de tareas hijas (no se lee la columna B ni el % de filas .0.0).
            </p>
          </CardContent>
        </Card>
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
