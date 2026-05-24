'use client'

import { Calendar, Fuel, TrendingDown, AlertTriangle, CheckCircle2 } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Spinner } from '@/components/ui/spinner'
import { useCombustibleProyeccion } from '@/hooks/use-combustible-proyeccion'
import type { CombustibleProyeccion } from '@/lib/services/combustible-proyeccion'

interface Props {
  /** Si true, muestra modo compacto (1 fila por estanque). Default false (1 card por estanque). */
  compacto?: boolean
  /** Encabezado custom. Default: "Proyección de stock combustible (demanda MYG + LISSET)" */
  titulo?: string
}

function fmt(n: number | null | undefined, d = 0): string {
  if (n == null) return '—'
  return n.toLocaleString('es-CL', { maximumFractionDigits: d })
}

function colorSeveridad(sev: CombustibleProyeccion['severidad']) {
  switch (sev) {
    case 'agotado':  return { border: 'border-red-400 bg-red-50',     text: 'text-red-800', badge: 'bg-red-600 text-white', label: 'AGOTADO' }
    case 'critico':  return { border: 'border-red-300 bg-red-50',     text: 'text-red-800', badge: 'bg-red-500 text-white', label: 'CRÍTICO' }
    case 'urgente':  return { border: 'border-orange-300 bg-orange-50', text: 'text-orange-800', badge: 'bg-orange-500 text-white', label: 'URGENTE (≤3d)' }
    case 'atencion': return { border: 'border-amber-300 bg-amber-50',  text: 'text-amber-800', badge: 'bg-amber-500 text-white', label: 'ATENCIÓN (≤7d)' }
    default:         return { border: 'border-green-200 bg-green-50',  text: 'text-green-800', badge: 'bg-green-500 text-white', label: 'OK' }
  }
}

function fechaCorta(iso: string | null): string {
  if (!iso) return '—'
  return new Date(iso + 'T12:00:00').toLocaleDateString('es-CL', { day: '2-digit', month: 'short' })
}

