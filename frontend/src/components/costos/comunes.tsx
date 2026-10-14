'use client'

import { useQuery } from '@tanstack/react-query'
import { Truck } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Spinner } from '@/components/ui/spinner'
import { Modal } from '@/components/ui/modal'
import { getDetalleCostos, type CostoEquipo } from '@/lib/services/costos-operacion'
import {
  HORAS_MINIMAS_CPH, fmtClp, fmtMM, fmtNum, fmtPct, variacionPct, vsMediana, type RangoPreset,
} from '@/lib/costos-operacion'

// ============================================================================
// Piezas compartidas del panel de costos (Gerencia y Flota). MIG594-600.
// ============================================================================

export const COLOR_EQUIPO = '#2563EB'
export const COLOR_OTROS = '#F59E0B'

export const PRESETS: { id: RangoPreset; label: string }[] = [
  { id: 'mes', label: 'Mes en curso' },
  { id: '3m', label: 'Últimos 3 meses' },
  { id: 'ytd', label: 'Año a la fecha' },
  { id: '12m', label: 'Últimos 12 meses' },
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

export type Detalle = { titulo: string; codiCc?: string; familia?: string }

export function etiquetaEquipo(e: CostoEquipo) {
  return e.patente ? `${e.patente}${e.tipo_equipo ? ` · ${nombreTipo(e.tipo_equipo)}` : ''}` : (e.descripcion ?? e.codi_cc)
}

/** Gasto y costo por hora por equipo. Clic en una fila abre las salidas. */
export function TablaEquiposCosto({ equipos, onDetalle }: {
  equipos: CostoEquipo[]; onDetalle: (d: Detalle) => void
}) {
  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="flex items-center gap-2 text-base">
          <Truck className="h-4 w-4" /> Gasto y costo por hora por equipo
          <span className="text-xs font-normal text-gray-500">— clic en una fila para ver las salidas</span>
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
            {equipos.slice(0, 80).map((e) => {
              const v = variacionPct(e.total, e.total_anterior)
              const r = vsMediana(e.costo_hora, e.mediana_tipo, e.horas, e.n_tipo)
              const pocas = e.costo_hora != null && (e.horas ?? 0) < HORAS_MINIMAS_CPH
              return (
                <tr key={e.codi_cc} className="cursor-pointer border-t hover:bg-gray-50"
                    onClick={() => onDetalle({ titulo: etiquetaEquipo(e), codiCc: e.codi_cc })}>
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
export function Barras({ filas, formato }: {
  filas: { label: string; valor: number }[]; formato: (v: number) => string
}) {
  const max = Math.max(1, ...filas.map((f) => f.valor))
  if (filas.length === 0) return <div className="py-6 text-center text-sm text-gray-500">Sin datos.</div>
  return (
    <div className="space-y-2">
      {filas.map((f) => (
        <div key={f.label} className="text-sm" title={`${f.label}: ${formato(f.valor)}`}>
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

export function DetalleModal({ detalle, desde, hasta, onClose }: {
  detalle: Detalle; desde: string; hasta: string; onClose: () => void
}) {
  const { data, isLoading, error } = useQuery({
    queryKey: ['costos-operacion-detalle', desde, hasta, detalle.codiCc, detalle.familia],
    queryFn: () => getDetalleCostos({ desde, hasta, codiCc: detalle.codiCc, familia: detalle.familia }),
  })
  const total = (data ?? []).reduce((s, l) => s + l.total, 0)
  return (
    <Modal open onClose={onClose} title={detalle.titulo}
           description={`Salidas de bodega Softland, de mayor a menor (máx. 500) · ${fmtClp(total)}`}
           className="max-w-5xl">
      {isLoading && <div className="flex justify-center py-8"><Spinner /></div>}
      {error && <div className="text-sm text-red-700">{(error as Error).message}</div>}
      {data && (
        <div className="max-h-[65vh] overflow-auto">
          <table className="w-full text-xs">
            <thead className="sticky top-0 bg-gray-50 text-gray-600">
              <tr>
                <th className="px-2 py-1.5 text-left">Fecha</th>
                <th className="px-2 py-1.5 text-left">Folio</th>
                <th className="px-2 py-1.5 text-left">Bodega</th>
                <th className="px-2 py-1.5 text-left">CC</th>
                <th className="px-2 py-1.5 text-left">Producto</th>
                <th className="px-2 py-1.5 text-right">Cant.</th>
                <th className="px-2 py-1.5 text-right">Precio</th>
                <th className="px-2 py-1.5 text-right">Total</th>
                <th className="px-2 py-1.5 text-left">Glosa</th>
              </tr>
            </thead>
            <tbody>
              {data.map((l, i) => (
                <tr key={i} className={`border-t ${l.total === 0 ? 'bg-amber-50' : ''}`}>
                  <td className="px-2 py-1">{l.fecha}</td>
                  <td className="px-2 py-1">{l.folio}{l.concepto === '08' ? ' (EPP)' : ''}</td>
                  <td className="px-2 py-1">{l.bodega}</td>
                  <td className="px-2 py-1">{l.codi_cc}</td>
                  <td className="px-2 py-1">{l.des_prod} <span className="text-gray-400">{l.cod_prod}</span></td>
                  <td className="px-2 py-1 text-right">{fmtNum(l.cantidad)}</td>
                  <td className="px-2 py-1 text-right">{fmtClp(l.precio_unit)}</td>
                  <td className="px-2 py-1 text-right font-medium">{fmtClp(l.total)}</td>
                  <td className="px-2 py-1 text-gray-500">{l.glosa}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </Modal>
  )
}
