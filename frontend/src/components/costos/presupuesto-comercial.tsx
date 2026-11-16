'use client'

import { useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import {
  Bar, BarChart, CartesianGrid, Legend, ResponsiveContainer, Tooltip, XAxis, YAxis,
} from 'recharts'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { MESES } from '@/components/costos/comunes'
import { fmtClp, fmtMM } from '@/lib/costos-operacion'
import { getComercialPpto, type ComercialPpto } from '@/lib/services/presupuesto'

// ============================================================================
// Base comercial de la mantención (MIG698). Comercial asume 13 UF por cada mes que
// un camión está arrendado (PPTO Comercial REV1); aquí se pone al lado de lo que
// SICOM proyecta, gasto por gasto y camión por camión. Es contraste: no cambia el total.
// ============================================================================

const C_COMERCIAL = '#2563EB'
const C_SICOM = '#059669'
type Camion = ComercialPpto['camiones'][number]

const fmtUF = (v: number) => `${v.toLocaleString('es-CL', { minimumFractionDigits: 1, maximumFractionDigits: 1 })} UF`
const fmtPct = (v: number) => `${v.toLocaleString('es-CL', { maximumFractionDigits: 0 })} %`
const sicomDe = (c: Camion) => c.preventivo + c.correctivo + c.neumaticos + c.mayores

export function BaseComercial() {
  const { data, isLoading, error } = useQuery({ queryKey: ['ppto-comercial'], queryFn: getComercialPpto })
  if (isLoading) return <p className="py-10 text-center text-sm text-gray-500">Cargando base comercial…</p>
  if (error || !data) return <p className="py-10 text-center text-sm text-red-600">No se pudo cargar la base comercial: {(error as Error)?.message}</p>
  return <Contenido d={data} />
}

function Contenido({ d }: { d: ComercialPpto }) {
  const mant = d.lineas.filter((l) => l.grupo === 'mantencion')
  const aparte = d.lineas.filter((l) => l.grupo === 'aparte')
  const excluido = d.lineas.filter((l) => l.grupo === 'excluido')
  const sicom = mant.reduce((a, l) => a + l.monto, 0)
  const comercial = d.meses_total * d.cuota
  const ufMes = (monto: number) => (d.meses_total ? monto / d.meses_total / d.uf : 0)
  const mesesContrato = d.camiones.filter((c) => c.fuente === 'contrato').reduce((a, c) => a + c.meses, 0)
  const brecha = sicom - comercial

  const tarjetas = [
    { t: 'Meses arrendados 2027', v: d.meses_total.toLocaleString('es-CL'),
      s: `${d.meses_total - mesesContrato} del PPTO Comercial + ${mesesContrato} de contratos Romeral y Franke` },
    { t: 'Base comercial mantención', v: fmtMM(comercial), s: `${fmtUF(d.uf_mes)} × ${fmtClp(d.uf)} = ${fmtClp(d.cuota)} por mes arrendado` },
    { t: 'SICOM mantención 2027', v: fmtMM(sicom), s: `${fmtUF(ufMes(sicom))} por mes arrendado` },
    { t: brecha > 0 ? 'Falta en la base comercial' : 'Holgura de la base comercial', v: fmtMM(Math.abs(brecha)),
      s: `${fmtUF(Math.abs(ufMes(brecha)))} por mes arrendado · ${comercial ? fmtPct((sicom / comercial - 1) * 100) : '—'} sobre Comercial` },
  ]

  return (
    <div className="space-y-4">
      <p className="max-w-4xl text-sm text-gray-600">
        El presupuesto de Operaciones se apoya en el de Comercial. Para mantención, Comercial asume {fmtUF(d.uf_mes)} por cada mes que
        un camión está arrendado, a UF {fmtClp(d.uf)}. Aquí queda al lado de lo que proyecta SICOM, como contraste: el total del
        presupuesto no cambia. Seguros quedan fuera; GPS y EPP se muestran aparte porque no van dentro de los {fmtUF(d.uf_mes)}.
      </p>

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        {tarjetas.map((c) => (
          <Card key={c.t}><CardContent className="p-4">
            <p className="text-xs font-medium uppercase tracking-wide text-gray-500">{c.t}</p>
            <p className={`mt-1 text-2xl font-bold ${c.t.startsWith('Falta') ? 'text-red-700' : 'text-gray-900'}`}>{c.v}</p>
            <p className="mt-0.5 text-xs text-gray-500">{c.s}</p>
          </CardContent></Card>
        ))}
      </div>

      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-base">De qué es cada gasto, 2027</CardTitle>
          <p className="text-xs text-gray-500">
            Cada gasto de SICOM llevado a UF por mes arrendado, para compararlo con los {fmtUF(d.uf_mes)} de Comercial
            ({d.meses_total.toLocaleString('es-CL')} meses arrendados en el año).
          </p>
        </CardHeader>
        <CardContent className="overflow-x-auto p-0">
          <table className="w-full min-w-[760px] text-sm">
            <thead className="bg-gray-50 text-xs text-gray-500">
              <tr>
                <th className="px-3 py-2 text-left">Gasto</th>
                <th className="px-3 py-2 text-left">Qué incluye y cómo se calcula</th>
                <th className="px-2 py-2 text-right">SICOM 2027</th>
                <th className="px-2 py-2 text-right">UF por mes arrendado</th>
                <th className="px-3 py-2 text-right">% de la mantención</th>
              </tr>
            </thead>
            <tbody>
              <tr className="border-t bg-gray-50 font-semibold text-gray-900"><td colSpan={5} className="px-3 py-1.5">Mantención: lo que deben cubrir los {fmtUF(d.uf_mes)}</td></tr>
              {mant.map((l) => (
                <tr key={l.codigo} className="border-t align-top">
                  <td className="px-3 py-1.5 pl-6 font-medium text-gray-800">{l.nombre}</td>
                  <td className="px-3 py-1.5 text-xs text-gray-600">{l.metodo}</td>
                  <td className="whitespace-nowrap px-2 py-1.5 text-right">{fmtMM(l.monto)}</td>
                  <td className="whitespace-nowrap px-2 py-1.5 text-right">{fmtUF(ufMes(l.monto))}</td>
                  <td className="whitespace-nowrap px-3 py-1.5 text-right text-gray-600">{sicom ? fmtPct((l.monto / sicom) * 100) : '—'}</td>
                </tr>
              ))}
              <tr className="border-t font-semibold text-gray-900">
                <td className="px-3 py-1.5" colSpan={2}>Total mantención SICOM</td>
                <td className="whitespace-nowrap px-2 py-1.5 text-right">{fmtMM(sicom)}</td>
                <td className="whitespace-nowrap px-2 py-1.5 text-right">{fmtUF(ufMes(sicom))}</td>
                <td className="px-3 py-1.5 text-right">100 %</td>
              </tr>
              <tr className="border-t font-semibold" style={{ color: C_COMERCIAL }}>
                <td className="px-3 py-1.5" colSpan={2}>Base comercial ({fmtUF(d.uf_mes)} × meses arrendados)</td>
                <td className="whitespace-nowrap px-2 py-1.5 text-right">{fmtMM(comercial)}</td>
                <td className="whitespace-nowrap px-2 py-1.5 text-right">{fmtUF(d.uf_mes)}</td>
                <td className="whitespace-nowrap px-3 py-1.5 text-right">{sicom ? fmtPct((comercial / sicom) * 100) : '—'}</td>
              </tr>
              <tr className={`border-t font-bold ${brecha > 0 ? 'text-red-700' : 'text-emerald-700'}`}>
                <td className="px-3 py-1.5" colSpan={2}>{brecha > 0 ? 'Falta para cubrir la mantención' : 'Holgura'}</td>
                <td className="whitespace-nowrap px-2 py-1.5 text-right">{fmtMM(Math.abs(brecha))}</td>
                <td className="whitespace-nowrap px-2 py-1.5 text-right">{fmtUF(Math.abs(ufMes(brecha)))}</td>
                <td />
              </tr>

              <tr className="border-t-2 border-gray-300 bg-gray-50 font-semibold text-gray-900"><td colSpan={5} className="px-3 py-1.5">Aparte, fuera de los {fmtUF(d.uf_mes)}</td></tr>
              {aparte.map((l) => (
                <tr key={l.codigo} className="border-t align-top">
                  <td className="px-3 py-1.5 pl-6 font-medium text-gray-800">{l.nombre}</td>
                  <td className="px-3 py-1.5 text-xs text-gray-600">{l.metodo}</td>
                  <td className="whitespace-nowrap px-2 py-1.5 text-right">{fmtMM(l.monto)}</td>
                  <td className="whitespace-nowrap px-2 py-1.5 text-right">{fmtUF(ufMes(l.monto))}</td>
                  <td />
                </tr>
              ))}
              <tr className="border-t font-semibold text-gray-900">
                <td className="px-3 py-1.5" colSpan={2}>Mantención + GPS + EPP</td>
                <td className="whitespace-nowrap px-2 py-1.5 text-right">{fmtMM(sicom + aparte.reduce((a, l) => a + l.monto, 0))}</td>
                <td className="whitespace-nowrap px-2 py-1.5 text-right">{fmtUF(ufMes(sicom + aparte.reduce((a, l) => a + l.monto, 0)))}</td>
                <td />
              </tr>
            </tbody>
          </table>
          {excluido.length > 0 && (
            <p className="border-t px-3 py-2 text-xs text-gray-500">
              Fuera de esta comparación: {excluido.map((l) => `${l.nombre} (${fmtMM(l.monto)} en 2027)`).join(', ')}. Sigue en el presupuesto de Operaciones como línea propia.
            </p>
          )}
        </CardContent>
      </Card>

      <PorMes d={d} />
      <PorCamion d={d} a5={mant.find((l) => l.codigo === 'A5')?.monto ?? 0} />

      <p className="text-xs text-gray-500">
        Fuente: PPTO COMERCIAL REV1.xlsx, hoja Base; un mes cuenta como arrendado si tiene ingreso. Los meses de la hoja se toman como
        el perfil de 2027. DJKL-18 y FSLZ-67 (Romeral) y HHWB-42 y HHWB-44 (Franke) no tienen ingreso en la hoja porque son contrato
        de servicio: cuentan 12 meses. El valor de la UF y las UF por mes se cambian en «Supuestos y programas».
      </p>
    </div>
  )
}

function PorMes({ d }: { d: ComercialPpto }) {
  const serie = d.meses.map((m) => ({ mes: MESES[m.mes - 1], Comercial: m.comercial, SICOM: m.sicom, camiones: m.camiones }))
  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-base">Mes a mes, 2027</CardTitle>
        <p className="text-xs text-gray-500">Comercial según los camiones arrendados de cada mes; SICOM con las pautas en su mes y el resto repartido parejo.</p>
      </CardHeader>
      <CardContent>
        <div style={{ width: '100%', height: 280 }}>
          <ResponsiveContainer>
            <BarChart data={serie} margin={{ top: 10, right: 10, left: 10, bottom: 0 }} barCategoryGap="22%" barGap={2}>
              <CartesianGrid strokeDasharray="3 3" stroke="#E5E7EB" vertical={false} />
              <XAxis dataKey="mes" tick={{ fontSize: 12 }} />
              <YAxis tick={{ fontSize: 11 }} tickFormatter={(v: number) => `${Math.round(v / 1e6)} M`} />
              <Tooltip
                cursor={{ fill: '#F3F4F6' }}
                formatter={(v: number, n: string) => [fmtMM(v), n]}
                labelFormatter={(l: string, p) => {
                  const c = (p?.[0]?.payload as { camiones?: number } | undefined)?.camiones
                  return c != null ? `${l} · ${c} camiones arrendados` : l
                }}
              />
              <Legend wrapperStyle={{ fontSize: 12 }} />
              <Bar dataKey="Comercial" fill={C_COMERCIAL} radius={[4, 4, 0, 0]} />
              <Bar dataKey="SICOM" fill={C_SICOM} radius={[4, 4, 0, 0]} />
            </BarChart>
          </ResponsiveContainer>
        </div>
      </CardContent>
    </Card>
  )
}

