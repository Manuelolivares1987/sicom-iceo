'use client'

import { useState, useMemo } from 'react'
import {
  Truck,
  Activity,
  AlertTriangle,
  CheckCircle2,
  BarChart3,
  Shield,
  RefreshCw,
} from 'lucide-react'
import {
  Tooltip,
  ResponsiveContainer,
  PieChart,
  Pie,
  Cell,
} from 'recharts'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Spinner } from '@/components/ui/spinner'
import { cn, todayISO } from '@/lib/utils'
import { useRequireAuth } from '@/hooks/use-require-auth'
import {
  useFlotaVehicular,
  useResumenDiario,
  useOEEFlota,
  useEjecutarVerificaciones,
  useAplicarEstadosAutomaticos,
} from '@/hooks/use-flota'
import { useAlertasNoLeidas } from '@/hooks/use-alertas'
import {
  ESTADO_DIARIO_COLORS,
  OEE_CLASSIFICATION_COLORS,
} from '@/lib/services/flota'
import { CambiarEstadoModal } from '@/components/flota/cambiar-estado-modal'

/* ─── Helpers ─────────────────────────────────────────── */

function formatPct(value: number | null | undefined): string {
  if (value == null) return '—'
  return `${value.toFixed(1)}%`
}

function getOEEColor(oee: number): string {
  if (oee >= 80) return 'text-green-600'
  if (oee >= 64) return 'text-blue-600'
  if (oee >= 50) return 'text-amber-600'
  return 'text-red-600'
}

function getOEEBgColor(oee: number): string {
  if (oee >= 80) return 'bg-green-50 border-green-200'
  if (oee >= 64) return 'bg-blue-50 border-blue-200'
  if (oee >= 50) return 'bg-amber-50 border-amber-200'
  return 'bg-red-50 border-red-200'
}

const PIE_COLORS = [
  '#16A34A', '#2563EB', '#0891B2', '#7C3AED',
  '#F59E0B', '#EA580C', '#DC2626', '#6B7280',
  '#059669', '#4F46E5',
]

/* ─── Page ────────────────────────────────────────────── */

