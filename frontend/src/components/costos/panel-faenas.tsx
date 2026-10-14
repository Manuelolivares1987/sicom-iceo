'use client'

import { Fragment, useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import {
  Bar, BarChart, CartesianGrid, Legend, ResponsiveContainer, Tooltip, XAxis, YAxis,
} from 'recharts'
import { ChevronDown, ChevronRight, MapPin, Target } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Spinner } from '@/components/ui/spinner'
import { getCostosPorFaena, type FaenaCosto } from '@/lib/services/costos-operacion'
import { fmtClp, fmtMM, fmtNum, fmtPct, pct } from '@/lib/costos-operacion'
import { ComoSeCalcula, fmtMes } from '@/components/costos/comunes'
import type { PasoPareto } from '@/components/costos/pareto-modal'

// ============================================================================
// Costos por faena (MIG600-602)
// ----------------------------------------------------------------------------
// Pillado opera Franke, Romeral y Calama. En Calama (Spence, Centinela —
// Contrato ESM— y Lomas Bayas) el negocio es el SERVICIO DE CALIBRACIONES
// (los CC de Calama); los camiones que están ahí son ARRIENDO a clientes
// (MIG603). El gasto de un equipo va a la faena donde estaba ese día (GPS
// primero, estado diario después). Todo clic abre un Pareto; en Franke y
// Romeral, por familia: en qué se gasta.
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
const OPERACION_PILLADO = ['Franke', 'Romeral', 'Calama']
const CALIBRACIONES = 'Calibraciones (servicio Calama)'
const orden = (f: string) => {
  const i = FAENAS.findIndex((x) => x.id === f)
  return i < 0 ? 99 : i
}
const colorDe = (f: string) => FAENAS.find((x) => x.id === f)?.color ?? '#9CA3AF'

