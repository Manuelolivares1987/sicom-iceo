'use client'

import Link from 'next/link'
import { Footprints, Plus, ClipboardCheck, AlertTriangle, Clock, TrendingUp } from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { cn } from '@/lib/utils'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { usePermissions } from '@/hooks/use-permissions'
import { useAuth } from '@/contexts/auth-context'
import { useGembaKpi, useGembaRecorridos, useGembaHallazgos, useGembaPlantillas } from '@/hooks/use-gemba'
import { plantillaDeRol, CADENCIA_LABEL, type GembaCadencia } from '@/lib/services/gemba'

const LUGAR_LABEL: Record<string, string> = { taller: 'Taller', faena: 'Faena' }

/** Cada cuántos días se espera el recorrido según su cadencia. */
const DIAS_CADENCIA: Record<GembaCadencia, number> = {
  diaria: 1, semanal: 7, quincenal: 14, mensual: 30,
}

const hoyIso = () => {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}

const diasEntre = (desdeIso: string, hastaIso: string): number => {
  const p = (s: string) => { const [y, m, d] = s.slice(0, 10).split('-').map(Number); return new Date(y, m - 1, d).getTime() }
  return Math.round((p(hastaIso) - p(desdeIso)) / 86_400_000)
}

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

  // ── ¿Le toca recorrer hoy? ────────────────────────────────────────────────
  // El recorrido del Jefe de Taller es DIARIO: sin un aviso, a la tercera
  // semana nadie lo abre. Se calcula contra su último recorrido, no contra un
  // programa aparte que habría que mantener.
  const { perfil } = useAuth()
  const { data: plantillas } = useGembaPlantillas()
  const miPlantilla = plantillaDeRol(plantillas, perfil?.rol)
  const miUltimo = (recorridos ?? []).find(
    (r) => r.plantilla_id === miPlantilla?.id && r.responsable_id === perfil?.id)
  const diasDesde = miUltimo ? diasEntre(miUltimo.fecha, hoyIso()) : null
  const cadencia = miPlantilla?.cadencia ?? null
  const toca = !!cadencia && puedeRecorrer &&
    (diasDesde === null || diasDesde >= DIAS_CADENCIA[cadencia])

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

      {/* ── Te toca recorrer ── */}
      {toca && (
        <Link href="/dashboard/prevencion/gemba/nuevo" className="block">
          <div className="flex items-center gap-3 rounded-lg border border-amber-300 bg-amber-50 p-4 transition-colors hover:bg-amber-100">
            <Footprints className="h-5 w-5 shrink-0 text-amber-600" />
            <div className="flex-1">
              <p className="text-sm font-semibold text-amber-900">
                {cadencia === 'diaria'
                  ? 'Todavía no has hecho el recorrido de hoy'
                  : `Te toca tu recorrido ${CADENCIA_LABEL[cadencia!].toLowerCase()}`}
              </p>
              <p className="text-xs text-amber-800">
                {diasDesde === null
                  ? 'Es tu primer recorrido con este checklist.'
                  : `Tu último recorrido fue hace ${diasDesde} día${diasDesde === 1 ? '' : 's'} (${miUltimo?.fecha}).`}
                {' '}{miPlantilla?.nombre}
              </p>
            </div>
            <span className="shrink-0 rounded bg-amber-600 px-3 py-1.5 text-xs font-semibold text-white">
              Iniciar
            </span>
          </div>
        </Link>
      )}

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
