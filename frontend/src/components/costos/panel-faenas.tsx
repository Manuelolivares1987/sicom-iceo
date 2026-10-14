'use client'

import { Fragment, useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import {
  Bar, BarChart, CartesianGrid, Legend, ResponsiveContainer, Tooltip, XAxis, YAxis,
} from 'recharts'
import { ChevronDown, ChevronRight, MapPin } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Spinner } from '@/components/ui/spinner'
import { getCostosPorFaena, type FaenaCosto } from '@/lib/services/costos-operacion'
import { fmtClp, fmtMM, fmtNum, fmtPct, pct } from '@/lib/costos-operacion'
import { fmtMes } from '@/components/costos/comunes'

// ============================================================================
// Costos por faena (MIG600)
// ----------------------------------------------------------------------------
// El gasto de un equipo va a la faena donde estaba el día del gasto; cada
// faena suma también sus centros de costo propios (Operaciones Franke…).
// Para comparar faenas de distinto tamaño: costo por equipo-día y por hora.
// Sin petróleo (se revende).
// ============================================================================

// Orden y color fijos por faena: el color sigue a la faena, no a su ranking.
const FAENAS: { id: string; color: string }[] = [
  { id: 'Franke', color: '#2a78d6' },
  { id: 'Romeral', color: '#eb6834' },
  { id: 'Calama', color: '#1baf7a' },
  { id: 'Otras faenas', color: '#eda100' },
  { id: 'Taller / sin contrato', color: '#e87ba4' },
  { id: 'Sin centro de costo', color: '#008300' },
]
const orden = (f: string) => {
  const i = FAENAS.findIndex((x) => x.id === f)
  return i < 0 ? 99 : i
}

export function PanelFaenas({ desde, hasta }: { desde: string; hasta: string }) {
  const [abierta, setAbierta] = useState<string | null>(null)
  const { data, isLoading, error } = useQuery({
    queryKey: ['costos-por-faena', desde, hasta],
    queryFn: () => getCostosPorFaena(desde, hasta),
    staleTime: 5 * 60_000,
  })

  const faenas = useMemo(
    () => [...(data?.faenas ?? [])].sort((a, b) => orden(a.faena) - orden(b.faena)),
    [data],
  )
  const total = faenas.reduce((s, f) => s + f.total, 0)

  const serie = useMemo(() => {
    const porMes = new Map<string, Record<string, number | string>>()
    for (const r of data?.por_mes ?? []) {
      const fila = porMes.get(r.mes) ?? { mes: fmtMes(r.mes) }
      fila[r.faena] = Math.round(r.total)
      porMes.set(r.mes, fila)
    }
    return Array.from(porMes.entries()).sort(([a], [b]) => a.localeCompare(b)).map(([, v]) => v)
  }, [data])
  const presentes = FAENAS.filter((f) => faenas.some((x) => x.faena === f.id))

  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="flex items-center gap-2 text-base">
          <MapPin className="h-4 w-4" /> Costo por faena
          <span className="text-xs font-normal text-gray-500">
            — cada gasto va a la faena donde estaba el equipo ese día
          </span>
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        {isLoading && <div className="flex justify-center py-10"><Spinner /></div>}
        {error && <div className="text-sm text-red-700">{(error as Error).message}</div>}
        {data && (
          <>
            {/* Tarjetas de las tres faenas grandes */}
            <div className="grid grid-cols-1 gap-3 md:grid-cols-3">
              {['Franke', 'Romeral', 'Calama'].map((id) => {
                const f = faenas.find((x) => x.faena === id)
                const color = FAENAS.find((x) => x.id === id)?.color
                return (
                  <div key={id} className="rounded-lg border p-3" style={{ borderLeft: `4px solid ${color}` }}>
                    <div className="text-sm font-semibold text-gray-800">{id}</div>
                    {f ? (
                      <>
                        <div className="mt-1 text-2xl font-bold text-gray-900">{fmtMM(f.total)}</div>
                        <div className="text-xs text-gray-500">{fmtPct(pct(f.total, total))} del gasto · {fmtNum(f.equipos)} equipos</div>
                        <div className="mt-2 grid grid-cols-2 gap-2 text-sm">
                          <div>
                            <div className="text-xs text-gray-500">Por equipo-día</div>
                            <div className="font-medium">{fmtClp(f.costo_equipo_dia)}</div>
                          </div>
                          <div>
                            <div className="text-xs text-gray-500">Por hora operada</div>
                            <div className="font-medium">{f.costo_hora != null ? `${fmtClp(f.costo_hora)}/h` : '—'}</div>
                          </div>
                        </div>
                      </>
                    ) : <div className="mt-2 text-sm text-gray-500">Sin gasto en el período.</div>}
                  </div>
                )
              })}
            </div>

            {/* Gasto mensual por faena */}
            {serie.length > 0 && (
              <div style={{ width: '100%', height: 280 }}>
                <ResponsiveContainer>
                  <BarChart data={serie} margin={{ top: 10, right: 10, left: 10, bottom: 0 }}>
                    <CartesianGrid strokeDasharray="3 3" stroke="#E5E7EB" vertical={false} />
                    <XAxis dataKey="mes" tick={{ fontSize: 11 }} />
                    <YAxis tick={{ fontSize: 11 }} tickFormatter={(v: number) => `${Math.round(v / 1e6)} M`} />
                    <Tooltip formatter={(v: number, n: string) => [fmtClp(v), n]} cursor={{ fill: '#F3F4F6' }} />
                    <Legend wrapperStyle={{ fontSize: 12 }} />
                    {presentes.map((f, i) => (
                      <Bar key={f.id} dataKey={f.id} stackId="f" fill={f.color} stroke="#fff" strokeWidth={1}
                           radius={i === presentes.length - 1 ? [4, 4, 0, 0] : undefined} />
                    ))}
                  </BarChart>
                </ResponsiveContainer>
              </div>
            )}

            {/* Tabla: todas las faenas, con el detalle desplegable */}
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="bg-gray-50 text-xs text-gray-600">
                  <tr>
                    <th className="px-3 py-2 text-left">Faena</th>
                    <th className="px-3 py-2 text-right">Total</th>
                    <th className="px-3 py-2 text-right">En equipos</th>
                    <th className="px-3 py-2 text-right">CC propios</th>
                    <th className="px-3 py-2 text-right">Repuestos</th>
                    <th className="px-3 py-2 text-right">Neumáticos</th>
                    <th className="px-3 py-2 text-right">Lubricantes</th>
                    <th className="px-3 py-2 text-right">Equipos</th>
                    <th className="px-3 py-2 text-right">$/equipo-día</th>
                    <th className="px-3 py-2 text-right">$/hora</th>
                  </tr>
                </thead>
                <tbody>
                  {faenas.map((f) => (
                    <FilaFaena key={f.faena} f={f} abierta={abierta === f.faena}
                               onToggle={() => setAbierta(abierta === f.faena ? null : f.faena)}
                               equipos={(data.equipos ?? []).filter((e) => e.faena === f.faena).slice(0, 8)}
                               directos={(data.directos ?? []).filter((d) => d.faena === f.faena).slice(0, 6)} />
                  ))}
                </tbody>
              </table>
              <p className="mt-2 text-xs text-gray-400">
                «$/equipo-día» = gasto en equipos ÷ días que los equipos estuvieron en la faena (sirve para comparar
                faenas de distinto tamaño). «$/hora» usa las horas medidas por horómetro. La ubicación diaria sale del
                estado diario de flota; si un día no tiene, se usa la última conocida.
              </p>
            </div>
          </>
        )}
      </CardContent>
    </Card>
  )
}