export function PanelFaenas({ desde, hasta, onPareto }: {
  desde: string; hasta: string; onPareto: (p: PasoPareto) => void
}) {
  const [abierta, setAbierta] = useState<string | null>('Calama')
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
  const subDe = (faena: string) => (data?.subfaenas ?? []).filter((s) => s.faena === faena)

  const serie = useMemo(() => {
    const porMes = new Map<string, Record<string, number | string>>()
    for (const r of data?.por_mes ?? []) {
      const fila = porMes.get(r.mes) ?? { mes: fmtMes(r.mes), mesIso: r.mes }
      fila[r.faena] = Math.round(r.total)
      porMes.set(r.mes, fila)
    }
    return Array.from(porMes.entries()).sort(([a], [b]) => a.localeCompare(b)).map(([, v]) => v)
  }, [data])
  const presentes = FAENAS.filter((f) => faenas.some((x) => x.faena === f.id))

  // Franke y Romeral: en qué se gasta (familia). Calama: primero qué negocio.
  const paretoFaena = (faena: string): PasoPareto => ({
    titulo: faena, filtros: { faena },
    dimension: faena === 'Calama' ? 'subfaena' : OPERACION_PILLADO.includes(faena) ? 'familia' : 'equipo',
  })
  const paretoSub = (faena: string, sub: string): PasoPareto => ({
    titulo: sub, filtros: { faena, subfaena: sub },
    dimension: sub.startsWith('Arriendo') ? 'equipo' : 'familia',
  })

  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="flex flex-wrap items-center gap-2 text-base">
          <MapPin className="h-4 w-4" /> Costo por faena
          <span className="text-xs font-normal text-gray-500">
            — cada gasto va a la faena donde estaba el equipo ese día (GPS). Clic en cualquier parte: Pareto de en qué se gasta.
          </span>
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        {isLoading && <div className="flex justify-center py-10"><Spinner /></div>}
        {error && <div className="text-sm text-red-700">{(error as Error).message}</div>}
        {data && (
          <>
            {/* Operación Pillado: Franke, Romeral, Calama */}
            <div className="grid grid-cols-1 gap-3 md:grid-cols-3">
              {OPERACION_PILLADO.map((id) => {
                const f = faenas.find((x) => x.faena === id)
                return (
                  <div key={id} onClick={() => f && onPareto(paretoFaena(id))}
                       className="cursor-pointer rounded-lg border p-3 hover:bg-gray-50"
                       style={{ borderLeft: `4px solid ${colorDe(id)}` }}>
                    <div className="flex items-center justify-between text-sm font-semibold text-gray-800">
                      {id}
                      <span className="flex items-center gap-1 text-xs font-normal text-pillado-green-700">
                        <Target className="h-3.5 w-3.5" /> Pareto
                      </span>
                    </div>
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
                        <ComoSeCalcula>
                          <p><b>Total</b> = lo que gastaron los equipos mientras estaban en {id} + los centros de costo
                            propios de {id} en Softland{id === 'Calama' ? ' (Operaciones, Proyectos y Taller Calama = calibraciones)' : ` (Operaciones ${id})`}.
                            El gasto de un equipo va a la faena donde estaba <b>ese día</b>: primero el GPS (geocerca),
                            si no hay GPS el estado diario de flota, y si no, la última ubicación conocida.</p>
                          <p><b>Por equipo-día</b> = gasto en equipos ÷ días que los equipos estuvieron en {id}:
                            {' '}{fmtMM(f.equipos_costo)} ÷ {fmtNum(f.dias_equipo)} días = {fmtClp(f.costo_equipo_dia)}.
                            Sirve para comparar faenas de distinto tamaño.</p>
                          <p><b>Por hora operada</b> = mismo método que el costo por hora de la flota (dos lecturas de
                            horómetro creíbles por equipo), pero las horas de cada equipo se reparten parejo por día y cada
                            día se asigna a la faena donde estaba: {fmtClp(f.costo_medido)} ÷ {fmtNum(f.horas)} h
                            = {f.costo_hora != null ? `${fmtClp(f.costo_hora)}/h` : '—'}.</p>
                        </ComoSeCalcula>
                        {id === 'Calama' && (() => {
                          const subs = subDe('Calama')
                          const cal = subs.find((x) => x.subfaena === CALIBRACIONES)
                          const arr = subs.filter((x) => x.subfaena.startsWith('Arriendo'))
                          const otros = subs.filter((x) => x !== cal && !arr.includes(x))
                          const linea = (label: string, valor: number | null, onClick?: () => void, sangria = false) => (
                            <div key={label} className={`flex justify-between rounded px-1 hover:bg-white ${sangria ? 'pl-4 text-gray-600' : 'font-medium'}`}
                                 onClick={(ev) => { ev.stopPropagation(); onClick?.() }}>
                              <span>{label}</span><span>{fmtMM(valor)}</span>
                            </div>
                          )
                          return (
                            <div className="mt-2 space-y-0.5 border-t pt-2 text-xs">
                              {linea('Calibraciones (servicio)', cal?.total ?? null,
                                     cal ? () => onPareto(paretoSub('Calama', CALIBRACIONES)) : undefined)}
                              {linea('Arriendo de camiones', arr.reduce((t, x) => t + x.total, 0) || null)}
                              {arr.map((x) => linea(x.subfaena.replace('Arriendo · ', ''), x.total,
                                                    () => onPareto(paretoSub('Calama', x.subfaena)), true))}
                              {otros.map((x) => linea(x.subfaena, x.total, () => onPareto(paretoSub('Calama', x.subfaena))))}
                            </div>
                          )
                        })()}
                      </>
                    ) : <div className="mt-2 text-sm text-gray-500">Sin gasto en el período.</div>}
                  </div>
                )
              })}
            </div>

            {/* Gasto mensual por faena: clic en un segmento = Pareto de esa faena en ese mes */}
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
                           className="cursor-pointer"
                           radius={i === presentes.length - 1 ? [4, 4, 0, 0] : undefined}
                           onClick={(d: { payload?: { mesIso: string; mes: string } }) => {
                             if (d?.payload) onPareto({
                               titulo: `${f.id} · ${d.payload.mes}`,
                               filtros: { faena: f.id, mes: d.payload.mesIso },
                               dimension: f.id === 'Calama' ? 'subfaena' : 'equipo',
                             })
                           }} />
                    ))}
                  </BarChart>
                </ResponsiveContainer>
              </div>
            )}

            {/* Tabla: faenas con sus subfaenas */}
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
                    <th className="px-3 py-2" />
                  </tr>
                </thead>
                <tbody>
                  {faenas.map((f) => {
                    const subs = subDe(f.faena)
                    const desplegable = subs.length > 1
                    const Chevron = abierta === f.faena ? ChevronDown : ChevronRight
                    return (
                      <Fragment key={f.faena}>
                        <Fila f={f} nombre={
                          <span className="flex items-center gap-2 font-medium">
                            {desplegable
                              ? <Chevron className="h-4 w-4 text-gray-400" onClick={(ev) => {
                                  ev.stopPropagation(); setAbierta(abierta === f.faena ? null : f.faena)
                                }} />
                              : <span className="w-4" />}
                            <i className="inline-block h-3 w-3 rounded-sm" style={{ background: colorDe(f.faena) }} />
                            {f.faena}
                          </span>}
                              onPareto={() => onPareto(paretoFaena(f.faena))} />
                        {desplegable && abierta === f.faena && subs.map((s) => (
                          <Fila key={s.subfaena} f={s} sub
                                nombre={<span className="pl-10 text-gray-700">{s.subfaena}</span>}
                                onPareto={() => onPareto(paretoSub(f.faena, s.subfaena))} />
                        ))}
                      </Fragment>
                    )
                  })}
                </tbody>
              </table>
              <p className="mt-2 text-xs text-gray-400">
                «$/equipo-día» = gasto en equipos ÷ días que los equipos estuvieron en la faena (compara faenas de
                distinto tamaño). «$/hora» usa las horas medidas por horómetro. La faena del día sale del GPS
                (geocerca); si ese día no hay GPS, del estado diario; si no, la última conocida. En Calama, «Calibraciones» es el servicio (centros de costo de Calama; Softland no lo separa por
                Spence / Centinela / Lomas Bayas) y «Arriendo · …» son los camiones arrendados a clientes en esas
                faenas. «Contrato ESM» = Centinela.
              </p>
            </div>
          </>
        )}
      </CardContent>
    </Card>
  )
}

