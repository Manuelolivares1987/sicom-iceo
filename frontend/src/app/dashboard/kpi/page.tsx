'use client'

import { useState, useMemo } from 'react'
import { useQuery } from '@tanstack/react-query'
import { BarChart3, Lock, RefreshCw, TrendingUp, TrendingDown, ChevronDown, ChevronUp } from 'lucide-react'
import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
} from 'recharts'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Spinner } from '@/components/ui/spinner'
import { EmptyState } from '@/components/ui/empty-state'
import { Button } from '@/components/ui/button'
import { Select } from '@/components/ui/select'
import {
  Table,
  TableHeader,
  TableBody,
  TableRow,
  TableHead,
  TableCell,
} from '@/components/ui/table'
import { getContratoActivo } from '@/lib/services/contratos'
import { useKPIDefiniciones, useMedicionesKPI, useCalcularKPIs } from '@/hooks/use-kpi-iceo'
import { formatPercent } from '@/lib/utils'
import type { AreaKPI } from '@/types/database'

function useContratoActivo() {
  return useQuery({
    queryKey: ['contrato-activo'],
    queryFn: async () => {
      const { data, error } = await getContratoActivo()
      if (error) throw error
      return data
    },
  })
}

const AREA_CONFIG: Record<AreaKPI, { title: string; prefix: string }> = {
  administracion_combustibles: {
    title: 'Administracion de Combustibles y Lubricantes',
    prefix: 'A',
  },
  mantenimiento_fijos: {
    title: 'Mantenimiento Puntos Fijos',
    prefix: 'B',
  },
  mantenimiento_moviles: {
    title: 'Mantenimiento Puntos Moviles',
    prefix: 'C',
  },
}

const MONTHS = [
  { value: '01', label: 'Enero' },
  { value: '02', label: 'Febrero' },
  { value: '03', label: 'Marzo' },
  { value: '04', label: 'Abril' },
  { value: '05', label: 'Mayo' },
  { value: '06', label: 'Junio' },
  { value: '07', label: 'Julio' },
  { value: '08', label: 'Agosto' },
  { value: '09', label: 'Septiembre' },
  { value: '10', label: 'Octubre' },
  { value: '11', label: 'Noviembre' },
  { value: '12', label: 'Diciembre' },
]

function getCumplimientoColor(value: number): string {
  if (value >= 95) return 'text-green-600'
  if (value >= 80) return 'text-yellow-600'
  return 'text-red-600'
}

function getCumplimientoBg(value: number): string {
  if (value >= 95) return 'bg-green-100 text-green-700'
  if (value >= 80) return 'bg-yellow-100 text-yellow-700'
  return 'bg-red-100 text-red-700'
}

function getBarColor(value: number): string {
  if (value >= 95) return '#16a34a'
  if (value >= 80) return '#ca8a04'
  return '#dc2626'
}

interface KPIAreaSectionProps {
  area: AreaKPI
  definiciones: Array<{
    id: string
    codigo: string
    nombre: string
    area: string
    peso: number
    meta_minima: number
    meta_objetivo: number
    es_bloqueante: boolean
    activo: boolean
    formula_descripcion?: string | null
  }>
  mediciones: Array<{
    id: string
    kpi_id: string
    valor_medido: number
    porcentaje_cumplimiento: number | null
    puntaje: number
    valor_ponderado: number
    bloqueante_activado: boolean
    kpi?: {
      id: string
      codigo: string
      nombre: string
      area: string
      peso: number
      meta_minima: number
      meta_objetivo: number
      es_bloqueante: boolean
    }
  }>
}

