'use client'

// ============================================================================
// Bono del taller — la vista de jefatura y el cierre del período (MIG452-456)
// ----------------------------------------------------------------------------
// Acá se ve el corte completo antes de pagarlo, y se cierra.
//
// LO QUE ESTA PANTALLA TIENE QUE DEJAR CLARO, PORQUE ES PLATA
//
//   · Que el número de HOY es un borrador y se sigue moviendo.
//   · Que hay dos fórmulas conviviendo: la de la planilla —transcrita literal,
//     con sus defectos— y la corregida. La marcha blanca existe para comparar
//     las dos, así que las dos se muestran, no una.
//   · Qué falta para poder cerrar. El cierre se niega con huecos, y negarse sin
//     decir por qué es peor que no tener botón.
//
// El cierre congela línea por línea. Después de cerrado el corte responde
// siempre lo mismo, aunque una OT se reabra en octubre.
// ============================================================================

import { useMemo, useState } from 'react'
import Link from 'next/link'
import {
  Wallet, Lock, Unlock, AlertTriangle, ChevronLeft, ChevronRight, Users,
  TrendingUp, Wrench, CheckCircle2, Info, ArrowLeft,
} from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { useToast } from '@/contexts/toast-context'
import { usePermissions } from '@/hooks/use-permissions'
import {
  useResumenBono, useDisponibilidadPeriodo, usePeriodosBono,
  useCerrarPeriodo, useReabrirPeriodo,
} from '@/hooks/use-taller-bono'
import { clp, corteDelMes } from '@/lib/services/taller-bono'

const PUEDE_CERRAR = ['administrador', 'subgerente_operaciones', 'jefe_operaciones', 'jefe_mantenimiento']
const PUEDE_REABRIR = ['administrador', 'subgerente_operaciones']

function fmt(iso: string): string {
  const [, m, d] = iso.split('-').map(Number)
  const MESES = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic']
  return `${d}-${MESES[m - 1]}`
}