function PorCamion({ d, a5 }: { d: ComercialPpto; a5: number }) {
  const areas = useMemo(() => Array.from(new Set(d.camiones.map((c) => c.area))), [d.camiones])
  const [area, setArea] = useState('todas')
  const filas = area === 'todas' ? d.camiones : d.camiones.filter((c) => c.area === area)
  const tot = (f: (c: Camion) => number) => filas.reduce((a, c) => a + f(c), 0)
  const ufMes = (c: Camion) => (c.meses ? sicomDe(c) / c.meses / d.uf : null)
  const th = 'px-2 py-2 text-right'
  const td = 'whitespace-nowrap px-2 py-1.5 text-right'

  return (
    <Card>
      <CardHeader className="pb-2">
        <div className="flex flex-wrap items-end justify-between gap-2">
          <div>
            <CardTitle className="text-base">Camión por camión, 2027</CardTitle>
            <p className="text-xs text-gray-500">Diferencia = SICOM − Comercial. En rojo, los camiones cuya mantención no alcanza con la base comercial.</p>
          </div>
          <select value={area} onChange={(e) => setArea(e.target.value)} className="rounded-md border px-2 py-1.5 text-sm">
            <option value="todas">Todas las áreas</option>
            {areas.map((a) => <option key={a} value={a}>{a}</option>)}
          </select>
        </div>
      </CardHeader>
      <CardContent className="max-h-[560px] overflow-auto p-0">
        <table className="w-full min-w-[1000px] text-sm">
          <thead className="sticky top-0 bg-gray-50 text-xs text-gray-500">
            <tr>
              <th className="px-3 py-2 text-left">Camión</th>
              <th className="px-2 py-2 text-left">Área comercial</th>
              <th className={th}>Meses</th>
              <th className={th} style={{ color: C_COMERCIAL }}>Comercial</th>
              <th className={th}>Preventivo</th>
              <th className={th}>Correctivo</th>
              <th className={th}>Neumáticos</th>
              <th className={th}>Rep. mayores</th>
              <th className={th} style={{ color: C_SICOM }}>SICOM</th>
              <th className={th}>UF/mes SICOM</th>
              <th className={th}>Diferencia</th>
            </tr>
          </thead>
          <tbody>
            {filas.map((c) => {
              const s = sicomDe(c)
              const dif = s - c.comercial
              const uf = ufMes(c)
              return (
                <tr key={c.patente} className="border-t">
                  <td className="px-3 py-1.5">
                    <span className="font-medium text-gray-900">{c.patente}</span>
                    <span className="block text-xs text-gray-500">{[c.codigo, c.modelo ?? c.tipo, c.anio_fab].filter(Boolean).join(' · ')}</span>
                  </td>
                  <td className="px-2 py-1.5 text-gray-700">
                    {c.area}
                    {c.fuente === 'contrato' && <span className="block text-xs text-gray-500">contrato de servicio</span>}
                  </td>
                  <td className={td} title={c.lista.length ? `Meses: ${c.lista.map((m) => MESES[m - 1]).join(', ')}` : undefined}>{c.meses}</td>
                  <td className={td}>{fmtMM(c.comercial)}</td>
                  <td className={`${td} text-gray-600`}>{fmtMM(c.preventivo)}</td>
                  <td className={`${td} text-gray-600`}>{fmtMM(c.correctivo)}</td>
                  <td className={`${td} text-gray-600`}>{fmtMM(c.neumaticos)}</td>
                  <td className={`${td} text-gray-600`}>{fmtMM(c.mayores)}</td>
                  <td className={`${td} font-medium`}>{fmtMM(s)}</td>
                  <td className={`${td} ${uf != null && uf > d.uf_mes ? 'text-red-700' : 'text-gray-600'}`}>{uf != null ? fmtUF(uf) : '—'}</td>
                  <td className={`${td} font-medium ${dif > 0 ? 'text-red-700' : 'text-emerald-700'}`}>{dif > 0 ? '+' : ''}{fmtMM(dif)}</td>
                </tr>
              )
            })}
            <tr className="border-t-2 border-gray-300 font-bold text-gray-900">
              <td className="px-3 py-2" colSpan={2}>Total {area === 'todas' ? 'camiones' : area}</td>
              <td className={td}>{tot((c) => c.meses)}</td>
              <td className={td}>{fmtMM(tot((c) => c.comercial))}</td>
              <td className={td}>{fmtMM(tot((c) => c.preventivo))}</td>
              <td className={td}>{fmtMM(tot((c) => c.correctivo))}</td>
              <td className={td}>{fmtMM(tot((c) => c.neumaticos))}</td>
              <td className={td}>{fmtMM(tot((c) => c.mayores))}</td>
              <td className={td}>{fmtMM(tot(sicomDe))}</td>
              <td className={td}>{tot((c) => c.meses) ? fmtUF(tot(sicomDe) / tot((c) => c.meses) / d.uf) : '—'}</td>
              <td className={td}>{fmtMM(tot(sicomDe) - tot((c) => c.comercial))}</td>
            </tr>
            {area === 'todas' && (
              <tr className="border-t text-gray-600">
                <td className="px-3 py-1.5" colSpan={8}>Repuestos y talleres sin patente (no se puede asignar a un camión)</td>
                <td className={td}>{fmtMM(a5)}</td>
                <td className={td}>{d.meses_total ? fmtUF(a5 / d.meses_total / d.uf) : '—'}</td>
                <td className={`${td} text-red-700`}>+{fmtMM(a5)}</td>
              </tr>
            )}
          </tbody>
        </table>
      </CardContent>
    </Card>
  )
}

