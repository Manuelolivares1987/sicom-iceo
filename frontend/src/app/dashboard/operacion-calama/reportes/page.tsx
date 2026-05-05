'use client'

import { useMemo, useState } from 'react'
import Link from 'next/link'
import {
  ArrowLeft, BarChart3, AlertTriangle, ListChecks, Calendar, Layers, RefreshCw,
} from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Spinner } from '@/components/ui/spinner'
import { useRequireAuth } from '@/hooks/use-require-auth'
import {
  useEstadoPlanificacionOTs, useReporteAtrasos, useCalidadDatos, useReporteSemanal,
} from '@/hooks/use-calama-reportes'

type Tab = 'ejecutivo' | 'atrasos' | 'continuidad' | 'semanal' | 'calidad'

export default function ReportesCalamaPage() {
  useRequireAuth()
  const [tab, setTab] = useState<Tab>('ejecutivo')

  const { data: estados, isLoading: l1 } = useEstadoPlanificacionOTs()
  const { data: atrasos, isLoading: l2 } = useReporteAtrasos()
  const { data: calidad, isLoading: l3 } = useCalidadDatos()
  const { data: semanal, isLoading: l4 } = useReporteSemanal()

  const ejecutivo = useMemo(() => {
    if (!estados) return null
    const total = estados.length
    const noPlanif = estados.filter((e) => e.estado_planificacion === 'no_planificada').length
    const planif = estados.filter((e) => e.estado_planificacion === 'planificada').length
    const ejecutadas = estados.filter((e) => e.estado_planificacion === 'ejecutada').length
    const vencidas = estados.filter((e) => e.estado_planificacion === 'vencida').length
    const parciales = estados.filter((e) => e.estado_planificacion === 'parcial_sin_proxima_jornada').length
    const sumReal = estados.reduce((acc, e) => acc + Number(e.avance_pct ?? 0), 0)
    const sumExcel = estados.reduce((acc, e) => acc + Number(e.avance_excel_pct ?? 0), 0)
    return {
      total,
      noPlanif, planif, ejecutadas, vencidas, parciales,
      avanceReal: total > 0 ? Math.round((sumReal / total) * 10) / 10 : 0,
      avanceExcel: total > 0 ? Math.round((sumExcel / total) * 10) / 10 : 0,
      desviacion: total > 0 ? Math.round(((sumReal - sumExcel) / total) * 10) / 10 : 0,
    }
  }, [estados])

  const continuidad = useMemo(() => {
    if (!estados) return []
    return estados.filter((e) => e.total_jornadas > 1 || e.estado_planificacion === 'parcial_sin_proxima_jornada')
  }, [estados])

  return (
    <div className="space-y-4">
      <Link href="/dashboard/operacion-calama" className="inline-flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700">
        <ArrowLeft className="h-4 w-4" /> Panel Calama
      </Link>

      <div className="rounded-2xl bg-gradient-to-r from-amber-700 to-orange-600 p-6 text-white shadow-lg">
        <h1 className="text-2xl font-bold flex items-center gap-2">
          <BarChart3 className="h-6 w-6" /> Reportes Calama
        </h1>
        <p className="text-sm text-white/90 mt-1">
          Resumen ejecutivo, atrasos, continuidad multidia, plan semanal y calidad de datos.
        </p>
      </div>

      <div className="flex gap-1 border-b border-gray-200 overflow-x-auto">
        {([
          ['ejecutivo',    'Ejecutivo',     <BarChart3 className="h-4 w-4" key="i1" />],
          ['atrasos',      'Atrasos',       <AlertTriangle className="h-4 w-4" key="i2" />],
          ['continuidad',  'Continuidad',   <ListChecks className="h-4 w-4" key="i3" />],
          ['semanal',      'Semanal',       <Calendar className="h-4 w-4" key="i4" />],
          ['calidad',      'Calidad datos', <Layers className="h-4 w-4" key="i5" />],
        ] as Array<[Tab, string, React.ReactNode]>).map(([k, label, icon]) => (
          <button
            key={k} onClick={() => setTab(k)}
            className={`shrink-0 flex items-center gap-2 px-3 py-2 text-sm font-medium border-b-2 -mb-px ${
              tab === k ? 'border-amber-600 text-amber-700' : 'border-transparent text-gray-500 hover:text-gray-700'
            }`}
          >{icon}{label}</button>
        ))}
      </div>

      {tab === 'ejecutivo' && (
        <Card>
          <CardHeader className="pb-2"><CardTitle className="text-base">Resumen ejecutivo</CardTitle></CardHeader>
          <CardContent className="space-y-3">
            {l1 && <div className="flex items-center gap-2 text-sm text-gray-500"><Spinner className="h-4 w-4" /> Cargando…</div>}
            {ejecutivo && (
              <>
                <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
                  <KPI title="Avance Real"      value={`${ejecutivo.avanceReal}%`}      tone="green" />
                  <KPI title="Avance Excel"     value={`${ejecutivo.avanceExcel}%`} />
                  <KPI title="Desviacion"       value={`${ejecutivo.desviacion >= 0 ? '+' : ''}${ejecutivo.desviacion}pp`} tone={ejecutivo.desviacion >= 0 ? 'green' : 'red'} />
                  <KPI title="Total OTs reales" value={ejecutivo.total} />
                </div>
                <div className="grid grid-cols-2 sm:grid-cols-5 gap-2">
                  <KPI title="No planificadas" value={ejecutivo.noPlanif}    tone={ejecutivo.noPlanif > 0 ? 'amber' : 'gray'} />
                  <KPI title="Planificadas"    value={ejecutivo.planif} />
                  <KPI title="Ejecutadas"      value={ejecutivo.ejecutadas}  tone="green" />
                  <KPI title="Vencidas"        value={ejecutivo.vencidas}    tone={ejecutivo.vencidas > 0 ? 'red' : 'gray'} />
                  <KPI title="Parciales s/ jornada" value={ejecutivo.parciales} tone={ejecutivo.parciales > 0 ? 'amber' : 'gray'} />
                </div>
                <p className="text-xs text-gray-500">
                  * Estado de planificacion calculado desde calama_plan_semanal_ots (no desde calama_ordenes_trabajo.estado).
                </p>
              </>
            )}
          </CardContent>
        </Card>
      )}

      {tab === 'atrasos' && (
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-base flex items-center gap-2">
              <AlertTriangle className="h-4 w-4 text-red-600" />
              OTs con jornada vencida ({atrasos?.length ?? 0})
            </CardTitle>
          </CardHeader>
          <CardContent className="overflow-x-auto">
            {l2 && <Spinner className="h-4 w-4" />}
            {atrasos && atrasos.length === 0 ? (
              <p className="text-sm text-gray-400">Sin atrasos. ✅</p>
            ) : atrasos && (
              <table className="w-full text-xs">
                <thead>
                  <tr className="border-b bg-gray-50 text-left uppercase text-gray-500">
                    <th className="px-2 py-2">OT</th>
                    <th className="px-2 py-2">Lugar</th>
                    <th className="px-2 py-2">Tarea</th>
                    <th className="px-2 py-2">Fecha</th>
                    <th className="px-2 py-2 text-right">Atraso</th>
                    <th className="px-2 py-2">Responsable</th>
                    <th className="px-2 py-2 text-right">Avance</th>
                    <th className="px-2 py-2">Comentario</th>
                  </tr>
                </thead>
                <tbody>
                  {atrasos.slice(0, 100).map((a) => (
                    <tr key={a.plan_ot_id} className={`border-b ${a.dias_atraso > 7 ? 'bg-red-50' : ''}`}>
                      <td className="px-2 py-1 font-mono">{a.folio.replace(/^OT_[^_]+_(?:[^_]+_)+/, '')}</td>
                      <td className="px-2 py-1">{a.lugar_fisico ?? '—'}</td>
                      <td className="px-2 py-1 max-w-xs truncate" title={a.titulo}>{a.titulo}</td>
                      <td className="px-2 py-1">{a.fecha_jornada}</td>
                      <td className="px-2 py-1 text-right font-mono font-bold text-red-700">
                        {a.dias_atraso} d
                      </td>
                      <td className="px-2 py-1">{a.responsable_nombre ?? '—'}</td>
                      <td className="px-2 py-1 text-right font-mono">{a.avance_actual.toFixed(0)}%</td>
                      <td className="px-2 py-1 max-w-xs truncate" title={a.ultimo_comentario ?? ''}>{a.ultimo_comentario ?? '—'}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </CardContent>
        </Card>
      )}

      {tab === 'continuidad' && (
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-base flex items-center gap-2">
              <ListChecks className="h-4 w-4" />
              OTs con multidia o requieren replanificacion ({continuidad.length})
            </CardTitle>
          </CardHeader>
          <CardContent className="overflow-x-auto">
            {!l1 && continuidad.length === 0 && (
              <p className="text-sm text-gray-400">No hay OTs con multidia ni parciales sin proxima jornada.</p>
            )}
            {continuidad.length > 0 && (
              <table className="w-full text-xs">
                <thead>
                  <tr className="border-b bg-gray-50 text-left uppercase text-gray-500">
                    <th className="px-2 py-2">OT</th>
                    <th className="px-2 py-2">Estado planif.</th>
                    <th className="px-2 py-2 text-right">Total jornadas</th>
                    <th className="px-2 py-2 text-right">Futuras</th>
                    <th className="px-2 py-2 text-right">Hoy</th>
                    <th className="px-2 py-2 text-right">Vencidas</th>
                    <th className="px-2 py-2 text-right">Avance Real</th>
                    <th className="px-2 py-2">Próxima</th>
                    <th className="px-2 py-2">Última</th>
                  </tr>
                </thead>
                <tbody>
                  {continuidad.slice(0, 200).map((c) => (
                    <tr key={c.ot_id} className={`border-b ${
                      c.estado_planificacion === 'parcial_sin_proxima_jornada' ? 'bg-amber-50' :
                      c.estado_planificacion === 'vencida' ? 'bg-red-50' : ''
                    }`}>
                      <td className="px-2 py-1 font-mono">{c.folio.replace(/^OT_[^_]+_(?:[^_]+_)+/, '')}</td>
                      <td className="px-2 py-1 text-[10px]">{c.estado_planificacion.replaceAll('_', ' ')}</td>
                      <td className="px-2 py-1 text-right font-mono">{c.total_jornadas}</td>
                      <td className="px-2 py-1 text-right font-mono text-green-700">{c.jornadas_futuras}</td>
                      <td className="px-2 py-1 text-right font-mono">{c.jornadas_hoy}</td>
                      <td className="px-2 py-1 text-right font-mono text-red-700">{c.jornadas_vencidas}</td>
                      <td className="px-2 py-1 text-right font-mono">{c.avance_pct.toFixed(0)}%</td>
                      <td className="px-2 py-1">{c.proxima_fecha_planificada ?? '—'}</td>
                      <td className="px-2 py-1">{c.ultima_fecha_planificada ?? '—'}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </CardContent>
        </Card>
      )}

      {tab === 'semanal' && (
        <Card>
          <CardHeader className="pb-2"><CardTitle className="text-base">Reporte semanal</CardTitle></CardHeader>
          <CardContent className="overflow-x-auto">
            {l4 && <Spinner className="h-4 w-4" />}
            {semanal && semanal.length === 0 && (
              <p className="text-sm text-gray-400">Aun no hay planes semanales creados.</p>
            )}
            {semanal && semanal.length > 0 && (
              <table className="w-full text-xs">
                <thead>
                  <tr className="border-b bg-gray-50 text-left uppercase text-gray-500">
                    <th className="px-2 py-2">Plan</th>
                    <th className="px-2 py-2">Semana</th>
                    <th className="px-2 py-2">Estado</th>
                    <th className="px-2 py-2 text-right">Jornadas</th>
                    <th className="px-2 py-2 text-right">Ejec.</th>
                    <th className="px-2 py-2 text-right">Pend.</th>
                    <th className="px-2 py-2 text-right">No ejec.</th>
                    <th className="px-2 py-2 text-right">OTs</th>
                    <th className="px-2 py-2 text-right">Hs plan</th>
                    <th className="px-2 py-2 text-right">Hs reales</th>
                    <th className="px-2 py-2 text-right">Cumpl. %</th>
                  </tr>
                </thead>
                <tbody>
                  {semanal.map((s) => (
                    <tr key={s.plan_semanal_id} className="border-b">
                      <td className="px-2 py-1 font-mono">{s.planificacion}</td>
                      <td className="px-2 py-1">{s.fecha_inicio_semana} → {s.fecha_fin_semana}</td>
                      <td className="px-2 py-1">{s.estado_plan}</td>
                      <td className="px-2 py-1 text-right font-mono">{s.jornadas_total}</td>
                      <td className="px-2 py-1 text-right font-mono text-green-700">{s.jornadas_ejecutadas}</td>
                      <td className="px-2 py-1 text-right font-mono">{s.jornadas_pendientes}</td>
                      <td className="px-2 py-1 text-right font-mono text-red-700">{s.jornadas_no_ejecutadas}</td>
                      <td className="px-2 py-1 text-right font-mono">{s.ots_distintas}</td>
                      <td className="px-2 py-1 text-right font-mono">{Number(s.horas_planificadas).toFixed(0)}</td>
                      <td className="px-2 py-1 text-right font-mono">{Number(s.horas_reales).toFixed(0)}</td>
                      <td className="px-2 py-1 text-right font-mono font-bold">{Number(s.cumplimiento_pct).toFixed(0)}%</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </CardContent>
        </Card>
      )}

      {tab === 'calidad' && (
        <Card>
          <CardHeader className="pb-2"><CardTitle className="text-base">Calidad de datos</CardTitle></CardHeader>
          <CardContent>
            {l3 && <Spinner className="h-4 w-4" />}
            {calidad && (
              <ul className="space-y-1 text-sm">
                {calidad.map((c) => (
                  <li key={c.check_id} className={`flex items-center gap-3 px-3 py-2 rounded-lg ${
                    c.valor === 0 ? 'bg-green-50 border border-green-200' :
                    c.valor > 10 ? 'bg-red-50 border border-red-200' :
                    'bg-amber-50 border border-amber-200'
                  }`}>
                    <span className={`font-mono text-xl font-bold w-12 text-right ${
                      c.valor === 0 ? 'text-green-700' :
                      c.valor > 10 ? 'text-red-700' : 'text-amber-700'
                    }`}>{c.valor}</span>
                    <span className="flex-1">
                      <div className="font-medium text-gray-900">{c.check_id.replaceAll('_',' ')}</div>
                      <div className="text-xs text-gray-600">{c.descripcion}</div>
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </CardContent>
        </Card>
      )}
    </div>
  )
}

function KPI({ title, value, tone = 'gray' }: { title: string; value: string | number; tone?: 'gray' | 'green' | 'red' | 'amber' }) {
  const colors: Record<string, string> = {
    gray: 'border-gray-200 text-gray-900',
    green: 'border-green-200 text-green-700 bg-green-50',
    red: 'border-red-200 text-red-700 bg-red-50',
    amber: 'border-amber-200 text-amber-700 bg-amber-50',
  }
  return (
    <div className={`rounded-xl border bg-white p-3 ${colors[tone]}`}>
      <div className="text-[10px] font-medium uppercase opacity-80">{title}</div>
      <div className="text-2xl font-bold mt-1">{value}</div>
    </div>
  )
}
