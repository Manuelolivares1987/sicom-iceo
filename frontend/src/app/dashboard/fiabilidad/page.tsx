'use client'

import { useMemo, useState } from 'react'
import {
  Activity, AlertTriangle, TrendingUp, TrendingDown,
  Gauge as GaugeIcon, Zap, Clock, Wrench,
} from 'lucide-react'
import {
  PieChart, Pie, Cell,
  BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer,
  ScatterChart, Scatter, ZAxis,
  RadialBarChart, RadialBar, PolarAngleAxis,
} from 'recharts'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Spinner } from '@/components/ui/spinner'
import { Badge } from '@/components/ui/badge'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useFiabilidadFlota, useDetalleFiabilidadFlota } from '@/hooks/use-fiabilidad'
import {
  CATEGORIA_LABELS,
  CATEGORIA_COLORS,
  type CategoriaUso,
  type ActivoFiabilidadDetalle,
} from '@/lib/services/fiabilidad'
import { todayISO } from '@/lib/utils'

// ─── Paleta ─────────────────────────────────────────────
const CAT_PIE_COLORS: Record<string, string> = {
  arriendo_comercial: '#16A34A',
  leasing_operativo: '#2563EB',
  uso_interno: '#0891B2',
  venta: '#7C3AED',
  sin_categoria: '#9CA3AF',
}

// ─── Helpers ───────────────────────────────────────────
const fmtPct = (v: number | null | undefined, digits = 1) =>
  v == null ? '—' : `${(Number(v) * 100).toFixed(digits)}%`
const fmtNum = (v: number | null | undefined, digits = 1) =>
  v == null ? '—' : Number(v).toFixed(digits)
const fmtInt = (v: number | null | undefined) => (v == null ? '—' : String(Math.round(Number(v))))

function colorOEE(v: number | null | undefined): string {
  if (v == null) return 'text-gray-500'
  if (v >= 0.85) return 'text-green-600 font-semibold'
  if (v >= 0.7) return 'text-blue-600'
  if (v >= 0.5) return 'text-amber-600'
  return 'text-red-600 font-semibold'
}

function colorOEEBar(v: number): string {
  if (v >= 0.85) return '#16A34A'
  if (v >= 0.7) return '#2563EB'
  if (v >= 0.5) return '#F59E0B'
  return '#DC2626'
}

function colorDispTxt(v: number): string {
  if (v >= 0.92) return 'text-green-600'
  if (v >= 0.85) return 'text-blue-600'
  if (v >= 0.75) return 'text-amber-600'
  return 'text-red-600'
}