/** Franja para el Resumen: la base comercial al lado de la mantención de SICOM. */
export function FranjaComercial() {
  const { data: d } = useQuery({ queryKey: ['ppto-comercial'], queryFn: getComercialPpto })
  if (!d) return null
  const sicom = d.lineas.filter((l) => l.grupo === 'mantencion').reduce((a, l) => a + l.monto, 0)
  const comercial = d.meses_total * d.cuota
  const extra = d.lineas.filter((l) => l.grupo === 'aparte')
  const brecha = sicom - comercial
  return (
    <div className="flex flex-wrap items-center gap-x-6 gap-y-1 rounded-lg border border-blue-200 bg-blue-50 px-4 py-3 text-sm">
      <span className="font-semibold" style={{ color: C_COMERCIAL }}>Contraste con Comercial 2027</span>
      <span>Base comercial mantención <b>{fmtMM(comercial)}</b> <span className="text-gray-500">({fmtUF(d.uf_mes)} × {d.meses_total} meses arrendados)</span></span>
      <span>SICOM mantención <b>{fmtMM(sicom)}</b></span>
      <span className={brecha > 0 ? 'font-semibold text-red-700' : 'font-semibold text-emerald-700'}>
        {brecha > 0 ? 'Falta' : 'Holgura'} {fmtMM(Math.abs(brecha))}
      </span>
      <span className="text-gray-600">Aparte: {extra.map((l) => `${l.nombre} ${fmtMM(l.monto)}`).join(' · ')}</span>
      <span className="text-xs text-gray-500">Detalle en «Base comercial».</span>
    </div>
  )
}
