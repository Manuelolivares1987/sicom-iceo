'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import {
  Gauge,
  ClipboardList,
  CheckCircle2,
  DollarSign,
  AlertTriangle,
  CalendarClock,
  TrendingUp,
  TrendingDown,
} from 'lucide-react'
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  PieChart,
  Pie,
  Cell,
  BarChart,
  Bar,
  Legend,
} from 'recharts'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Spinner } from '@/components/ui/spinner'
import { cn } from '@/lib/utils'
import { getICEOColor, getICEOLabel } from '@/lib/utils'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useAuth } from '@/contexts/auth-context'
import { ExecutiveDashboard } from '@/components/dashboard/executive-dashboard'
import { CommercialDashboard } from '@/components/dashboard/commercial-dashboard'
import { useOTsStats } from '@/hooks/use-ordenes-trabajo'
import { useValorizacionTotal } from '@/hooks/use-inventario'
import { useICEOHistorico, useICEOPeriodo } from '@/hooks/use-kpi-iceo'
import { useAlertasNoLeidas } from '@/hooks/use-alertas'
import { useCertificacionesVencidas, useProximosVencimientos } from '@/hooks/use-certificaciones'
import { useQuery } from '@tanstack/react-query'
import { getContratoActivo } from '@/lib/services/contratos'

/* ─── Helper: color map for OT estados ────────────────────── */
const estadoColorMap: Record<string, string> = {
  en_ejecucion: '#F59E0B',
  asignada: '#2563EB',
  ejecutada_ok: '#16A34A',
  ejecutada_con_observaciones: '#059669',
  pausada: '#E87722',
  no_ejecutada: '#DC2626',
  creada: '#8B5CF6',
  cancelada: '#6B7280',
}

const estadoLabelMap: Record<string, string> = {
  en_ejecucion: 'En Ejecucion',
  asignada: 'Asignadas',
  ejecutada_ok: 'Ejecutadas OK',
  ejecutada_con_observaciones: 'Ejecutadas c/ Obs.',
  pausada: 'Pausadas',
  no_ejecutada: 'Sin Ejecutar',
  creada: 'Creadas',
  cancelada: 'Canceladas',
}

const semaforoColors: Record<string, string> = {
  vencido: 'bg-red-500',
  por_vencer: 'bg-yellow-400',
  vigente: 'bg-green-500',
}

const semaforoBorder: Record<string, string> = {
  vencido: 'border-l-red-500',
  por_vencer: 'border-l-yellow-400',
  vigente: 'border-l-green-500',
}

function formatCurrency(value: number): string {
  if (value >= 1_000_000) return `$${(value / 1_000_000).toFixed(1)}M`
  if (value >= 1_000) return `$${(value / 1_000).toFixed(0)}K`
  return `$${value.toFixed(0)}`
}

/* ─── Component ───────────────────────────────────────────────── */
// Roles que ven el Dashboard Ejecutivo (Control Tower)
const ROLES_EJECUTIVOS = new Set([
  'administrador',
  'gerencia',
  'subgerente_operaciones',
  'jefe_operaciones',
])