// ────────────────────────────────────────────────────────
// Page
// ────────────────────────────────────────────────────────
export default function FiabilidadPage() {
  useRequireAuth()

  const hoy = new Date()
  const primerDiaMes = `${hoy.getFullYear()}-${String(hoy.getMonth() + 1).padStart(2, '0')}-01`
  const [fechaInicio, setFechaInicio] = useState(primerDiaMes)
  const [fechaFin, setFechaFin] = useState(todayISO())
  const [filtroCat, setFiltroCat] = useState<CategoriaUso | 'todas'>('todas')

  const { data: porCategoria = [], isLoading: loadingCat } =
    useFiabilidadFlota(fechaInicio, fechaFin)
  const { data: detalles = [], isLoading: loadingDetalle } =
    useDetalleFiabilidadFlota(fechaInicio, fechaFin)

  // ─── Agregados globales ────────────────────────────────
  const kpiGlobal = useMemo(() => {
    if (porCategoria.length === 0) return null
    const acc = porCategoria.reduce(
      (a, c) => ({
        total_equipos: a.total_equipos + Number(c.total_equipos),
        dias_equipo: a.dias_equipo + Number(c.dias_equipo),
        dias_up: a.dias_up + Number(c.dias_up),
        dias_down: a.dias_down + Number(c.dias_down),
        eventos_falla_total: a.eventos_falla_total + Number(c.eventos_falla_total),
      }),
      { total_equipos: 0, dias_equipo: 0, dias_up: 0, dias_down: 0, eventos_falla_total: 0 },
    )
    const disp = acc.dias_equipo > 0 ? acc.dias_up / acc.dias_equipo : 0
    const mtbf = acc.eventos_falla_total > 0 ? acc.dias_up / acc.eventos_falla_total : acc.dias_up
    const mttr = acc.eventos_falla_total > 0 ? acc.dias_down / acc.eventos_falla_total : 0
    return { ...acc, disp_fisica: disp, mtbf, mttr }
  }, [porCategoria])

  const utilBruta = useMemo(() => {
    if (detalles.length === 0) return 0
    const sumTotal = detalles.reduce((s, d) => s + d.dias_observados, 0)
    const sumAL = detalles.reduce((s, d) => s + d.dias_a + d.dias_l, 0)
    return sumTotal > 0 ? sumAL / sumTotal : 0
  }, [detalles])

  const oeeGlobal = useMemo(() => {
    const conOEE = detalles.filter((d) => d.oee_total != null)
    if (conOEE.length === 0) return null
    return conOEE.reduce((s, d) => s + Number(d.oee_total), 0) / conOEE.length
  }, [detalles])

  // ─── Pie: equipos por categoría ────────────────────────
  const piePorCategoria = useMemo(
    () =>
      porCategoria.map((c) => ({
        key: (c.categoria ?? 'sin_categoria') as string,
        name: c.categoria ? CATEGORIA_LABELS[c.categoria] : 'Sin categoría',
        value: Number(c.total_equipos),
        color: CAT_PIE_COLORS[c.categoria ?? 'sin_categoria'] ?? '#6B7280',
      })),
    [porCategoria],
  )

  // ─── Filtrado por categoría ────────────────────────────
  const detallesFiltrados = useMemo(() => {
    if (filtroCat === 'todas') return detalles
    return detalles.filter((d) => d.categoria_uso === filtroCat)
  }, [detalles, filtroCat])

  // ─── Rankings ──────────────────────────────────────────
  const top5Criticos = useMemo(
    () =>
      [...detalles]
        .filter((d) => d.dias_down > 0)
        .sort((a, b) => b.dias_down - a.dias_down)
        .slice(0, 5),
    [detalles],
  )

  const oeeRanking = useMemo(
    () =>
      detalles.filter(
        (d) =>
          d.oee_total != null &&
          (d.categoria_uso === 'arriendo_comercial' || d.categoria_uso === 'leasing_operativo'),
      ),
    [detalles],
  )
  const top5OEE = useMemo(
    () =>
      [...oeeRanking]
        .sort((a, b) => (b.oee_total ?? 0) - (a.oee_total ?? 0))
        .slice(0, 5),
    [oeeRanking],
  )
  const bottom5OEE = useMemo(
    () =>
      [...oeeRanking]
        .sort((a, b) => (a.oee_total ?? 0) - (b.oee_total ?? 0))
        .slice(0, 5),
    [oeeRanking],
  )

  // ─── Scatter: Disp.Inh vs OEE ─────────────────────────
  const scatterData = useMemo(
    () =>
      detalles
        .filter((d) => d.oee_total != null && d.dias_observados > 0)
        .map((d) => ({
          patente: d.patente,
          disp: Number(d.disponibilidad_inherente) * 100,
          oee: Number(d.oee_total) * 100,
          dias: d.dias_observados,
          color: CAT_PIE_COLORS[d.categoria_uso ?? 'sin_categoria'] ?? '#6B7280',
          categoria: d.categoria_uso,
        })),
    [detalles],
  )

  const isLoading = loadingCat || loadingDetalle

  return (
    <div className="space-y-6">
      {/* ─── Header ───────────────────────────── */}
      <div className="rounded-2xl bg-gradient-to-r from-indigo-600 via-blue-600 to-cyan-600 p-6 text-white shadow-lg">
        <div className="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
          <div>
            <h1 className="text-2xl font-bold flex items-center gap-2">
              <Activity className="h-7 w-7" />
              Análisis de Fiabilidad & OEE de Flota
            </h1>
            <p className="text-sm text-white/80 mt-1">
              MTBF · MTTR · Disponibilidad Inherente · OEE (A × P × Q) — metodología del análisis ejecutivo
            </p>
          </div>
          <div className="flex gap-2">
            <div>
              <label className="block text-[10px] uppercase text-white/70">Desde</label>
              <input
                type="date"
                className="h-9 rounded bg-white/95 px-2 text-sm text-gray-800"
                value={fechaInicio}
                onChange={(e) => setFechaInicio(e.target.value)}
              />
            </div>
            <div>
              <label className="block text-[10px] uppercase text-white/70">Hasta</label>
              <input
                type="date"
                className="h-9 rounded bg-white/95 px-2 text-sm text-gray-800"
                value={fechaFin}
                onChange={(e) => setFechaFin(e.target.value)}
              />
            </div>
          </div>
        </div>
      </div>

      {isLoading && (
        <div className="flex h-64 items-center justify-center">
          <Spinner className="h-8 w-8" />
        </div>
      )}

      {!isLoading && !kpiGlobal && (
        <Card>
          <CardContent className="py-10 text-center space-y-2">
            <AlertTriangle className="h-10 w-10 text-amber-500 mx-auto" />
            <h3 className="text-lg font-semibold text-gray-800">Sin datos en el período</h3>
            <p className="text-sm text-gray-500 max-w-lg mx-auto">
              Revisa que (1) las migraciones 40-42 estén aplicadas en Supabase,
              (2) el seed de categoría esté corrido y (3) haya filas en
              <code className="mx-1 rounded bg-gray-100 px-1 text-xs">estado_diario_flota</code>
              dentro del rango {fechaInicio} → {fechaFin}. Si todo está listo,
              mira la consola del navegador (F12 → Network) por errores 400/500
              en las llamadas <code className="text-xs">rpc/fn_calcular_fiabilidad_*</code>.
            </p>
          </CardContent>
        </Card>
      )}

      {!isLoading && kpiGlobal && (
        <>
          {/* ─── KPI Tiles ───────────────────────── */}
          <div className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-6 gap-3">
            <KpiTile
              icon={<Zap className="h-4 w-4" />}
              label="Equipos"
              value={fmtInt(kpiGlobal.total_equipos)}
              tone="indigo"
            />
            <KpiTile
              icon={<Clock className="h-4 w-4" />}
              label="Días-Eq"
              value={fmtInt(kpiGlobal.dias_equipo)}
              tone="slate"
            />
            <KpiTile
              icon={<TrendingUp className="h-4 w-4" />}
              label="Días UP"
              value={fmtInt(kpiGlobal.dias_up)}
              tone="green"
            />
            <KpiTile
              icon={<TrendingDown className="h-4 w-4" />}
              label="Días DOWN"
              value={fmtInt(kpiGlobal.dias_down)}
              tone="red"
              hint={`${kpiGlobal.eventos_falla_total} eventos`}
            />
            <KpiTile
              icon={<Wrench className="h-4 w-4" />}
              label="MTBF"
              value={`${fmtNum(kpiGlobal.mtbf)} d`}
              tone="blue"
              hint="Media entre fallas"
            />
            <KpiTile
              icon={<AlertTriangle className="h-4 w-4" />}
              label="MTTR"
              value={`${fmtNum(kpiGlobal.mttr)} d`}
              tone="amber"
              hint="Media reparación"
            />
          </div>

          {/* ─── Gauges Disp Física + OEE + Util ──────────── */}
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            <GaugeCard
              title="Disponibilidad Física"
              value={kpiGlobal.disp_fisica * 100}
              target={92}
              unit="%"
              description="World-class industria pesada: ≥ 92%"
            />
            <GaugeCard
              title="Utilización Bruta"
              value={utilBruta * 100}
              target={70}
              unit="%"
              description="(A + L) / Total — captura comercial"
            />
            <GaugeCard
              title="OEE Flota"
              value={(oeeGlobal ?? 0) * 100}
              target={85}
              unit="%"
              description="A × P × Q — world-class ≥ 85%"
            />
          </div>

          {/* ─── Distribución por Categoría + Matriz Disp vs OEE ─── */}
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
            {/* Pie interactivo */}
            <Card>
              <CardHeader className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2 pb-2">
                <CardTitle className="text-base text-gray-700">
                  Distribución por Categoría
                </CardTitle>
                {filtroCat !== 'todas' && (
                  <button
                    className="text-xs text-blue-600 hover:underline"
                    onClick={() => setFiltroCat('todas')}
                  >
                    Limpiar filtro
                  </button>
                )}
              </CardHeader>
              <CardContent>
                <div className="h-72">
                  <ResponsiveContainer width="100%" height="100%">
                    <PieChart>
                      <Pie
                        data={piePorCategoria}
                        cx="50%" cy="50%"
                        innerRadius={60} outerRadius={110}
                        paddingAngle={3}
                        dataKey="value"
                        label={({ name, value }) => `${name}: ${value}`}
                        cursor="pointer"
                        onClick={(data: any) => {
                          if (data?.key && data.key !== 'sin_categoria') {
                            setFiltroCat(
                              filtroCat === data.key
                                ? 'todas'
                                : (data.key as CategoriaUso),
                            )
                          }
                        }}
                      >
                        {piePorCategoria.map((entry) => (
                          <Cell
                            key={entry.key}
                            fill={entry.color}
                            opacity={
                              filtroCat !== 'todas' && filtroCat !== entry.key ? 0.3 : 1
                            }
                          />
                        ))}
                      </Pie>
                      <Tooltip />
                    </PieChart>
                  </ResponsiveContainer>
                </div>
                <p className="text-xs text-gray-500 text-center mt-1">
                  Click en un segmento para filtrar la tabla detalle
                </p>
              </CardContent>
            </Card>

            {/* Scatter Disp.Inh vs OEE */}
            <Card>
              <CardHeader className="pb-2">
                <CardTitle className="text-base text-gray-700">
                  Matriz Disponibilidad Inherente vs OEE
                </CardTitle>
                <p className="text-[11px] text-gray-400">
                  Arriba-derecha = world class · Abajo-izq = foco de mejora
                </p>
              </CardHeader>
              <CardContent>
                <div className="h-72">
                  <ResponsiveContainer width="100%" height="100%">
                    <ScatterChart margin={{ top: 10, right: 10, bottom: 20, left: 0 }}>
                      <CartesianGrid strokeDasharray="3 3" />
                      <XAxis
                        type="number" dataKey="disp" name="Disp. Inh."
                        unit="%" domain={[0, 100]}
                        label={{ value: 'Disp. Inherente (%)', position: 'bottom', offset: -5, fontSize: 11 }}
                      />
                      <YAxis
                        type="number" dataKey="oee" name="OEE"
                        unit="%" domain={[0, 100]}
                        label={{ value: 'OEE (%)', angle: -90, position: 'insideLeft', fontSize: 11 }}
                      />
                      <ZAxis type="number" dataKey="dias" range={[40, 200]} name="Días" />
                      <Tooltip
                        cursor={{ strokeDasharray: '3 3' }}
                        content={({ active, payload }) => {
                          if (!active || !payload?.length) return null
                          const d: any = payload[0].payload
                          return (
                            <div className="rounded border bg-white p-2 text-xs shadow">
                              <div className="font-mono font-semibold">{d.patente}</div>
                              <div className="text-gray-600">
                                Disp.Inh: {d.disp.toFixed(1)}%
                              </div>
                              <div className="text-gray-600">OEE: {d.oee.toFixed(1)}%</div>
                              <div className="text-gray-500 text-[11px]">
                                {d.categoria ? CATEGORIA_LABELS[d.categoria as CategoriaUso] : '—'}
                              </div>
                            </div>
                          )
                        }}
                      />
                      <Scatter data={scatterData} fill="#6366F1">
                        {scatterData.map((entry, i) => (
                          <Cell key={i} fill={entry.color} />
                        ))}
                      </Scatter>
                    </ScatterChart>
                  </ResponsiveContainer>
                </div>
              </CardContent>
            </Card>
          </div>

          {/* ─── Rankings (Bar charts horizontales) ─── */}
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
            <RankingBarCard
              title="Top 5 Críticos (DOWN)"
              icon={<AlertTriangle className="h-4 w-4 text-red-600" />}
              borderClass="border-red-200"
              data={top5Criticos.map((d) => ({
                patente: d.patente,
                valor: d.dias_down,
                color: '#DC2626',
              }))}
              labelUnit="días"
            />
            <RankingBarCard
              title="Top 5 OEE"
              icon={<TrendingUp className="h-4 w-4 text-green-600" />}
              borderClass="border-green-200"
              data={top5OEE.map((d) => ({
                patente: d.patente,
                valor: Math.round((Number(d.oee_total) ?? 0) * 100),
                color: colorOEEBar(Number(d.oee_total) ?? 0),
              }))}
              labelUnit="%"
            />
            <RankingBarCard
              title="Bottom 5 OEE"
              icon={<TrendingDown className="h-4 w-4 text-amber-600" />}
              borderClass="border-amber-200"
              data={bottom5OEE.map((d) => ({
                patente: d.patente,
                valor: Math.round((Number(d.oee_total) ?? 0) * 100),
                color: colorOEEBar(Number(d.oee_total) ?? 0),
              }))}
              labelUnit="%"
            />
          </div>

          {/* ─── KPIs por Categoría ─── */}
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-base text-gray-700">KPIs por Categoría</CardTitle>
            </CardHeader>
            <CardContent className="overflow-x-auto">
              <table className="w-full text-xs">
                <thead>
                  <tr className="border-b bg-gray-50 text-left text-gray-500 uppercase">
                    <th className="px-2 py-2">Categoría</th>
                    <th className="px-2 py-2 text-right">Equipos</th>
                    <th className="px-2 py-2 text-right">Días-Eq</th>
                    <th className="px-2 py-2 text-right">Disp. Física</th>
                    <th className="px-2 py-2 text-right">Util. Bruta</th>
                    <th className="px-2 py-2 text-right">N° Fallas</th>
                    <th className="px-2 py-2 text-right">MTBF (d)</th>
                    <th className="px-2 py-2 text-right">MTTR (d)</th>
                  </tr>
                </thead>
                <tbody>
                  {porCategoria.map((c) => (
                    <tr key={c.categoria ?? 'sin'} className="border-b hover:bg-gray-50">
                      <td className="px-2 py-2">
                        {c.categoria ? (
                          <Badge className={CATEGORIA_COLORS[c.categoria]}>
                            {CATEGORIA_LABELS[c.categoria]}
                          </Badge>
                        ) : (
                          <span className="text-gray-400 italic">Sin categoría</span>
                        )}
                      </td>
                      <td className="px-2 py-2 text-right">{c.total_equipos}</td>
                      <td className="px-2 py-2 text-right">{c.dias_equipo}</td>
                      <td className={`px-2 py-2 text-right font-semibold ${colorDispTxt(Number(c.disponibilidad_fisica))}`}>
                        {fmtPct(Number(c.disponibilidad_fisica))}
                      </td>
                      <td className="px-2 py-2 text-right">{fmtPct(Number(c.utilizacion_bruta))}</td>
                      <td className="px-2 py-2 text-right">{c.eventos_falla_total}</td>
                      <td className="px-2 py-2 text-right">{fmtNum(Number(c.mtbf_agregado))}</td>
                      <td className="px-2 py-2 text-right">{fmtNum(Number(c.mttr_agregado))}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </CardContent>
          </Card>

          {/* ─── Tabla detalle ─── */}
          <Card>
            <CardHeader className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2">
              <CardTitle className="text-base text-gray-700">
                Detalle por Equipo
                {filtroCat !== 'todas' && (
                  <span className="ml-2 text-xs text-gray-500">
                    · filtro: {CATEGORIA_LABELS[filtroCat as CategoriaUso]}
                  </span>
                )}
              </CardTitle>
              <select
                className="h-9 rounded border border-gray-300 px-2 text-sm"
                value={filtroCat}
                onChange={(e) => setFiltroCat(e.target.value as CategoriaUso | 'todas')}
              >
                <option value="todas">Todas las categorías</option>
                <option value="arriendo_comercial">Arriendo Comercial</option>
                <option value="leasing_operativo">Leasing Operativo</option>
                <option value="uso_interno">Uso Interno</option>
                <option value="venta">Venta</option>
              </select>
            </CardHeader>
            <CardContent className="overflow-x-auto">
              <table className="w-full text-xs whitespace-nowrap">
                <thead>
                  <tr className="border-b bg-gray-50 text-left text-gray-500 uppercase">
                    <th className="px-2 py-2">Patente</th>
                    <th className="px-2 py-2">Equipamiento</th>
                    <th className="px-2 py-2">Cliente</th>
                    <th className="px-2 py-2">Categoría</th>
                    <th className="px-2 py-2 text-right">Tot</th>
                    <th className="px-2 py-2 text-right">A</th>
                    <th className="px-2 py-2 text-right">D</th>
                    <th className="px-2 py-2 text-right">U</th>
                    <th className="px-2 py-2 text-right">L</th>
                    <th className="px-2 py-2 text-right">M</th>
                    <th className="px-2 py-2 text-right">T</th>
                    <th className="px-2 py-2 text-right">F</th>
                    <th className="px-2 py-2 text-right">UP</th>
                    <th className="px-2 py-2 text-right">DOWN</th>
                    <th className="px-2 py-2 text-right">N°Fal</th>
                    <th className="px-2 py-2 text-right">MTBF</th>
                    <th className="px-2 py-2 text-right">MTTR</th>
                    <th className="px-2 py-2 text-right">Disp.Inh</th>
                    <th className="px-2 py-2 text-right">A</th>
                    <th className="px-2 py-2 text-right">P</th>
                    <th className="px-2 py-2 text-right">Q</th>
                    <th className="px-2 py-2 text-right">OEE</th>
                  </tr>
                </thead>
                <tbody>
                  {detallesFiltrados.map((d) => (
                    <tr key={d.activo_id} className="border-b hover:bg-gray-50">
                      <td className="px-2 py-1.5 font-mono font-semibold">{d.patente}</td>
                      <td className="px-2 py-1.5">{d.equipamiento ?? '—'}</td>
                      <td className="px-2 py-1.5 text-gray-500 max-w-[160px] truncate">
                        {d.cliente_actual ?? '—'}
                      </td>
                      <td className="px-2 py-1.5">
                        {d.categoria_uso ? (
                          <Badge className={CATEGORIA_COLORS[d.categoria_uso]}>
                            {CATEGORIA_LABELS[d.categoria_uso]}
                          </Badge>
                        ) : (
                          <span className="text-gray-400 italic">—</span>
                        )}
                      </td>
                      <td className="px-2 py-1.5 text-right">{d.dias_observados}</td>
                      <td className="px-2 py-1.5 text-right">{d.dias_a}</td>
                      <td className="px-2 py-1.5 text-right">{d.dias_d}</td>
                      <td className="px-2 py-1.5 text-right">{d.dias_u}</td>
                      <td className="px-2 py-1.5 text-right">{d.dias_l}</td>
                      <td className="px-2 py-1.5 text-right text-amber-700">{d.dias_m}</td>
                      <td className="px-2 py-1.5 text-right text-amber-700">{d.dias_t}</td>
                      <td className="px-2 py-1.5 text-right text-red-700">{d.dias_f}</td>
                      <td className="px-2 py-1.5 text-right text-green-700">{d.dias_up}</td>
                      <td className="px-2 py-1.5 text-right text-red-700">{d.dias_down}</td>
                      <td className="px-2 py-1.5 text-right">{d.eventos_falla}</td>
                      <td className="px-2 py-1.5 text-right">{fmtNum(d.mtbf_dias)}</td>
                      <td className="px-2 py-1.5 text-right">{fmtNum(d.mttr_dias)}</td>
                      <td className={`px-2 py-1.5 text-right font-semibold ${colorDispTxt(d.disponibilidad_inherente)}`}>
                        {fmtPct(d.disponibilidad_inherente, 0)}
                      </td>
                      <td className="px-2 py-1.5 text-right">{fmtPct(d.oee_a)}</td>
                      <td className="px-2 py-1.5 text-right">
                        {d.oee_p == null ? 'N/A' : fmtPct(d.oee_p)}
                      </td>
                      <td className="px-2 py-1.5 text-right">{fmtPct(d.oee_q)}</td>
                      <td className={`px-2 py-1.5 text-right ${colorOEE(d.oee_total)}`}>
                        {d.oee_total == null ? 'N/A' : fmtPct(d.oee_total)}
                      </td>
                    </tr>
                  ))}
                  {detallesFiltrados.length === 0 && (
                    <tr>
                      <td colSpan={22} className="py-6 text-center text-gray-400">
                        Sin equipos en esa categoría con datos en el período
                      </td>
                    </tr>
                  )}
                </tbody>
              </table>
              <p className="mt-2 text-[11px] text-gray-400">
                Columnas día-estado: A=Arrendado · D=Disponible · U=Uso Interno · L=Leasing · M=Mantención (&gt;1d) · T=Taller (&lt;1d) · F=Fuera Servicio ·
                UP=días operativos · DOWN=días no disponibles. OEE: A=Disp · P=Rendimiento · Q=Calidad · OEE = A × P × Q.
              </p>
            </CardContent>
          </Card>
        </>
      )}
    </div>
  )
}

// ─── Subcomponentes ──────────────────────────────────────
function KpiTile({
  icon, label, value, hint, tone,
}: {
  icon: React.ReactNode
  label: string
  value: string
  hint?: string
  tone: 'indigo' | 'slate' | 'green' | 'red' | 'blue' | 'amber'
}) {
  const toneBg: Record<string, string> = {
    indigo: 'from-indigo-50 to-white border-indigo-200 text-indigo-700',
    slate: 'from-slate-50 to-white border-slate-200 text-slate-700',
    green: 'from-green-50 to-white border-green-200 text-green-700',
    red: 'from-red-50 to-white border-red-200 text-red-700',
    blue: 'from-blue-50 to-white border-blue-200 text-blue-700',
    amber: 'from-amber-50 to-white border-amber-200 text-amber-700',
  }
  return (
    <div className={`rounded-xl border bg-gradient-to-br ${toneBg[tone]} p-3 shadow-sm transition hover:shadow-md`}>
      <div className="flex items-center justify-between">
        <span className="text-[10px] uppercase tracking-wide opacity-70">{label}</span>
        {icon}
      </div>
      <div className="mt-1 text-2xl font-bold">{value}</div>
      {hint && <div className="text-[10px] opacity-60">{hint}</div>}
    </div>
  )
}

function GaugeCard({
  title, value, target, unit, description,
}: {
  title: string
  value: number
  target: number
  unit: string
  description: string
}) {
  const pct = Math.max(0, Math.min(100, value))
  const color = pct >= target ? '#16A34A' : pct >= target * 0.85 ? '#F59E0B' : '#DC2626'
  const data = [{ name: title, value: pct, fill: color }]
  return (
    <Card>
      <CardHeader className="pb-0">
        <CardTitle className="text-sm text-gray-600 flex items-center gap-2">
          <GaugeIcon className="h-4 w-4" />
          {title}
        </CardTitle>
      </CardHeader>
      <CardContent>
        <div className="relative h-36">
          <ResponsiveContainer width="100%" height="100%">
            <RadialBarChart
              innerRadius="70%" outerRadius="100%"
              data={data} startAngle={180} endAngle={0}
              cx="50%" cy="100%"
            >
              <PolarAngleAxis type="number" domain={[0, 100]} tick={false} />
              <RadialBar dataKey="value" cornerRadius={10} fill={color} />
            </RadialBarChart>
          </ResponsiveContainer>
          <div className="absolute inset-0 flex flex-col items-center justify-end pb-2">
            <div className="text-3xl font-bold" style={{ color }}>
              {value.toFixed(1)}{unit}
            </div>
            <div className="text-[10px] text-gray-400">
              Meta {target}{unit}
            </div>
          </div>
        </div>
        <p className="text-[11px] text-gray-500 text-center">{description}</p>
      </CardContent>
    </Card>
  )
}

function RankingBarCard({
  title, icon, borderClass, data, labelUnit,
}: {
  title: string
  icon: React.ReactNode
  borderClass: string
  data: Array<{ patente: string; valor: number; color: string }>
  labelUnit: string
}) {
  return (
    <Card className={borderClass}>
      <CardHeader className="pb-0">
        <CardTitle className="text-sm text-gray-700 flex items-center gap-2">
          {icon}
          {title}
        </CardTitle>
      </CardHeader>
      <CardContent>
        {data.length === 0 ? (
          <p className="text-xs text-gray-400 text-center py-6">Sin datos</p>
        ) : (
          <div className="h-48">
            <ResponsiveContainer width="100%" height="100%">
              <BarChart
                data={data} layout="vertical" margin={{ left: 0, right: 24, top: 6, bottom: 6 }}
              >
                <XAxis type="number" hide />
                <YAxis
                  type="category" dataKey="patente" width={80}
                  tick={{ fontSize: 11, fontFamily: 'monospace' }}
                />
                <Tooltip
                  cursor={{ fill: '#F3F4F6' }}
                  formatter={(v: number) => `${v} ${labelUnit}`}
                />
                <Bar
                  dataKey="valor" radius={[0, 4, 4, 0]}
                  label={{ position: 'right', fontSize: 11, fill: '#374151',
                           formatter: (v: number) => `${v}${labelUnit}` }}
                >
                  {data.map((entry, i) => (
                    <Cell key={i} fill={entry.color} />
                  ))}
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          </div>
        )}
      </CardContent>
    </Card>
  )
}
