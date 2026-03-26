'use client'

import { useState, useEffect } from 'react'
import Link from 'next/link'
import { useQuery } from '@tanstack/react-query'
import { Fuel, Truck, MapPin, Calendar, ChevronDown } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Spinner } from '@/components/ui/spinner'
import { EmptyState } from '@/components/ui/empty-state'
import { StatCard } from '@/components/ui/stat-card'
import { Input } from '@/components/ui/input'
import {
  Table,
  TableHeader,
  TableBody,
  TableRow,
  TableHead,
  TableCell,
} from '@/components/ui/table'
import { formatDate, formatDateTime } from '@/lib/utils'
import { getRutasDespacho, getAbastecimientos, getRutaStats } from '@/lib/services/abastecimiento'
import { getFaenas } from '@/lib/services/faenas'

// ---------------------------------------------------------------------------
// Filter options
// ---------------------------------------------------------------------------
const estadoOptions = [
  { value: '', label: 'Todos' },
  { value: 'programada', label: 'Programada' },
  { value: 'completada', label: 'Completada' },
  { value: 'incompleta', label: 'Incompleta' },
]

// ---------------------------------------------------------------------------
// Select helper (inline, same pattern as OT page)
// ---------------------------------------------------------------------------
function Select({
  label,
  value,
  onChange,
  options,
}: {
  label: string
  value: string
  onChange: (v: string) => void
  options: { value: string; label: string }[]
}) {
  return (
    <div className="w-full sm:w-auto">
      <label className="mb-1 block text-xs font-medium text-gray-500">{label}</label>
      <div className="relative">
        <select
          value={value}
          onChange={(e) => onChange(e.target.value)}
          className="h-10 w-full appearance-none rounded-lg border border-gray-300 bg-white px-3 pr-8 text-sm text-gray-700 focus:border-pillado-green-500 focus:outline-none focus:ring-2 focus:ring-pillado-green-500/20 sm:w-44"
        >
          {options.map((o) => (
            <option key={o.value} value={o.value}>
              {o.label}
            </option>
          ))}
        </select>
        <ChevronDown className="pointer-events-none absolute right-2 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400" />
      </div>
    </div>
  )
}

// ---------------------------------------------------------------------------
// Estado badge helper
// ---------------------------------------------------------------------------
function getEstadoBadge(estado: string) {
  const config: Record<string, { variant: string; label: string }> = {
    programada: { variant: 'bg-blue-100 text-blue-700', label: 'Programada' },
    completada: { variant: 'bg-green-100 text-green-700', label: 'Completada' },
    incompleta: { variant: 'bg-red-100 text-red-700', label: 'Incompleta' },
  }
  const c = config[estado] || { variant: 'bg-gray-100 text-gray-700', label: estado }
  return <Badge className={c.variant}>{c.label}</Badge>
}

// ---------------------------------------------------------------------------
// Ruta mobile card
// ---------------------------------------------------------------------------
function RutaMobileCard({ ruta }: { ruta: any }) {
  const progress = ruta.puntos_programados
    ? Math.round((ruta.puntos_completados || 0) / ruta.puntos_programados * 100)
    : 0

  return (
    <Card className="mb-3">
      <CardContent className="p-4">
        <div className="flex items-start justify-between">
          <div>
            <p className="text-sm font-bold text-gray-900">
              {ruta.fecha_programada ? formatDate(ruta.fecha_programada) : '—'}
            </p>
            <p className="text-xs text-gray-500">{ruta.faena?.nombre || '—'}</p>
          </div>
          {getEstadoBadge(ruta.estado)}
        </div>
        <div className="mt-3 grid grid-cols-2 gap-y-1 text-xs text-gray-600">
          <span>Activo: {ruta.activo?.nombre || ruta.activo?.codigo || '—'}</span>
          <span>Operador: {ruta.operador?.nombre_completo || '—'}</span>
          <span>Puntos: {ruta.puntos_completados || 0}/{ruta.puntos_programados || 0} ({progress}%)</span>
          <span>Km: {ruta.km_reales ?? '—'}/{ruta.km_programados ?? '—'}</span>
          <span>Litros: {ruta.litros_despachados ?? '—'}</span>
          {ruta.ot?.folio && (
            <Link href={`/dashboard/ordenes-trabajo/${ruta.ot_id}`} className="text-pillado-green-600 font-medium hover:underline">
              OT: {ruta.ot.folio}
            </Link>
          )}
        </div>
      </CardContent>
    </Card>
  )
}