export default function BonoTallerPage() {
  const toast = useToast()
  const { rol } = usePermissions()
  const puedeCerrar = PUEDE_CERRAR.includes(rol ?? '')
  const puedeReabrir = PUEDE_REABRIR.includes(rol ?? '')

  const [ancla, setAncla] = useState(() => new Date())
  const corte = useMemo(() => corteDelMes(ancla), [ancla])

  const { data: lineas = [], isLoading, error } = useResumenBono(corte.desde, corte.hasta)
  const { data: disp } = useDisponibilidadPeriodo(corte.desde, corte.hasta)
  const { data: periodos = [] } = usePeriodosBono()
  const cerrar = useCerrarPeriodo()
  const reabrir = useReabrirPeriodo()

  const [notas, setNotas] = useState('')
  const [confirmando, setConfirmando] = useState(false)
  const [reabriendo, setReabriendo] = useState<string | null>(null)
  const [motivo, setMotivo] = useState('')

  const cerrado = periodos.find((p) => p.desde === corte.desde && p.hasta === corte.hasta)
  const conFalta = lineas.filter((l) => l.falta)
  const totalPropuesto = lineas.reduce((a, l) => a + (l.total ?? 0), 0)
  const totalPlan = lineas.reduce((a, l) => a + (l.plan_pagado ?? 0), 0)
  const totalKpi = lineas.reduce((a, l) => a + (l.kpi_pagado ?? 0), 0)
  const totalFormula = lineas.reduce((a, l) => a + (l.plan_formula ?? 0), 0)
  const totalCalculado = lineas.reduce((a, l) => a + (l.plan_calculado ?? 0), 0)

  const moverCorte = (meses: number) => {
    const d = new Date(ancla); d.setMonth(d.getMonth() + meses); setAncla(d)
  }

  return (
    <div className="p-4 lg:p-6">
      <Link href="/dashboard/mantenimiento"
            className="mb-3 inline-flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700">
        <ArrowLeft className="h-4 w-4" /> Mantenimiento
      </Link>

      <div className="mb-4 flex flex-wrap items-center gap-3">
        <span className="rounded-lg bg-emerald-100 p-2"><Wallet className="h-5 w-5 text-emerald-700" /></span>
        <div>
          <h1 className="text-xl font-semibold text-gray-900">Bono del taller</h1>
          <p className="text-sm text-gray-500">
            Plan de incentivo por trabajo + KPI de disponibilidad, calculados por SICOM.
          </p>
        </div>

        <div className="ml-auto flex items-center gap-1 rounded-lg border border-gray-200 bg-white px-1 py-1">
          <button onClick={() => moverCorte(-1)} className="rounded p-1.5 hover:bg-gray-100">
            <ChevronLeft className="h-4 w-4 text-gray-500" />
          </button>
          <div className="px-2 text-center">
            <p className="text-sm font-semibold text-gray-800">{corte.nombre}</p>
            <p className="text-[11px] text-gray-500">{fmt(corte.desde)} al {fmt(corte.hasta)}</p>
          </div>
          <button onClick={() => moverCorte(1)} className="rounded p-1.5 hover:bg-gray-100">
            <ChevronRight className="h-4 w-4 text-gray-500" />
          </button>
        </div>
      </div>

      {cerrado ? (
        <div className="mb-4 flex flex-wrap items-center gap-3 rounded-xl border border-emerald-300 bg-emerald-50 p-3">
          <Lock className="h-5 w-5 shrink-0 text-emerald-700" />
          <div className="min-w-0">
            <p className="text-sm font-semibold text-emerald-900">
              {cerrado.nombre} · cerrado {cerrado.estado === 'reabierto' && '(y reabierto)'}
            </p>
            <p className="text-xs text-emerald-800">
              {clp(cerrado.total_clp)} · {cerrado.personas} personas ·{' '}
              {cerrado.acusadas} de {cerrado.personas} revisaron su cartola ·
              cerrado por {cerrado.cerrado_por ?? '—'} el{' '}
              {new Date(cerrado.cerrado_at).toLocaleDateString('es-CL')}
            </p>
          </div>
          {puedeReabrir && cerrado.estado === 'cerrado' && (
            <button onClick={() => setReabriendo(cerrado.id)}
                    className="ml-auto inline-flex items-center gap-1 rounded-lg border border-emerald-400 px-2.5 py-1.5 text-xs font-medium text-emerald-800 hover:bg-emerald-100">
              <Unlock className="h-3.5 w-3.5" /> Reabrir
            </button>
          )}
        </div>
      ) : (
        <div className="mb-4 flex items-start gap-2 rounded-xl border border-amber-300 bg-amber-50 p-3 text-sm text-amber-900">
          <Info className="mt-0.5 h-4 w-4 shrink-0" />
          <span>
            <b>Este corte es un borrador.</b> Los montos se siguen moviendo con cada OT que se
            cierre. Nadie cobra hasta que el corte se cierre acá abajo.
          </span>
        </div>
      )}

      {reabriendo && (
        <div className="mb-4 rounded-xl border border-amber-300 bg-white p-3">
          <p className="text-sm font-medium text-gray-800">¿Por qué se reabre este corte?</p>
          <p className="mb-2 text-xs text-gray-500">
            Queda en el registro con tu nombre y la fecha. El corte no vuelve a estar «cerrado limpio».
          </p>
          <textarea rows={2} value={motivo} onChange={(e) => setMotivo(e.target.value)}
                    placeholder="Mínimo 10 caracteres"
                    className="w-full rounded-lg border border-gray-300 px-2 py-1.5 text-sm" />
          <div className="mt-2 flex gap-2">
            <Button disabled={reabrir.isPending || motivo.trim().length < 10}
                    onClick={() => reabrir.mutate({ periodoId: reabriendo, motivo }, {
                      onSuccess: () => { toast.success('Corte reabierto'); setReabriendo(null); setMotivo('') },
                      onError: (e) => toast.error((e as Error).message),
                    })}>
              {reabrir.isPending && <Spinner className="mr-1 h-4 w-4" />} Reabrir
            </Button>
            <Button variant="outline" onClick={() => { setReabriendo(null); setMotivo('') }}>Cancelar</Button>
          </div>
        </div>
      )}

      {/* KPI del corte */}
      <div className="mb-4 grid grid-cols-2 gap-3 lg:grid-cols-4">
        <div className="rounded-xl border border-gray-200 bg-white p-3">
          <p className="text-[11px] font-medium uppercase text-gray-500">Total del corte</p>
          <p className="mt-0.5 text-2xl font-bold tabular-nums text-gray-900">{clp(totalPropuesto)}</p>
        </div>
        <div className="rounded-xl border border-gray-200 bg-white p-3">
          <div className="flex items-center gap-1.5"><Wrench className="h-3.5 w-3.5 text-blue-600" />
            <p className="text-[11px] font-medium uppercase text-gray-500">Por trabajos</p></div>
          <p className="mt-0.5 text-2xl font-bold tabular-nums text-gray-900">{clp(totalPlan)}</p>
        </div>
        <div className="rounded-xl border border-gray-200 bg-white p-3">
          <div className="flex items-center gap-1.5"><TrendingUp className="h-3.5 w-3.5 text-emerald-600" />
            <p className="text-[11px] font-medium uppercase text-gray-500">Por disponibilidad</p></div>
          <p className="mt-0.5 text-2xl font-bold tabular-nums text-gray-900">{clp(totalKpi)}</p>
          <p className="text-[11px] text-gray-500">
            flota {disp?.disponibilidad_pct ?? '—'}%
            {disp?.promedio_diario_pct != null && disp.promedio_diario_pct !== disp.disponibilidad_pct && (
              <> · promedio diario {disp.promedio_diario_pct}%</>
            )}
          </p>
        </div>
        <div className="rounded-xl border border-gray-200 bg-white p-3">
          <div className="flex items-center gap-1.5"><Users className="h-3.5 w-3.5 text-gray-500" />
            <p className="text-[11px] font-medium uppercase text-gray-500">Personas</p></div>
          <p className="mt-0.5 text-2xl font-bold tabular-nums text-gray-900">{lineas.length}</p>
          {conFalta.length > 0 && (
            <p className="text-[11px] text-amber-800">{conFalta.length} con datos pendientes</p>
          )}
        </div>
      </div>

      {/* Las dos fórmulas, lado a lado */}
      {totalFormula !== totalCalculado && (
        <div className="mb-4 rounded-xl border border-blue-200 bg-blue-50 p-3 text-sm text-blue-900">
          <p className="font-medium">Las dos fórmulas no dan lo mismo en este corte</p>
          <p className="mt-1 text-xs">
            La fórmula de la planilla, transcrita literal, suma <b>{clp(totalFormula)}</b> en plan
            de incentivo. La corregida —monótona, nunca negativa— suma <b>{clp(totalCalculado)}</b>.
            La diferencia es lo que la marcha blanca tiene que explicar antes de activar los
            parámetros.
          </p>
        </div>
      )}

      {isLoading && <div className="flex justify-center py-10"><Spinner /></div>}
      {error && (
        <div className="rounded-xl border border-red-200 bg-red-50 p-3 text-sm text-red-800">
          {(error as Error).message}
        </div>
      )}

      {/* La tabla */}
      {!isLoading && !error && (
        <div className="overflow-x-auto rounded-xl border border-gray-200 bg-white">
          <table className="w-full min-w-[900px] text-sm">
            <thead className="border-b border-gray-200 bg-gray-50 text-left text-xs uppercase text-gray-500">
              <tr>
                <th className="px-3 py-2">Técnico</th>
                <th className="px-3 py-2">Cargo</th>
                <th className="px-3 py-2 text-right">OT</th>
                <th className="px-3 py-2 text-right">Planilla</th>
                <th className="px-3 py-2 text-right">Corregida</th>
                <th className="px-3 py-2 text-right">Tope</th>
                <th className="px-3 py-2 text-right">Trabajos</th>
                <th className="px-3 py-2 text-right">KPI</th>
                <th className="px-3 py-2 text-right">Total</th>
                <th className="px-3 py-2">Falta / aviso</th>
              </tr>
            </thead>
            <tbody>
              {lineas.map((l) => (
                <tr key={l.tecnico_id} className={`border-b border-gray-100 last:border-0 ${
                  l.falta ? 'bg-amber-50/50' : ''}`}>
                  <td className="px-3 py-2 font-medium text-gray-800">{l.tecnico}</td>
                  <td className="px-3 py-2 text-gray-600">{l.cargo ?? '—'}</td>
                  <td className="px-3 py-2 text-right tabular-nums text-gray-600">{l.ots}</td>
                  <td className="px-3 py-2 text-right tabular-nums text-gray-500">{clp(l.plan_formula)}</td>
                  <td className="px-3 py-2 text-right tabular-nums text-gray-500">{clp(l.plan_calculado)}</td>
                  <td className="px-3 py-2 text-right tabular-nums text-gray-400">{clp(l.plan_tope)}</td>
                  <td className="px-3 py-2 text-right tabular-nums text-gray-800">{clp(l.plan_pagado)}</td>
                  <td className="px-3 py-2 text-right tabular-nums text-gray-800">{clp(l.kpi_pagado)}</td>
                  <td className="px-3 py-2 text-right font-semibold tabular-nums text-gray-900">{clp(l.total)}</td>
                  <td className="px-3 py-2 text-xs">
                    {l.falta && <span className="text-amber-800">{l.falta}</span>}
                    {l.falta && l.aviso && <br />}
                    {l.aviso && <span className="text-gray-500">{l.aviso}</span>}
                  </td>
                </tr>
              ))}
              {lineas.length === 0 && (
                <tr><td colSpan={10} className="px-3 py-6 text-center text-gray-400">
                  No hay técnicos con cargo vigente en este corte.
                </td></tr>
              )}
            </tbody>
          </table>
        </div>
      )}

      {/* El cierre */}
      {!cerrado && puedeCerrar && lineas.length > 0 && (
        <div className="mt-4 rounded-xl border border-gray-200 bg-white p-4">
          <h2 className="flex items-center gap-2 text-sm font-semibold text-gray-800">
            <Lock className="h-4 w-4 text-gray-400" /> Cerrar {corte.nombre}
          </h2>
          <p className="mt-1 text-xs text-gray-600">
            Congela línea por línea con los parámetros y la disponibilidad de hoy. Después de
            cerrado, el corte responde siempre lo mismo aunque una OT se reabra más adelante.
          </p>

          {conFalta.length > 0 && (
            <div className="mt-2 flex items-start gap-2 rounded-lg border border-amber-300 bg-amber-50 p-2.5 text-xs text-amber-900">
              <AlertTriangle className="mt-px h-4 w-4 shrink-0" />
              <div>
                <p className="font-medium">No se puede cerrar todavía. Falta:</p>
                {/* [MIG458] Acá sólo aparece lo que impide poner un número. Un
                    reparto en partes iguales o un tope que recorta son avisos y
                    van en la tabla, no frenan el cierre. */}
                <ul className="mt-1 list-disc pl-4">
                  {conFalta.map((l) => <li key={l.tecnico_id}>{l.tecnico}: {l.falta}</li>)}
                </ul>
              </div>
            </div>
          )}

          <input value={notas} onChange={(e) => setNotas(e.target.value)}
                 placeholder="Nota del cierre (opcional): número de acta, acuerdos, etc."
                 className="mt-3 w-full rounded-lg border border-gray-300 px-2 py-1.5 text-sm" />

          {!confirmando ? (
            <Button className="mt-3" disabled={conFalta.length > 0}
                    onClick={() => setConfirmando(true)}>
              <Lock className="mr-1 h-4 w-4" /> Cerrar el corte
            </Button>
          ) : (
            <div className="mt-3 rounded-lg border border-gray-300 bg-gray-50 p-3">
              <p className="text-sm text-gray-800">
                Se van a congelar <b>{lineas.length} cartolas</b> por un total de{' '}
                <b>{clp(totalPropuesto)}</b>. ¿Confirmas?
              </p>
              <div className="mt-2 flex gap-2">
                <Button disabled={cerrar.isPending}
                        onClick={() => cerrar.mutate({
                          nombre: corte.nombre, desde: corte.desde, hasta: corte.hasta,
                          notas: notas.trim() || null,
                        }, {
                          onSuccess: (r) => {
                            toast.success(`Corte cerrado: ${r.personas} cartolas, ${clp(r.total_clp)}`)
                            setConfirmando(false); setNotas('')
                          },
                          onError: (e) => toast.error((e as Error).message),
                        })}>
                  {cerrar.isPending && <Spinner className="mr-1 h-4 w-4" />} Sí, cerrar
                </Button>
                <Button variant="outline" onClick={() => setConfirmando(false)}>Cancelar</Button>
              </div>
            </div>
          )}
        </div>
      )}

      {/* Historial */}
      {periodos.length > 0 && (
        <>
          <h2 className="mb-2 mt-6 text-sm font-semibold text-gray-800">Cortes cerrados</h2>
          <div className="space-y-2">
            {periodos.map((p) => (
              <div key={p.id} className="flex flex-wrap items-center gap-3 rounded-xl border border-gray-200 bg-white px-3 py-2 text-sm">
                {p.estado === 'cerrado'
                  ? <Lock className="h-4 w-4 shrink-0 text-gray-400" />
                  : <Unlock className="h-4 w-4 shrink-0 text-amber-600" />}
                <span className="font-medium text-gray-800">{p.nombre}</span>
                <span className="text-xs text-gray-500">{fmt(p.desde)} al {fmt(p.hasta)}</span>
                <span className="ml-auto tabular-nums font-semibold text-gray-900">{clp(p.total_clp)}</span>
                <span className="inline-flex items-center gap-1 text-xs text-gray-500">
                  <CheckCircle2 className="h-3.5 w-3.5" />{p.acusadas}/{p.personas} revisaron
                </span>
              </div>
            ))}
          </div>
        </>
      )}
    </div>
  )
}
