'use client'

import Link from 'next/link'
import { ArrowRight, AlertTriangle } from 'lucide-react'
import type { CalamaOTConRelaciones } from '@/lib/services/calama'
import { zonaCodeFromFolio, excelCodigoFromFolio, desviacionPp } from '@/lib/services/calama'

type Props = {
  ots: CalamaOTConRelaciones[]
  hoy?: string
  maxRows?: number
}

export function GanttTable({ ots, hoy, maxRows }: Props) {
  const today = hoy ?? new Date().toISOString().slice(0, 10)
  const filas = maxRows ? ots.slice(0, maxRows) : ots

  if (filas.length === 0) {
    return (
      <div className="rounded-lg border border-dashed border-gray-200 p-6 text-center text-sm text-gray-400">
        Sin OTs para mostrar.
      </div>
    )
  }

  return (
    <div className="overflow-x-auto">
      <table className="w-full text-xs">
        <thead>
          <tr className="border-b bg-gray-50 text-left uppercase text-gray-500">
            <th className="px-2 py-2">Cod</th>
            <th className="px-2 py-2">Tarea</th>
            <th className="px-2 py-2">Zona</th>
            <th className="px-2 py-2">Fecha</th>
            <th className="px-2 py-2">Estado</th>
            <th className="px-2 py-2 text-right">Real</th>
            <th className="px-2 py-2 text-right">Excel</th>
            <th className="px-2 py-2 text-right">Δ</th>
            <th className="px-2 py-2">Progreso</th>
            <th className="px-2 py-2 w-12"></th>
          </tr>
        </thead>
        <tbody>
          {filas.map((ot) => {
            const codigoTarea = excelCodigoFromFolio(ot.folio)
            const zona = zonaCodeFromFolio(ot.folio)
            const atrasada =
              ot.fecha_programada < today
              && !['finalizada', 'cancelada', 'no_ejecutada'].includes(ot.estado)
            const real = Number(ot.avance_pct ?? 0)
            const excel = Number((ot as { avance_excel_pct?: number }).avance_excel_pct ?? 0)
            const delta = desviacionPp(real, excel)
            return (
              <tr key={ot.id} className={`border-b ${atrasada ? 'bg-red-50' : ''}`}>
                <td className="px-2 py-1.5 font-mono text-gray-700">{codigoTarea ?? '—'}</td>
                <td className="px-2 py-1.5 max-w-xs truncate" title={ot.titulo}>{ot.titulo}</td>
                <td className="px-2 py-1.5 font-mono text-gray-500">{zona ?? '—'}</td>
                <td className="px-2 py-1.5 whitespace-nowrap">
                  {ot.fecha_programada}
                  {atrasada && (
                    <AlertTriangle className="inline-block h-3 w-3 ml-1 text-red-600" aria-label="atrasada" />
                  )}
                </td>
                <td className="px-2 py-1.5">
                  <EstadoBadge estado={ot.estado} />
                </td>
                <td className={`px-2 py-1.5 text-right font-mono font-bold ${
                  real >= 100 ? 'text-green-700' : real > 0 ? 'text-amber-700' : 'text-gray-400'
                }`}>{real.toFixed(0)}%</td>
                <td className="px-2 py-1.5 text-right font-mono text-gray-500">{excel.toFixed(0)}%</td>
                <td className={`px-2 py-1.5 text-right font-mono text-[11px] ${
                  delta >= 0 ? 'text-green-700' : 'text-red-700'
                }`}>{delta >= 0 ? '+' : ''}{delta.toFixed(0)}pp</td>
                <td className="px-2 py-1.5 min-w-[100px]">
                  <BarraAvanceDual real={real} excel={excel} />
                </td>
                <td className="px-2 py-1.5">
                  <Link
                    href={`/dashboard/operacion-calama/ots/${ot.id}`}
                    className="inline-flex items-center gap-1 text-indigo-600 hover:text-indigo-800 text-xs"
                  >
                    Ver <ArrowRight className="h-3 w-3" />
                  </Link>
                </td>
              </tr>
            )
          })}
        </tbody>
      </table>
      {maxRows && ots.length > maxRows && (
        <p className="mt-2 text-xs text-gray-400 text-center">
          Mostrando {maxRows} de {ots.length} OTs.
        </p>
      )}
    </div>
  )
}

export function EstadoBadge({ estado }: { estado: string }) {
  const cfg: Record<string, { bg: string; fg: string; text: string }> = {
    planificada:   { bg: 'bg-slate-100',   fg: 'text-slate-700',   text: 'Planificada' },
    liberada:      { bg: 'bg-blue-100',    fg: 'text-blue-700',    text: 'Liberada' },
    en_ejecucion:  { bg: 'bg-amber-100',   fg: 'text-amber-700',   text: 'En ejecucion' },
    en_pausa:      { bg: 'bg-yellow-100',  fg: 'text-yellow-700',  text: 'Pausa' },
    finalizada:    { bg: 'bg-green-100',   fg: 'text-green-700',   text: 'Finalizada' },
    no_ejecutada:  { bg: 'bg-red-100',     fg: 'text-red-700',     text: 'No ejecutada' },
    cancelada:     { bg: 'bg-gray-100',    fg: 'text-gray-500',    text: 'Cancelada' },
  }
  const c = cfg[estado] ?? { bg: 'bg-gray-100', fg: 'text-gray-700', text: estado }
  return (
    <span className={`inline-flex rounded-full px-2 py-0.5 text-xs font-medium ${c.bg} ${c.fg}`}>
      {c.text}
    </span>
  )
}

function BarraAvance({ pct }: { pct: number }) {
  const v = Math.max(0, Math.min(100, Number(pct ?? 0)))
  const color = v >= 100 ? 'bg-green-500' : v >= 50 ? 'bg-blue-500' : 'bg-amber-500'
  return (
    <div className="flex items-center gap-1.5 justify-end">
      <span className="text-xs font-mono w-9 text-right">{v.toFixed(0)}%</span>
      <div className="h-1.5 w-16 rounded bg-gray-100 overflow-hidden">
        <div className={`h-full ${color}`} style={{ width: `${v}%` }} />
      </div>
    </div>
  )
}

/**
 * Barra dual: avance real (color solido) sobre la barra base de avance Excel
 * (linea punteada). Permite ver de un vistazo si vamos arriba o debajo del plan.
 */
export function BarraAvanceDual({ real, excel }: { real: number; excel: number }) {
  const r = Math.max(0, Math.min(100, Number(real ?? 0)))
  const e = Math.max(0, Math.min(100, Number(excel ?? 0)))
  const color = r >= 100 ? 'bg-green-500' : r >= e ? 'bg-blue-500' : r > 0 ? 'bg-amber-500' : 'bg-gray-300'
  return (
    <div className="relative h-2.5 w-full rounded bg-gray-100 overflow-hidden">
      {/* Marcador del avance Excel (linea vertical) */}
      {e > 0 && e < 100 && (
        <div
          className="absolute top-0 bottom-0 border-l-2 border-dashed border-indigo-400 z-10"
          style={{ left: `calc(${e}% - 1px)` }}
          aria-label={`Plan Excel ${e.toFixed(0)}%`}
        />
      )}
      <div className={`h-full ${color}`} style={{ width: `${r}%` }} />
    </div>
  )
}
