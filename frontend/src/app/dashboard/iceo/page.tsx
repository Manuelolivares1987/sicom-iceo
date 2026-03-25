'use client'

import { useState, useEffect, useMemo } from 'react'
import { useQuery } from '@tanstack/react-query'
import {
  ChevronDown,
  ChevronUp,
  TrendingUp,
  TrendingDown,
  AlertTriangle,
  CheckCircle2,
  XCircle,
  ShieldCheck,
  Lock,
  Calculator,
} from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Gauge } from '@/components/ui/gauge'
import { Spinner } from '@/components/ui/spinner'
import {
  Table,
  TableHeader,
  TableBody,
  TableRow,
  TableHead,
  TableCell,
} from '@/components/ui/table'
import { formatPercent, cn } from '@/lib/utils'
import {
  useICEOPeriodo,
  useICEOHistorico,
  useMedicionesKPI,
  useBloqueantesStatus,
  useKPIDefiniciones,
  useCalcularICEO,
} from '@/hooks/use-kpi-iceo'
import { getContratoActivo } from '@/lib/services/contratos'
import type { AreaKPI } from '@/types/database'
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  ReferenceLine,
} from 'recharts'

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
const MONTH_NAMES = [
  'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
  'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
]

const SHORT_MONTHS = [
  'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
  'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
]

function getAreaColor(puntaje: number): string {
  if (puntaje >= 95) return '#7C3AED'
  if (puntaje >= 85) return '#16A34A'
  if (puntaje >= 70) return '#F59E0B'
  return '#DC2626'
}

const areaLabels: Record<string, string> = {
  administracion_combustibles: 'Administración Combustibles',
  mantenimiento_fijos: 'Mantenimiento Puntos Fijos',
  mantenimiento_moviles: 'Mantenimiento Puntos Móviles',
}

const areaKeys: { key: 'A' | 'B' | 'C'; field: 'puntaje_area_a' | 'puntaje_area_b' | 'puntaje_area_c'; pesoField: 'peso_area_a' | 'peso_area_b' | 'peso_area_c'; area: AreaKPI }[] = [
  { key: 'A', field: 'puntaje_area_a', pesoField: 'peso_area_a', area: 'administracion_combustibles' },
  { key: 'B', field: 'puntaje_area_b', pesoField: 'peso_area_b', area: 'mantenimiento_fijos' },
  { key: 'C', field: 'puntaje_area_c', pesoField: 'peso_area_c', area: 'mantenimiento_moviles' },
]

function buildPeriodoInicio(year: number, month: number): string {
  return `${year}-${String(month + 1).padStart(2, '0')}-01`
}

