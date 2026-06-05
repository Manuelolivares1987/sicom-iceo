'use client'

import { useEffect, useMemo, useState } from 'react'
import Link from 'next/link'
import {
  ArrowLeft, Calendar, Fuel, DollarSign, Truck, BarChart3, Building2,
  RefreshCw, AlertTriangle, Download, Trophy,
} from 'lucide-react'
import {
  BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Legend,
} from 'recharts'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { useRequireAuth } from '@/hooks/use-require-auth'
import {
  cargarConsolidadoComercial, agruparPorEmpresa, gruparApiladoPorDia, rankearPatentes,
  cargarStockEstanques, type EstanqueStock,
} from '@/lib/services/combustible-comercial'
import type { TransaccionCombustibleCliente } from '@/lib/services/portal-cliente'
import { ProyeccionStockCard } from '@/components/combustible/proyeccion-stock-card'

type Rango = 'hoy' | 'semana' | 'mes' | 'mes_anterior' | 'trimestre' | 'anio'

function fmtCLP(n: number) {
  return n.toLocaleString('es-CL', { style: 'currency', currency: 'CLP', maximumFractionDigits: 0 })
}
function fmtLt(n: number) {
  return `${n.toLocaleString('es-CL', { maximumFractionDigits: 0 })} L`
}
function isoDate(d: Date) { return d.toISOString().slice(0, 10) }

function rangoFechas(r: Rango): { desde: string; hasta: string; label: string } {
  const hoy = new Date()
  if (r === 'hoy')          { const f = isoDate(hoy); return { desde: f, hasta: f, label: 'Hoy' } }
  if (r === 'semana')       { const i = new Date(hoy); i.setDate(hoy.getDate() - hoy.getDay()); return { desde: isoDate(i), hasta: isoDate(hoy), label: 'Esta semana' } }
  if (r === 'mes')          { const i = new Date(hoy.getFullYear(), hoy.getMonth(), 1); return { desde: isoDate(i), hasta: isoDate(hoy), label: hoy.toLocaleString('es-CL', { month: 'long', year: 'numeric' }) } }
  if (r === 'mes_anterior') { const i = new Date(hoy.getFullYear(), hoy.getMonth() - 1, 1); const f = new Date(hoy.getFullYear(), hoy.getMonth(), 0); return { desde: isoDate(i), hasta: isoDate(f), label: i.toLocaleString('es-CL', { month: 'long', year: 'numeric' }) } }
  if (r === 'trimestre')    { const q = Math.floor(hoy.getMonth() / 3); const i = new Date(hoy.getFullYear(), q * 3, 1); return { desde: isoDate(i), hasta: isoDate(hoy), label: `Q${q + 1} ${hoy.getFullYear()}` } }
  // año
  const i = new Date(hoy.getFullYear(), 0, 1)
  return { desde: isoDate(i), hasta: isoDate(hoy), label: `Año ${hoy.getFullYear()}` }
}

const COLORS_EMPRESAS = ['#2D8B3D', '#E87722', '#3B82F6', '#8B5CF6', '#EC4899', '#0EA5E9', '#F59E0B', '#10B981']

