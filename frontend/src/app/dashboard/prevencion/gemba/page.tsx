'use client'

import Link from 'next/link'
import { Footprints, Plus, ClipboardCheck, AlertTriangle, Clock, TrendingUp } from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { cn } from '@/lib/utils'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { usePermissions } from '@/hooks/use-permissions'
import { useGembaKpi, useGembaRecorridos, useGembaHallazgos } from '@/hooks/use-gemba'

const LUGAR_LABEL: Record<string, string> = { taller: 'Taller', faena: 'Faena' }

export default function GembaPage() {
  useRequireAuth()
  // [MIG288] La base rechaza el recorrido de quien no tiene el permiso: si el
  // botón igual apareciera, el usuario llenaría el checklist completo para
  // recibir un error al guardar.
  const { canCreate } = usePermissions()
  const puedeRecorrer = canCreate('prevencion')

  const { data: kpi, isLoading: loadingKpi } = useGembaKpi()
  const { data: recorridos, isLoading } = useGembaRecorridos(50)
  const { data: hallazgosAbiertos } = useGembaHallazgos(undefined, true)

  if (isLoading || loadingKpi) {
    return (
      <div className="flex h-64 items-center justify-center">
        <Spinner className="h-8 w-8" />
      </div>
    )
  }

  return (
    <div className="space-y-6">
      {/* ── Header ── */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-gray-900 flex items-center gap-2">
            <Footprints className="h-7 w-7 text-amber-500" />
            Recorridos Gemba
          </h1>
          <p className="text-sm text-gray-500 mt-1">
            Liderazgo visible en terreno — taller y faenas · Metodología Lean
          </p>
        </div>
        {puedeRecorrer && (
          <Link href="/dashboard/prevencion/gemba/nuevo">
            <Button>
              <Plus className="h-4 w-4" />
              Nuevo recorrido
            </Button>
          </Link>
        )}
      </div>

      {/* ── KPIs ── */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <div className="rounded-lg border border-gray-200 bg-gray-50 p-4">
          <div className="flex items-center justify-between">
            <span className="text-xs font-medium text-gray-500">Recorridos este mes</span>
            <ClipboardCheck className="h-4 w-4 text-gray-500" />
          </div>
          <div className="mt-2 text-3xl font-bold text-gray-900">{kpi?.recorridos_mes ?? 0}</div>
        </div>
        <div
          className={cn(
            'rounded-lg border p-4',
            (kpi?.hallazgos_abiertos ?? 0) > 0
              ? 'border-amber-200 bg-amber-50'
              : 'border-green-200 bg-green-50'
          )}
        >
          <div className="flex items-center justify-between">
            <span className="text-xs font-medium text-gray-600">Hallazgos abiertos</span>
            <AlertTriangle className="h-4 w-4 text-amber-500" />
          </div>
          <div className="mt-2 text-3xl font-bold text-gray-900">{kpi?.hallazgos_abiertos ?? 0}</div>
        </div>
        <div
          className={cn(
            'rounded-lg border p-4',
            (kpi?.hallazgos_vencidos ?? 0) > 0
              ? 'border-red-200 bg-red-50'
              : 'border-green-200 bg-green-50'
          )}
        >
          <div className="flex items-center justify-between">
            <span className="text-xs font-medium text-gray-600">Acciones vencidas</span>
            <Clock className="h-4 w-4 text-red-500" />
          </div>
          <div className="mt-2 text-3xl font-bold text-gray-900">{kpi?.hallazgos_vencidos ?? 0}</div>
        </div>
        <div className="rounded-lg border border-gray-200 bg-gray-50 p-4">
          <div className="flex items-center justify-between">
            <span className="text-xs font-medium text-gray-500">% cumplimiento (90d)</span>
            <TrendingUp className="h-4 w-4 text-gray-500" />
          </div>
          <div className="mt-2 text-3xl font-bold text-gray-900">
            {kpi?.pct_cumplimiento_90d != null ? `${kpi.pct_cumplimiento_90d}%` : '—'}
          </div>
        </div>
      </div>

      {/* ── Listado de recorridos ── */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base">Recorridos realizados</CardTitle>
        </CardHeader>
        <CardContent className="overflow-x-auto">
          {recorridos && recorridos.length > 0 ? (
            <table className="w-full text-xs">
              <thead>
                <tr className="border-b text-left text-gray-500 uppercase">
                  <th className="px-2 py-2">Fecha</th>
                  <th className="px-2 py-2">Checklist</th>
                  <th className="px-2 py-2">Lugar</th>
                  <th className="px-2 py-2">Responsable</th>
                  <th className="px-2 py-2 text-right">% Cumpl.</th>
                  <th className="px-2 py-2 text-right">No cumple</th>
                  <th className="px-2 py-2">Estado</th>
                </tr>
              </thead>
              <tbody>
                {recorridos.map((r) => (
                  <tr key={r.id} className="border-b hover:bg-gray-50">
                    <td className="px-2 py-2 whitespace-nowrap">
                      <Link
                        href={`/dashboard/prevencion/gemba/${r.id}`}
                        className="font-medium text-blue-600 hover:underline"
                      >
                        {r.fecha}
                      </Link>
                    </td>
                    <td className="px-2 py-2">{r.plantilla?.nombre ?? '—'}</td>
                    <td className="px-2 py-2 whitespace-nowrap">
                      {LUGAR_LABEL[r.lugar_tipo]}
                      {r.faena?.nombre ? ` · ${r.faena.nombre}` : ''}
                      {r.sector ? ` · ${r.sector}` : ''}
                    </td>
                    <td className="px-2 py-2 text-gray-600">
                      {r.responsable?.nombre_completo ?? r.responsable?.email ?? '—'}
                    </td>
                    <td className="px-2 py-2 text-right font-semibold">
                      {r.resumen?.pct_cumplimiento != null ? `${r.resumen.pct_cumplimiento}%` : '—'}
                    </td>
                    <td
                      className={cn(
                        'px-2 py-2 text-right font-semibold',
                        (r.resumen?.no_cumple ?? 0) > 0 ? 'text-red-600' : 'text-gray-600'
                      )}
                    >
                      {r.resumen?.no_cumple ?? 0}
                    </td>
                    <td className="px-2 py-2">
                      <span
                        className={cn(
                          'inline-block rounded px-2 py-0.5 text-xs',
                          r.estado === 'cerrado'
                            ? 'bg-green-100 text-green-700'
                            : 'bg-amber-100 text-amber-700'
                        )}
                      >
                        {r.estado === 'cerrado' ? 'Cerrado' : 'En curso'}
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          ) : (
            <div className="py-6 text-sm text-gray-400">
              <p>Aún no hay recorridos registrados.</p>
              <p className="mt-2">
                Inicia el primero con &quot;Nuevo recorrido&quot;: elige el checklist según el cargo
                (Prevencionista, Jefe de Taller o Jefe de Operaciones) y el lugar (taller o faena).
              </p>
            </div>
          )}
        </CardContent>
      </Card>

      {/* ── Hallazgos abiertos (plan de acción global) ── */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base flex items-center gap-2">
            <AlertTriangle className="h-5 w-5 text-amber-500" />
            Plan de acción — hallazgos abiertos ({hallazgosAbiertos?.length ?? 0})
          </CardTitle>
        </CardHeader>
        <CardContent className="overflow-x-auto">
          {hallazgosAbiertos && hallazgosAbiertos.length > 0 ? (
            <table className="w-full text-xs">
              <thead>
                <tr className="border-b text-left text-gray-500 uppercase">
                  <th className="px-2 py-2">Recorrido</th>
                  <th className="px-2 py-2">Hallazgo</th>
                  <th className="px-2 py-2">Acción correctiva</th>
                  <th className="px-2 py-2">Responsable</th>
                  <th className="px-2 py-2">Compromiso</th>
                  <th className="px-2 py-2">Estado</th>
                </tr>
              </thead>
              <tbody>
                {hallazgosAbiertos.map((h) => {
                  const vencido =
                    h.fecha_compromiso && new Date(h.fecha_compromiso) < new Date()
                  return (
                    <tr key={h.id} className="border-b hover:bg-gray-50">
                      <td className="px-2 py-2 whitespace-nowrap">
                        <Link
                          href={`/dashboard/prevencion/gemba/${h.recorrido_id}`}
                          className="text-blue-600 hover:underline"
                        >
                          {h.recorrido?.fecha ?? '—'}
                        </Link>
                      </td>
                      <td className="px-2 py-2 max-w-md">{h.descripcion}</td>
                      <td className="px-2 py-2 max-w-md text-gray-600">
                        {h.accion_correctiva || '—'}
                      </td>
                      <td className="px-2 py-2">
                        {h.responsable?.nombre_completo ?? h.responsable_texto ?? '—'}
                      </td>
                      <td className={cn('px-2 py-2 whitespace-nowrap', vencido && 'font-semibold text-red-600')}>
                        {h.fecha_compromiso ?? '—'}
                      </td>
                      <td className="px-2 py-2">
                        <span
                          className={cn(
                            'inline-block rounded px-2 py-0.5 text-xs',
                            h.estado === 'en_proceso'
                              ? 'bg-blue-100 text-blue-700'
                              : 'bg-amber-100 text-amber-700'
                          )}
                        >
                          {h.estado === 'en_proceso' ? 'En proceso' : 'Abierta'}
                        </span>
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          ) : (
            <p className="text-sm text-gray-400">Sin hallazgos pendientes — plan de acción al día</p>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