export function ProyeccionStockCard({ compacto = false, titulo }: Props) {
  const { data, isLoading } = useCombustibleProyeccion()
  const heading = titulo ?? 'Proyección de stock — demanda real (MYG + LISSET)'

  if (isLoading) {
    return <Card><CardContent className="flex justify-center py-8"><Spinner /></CardContent></Card>
  }
  if (!data || data.length === 0) {
    return null
  }

  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-base flex items-center justify-between gap-2">
          <span className="flex items-center gap-2">
            <Fuel className="h-5 w-5 text-amber-700" />
            {heading}
          </span>
          <span className="text-[10px] font-normal text-gray-500">
            Excluye traspasos entre estanques y recirculaciones
          </span>
        </CardTitle>
      </CardHeader>
      <CardContent className={compacto ? 'p-0' : ''}>
        {compacto ? (
          <table className="w-full text-xs">
            <thead className="bg-gray-50">
              <tr>
                <th className="px-3 py-2 text-left">Estanque</th>
                <th className="px-3 py-2 text-right">Stock actual</th>
                <th className="px-3 py-2 text-right">Hoy (MYG+LISSET)</th>
                <th className="px-3 py-2 text-right">Prom. 7d</th>
                <th className="px-3 py-2 text-right">Días cobertura</th>
                <th className="px-3 py-2 text-right">Agotam. estimado</th>
                <th className="px-3 py-2 text-center">Estado</th>
              </tr>
            </thead>
            <tbody>
              {data.map((p) => {
                const c = colorSeveridad(p.severidad)
                return (
                  <tr key={p.estanque_id} className="border-t hover:bg-gray-50">
                    <td className="px-3 py-2">
                      <div className="font-mono font-bold">{p.estanque_codigo}</div>
                      <div className="text-[10px] text-gray-500">{p.estanque_nombre}</div>
                    </td>
                    <td className="px-3 py-2 text-right font-mono">
                      {fmt(p.stock_actual, 0)} L
                      <div className="text-[10px] text-gray-500">de {fmt(p.capacidad_lt, 0)}</div>
                    </td>
                    <td className="px-3 py-2 text-right font-mono">
                      {fmt(p.litros_hoy, 0)} L
                      {p.despachos_hoy > 0 && <div className="text-[10px] text-gray-500">{p.despachos_hoy} desp.</div>}
                    </td>
                    <td className="px-3 py-2 text-right font-mono">{fmt(p.promedio_diario_7d, 0)} L/d</td>
                    <td className="px-3 py-2 text-right font-mono font-bold">
                      {p.dias_cobertura != null ? `${fmt(p.dias_cobertura, 1)}d` : '—'}
                    </td>
                    <td className="px-3 py-2 text-right">{fechaCorta(p.fecha_agotamiento_estimada)}</td>
                    <td className="px-3 py-2 text-center">
                      <span className={`rounded px-1.5 py-0.5 text-[9px] font-bold ${c.badge}`}>{c.label}</span>
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
            {data.map((p) => {
              const c = colorSeveridad(p.severidad)
              const fillPct = p.capacidad_lt > 0 ? Math.min(100, (p.stock_actual / p.capacidad_lt) * 100) : 0
              return (
                <div key={p.estanque_id} className={`rounded-lg border-2 p-3 ${c.border}`}>
                  <div className="flex items-start justify-between gap-2 mb-2">
                    <div>
                      <div className="font-mono font-bold text-sm">{p.estanque_codigo}</div>
                      <div className="text-[10px] text-gray-600 truncate">{p.estanque_nombre}</div>
                    </div>
                    <span className={`rounded px-1.5 py-0.5 text-[9px] font-bold ${c.badge}`}>{c.label}</span>
                  </div>
                  <div className="flex items-baseline gap-1">
                    <span className={`text-2xl font-bold ${c.text}`}>{fmt(p.stock_actual, 0)}</span>
                    <span className="text-xs text-gray-500">/ {fmt(p.capacidad_lt, 0)} L</span>
                  </div>
                  <div className="h-2 w-full bg-gray-100 rounded overflow-hidden mt-1">
                    <div className={c.badge} style={{ width: `${fillPct}%`, height: '100%' }} />
                  </div>
                  <div className="grid grid-cols-2 gap-2 mt-3 text-[11px]">
                    <div>
                      <div className="text-gray-500 flex items-center gap-1">
                        <Calendar className="h-3 w-3" /> Días cobertura
                      </div>
                      <div className={`font-bold ${c.text}`}>
                        {p.dias_cobertura != null ? `${fmt(p.dias_cobertura, 1)}d` : '—'}
                      </div>
                    </div>
                    <div>
                      <div className="text-gray-500 flex items-center gap-1">
                        <TrendingDown className="h-3 w-3" /> Demanda 7d
                      </div>
                      <div className="font-bold">{fmt(p.promedio_diario_7d, 0)} L/d</div>
                    </div>
                    <div>
                      <div className="text-gray-500">Hoy</div>
                      <div>
                        {fmt(p.litros_hoy, 0)} L
                        {p.despachos_hoy > 0 && <span className="text-gray-500 text-[10px] ml-1">({p.despachos_hoy})</span>}
                      </div>
                    </div>
                    <div>
                      <div className="text-gray-500">Se agota</div>
                      <div>{fechaCorta(p.fecha_agotamiento_estimada)}</div>
                    </div>
                  </div>
                  {p.severidad === 'ok' && p.dias_hasta_minimo != null && (
                    <div className="text-[10px] text-gray-600 mt-2 flex items-center gap-1">
                      <CheckCircle2 className="h-3 w-3 text-green-600" />
                      {fmt(p.dias_hasta_minimo, 1)}d hasta stock mínimo
                    </div>
                  )}
                  {(p.severidad === 'urgente' || p.severidad === 'critico' || p.severidad === 'agotado') && (
                    <div className="text-[10px] text-red-700 mt-2 flex items-center gap-1 font-semibold">
                      <AlertTriangle className="h-3 w-3" />
                      Reponer combustible YA
                    </div>
                  )}
                </div>
              )
            })}
          </div>
        )}
      </CardContent>
    </Card>
  )
}