export default function ComercialCombustibleConsolidadoPage() {
  useRequireAuth()
  const [rango, setRango]     = useState<Rango>('mes')
  const [rows, setRows]       = useState<TransaccionCombustibleCliente[]>([])
  const [estanques, setEstanques] = useState<EstanqueStock[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError]     = useState<string | null>(null)

  const { desde, hasta, label } = useMemo(() => rangoFechas(rango), [rango])

  const cargar = async () => {
    setError(null); setLoading(true)
    try {
      const [trx, est] = await Promise.all([
        cargarConsolidadoComercial({ fechaDesde: desde, fechaHasta: hasta }),
        cargarStockEstanques(),
      ])
      setRows(trx); setEstanques(est)
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setLoading(false)
    }
  }
  useEffect(() => { cargar() /* eslint-disable-line react-hooks/exhaustive-deps */ }, [rango])

  // Solo despachos con empresa cliente identificada (excluye consumos internos
  // o despachos sin clasificar). Todas las agregaciones usan este subset.
  const rowsConEmpresa = useMemo(
    () => rows.filter((r) => (r.externo_empresa ?? r.activo_cliente) != null),
    [rows],
  )
  const excluidas = rows.length - rowsConEmpresa.length

  const porEmpresa  = useMemo(() => agruparPorEmpresa(rowsConEmpresa), [rowsConEmpresa])
  const empresasTop = useMemo(() => porEmpresa.slice(0, 8).map((e) => e.empresa), [porEmpresa])
  const apilado     = useMemo(() => gruparApiladoPorDia(rowsConEmpresa, empresasTop), [rowsConEmpresa, empresasTop])
  const topPatentes = useMemo(() => rankearPatentes(rowsConEmpresa).slice(0, 10), [rowsConEmpresa])

  const kpis = useMemo(() => {
    const litros = rowsConEmpresa.reduce((s, r) => s + Number(r.litros), 0)
    const costo  = rowsConEmpresa.reduce((s, r) => s + Number(r.costo_total_clp ?? 0), 0)
    const patentes = new Set<string>()
    for (const r of rowsConEmpresa) {
      const p = r.activo_patente ?? r.externo_patente
      if (p) patentes.add(p)
    }
    return {
      despachos: rowsConEmpresa.length, litros, costo,
      patentes_unicas: patentes.size,
      empresas: porEmpresa.length,
    }
  }, [rowsConEmpresa, porEmpresa])

  const exportarCSV = () => {
    const headers = ['Empresa', 'Origen', 'Despachos', 'Litros', 'Costo CLP', 'Patentes', 'Primera fecha', 'Ultima fecha']
    const rows = porEmpresa.map((e) => [
      e.empresa, e.origen, e.transacciones, e.litros.toFixed(1), e.costo,
      e.patentes_unicas, e.primera_fecha ?? '', e.ultima_fecha ?? '',
    ])
    const csv = [headers, ...rows].map((r) => r.map((v) => `"${String(v).replace(/"/g, '""')}"`).join(',')).join('\n')
    const blob = new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8' })
    const a = document.createElement('a')
    a.href = URL.createObjectURL(blob)
    a.download = `consolidado_combustible_${desde}_${hasta}.csv`
    a.click()
  }

  return (
    <div className="space-y-4 p-4 sm:p-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-3">
          <Link href="/dashboard/comercial">
            <Button variant="ghost" size="sm" className="gap-1">
              <ArrowLeft className="h-4 w-4" /> Comercial
            </Button>
          </Link>
          <div>
            <h1 className="flex items-center gap-2 text-2xl font-bold">
              <BarChart3 className="h-6 w-6 text-pillado-green-600" />
              Consolidado Combustible
            </h1>
            <p className="text-sm text-muted-foreground">
              Vista comercial de todas las ventas/despachos a clientes y empresas externas autorizadas.
            </p>
          </div>
        </div>
        <div className="flex gap-2">
          <Button onClick={cargar} variant="outline" size="sm" className="gap-1" disabled={loading}>
            <RefreshCw className={`h-4 w-4 ${loading ? 'animate-spin' : ''}`} />
          </Button>
          <Button onClick={exportarCSV} variant="outline" size="sm" className="gap-1" disabled={rows.length === 0}>
            <Download className="h-4 w-4" /> Exportar CSV
          </Button>
        </div>
      </div>

      {/* Tabs rango */}
      <div className="flex flex-wrap gap-2">
        <TabBtn label="Hoy"            active={rango === 'hoy'}          onClick={() => setRango('hoy')} />
        <TabBtn label="Esta semana"    active={rango === 'semana'}       onClick={() => setRango('semana')} />
        <TabBtn label="Mes actual"     active={rango === 'mes'}          onClick={() => setRango('mes')} />
        <TabBtn label="Mes anterior"   active={rango === 'mes_anterior'} onClick={() => setRango('mes_anterior')} />
        <TabBtn label="Trimestre"      active={rango === 'trimestre'}    onClick={() => setRango('trimestre')} />
        <TabBtn label="Año"            active={rango === 'anio'}         onClick={() => setRango('anio')} />
        <div className="ml-auto flex items-center gap-2 text-xs text-muted-foreground">
          {rowsConEmpresa.length} despachos a empresa · {desde} → {hasta}
          {excluidas > 0 && (
            <span className="rounded-full bg-gray-200 px-2 py-0.5 text-[10px] font-semibold text-gray-600">
              {excluidas} sin empresa (ocultos)
            </span>
          )}
        </div>
      </div>

      {/* Proyeccion de stock con demanda real — todas las ventas a clientes */}
      <ProyeccionStockCard compacto />

      {/* STOCK ACTUAL DE ESTANQUES (siempre visible — info crítica para comercial) */}
      <Card className="border-pillado-orange-300 bg-pillado-orange-50/40">
        <CardHeader className="pb-2">
          <CardTitle className="flex items-center gap-2 text-base text-pillado-orange-800">
            <Fuel className="h-4 w-4" /> Stock actual de estanques (en vivo)
          </CardTitle>
        </CardHeader>
        <CardContent>
          {estanques.length === 0 ? (
            <div className="text-sm text-muted-foreground">Sin estanques registrados.</div>
          ) : (
            <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
              {estanques.map((e) => {
                const colorBar = e.estado === 'critico' ? 'bg-red-500'
                              : e.estado === 'bajo'     ? 'bg-amber-500'
                              : e.estado === 'lleno'    ? 'bg-pillado-orange-500'
                              : 'bg-pillado-green-500'
                const colorTxt = e.estado === 'critico' ? 'text-red-700'
                              : e.estado === 'bajo'     ? 'text-amber-700'
                              : 'text-pillado-green-700'
                return (
                  <div key={e.id} className="rounded-lg border bg-white p-3 shadow-sm">
                    <div className="flex items-start justify-between gap-2">
                      <div className="min-w-0 flex-1">
                        <div className="text-xs font-mono text-gray-500">{e.codigo}</div>
                        <div className="text-sm font-semibold truncate">{e.nombre}</div>
                        {e.faena_nombre && <div className="text-[10px] text-gray-500 truncate">{e.faena_nombre}</div>}
                      </div>
                      {(e.estado === 'critico' || e.estado === 'bajo') && (
                        <span className="rounded bg-red-100 px-1.5 py-0.5 text-[10px] font-bold text-red-700">
                          {e.estado === 'critico' ? '⚠ CRÍTICO' : '⚠ BAJO'}
                        </span>
                      )}
                    </div>
                    <div className="mt-2 flex items-baseline justify-between">
                      <span className={`text-xl font-bold ${colorTxt}`}>
                        {fmtLt(Number(e.stock_teorico_lt))}
                      </span>
                      <span className="text-[10px] text-gray-500">
                        / {fmtLt(Number(e.capacidad_lt))}
                      </span>
                    </div>
                    <div className="mt-1 h-2 w-full overflow-hidden rounded-full bg-gray-100">
                      <div className={`h-full ${colorBar} transition-all`}
                           style={{ width: `${e.porcentaje}%` }} />
                    </div>
                    <div className="mt-1 flex justify-between text-[10px] text-gray-500">
                      <span>{e.porcentaje.toFixed(0)}% lleno</span>
                      {e.stock_minimo_alerta_lt != null && (
                        <span>mín: {fmtLt(Number(e.stock_minimo_alerta_lt))}</span>
                      )}
                    </div>
                  </div>
                )
              })}
            </div>
          )}
        </CardContent>
      </Card>

      {/* Periodo */}
      <Card className="overflow-hidden border-0 bg-gradient-to-r from-pillado-green-700 via-pillado-green-600 to-pillado-green-500 text-white shadow-lg">
        <CardContent className="flex items-center justify-between p-5">
          <div>
            <div className="text-xs uppercase tracking-widest opacity-80">Periodo de análisis</div>
            <div className="mt-1 text-2xl font-bold capitalize sm:text-3xl">{label}</div>
            <div className="mt-0.5 text-xs text-pillado-orange-200">{desde} → {hasta}</div>
          </div>
          <Calendar className="h-10 w-10 text-pillado-orange-300 opacity-60" />
        </CardContent>
      </Card>

      {/* KPIs */}
      <div className="grid grid-cols-2 gap-3 md:grid-cols-5">
        <Kpi icon={<Truck />}      label="Despachos"  valor={kpis.despachos.toString()}        accent="text-pillado-green-700" />
        <Kpi icon={<Fuel />}       label="Litros"     valor={fmtLt(kpis.litros)}                accent="text-pillado-orange-700" />
        <Kpi icon={<DollarSign />} label="Costo"      valor={fmtCLP(kpis.costo)}                accent="text-pillado-green-700" highlight />
        <Kpi icon={<Building2 />}  label="Empresas"   valor={kpis.empresas.toString()}          accent="text-blue-700" />
        <Kpi icon={<Truck />}      label="Patentes"   valor={kpis.patentes_unicas.toString()}   accent="text-purple-700" />
      </div>

      {error && (
        <Card className="border-red-200 bg-red-50">
          <CardContent className="flex items-center gap-2 p-3 text-sm text-red-700">
            <AlertTriangle className="h-4 w-4" /> {error}
          </CardContent>
        </Card>
      )}

      {/* Comparativa por empresa */}
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="flex items-center gap-2 text-base">
            <Building2 className="h-4 w-4" /> Comparativa por empresa / cliente
          </CardTitle>
        </CardHeader>
        <CardContent className="p-0">
          {loading && rows.length === 0 ? (
            <div className="flex h-32 items-center justify-center"><Spinner /></div>
          ) : porEmpresa.length === 0 ? (
            <div className="p-6 text-center text-sm text-muted-foreground">Sin datos en el periodo.</div>
          ) : (
            <table className="w-full text-sm">
              <thead className="bg-pillado-green-50">
                <tr>
                  <th className="px-3 py-2 text-left">Empresa / Cliente</th>
                  <th className="px-3 py-2 text-center">Origen</th>
                  <th className="px-3 py-2 text-right">Despachos</th>
                  <th className="px-3 py-2 text-right">Litros</th>
                  <th className="px-3 py-2 text-right">% Share</th>
                  <th className="px-3 py-2 text-right">Costo</th>
                  <th className="px-3 py-2 text-right">Patentes</th>
                  <th className="px-3 py-2 text-center">Periodo activo</th>
                </tr>
              </thead>
              <tbody>
                {porEmpresa.map((e, idx) => {
                  const share = kpis.litros > 0 ? (e.litros / kpis.litros) * 100 : 0
                  const colorBar = COLORS_EMPRESAS[idx % COLORS_EMPRESAS.length]
                  return (
                    <tr key={e.empresa} className="border-t hover:bg-gray-50">
                      <td className="px-3 py-2">
                        <div className="flex items-center gap-2">
                          <span className="h-3 w-3 rounded-full" style={{ background: colorBar }} />
                          <b>{e.empresa}</b>
                        </div>
                      </td>
                      <td className="px-3 py-2 text-center">
                        <OrigenBadge origen={e.origen} />
                      </td>
                      <td className="px-3 py-2 text-right">{e.transacciones}</td>
                      <td className="px-3 py-2 text-right font-mono font-semibold">{fmtLt(e.litros)}</td>
                      <td className="px-3 py-2 text-right">
                        <div className="flex items-center justify-end gap-1">
                          <div className="h-2 w-16 rounded bg-gray-100 overflow-hidden">
                            <div style={{ width: `${share}%`, background: colorBar }} className="h-full" />
                          </div>
                          <span className="font-mono w-12 text-right">{share.toFixed(1)}%</span>
                        </div>
                      </td>
                      <td className="px-3 py-2 text-right">{fmtCLP(e.costo)}</td>
                      <td className="px-3 py-2 text-right text-gray-500">{e.patentes_unicas}</td>
                      <td className="px-3 py-2 text-center text-[11px] text-gray-500">
                        {e.primera_fecha} → {e.ultima_fecha}
                      </td>
                    </tr>
                  )
                })}
              </tbody>
              <tfoot className="bg-pillado-green-50 font-semibold">
                <tr>
                  <td className="px-3 py-2">TOTAL</td>
                  <td />
                  <td className="px-3 py-2 text-right">{kpis.despachos}</td>
                  <td className="px-3 py-2 text-right font-mono">{fmtLt(kpis.litros)}</td>
                  <td />
                  <td className="px-3 py-2 text-right">{fmtCLP(kpis.costo)}</td>
                  <td className="px-3 py-2 text-right">{kpis.patentes_unicas}</td>
                  <td />
                </tr>
              </tfoot>
            </table>
          )}
        </CardContent>
      </Card>

      {/* Grafico apilado por dia */}
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="flex items-center gap-2 text-base">
            <BarChart3 className="h-4 w-4" /> Litros por día — apilado por empresa
          </CardTitle>
        </CardHeader>
        <CardContent>
          {apilado.length === 0 ? (
            <div className="flex h-32 items-center justify-center text-sm text-muted-foreground">Sin datos.</div>
          ) : (
            <div style={{ width: '100%', height: 320 }}>
              <ResponsiveContainer>
                <BarChart data={apilado} margin={{ top: 10, right: 20, left: 0, bottom: 40 }}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#E5E7EB" />
                  <XAxis dataKey="fecha" tick={{ fontSize: 10 }}
                         tickFormatter={(d: string) => d.slice(5)} angle={-45} textAnchor="end" height={50} />
                  <YAxis tick={{ fontSize: 11 }} />
                  <Tooltip
                    formatter={(value: number) => [fmtLt(value), '']}
                    labelFormatter={(l) => `Fecha: ${l}`}
                  />
                  <Legend wrapperStyle={{ fontSize: 11 }} />
                  {empresasTop.map((emp, idx) => (
                    <Bar key={emp} dataKey={emp} stackId="a"
                         fill={COLORS_EMPRESAS[idx % COLORS_EMPRESAS.length]} />
                  ))}
                </BarChart>
              </ResponsiveContainer>
            </div>
          )}
        </CardContent>
      </Card>

      {/* Top patentes */}
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="flex items-center gap-2 text-base">
            <Trophy className="h-4 w-4 text-pillado-orange-500" /> Top 10 patentes con más consumo
          </CardTitle>
        </CardHeader>
        <CardContent className="p-0">
          {topPatentes.length === 0 ? (
            <div className="p-6 text-center text-sm text-muted-foreground">Sin datos.</div>
          ) : (
            <table className="w-full text-sm">
              <thead className="bg-gray-50">
                <tr>
                  <th className="px-3 py-2 text-left">#</th>
                  <th className="px-3 py-2 text-left">Patente</th>
                  <th className="px-3 py-2 text-left">Empresa</th>
                  <th className="px-3 py-2 text-right">Despachos</th>
                  <th className="px-3 py-2 text-right">Litros</th>
                  <th className="px-3 py-2 text-right">Costo</th>
                </tr>
              </thead>
              <tbody>
                {topPatentes.map((p, idx) => (
                  <tr key={p.patente} className="border-t">
                    <td className="px-3 py-2 text-gray-500">{idx + 1}</td>
                    <td className="px-3 py-2 font-mono font-semibold">{p.patente}</td>
                    <td className="px-3 py-2 text-gray-600">{p.empresa}</td>
                    <td className="px-3 py-2 text-right">{p.despachos}</td>
                    <td className="px-3 py-2 text-right font-mono">{fmtLt(p.litros)}</td>
                    <td className="px-3 py-2 text-right">{fmtCLP(p.costo)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </CardContent>
      </Card>
    </div>
  )
}

function TabBtn({ label, active, onClick }: { label: string; active: boolean; onClick: () => void }) {
  return (
    <button onClick={onClick}
            className={`rounded-md border px-3 py-1.5 text-sm font-medium transition-colors ${
              active
                ? 'border-pillado-green-500 bg-pillado-green-500 text-white shadow-md'
                : 'border-gray-200 bg-white text-gray-700 hover:bg-pillado-green-50 hover:text-pillado-green-700'
            }`}>
      {label}
    </button>
  )
}

function Kpi({ icon, label, valor, accent, highlight }: {
  icon: React.ReactNode; label: string; valor: string; accent: string; highlight?: boolean
}) {
  return (
    <div className={`rounded-xl border-2 p-4 shadow-sm transition-shadow hover:shadow-md ${
      highlight
        ? 'border-pillado-green-600 bg-pillado-green-500 text-white'
        : 'border-gray-200 bg-white'
    }`}>
      <div className="flex items-center justify-between">
        <div className="text-xs font-semibold uppercase tracking-wider opacity-80">{label}</div>
        <div className={highlight ? 'text-pillado-orange-300' : `${accent} opacity-60`}>{icon}</div>
      </div>
      <div className={`mt-2 text-2xl font-bold sm:text-3xl ${highlight ? '' : accent}`}>{valor}</div>
    </div>
  )
}

function OrigenBadge({ origen }: { origen: 'externa' | 'contrato' | 'sin_clasificar' }) {
  const map = {
    externa:         { l: 'Externa', c: 'bg-purple-100 text-purple-700' },
    contrato:        { l: 'Contrato', c: 'bg-pillado-green-100 text-pillado-green-700' },
    sin_clasificar:  { l: 'Sin clasif.', c: 'bg-gray-100 text-gray-500' },
  }
  const v = map[origen]
  return (
    <span className={`rounded px-1.5 py-0.5 text-[10px] font-bold ${v.c}`}>{v.l}</span>
  )
}
