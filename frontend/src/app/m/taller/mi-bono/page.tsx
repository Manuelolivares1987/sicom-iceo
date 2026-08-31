'use client'

// ============================================================================
// Mi bono — la cartola del trabajador (MIG456)
// ----------------------------------------------------------------------------
// Hasta hoy el mecánico recibía un monto en la liquidación y no tenía forma de
// saber de dónde salía. Ni cuántos trabajos se le contaron, ni en qué días, ni
// qué pasó cuando una OT se demoró. Eso es lo que hace que el sistema sea
// discrecional: no es que el número esté mal, es que nadie puede revisarlo.
//
// Esta pantalla muestra lo mismo que calcula el motor, en el orden en que el
// trabajador se lo pregunta:
//
//   1. ¿Cuánto me tocó?           el total, arriba, grande
//   2. ¿De dónde sale?            las dos mitades separadas
//   3. ¿Qué trabajos me contaron? la lista de OT, con días y tramo
//   4. ¿Estoy de acuerdo?         el acuse, con espacio para reclamar
//
// MIENTRAS EL PERÍODO NO ESTÉ CERRADO, ESTO ES UN BORRADOR Y LO DICE.
// Un número en pantalla que después cambia sin aviso destruye la confianza más
// rápido de lo que la construye no tener pantalla.
// ============================================================================

import { useMemo, useState } from 'react'
import Link from 'next/link'
import {
  ChevronLeft, ChevronRight, Wallet, TrendingUp, Wrench, CheckCircle2,
  AlertTriangle, FileText, Loader2, Info,
} from 'lucide-react'
import { useToast } from '@/contexts/toast-context'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useCartolaBono, useAcusarRecibo } from '@/hooks/use-taller-bono'
import { clp, corteDelMes, CONCEPTO_LABEL } from '@/lib/services/taller-bono'

const TRAMO_COLOR: Record<string, string> = {
  optimizado: 'bg-green-100 text-green-800',
  normal: 'bg-blue-100 text-blue-800',
  'con demora': 'bg-amber-100 text-amber-900',
  'fuera de plazo': 'bg-red-100 text-red-800',
}

function fmtFecha(iso: string): string {
  const [y, m, d] = iso.split('-').map(Number)
  const MESES = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic']
  return `${d}-${MESES[m - 1]}`
}

