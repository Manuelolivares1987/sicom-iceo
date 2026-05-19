'use client'

import { useEffect, useMemo, useState } from 'react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import {
  Calendar, Fuel, DollarSign, Truck, BarChart3, ExternalLink, AlertTriangle,
  RefreshCw,
} from 'lucide-react'
import {
  BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Cell,
} from 'recharts'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { supabase } from '@/lib/supabase'
import {
  cargarTransaccionesCliente, esUsuarioPortal,
  agruparPorDia, calcularKpis,
  type TransaccionCombustibleCliente, type ResumenPorDia,
} from '@/lib/services/portal-cliente'

type Rango = 'hoy' | 'semana' | 'mes' | 'mes_anterior'

function fmtCLP(n: number) {
  return n.toLocaleString('es-CL', { style: 'currency', currency: 'CLP', maximumFractionDigits: 0 })
}
function fmtLt(n: number) {
  return `${n.toLocaleString('es-CL', { maximumFractionDigits: 0 })} L`
}
function isoDate(d: Date) { return d.toISOString().slice(0, 10) }

function rangoFechas(r: Rango): { desde: string; hasta: string; label: string } {
  const hoy = new Date()
  if (r === 'hoy') {
    const f = isoDate(hoy)
    return { desde: f, hasta: f, label: 'Hoy' }
  }
  if (r === 'semana') {
    const inicio = new Date(hoy); inicio.setDate(hoy.getDate() - hoy.getDay())  // Domingo
    return { desde: isoDate(inicio), hasta: isoDate(hoy), label: 'Esta semana' }
  }
  if (r === 'mes') {
    const inicio = new Date(hoy.getFullYear(), hoy.getMonth(), 1)
    return { desde: isoDate(inicio), hasta: isoDate(hoy),
             label: hoy.toLocaleString('es-CL', { month: 'long', year: 'numeric' }) }
  }
  // mes_anterior
  const inicio = new Date(hoy.getFullYear(), hoy.getMonth() - 1, 1)
  const fin    = new Date(hoy.getFullYear(), hoy.getMonth(), 0)
  return { desde: isoDate(inicio), hasta: isoDate(fin),
           label: inicio.toLocaleString('es-CL', { month: 'long', year: 'numeric' }) }
}

