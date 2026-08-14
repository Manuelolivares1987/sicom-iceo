'use client'

// Avance de los Recorridos Gemba (MIG292).
//
// La portada del módulo cuenta cuántos recorridos se hicieron. Esta página
// responde la pregunta que importa: ¿se está cumpliendo el programa? 8
// recorridos en el mes suena bien hasta que uno recuerda que el del taller es
// diario y deberían ser 22.
//
// Dos números distintos y a propósito separados:
//   · AVANCE DEL PROGRAMA → se recorrió o no. No se puede falsear sin salir.
//   · % DEL CHECKLIST      → qué tan bien salió. Ese sí sube marcando "cumple".
//
// Pensada para leerse en el teléfono: una columna, tarjetas, sin tablas anchas.

import { useState } from 'react'
import Link from 'next/link'
import {
  ArrowLeft, ChevronLeft, ChevronRight, TrendingUp, Users, AlertTriangle,
  ClipboardCheck, Repeat,
} from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Spinner } from '@/components/ui/spinner'
import { cn } from '@/lib/utils'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useGembaReporte } from '@/hooks/use-gemba'
import { CADENCIA_LABEL, MESES_GEMBA, type GembaProgramaFila } from '@/lib/services/gemba'

const hoy = () => { const d = new Date(); return { anio: d.getFullYear(), mes: d.getMonth() + 1 } }

function fechaCorta(iso?: string | null): string {
  if (!iso) return '—'
  const [y, m, d] = iso.slice(0, 10).split('-')
  return `${d}-${m}-${y.slice(2)}`
}

/** Semáforo del avance: bajo el 60% el programa no se está haciendo. */
const colorAvance = (pct: number) =>
  pct >= 90 ? 'bg-green-600' : pct >= 60 ? 'bg-amber-500' : 'bg-red-600'
const textoAvance = (pct: number) =>
  pct >= 90 ? 'text-green-700' : pct >= 60 ? 'text-amber-700' : 'text-red-700'

function FilaPrograma({ p }: { p: GembaProgramaFila }) {
  const pct = p.esperados > 0 ? Math.round((100 * p.realizados) / p.esperados) : null
  const faltan = Math.max(0, p.esperados - p.realizados)

  return (
    <div className="border-b border-gray-100 py-3 last:border-0">
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0 flex-1">
          <p className="truncate text-sm font-semibold text-gray-800">{p.nombre}</p>
          <p className="text-[11px] text-gray-500">
            {p.cadencia ? CADENCIA_LABEL[p.cadencia] : 'Sin cadencia'} · {p.codigo}
          </p>
        </div>
        <div className="shrink-0 text-right">
          <p className={cn('text-lg font-bold leading-none', pct == null ? 'text-gray-400' : textoAvance(pct))}>
            {pct == null ? '—' : `${pct}%`}
          </p>
          <p className="text-[10px] text-gray-500">avance</p>
        </div>
      </div>

      {/* Barra: lo hecho sobre lo que se esperaba en el período */}
      <div className="mt-2 h-2 w-full overflow-hidden rounded-full bg-gray-100">
        <div className={cn('h-full rounded-full transition-all', pct == null ? 'bg-gray-300' : colorAvance(pct))}
             style={{ width: `${Math.min(100, pct ?? 0)}%` }} />
      </div>

      <div className="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-[11px] text-gray-600">
        <span><b className="text-gray-900">{p.realizados}</b> de {p.esperados} esperados</span>
        {faltan > 0 && <span className="font-semibold text-red-700">faltan {faltan}</span>}
        <span>{p.cerrados} cerrados</span>
        {p.hallazgos > 0 && <span className="text-amber-700">{p.hallazgos} hallazgo(s)</span>}
        {p.pct_checklist != null && (
          <span className="text-gray-500">checklist {p.pct_checklist}%</span>
        )}
      </div>
    </div>
  )
}

