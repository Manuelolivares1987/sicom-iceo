'use client'

import { useMemo, useState } from 'react'
import Link from 'next/link'
import { ArrowLeft, ArrowRight, Calendar, Layers, MapPin } from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Spinner } from '@/components/ui/spinner'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useCalamaResumenPlanificaciones, useCalamaCurvaSConteo } from '@/hooks/use-calama'
import { CurvaSConteoChart } from '@/components/calama/curva-s-chart'

type CurvaPreset = 'mes_actual' | 'mes_anterior' | 'trimestre' | 'acumulado' | 'personalizado'

const isoDate = (d: Date) => {
  const y = d.getFullYear(), m = String(d.getMonth() + 1).padStart(2, '0'), day = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${day}`
}

function rangoCurva(preset: CurvaPreset, fechaIni: string, fechaFin: string, personalDesde: string, personalHasta: string): { desde: string; hasta: string; label: string } {
  const hoy = new Date()
  switch (preset) {
    case 'mes_actual': {
      const d1 = new Date(hoy.getFullYear(), hoy.getMonth(), 1)
      const d2 = new Date(hoy.getFullYear(), hoy.getMonth() + 1, 0)
      return { desde: isoDate(d1), hasta: isoDate(d2), label: 'Mes actual' }
    }
    case 'mes_anterior': {
      const d1 = new Date(hoy.getFullYear(), hoy.getMonth() - 1, 1)
      const d2 = new Date(hoy.getFullYear(), hoy.getMonth(), 0)
      return { desde: isoDate(d1), hasta: isoDate(d2), label: 'Mes anterior' }
    }
    case 'trimestre': {
      const d2 = new Date(hoy)
      const d1 = new Date(hoy.getFullYear(), hoy.getMonth() - 2, 1)
      return { desde: isoDate(d1), hasta: isoDate(d2), label: 'Últ. 3 meses' }
    }
    case 'acumulado':
      return { desde: fechaIni, hasta: fechaFin, label: 'Acumulado' }
    case 'personalizado':
      return { desde: personalDesde || fechaIni, hasta: personalHasta || fechaFin, label: 'Personalizado' }
  }
}

export default function PlanificacionesPage() {
  useRequireAuth()
  const { data, isLoading, error } = useCalamaResumenPlanificaciones()

  return (
    <div className="space-y-4">
      <Link
        href="/dashboard/operacion-calama"
        className="inline-flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700"
      >
        <ArrowLeft className="h-4 w-4" />
        Volver al dashboard
      </Link>

      <div className="rounded-2xl bg-gradient-to-r from-amber-700 to-orange-600 p-6 text-white shadow-lg">
        <h1 className="text-2xl font-bold flex items-center gap-2">
          <Layers className="h-6 w-6" />
          Planificaciones Operacion Calama
        </h1>
        <p className="text-sm text-white/90 mt-1">
          {data?.length ?? 0} planificaciones registradas.
        </p>
      </div>

      {isLoading && (
        <div className="flex items-center gap-2 text-sm text-gray-500">
          <Spinner className="h-4 w-4" />
          Cargando…
        </div>
      )}
      {error && (
        <div className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">
          Error: {error instanceof Error ? error.message : 'desconocido'}
        </div>
      )}

      {data && data.length === 0 && (
        <Card>
          <CardContent className="p-6 text-center text-sm text-gray-400">
            No hay planificaciones aun. Importa un Excel desde{' '}
            <Link href="/dashboard/operacion-calama/importar" className="text-amber-600 hover:underline">
              esta pagina
            </Link>.
          </CardContent>
        </Card>
      )}

      {data && data.map((p) => (
        <PlanificacionCard key={p.id} p={p} />
      ))}
    </div>
  )
}

type PlanWithFaena = NonNullable<ReturnType<typeof useCalamaResumenPlanificaciones>['data']>[number]

function PlanificacionCard({ p }: { p: PlanWithFaena }) {
  const { data: serie } = useCalamaCurvaSConteo(p.id)
  const desviacion = Number(p.avance_real) - Number(p.avance_planificado)

  const [preset, setPreset] = useState<CurvaPreset>('acumulado')
  const [personalDesde, setPersonalDesde] = useState('')
  const [personalHasta, setPersonalHasta] = useState('')

  const rango = useMemo(
    () => rangoCurva(preset, p.fecha_inicio_plan, p.fecha_termino_plan, personalDesde, personalHasta),
    [preset, p.fecha_inicio_plan, p.fecha_termino_plan, personalDesde, personalHasta],
  )

  const serieFiltrada = useMemo(() => {
    if (!serie) return []
    return serie.filter((s) => s.fecha >= rango.desde && s.fecha <= rango.hasta)
  }, [serie, rango.desde, rango.hasta])

  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-base flex items-center justify-between">
          <span className="flex items-center gap-2">
            <span className="font-mono">{p.codigo}</span>
            <span className="text-gray-500 font-normal">— {p.nombre}</span>
          </span>
          <span className={`rounded-full px-3 py-0.5 text-xs font-semibold ${
            p.estado === 'finalizada' ? 'bg-green-100 text-green-700'
            : p.estado === 'en_curso' ? 'bg-amber-100 text-amber-700'
            : p.estado === 'cancelada' ? 'bg-gray-100 text-gray-500'
            : 'bg-slate-100 text-slate-700'
          }`}>
            {p.estado}
          </span>
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-3">
        <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3 text-xs">
          <Info icon={<MapPin className="h-3 w-3" />} label="Faena" value={p.faena?.codigo ?? '—'} />
          <Info icon={<Layers className="h-3 w-3" />} label="Linea" value={p.linea_negocio} mono />
          <Info icon={<Calendar className="h-3 w-3" />} label="Inicio plan" value={p.fecha_inicio_plan} />
          <Info icon={<Calendar className="h-3 w-3" />} label="Fin plan" value={p.fecha_termino_plan} />
          <Info label="Avance plan" value={`${Number(p.avance_planificado).toFixed(1)}%`} />
          <Info
            label="Avance real"
            value={`${Number(p.avance_real).toFixed(1)}%`}
            tone={desviacion >= 0 ? 'green' : 'red'}
          />
          <Info label="OTs totales" value={String(p.total_ots)} />
          <Info
            label="Desviacion"
            value={`${desviacion >= 0 ? '+' : ''}${desviacion.toFixed(1)} pp`}
            tone={desviacion >= 0 ? 'green' : 'red'}
          />
        </div>

        {serie && serie.length > 0 && (
          <div>
            <div className="flex items-center justify-between mb-1 flex-wrap gap-2">
              <div className="text-xs uppercase text-gray-500">
                Curva S — {rango.label} ({rango.desde} → {rango.hasta})
              </div>
              <div className="flex flex-wrap gap-1">
                {([
                  ['mes_actual',    'Mes actual'],
                  ['mes_anterior',  'Mes anterior'],
                  ['trimestre',     'Últ. 3 meses'],
                  ['acumulado',     'Acumulado'],
                  ['personalizado', 'Rango'],
                ] as Array<[CurvaPreset, string]>).map(([k, label]) => (
                  <button
                    key={k}
                    onClick={() => setPreset(k)}
                    className={`rounded-full px-2 py-0.5 text-[10px] font-medium transition ${
                      preset === k
                        ? 'bg-amber-600 text-white'
                        : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
                    }`}
                  >
                    {label}
                  </button>
                ))}
              </div>
            </div>
            {preset === 'personalizado' && (
              <div className="flex flex-wrap items-end gap-2 mb-2 text-[10px]">
                <div>
                  <label className="text-gray-500 block">Desde</label>
                  <input type="date" value={personalDesde} onChange={(e) => setPersonalDesde(e.target.value)}
                    min={p.fecha_inicio_plan} max={p.fecha_termino_plan}
                    className="rounded border border-gray-300 px-2 py-1" />
                </div>
                <div>
                  <label className="text-gray-500 block">Hasta</label>
                  <input type="date" value={personalHasta} onChange={(e) => setPersonalHasta(e.target.value)}
                    min={p.fecha_inicio_plan} max={p.fecha_termino_plan}
                    className="rounded border border-gray-300 px-2 py-1" />
                </div>
              </div>
            )}
            {serieFiltrada.length > 0 ? (
              <CurvaSConteoChart data={serieFiltrada} height={240} />
            ) : (
              <div className="rounded border border-dashed border-gray-200 p-4 text-center text-xs text-gray-400">
                Sin datos en el rango seleccionado.
              </div>
            )}
            <div className="mt-1 text-[10px] text-gray-500 leading-snug">
              <strong>Completitud</strong> = Finalizadas / Total &nbsp;·&nbsp;
              <strong>Real</strong> = (Finalizadas + En ejecución) / Total &nbsp;·&nbsp;
              <strong>Proyectado</strong> = (Finalizadas + En ejecución + Planificadas) / Total
            </div>
          </div>
        )}

        <div className="flex justify-end gap-2">
          <Link
            href={`/dashboard/operacion-calama/ots?planificacionId=${p.id}`}
            className="inline-flex items-center gap-1 rounded-lg border border-amber-200 bg-amber-50 px-3 py-1.5 text-xs text-amber-800 hover:bg-amber-100"
          >
            Ver OTs <ArrowRight className="h-3 w-3" />
          </Link>
        </div>
      </CardContent>
    </Card>
  )
}

function Info({
  label, value, mono, tone, icon,
}: {
  label: string; value: string; mono?: boolean
  tone?: 'green' | 'red'
  icon?: React.ReactNode
}) {
  const color = tone === 'green' ? 'text-green-700' : tone === 'red' ? 'text-red-700' : 'text-gray-900'
  return (
    <div>
      <div className="flex items-center gap-1 text-gray-500 uppercase text-[10px]">
        {icon}
        {label}
      </div>
      <div className={`${color} ${mono ? 'font-mono text-xs' : 'text-sm'} font-medium mt-0.5`}>{value}</div>
    </div>
  )
}