// ---------------------------------------------------------------------------
// Main page
// ---------------------------------------------------------------------------
export default function ICEOPage() {
  const [expandedArea, setExpandedArea] = useState<string | null>('A')
  const [contratoId, setContratoId] = useState<string>('')

  // Period selector state
  const now = new Date()
  const [selectedYear, setSelectedYear] = useState(now.getFullYear())
  const [selectedMonth, setSelectedMonth] = useState(now.getMonth()) // 0-indexed

  const periodoInicio = buildPeriodoInicio(selectedYear, selectedMonth)
  const periodoLabel = `${MONTH_NAMES[selectedMonth]} ${selectedYear}`

  // Fetch contrato activo
  const { data: contrato } = useQuery({
    queryKey: ['contrato-activo'],
    queryFn: async () => {
      const { data, error } = await getContratoActivo()
      if (error) throw error
      return data
    },
  })

  useEffect(() => {
    if (contrato?.id) setContratoId(contrato.id)
  }, [contrato])

  // ICEO data hooks
  const {
    data: iceoPeriodo,
    isLoading: loadingPeriodo,
    error: errorPeriodo,
  } = useICEOPeriodo(contratoId, undefined, periodoInicio)

  const {
    data: historico,
    isLoading: loadingHistorico,
  } = useICEOHistorico(contratoId, undefined, 6)

  const {
    data: mediciones,
    isLoading: loadingMediciones,
  } = useMedicionesKPI(contratoId, undefined, periodoInicio)

  const {
    data: bloqueantes,
    isLoading: loadingBloqueantes,
  } = useBloqueantesStatus(contratoId, undefined, periodoInicio)

  const { data: definiciones } = useKPIDefiniciones()

  const calcularICEOMutation = useCalcularICEO()

  const isLoading = loadingPeriodo || loadingMediciones || !contratoId

  // Build KPI list joined with definiciones
  const kpis = useMemo(() => {
    if (!mediciones || !definiciones) return []
    return mediciones.map((m: any) => {
      const def = m.kpi ?? definiciones.find((d: any) => d.id === m.kpi_id)
      return {
        id: m.id,
        area: def?.area ?? '',
        codigo: def?.codigo ?? '',
        nombre: def?.nombre ?? '',
        valorMedido: m.valor_medido ?? 0,
        meta: def?.meta ?? 0,
        cumplimiento: m.porcentaje_cumplimiento ?? 0,
        puntaje: m.puntaje ?? 0,
        peso: def?.peso ?? 0,
        ponderado: m.valor_ponderado ?? 0,
        bloqueante: def?.es_bloqueante ?? false,
      }
    })
  }, [mediciones, definiciones])

  // Build area structures from the periodo
  const areas = useMemo(() => {
    if (!iceoPeriodo) return []
    return areaKeys.map((ak) => ({
      id: ak.key,
      nombre: areaLabels[ak.area] ?? ak.area,
      area: ak.area,
      puntaje: (iceoPeriodo[ak.field] as number) ?? 0,
      peso: (iceoPeriodo[ak.pesoField] as number) ?? 0,
    }))
  }, [iceoPeriodo])

  // Map area enums to A/B/C
  const areaEnumToKey: Record<string, string> = {
    administracion_combustibles: 'A',
    mantenimiento_fijos: 'B',
    mantenimiento_moviles: 'C',
  }

  // Top causas de caida
  const topCausas = useMemo(() => {
    return kpis
      .filter((k) => k.puntaje < 100 && k.peso > 0)
      .sort((a, b) => (a.ponderado / a.peso) - (b.ponderado / b.peso))
      .slice(0, 5)
  }, [kpis])

  // Build trend chart data from historico
  const trendData = useMemo(() => {
    if (!historico) return []
    return [...historico]
      .sort((a, b) => a.periodo_inicio.localeCompare(b.periodo_inicio))
      .map((h) => {
        const d = new Date(h.periodo_inicio)
        return {
          mes: SHORT_MONTHS[d.getMonth()],
          iceo: h.iceo_final,
        }
      })
  }, [historico])

  // Bloqueantes list
  const bloqueantesFormatted: { codigo: string; nombre: string; cumple: boolean }[] = useMemo(() => {
    if (!bloqueantes) return []
    return bloqueantes.map((b: any) => ({
      codigo: b.kpi?.codigo ?? '',
      nombre: b.kpi?.nombre ?? '',
      cumple: !b.bloqueante_activado,
    }))
  }, [bloqueantes])

  // Year options for selector
  const yearOptions = Array.from({ length: 5 }, (_, i) => now.getFullYear() - i)

  // Handle calcular ICEO
  function handleCalcularICEO() {
    if (!contratoId) return
    const periodoFin = new Date(selectedYear, selectedMonth + 1, 0)
    const periodoFinStr = `${periodoFin.getFullYear()}-${String(periodoFin.getMonth() + 1).padStart(2, '0')}-${String(periodoFin.getDate()).padStart(2, '0')}`

    calcularICEOMutation.mutate({
      contratoId,
      periodoInicio,
      periodoFin: periodoFinStr,
    })
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <h1 className="text-2xl font-bold text-gray-900">Dashboard ICEO</h1>

        <div className="flex items-center gap-2">
          {/* Period selector */}
          <div className="relative">
            <select
              value={selectedMonth}
              onChange={(e) => setSelectedMonth(Number(e.target.value))}
              className="h-10 appearance-none rounded-lg border border-gray-300 bg-white px-3 pr-8 text-sm focus:border-pillado-green-500 focus:outline-none focus:ring-2 focus:ring-pillado-green-500/20"
            >
              {MONTH_NAMES.map((m, i) => (
                <option key={i} value={i}>{m}</option>
              ))}
            </select>
            <ChevronDown className="pointer-events-none absolute right-2 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400" />
          </div>
          <div className="relative">
            <select
              value={selectedYear}
              onChange={(e) => setSelectedYear(Number(e.target.value))}
              className="h-10 appearance-none rounded-lg border border-gray-300 bg-white px-3 pr-8 text-sm focus:border-pillado-green-500 focus:outline-none focus:ring-2 focus:ring-pillado-green-500/20"
            >
              {yearOptions.map((y) => (
                <option key={y} value={y}>{y}</option>
              ))}
            </select>
            <ChevronDown className="pointer-events-none absolute right-2 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400" />
          </div>

          <Button
            variant="primary"
            size="sm"
            onClick={handleCalcularICEO}
            disabled={calcularICEOMutation.isPending || !contratoId}
            className="gap-1"
          >
            {calcularICEOMutation.isPending ? (
              <Spinner size="sm" />
            ) : (
              <Calculator className="h-4 w-4" />
            )}
            Calcular ICEO
          </Button>
        </div>
      </div>

      {/* Loading state */}
      {isLoading && (
        <div className="flex justify-center py-16">
          <Spinner size="lg" className="text-pillado-green-600" />
        </div>
      )}

      {/* No data state */}
      {!isLoading && !iceoPeriodo && !errorPeriodo && (
        <div className="py-16 text-center">
          <AlertTriangle className="mx-auto mb-4 h-12 w-12 text-gray-300" />
          <p className="text-lg font-medium text-gray-500">No hay datos ICEO para este periodo</p>
          <p className="mt-1 text-sm text-gray-400">
            Haga clic en "Calcular ICEO" para generar el resultado del periodo {periodoLabel}.
          </p>
        </div>
      )}

      {/* Error state */}
      {!isLoading && errorPeriodo && (
        <div className="py-16 text-center">
          <p className="text-lg font-medium text-red-500">Error al cargar datos ICEO</p>
          <p className="mt-1 text-sm text-gray-400">{(errorPeriodo as Error).message}</p>
        </div>
      )}

      {/* Main content - only shown when we have periodo data */}
      {!isLoading && iceoPeriodo && (
        <>
          {/* Hero section */}
          <Card>
            <CardContent className="flex flex-col items-center py-8">
              <p className="mb-2 text-sm font-medium text-gray-500">{periodoLabel}</p>
              <Gauge value={iceoPeriodo.iceo_final} size="xl" />
              <div className="mt-4 flex items-center gap-3">
                {iceoPeriodo.incentivo_habilitado ? (
                  <Badge variant="bueno" className="gap-1 px-4 py-1.5 text-sm">
                    <ShieldCheck className="h-4 w-4" />
                    Incentivo: Habilitado
                  </Badge>
                ) : (
                  <Badge variant="deficiente" className="gap-1 px-4 py-1.5 text-sm">
                    <Lock className="h-4 w-4" />
                    Incentivo: Bloqueado
                  </Badge>
                )}
              </div>
            </CardContent>
          </Card>

          {/* Area cards */}
          <div className="grid grid-cols-1 gap-4 md:grid-cols-3">
            {areas.map((area) => {
              const color = getAreaColor(area.puntaje)
              return (
                <Card key={area.id} className="overflow-hidden">
                  <CardContent className="p-4">
                    <div className="flex items-start justify-between">
                      <div>
                        <p className="text-xs font-semibold text-gray-400">Area {area.id}</p>
                        <p className="text-sm font-semibold text-gray-900">{area.nombre}</p>
                      </div>
                      <Gauge value={area.puntaje} size="md" />
                    </div>
                    <div className="mt-3">
                      <div className="h-2 w-full overflow-hidden rounded-full bg-gray-100">
                        <div
                          className="h-full rounded-full transition-all"
                          style={{
                            width: `${Math.min(area.puntaje, 100)}%`,
                            backgroundColor: color,
                          }}
                        />
                      </div>
                      <p className="mt-1 text-right text-xs font-semibold" style={{ color }}>
                        {area.puntaje.toFixed(1)} pts
                      </p>
                    </div>
                  </CardContent>
                </Card>
              )
            })}
          </div>

          {/* KPI detail tables (expandable per area) */}
          <div className="space-y-4">
            {areas.map((area) => {
              const areaKpis = kpis.filter((k) => areaEnumToKey[k.area] === area.id || k.codigo.startsWith(area.id))
              const isExpanded = expandedArea === area.id
              return (
                <Card key={area.id}>
                  <button
                    type="button"
                    onClick={() => setExpandedArea(isExpanded ? null : area.id)}
                    className="flex w-full items-center justify-between p-4 text-left"
                  >
                    <div className="flex items-center gap-3">
                      <div
                        className="flex h-8 w-8 items-center justify-center rounded-lg text-sm font-bold text-white"
                        style={{ backgroundColor: getAreaColor(area.puntaje) }}
                      >
                        {area.id}
                      </div>
                      <div>
                        <p className="text-sm font-semibold text-gray-900">{area.nombre}</p>
                        <p className="text-xs text-gray-500">
                          {areaKpis.length} KPIs — Puntaje: {area.puntaje.toFixed(1)}
                        </p>
                      </div>
                    </div>
                    {isExpanded ? (
                      <ChevronUp className="h-5 w-5 text-gray-400" />
                    ) : (
                      <ChevronDown className="h-5 w-5 text-gray-400" />
                    )}
                  </button>
                  {isExpanded && (
                    <div className="border-t border-gray-100">
                      {/* Desktop table */}
                      <div className="hidden overflow-x-auto md:block">
                        <Table>
                          <TableHeader>
                            <TableRow>
                              <TableHead>Codigo</TableHead>
                              <TableHead>KPI</TableHead>
                              <TableHead className="text-right">Medido</TableHead>
                              <TableHead className="text-right">Meta</TableHead>
                              <TableHead className="text-right">% Cumpl.</TableHead>
                              <TableHead className="text-right">Puntaje</TableHead>
                              <TableHead className="text-right">Peso</TableHead>
                              <TableHead className="text-right">Ponderado</TableHead>
                              <TableHead className="text-center">Bloq.</TableHead>
                            </TableRow>
                          </TableHeader>
                          <TableBody>
                            {areaKpis.map((kpi) => (
                              <TableRow key={kpi.id}>
                                <TableCell className="font-mono text-xs font-semibold">{kpi.codigo}</TableCell>
                                <TableCell className="text-sm">{kpi.nombre}</TableCell>
                                <TableCell className="text-right">{kpi.valorMedido}</TableCell>
                                <TableCell className="text-right">{kpi.meta}</TableCell>
                                <TableCell className="text-right">
                                  <span
                                    className={cn(
                                      'font-semibold',
                                      kpi.cumplimiento >= 100 ? 'text-green-600' : 'text-amber-600'
                                    )}
                                  >
                                    {formatPercent(kpi.cumplimiento)}
                                  </span>
                                </TableCell>
                                <TableCell className="text-right font-semibold">{kpi.puntaje}</TableCell>
                                <TableCell className="text-right text-xs text-gray-500">{kpi.peso}</TableCell>
                                <TableCell className="text-right font-semibold">{kpi.ponderado.toFixed(1)}</TableCell>
                                <TableCell className="text-center">
                                  {kpi.bloqueante && (
                                    <AlertTriangle className="mx-auto h-4 w-4 text-amber-500" />
                                  )}
                                </TableCell>
                              </TableRow>
                            ))}
                            {areaKpis.length === 0 && (
                              <TableRow>
                                <TableCell colSpan={9} className="py-4 text-center text-sm text-gray-400">
                                  Sin mediciones para este periodo
                                </TableCell>
                              </TableRow>
                            )}
                          </TableBody>
                        </Table>
                      </div>

                      {/* Mobile cards */}
                      <div className="space-y-2 p-4 md:hidden">
                        {areaKpis.map((kpi) => (
                          <div key={kpi.id} className="rounded-lg border border-gray-100 p-3">
                            <div className="flex items-start justify-between">
                              <div>
                                <p className="font-mono text-xs font-semibold text-gray-400">{kpi.codigo}</p>
                                <p className="text-sm font-medium text-gray-900">{kpi.nombre}</p>
                              </div>
                              {kpi.bloqueante && <AlertTriangle className="h-4 w-4 shrink-0 text-amber-500" />}
                            </div>
                            <div className="mt-2 grid grid-cols-4 gap-2 text-xs">
                              <div>
                                <p className="text-gray-400">Medido</p>
                                <p className="font-semibold">{kpi.valorMedido}</p>
                              </div>
                              <div>
                                <p className="text-gray-400">Meta</p>
                                <p className="font-semibold">{kpi.meta}</p>
                              </div>
                              <div>
                                <p className="text-gray-400">Cumpl.</p>
                                <p className={cn('font-semibold', kpi.cumplimiento >= 100 ? 'text-green-600' : 'text-amber-600')}>
                                  {formatPercent(kpi.cumplimiento)}
                                </p>
                              </div>
                              <div>
                                <p className="text-gray-400">Pond.</p>
                                <p className="font-semibold">{kpi.ponderado.toFixed(1)}</p>
                              </div>
                            </div>
                          </div>
                        ))}
                        {areaKpis.length === 0 && (
                          <p className="py-4 text-center text-sm text-gray-400">
                            Sin mediciones para este periodo
                          </p>
                        )}
                      </div>
                    </div>
                  )}
                </Card>
              )
            })}
          </div>

          {/* Trend chart */}
          <Card>
            <CardHeader>
              <CardTitle>Tendencia ICEO — Ultimos 6 Meses</CardTitle>
            </CardHeader>
            <CardContent>
              {loadingHistorico ? (
                <div className="flex h-64 items-center justify-center">
                  <Spinner size="lg" className="text-pillado-green-600" />
                </div>
              ) : trendData.length > 0 ? (
                <div className="h-64">
                  <ResponsiveContainer width="100%" height="100%">
                    <LineChart data={trendData} margin={{ top: 5, right: 20, left: 0, bottom: 5 }}>
                      <CartesianGrid strokeDasharray="3 3" stroke="#f3f4f6" />
                      <XAxis dataKey="mes" tick={{ fontSize: 12, fill: '#9ca3af' }} />
                      <YAxis domain={[80, 100]} tick={{ fontSize: 12, fill: '#9ca3af' }} />
                      <Tooltip
                        formatter={(value: number) => [`${value.toFixed(1)}`, 'ICEO']}
                        contentStyle={{ borderRadius: 12, border: '1px solid #e5e7eb' }}
                      />
                      <ReferenceLine y={95} stroke="#7C3AED" strokeDasharray="4 4" label={{ value: 'Excelencia', position: 'right', fontSize: 11, fill: '#7C3AED' }} />
                      <ReferenceLine y={85} stroke="#16A34A" strokeDasharray="4 4" label={{ value: 'Bueno', position: 'right', fontSize: 11, fill: '#16A34A' }} />
                      <Line
                        type="monotone"
                        dataKey="iceo"
                        stroke="#2D8B3D"
                        strokeWidth={3}
                        dot={{ r: 5, fill: '#2D8B3D' }}
                        activeDot={{ r: 7 }}
                      />
                    </LineChart>
                  </ResponsiveContainer>
                </div>
              ) : (
                <div className="flex h-64 items-center justify-center text-sm text-gray-400">
                  Sin datos historicos disponibles
                </div>
              )}
            </CardContent>
          </Card>

          {/* Top Causas de Caida */}
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <TrendingDown className="h-5 w-5 text-amber-500" />
                Top Causas de Caida
              </CardTitle>
            </CardHeader>
            <CardContent>
              <div className="space-y-3">
                {topCausas.map((kpi) => {
                  const perdida = kpi.peso - kpi.ponderado
                  return (
                    <div key={kpi.id} className="flex items-center justify-between rounded-lg border border-gray-100 p-3">
                      <div className="flex items-center gap-3">
                        <span className="font-mono text-xs font-bold text-gray-400">{kpi.codigo}</span>
                        <div>
                          <p className="text-sm font-medium text-gray-900">{kpi.nombre}</p>
                          <p className="text-xs text-gray-500">
                            Medido: {kpi.valorMedido} / Meta: {kpi.meta}
                          </p>
                        </div>
                      </div>
                      <div className="text-right">
                        <p className="text-sm font-bold text-red-600">-{perdida.toFixed(1)} pts</p>
                        <p className="text-xs text-gray-400">Puntaje: {kpi.puntaje}/100</p>
                      </div>
                    </div>
                  )
                })}
                {topCausas.length === 0 && (
                  <p className="py-4 text-center text-sm text-gray-400">
                    Todos los KPIs al 100% este mes
                  </p>
                )}
              </div>
            </CardContent>
          </Card>

          {/* Bloqueantes */}
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <AlertTriangle className="h-5 w-5 text-amber-500" />
                Estado de Bloqueantes
              </CardTitle>
            </CardHeader>
            <CardContent>
              {loadingBloqueantes ? (
                <div className="flex justify-center py-8">
                  <Spinner size="lg" className="text-pillado-green-600" />
                </div>
              ) : bloqueantesFormatted.length > 0 ? (
                <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
                  {bloqueantesFormatted.map((b) => (
                    <div
                      key={b.codigo}
                      className={cn(
                        'flex items-center gap-3 rounded-lg border p-3',
                        b.cumple ? 'border-green-200 bg-green-50' : 'border-red-200 bg-red-50'
                      )}
                    >
                      {b.cumple ? (
                        <CheckCircle2 className="h-5 w-5 shrink-0 text-green-600" />
                      ) : (
                        <XCircle className="h-5 w-5 shrink-0 text-red-600" />
                      )}
                      <div>
                        <p className="text-xs font-bold text-gray-500">{b.codigo}</p>
                        <p className="text-sm text-gray-900">{b.nombre}</p>
                      </div>
                    </div>
                  ))}
                </div>
              ) : (
                <p className="py-4 text-center text-sm text-gray-400">
                  Sin bloqueantes registrados para este periodo
                </p>
              )}
            </CardContent>
          </Card>
        </>
      )}
    </div>
  )
}