export default function PortalDashboardPage() {
  const router = useRouter()
  const [rango, setRango]       = useState<Rango>('mes')
  const [rows, setRows]         = useState<TransaccionCombustibleCliente[]>([])
  const [loading, setLoading]   = useState(true)
  const [error, setError]       = useState<string | null>(null)

  // Guard
  useEffect(() => {
    (async () => {
      const { data } = await supabase.auth.getUser()
      if (!data.user) { router.push('/portal/login'); return }
      const esPortal = await esUsuarioPortal()
      if (!esPortal) { router.push('/portal/login'); return }
    })()
  }, [router])

  const { desde, hasta, label } = useMemo(() => rangoFechas(rango), [rango])

  const cargar = async () => {
    setError(null); setLoading(true)
    try {
      const data = await cargarTransaccionesCliente({ fechaDesde: desde, fechaHasta: hasta })
      setRows(data)
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setLoading(false)
    }
  }
  useEffect(() => { cargar() /* eslint-disable-line react-hooks/exhaustive-deps */ }, [rango])

  const kpis        = useMemo(() => calcularKpis(rows), [rows])
  const resumenDia  = useMemo(() => agruparPorDia(rows), [rows])

  // Top 5 días con más actividad (para tabla)
  const topDias = useMemo(
    () => [...resumenDia].sort((a, b) => b.litros - a.litros).slice(0, 10),
    [resumenDia]
  )

  return (
    <div className="space-y-4 p-4">
      {/* Tabs rangos */}
      <div className="flex flex-wrap gap-2">
        <TabBtn label="Hoy"          active={rango === 'hoy'}          onClick={() => setRango('hoy')} />
        <TabBtn label="Esta semana"  active={rango === 'semana'}       onClick={() => setRango('semana')} />
        <TabBtn label="Mes actual"   active={rango === 'mes'}          onClick={() => setRango('mes')} />
        <TabBtn label="Mes anterior" active={rango === 'mes_anterior'} onClick={() => setRango('mes_anterior')} />
        <div className="ml-auto flex items-center gap-2 text-xs text-muted-foreground">
          <RefreshCw className={`h-3 w-3 ${loading ? 'animate-spin' : ''}`} />
          {rows.length} despachos · {desde} → {hasta}
        </div>
      </div>

      {error && (
        <Card className="border-red-200 bg-red-50">
          <CardContent className="flex items-center gap-2 p-3 text-sm text-red-700">
            <AlertTriangle className="h-4 w-4" /> {error}
          </CardContent>
        </Card>
      )}

      {/* Titulo del periodo */}
      <Card className="bg-gradient-to-r from-blue-600 to-blue-700 text-white">
        <CardContent className="flex items-center justify-between p-4">
          <div>
            <div className="text-xs uppercase opacity-80">Periodo</div>
            <div className="text-2xl font-bold capitalize">{label}</div>
          </div>
          <Calendar className="h-8 w-8 opacity-50" />
        </CardContent>
      </Card>

      {/* KPIs */}
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        <KpiCard icon={<Truck className="h-5 w-5" />}   label="Despachos"      valor={kpis.transacciones.toString()} color="text-blue-700 bg-blue-50" />
        <KpiCard icon={<Fuel className="h-5 w-5" />}    label="Litros totales" valor={fmtLt(kpis.litros)}            color="text-amber-700 bg-amber-50" />
        <KpiCard icon={<DollarSign className="h-5 w-5" />} label="Costo total" valor={fmtCLP(kpis.costo)}            color="text-green-700 bg-green-50" />
        <KpiCard icon={<Truck className="h-5 w-5" />}   label="Patentes únicas" valor={kpis.patentes_unicas.toString()} color="text-purple-700 bg-purple-50" />
      </div>

      {/* Grafico de barras */}
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="flex items-center gap-2 text-base">
            <BarChart3 className="h-4 w-4" /> Litros por día
          </CardTitle>
        </CardHeader>
        <CardContent>
          {loading && rows.length === 0 ? (
            <div className="flex h-48 items-center justify-center"><Spinner /></div>
          ) : resumenDia.length === 0 ? (
            <div className="flex h-32 items-center justify-center text-sm text-muted-foreground">
              Sin despachos en este periodo.
            </div>
          ) : (
            <div style={{ width: '100%', height: 240 }}>
              <ResponsiveContainer>
                <BarChart data={resumenDia} margin={{ top: 10, right: 10, left: 0, bottom: 30 }}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#E5E7EB" />
                  <XAxis dataKey="fecha"
                         tick={{ fontSize: 10 }}
                         tickFormatter={(d: string) => d.slice(5)}  // MM-DD
                         angle={-45} textAnchor="end" height={50} />
                  <YAxis tick={{ fontSize: 11 }} />
                  <Tooltip
                    formatter={(value: number, name: string) => {
                      if (name === 'litros') return [fmtLt(value), 'Litros']
                      return [value, name]
                    }}
                    labelFormatter={(l) => `Fecha: ${l}`}
                  />
                  <Bar dataKey="litros" radius={[4, 4, 0, 0]}>
                    {resumenDia.map((_, idx) => (
                      <Cell key={idx} fill="#3B82F6" />
                    ))}
                  </Bar>
                </BarChart>
              </ResponsiveContainer>
            </div>
          )}
        </CardContent>
      </Card>

      {/* Resumen por dia (top 10) */}
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-base">Resumen por día</CardTitle>
        </CardHeader>
        <CardContent className="p-0">
          {resumenDia.length === 0 ? (
            <div className="p-6 text-center text-sm text-muted-foreground">
              Sin datos.
            </div>
          ) : (
            <table className="w-full text-sm">
              <thead className="bg-gray-50">
                <tr>
                  <th className="px-3 py-2 text-left">Fecha</th>
                  <th className="px-3 py-2 text-right">Despachos</th>
                  <th className="px-3 py-2 text-right">Litros</th>
                  <th className="px-3 py-2 text-right">Costo</th>
                  <th className="px-3 py-2 text-right">Patentes</th>
                </tr>
              </thead>
              <tbody>
                {topDias.map((d) => (
                  <tr key={d.fecha} className="border-t">
                    <td className="px-3 py-1.5 font-medium">
                      {new Date(d.fecha + 'T12:00:00').toLocaleDateString('es-CL', { weekday: 'short', day: '2-digit', month: 'short' })}
                    </td>
                    <td className="px-3 py-1.5 text-right">{d.transacciones}</td>
                    <td className="px-3 py-1.5 text-right font-mono">{fmtLt(d.litros)}</td>
                    <td className="px-3 py-1.5 text-right">{fmtCLP(d.costo)}</td>
                    <td className="px-3 py-1.5 text-right text-gray-500">{d.patentes_unicas}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </CardContent>
      </Card>

      <div className="flex justify-end">
        <Link href="/portal/transacciones">
          <Button variant="outline" size="sm" className="gap-1">
            Ver detalle completo de transacciones <ExternalLink className="h-4 w-4" />
          </Button>
        </Link>
      </div>
    </div>
  )
}

function TabBtn({ label, active, onClick }: { label: string; active: boolean; onClick: () => void }) {
  return (
    <button onClick={onClick}
            className={`rounded-md border px-3 py-1.5 text-sm font-medium transition-colors ${
              active
                ? 'border-blue-600 bg-blue-600 text-white'
                : 'border-gray-200 bg-white text-gray-600 hover:bg-gray-50'
            }`}>
      {label}
    </button>
  )
}

function KpiCard({ icon, label, valor, color }: { icon: React.ReactNode; label: string; valor: string; color: string }) {
  return (
    <div className={`rounded-lg border p-3 ${color}`}>
      <div className="flex items-center justify-between">
        <div className="text-xs font-medium opacity-80">{label}</div>
        <div className="opacity-50">{icon}</div>
      </div>
      <div className="mt-1 text-2xl font-bold">{valor}</div>
    </div>
  )
}