export default function MiBonoPage() {
  useRequireAuth()
  const toast = useToast()

  // El ancla se mueve de corte en corte, no de mes calendario: el corte del
  // taller va del 24 al 23, igual que la liquidación.
  const [ancla, setAncla] = useState(() => new Date())
  const corte = useMemo(() => corteDelMes(ancla), [ancla])

  const { data, isLoading, error } = useCartolaBono(corte.desde, corte.hasta)
  const acusar = useAcusarRecibo()
  const [comentario, setComentario] = useState('')
  const [abriendoAcuse, setAbriendoAcuse] = useState(false)

  const moverCorte = (meses: number) => {
    const d = new Date(ancla)
    d.setMonth(d.getMonth() + meses)
    setAncla(d)
  }

  const linea = data?.linea ?? null
  const detalle = data?.detalle ?? []
  const yaAcuso = !!linea?.acuse_at

  return (
    <div className="mx-auto max-w-md px-3 pb-24 pt-3">
      <div className="mb-3 flex items-center gap-2">
        <Link href="/m/taller" className="rounded-lg p-1.5 active:bg-gray-100">
          <ChevronLeft className="h-5 w-5 text-gray-600" />
        </Link>
        <div className="flex items-center gap-2">
          <span className="rounded-lg bg-emerald-100 p-1.5"><Wallet className="h-4 w-4 text-emerald-700" /></span>
          <div>
            <h1 className="text-base font-semibold leading-tight text-gray-900">Mi bono</h1>
            <p className="text-[11px] leading-tight text-gray-500">Lo que llevo en este corte</p>
          </div>
        </div>
      </div>

      {/* Selector de corte */}
      <div className="mb-3 flex items-center justify-between rounded-xl border border-gray-200 bg-white px-2 py-2">
        <button onClick={() => moverCorte(-1)} className="rounded-lg p-1.5 active:bg-gray-100">
          <ChevronLeft className="h-4 w-4 text-gray-500" />
        </button>
        <div className="text-center">
          <p className="text-sm font-semibold text-gray-800">{corte.nombre}</p>
          <p className="text-[11px] text-gray-500">
            {fmtFecha(corte.desde)} al {fmtFecha(corte.hasta)}
          </p>
        </div>
        <button onClick={() => moverCorte(1)} className="rounded-lg p-1.5 active:bg-gray-100">
          <ChevronRight className="h-4 w-4 text-gray-500" />
        </button>
      </div>

      {isLoading && (
        <div className="flex justify-center py-10"><Loader2 className="h-6 w-6 animate-spin text-gray-400" /></div>
      )}

      {error && (
        <div className="rounded-xl border border-red-200 bg-red-50 p-3 text-sm text-red-800">
          {(error as Error).message}
        </div>
      )}

      {!isLoading && !error && !linea && (
        <p className="rounded-xl border border-gray-200 bg-white p-4 text-center text-sm text-gray-500">
          En este corte no hay nada calculado todavía.
        </p>
      )}

      {linea && (
        <>
          {/* 1 · El total */}
          <div className={`rounded-2xl border p-4 ${
            data?.cerrado ? 'border-emerald-300 bg-emerald-50' : 'border-gray-200 bg-white'}`}>
            <p className="text-[11px] font-medium uppercase tracking-wide text-gray-500">
              {data?.cerrado ? 'Total del corte' : 'Total hasta ahora'}
            </p>
            <p className="mt-0.5 text-3xl font-bold tabular-nums text-gray-900">{clp(linea.total)}</p>
            <p className="mt-1 text-xs text-gray-600">
              {linea.cargo ?? 'sin cargo asignado'}
              {linea.dias_cargo != null && linea.dias_corte != null &&
                linea.dias_cargo < linea.dias_corte && (
                  <> · {linea.dias_cargo} de {linea.dias_corte} días de contrato</>
              )}
            </p>

            {!data?.cerrado && (
              <p className="mt-2 flex items-start gap-1.5 rounded-lg bg-amber-100 px-2 py-1.5 text-[11px] text-amber-900">
                <Info className="mt-px h-3.5 w-3.5 shrink-0" />
                <span>
                  Borrador: el corte no está cerrado. Este número se sigue moviendo con cada
                  OT que se cierre.
                </span>
              </p>
            )}
            {data?.cerrado && data.periodo?.estado === 'reabierto' && (
              <p className="mt-2 rounded-lg bg-amber-100 px-2 py-1.5 text-[11px] text-amber-900">
                Este corte se reabrió: {data.periodo.motivo_reapertura}
              </p>
            )}
          </div>

          {/* 2 · Las dos mitades */}
          <div className="mt-3 grid grid-cols-2 gap-2">
            <div className="rounded-xl border border-gray-200 bg-white p-3">
              <div className="flex items-center gap-1.5">
                <Wrench className="h-3.5 w-3.5 text-blue-600" />
                <p className="text-[11px] font-medium text-gray-600">Por trabajos</p>
              </div>
              <p className="mt-0.5 text-lg font-bold tabular-nums text-gray-900">{clp(linea.plan_pagado)}</p>
              <p className="text-[11px] text-gray-500">
                {linea.ots} {linea.ots === 1 ? 'OT cerrada' : 'OT cerradas'}
              </p>
              {linea.plan_calculado != null && linea.plan_tope != null &&
               linea.plan_calculado > linea.plan_tope && (
                <p className="mt-1 text-[10px] text-amber-800">
                  Sumaba {clp(linea.plan_calculado)}; el tope de tu cargo es {clp(linea.plan_tope)}.
                </p>
              )}
            </div>
            <div className="rounded-xl border border-gray-200 bg-white p-3">
              <div className="flex items-center gap-1.5">
                <TrendingUp className="h-3.5 w-3.5 text-emerald-600" />
                <p className="text-[11px] font-medium text-gray-600">Por disponibilidad</p>
              </div>
              <p className="mt-0.5 text-lg font-bold tabular-nums text-gray-900">{clp(linea.kpi_pagado)}</p>
              <p className="text-[11px] text-gray-500">{linea.tramo ?? '—'}</p>
            </div>
          </div>

          {linea.falta && (
            <p className="mt-2 flex items-start gap-1.5 rounded-xl border border-amber-300 bg-amber-50 px-3 py-2 text-xs text-amber-900">
              <AlertTriangle className="mt-px h-4 w-4 shrink-0" />
              <span><b>Falta un dato para poder pagar:</b> {linea.falta}. Avísale al jefe de taller.</span>
            </p>
          )}

          {/* [MIG458] Los avisos no bloquean nada, pero explican el número. Van
              impresos acá porque el dueño del bono es quien tiene derecho a
              saber por qué su reparto fue mitad y mitad. */}
          {linea.aviso && (
            <p className="mt-2 flex items-start gap-1.5 rounded-xl border border-gray-200 bg-gray-50 px-3 py-2 text-xs text-gray-600">
              <Info className="mt-px h-4 w-4 shrink-0 text-gray-400" />
              <span>{linea.aviso}</span>
            </p>
          )}

          {/* 3 · Los trabajos que se contaron */}
          <h2 className="mb-2 mt-4 flex items-center gap-1.5 text-sm font-semibold text-gray-800">
            <FileText className="h-4 w-4 text-gray-400" />
            Trabajos contados
            <span className="ml-auto text-[11px] font-normal text-gray-500">{detalle.length}</span>
          </h2>

          {detalle.length === 0 ? (
            <p className="rounded-xl border border-dashed border-gray-300 bg-white p-4 text-center text-xs text-gray-500">
              Ninguna OT tuya se cerró dentro de este corte. El bono por trabajos se paga
              cuando la OT queda ejecutada, no cuando se empieza.
            </p>
          ) : (
            <div className="space-y-2">
              {detalle.map((d, i) => (
                <div key={(d.ot_id ?? '') + i} className="rounded-xl border border-gray-200 bg-white p-3">
                  <div className="flex items-start gap-2">
                    <div className="min-w-0 flex-1">
                      <p className="font-mono text-[11px] text-gray-500">{d.ot_folio}</p>
                      <p className="text-sm text-gray-800">
                        {d.concepto ? (CONCEPTO_LABEL[d.concepto] ?? d.concepto) : 'Sin concepto'}
                      </p>
                    </div>
                    <p className="shrink-0 text-sm font-semibold tabular-nums text-gray-900">
                      {clp(d.monto_propuesto)}
                    </p>
                  </div>
                  <div className="mt-1.5 flex flex-wrap items-center gap-1.5 text-[11px]">
                    <span className={`rounded px-1.5 py-0.5 font-medium ${
                      TRAMO_COLOR[d.tramo ?? ''] ?? 'bg-gray-100 text-gray-600'}`}>
                      {d.dias} {Number(d.dias) === 1 ? 'día' : 'días'} · {d.tramo ?? '—'}
                    </span>
                    {d.participacion != null && Number(d.participacion) < 1 && (
                      <span className="rounded bg-gray-100 px-1.5 py-0.5 text-gray-600">
                        te tocó el {Math.round(Number(d.participacion) * 100)}% ({d.base_reparto})
                      </span>
                    )}
                  </div>
                  {d.falta && <p className="mt-1 text-[11px] text-amber-800">{d.falta}</p>}
                  {d.aviso && <p className="mt-1 text-[11px] text-gray-500">{d.aviso}</p>}
                </div>
              ))}
            </div>
          )}

          {/* 4 · El acuse */}
          {data?.cerrado && linea.id && (
            <div className="mt-4 rounded-xl border border-gray-200 bg-white p-3">
              {yaAcuso ? (
                <div className="flex items-start gap-2">
                  <CheckCircle2 className="mt-px h-4 w-4 shrink-0 text-green-600" />
                  <div>
                    <p className="text-sm font-medium text-gray-800">Revisada por ti</p>
                    <p className="text-[11px] text-gray-500">
                      {new Date(linea.acuse_at!).toLocaleString('es-CL')}
                    </p>
                    {linea.acuse_comentario && (
                      <p className="mt-1 rounded bg-gray-50 px-2 py-1 text-xs text-gray-700">
                        “{linea.acuse_comentario}”
                      </p>
                    )}
                  </div>
                </div>
              ) : !abriendoAcuse ? (
                <>
                  <p className="text-sm text-gray-700">
                    ¿Revisaste tu cartola? Deja constancia. Si algo no cuadra, escríbelo:
                    queda en el registro junto al monto.
                  </p>
                  <button
                    onClick={() => setAbriendoAcuse(true)}
                    className="mt-2 w-full rounded-xl bg-emerald-600 px-3 py-2.5 text-sm font-semibold text-white active:bg-emerald-700">
                    Revisé mi cartola
                  </button>
                </>
              ) : (
                <>
                  <label className="text-xs font-medium text-gray-700">
                    Comentario (opcional, sólo si algo no cuadra)
                  </label>
                  <textarea
                    rows={3} value={comentario} onChange={(e) => setComentario(e.target.value)}
                    placeholder="Ej: la OT-202609-00012 la hice yo solo, no a medias"
                    className="mt-1 w-full rounded-lg border border-gray-300 px-2 py-1.5 text-sm" />
                  <div className="mt-2 flex gap-2">
                    <button
                      disabled={acusar.isPending}
                      onClick={() => acusar.mutate(
                        { lineaId: linea.id!, comentario },
                        {
                          onSuccess: () => { toast.success('Quedó registrado'); setAbriendoAcuse(false) },
                          onError: (e) => toast.error((e as Error).message),
                        })}
                      className="flex-1 rounded-xl bg-emerald-600 px-3 py-2.5 text-sm font-semibold text-white disabled:opacity-50">
                      {acusar.isPending ? 'Guardando…' : 'Confirmar'}
                    </button>
                    <button
                      onClick={() => setAbriendoAcuse(false)}
                      className="rounded-xl border border-gray-300 px-3 py-2.5 text-sm text-gray-600">
                      Cancelar
                    </button>
                  </div>
                </>
              )}
            </div>
          )}

          {data?.cerrado && (
            <p className="mt-3 text-center text-[11px] text-gray-400">
              Cerrado por {data.periodo?.cerrado_por ?? '—'} el{' '}
              {data.periodo?.cerrado_at ? new Date(data.periodo.cerrado_at).toLocaleDateString('es-CL') : '—'}
              {data.periodo?.disponibilidad_pct != null && (
                <> · disponibilidad de flota {data.periodo.disponibilidad_pct}%</>
              )}
            </p>
          )}
        </>
      )}
    </div>
  )
}