function Fila({ f, nombre, sub, onPareto }: {
  f: FaenaCosto; nombre: React.ReactNode; sub?: boolean; onPareto: () => void
}) {
  return (
    <tr className={`cursor-pointer border-t hover:bg-gray-50 ${sub ? 'bg-gray-50/50 text-[13px]' : ''}`} onClick={onPareto}>
      <td className="px-3 py-1.5">{nombre}</td>
      <td className={`px-3 py-1.5 text-right ${sub ? '' : 'font-medium'}`}>{fmtMM(f.total)}</td>
      <td className="px-3 py-1.5 text-right">{fmtMM(f.equipos_costo)}</td>
      <td className="px-3 py-1.5 text-right">{fmtMM(f.directo)}</td>
      <td className="px-3 py-1.5 text-right">{fmtMM(f.repuestos)}</td>
      <td className="px-3 py-1.5 text-right">{fmtMM(f.neumaticos)}</td>
      <td className="px-3 py-1.5 text-right">{fmtMM(f.lubricantes)}</td>
      <td className="px-3 py-1.5 text-right">{fmtNum(f.equipos)}</td>
      <td className="px-3 py-1.5 text-right">{fmtClp(f.costo_equipo_dia)}</td>
      <td className="px-3 py-1.5 text-right">{f.costo_hora != null ? fmtClp(f.costo_hora) : '—'}</td>
      <td className="px-3 py-1.5 text-right text-xs text-pillado-green-700">Pareto ›</td>
    </tr>
  )
}