function FilaFaena({ f, abierta, onToggle, equipos, directos }: {
  f: FaenaCosto
  abierta: boolean
  onToggle: () => void
  equipos: { patente: string | null; total: number }[]
  directos: { codi_cc: string | null; descripcion: string | null; total: number }[]
}) {
  const color = FAENAS.find((x) => x.id === f.faena)?.color ?? '#9CA3AF'
  const Chevron = abierta ? ChevronDown : ChevronRight
  return (
    <Fragment>
      <tr className="cursor-pointer border-t hover:bg-gray-50" onClick={onToggle}>
        <td className="px-3 py-1.5">
          <span className="flex items-center gap-2 font-medium">
            <Chevron className="h-4 w-4 text-gray-400" />
            <i className="inline-block h-3 w-3 rounded-sm" style={{ background: color }} />
            {f.faena}
          </span>
        </td>
        <td className="px-3 py-1.5 text-right font-medium">{fmtMM(f.total)}</td>
        <td className="px-3 py-1.5 text-right">{fmtMM(f.equipos_costo)}</td>
        <td className="px-3 py-1.5 text-right">{fmtMM(f.directo)}</td>
        <td className="px-3 py-1.5 text-right">{fmtMM(f.repuestos)}</td>
        <td className="px-3 py-1.5 text-right">{fmtMM(f.neumaticos)}</td>
        <td className="px-3 py-1.5 text-right">{fmtMM(f.lubricantes)}</td>
        <td className="px-3 py-1.5 text-right">{fmtNum(f.equipos)}</td>
        <td className="px-3 py-1.5 text-right">{fmtClp(f.costo_equipo_dia)}</td>
        <td className="px-3 py-1.5 text-right">{f.costo_hora != null ? fmtClp(f.costo_hora) : '—'}</td>
      </tr>
      {abierta && (
        <tr className="bg-gray-50">
          <td colSpan={10} className="px-6 py-3">
            <div className="grid grid-cols-1 gap-4 text-sm md:grid-cols-2">
              <div>
                <div className="mb-1 text-xs font-semibold uppercase text-gray-500">Equipos que más gastaron aquí</div>
                {equipos.length === 0 ? <div className="text-gray-500">—</div> : equipos.map((e, i) => (
                  <div key={i} className="flex justify-between border-b border-gray-200 py-0.5">
                    <span>{e.patente ?? '—'}</span><span>{fmtMM(e.total)}</span>
                  </div>
                ))}
              </div>
              <div>
                <div className="mb-1 text-xs font-semibold uppercase text-gray-500">Centros de costo propios</div>
                {directos.length === 0 ? <div className="text-gray-500">—</div> : directos.map((d, i) => (
                  <div key={i} className="flex justify-between border-b border-gray-200 py-0.5">
                    <span>{d.descripcion ?? d.codi_cc ?? 'Sin centro de costo'}</span><span>{fmtMM(d.total)}</span>
                  </div>
                ))}
              </div>
            </div>
          </td>
        </tr>
      )}
    </Fragment>
  )
}