export default function GembaReportePage() {
  useRequireAuth()
  const [{ anio, mes }, setPeriodo] = useState(hoy())
  const { data: rep, isLoading } = useGembaReporte(anio, mes)

  function cambiarMes(delta: number) {
    let m = mes + delta, a = anio
    if (m < 1) { m = 12; a-- } else if (m > 12) { m = 1; a++ }
    setPeriodo({ anio: a, mes: m })
  }

  const h = rep?.hallazgos
  const enPlazo = h && h.cerrados_con_plazo > 0
    ? Math.round((100 * h.cerrados_en_plazo) / h.cerrados_con_plazo) : null

  // El avance global pondera por lo esperado: un checklist diario pesa más que
  // uno mensual, que es exactamente como se siente en el taller.
  const totEsperados = (rep?.programa ?? []).reduce((n, p) => n + p.esperados, 0)
  const totRealizados = (rep?.programa ?? []).reduce((n, p) => n + Math.min(p.realizados, p.esperados), 0)
  const avanceGlobal = totEsperados > 0 ? Math.round((100 * totRealizados) / totEsperados) : null

  return (
    <div className="space-y-4 pb-6">
      {/* ── Encabezado + selector de mes ── */}
      <div>
        <Link href="/dashboard/prevencion/gemba"
              className="inline-flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700">
          <ArrowLeft className="h-4 w-4" /> Volver a recorridos
        </Link>
        <h1 className="mt-2 flex items-center gap-2 text-xl font-bold text-gray-900 sm:text-2xl">
          <TrendingUp className="h-6 w-6 text-amber-500" />
          Avance de recorridos
        </h1>
      </div>

      <div className="flex items-center justify-between gap-2 rounded-lg border border-gray-200 bg-white p-2">
        <button onClick={() => cambiarMes(-1)} aria-label="Mes anterior"
                className="rounded-lg border p-2 hover:bg-gray-50">
          <ChevronLeft className="h-4 w-4" />
        </button>
        <div className="text-center">
          <p className="text-sm font-semibold">{MESES_GEMBA[mes - 1]} {anio}</p>
          {rep?.periodo?.en_curso && (
            <p className="text-[10px] text-gray-500">medido hasta hoy ({fechaCorta(rep.periodo.hasta)})</p>
          )}
        </div>
        <button onClick={() => cambiarMes(1)} aria-label="Mes siguiente"
                className="rounded-lg border p-2 hover:bg-gray-50">
          <ChevronRight className="h-4 w-4" />
        </button>
      </div>

      {isLoading || !rep ? (
        <div className="flex h-40 items-center justify-center"><Spinner className="h-8 w-8" /></div>
      ) : (
        <>
          {/* ── Avance global del programa ── */}
          <Card>
            <CardContent className="p-4">
              <div className="flex items-end justify-between">
                <div>
                  <p className="text-xs font-medium uppercase tracking-wide text-gray-500">
                    Cumplimiento del programa
                  </p>
                  <p className="mt-1 text-xs text-gray-500">
                    {totRealizados} de {totEsperados} recorridos esperados en el período
                  </p>
                </div>
                <p className={cn('text-4xl font-bold leading-none',
                                 avanceGlobal == null ? 'text-gray-300' : textoAvance(avanceGlobal))}>
                  {avanceGlobal == null ? '—' : `${avanceGlobal}%`}
                </p>
              </div>
              <div className="mt-3 h-3 w-full overflow-hidden rounded-full bg-gray-100">
                <div className={cn('h-full rounded-full transition-all',
                                   avanceGlobal == null ? 'bg-gray-300' : colorAvance(avanceGlobal))}
                     style={{ width: `${Math.min(100, avanceGlobal ?? 0)}%` }} />
              </div>
              <p className="mt-2 text-[11px] text-gray-500">
                Esto mide si se sale a terreno. El % de cumplimiento de cada checklist —qué tan bien
                salió— va aparte: ese sube marcando &quot;cumple&quot;, este no.
              </p>
            </CardContent>
          </Card>

          {/* ── Programa por checklist ── */}
          <Card>
            <CardContent className="p-4">
              <h2 className="mb-1 flex items-center gap-1.5 text-sm font-bold text-gray-800">
                <ClipboardCheck className="h-4 w-4 text-blue-700" /> Por checklist
              </h2>
              {rep.programa.length === 0
                ? <p className="py-4 text-center text-sm text-gray-400">Sin checklists activos.</p>
                : rep.programa.map((p) => <FilaPrograma key={p.plantilla_id} p={p} />)}
            </CardContent>
          </Card>

          {/* ── Plan de acción ── */}
          <Card>
            <CardContent className="p-4">
              <h2 className="mb-2 flex items-center gap-1.5 text-sm font-bold text-gray-800">
                <AlertTriangle className="h-4 w-4 text-amber-500" /> Plan de acción
              </h2>
              <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
                {[
                  { l: 'Abiertos', v: h?.abiertos ?? 0, c: 'text-amber-700 bg-amber-50 border-amber-200' },
                  { l: 'En proceso', v: h?.en_proceso ?? 0, c: 'text-blue-700 bg-blue-50 border-blue-200' },
                  { l: 'Vencidos', v: h?.vencidos ?? 0, c: (h?.vencidos ?? 0) > 0 ? 'text-red-700 bg-red-50 border-red-200' : 'text-gray-600 bg-gray-50 border-gray-200' },
                  { l: 'Cerrados', v: h?.cerrados ?? 0, c: 'text-green-700 bg-green-50 border-green-200' },
                ].map((k) => (
                  <div key={k.l} className={cn('rounded-lg border p-2.5 text-center', k.c)}>
                    <div className="text-2xl font-bold">{k.v}</div>
                    <div className="text-[10px] leading-tight">{k.l}</div>
                  </div>
                ))}
              </div>
              <div className="mt-3 space-y-1 text-[11px] text-gray-600">
                {enPlazo != null && (
                  <p>
                    <b className={enPlazo >= 80 ? 'text-green-700' : 'text-amber-700'}>{enPlazo}%</b>
                    {' '}de las acciones cerradas llegó dentro del plazo comprometido.
                  </p>
                )}
                {h?.dias_promedio_cierre != null && (
                  <p>Una acción se demora <b>{h.dias_promedio_cierre} días</b> en cerrarse, en promedio.</p>
                )}
                {(h?.sin_plazo ?? 0) > 0 && (
                  <p className="text-amber-800">
                    <b>{h!.sin_plazo}</b> acción(es) abierta(s) sin fecha de compromiso: sin plazo no hay seguimiento.
                  </p>
                )}
              </div>
            </CardContent>
          </Card>

          {/* ── Lo que más falla ── */}
          <Card>
            <CardContent className="p-4">
              <h2 className="mb-1 flex items-center gap-1.5 text-sm font-bold text-gray-800">
                <Repeat className="h-4 w-4 text-red-600" /> Lo que más falla (90 días)
              </h2>
              <p className="mb-2 text-[11px] text-gray-500">
                Un ítem que falla muchas veces no es un descuido: es un proceso que no está.
              </p>
              {rep.items_criticos.length === 0 ? (
                <p className="py-4 text-center text-sm text-gray-400">
                  Sin ítems no conformes en los últimos 90 días.
                </p>
              ) : (
                <ul className="space-y-2">
                  {rep.items_criticos.map((it, i) => (
                    <li key={i} className="flex items-start gap-2.5 border-b border-gray-100 pb-2 last:border-0">
                      <span className="mt-0.5 shrink-0 rounded bg-red-100 px-1.5 py-0.5 text-xs font-bold text-red-800">
                        {it.veces}×
                      </span>
                      <div className="min-w-0 flex-1">
                        <p className="text-xs text-gray-800">{it.item}</p>
                        <p className="text-[10px] text-gray-500">
                          {it.seccion}
                          {it.pct_falla != null && ` · falla el ${it.pct_falla}% de las veces que se revisa`}
                        </p>
                      </div>
                    </li>
                  ))}
                </ul>
              )}
            </CardContent>
          </Card>

          {/* ── Quién recorre ── */}
          <Card>
            <CardContent className="p-4">
              <h2 className="mb-2 flex items-center gap-1.5 text-sm font-bold text-gray-800">
                <Users className="h-4 w-4 text-blue-700" /> Quién recorrió
              </h2>
              {rep.responsables.length === 0 ? (
                <p className="py-4 text-center text-sm text-gray-400">
                  Nadie registró recorridos en {MESES_GEMBA[mes - 1]}.
                </p>
              ) : (
                <ul className="divide-y divide-gray-100">
                  {rep.responsables.map((r, i) => (
                    <li key={i} className="flex items-center gap-3 py-2.5">
                      <div className="min-w-0 flex-1">
                        <p className="truncate text-sm font-medium text-gray-800">{r.nombre}</p>
                        <p className="text-[11px] text-gray-500">
                          Último: {fechaCorta(r.ultimo)}
                          {r.dias_sin_recorrer != null && r.dias_sin_recorrer > 2 &&
                            ` · hace ${r.dias_sin_recorrer} días`}
                          {r.hallazgos > 0 && ` · ${r.hallazgos} hallazgo(s)`}
                        </p>
                      </div>
                      <div className="shrink-0 text-right">
                        <p className="text-lg font-bold leading-none text-gray-900">{r.recorridos}</p>
                        <p className="text-[10px] text-gray-500">{r.cerrados} cerrados</p>
                      </div>
                    </li>
                  ))}
                </ul>
              )}
            </CardContent>
          </Card>
        </>
      )}
    </div>
  )
}
