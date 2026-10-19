'use client'

import { useState } from 'react'
import { Info, Truck } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import type { CostoEquipo } from '@/lib/services/costos-operacion'
import type { PasoPareto } from '@/components/costos/pareto-modal'
import {
  HORAS_MINIMAS_CPH, fmtClp, fmtMM, fmtNum, fmtPct, variacionPct, vsMediana, type RangoPreset,
} from '@/lib/costos-operacion'

// ============================================================================
// Piezas compartidas del panel de costos (Gerencia y Flota). MIG594-600.
// ============================================================================

export const COLOR_EQUIPO = '#2563EB'
export const COLOR_OTROS = '#F59E0B'

/** Filtros de período. El panel abre en «Este año» (Manuel: «ver solo este año»). */
export const PRESETS: { id: RangoPreset; label: string }[] = [
  { id: 'ytd', label: `Este año ${new Date().getFullYear()}` },
  { id: 'mes', label: 'Mes en curso' },
  { id: '3m', label: 'Últimos 3 meses' },
  { id: '12m', label: 'Últimos 12 meses' },
  { id: 'anio_ant', label: `Año ${new Date().getFullYear() - 1}` },
]

export const MESES = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic']
export const fmtMes = (iso: string) => `${MESES[Number(iso.slice(5, 7)) - 1]} ${iso.slice(2, 4)}`
export const fmtFecha = (iso: string | null) => iso
  ? new Date(iso + 'T12:00:00').toLocaleDateString('es-CL', { day: '2-digit', month: 'short', year: '2-digit' }) : '—'

export const NOMBRE_TIPO: Record<string, string> = {
  aljibe_combustible: 'Aljibe combustible', aljibe_agua: 'Aljibe agua', camioneta: 'Camioneta',
  pluma_grua: 'Pluma / grúa', generico: 'Otros (tipo sin definir)', lubricador: 'Lubricador',
}
export const nombreTipo = (t: string | null) => (t ? NOMBRE_TIPO[t] ?? t.replace(/_/g, ' ') : '—')


/**
 * Las tablas del panel muestran sólo los 10 con más gasto (Manuel: el panel va
 * al dueño, «no tan extenso»); el resto queda a un clic. `filas` ya viene
 * ordenado por gasto descendente desde el RPC.
 */
export const TOP_N = 10
export function useTop<T>(filas: T[], n = TOP_N) {
  const [todos, setTodos] = useState(false)
  const visibles = todos ? filas : filas.slice(0, n)
  const pie = filas.length > n ? (
    <button type="button" onClick={() => setTodos(!todos)}
            className="w-full border-t px-3 py-2 text-left text-xs font-medium text-pillado-green-700 hover:bg-gray-50">
      {todos ? `Mostrar sólo los ${n} con más gasto` : `Ver los ${filas.length} (${filas.length - n} más)`}
    </button>
  ) : null
  return { visibles, pie }
}

export function etiquetaEquipo(e: CostoEquipo) {
  return e.patente ? `${e.patente}${e.tipo_equipo ? ` · ${nombreTipo(e.tipo_equipo)}` : ''}` : (e.descripcion ?? e.codi_cc)
}

/** Gasto y costo por hora por equipo. Clic en una fila abre las salidas. */
/** Paso de Pareto de un equipo: qué familias explican su gasto. */
export function paretoEquipo(e: CostoEquipo): PasoPareto {
  return {
    titulo: etiquetaEquipo(e),
    filtros: e.activo_id ? { activo_id: e.activo_id } : { codi_cc: e.codi_cc },
    dimension: 'familia',
  }
}

