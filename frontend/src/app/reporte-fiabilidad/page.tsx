'use client'

import { useEffect, useMemo, useState } from 'react'
import { PieChart, Pie, Cell, Tooltip, ResponsiveContainer } from 'recharts'
import { supabase } from '@/lib/supabase'

// ── Estados ────────────────────────────────────────────────
const COLOR: Record<string, string> = {
  A: '#16A34A', C: '#15803D', L: '#4F46E5', U: '#0891B2', D: '#2563EB',
  H: '#A855F7', R: '#06B6D4', M: '#F59E0B', T: '#FB923C', F: '#DC2626', V: '#9333EA',
}
const LABEL: Record<string, string> = {
  A: 'Arrendado', C: 'En contrato', D: 'Disponible', H: 'Habilitación', R: 'Recepción',
  M: 'Mantención', T: 'Taller', F: 'Fuera de servicio', V: 'Venta', U: 'Uso interno', L: 'Leasing',
}
const ORDEN = ['A', 'C', 'L', 'U', 'D', 'M', 'T', 'F', 'H', 'R', 'V']

type Categoria = {
  categoria: string | null
  total_equipos: number; dias_equipo: number; dias_up: number; dias_down: number
  eventos_falla_total: number; disponibilidad_fisica: number; utilizacion_bruta: number
  mtbf_agregado: number; mttr_agregado: number
}
type Equipo = {
  activo_id: string; patente: string; equipamiento: string | null
  categoria_uso: string | null; cliente: string | null
  dias_observados: number; dias_up: number; dias_down: number; eventos_falla: number
  mtbf_dias: number; mttr_dias: number
  disponibilidad_inherente: number; disponibilidad_fisica: number
}
type Celda = { activo_id: string; fecha: string; estado: string }
type Estanque = {
  estanque_codigo: string; estanque_nombre: string; capacidad_lt: number
  stock_actual: number; stock_minimo: number; dias_cobertura: number | null
  fecha_agotamiento_estimada: string | null; severidad: string
}
type Reporte = {
  desde: string; hasta: string; categorias: Categoria[]; equipos: Equipo[]
  matriz: Celda[]; combustible: Estanque[]
}

const SEV: Record<string, [string, string]> = {
  agotado: ['Agotado', '#7f1d1d'], critico: ['Crítico', '#dc2626'],
  urgente: ['Urgente', '#ea580c'], atencion: ['Atención', '#d97706'], ok: ['OK', '#16a34a'],
}
const lt = (v: number | null | undefined) => Math.round(Number(v || 0)).toLocaleString('es-CL')

