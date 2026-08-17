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
import { plantillasDeRol, CADENCIA_LABEL, DIAS_CADENCIA } from '@/lib/services/gemba'

const LUGAR_LABEL: Record<string, string> = { taller: 'Taller', faena: 'Faena' }

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
  // [MIG291] Prevencion lleva DOS checklists (caminata diaria e inspeccion
  // mensual): el aviso se calcula por checklist, no por persona.
  const pendientes = (puedeRecorrer ? plantillasDeRol(plantillas, perfil?.rol) : [])
    .filter((p) => p.cadencia)
    .map((p) => {
      const ultimo = (recorridos ?? []).find(
        (r) => r.plantilla_id === p.id && r.responsable_id === perfil?.id)
      const dias = ultimo ? diasEntre(ultimo.fecha, hoyIso()) : null
      return { plantilla: p, ultimo, dias }
    })
    .filter((x) => x.dias === null || x.dias >= DIAS_CADENCIA[x.plantilla.cadencia!])

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
        <div className="flex gap-2">
          <Link href="/dashboard/gemba/reporte" className="flex-1 sm:flex-none">
            <Button variant="outline" className="w-full">
              <TrendingUp className="h-4 w-4" />
              Avance
            </Button>
          </Link>
          {puedeRecorrer && (
            <Link href="/dashboard/gemba/nuevo" className="flex-1 sm:flex-none">
              <Button className="w-full">
                <Plus className="h-4 w-4" />
                Nuevo recorrido
              </Button>
            </Link>
          )}
        </div>
      </div>

      {/* ── Te toca recorrer ── */}
      {pendientes.map(({ plantilla, ultimo, dias }) => (
        <Link key={plantilla.id} className="block"
              href={`/dashboard/gemba/nuevo?plantilla=${plantilla.id}`}>
          <div className="flex items-center gap-3 rounded-lg border border-amber-300 bg-amber-50 p-4 transition-colors hover:bg-amber-100">
            <Footprints className="h-5 w-5 shrink-0 text-amber-600" />
            <div className="flex-1">
              <p className="text-sm font-semibold text-amber-900">
                {plantilla.cadencia === 'diaria'
                  ? 'Todavía no has hecho el recorrido de hoy'
                  : `Te toca tu recorrido ${CADENCIA_LABEL[plantilla.cadencia!].toLowerCase()}`}
              </p>
              <p className="text-xs text-amber-800">
                {plantilla.nombre}.{' '}
                {dias === null
                  ? 'Es tu primer recorrido con este checklist.'
                  : `El último fue hace ${dias} día${dias === 1 ? '' : 's'} (${ultimo?.fecha}).`}
              </p>
            </div>
            <span className="shrink-0 rounded bg-amber-600 px-3 py-1.5 text-xs font-semibold text-white">
              Iniciar
            </span>
          </div>
        </Link>
      ))}

      {/* ── KPIs ── */}
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
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
        <CardContent>
          {recorridos && recorridos.length > 0 ? (
            <ul className="divide-y divide-gray-100">
              {recorridos.map((r) => (
                <li key={r.id}>
                  <Link href={`/dashboard/gemba/${r.id}`}
                        className="-mx-2 flex items-center gap-3 rounded-lg px-2 py-3 hover:bg-gray-50">
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-sm font-medium text-gray-800">
                        {r.plantilla?.nombre ?? 'Recorrido'}
                      </p>
                      <p className="truncate text-[11px] text-gray-500">
                        {r.fecha} · {LUGAR_LABEL[r.lugar_tipo]}
                        {r.faena?.nombre ? ` · ${r.faena.nombre}` : ''}
                        {r.sector ? ` · ${r.sector}` : ''}
                      </p>
                      <p className="truncate text-[11px] text-gray-400">
                        {r.responsable?.nombre_completo ?? r.responsable?.email ?? 'Sin responsable'}
                      </p>
                    </div>
                    <div className="shrink-0 text-right">
                      <p className="text-base font-bold leading-none text-gray-900">
                        {r.resumen?.pct_cumplimiento != null ? `${r.resumen.pct_cumplimiento}%` : '—'}
                      </p>
                      {(r.resumen?.no_cumple ?? 0) > 0 && (
                        <p className="text-[11px] font-semibold text-red-600">
                          {r.resumen!.no_cumple} no cumple
                        </p>
                      )}
                      <span className={cn('mt-1 inline-block rounded px-1.5 py-0.5 text-[10px] font-semibold',
                        r.estado === 'cerrado'
                          ? 'bg-green-100 text-green-700'
                          : 'bg-amber-100 text-amber-700')}>
                        {r.estado === 'cerrado' ? 'Cerrado' : 'En curso'}
                      </span>
                    </div>
                  </Link>
                </li>
              ))}
            </ul>
          ) : (
            <div className="py-6 text-sm text-gray-400">
              <p>Aún no hay recorridos registrados.</p>
              <p className="mt-2">
                Inicia el primero con &quot;Nuevo recorrido&quot;: elige el checklist según el cargo
                (Prevención, Jefe de Taller o Jefe de Operaciones) y el lugar (taller o faena).
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
        <CardContent>
          {hallazgosAbiertos && hallazgosAbiertos.length > 0 ? (
            <ul className="space-y-2">
              {hallazgosAbiertos.map((h) => {
                const vencido = !!h.fecha_compromiso &&
                  h.fecha_compromiso < new Date().toISOString().slice(0, 10)
                return (
                  <li key={h.id}>
                    <Link href={`/dashboard/gemba/${h.recorrido_id}`}
                          className={cn('block rounded-lg border p-3 hover:bg-gray-50',
                            vencido ? 'border-red-200 bg-red-50/50' : 'border-gray-200')}>
                      <div className="flex items-start justify-between gap-2">
                        <p className="min-w-0 flex-1 text-sm font-medium text-gray-800">{h.descripcion}</p>
                        <span className={cn('shrink-0 rounded px-1.5 py-0.5 text-[10px] font-semibold',
                          h.estado === 'en_proceso' ? 'bg-blue-100 text-blue-700' : 'bg-amber-100 text-amber-700')}>
                          {h.estado === 'en_proceso' ? 'En proceso' : 'Abierta'}
                        </span>
                      </div>
                      {h.accion_correctiva && (
                        <p className="mt-0.5 text-xs text-gray-600">
                          <span className="text-gray-400">Acción:</span> {h.accion_correctiva}
                        </p>
                      )}
                      <div className="mt-1 flex flex-wrap items-center gap-x-3 gap-y-0.5 text-[11px] text-gray-500">
                        <span>{h.responsable?.nombre_completo ?? h.responsable_texto ?? 'Sin responsable'}</span>
                        {h.fecha_compromiso && (
                          <span className={vencido ? 'font-semibold text-red-700' : ''}>
                            compromiso {h.fecha_compromiso}{vencido ? ' · vencido' : ''}
                          </span>
                        )}
                        {h.recorrido?.fecha && <span className="text-gray-400">recorrido {h.recorrido.fecha}</span>}
                      </div>
                    </Link>
                  </li>
                )
              })}
            </ul>
          ) : (
            <p className="text-sm text-gray-400">Sin hallazgos pendientes — plan de acción al día</p>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