export default function DashboardPage() {
  const { loading: authLoading } = useRequireAuth()
  const { perfil } = useAuth()

  // Router por rol:
  //   - Ejecutivos -> Control Tower.
  //   - Comercial  -> Panel Comercial (equipos rentables, pendientes, clientes).
  //   - Otros      -> dashboard legacy (resto de este archivo).
  if (!authLoading && perfil?.rol) {
    if (ROLES_EJECUTIVOS.has(perfil.rol)) {
      return <ExecutiveDashboard />
    }
    if (perfil.rol === 'comercial') {
      return <CommercialDashboard />
    }
  }

  // Fetch active contrato for ICEO hooks
  const { data: contrato } = useQuery({
    queryKey: ['contrato-activo'],
    queryFn: async () => {
      const { data, error } = await getContratoActivo()
      if (error) throw error
      return data
    },
  })
  const contratoId = contrato?.id ?? ''

  // ── Data hooks ──
  const otsStats = useOTsStats()
  const valorizacion = useValorizacionTotal()
  const iceoPeriodo = useICEOPeriodo(contratoId)
  const iceoHistorico = useICEOHistorico(contratoId)
  const alertasNoLeidas = useAlertasNoLeidas()
  const certVencidas = useCertificacionesVencidas()
  const proximosVenc = useProximosVencimientos(60)

  // ── Derived data ──
  const iceoValue = iceoPeriodo.data?.iceo_final ?? null
  const iceoTrendData = (iceoHistorico.data ?? [])
    .slice()
    .sort((a, b) => a.periodo_inicio.localeCompare(b.periodo_inicio))
    .map((p) => {
      const date = new Date(p.periodo_inicio)
      const mes = date.toLocaleDateString('es-CL', { month: 'short' })
      return { mes: mes.charAt(0).toUpperCase() + mes.slice(1), valor: p.iceo_final }
    })

  // Previous period delta for ICEO
  const iceoDelta =
    iceoTrendData.length >= 2
      ? iceoTrendData[iceoTrendData.length - 1].valor -
        iceoTrendData[iceoTrendData.length - 2].valor
      : null

  // OTs stats
  const statsData = otsStats.data as Record<string, number> | null | undefined
  const totalOTs = statsData
    ? Object.values(statsData).reduce((a, b) => a + b, 0)
    : 0
  const otsActivas = statsData
    ? (statsData.en_ejecucion ?? 0) +
      (statsData.asignada ?? 0) +
      (statsData.pausada ?? 0) +
      (statsData.creada ?? 0)
    : 0
  const otsVencidas = statsData?.no_ejecutada ?? 0

  // OTs pie chart data
  const otsPorEstado = statsData
    ? Object.entries(statsData)
        .filter(([, v]) => v > 0)
        .map(([estado, value]) => ({
          key: estado,
          name: estadoLabelMap[estado] ?? estado,
          value,
          color: estadoColorMap[estado] ?? '#6B7280',
        }))
    : []

  // ── Filtro interactivo desde pie chart ──
  const [filtroOtEstado, setFiltroOtEstado] = useState<string | null>(null)
  const router = useRouter()

  // Inventory valuation
  const inventarioTotal = valorizacion.data as number | null | undefined

  // Certificaciones for document expiry section
  const certDocs = (certVencidas.data ?? []).concat(proximosVenc.data ?? [])
  // De-duplicate by id
  const certDocsUnique = Array.from(
    new Map(certDocs.map((c) => [c.id, c])).values()
  ).slice(0, 6)

  // Global loading
  const isLoading =
    authLoading ||
    otsStats.isLoading ||
    valorizacion.isLoading ||
    iceoPeriodo.isLoading

  if (authLoading) {
    return (
      <div className="flex h-96 items-center justify-center">
        <Spinner size="lg" className="text-gray-400" />
      </div>
    )
  }

  return (
    <div className="space-y-6">
      {/* Page title */}
      <div>
        <h1 className="text-2xl font-bold text-gray-900">
          Panel de Control Gerencial
        </h1>
        <p className="text-sm text-gray-500">
          Resumen operacional al {new Date().toLocaleDateString('es-CL', { day: 'numeric', month: 'long', year: 'numeric' })}
        </p>
      </div>

      {/* ─── Row 1: Stat Cards ──────────────────────────────── */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        {/* ICEO */}
        <Card className="relative overflow-hidden">
          <CardContent className="p-6">
            {iceoPeriodo.isLoading ? (
              <div className="flex h-20 items-center justify-center">
                <Spinner size="md" className="text-purple-400" />
              </div>
            ) : iceoPeriodo.isError ? (
              <p className="text-sm text-red-500">Error al cargar ICEO</p>
            ) : iceoValue !== null ? (
              <>
                <div className="flex items-start justify-between">
                  <div>
                    <p className="text-sm font-medium text-gray-500">
                      ICEO del Periodo
                    </p>
                    <p className={cn('mt-1 text-3xl font-bold', getICEOColor(iceoValue))}>
                      {iceoValue.toFixed(1)}
                    </p>
                    {iceoDelta !== null && (
                      <span
                        className={cn(
                          'mt-1 inline-flex items-center gap-1 text-xs font-medium',
                          iceoDelta >= 0 ? 'text-green-600' : 'text-red-500'
                        )}
                      >
                        {iceoDelta >= 0 ? (
                          <TrendingUp className="h-3 w-3" />
                        ) : (
                          <TrendingDown className="h-3 w-3" />
                        )}
                        {iceoDelta >= 0 ? '+' : ''}
                        {iceoDelta.toFixed(1)} vs mes anterior
                      </span>
                    )}
                  </div>
                  <div className="rounded-lg bg-purple-50 p-2.5">
                    <Gauge className="h-6 w-6 text-purple-600" />
                  </div>
                </div>
                <div className="mt-3 h-1.5 w-full overflow-hidden rounded-full bg-gray-100">
                  <div
                    className="h-full rounded-full bg-green-500 transition-all"
                    style={{ width: `${Math.min(iceoValue, 100)}%` }}
                  />
                </div>
                <p className="mt-1 text-right text-[10px] text-gray-400">
                  {getICEOLabel(iceoValue)}
                </p>
              </>
            ) : (
              <div className="flex items-start justify-between">
                <div>
                  <p className="text-sm font-medium text-gray-500">ICEO del Periodo</p>
                  <p className="mt-1 text-lg text-gray-400">Sin datos</p>
                </div>
                <div className="rounded-lg bg-purple-50 p-2.5">
                  <Gauge className="h-6 w-6 text-purple-600" />
                </div>
              </div>
            )}
          </CardContent>
        </Card>

        {/* OTs Activas */}
        <Card className="cursor-pointer hover:shadow-md transition-shadow" onClick={() => router.push('/dashboard/ordenes-trabajo')}>
          <CardContent className="p-6">
            {otsStats.isLoading ? (
              <div className="flex h-20 items-center justify-center">
                <Spinner size="md" className="text-blue-400" />
              </div>
            ) : otsStats.isError ? (
              <p className="text-sm text-red-500">Error al cargar OTs</p>
            ) : (
              <div className="flex items-start justify-between">
                <div>
                  <p className="text-sm font-medium text-gray-500">OTs Activas</p>
                  <p className="mt-1 text-3xl font-bold text-gray-900">{otsActivas}</p>
                  {otsVencidas > 0 && (
                    <span className="mt-1 inline-flex items-center gap-1 text-xs font-medium text-amber-600">
                      <AlertTriangle className="h-3 w-3" />
                      {otsVencidas} no ejecutadas
                    </span>
                  )}
                </div>
                <div className="rounded-lg bg-blue-50 p-2.5">
                  <ClipboardList className="h-6 w-6 text-blue-600" />
                </div>
              </div>
            )}
          </CardContent>
        </Card>

        {/* Cumplimiento PM — use ICEO area data if available */}
        <Card>
          <CardContent className="p-6">
            {iceoPeriodo.isLoading ? (
              <div className="flex h-20 items-center justify-center">
                <Spinner size="md" className="text-green-400" />
              </div>
            ) : (
              <div className="flex items-start justify-between">
                <div>
                  <p className="text-sm font-medium text-gray-500">
                    Total OTs
                  </p>
                  <p className="mt-1 text-3xl font-bold text-gray-900">
                    {totalOTs}
                  </p>
                  {statsData && (statsData.ejecutada_ok ?? 0) > 0 && (
                    <span className="mt-1 inline-flex items-center gap-1 text-xs font-medium text-green-600">
                      <CheckCircle2 className="h-3 w-3" />
                      {statsData.ejecutada_ok} ejecutadas OK
                    </span>
                  )}
                </div>
                <div className="rounded-lg bg-green-50 p-2.5">
                  <CheckCircle2 className="h-6 w-6 text-green-600" />
                </div>
              </div>
            )}
          </CardContent>
        </Card>

        {/* Inventario Valorizado */}
        <Card className="cursor-pointer hover:shadow-md transition-shadow" onClick={() => router.push('/dashboard/inventario')}>
          <CardContent className="p-6">
            {valorizacion.isLoading ? (
              <div className="flex h-20 items-center justify-center">
                <Spinner size="md" className="text-amber-400" />
              </div>
            ) : valorizacion.isError ? (
              <p className="text-sm text-red-500">Error al cargar inventario</p>
            ) : (
              <div className="flex items-start justify-between">
                <div>
                  <p className="text-sm font-medium text-gray-500">
                    Inventario Valorizado
                  </p>
                  <p className="mt-1 text-3xl font-bold text-gray-900">
                    {inventarioTotal != null
                      ? formatCurrency(inventarioTotal)
                      : 'Sin datos'}
                  </p>
                </div>
                <div className="rounded-lg bg-amber-50 p-2.5">
                  <DollarSign className="h-6 w-6 text-amber-600" />
                </div>
              </div>
            )}
          </CardContent>
        </Card>
      </div>

      {/* ─── Row 2: Charts ──────────────────────────────────── */}
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        {/* ICEO Tendencia */}
        <Card>
          <CardHeader>
            <CardTitle>ICEO Tendencia — Ultimos 6 Meses</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="h-[280px]">
              {iceoHistorico.isLoading ? (
                <div className="flex h-full items-center justify-center">
                  <Spinner size="lg" className="text-gray-300" />
                </div>
              ) : iceoHistorico.isError ? (
                <div className="flex h-full items-center justify-center">
                  <p className="text-sm text-red-500">Error al cargar tendencia ICEO</p>
                </div>
              ) : iceoTrendData.length === 0 ? (
                <div className="flex h-full items-center justify-center">
                  <p className="text-sm text-gray-400">Sin datos de tendencia</p>
                </div>
              ) : (
                <ResponsiveContainer width="100%" height="100%">
                  <LineChart data={iceoTrendData}>
                    <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" />
                    <XAxis
                      dataKey="mes"
                      tick={{ fontSize: 12, fill: '#6b7280' }}
                    />
                    <YAxis
                      domain={[85, 100]}
                      tick={{ fontSize: 12, fill: '#6b7280' }}
                    />
                    <Tooltip
                      contentStyle={{
                        borderRadius: '8px',
                        border: '1px solid #e5e7eb',
                        fontSize: '13px',
                      }}
                      formatter={(value: number) => [value.toFixed(1), 'ICEO']}
                    />
                    <Line
                      type="monotone"
                      dataKey="valor"
                      stroke="#2D8B3D"
                      strokeWidth={2.5}
                      dot={{ fill: '#2D8B3D', r: 4 }}
                      activeDot={{ r: 6 }}
                    />
                  </LineChart>
                </ResponsiveContainer>
              )}
            </div>
          </CardContent>
        </Card>

        {/* OTs por Estado */}
        <Card>
          <CardHeader>
            <div className="flex items-center justify-between">
              <CardTitle>OTs por Estado</CardTitle>
              {filtroOtEstado && (
                <button className="text-xs font-medium text-blue-600 hover:underline" onClick={() => setFiltroOtEstado(null)}>
                  Limpiar filtro
                </button>
              )}
            </div>
          </CardHeader>
          <CardContent>
            <div className="flex h-[280px] items-center gap-4">
              {otsStats.isLoading ? (
                <div className="flex h-full w-full items-center justify-center">
                  <Spinner size="lg" className="text-gray-300" />
                </div>
              ) : otsStats.isError ? (
                <div className="flex h-full w-full items-center justify-center">
                  <p className="text-sm text-red-500">Error al cargar OTs</p>
                </div>
              ) : otsPorEstado.length === 0 ? (
                <div className="flex h-full w-full items-center justify-center">
                  <p className="text-sm text-gray-400">Sin ordenes de trabajo</p>
                </div>
              ) : (
                <>
                  <div className="h-full flex-1">
                    <ResponsiveContainer width="100%" height="100%">
                      <PieChart>
                        <Pie
                          data={otsPorEstado}
                          cx="50%"
                          cy="50%"
                          innerRadius={60}
                          outerRadius={95}
                          paddingAngle={3}
                          dataKey="value"
                          onClick={(data: any) => {
                            if (data?.key) {
                              setFiltroOtEstado(filtroOtEstado === data.key ? null : data.key)
                            }
                          }}
                          cursor="pointer"
                        >
                          {otsPorEstado.map((entry, index) => (
                            <Cell
                              key={index}
                              fill={entry.color}
                              opacity={filtroOtEstado && filtroOtEstado !== entry.key ? 0.3 : 1}
                            />
                          ))}
                        </Pie>
                        <Tooltip
                          contentStyle={{
                            borderRadius: '8px',
                            border: '1px solid #e5e7eb',
                            fontSize: '13px',
                          }}
                        />
                      </PieChart>
                    </ResponsiveContainer>
                  </div>
                  <div className="space-y-2">
                    {otsPorEstado.map((item) => (
                      <div
                        key={item.name}
                        className={cn(
                          'flex items-center gap-2 text-sm cursor-pointer rounded px-2 py-1 transition-colors hover:bg-gray-100',
                          filtroOtEstado === item.key && 'bg-gray-100 ring-1 ring-gray-300'
                        )}
                        onClick={() => setFiltroOtEstado(filtroOtEstado === item.key ? null : item.key)}
                      >
                        <div
                          className="h-3 w-3 rounded-full"
                          style={{ backgroundColor: item.color, opacity: filtroOtEstado && filtroOtEstado !== item.key ? 0.3 : 1 }}
                        />
                        <span className="text-gray-600">{item.name}</span>
                        <span className="font-semibold text-gray-900">
                          {item.value}
                        </span>
                      </div>
                    ))}
                    <p className="text-xs text-gray-400 mt-1">Click para filtrar</p>
                  </div>
                </>
              )}
            </div>
          </CardContent>
        </Card>
      </div>

      {/* ─── Row 3: Alerts ──────────────────────────────────── */}
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        {/* Alertas No Leidas */}
        <Card className="border-l-4 border-l-red-500">
          <CardHeader>
            <div className="flex items-center gap-2">
              <AlertTriangle className="h-5 w-5 text-red-500" />
              <CardTitle className="text-red-700">
                Alertas Pendientes
              </CardTitle>
            </div>
          </CardHeader>
          <CardContent>
            {alertasNoLeidas.isLoading ? (
              <div className="flex h-32 items-center justify-center">
                <Spinner size="md" className="text-red-300" />
              </div>
            ) : alertasNoLeidas.isError ? (
              <p className="text-sm text-red-500">Error al cargar alertas</p>
            ) : !alertasNoLeidas.data || alertasNoLeidas.data.length === 0 ? (
              <p className="py-4 text-center text-sm text-gray-400">
                Sin alertas pendientes
              </p>
            ) : (
              <div className="space-y-3">
                {alertasNoLeidas.data.slice(0, 5).map((alerta) => (
                  <div
                    key={alerta.id}
                    className={cn(
                      'flex items-center justify-between rounded-lg px-4 py-3',
                      alerta.severidad === 'critical'
                        ? 'bg-red-50'
                        : alerta.severidad === 'warning'
                          ? 'bg-amber-50'
                          : 'bg-blue-50'
                    )}
                  >
                    <div>
                      <p
                        className={cn(
                          'text-sm font-semibold',
                          alerta.severidad === 'critical'
                            ? 'text-red-900'
                            : alerta.severidad === 'warning'
                              ? 'text-amber-900'
                              : 'text-blue-900'
                        )}
                      >
                        {alerta.titulo}
                      </p>
                      {alerta.mensaje && (
                        <p className="text-xs text-gray-600">
                          {alerta.mensaje.length > 80
                            ? alerta.mensaje.slice(0, 80) + '...'
                            : alerta.mensaje}
                        </p>
                      )}
                    </div>
                    <div className="text-right">
                      <span
                        className={cn(
                          'inline-block rounded-full px-2.5 py-0.5 text-xs font-medium',
                          alerta.severidad === 'critical'
                            ? 'bg-red-100 text-red-700'
                            : alerta.severidad === 'warning'
                              ? 'bg-amber-100 text-amber-700'
                              : 'bg-blue-100 text-blue-700'
                        )}
                      >
                        {alerta.tipo}
                      </span>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>

        {/* Vencimientos Documentales */}
        <Card>
          <CardHeader>
            <div className="flex items-center gap-2">
              <CalendarClock className="h-5 w-5 text-amber-500" />
              <CardTitle>Proximos Vencimientos Documentales</CardTitle>
            </div>
          </CardHeader>
          <CardContent>
            {certVencidas.isLoading ? (
              <div className="flex h-32 items-center justify-center">
                <Spinner size="md" className="text-amber-300" />
              </div>
            ) : certVencidas.isError ? (
              <p className="text-sm text-red-500">Error al cargar certificaciones</p>
            ) : certDocsUnique.length === 0 ? (
              <p className="py-4 text-center text-sm text-gray-400">
                Sin vencimientos proximos
              </p>
            ) : (
              <div className="space-y-3">
                {certDocsUnique.map((cert) => {
                  const estadoKey = cert.estado ?? 'vigente'
                  return (
                    <div
                      key={cert.id}
                      className={cn(
                        'flex items-center justify-between rounded-lg border-l-4 bg-gray-50 px-4 py-3',
                        semaforoBorder[estadoKey] ?? 'border-l-gray-300'
                      )}
                    >
                      <div className="flex items-center gap-3">
                        <div
                          className={cn(
                            'h-2.5 w-2.5 rounded-full',
                            semaforoColors[estadoKey] ?? 'bg-gray-400'
                          )}
                        />
                        <p className="text-sm font-medium text-gray-900">
                          {cert.tipo} — {cert.numero_certificado ?? 'S/N'}
                        </p>
                      </div>
                      <p className="shrink-0 text-xs font-medium text-gray-500">
                        {new Date(cert.fecha_vencimiento).toLocaleDateString('es-CL', {
                          day: '2-digit',
                          month: 'short',
                          year: 'numeric',
                        })}
                      </p>
                    </div>
                  )
                })}
              </div>
            )}
          </CardContent>
        </Card>
      </div>

      {/* ─── Row 4: ICEO Areas Breakdown ──────────────────────── */}
      {iceoPeriodo.data && (
        <div className="grid grid-cols-1 gap-4 md:grid-cols-3">
          {[
            { area: 'Area A', puntaje: iceoPeriodo.data.puntaje_area_a, peso: iceoPeriodo.data.peso_area_a },
            { area: 'Area B', puntaje: iceoPeriodo.data.puntaje_area_b, peso: iceoPeriodo.data.peso_area_b },
            { area: 'Area C', puntaje: iceoPeriodo.data.puntaje_area_c, peso: iceoPeriodo.data.peso_area_c },
          ].map((area) => (
            <Card key={area.area}>
              <CardHeader>
                <CardTitle className="text-sm">{area.area}</CardTitle>
              </CardHeader>
              <CardContent>
                <div className="mb-4 grid grid-cols-2 gap-2 text-center">
                  <div>
                    <p className="text-xs text-gray-500">Puntaje</p>
                    <p
                      className={cn(
                        'text-lg font-bold',
                        (area.puntaje ?? 0) >= 95
                          ? 'text-green-600'
                          : (area.puntaje ?? 0) >= 85
                            ? 'text-amber-600'
                            : 'text-red-600'
                      )}
                    >
                      {area.puntaje != null ? area.puntaje.toFixed(1) : '—'}
                    </p>
                  </div>
                  <div>
                    <p className="text-xs text-gray-500">Peso</p>
                    <p className="text-lg font-bold text-gray-900">
                      {(area.peso * 100).toFixed(0)}%
                    </p>
                  </div>
                </div>
                <div className="h-2 w-full overflow-hidden rounded-full bg-gray-100">
                  <div
                    className={cn(
                      'h-full rounded-full transition-all',
                      (area.puntaje ?? 0) >= 95
                        ? 'bg-green-500'
                        : (area.puntaje ?? 0) >= 85
                          ? 'bg-amber-500'
                          : 'bg-red-500'
                    )}
                    style={{ width: `${Math.min(area.puntaje ?? 0, 100)}%` }}
                  />
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  )
}