const fmtPct = (v: number | null | undefined, d = 1) => v == null ? '—' : `${(Number(v) * 100).toFixed(d)}%`
const fmtNum = (v: number | null | undefined, d = 1) => v == null ? '—' : Number(v).toFixed(d)
const firstOfMonth = () => { const d = new Date(); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-01` }
const todayStr = () => new Date().toISOString().slice(0, 10)

function colorDisp(v: number): string {
  if (v >= 0.92) return 'text-green-600'; if (v >= 0.85) return 'text-blue-600'
  if (v >= 0.75) return 'text-amber-600'; return 'text-red-600'
}

export default function ReporteFiabilidadPublicoPage() {
  const [desde, setDesde] = useState(firstOfMonth())
  const [hasta, setHasta] = useState(todayStr())
  const [data, setData] = useState<Reporte | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [cargando, setCargando] = useState(true)
  const [equipoSel, setEquipoSel] = useState<string | null>(null)
  const [filtroEstado, setFiltroEstado] = useState<string | null>(null)

  // Permitir fijar el período por URL (?desde=...&hasta=...) desde el correo
  useEffect(() => {
    const q = new URLSearchParams(window.location.search)
    const d = q.get('desde'); const h = q.get('hasta')
    if (d) setDesde(d); if (h) setHasta(h)
  }, [])

  useEffect(() => {
    let cancel = false
    setCargando(true); setError(null)
    ;(async () => {
      const { data, error } = await supabase.rpc('fn_reporte_fiabilidad_publico', { p_ini: desde, p_fin: hasta })
      if (cancel) return
      if (error) setError(error.message)
      else setData(data as Reporte)
      setCargando(false)
    })()
    return () => { cancel = true }
  }, [desde, hasta])

  const equipos = data?.equipos ?? []
  const matriz = data?.matriz ?? []
  const combustible = data?.combustible ?? []
  const combTot = combustible.reduce((a, e) => ({
    cap: a.cap + Number(e.capacidad_lt || 0), st: a.st + Number(e.stock_actual || 0),
    min: a.min + Number(e.stock_minimo || 0),
  }), { cap: 0, st: 0, min: 0 })

  const diasUnicos = useMemo(
    () => Array.from(new Set(matriz.map((c) => c.fecha.slice(0, 10)))).sort(),
    [matriz],
  )
  const estadoActual = useMemo(() => {
    const m = new Map<string, string>()
    if (diasUnicos.length === 0) return m
    const ultimo = diasUnicos[diasUnicos.length - 1]
    for (const c of matriz) if (c.fecha.slice(0, 10) === ultimo) m.set(c.activo_id, c.estado)
    return m
  }, [matriz, diasUnicos])

  const distEstado = useMemo(() => {
    const counts: Record<string, number> = {}
    for (const e of Array.from(estadoActual.values())) counts[e] = (counts[e] ?? 0) + 1
    return ORDEN.filter((s) => counts[s]).map((s) => ({ key: s, name: LABEL[s], value: counts[s], color: COLOR[s] }))
  }, [estadoActual])

  const kpi = useMemo(() => {
    const cats = data?.categorias ?? []
    if (cats.length === 0) return null
    const s = cats.reduce((a, c) => ({
      equipos: a.equipos + Number(c.total_equipos),
      dias: a.dias + Number(c.dias_equipo),
      up: a.up + Number(c.dias_up),
      down: a.down + Number(c.dias_down),
      ev: a.ev + Number(c.eventos_falla_total),
    }), { equipos: 0, dias: 0, up: 0, down: 0, ev: 0 })
    const dispFis = s.dias > 0 ? s.up / s.dias : 0
    const util = s.dias > 0 ? cats.reduce((a, c) => a + Number(c.utilizacion_bruta) * Number(c.dias_equipo), 0) / s.dias : 0
    const mtbf = s.ev > 0 ? s.up / s.ev : s.up
    const mttr = s.ev > 0 ? s.down / s.ev : 0
    const dispInh = mtbf + mttr > 0 ? mtbf / (mtbf + mttr) : 1
    return { ...s, dispFis, util, mtbf, mttr, dispInh }
  }, [data])

  const equiposFiltrados = useMemo(
    () => filtroEstado ? equipos.filter((e) => estadoActual.get(e.activo_id) === filtroEstado) : equipos,
    [equipos, filtroEstado, estadoActual],
  )

  const histSel = useMemo(() => {
    if (!equipoSel) return null
    const estados: Record<string, string> = {}
    for (const c of matriz) if (c.activo_id === equipoSel) estados[c.fecha.slice(0, 10)] = c.estado
    const det = equipos.find((e) => e.activo_id === equipoSel) ?? null
    return { det, estados }
  }, [equipoSel, matriz, equipos])

  return (
    <div className="min-h-screen bg-gray-50 py-8">
      <div className="mx-auto max-w-5xl px-4">
        <div className="mb-5 flex flex-wrap items-start justify-between gap-3">
          <div>
            <h1 className="text-2xl font-bold text-[#0b2a4a]">Análisis de Fiabilidad de Flota — Pillado</h1>
            <p className="text-sm text-gray-500">
              MTBF · MTTR · Disponibilidad Inherente · {desde} a {hasta} · SICOM-ICEO
            </p>
            <p className="mt-1 text-xs text-gray-400">Haz click en una patente para ver su historial diario.</p>
          </div>
          <div className="flex items-end gap-2">
            <div>
              <label className="block text-[10px] uppercase text-gray-400">Desde</label>
              <input type="date" className="h-9 rounded border border-gray-300 px-2 text-sm" value={desde} onChange={(e) => setDesde(e.target.value)} />
            </div>
            <div>
              <label className="block text-[10px] uppercase text-gray-400">Hasta</label>
              <input type="date" className="h-9 rounded border border-gray-300 px-2 text-sm" value={hasta} onChange={(e) => setHasta(e.target.value)} />
            </div>
          </div>
        </div>

        {error && <div className="rounded-lg bg-red-50 p-4 text-sm text-red-700">No se pudo cargar: {error}</div>}
        {cargando && <div className="py-20 text-center text-gray-400">Cargando…</div>}

        {!cargando && kpi && (
          <div className="space-y-5">
            {/* KPIs */}
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-4 lg:grid-cols-6">
              <Kpi n={String(kpi.equipos)} l="Equipos" />
              <Kpi n={String(kpi.dias)} l="Días-equipo" />
              <Kpi n={fmtPct(kpi.dispFis)} l="Disp. física" />
              <Kpi n={fmtPct(kpi.dispInh)} l="Disp. inherente" />
              <Kpi n={`${fmtNum(kpi.mtbf)} d`} l="MTBF" />
              <Kpi n={`${fmtNum(kpi.mttr)} d`} l="MTTR" />
            </div>

            {/* Distribución por estado */}
            <Card title={`Distribución por estado${diasUnicos.length ? ` · ${diasUnicos[diasUnicos.length - 1]}` : ''} — click para filtrar`}>
              <div className="grid items-center gap-4 sm:grid-cols-2">
                <div className="h-56">
                  <ResponsiveContainer width="100%" height="100%">
                    <PieChart>
                      <Pie data={distEstado} cx="50%" cy="50%" innerRadius={48} outerRadius={88} paddingAngle={2}
                        dataKey="value" cursor="pointer" label={({ value }) => `${value}`}
                        onClick={(d: { key?: string }) => d?.key && setFiltroEstado(filtroEstado === d.key ? null : d.key)}>
                        {distEstado.map((e) => (
                          <Cell key={e.key} fill={e.color} opacity={filtroEstado && filtroEstado !== e.key ? 0.3 : 1} />
                        ))}
                      </Pie>
                      <Tooltip formatter={(v: number, n: string) => [`${v} equipos`, n]} />
                    </PieChart>
                  </ResponsiveContainer>
                </div>
                <div className="space-y-1">
                  {distEstado.map((e) => (
                    <button key={e.key} onClick={() => setFiltroEstado(filtroEstado === e.key ? null : e.key)}
                      className="flex w-full items-center justify-between rounded px-1 text-sm hover:bg-gray-50"
                      style={{ opacity: filtroEstado && filtroEstado !== e.key ? 0.4 : 1 }}>
                      <span className="flex items-center gap-2">
                        <span className="inline-block h-3 w-3 rounded-sm" style={{ background: e.color }} />
                        {e.name} <span className="text-gray-400">({e.key})</span>
                      </span>
                      <b>{e.value}</b>
                    </button>
                  ))}
                </div>
              </div>
            </Card>

            {/* Stock de combustible (debajo de la torta) */}
            {combustible.length > 0 && (
              <Card title="Stock de combustible">
                <div className="overflow-x-auto">
                  <table className="w-full text-xs">
                    <thead>
                      <tr className="border-b bg-gray-50 text-left uppercase text-gray-500">
                        <th className="px-2 py-2">Estanque</th>
                        <th className="px-2 py-2 text-right">Capacidad</th>
                        <th className="px-2 py-2 text-right">Stock</th>
                        <th className="px-2 py-2 text-right">% lleno</th>
                        <th className="px-2 py-2 text-right">Mínimo</th>
                        <th className="px-2 py-2 text-right">Cobertura</th>
                        <th className="px-2 py-2">Agotamiento est.</th>
                        <th className="px-2 py-2 text-center">Estado</th>
                      </tr>
                    </thead>
                    <tbody>
                      {combustible.map((e) => {
                        const cap = Number(e.capacidad_lt || 0), st = Number(e.stock_actual || 0)
                        const llen = cap > 0 ? Math.round(st / cap * 100) : 0
                        const sev = SEV[e.severidad] ?? SEV.ok
                        return (
                          <tr key={e.estanque_codigo} className="border-b">
                            <td className="px-2 py-1.5"><b>{e.estanque_codigo}</b><div className="text-[10px] text-gray-400">{e.estanque_nombre}</div></td>
                            <td className="px-2 py-1.5 text-right">{lt(cap)} L</td>
                            <td className="px-2 py-1.5 text-right font-semibold">{lt(st)} L</td>
                            <td className="px-2 py-1.5 text-right">{llen}%</td>
                            <td className="px-2 py-1.5 text-right text-gray-400">{lt(e.stock_minimo)} L</td>
                            <td className="px-2 py-1.5 text-right">{e.dias_cobertura != null ? `${Number(e.dias_cobertura).toFixed(1)} d` : '—'}</td>
                            <td className="px-2 py-1.5">{e.fecha_agotamiento_estimada ? e.fecha_agotamiento_estimada.slice(0, 10) : '—'}</td>
                            <td className="px-2 py-1.5 text-center">
                              <span className="inline-block rounded px-2 py-0.5 text-[10px] font-semibold text-white" style={{ background: sev[1] }}>{sev[0]}</span>
                            </td>
                          </tr>
                        )
                      })}
                    </tbody>
                    <tfoot>
                      <tr className="font-bold text-white" style={{ background: '#0b2a4a' }}>
                        <td className="px-2 py-2">CONSOLIDADO ({combustible.length} estanques)</td>
                        <td className="px-2 py-2 text-right">{lt(combTot.cap)} L</td>
                        <td className="px-2 py-2 text-right">{lt(combTot.st)} L</td>
                        <td className="px-2 py-2 text-right">{combTot.cap > 0 ? Math.round(combTot.st / combTot.cap * 100) : 0}%</td>
                        <td className="px-2 py-2 text-right">{lt(combTot.min)} L</td>
                        <td className="px-2 py-2 text-center" colSpan={3}>Stock total disponible</td>
                      </tr>
                    </tfoot>
                  </table>
                </div>
              </Card>
            )}

            {/* Detalle por equipo (clickable) */}
            <Card title="Detalle por equipo — click en la patente para ver su historial">
              {filtroEstado && (
                <div className="mb-2 flex items-center gap-2 text-xs">
                  <span className="rounded bg-blue-50 px-2 py-1 text-blue-700">
                    Filtro: {LABEL[filtroEstado] ?? filtroEstado} ({equiposFiltrados.length})
                  </span>
                  <button onClick={() => setFiltroEstado(null)} className="text-blue-600 hover:underline">Limpiar filtro</button>
                </div>
              )}
              <div className="overflow-x-auto">
                <table className="w-full text-xs whitespace-nowrap">
                  <thead>
                    <tr className="border-b bg-gray-50 text-left uppercase text-gray-500">
                      <th className="px-2 py-2">Patente</th>
                      <th className="px-2 py-2">Equipo</th>
                      <th className="px-2 py-2">Cliente</th>
                      <th className="px-2 py-2 text-right">Días</th>
                      <th className="px-2 py-2 text-right">UP</th>
                      <th className="px-2 py-2 text-right">DOWN</th>
                      <th className="px-2 py-2 text-right">N°Fal</th>
                      <th className="px-2 py-2 text-right">MTBF</th>
                      <th className="px-2 py-2 text-right">MTTR</th>
                      <th className="px-2 py-2 text-right">Disp.Inh</th>
                      <th className="px-2 py-2 text-right">Disp.Fís</th>
                    </tr>
                  </thead>
                  <tbody>
                    {equiposFiltrados.map((d) => (
                      <tr key={d.activo_id} className="border-b hover:bg-blue-50">
                        <td className="px-2 py-1.5">
                          <button onClick={() => setEquipoSel(d.activo_id)} className="font-mono font-semibold text-blue-700 hover:underline">
                            {d.patente}
                          </button>
                        </td>
                        <td className="px-2 py-1.5 text-gray-600">{d.equipamiento ?? '—'}</td>
                        <td className="px-2 py-1.5 text-gray-500 max-w-[150px] truncate">{d.cliente ?? '—'}</td>
                        <td className="px-2 py-1.5 text-right">{d.dias_observados}</td>
                        <td className="px-2 py-1.5 text-right text-green-700">{d.dias_up}</td>
                        <td className="px-2 py-1.5 text-right text-red-700">{d.dias_down}</td>
                        <td className="px-2 py-1.5 text-right">{d.eventos_falla}</td>
                        <td className="px-2 py-1.5 text-right">{fmtNum(d.mtbf_dias)}</td>
                        <td className="px-2 py-1.5 text-right">{fmtNum(d.mttr_dias)}</td>
                        <td className={`px-2 py-1.5 text-right font-semibold ${colorDisp(Number(d.disponibilidad_inherente))}`}>{fmtPct(d.disponibilidad_inherente, 0)}</td>
                        <td className={`px-2 py-1.5 text-right ${colorDisp(Number(d.disponibilidad_fisica))}`}>{fmtPct(d.disponibilidad_fisica, 0)}</td>
                      </tr>
                    ))}
                    {equiposFiltrados.length === 0 && (
                      <tr><td colSpan={11} className="py-6 text-center text-gray-400">Sin equipos en ese estado.</td></tr>
                    )}
                  </tbody>
                </table>
              </div>
            </Card>

            <p className="pt-2 text-center text-xs text-gray-400">Pillado · SICOM-ICEO · Disp. Inherente = MTBF ÷ (MTBF + MTTR)</p>
          </div>
        )}
      </div>

      {/* Modal historial */}
      {histSel && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4" onClick={() => setEquipoSel(null)}>
          <div className="max-h-[85vh] w-full max-w-3xl overflow-auto rounded-2xl bg-white p-5 shadow-xl" onClick={(e) => e.stopPropagation()}>
            <div className="mb-3 flex items-start justify-between">
              <div>
                <h3 className="text-lg font-bold text-[#0b2a4a]">Historial · {histSel.det?.patente}</h3>
                <p className="text-sm text-gray-500">{histSel.det?.equipamiento ?? ''}{histSel.det?.cliente ? ` · ${histSel.det.cliente}` : ''}</p>
              </div>
              <button onClick={() => setEquipoSel(null)} className="rounded px-2 py-1 text-gray-400 hover:bg-gray-100">✕</button>
            </div>

            <div className="flex flex-wrap gap-0.5">
              {diasUnicos.map((f) => {
                const e = histSel.estados[f]
                return (
                  <div key={f} className="flex flex-col items-center">
                    <div className="text-[8px] text-gray-400">{f.slice(8, 10)}</div>
                    <div className="h-6 w-6 text-center text-[10px] font-semibold leading-6"
                      style={{ background: e ? COLOR[e] : '#F3F4F6', color: e ? '#fff' : '#D1D5DB' }}
                      title={e ? `${f}: ${LABEL[e]}` : f}>
                      {e ?? ''}
                    </div>
                  </div>
                )
              })}
            </div>

            <div className="mt-4 flex flex-wrap gap-x-3 gap-y-1 text-xs">
              {(() => {
                const counts: Record<string, number> = {}
                for (const f of diasUnicos) { const e = histSel.estados[f]; if (e) counts[e] = (counts[e] ?? 0) + 1 }
                return ORDEN.filter((e) => counts[e]).map((e) => (
                  <span key={e} className="flex items-center gap-1 text-gray-700">
                    <span className="inline-block h-3 w-3 rounded-sm" style={{ background: COLOR[e] }} />
                    {LABEL[e]}: <b>{counts[e]}</b> d
                  </span>
                ))
              })()}
            </div>

            {histSel.det && (
              <div className="mt-4 grid grid-cols-3 gap-2 border-t pt-3 text-xs">
                <div>Disp. inherente: <b>{fmtPct(histSel.det.disponibilidad_inherente)}</b></div>
                <div>Disp. física: <b>{fmtPct(histSel.det.disponibilidad_fisica)}</b></div>
                <div>MTBF / MTTR: <b>{fmtNum(histSel.det.mtbf_dias)} / {fmtNum(histSel.det.mttr_dias)} d</b></div>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  )
}

function Kpi({ n, l }: { n: string; l: string }) {
  return (
    <div className="rounded-xl border bg-white p-3 text-center">
      <div className="text-xl font-bold text-[#0b2a4a]">{n}</div>
      <div className="mt-1 text-[10px] uppercase tracking-wide text-gray-500">{l}</div>
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