// ---------------------------------------------------------------------------
// Abastecimiento mobile card
// ---------------------------------------------------------------------------
function AbastecimientoMobileCard({ item }: { item: any }) {
  const diff = (item.cantidad_real ?? 0) - (item.cantidad_programada ?? 0)
  const diffColor = diff === 0 ? 'text-green-600' : diff < 0 ? 'text-red-600' : 'text-green-600'

  return (
    <Card className="mb-3">
      <CardContent className="p-4">
        <div className="flex items-start justify-between">
          <div>
            <p className="text-sm font-bold text-gray-900">
              {item.producto?.nombre || '—'}
            </p>
            <p className="text-xs text-gray-500">
              {item.fecha_hora ? formatDateTime(item.fecha_hora) : '—'}
            </p>
          </div>
        </div>
        <div className="mt-3 grid grid-cols-2 gap-y-1 text-xs text-gray-600">
          <span>Programada: {item.cantidad_programada ?? '—'}</span>
          <span>Real: {item.cantidad_real ?? '—'}</span>
          <span className={diffColor}>Diferencia: {diff > 0 ? `+${diff}` : diff}</span>
          <span>Operador: {item.operador?.nombre_completo || '—'}</span>
          {item.ot?.folio && (
            <Link href={`/dashboard/ordenes-trabajo/${item.ot_id}`} className="text-pillado-green-600 font-medium hover:underline">
              OT: {item.ot.folio}
            </Link>
          )}
        </div>
      </CardContent>
    </Card>
  )
}