function KPIAreaSection({ area, definiciones, mediciones }: KPIAreaSectionProps) {
  const [expanded, setExpanded] = useState(true)
  const config = AREA_CONFIG[area]

  const areaDefiniciones = definiciones.filter((d) => d.area === area)

  // Merge definitions with mediciones
  const rows = areaDefiniciones.map((def) => {
    const medicion = mediciones.find((m) => m.kpi_id === def.id || m.kpi?.id === def.id)
    return {
      codigo: def.codigo,
      nombre: def.nombre,
      peso: def.peso,
      es_bloqueante: def.es_bloqueante,
      meta: def.meta_objetivo,
      valor_medido: medicion?.valor_medido ?? null,
      porcentaje_cumplimiento: medicion?.porcentaje_cumplimiento ?? null,
      puntaje: medicion?.puntaje ?? 0,
      valor_ponderado: medicion?.valor_ponderado ?? 0,
      bloqueante_activado: medicion?.bloqueante_activado ?? false,
    }
  })

  const chartData = rows.map((r) => ({
    name: r.codigo,
    puntaje: r.puntaje,
    fill: getBarColor(r.porcentaje_cumplimiento ?? 0),
  }))

  const totalPonderado = rows.reduce((acc, r) => acc + r.valor_ponderado, 0)

  return (
    <Card>
      <CardHeader
        className="cursor-pointer select-none"
        onClick={() => setExpanded(!expanded)}
      >
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-pillado-green-50">
              <span className="text-sm font-bold text-pillado-green-600">{config.prefix}</span>
            </div>
            <div>
              <CardTitle>{config.title}</CardTitle>
              <p className="text-sm text-gray-500 mt-0.5">
                {areaDefiniciones.length} indicadores | Puntaje ponderado: {totalPonderado.toFixed(2)}
              </p>
            </div>
          </div>
          {expanded ? (
            <ChevronUp className="h-5 w-5 text-gray-400" />
          ) : (
            <ChevronDown className="h-5 w-5 text-gray-400" />
          )}
        </div>
      </CardHeader>

      {expanded && (
        <CardContent>
          {/* KPI Table */}
          <Table striped>
            <TableHeader>
              <TableRow>
                <TableHead>Codigo</TableHead>
                <TableHead>Nombre</TableHead>
                <TableHead className="text-right">Valor Medido</TableHead>
                <TableHead className="text-right">Meta</TableHead>
                <TableHead className="text-right">% Cumplimiento</TableHead>
                <TableHead className="text-right">Puntaje</TableHead>
                <TableHead className="text-right">Peso</TableHead>
                <TableHead className="text-right">Ponderado</TableHead>
                <TableHead className="text-center">Bloq.</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {rows.length === 0 ? (
                <TableRow>
                  <TableCell colSpan={9} className="text-center text-gray-400 py-8">
                    Sin definiciones de KPI para esta area
                  </TableCell>
                </TableRow>
              ) : (
                rows.map((row) => (
                  <TableRow key={row.codigo}>
                    <TableCell className="font-medium">{row.codigo}</TableCell>
                    <TableCell className="max-w-[200px]">
                      <span className="text-sm">{row.nombre}</span>
                    </TableCell>
                    <TableCell className="text-right font-mono">
                      {row.valor_medido !== null ? row.valor_medido.toFixed(2) : '-'}
                    </TableCell>
                    <TableCell className="text-right font-mono">
                      {row.meta.toFixed(2)}
                    </TableCell>
                    <TableCell className="text-right">
                      {row.porcentaje_cumplimiento !== null ? (
                        <span
                          className={`inline-flex items-center rounded-full px-2 py-0.5 text-xs font-semibold ${getCumplimientoBg(row.porcentaje_cumplimiento)}`}
                        >
                          {formatPercent(row.porcentaje_cumplimiento)}
                        </span>
                      ) : (
                        <span className="text-gray-400">-</span>
                      )}
                    </TableCell>
                    <TableCell className="text-right font-mono">
                      {row.puntaje.toFixed(1)}
                    </TableCell>
                    <TableCell className="text-right font-mono text-gray-500">
                      {formatPercent(row.peso * 100, 0)}
                    </TableCell>
                    <TableCell className="text-right font-mono font-medium">
                      {row.valor_ponderado.toFixed(2)}
                    </TableCell>
                    <TableCell className="text-center">
                      {row.es_bloqueante ? (
                        <Lock
                          className={`h-4 w-4 mx-auto ${
                            row.bloqueante_activado ? 'text-red-500' : 'text-gray-400'
                          }`}
                        />
                      ) : (
                        <span className="text-gray-300">-</span>
                      )}
                    </TableCell>
                  </TableRow>
                ))
              )}
            </TableBody>
          </Table>

          {/* Bar Chart */}
          {rows.length > 0 && (
            <div className="mt-6">
              <h4 className="text-sm font-medium text-gray-700 mb-3">Puntajes por KPI</h4>
              <div className="h-56">
                <ResponsiveContainer width="100%" height="100%">
                  <BarChart data={chartData} margin={{ top: 5, right: 20, left: 0, bottom: 5 }}>
                    <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" />
                    <XAxis dataKey="name" tick={{ fontSize: 12 }} />
                    <YAxis domain={[0, 100]} tick={{ fontSize: 12 }} />
                    <Tooltip
                      formatter={(value: number) => [value.toFixed(1), 'Puntaje']}
                      contentStyle={{
                        borderRadius: '8px',
                        border: '1px solid #e5e7eb',
                        fontSize: '13px',
                      }}
                    />
                    <Bar
                      dataKey="puntaje"
                      radius={[4, 4, 0, 0]}
                      fill="#16a34a"
                    />
                  </BarChart>
                </ResponsiveContainer>
              </div>
            </div>
          )}
        </CardContent>
      )}
    </Card>
  )
}