export function TablaEquiposCosto({ equipos, onPareto }: {
  equipos: CostoEquipo[]; onPareto: (p: PasoPareto) => void
}) {
  const { visibles, pie } = useTop(equipos)
  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="flex items-center gap-2 text-base">
          <Truck className="h-4 w-4" /> Los {Math.min(TOP_N, equipos.length)} equipos con más gasto
          <span className="text-xs font-normal text-gray-500">— clic en una fila: Pareto de lo que explica su gasto</span>
        </CardTitle>
      </CardHeader>
      <CardContent className="overflow-x-auto p-0">
        <table className="w-full text-sm">
          <thead className="bg-gray-50 text-xs text-gray-600">
            <tr>
              <th className="px-3 py-2 text-left">Equipo</th>
              <th className="px-3 py-2 text-right">Repuestos</th>
              <th className="px-3 py-2 text-right">Neumáticos</th>
              <th className="px-3 py-2 text-right">Lubricantes</th>
              <th className="px-3 py-2 text-right">Total</th>
              <th className="px-3 py-2 text-right">vs anterior</th>
              <th className="px-3 py-2 text-right">Horas medidas</th>
              <th className="px-3 py-2 text-right">$/hora</th>
              <th className="px-3 py-2 text-right">vs su tipo</th>
            </tr>
          </thead>
          <tbody>
            {visibles.map((e) => {
              const v = variacionPct(e.total, e.total_anterior)
              const r = vsMediana(e.costo_hora, e.mediana_tipo, e.horas, e.n_tipo)
              const pocas = e.costo_hora != null && (e.horas ?? 0) < HORAS_MINIMAS_CPH
              return (
                <tr key={e.codi_cc} className="cursor-pointer border-t hover:bg-gray-50"
                    onClick={() => onPareto(paretoEquipo(e))}>
                  <td className="px-3 py-1.5">
                    <div className="font-medium">{e.patente ?? e.codi_cc}</div>
                    <div className="text-xs text-gray-500">{nombreTipo(e.tipo_equipo)} · {e.faena ?? '—'}</div>
                  </td>
                  <td className="px-3 py-1.5 text-right">{fmtMM(e.repuestos)}</td>
                  <td className="px-3 py-1.5 text-right">{fmtMM(e.neumaticos)}</td>
                  <td className="px-3 py-1.5 text-right">{fmtMM(e.lubricantes)}</td>
                  <td className="px-3 py-1.5 text-right font-medium">{fmtMM(e.total)}</td>
                  <td className={`px-3 py-1.5 text-right ${v != null && v > 25 ? 'text-red-700' : v != null && v < -25 ? 'text-green-700' : ''}`}>
                    {fmtPct(v, true)}
                  </td>
                  <td className="px-3 py-1.5 text-right"
                      title={e.medido_desde ? `${fmtFecha(e.medido_desde)} (${e.fuente_ini}) → ${fmtFecha(e.medido_hasta)} (${e.fuente_fin})` : 'Sin dos lecturas de horómetro creíbles en el período'}>
                    {fmtNum(e.horas)}
                    {e.dias_medidos != null && <div className="text-xs text-gray-400">{e.dias_medidos} días</div>}
                  </td>
                  <td className={`px-3 py-1.5 text-right font-medium ${pocas ? 'text-gray-400' : ''}`}
                      title={pocas ? `Menos de ${HORAS_MINIMAS_CPH} h medidas: no se compara` : undefined}>
                    {e.costo_hora != null ? fmtClp(e.costo_hora) : '—'}
                  </td>
                  <td className={`px-3 py-1.5 text-right ${r != null && r >= 1.5 ? 'font-medium text-red-700' : r != null && r <= 0.67 ? 'text-green-700' : ''}`}>
                    {r != null ? `${r.toLocaleString('es-CL', { maximumFractionDigits: 1 })}×` : '—'}
                  </td>
                </tr>
              )
            })}
          </tbody>
        </table>
        {pie}
        <p className="px-3 py-2 text-xs text-gray-400">
          Costo por hora = gasto de bodega entre dos lecturas de horómetro (GPS, recepción en taller, OS,
          preventivas) ÷ horas entre ellas. Pasa el mouse por las horas para ver qué lecturas se usaron.
          «vs su tipo» compara contra la mediana de equipos del mismo tipo.
        </p>
      </CardContent>
    </Card>
  )
}

/** Barras horizontales simples (un valor por renglón). */
export function Barras({ filas, formato, onClick }: {
  filas: { label: string; valor: number; clave?: string }[]
  formato: (v: number) => string
  onClick?: (f: { label: string; valor: number; clave?: string }) => void
}) {
  const max = Math.max(1, ...filas.map((f) => f.valor))
  if (filas.length === 0) return <div className="py-6 text-center text-sm text-gray-500">Sin datos.</div>
  return (
    <div className="space-y-2">
      {filas.map((f) => (
        <div key={f.label} title={`${f.label}: ${formato(f.valor)}`}
             className={`text-sm ${onClick ? 'cursor-pointer rounded hover:bg-gray-50' : ''}`}
             onClick={onClick ? () => onClick(f) : undefined}>
          <div className="flex justify-between gap-2">
            <span className="truncate">{f.label}</span>
            <span className="shrink-0 font-medium">{formato(f.valor)}</span>
          </div>
          <div className="mt-0.5 h-2 w-full overflow-hidden rounded bg-gray-100">
            <div className="h-full rounded" style={{ width: `${(f.valor / max) * 100}%`, background: COLOR_EQUIPO }} />
          </div>
        </div>
      ))}
    </div>
  )
}

/**
 * «¿Cómo se calcula?» desplegable (clic, no hover: sirve en el teléfono).
 * Cada tarjeta del panel explica su fórmula con los números del período.
 */
export function ComoSeCalcula({ children }: { children: React.ReactNode }) {
  const [abierto, setAbierto] = useState(false)
  return (
    <div className="mt-2" onClick={(e) => e.stopPropagation()}>
      <button onClick={() => setAbierto(!abierto)}
              className="flex items-center gap-1 text-xs font-medium text-pillado-green-700 hover:underline">
        <Info className="h-3.5 w-3.5" /> {abierto ? 'Ocultar cálculo' : '¿Cómo se calcula?'}
      </button>
      {abierto && (
        <div className="mt-1.5 space-y-1.5 rounded-md bg-gray-50 p-2.5 text-xs leading-relaxed text-gray-700">
          {children}
        </div>
      )}
    </div>
  )
}