// ---------------------------------------------------------------------------
// Main page
// ---------------------------------------------------------------------------
export default function AbastecimientoPage() {
  const [activeTab, setActiveTab] = useState<'rutas' | 'abastecimientos'>('rutas')
  const [faenaFilter, setFaenaFilter] = useState('')
  const [estadoFilter, setEstadoFilter] = useState('')
  const [fechaDesde, setFechaDesde] = useState('')
  const [fechaHasta, setFechaHasta] = useState('')

  // Faenas for filter dropdown
  const [faenaOptions, setFaenaOptions] = useState<{ value: string; label: string }[]>([
    { value: '', label: 'Todas' },
  ])

  useEffect(() => {
    getFaenas().then(({ data }) => {
      if (data) {
        setFaenaOptions([
          { value: '', label: 'Todas' },
          ...data.map((f) => ({ value: f.id, label: f.nombre })),
        ])
      }
    })
  }, [])

  // Build filters
  const rutaFilters: Record<string, string> = {}
  if (faenaFilter) rutaFilters.faena_id = faenaFilter
  if (estadoFilter) rutaFilters.estado = estadoFilter
  if (fechaDesde) rutaFilters.fecha_desde = fechaDesde
  if (fechaHasta) rutaFilters.fecha_hasta = fechaHasta

  // Queries
  const { data: rutas, isLoading: loadingRutas, error: errorRutas } = useQuery({
    queryKey: ['rutas-despacho', rutaFilters],
    queryFn: async () => {
      const { data, error } = await getRutasDespacho(rutaFilters)
      if (error) throw error
      return data
    },
  })

  const { data: abastecimientos, isLoading: loadingAbast, error: errorAbast } = useQuery({
    queryKey: ['abastecimientos'],
    queryFn: async () => {
      const { data, error } = await getAbastecimientos()
      if (error) throw error
      return data
    },
  })

  const { data: stats } = useQuery({
    queryKey: ['ruta-stats', faenaFilter],
    queryFn: async () => {
      const { data, error } = await getRutaStats(faenaFilter || undefined)
      if (error) throw error
      return data
    },
  })

  const isLoading = activeTab === 'rutas' ? loadingRutas : loadingAbast
  const error = activeTab === 'rutas' ? errorRutas : errorAbast

  return (
    <div className="space-y-6">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Abastecimiento y Lubricacion</h1>
        <p className="mt-1 text-sm text-gray-500">
          Programacion de abastecimientos, rutas de despacho, control de volumen y cumplimiento.
        </p>
      </div>

      {/* Stats */}
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <StatCard
          title="Rutas Totales"
          value={stats?.total ?? 0}
          icon={Truck}
          color="blue"
        />
        <StatCard
          title="Programadas"
          value={stats?.programadas ?? 0}
          icon={Calendar}
          color="orange"
        />
        <StatCard
          title="Completadas"
          value={stats?.completadas ?? 0}
          icon={MapPin}
          color="green"
        />
        <StatCard
          title="Incompletas"
          value={stats?.incompletas ?? 0}
          icon={Fuel}
          color="red"
        />
      </div>

      {/* Tabs */}
      <div className="flex gap-1 rounded-lg bg-gray-100 p-1">
        <button
          onClick={() => setActiveTab('rutas')}
          className={`flex-1 rounded-md px-4 py-2 text-sm font-medium transition-colors ${
            activeTab === 'rutas'
              ? 'bg-white text-gray-900 shadow-sm'
              : 'text-gray-500 hover:text-gray-700'
          }`}
        >
          Rutas de Despacho
        </button>
        <button
          onClick={() => setActiveTab('abastecimientos')}
          className={`flex-1 rounded-md px-4 py-2 text-sm font-medium transition-colors ${
            activeTab === 'abastecimientos'
              ? 'bg-white text-gray-900 shadow-sm'
              : 'text-gray-500 hover:text-gray-700'
          }`}
        >
          Abastecimientos
        </button>
      </div>

      {/* Filters (only for Rutas tab) */}
      {activeTab === 'rutas' && (
        <Card>
          <CardContent className="p-4">
            <div className="flex flex-col gap-3 sm:flex-row sm:flex-wrap sm:items-end">
              <Select
                label="Faena"
                value={faenaFilter}
                onChange={setFaenaFilter}
                options={faenaOptions}
              />
              <Select
                label="Estado"
                value={estadoFilter}
                onChange={setEstadoFilter}
                options={estadoOptions}
              />
              <div className="w-full sm:w-auto">
                <Input
                  label="Fecha desde"
                  type="date"
                  value={fechaDesde}
                  onChange={(e) => setFechaDesde(e.target.value)}
                />
              </div>
              <div className="w-full sm:w-auto">
                <Input
                  label="Fecha hasta"
                  type="date"
                  value={fechaHasta}
                  onChange={(e) => setFechaHasta(e.target.value)}
                />
              </div>
            </div>
          </CardContent>
        </Card>
      )}

      {/* Loading */}
      {isLoading && (
        <div className="flex items-center justify-center py-12">
          <Spinner size="lg" className="text-pillado-green-500" />
        </div>
      )}

      {/* Error */}
      {error && (
        <div className="rounded-xl border border-red-200 bg-red-50 p-4 text-center text-sm text-red-700">
          Error al cargar datos. Intente nuevamente.
        </div>
      )}

      {/* Rutas de Despacho Tab */}
      {!isLoading && !error && activeTab === 'rutas' && (
        <>
          {(!rutas || rutas.length === 0) ? (
            <Card>
              <EmptyState
                icon={Truck}
                title="Sin rutas de despacho"
                description="No se encontraron rutas con los filtros seleccionados."
              />
            </Card>
          ) : (
            <>
              {/* Desktop table */}
              <Card className="hidden md:block">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Fecha Prog.</TableHead>
                      <TableHead>Faena</TableHead>
                      <TableHead>Activo</TableHead>
                      <TableHead>Progreso</TableHead>
                      <TableHead>Km Prog./Real</TableHead>
                      <TableHead>Litros</TableHead>
                      <TableHead>Estado</TableHead>
                      <TableHead>Operador</TableHead>
                      <TableHead>OT</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {rutas.map((ruta: any) => {
                      const progress = ruta.puntos_programados
                        ? Math.round((ruta.puntos_completados || 0) / ruta.puntos_programados * 100)
                        : 0
                      return (
                        <TableRow key={ruta.id}>
                          <TableCell className="font-medium">
                            {ruta.fecha_programada ? formatDate(ruta.fecha_programada) : '—'}
                          </TableCell>
                          <TableCell>{ruta.faena?.nombre || '—'}</TableCell>
                          <TableCell className="text-xs">
                            {ruta.activo?.nombre || ruta.activo?.codigo || '—'}
                          </TableCell>
                          <TableCell>
                            <div className="flex items-center gap-2">
                              <div className="h-2 w-20 rounded-full bg-gray-200">
                                <div
                                  className="h-2 rounded-full bg-pillado-green-500"
                                  style={{ width: `${progress}%` }}
                                />
                              </div>
                              <span className="text-xs text-gray-500">
                                {ruta.puntos_completados || 0}/{ruta.puntos_programados || 0}
                              </span>
                            </div>
                          </TableCell>
                          <TableCell className="text-xs">
                            {ruta.km_programados ?? '—'} / {ruta.km_reales ?? '—'}
                          </TableCell>
                          <TableCell className="font-medium">
                            {ruta.litros_despachados ?? '—'}
                          </TableCell>
                          <TableCell>{getEstadoBadge(ruta.estado)}</TableCell>
                          <TableCell className="text-xs">
                            {ruta.operador?.nombre_completo || '—'}
                          </TableCell>
                          <TableCell>
                            {ruta.ot?.folio ? (
                              <Link
                                href={`/dashboard/ordenes-trabajo/${ruta.ot_id}`}
                                className="text-sm text-pillado-green-600 font-medium hover:underline"
                              >
                                {ruta.ot.folio}
                              </Link>
                            ) : (
                              '—'
                            )}
                          </TableCell>
                        </TableRow>
                      )
                    })}
                  </TableBody>
                </Table>
              </Card>

              {/* Mobile cards */}
              <div className="md:hidden">
                {rutas.map((ruta: any) => (
                  <RutaMobileCard key={ruta.id} ruta={ruta} />
                ))}
              </div>
            </>
          )}
        </>
      )}

      {/* Abastecimientos Tab */}
      {!isLoading && !error && activeTab === 'abastecimientos' && (
        <>
          {(!abastecimientos || abastecimientos.length === 0) ? (
            <Card>
              <EmptyState
                icon={Fuel}
                title="Sin abastecimientos"
                description="No se encontraron registros de abastecimiento."
              />
            </Card>
          ) : (
            <>
              {/* Desktop table */}
              <Card className="hidden md:block">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Fecha/Hora</TableHead>
                      <TableHead>Producto</TableHead>
                      <TableHead>Cant. Programada</TableHead>
                      <TableHead>Cant. Real</TableHead>
                      <TableHead>Diferencia</TableHead>
                      <TableHead>Operador</TableHead>
                      <TableHead>OT</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {abastecimientos.map((item: any) => {
                      const diff = (item.cantidad_real ?? 0) - (item.cantidad_programada ?? 0)
                      const diffColor = diff === 0 ? 'text-green-600' : diff < 0 ? 'text-red-600' : 'text-green-600'
                      return (
                        <TableRow key={item.id}>
                          <TableCell className="text-xs">
                            {item.fecha_hora ? formatDateTime(item.fecha_hora) : '—'}
                          </TableCell>
                          <TableCell className="font-medium">
                            {item.producto?.nombre || '—'}
                          </TableCell>
                          <TableCell>{item.cantidad_programada ?? '—'}</TableCell>
                          <TableCell>{item.cantidad_real ?? '—'}</TableCell>
                          <TableCell className={`font-medium ${diffColor}`}>
                            {diff > 0 ? `+${diff}` : diff}
                          </TableCell>
                          <TableCell className="text-xs">
                            {item.operador?.nombre_completo || '—'}
                          </TableCell>
                          <TableCell>
                            {item.ot?.folio ? (
                              <Link
                                href={`/dashboard/ordenes-trabajo/${item.ot_id}`}
                                className="text-sm text-pillado-green-600 font-medium hover:underline"
                              >
                                {item.ot.folio}
                              </Link>
                            ) : (
                              '—'
                            )}
                          </TableCell>
                        </TableRow>
                      )
                    })}
                  </TableBody>
                </Table>
              </Card>

              {/* Mobile cards */}
              <div className="md:hidden">
                {abastecimientos.map((item: any) => (
                  <AbastecimientoMobileCard key={item.id} item={item} />
                ))}
              </div>
            </>
          )}
        </>
      )}
    </div>
  )
}