export default function FlotaPage() {
  useRequireAuth()

  const today = new Date()
  const firstOfMonth = new Date(today.getFullYear(), today.getMonth(), 1)
  const [fechaInicio] = useState(
    `${firstOfMonth.getFullYear()}-${String(firstOfMonth.getMonth() + 1).padStart(2, '0')}-01`
  )
  const [fechaFin] = useState(todayISO())
  const [operacionFilter, setOperacionFilter] = useState<string>('')
  const [contratoFilter, setContratoFilter] = useState<string>('')

  const { data: flota, isLoading: loadingFlota } = useFlotaVehicular()
  const { isLoading: loadingResumen } = useResumenDiario(fechaInicio, fechaFin, operacionFilter || undefined)
  const { data: oeeTotal } = useOEEFlota(fechaInicio, fechaFin, undefined, undefined)
  const { data: oeeHoy } = useOEEFlota(fechaFin, fechaFin, undefined, undefined)
  const { data: oeeCoquimbo } = useOEEFlota(fechaInicio, fechaFin, undefined, 'Coquimbo')
  const { data: oeeCalama } = useOEEFlota(fechaInicio, fechaFin, undefined, 'Calama')
  const { data: alertas } = useAlertasNoLeidas()
  const ejecutarVerif = useEjecutarVerificaciones()
  const aplicarAuto = useAplicarEstadosAutomaticos()

  // ── Modal Cambiar Estado ──
  const [activoSeleccionado, setActivoSeleccionado] = useState<{
    id: string
    patente?: string | null
    codigo?: string | null
    nombre?: string | null
    estado_comercial?: string | null
    operacion?: string | null
    cliente_actual?: string | null
  } | null>(null)
  const [modalOpen, setModalOpen] = useState(false)

  // ── Filtros por pie charts ──
  const [filtroEstado, setFiltroEstado] = useState<string | null>(null)
  const [filtroEstadoOp, setFiltroEstadoOp] = useState<string | null>(null)

  const contratosDisponibles = useMemo(() => {
    if (!flota) return []
    const map = new Map<string, { id: string; codigo: string; nombre: string; cliente: string | null }>()
    flota.forEach((a: Record<string, unknown>) => {
      const c = a.contrato as { id?: string; codigo?: string; nombre?: string; cliente?: string } | null
      if (c?.id && !map.has(c.id)) {
        map.set(c.id, {
          id: c.id,
          codigo: c.codigo ?? '',
          nombre: c.nombre ?? '',
          cliente: c.cliente ?? null,
        })
      }
    })
    return Array.from(map.values()).sort((a, b) => a.codigo.localeCompare(b.codigo))
  }, [flota])

  const flotaFiltrada = useMemo(() => {
    if (!flota) return []
    return flota.filter((a: Record<string, unknown>) => {
      if (filtroEstado) {
        const eo = (a.estado as string) || 'sin_estado'
        if (filtroEstado === 'no_disponible') {
          if (eo === 'operativo') return false
        } else {
          // Solo filtro por estado_comercial entre equipos operativos.
          if (eo !== 'operativo') return false
          const ec = (a.estado_comercial as string) || 'sin_estado'
          if (ec !== filtroEstado) return false
        }
      }
      if (filtroEstadoOp) {
        const eo = (a.estado as string) || 'sin_estado'
        if (eo !== filtroEstadoOp) return false
      }
      if (contratoFilter) {
        const cid = (a.contrato as { id?: string } | null)?.id ?? (a.contrato_id as string) ?? ''
        if (contratoFilter === '__sin_contrato__') {
          if (cid) return false
        } else if (cid !== contratoFilter) {
          return false
        }
      }
      return true
    })
  }, [flota, filtroEstado, filtroEstadoOp, contratoFilter])

  const handleRowClick = (activo: Record<string, unknown>) => {
    setActivoSeleccionado({
      id: activo.id as string,
      patente: (activo.patente as string) ?? null,
      codigo: (activo.codigo as string) ?? null,
      nombre: (activo.nombre as string) ?? null,
      estado_comercial: (activo.estado_comercial as string) ?? null,
      operacion: (activo.operacion as string) ?? null,
      cliente_actual: (activo.cliente_actual as string) ?? null,
    })
    setModalOpen(true)
  }

  // ── Derived data ──

  const flotaStats = useMemo(() => {
    if (!flota) return null
    const total = flota.length
    const porEstado: Record<string, number> = {}
    const porEstadoOp: Record<string, number> = {}
    const porOperacion: Record<string, number> = {}
    const porTipo: Record<string, number> = {}
    let noDisponibles = 0

    flota.forEach((a: Record<string, unknown>) => {
      const eo = (a.estado as string) || 'sin_estado'
      porEstadoOp[eo] = (porEstadoOp[eo] || 0) + 1
      const op = (a.operacion as string) || 'Sin asignar'
      porOperacion[op] = (porOperacion[op] || 0) + 1
      const tipo = (a.tipo as string) || 'otro'
      porTipo[tipo] = (porTipo[tipo] || 0) + 1

      // El breakdown comercial se calcula SOLO sobre equipos operativos.
      // Los que estan en taller/mantencion/fuera se agrupan en "No disponible"
      // para que el cambio de estado se refleje visualmente en el pie.
      if (eo === 'operativo') {
        const ec = (a.estado_comercial as string) || 'sin_estado'
        porEstado[ec] = (porEstado[ec] || 0) + 1
      } else {
        noDisponibles += 1
      }
    })

    return { total, porEstado, porEstadoOp, porOperacion, porTipo, noDisponibles }
  }, [flota])

  const alertasNormativas = useMemo(() => {
    if (!alertas) return []
    const tiposNormativos = ['antiguedad_vehiculo', 'semep_vencido', 'fatiga_conductor',
       'rt_por_vencer', 'hermeticidad_vencida', 'sec_no_vigente',
       'disponibilidad_vencida']
    return alertas.filter((a) => tiposNormativos.includes(a.tipo))
  }, [alertas])

  const estadoComercialPie = useMemo(() => {
    if (!flotaStats) return []
    const labels: Record<string, string> = {
      arrendado: 'Arrendado',
      disponible: 'Disponible',
      uso_interno: 'Uso Interno',
      leasing: 'Leasing',
      en_recepcion: 'En Recepción',
      en_venta: 'En Venta',
      comprometido: 'Comprometido',
      sin_estado: 'Sin Estado',
    }
    const base = Object.entries(flotaStats.porEstado).map(([key, value]) => ({
      key,
      name: labels[key] || key,
      value,
    }))
    if (flotaStats.noDisponibles > 0) {
      base.push({
        key: 'no_disponible',
        name: 'No disponible (taller/mantencion)',
        value: flotaStats.noDisponibles,
      })
    }
    return base
  }, [flotaStats])

  const estadoOperativoPie = useMemo(() => {
    if (!flotaStats) return []
    const labels: Record<string, string> = {
      operativo: 'Operativo',
      en_mantenimiento: 'En Mantención',
      fuera_servicio: 'Fuera de Servicio',
      dado_baja: 'Dado de Baja',
      en_transito: 'En Tránsito',
      sin_estado: 'Sin Estado',
    }
    const opColors = ['#16A34A', '#F59E0B', '#DC2626', '#6B7280', '#2563EB', '#9CA3AF']
    return Object.entries(flotaStats.porEstadoOp).map(([key, value], i) => ({
      key,
      name: labels[key] || key,
      value,
      color: opColors[i % opColors.length],
    }))
  }, [flotaStats])

  const isLoading = loadingFlota || loadingResumen

  if (isLoading) {
    return (
      <div className="flex items-center justify-center h-64">
        <Spinner className="h-8 w-8" />
      </div>
    )
  }

  return (
    <div className="space-y-6">
      {/* ── Header ── */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-gray-900 flex items-center gap-2">
            <Truck className="h-7 w-7 text-blue-600" />
            Panel de Control de Flota
          </h1>
          <p className="text-sm text-gray-500 mt-1">
            {fechaInicio} al {fechaFin} | {flotaStats?.total ?? 0} equipos
          </p>
        </div>
        <div className="flex gap-2">
          <select
            className="rounded-md border border-gray-300 px-3 py-2 text-sm"
            value={operacionFilter}
            onChange={(e) => setOperacionFilter(e.target.value)}
          >
            <option value="">Todas las operaciones</option>
            <option value="Coquimbo">Coquimbo</option>
            <option value="Calama">Calama</option>
          </select>
          <select
            className="rounded-md border border-gray-300 px-3 py-2 text-sm max-w-[240px]"
            value={contratoFilter}
            onChange={(e) => setContratoFilter(e.target.value)}
            title="Filtrar equipos por contrato"
          >
            <option value="">Todos los contratos</option>
            <option value="__sin_contrato__">Sin contrato</option>
            {contratosDisponibles.map((c) => (
              <option key={c.id} value={c.id}>
                {c.codigo} — {c.cliente || c.nombre}
              </option>
            ))}
          </select>
          <button
            className="rounded-md bg-emerald-600 px-4 py-2 text-sm font-medium text-white hover:bg-emerald-700 flex items-center gap-1"
            onClick={() => aplicarAuto.mutate(undefined)}
            disabled={aplicarAuto.isPending}
            title="Aplica la cascada de fuentes automáticas (OTs, certificaciones, contratos) a los activos sin override manual"
          >
            <RefreshCw className={cn('h-4 w-4', aplicarAuto.isPending && 'animate-spin')} />
            {aplicarAuto.isPending ? 'Recalculando...' : 'Recalcular Estados'}
          </button>
          <button
            className="rounded-md bg-blue-600 px-4 py-2 text-sm font-medium text-white hover:bg-blue-700 flex items-center gap-1"
            onClick={() => ejecutarVerif.mutate()}
            disabled={ejecutarVerif.isPending}
          >
            <Shield className="h-4 w-4" />
            {ejecutarVerif.isPending ? 'Verificando...' : 'Verificar Normativa'}
          </button>
        </div>
      </div>

      {/* ── Alertas Normativas ── */}
      {alertasNormativas.length > 0 && (
        <Card className="border-red-200 bg-red-50">
          <CardHeader className="pb-2">
            <CardTitle className="text-red-700 flex items-center gap-2 text-base">
              <AlertTriangle className="h-5 w-5" />
              Alertas Normativas Activas ({alertasNormativas.length})
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="space-y-2 max-h-40 overflow-y-auto">
              {alertasNormativas.slice(0, 5).map((alerta, i) => (
                <div key={i} className="flex items-start gap-2 text-sm">
                  <span className={cn(
                    'inline-block px-2 py-0.5 rounded text-xs font-medium',
                    alerta.severidad === 'critical' ? 'bg-red-200 text-red-800' : 'bg-amber-200 text-amber-800'
                  )}>
                    {alerta.severidad === 'critical' ? 'BLOQUEO' : 'ALERTA'}
                  </span>
                  <span className="text-gray-700">{alerta.titulo}</span>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      )}

      {/* ── OEE Dashboard ── */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
        {[
          { label: 'OEE Hoy', data: oeeHoy, hint: 'Impacto en tiempo real' },
          { label: 'OEE Mes', data: oeeTotal, hint: 'Rolling mensual' },
          { label: 'OEE Coquimbo', data: oeeCoquimbo, hint: '' },
          { label: 'OEE Calama', data: oeeCalama, hint: '' },
        ].map(({ label, data: oee, hint }) => (
          <Card key={label} className={cn('border', oee ? getOEEBgColor(oee.oee_promedio) : 'bg-gray-50')}>
            <CardHeader className="pb-2">
              <CardTitle className="text-sm font-medium text-gray-600 flex items-center gap-2">
                <Activity className="h-4 w-4" />
                {label}
              </CardTitle>
              {hint && <p className="text-[10px] text-gray-400">{hint}</p>}
            </CardHeader>
            <CardContent>
              {oee ? (
                <div className="space-y-3">
                  <div className="flex items-baseline gap-2">
                    <span className={cn('text-3xl font-bold', getOEEColor(oee.oee_promedio))}>
                      {formatPct(oee.oee_promedio)}
                    </span>
                    <span className={cn('text-sm font-medium', OEE_CLASSIFICATION_COLORS[oee.clasificacion] || '')}>
                      {oee.clasificacion}
                    </span>
                  </div>
                  <div className="grid grid-cols-3 gap-2 text-center">
                    <div>
                      <div className="text-xs text-gray-500">Disponib.</div>
                      <div className="font-semibold text-sm">{formatPct(oee.disponibilidad_promedio)}</div>
                    </div>
                    <div>
                      <div className="text-xs text-gray-500">Utilización</div>
                      <div className="font-semibold text-sm">{formatPct(oee.utilizacion_promedio)}</div>
                    </div>
                    <div>
                      <div className="text-xs text-gray-500">Calidad</div>
                      <div className="font-semibold text-sm">{formatPct(oee.calidad_promedio)}</div>
                    </div>
                  </div>
                  <div className="text-xs text-gray-500 text-center">
                    {oee.total_equipos} equipos
                  </div>
                </div>
              ) : (
                <p className="text-sm text-gray-400">Sin datos de estado diario</p>
              )}
            </CardContent>
          </Card>
        ))}
      </div>

      {/* ── Estado de Flota (Pie Comercial + Pie Operativo + Stats) ── */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
        {/* Pie Chart Estado Comercial */}
        <Card>
          <CardHeader>
            <CardTitle className="text-base flex items-center gap-2 justify-between">
              <span className="flex items-center gap-2">
                <BarChart3 className="h-5 w-5 text-gray-600" />
                Estado Comercial de la Flota
              </span>
              {filtroEstado && (
                <button
                  className="text-xs font-medium text-blue-600 hover:underline"
                  onClick={() => setFiltroEstado(null)}
                >
                  Limpiar filtro
                </button>
              )}
            </CardTitle>
          </CardHeader>
          <CardContent>
            {estadoComercialPie.length > 0 ? (
              <>
                <div className="h-64">
                  <ResponsiveContainer width="100%" height="100%">
                    <PieChart>
                      <Pie
                        data={estadoComercialPie}
                        cx="50%"
                        cy="50%"
                        innerRadius={50}
                        outerRadius={90}
                        paddingAngle={2}
                        dataKey="value"
                        label={({ name, value }) => `${name}: ${value}`}
                        onClick={(data: any) => {
                          if (data?.key) {
                            setFiltroEstado(filtroEstado === data.key ? null : data.key)
                          }
                        }}
                        cursor="pointer"
                      >
                        {estadoComercialPie.map((entry, index) => (
                          <Cell
                            key={index}
                            fill={entry.key === 'no_disponible' ? '#9CA3AF' : PIE_COLORS[index % PIE_COLORS.length]}
                            opacity={filtroEstado && filtroEstado !== entry.key ? 0.3 : 1}
                          />
                        ))}
                      </Pie>
                      <Tooltip />
                    </PieChart>
                  </ResponsiveContainer>
                </div>
                <p className="mt-2 text-xs text-gray-500 text-center">
                  Click en un segmento para filtrar la tabla
                </p>
              </>
            ) : (
              <p className="text-sm text-gray-400">Sin datos</p>
            )}
          </CardContent>
        </Card>

        {/* KPIs rápidos */}
        <Card>
          <CardHeader>
            <CardTitle className="text-base flex items-center gap-2">
              <CheckCircle2 className="h-5 w-5 text-gray-600" />
              Indicadores Clave
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="grid grid-cols-2 gap-4">
              {flotaStats && (
                <>
                  <div className="rounded-lg bg-green-50 p-4 text-center">
                    <div className="text-2xl font-bold text-green-700">
                      {flotaStats.porEstado.arrendado || 0}
                    </div>
                    <div className="text-xs text-green-600">Arrendados</div>
                    <div className="text-xs text-gray-500 mt-1">
                      {flotaStats.total > 0
                        ? `${((flotaStats.porEstado.arrendado || 0) / flotaStats.total * 100).toFixed(1)}%`
                        : '0%'}
                    </div>
                  </div>
                  <div className="rounded-lg bg-blue-50 p-4 text-center">
                    <div className="text-2xl font-bold text-blue-700">
                      {flotaStats.porEstado.disponible || 0}
                    </div>
                    <div className="text-xs text-blue-600">Disponibles</div>
                    <div className="text-xs text-gray-500 mt-1">
                      {flotaStats.total > 0
                        ? `${((flotaStats.porEstado.disponible || 0) / flotaStats.total * 100).toFixed(1)}%`
                        : '0%'}
                    </div>
                  </div>
                  <div className="rounded-lg bg-cyan-50 p-4 text-center">
                    <div className="text-2xl font-bold text-cyan-700">
                      {flotaStats.porEstado.uso_interno || 0}
                    </div>
                    <div className="text-xs text-cyan-600">Uso Interno</div>
                  </div>
                  <div className="rounded-lg bg-indigo-50 p-4 text-center">
                    <div className="text-2xl font-bold text-indigo-700">
                      {flotaStats.porEstado.leasing || 0}
                    </div>
                    <div className="text-xs text-indigo-600">Leasing</div>
                  </div>
                  <div className="rounded-lg bg-amber-50 p-4 text-center col-span-2">
                    <div className="text-lg font-bold text-amber-700">
                      Pérdida Comercial: {flotaStats.porEstado.disponible || 0} equipos sin arriendo
                    </div>
                    <div className="text-xs text-amber-600">
                      {flotaStats.total > 0
                        ? `${((flotaStats.porEstado.disponible || 0) / flotaStats.total * 100).toFixed(1)}% de la flota ociosa`
                        : ''}
                    </div>
                  </div>
                </>
              )}
            </div>
          </CardContent>
        </Card>

        {/* Pie Chart Estado Operativo */}
        <Card>
          <CardHeader>
            <CardTitle className="text-base flex items-center gap-2 justify-between">
              <span className="flex items-center gap-2">
                <Activity className="h-5 w-5 text-gray-600" />
                Estado Operativo
              </span>
              {filtroEstadoOp && (
                <button
                  className="text-xs font-medium text-blue-600 hover:underline"
                  onClick={() => setFiltroEstadoOp(null)}
                >
                  Limpiar filtro
                </button>
              )}
            </CardTitle>
          </CardHeader>
          <CardContent>
            {estadoOperativoPie.length > 0 ? (
              <>
                <div className="h-64">
                  <ResponsiveContainer width="100%" height="100%">
                    <PieChart>
                      <Pie
                        data={estadoOperativoPie}
                        cx="50%"
                        cy="50%"
                        innerRadius={50}
                        outerRadius={90}
                        paddingAngle={2}
                        dataKey="value"
                        label={({ name, value }) => `${name}: ${value}`}
                        onClick={(data: any) => {
                          if (data?.key) {
                            setFiltroEstadoOp(filtroEstadoOp === data.key ? null : data.key)
                          }
                        }}
                        cursor="pointer"
                      >
                        {estadoOperativoPie.map((entry, index) => (
                          <Cell
                            key={index}
                            fill={entry.color}
                            opacity={filtroEstadoOp && filtroEstadoOp !== entry.key ? 0.3 : 1}
                          />
                        ))}
                      </Pie>
                      <Tooltip />
                    </PieChart>
                  </ResponsiveContainer>
                </div>
                <p className="mt-2 text-xs text-gray-500 text-center">
                  Click en un segmento para filtrar la tabla
                </p>
              </>
            ) : (
              <p className="text-sm text-gray-400">Sin datos</p>
            )}
          </CardContent>
        </Card>
      </div>

      {/* ── Tabla de Flota ── */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base flex items-center gap-2 justify-between">
            <span className="flex items-center gap-2">
              <Truck className="h-5 w-5 text-gray-600" />
              Maestro de Flota ({flotaFiltrada.length} {(filtroEstado || filtroEstadoOp || contratoFilter) ? `de ${flotaStats?.total ?? 0}` : 'equipos'})
            </span>
            {(filtroEstado || filtroEstadoOp || contratoFilter) && (
              <button
                className="text-xs font-medium text-blue-600 hover:underline"
                onClick={() => { setFiltroEstado(null); setFiltroEstadoOp(null); setContratoFilter('') }}
              >
                Ver todos
              </button>
            )}
          </CardTitle>
        </CardHeader>
        <CardContent className="overflow-x-auto">
          <table className="w-full text-xs">
            <thead>
              <tr className="border-b text-left text-gray-500 uppercase">
                <th className="px-2 py-2">PPU</th>
                <th className="px-2 py-2">CECO</th>
                <th className="px-2 py-2">Equipo</th>
                <th className="px-2 py-2">Marca/Modelo</th>
                <th className="px-2 py-2">Ano</th>
                <th className="px-2 py-2">Estado</th>
                <th className="px-2 py-2">Comercial</th>
                <th className="px-2 py-2">Operacion</th>
                <th className="px-2 py-2">Contrato</th>
                <th className="px-2 py-2">Cliente</th>
                <th className="px-2 py-2">Ubicacion</th>
              </tr>
            </thead>
            <tbody>
              {flotaFiltrada.map((activo: Record<string, unknown>) => {
                const modelo = activo.modelo as Record<string, unknown> | null
                const marca = modelo?.marca as Record<string, unknown> | null
                const ec = activo.estado_comercial as string
                const ecColor = ec ? (ESTADO_DIARIO_COLORS[ec.charAt(0).toUpperCase()] || 'bg-gray-200 text-gray-700') : 'bg-gray-200 text-gray-700'

                return (
                  <tr
                    key={activo.id as string}
                    className="border-b hover:bg-blue-50 cursor-pointer transition-colors"
                    onClick={() => handleRowClick(activo)}
                    title="Click para cambiar estado del equipo"
                  >
                    <td className="px-2 py-2 font-mono font-semibold">{activo.patente as string || activo.codigo as string}</td>
                    <td className="px-2 py-2 text-gray-500">{activo.centro_costo as string}</td>
                    <td className="px-2 py-2">{activo.nombre as string}</td>
                    <td className="px-2 py-2">
                      {marca?.nombre as string} {modelo?.nombre as string}
                    </td>
                    <td className="px-2 py-2">{activo.anio_fabricacion as number}</td>
                    <td className="px-2 py-2">
                      <span className={cn(
                        'inline-block px-2 py-0.5 rounded text-xs',
                        activo.estado === 'operativo' ? 'bg-green-100 text-green-700' :
                        activo.estado === 'en_mantenimiento' ? 'bg-amber-100 text-amber-700' :
                        activo.estado === 'fuera_servicio' ? 'bg-red-100 text-red-700' :
                        'bg-gray-100 text-gray-700'
                      )}>
                        {activo.estado as string}
                      </span>
                    </td>
                    <td className="px-2 py-2">
                      {ec && (
                        <span className={cn('inline-block px-2 py-0.5 rounded text-xs', ecColor)}>
                          {ec.replace(/_/g, ' ')}
                        </span>
                      )}
                    </td>
                    <td className="px-2 py-2">{activo.operacion as string}</td>
                    <td className="px-2 py-2 text-gray-600 font-mono">
                      {(activo.contrato as { codigo?: string } | null)?.codigo ?? '—'}
                    </td>
                    <td className="px-2 py-2 text-gray-600">{activo.cliente_actual as string}</td>
                    <td className="px-2 py-2 text-gray-500 max-w-[150px] truncate">{activo.ubicacion_actual as string}</td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </CardContent>
      </Card>

      {/* ── Leyenda OEE ── */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base">OEE Flota = Disponibilidad x Utilizacion x Calidad</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4 text-sm">
            <div className="p-3 rounded bg-blue-50">
              <h4 className="font-semibold text-blue-700">Disponibilidad Mecanica</h4>
              <p className="text-gray-600 mt-1">
                (Dias periodo - Dias mantencion/F.Servicio) / Dias periodo.
                Fuente: MTBF / (MTBF + MTTR). Meta: &ge; 90%
              </p>
            </div>
            <div className="p-3 rounded bg-green-50">
              <h4 className="font-semibold text-green-700">Utilizacion Operativa</h4>
              <p className="text-gray-600 mt-1">
                Dias productivos (A+U+L) / Dias disponibles.
                Mide cuanto se usa la flota cuando esta lista. Meta: &ge; 75%
              </p>
            </div>
            <div className="p-3 rounded bg-purple-50">
              <h4 className="font-semibold text-purple-700">Calidad de Servicio</h4>
              <p className="text-gray-600 mt-1">
                (Servicios - No conformidades) / Servicios totales.
                Mide entregas a tiempo, sin incidentes. Meta: &ge; 95%
              </p>
            </div>
          </div>
          <div className="mt-4 flex gap-4 text-xs text-gray-500">
            <span className="flex items-center gap-1"><span className="w-3 h-3 rounded bg-green-500 inline-block" /> &ge;80% Clase Mundial</span>
            <span className="flex items-center gap-1"><span className="w-3 h-3 rounded bg-blue-500 inline-block" /> &ge;64% Bueno</span>
            <span className="flex items-center gap-1"><span className="w-3 h-3 rounded bg-amber-500 inline-block" /> &ge;50% Aceptable</span>
            <span className="flex items-center gap-1"><span className="w-3 h-3 rounded bg-red-500 inline-block" /> &lt;50% Deficiente</span>
          </div>
        </CardContent>
      </Card>

      {/* ── Modal Cambiar Estado del Equipo ── */}
      <CambiarEstadoModal
        open={modalOpen}
        onClose={() => setModalOpen(false)}
        activo={activoSeleccionado}
      />
    </div>
  )
}
