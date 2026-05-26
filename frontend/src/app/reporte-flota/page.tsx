'use client'

import { useEffect, useState } from 'react'
import { PieChart, Pie, Cell, Tooltip, ResponsiveContainer } from 'recharts'
import { supabase } from '@/lib/supabase'
import { generarReporteFlotaPDF, type ReporteFlotaData } from '@/components/flota/reporte-flota-pdf'

const COLOR: Record<string, string> = {
  A: '#16A34A', C: '#15803D', L: '#4F46E5', U: '#0891B2', D: '#2563EB',
  H: '#A855F7', R: '#06B6D4', M: '#F59E0B', T: '#FB923C', F: '#DC2626', V: '#9333EA',
}
const LABEL: Record<string, string> = {
  A: 'Arrendado', C: 'En contrato', D: 'Disponible', H: 'Habilitación', R: 'Recepción',
  M: 'Mantención', T: 'Taller', F: 'Fuera de servicio', V: 'Venta', U: 'Uso interno', L: 'Leasing',
}
const ORDEN = ['A', 'C', 'L', 'U', 'D', 'M', 'T', 'F', 'H', 'R', 'V']

export default function ReporteFlotaPublicoPage() {
  const [data, setData] = useState<ReporteFlotaData | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [descargando, setDescargando] = useState(false)

  useEffect(() => {
    supabase.rpc('fn_reporte_flota_publico').then(({ data, error }) => {
      if (error) setError(error.message)
      else setData(data as ReporteFlotaData)
    })
  }, [])

  const descargarPDF = async () => {
    if (!data) return
    setDescargando(true)
    try {
      const blob = await generarReporteFlotaPDF(data)
      const url = URL.createObjectURL(blob)
      const a = document.createElement('a')
      a.href = url
      a.download = `reporte-flota-${data.fecha ?? 'hoy'}.pdf`
      a.click()
      URL.revokeObjectURL(url)
    } finally {
      setDescargando(false)
    }
  }

  const est = data?.por_estado ?? {}
  const oper = Object.entries(data?.por_operacion ?? {})

  return (
    <div className="min-h-screen bg-gray-50 py-8">
      <div className="mx-auto max-w-3xl px-4">
        <div className="mb-6 flex items-start justify-between gap-3">
          <div>
            <h1 className="text-2xl font-bold text-[#0b2a4a]">Reporte de Flota — Pillado</h1>
            <p className="text-sm text-gray-500">
              Estado real de la flota{data?.fecha ? ` al ${data.fecha}` : ''} · SICOM-ICEO
            </p>
          </div>
          {data && (
            <button
              onClick={descargarPDF}
              disabled={descargando}
              className="rounded-lg bg-[#0b2a4a] px-4 py-2 text-sm font-semibold text-white hover:bg-[#0e3458] disabled:opacity-50"
            >
              {descargando ? 'Generando…' : 'Descargar PDF'}
            </button>
          )}
        </div>

        {error && <div className="rounded-lg bg-red-50 p-4 text-sm text-red-700">No se pudo cargar el reporte: {error}</div>}
        {!data && !error && <div className="py-20 text-center text-gray-400">Cargando…</div>}

        {data && (
          <div className="space-y-5">
            <div className="grid grid-cols-3 gap-3">
              <Kpi n={String(data.total)} l="Equipos de flota" />
              <Kpi n={`${data.disponibilidad ?? '—'}%`} l="Disponibilidad física (mes)" />
              <Kpi n={`${data.utilizacion ?? '—'}%`} l="Utilización bruta (mes)" />
            </div>

            <Card title="Distribución por estado">
              <div className="grid items-center gap-4 sm:grid-cols-2">
                <div className="h-56">
                  <ResponsiveContainer width="100%" height="100%">
                    <PieChart>
                      <Pie
                        data={ORDEN.filter((e) => est[e]).map((e) => ({ name: LABEL[e], value: est[e], color: COLOR[e] }))}
                        cx="50%" cy="50%" innerRadius={48} outerRadius={88} paddingAngle={2}
                        dataKey="value" label={({ value }) => `${value}`}
                      >
                        {ORDEN.filter((e) => est[e]).map((e) => (<Cell key={e} fill={COLOR[e]} />))}
                      </Pie>
                      <Tooltip formatter={(v: number, n: string) => [`${v} equipos`, n]} />
                    </PieChart>
                  </ResponsiveContainer>
                </div>
                <div className="space-y-1">
                  {ORDEN.filter((e) => est[e]).map((e) => (
                    <div key={e} className="flex items-center justify-between text-sm">
                      <span className="flex items-center gap-2">
                        <span className="inline-block h-3 w-3 rounded-sm" style={{ background: COLOR[e] }} />
                        {LABEL[e]} <span className="text-gray-400">({e})</span>
                      </span>
                      <b>{est[e]}</b>
                    </div>
                  ))}
                </div>
              </div>
            </Card>

            <Card title="Por operación">
              {oper.map(([k, v]) => (
                <div key={k} className="flex justify-between text-sm"><span>{k}</span><b>{v}</b></div>
              ))}
            </Card>

            <Card title="Por cliente">
              {(data.por_cliente ?? []).map((c) => (
                <div key={c.cliente} className="flex justify-between border-b border-gray-100 py-1 text-sm">
                  <span>{c.cliente}</span><b>{c.equipos}</b>
                </div>
              ))}
            </Card>

            {(data.equipos ?? []).length > 0 && (
              <Card title="Días arrendado por equipo">
                <p className="mb-2 text-xs text-gray-500">Días en arriendo/contrato en el año · último cliente arrendado</p>
                <div className="overflow-x-auto">
                  <table className="w-full text-xs">
                    <thead>
                      <tr className="border-b bg-gray-50 text-left uppercase text-gray-500">
                        <th className="px-2 py-2">Patente</th>
                        <th className="px-2 py-2">Equipo</th>
                        <th className="px-2 py-2">Estado</th>
                        <th className="px-2 py-2 text-right">Días arrendado</th>
                        <th className="px-2 py-2">Último cliente</th>
                      </tr>
                    </thead>
                    <tbody>
                      {(data.equipos ?? []).map((e, i) => (
                        <tr key={(e.patente ?? '') + i} className="border-b border-gray-100 hover:bg-gray-50">
                          <td className="px-2 py-1.5 font-mono font-semibold">{e.patente ?? '—'}</td>
                          <td className="px-2 py-1.5 text-gray-600">{e.equipamiento ?? '—'}</td>
                          <td className="px-2 py-1.5">
                            <span className="inline-flex items-center gap-1 rounded px-1.5 py-0.5 text-[11px] font-semibold text-white" style={{ background: e.estado ? COLOR[e.estado] ?? '#9CA3AF' : '#9CA3AF' }}>
                              {e.estado ? LABEL[e.estado] ?? e.estado : '—'}
                            </span>
                          </td>
                          <td className="px-2 py-1.5 text-right font-semibold">{e.dias_arrendado}</td>
                          <td className="px-2 py-1.5 text-gray-600">{e.ultimo_cliente ?? 'Sin contrato'}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </Card>
            )}

            <p className="pt-2 text-center text-xs text-gray-400">Pillado · SICOM-ICEO</p>
          </div>
        )}
      </div>
    </div>
  )
}

function Kpi({ n, l }: { n: string; l: string }) {
  return (
    <div className="rounded-xl border bg-white p-4 text-center">
      <div className="text-2xl font-bold text-[#0b2a4a]">{n}</div>
      <div className="mt-1 text-[11px] text-gray-500">{l}</div>
    </div>
  )
}
function Card({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="rounded-xl border bg-white p-4">
      <h2 className="mb-2 text-sm font-semibold text-[#0b2a4a]">{title}</h2>
      {children}
    </div>
  )
}