export default function KpiPage() {
  const now = new Date()
  const [month, setMonth] = useState(String(now.getMonth() + 1).padStart(2, '0'))
  const [year, setYear] = useState(String(now.getFullYear()))

  const periodoInicio = `${year}-${month}-01`
  // Last day of month
  const lastDay = new Date(Number(year), Number(month), 0).getDate()
  const periodoFin = `${year}-${month}-${String(lastDay).padStart(2, '0')}`

  const { data: contrato, isLoading: loadingContrato } = useContratoActivo()
  const contratoId = contrato?.id ?? ''

  const { data: definiciones, isLoading: loadingDefs } = useKPIDefiniciones()
  const { data: mediciones, isLoading: loadingMediciones } = useMedicionesKPI(
    contratoId,
    undefined,
    periodoInicio
  )

  const calcularMutation = useCalcularKPIs()

  const yearOptions = useMemo(() => {
    const currentYear = now.getFullYear()
    const years = []
    for (let y = currentYear - 2; y <= currentYear + 1; y++) {
      years.push({ value: String(y), label: String(y) })
    }
    return years
  }, [])

  const isLoading = loadingContrato || loadingDefs || loadingMediciones

  const handleCalcular = () => {
    if (!contratoId) return
    calcularMutation.mutate({
      contratoId,
      periodoInicio,
      periodoFin,
    })
  }

  if (loadingContrato) {
    return (
      <div className="flex items-center justify-center min-h-[60vh]">
        <Spinner size="lg" />
      </div>
    )
  }

  if (!contrato) {
    return (
      <div className="flex items-center justify-center min-h-[60vh]">
        <EmptyState
          icon={BarChart3}
          title="Sin contrato activo"
          description="Se necesita un contrato activo para visualizar los KPIs."
        />
      </div>
    )
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">KPI Detalle</h1>
          <p className="text-sm text-gray-500 mt-1">
            Indicadores clave de rendimiento por area - {contrato.nombre}
          </p>
        </div>
      </div>

      {/* Period selector */}
      <Card>
        <CardContent className="p-4">
          <div className="flex flex-col sm:flex-row items-start sm:items-end gap-4">
            <Select
              label="Mes"
              value={month}
              onChange={(e) => setMonth(e.target.value)}
              options={MONTHS}
            />
            <Select
              label="Anio"
              value={year}
              onChange={(e) => setYear(e.target.value)}
              options={yearOptions}
            />
            <Button
              variant="primary"
              onClick={handleCalcular}
              loading={calcularMutation.isPending}
              className="shrink-0"
            >
              <RefreshCw className="h-4 w-4" />
              Calcular KPIs
            </Button>
          </div>
          {calcularMutation.isSuccess && (
            <p className="mt-2 text-sm text-green-600 flex items-center gap-1">
              <TrendingUp className="h-4 w-4" />
              KPIs calculados exitosamente
            </p>
          )}
          {calcularMutation.isError && (
            <p className="mt-2 text-sm text-red-600 flex items-center gap-1">
              <TrendingDown className="h-4 w-4" />
              Error al calcular KPIs: {(calcularMutation.error as Error)?.message ?? 'Error desconocido'}
            </p>
          )}
        </CardContent>
      </Card>

      {/* Loading state for definitions/mediciones */}
      {(loadingDefs || loadingMediciones) && (
        <div className="flex items-center justify-center py-12">
          <Spinner size="md" />
        </div>
      )}

      {/* KPI Sections */}
      {!loadingDefs && definiciones && (
        <div className="space-y-6">
          {(Object.keys(AREA_CONFIG) as AreaKPI[]).map((area) => (
            <KPIAreaSection
              key={area}
              area={area}
              definiciones={(definiciones as Array<{
                id: string
                codigo: string
                nombre: string
                area: string
                peso: number
                meta_minima: number
                meta_objetivo: number
                es_bloqueante: boolean
                activo: boolean
                formula_descripcion?: string | null
              }>) ?? []}
              mediciones={(mediciones as Array<{
                id: string
                kpi_id: string
                valor_medido: number
                porcentaje_cumplimiento: number | null
                puntaje: number
                valor_ponderado: number
                bloqueante_activado: boolean
                kpi?: {
                  id: string
                  codigo: string
                  nombre: string
                  area: string
                  peso: number
                  meta_minima: number
                  meta_objetivo: number
                  es_bloqueante: boolean
                }
              }>) ?? []}
            />
          ))}
        </div>
      )}
    </div>
  )
}
