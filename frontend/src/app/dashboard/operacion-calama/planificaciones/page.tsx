'use client'

import Link from 'next/link'
import { ArrowLeft, ArrowRight, Calendar, Layers, MapPin } from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Spinner } from '@/components/ui/spinner'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useCalamaResumenPlanificaciones, useCalamaCurvaSConteo } from '@/hooks/use-calama'
import { CurvaSConteoChart } from '@/components/calama/curva-s-chart'

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
            <div className="flex items-center justify-between mb-1">
              <div className="text-xs uppercase text-gray-500">Curva S — 3 métricas por conteo de OTs</div>
              <div className="text-[10px] text-gray-400">MIG34/35 + 46</div>
            </div>
            <CurvaSConteoChart data={serie} height={240} />
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
