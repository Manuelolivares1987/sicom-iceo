'use client'

import { useState, useEffect } from 'react'
import Link from 'next/link'
import { Fuel, Truck, MapPin, Calendar, ChevronDown, Plus } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { EmptyState } from '@/components/ui/empty-state'
import { StatCard } from '@/components/ui/stat-card'
import { Input } from '@/components/ui/input'
import { Modal, ModalFooter } from '@/components/ui/modal'
import {
  Table,
  TableHeader,
  TableBody,
  TableRow,
  TableHead,
  TableCell,
} from '@/components/ui/table'
import { formatDate, formatDateTime } from '@/lib/utils'
import { getFaenas } from '@/lib/services/faenas'
import { getProductos } from '@/lib/services/inventario'
import {
  useRutasDespacho,
  useAbastecimientos,
  useRutaStats,
  useCreateRuta,
  useUpdateRutaEstado,
  useCreateAbastecimiento,
  usePuntosPorFaena,
} from '@/hooks/use-abastecimiento'

// ---------------------------------------------------------------------------
// Filter options
// ---------------------------------------------------------------------------
const estadoOptions = [
  { value: '', label: 'Todos' },
  { value: 'programada', label: 'Programada' },
  { value: 'en_ejecucion', label: 'En Ejecucion' },
  { value: 'completada', label: 'Completada' },
  { value: 'incompleta', label: 'Incompleta' },
]

const estadoTransitions: Record<string, { value: string; label: string }[]> = {
  programada: [
    { value: 'en_ejecucion', label: 'En Ejecucion' },
  ],
  en_ejecucion: [
    { value: 'completada', label: 'Completada' },
    { value: 'incompleta', label: 'Incompleta' },
  ],
  completada: [],
  incompleta: [],
}

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
    en_ejecucion: { variant: 'bg-yellow-100 text-yellow-700', label: 'En Ejecucion' },
    completada: { variant: 'bg-green-100 text-green-700', label: 'Completada' },
    incompleta: { variant: 'bg-red-100 text-red-700', label: 'Incompleta' },
  }
  const c = config[estado] || { variant: 'bg-gray-100 text-gray-700', label: estado }
  return <Badge className={c.variant}>{c.label}</Badge>
}

// ---------------------------------------------------------------------------
// Estado change dropdown (inline)
// ---------------------------------------------------------------------------
function EstadoDropdown({
  estado,
  rutaId,
  onUpdate,
  loading,
}: {
  estado: string
  rutaId: string
  onUpdate: (id: string, estado: string) => void
  loading: boolean
}) {
  const transitions = estadoTransitions[estado] || []

  if (transitions.length === 0) {
    return getEstadoBadge(estado)
  }

  return (
    <div className="flex items-center gap-2">
      {getEstadoBadge(estado)}
      <div className="relative">
        <select
          disabled={loading}
          value=""
          onChange={(e) => {
            if (e.target.value) onUpdate(rutaId, e.target.value)
          }}
          className="h-7 appearance-none rounded border border-gray-300 bg-white px-2 pr-6 text-xs text-gray-600 focus:border-pillado-green-500 focus:outline-none disabled:opacity-50"
        >
          <option value="">Cambiar...</option>
          {transitions.map((t) => (
            <option key={t.value} value={t.value}>
              {t.label}
            </option>
          ))}
        </select>
        <ChevronDown className="pointer-events-none absolute right-1 top-1/2 h-3 w-3 -translate-y-1/2 text-gray-400" />
      </div>
    </div>
  )
}

// ---------------------------------------------------------------------------
// Ruta mobile card
// ---------------------------------------------------------------------------
function RutaMobileCard({
  ruta,
  onUpdateEstado,
  updatingEstado,
  onAddAbastecimiento,
}: {
  ruta: any
  onUpdateEstado: (id: string, estado: string) => void
  updatingEstado: boolean
  onAddAbastecimiento: (rutaId: string) => void
}) {
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
          <EstadoDropdown
            estado={ruta.estado}
            rutaId={ruta.id}
            onUpdate={onUpdateEstado}
            loading={updatingEstado}
          />
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
        <div className="mt-3 flex justify-end">
          <Button
            variant="outline"
            size="sm"
            onClick={() => onAddAbastecimiento(ruta.id)}
          >
            <Plus className="h-3 w-3" />
            Abastecimiento
          </Button>
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
// Nueva Ruta Modal
// ---------------------------------------------------------------------------
function NuevaRutaModal({
  open,
  onClose,
  faenaOptions,
  onSubmit,
  loading,
}: {
  open: boolean
  onClose: () => void
  faenaOptions: { value: string; label: string }[]
  onSubmit: (data: {
    faena_id: string
    fecha_programada: string
    puntos_programados?: number
    km_programados?: number
  }) => void
  loading: boolean
}) {
  const [faenaId, setFaenaId] = useState('')
  const [fechaProgramada, setFechaProgramada] = useState('')
  const [puntosProgramados, setPuntosProgramados] = useState('')
  const [kmProgramados, setKmProgramados] = useState('')

  const handleSubmit = () => {
    if (!faenaId || !fechaProgramada) return
    onSubmit({
      faena_id: faenaId,
      fecha_programada: fechaProgramada,
      puntos_programados: puntosProgramados ? Number(puntosProgramados) : undefined,
      km_programados: kmProgramados ? Number(kmProgramados) : undefined,
    })
  }

  // Reset form on close
  useEffect(() => {
    if (!open) {
      setFaenaId('')
      setFechaProgramada('')
      setPuntosProgramados('')
      setKmProgramados('')
    }
  }, [open])

  const faenasFiltered = faenaOptions.filter((f) => f.value !== '')

  return (
    <Modal open={open} onClose={onClose} title="Nueva Ruta de Despacho">
      <div className="space-y-4">
        <div>
          <label className="mb-1.5 block text-sm font-medium text-gray-700">
            Faena *
          </label>
          <div className="relative">
            <select
              value={faenaId}
              onChange={(e) => setFaenaId(e.target.value)}
              className="h-11 w-full appearance-none rounded-lg border border-gray-300 bg-white px-3 pr-8 text-sm text-gray-700 focus:border-pillado-green-500 focus:outline-none focus:ring-2 focus:ring-pillado-green-500/20"
            >
              <option value="">Seleccionar faena...</option>
              {faenasFiltered.map((f) => (
                <option key={f.value} value={f.value}>
                  {f.label}
                </option>
              ))}
            </select>
            <ChevronDown className="pointer-events-none absolute right-2 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400" />
          </div>
        </div>

        <Input
          label="Fecha Programada *"
          type="date"
          value={fechaProgramada}
          onChange={(e) => setFechaProgramada(e.target.value)}
        />

        <Input
          label="Puntos Programados"
          type="number"
          min={0}
          value={puntosProgramados}
          onChange={(e) => setPuntosProgramados(e.target.value)}
          placeholder="0"
        />

        <Input
          label="Km Programados"
          type="number"
          min={0}
          value={kmProgramados}
          onChange={(e) => setKmProgramados(e.target.value)}
          placeholder="0"
        />
      </div>

      <ModalFooter className="-mx-6 -mb-6 mt-6">
        <Button variant="ghost" onClick={onClose} disabled={loading}>
          Cancelar
        </Button>
        <Button
          variant="primary"
          onClick={handleSubmit}
          loading={loading}
          disabled={!faenaId || !fechaProgramada}
        >
          Crear Ruta
        </Button>
      </ModalFooter>
    </Modal>
  )
}

// ---------------------------------------------------------------------------
// Agregar Abastecimiento Modal
// ---------------------------------------------------------------------------
function NuevoAbastecimientoModal({
  open,
  onClose,
  rutaId,
  onSubmit,
  loading,
}: {
  open: boolean
  onClose: () => void
  rutaId: string | null
  onSubmit: (data: {
    ruta_despacho_id?: string
    producto_id: string
    cantidad_programada?: number
    cantidad_real?: number
  }) => void
  loading: boolean
}) {
  const [productoId, setProductoId] = useState('')
  const [productoSearch, setProductoSearch] = useState('')
  const [cantidadProgramada, setCantidadProgramada] = useState('')
  const [cantidadReal, setCantidadReal] = useState('')
  const [productos, setProductos] = useState<{ id: string; nombre: string }[]>([])
  const [loadingProductos, setLoadingProductos] = useState(false)

  // Search productos
  useEffect(() => {
    if (!open) return
    setLoadingProductos(true)
    getProductos(productoSearch ? { search: productoSearch } : undefined).then(
      ({ data }) => {
        setProductos(data || [])
        setLoadingProductos(false)
      }
    )
  }, [productoSearch, open])

  // Reset on close
  useEffect(() => {
    if (!open) {
      setProductoId('')
      setProductoSearch('')
      setCantidadProgramada('')
      setCantidadReal('')
    }
  }, [open])

  const handleSubmit = () => {
    if (!productoId) return
    onSubmit({
      ruta_despacho_id: rutaId || undefined,
      producto_id: productoId,
      cantidad_programada: cantidadProgramada ? Number(cantidadProgramada) : undefined,
      cantidad_real: cantidadReal ? Number(cantidadReal) : undefined,
    })
  }

  return (
    <Modal open={open} onClose={onClose} title="Agregar Abastecimiento">
      <div className="space-y-4">
        <div>
          <label className="mb-1.5 block text-sm font-medium text-gray-700">
            Producto *
          </label>
          <input
            type="text"
            placeholder="Buscar producto..."
            value={productoSearch}
            onChange={(e) => {
              setProductoSearch(e.target.value)
              setProductoId('')
            }}
            className="mb-2 flex h-10 w-full rounded-lg border border-gray-300 bg-white px-3 text-sm text-gray-900 placeholder:text-gray-400 focus:border-pillado-green-500 focus:outline-none focus:ring-2 focus:ring-pillado-green-500/20"
          />
          <div className="max-h-40 overflow-y-auto rounded-lg border border-gray-200 bg-white">
            {loadingProductos ? (
              <div className="flex items-center justify-center py-4">
                <Spinner size="sm" />
              </div>
            ) : productos.length === 0 ? (
              <p className="px-3 py-3 text-xs text-gray-500">Sin resultados</p>
            ) : (
              productos.map((p) => (
                <button
                  key={p.id}
                  type="button"
                  onClick={() => {
                    setProductoId(p.id)
                    setProductoSearch(p.nombre)
                  }}
                  className={`w-full px-3 py-2 text-left text-sm transition-colors hover:bg-pillado-green-50 ${
                    productoId === p.id
                      ? 'bg-pillado-green-50 font-medium text-pillado-green-700'
                      : 'text-gray-700'
                  }`}
                >
                  {p.nombre}
                </button>
              ))
            )}
          </div>
        </div>

        <Input
          label="Cantidad Programada"
          type="number"
          min={0}
          step="0.01"
          value={cantidadProgramada}
          onChange={(e) => setCantidadProgramada(e.target.value)}
          placeholder="0"
        />

        <Input
          label="Cantidad Real"
          type="number"
          min={0}
          step="0.01"
          value={cantidadReal}
          onChange={(e) => setCantidadReal(e.target.value)}
          placeholder="0"
        />
      </div>

      <ModalFooter className="-mx-6 -mb-6 mt-6">
        <Button variant="ghost" onClick={onClose} disabled={loading}>
          Cancelar
        </Button>
        <Button
          variant="primary"
          onClick={handleSubmit}
          loading={loading}
          disabled={!productoId}
        >
          Agregar
        </Button>
      </ModalFooter>
    </Modal>
  )
}

// ---------------------------------------------------------------------------
// Main page
// ---------------------------------------------------------------------------
export default function AbastecimientoPage() {
  const [activeTab, setActiveTab] = useState<'rutas' | 'abastecimientos' | 'puntos'>('rutas')
  const [puntosFaenaId, setPuntosFaenaId] = useState('')
  const [faenaFilter, setFaenaFilter] = useState('')
  const [estadoFilter, setEstadoFilter] = useState('')
  const [fechaDesde, setFechaDesde] = useState('')
  const [fechaHasta, setFechaHasta] = useState('')

  // Modal state
  const [showNuevaRuta, setShowNuevaRuta] = useState(false)
  const [showNuevoAbastecimiento, setShowNuevoAbastecimiento] = useState(false)
  const [abastecimientoRutaId, setAbastecimientoRutaId] = useState<string | null>(null)

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

  // Queries (using hooks)
  const { data: rutas, isLoading: loadingRutas, error: errorRutas } = useRutasDespacho(rutaFilters)
  const { data: abastecimientos, isLoading: loadingAbast, error: errorAbast } = useAbastecimientos()
  const { data: stats } = useRutaStats(faenaFilter || undefined)

  // Puntos por faena
  const { data: puntosFaena, isLoading: loadingPuntos } = usePuntosPorFaena(puntosFaenaId || undefined)

  // Mutations
  const createRuta = useCreateRuta()
  const updateEstado = useUpdateRutaEstado()
  const createAbast = useCreateAbastecimiento()

  const isLoading = activeTab === 'rutas' ? loadingRutas : activeTab === 'abastecimientos' ? loadingAbast : false
  const error = activeTab === 'rutas' ? errorRutas : activeTab === 'abastecimientos' ? errorAbast : null

  const handleCreateRuta = (data: {
    faena_id: string
    fecha_programada: string
    puntos_programados?: number
    km_programados?: number
  }) => {
    createRuta.mutate(data, {
      onSuccess: () => setShowNuevaRuta(false),
    })
  }

  const handleUpdateEstado = (id: string, estado: string) => {
    updateEstado.mutate({ id, estado })
  }

  const handleCreateAbastecimiento = (data: {
    ruta_despacho_id?: string
    producto_id: string
    cantidad_programada?: number
    cantidad_real?: number
  }) => {
    createAbast.mutate(data, {
      onSuccess: () => {
        setShowNuevoAbastecimiento(false)
        setAbastecimientoRutaId(null)
      },
    })
  }

  const openAbastecimientoModal = (rutaId: string) => {
    setAbastecimientoRutaId(rutaId)
    setShowNuevoAbastecimiento(true)
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-start justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Abastecimiento y Lubricacion</h1>
          <p className="mt-1 text-sm text-gray-500">
            Programacion de abastecimientos, rutas de despacho, control de volumen y cumplimiento.
          </p>
        </div>
        <Button
          variant="primary"
          onClick={() => setShowNuevaRuta(true)}
        >
          <Plus className="h-4 w-4" />
          Nueva Ruta
        </Button>
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
        <button
          onClick={() => setActiveTab('puntos')}
          className={`flex-1 rounded-md px-4 py-2 text-sm font-medium transition-colors flex items-center justify-center gap-1.5 ${
            activeTab === 'puntos'
              ? 'bg-white text-gray-900 shadow-sm'
              : 'text-gray-500 hover:text-gray-700'
          }`}
        >
          <MapPin className="h-4 w-4" />
          Puntos
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
                      <TableHead></TableHead>
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
                          <TableCell>
                            <EstadoDropdown
                              estado={ruta.estado}
                              rutaId={ruta.id}
                              onUpdate={handleUpdateEstado}
                              loading={updateEstado.isPending}
                            />
                          </TableCell>
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
                          <TableCell>
                            <Button
                              variant="ghost"
                              size="sm"
                              onClick={() => openAbastecimientoModal(ruta.id)}
                            >
                              <Plus className="h-3 w-3" />
                              Abast.
                            </Button>
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
                  <RutaMobileCard
                    key={ruta.id}
                    ruta={ruta}
                    onUpdateEstado={handleUpdateEstado}
                    updatingEstado={updateEstado.isPending}
                    onAddAbastecimiento={openAbastecimientoModal}
                  />
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

      {/* Puntos Tab */}
      {activeTab === 'puntos' && (
        <div className="space-y-4">
          {/* Faena Selector */}
          <Card>
            <CardContent className="p-4">
              <Select
                label="Faena"
                value={puntosFaenaId}
                onChange={setPuntosFaenaId}
                options={faenaOptions.filter(f => f.value !== '').length > 0
                  ? [{ value: '', label: 'Seleccionar faena...' }, ...faenaOptions.filter(f => f.value !== '')]
                  : [{ value: '', label: 'Cargando faenas...' }]}
              />
            </CardContent>
          </Card>

          {!puntosFaenaId && (
            <Card>
              <div className="flex flex-col items-center justify-center py-12 text-center">
                <MapPin className="h-10 w-10 text-gray-300 mb-2" />
                <p className="text-gray-400 text-sm">Seleccione una faena para ver sus puntos de abastecimiento</p>
              </div>
            </Card>
          )}

          {puntosFaenaId && loadingPuntos && (
            <div className="flex items-center justify-center py-12">
              <Spinner size="lg" className="text-pillado-green-500" />
            </div>
          )}

          {puntosFaenaId && !loadingPuntos && (!puntosFaena || puntosFaena.length === 0) && (
            <Card>
              <div className="flex flex-col items-center justify-center py-12 text-center">
                <MapPin className="h-10 w-10 text-gray-300 mb-2" />
                <p className="text-gray-500 font-medium">Sin puntos de abastecimiento</p>
                <p className="text-gray-400 text-sm mt-1">No se encontraron activos de tipo punto fijo, surtidor, estanque, bomba, dispensador o manguera operativos en esta faena.</p>
              </div>
            </Card>
          )}

          {puntosFaenaId && !loadingPuntos && puntosFaena && puntosFaena.length > 0 && (
            <div className="grid grid-cols-1 gap-4 md:grid-cols-2 lg:grid-cols-3">
              {puntosFaena.map((punto: any) => {
                const capacidad = punto.capacidad_litros
                const ultimoAbast = punto.ultimo_abastecimiento
                const cantSugerida = punto.cantidad_sugerida

                // Estimate level percentage
                let levelPct: number | null = null
                if (capacidad && ultimoAbast?.cantidad_real) {
                  levelPct = Math.max(0, Math.min(100, Math.round((ultimoAbast.cantidad_real * 0.3 / capacidad) * 100)))
                }

                const levelColor = levelPct !== null
                  ? levelPct > 50 ? 'bg-green-500' : levelPct > 20 ? 'bg-yellow-500' : 'bg-red-500'
                  : 'bg-gray-300'

                const tipoBadgeConfig: Record<string, string> = {
                  punto_fijo: 'bg-blue-100 text-blue-700',
                  surtidor: 'bg-purple-100 text-purple-700',
                  estanque: 'bg-cyan-100 text-cyan-700',
                  bomba: 'bg-orange-100 text-orange-700',
                  dispensador: 'bg-green-100 text-green-700',
                  manguera: 'bg-yellow-100 text-yellow-700',
                }

                return (
                  <Card key={punto.id}>
                    <CardContent className="p-4">
                      {/* Header */}
                      <div className="flex items-start justify-between gap-2">
                        <div className="min-w-0">
                          <p className="text-sm font-bold text-gray-900 truncate">
                            {punto.codigo} — {punto.nombre}
                          </p>
                        </div>
                        <Badge className={tipoBadgeConfig[punto.tipo] || 'bg-gray-100 text-gray-700'}>
                          {punto.tipo?.replace('_', ' ')}
                        </Badge>
                      </div>

                      {/* Capacity */}
                      <div className="mt-3">
                        {capacidad ? (
                          <p className="text-sm text-gray-600">
                            Capacidad: <span className="font-semibold">{Number(capacidad).toLocaleString('es-CL')} L</span>
                          </p>
                        ) : (
                          <p className="text-sm text-gray-400 italic">Capacidad no registrada en modelo</p>
                        )}
                      </div>

                      {/* Last supply */}
                      <div className="mt-2">
                        {ultimoAbast ? (
                          <p className="text-xs text-gray-500">
                            Ultimo abastecimiento: {ultimoAbast.fecha_hora ? formatDate(ultimoAbast.fecha_hora) : '—'} — {ultimoAbast.cantidad_real ?? '—'} L
                            {ultimoAbast.producto?.nombre ? ` (${ultimoAbast.producto.nombre})` : ''}
                          </p>
                        ) : (
                          <p className="text-xs text-gray-400">Sin registros de abastecimiento</p>
                        )}
                      </div>

                      {/* Visual bar */}
                      {capacidad && (
                        <div className="mt-3">
                          <div className="flex items-center justify-between text-xs text-gray-500 mb-1">
                            <span>Nivel estimado</span>
                            <span>{levelPct !== null ? `${levelPct}%` : '—'}</span>
                          </div>
                          <div className="h-3 w-full rounded-full bg-gray-200 overflow-hidden">
                            <div
                              className={`h-3 rounded-full transition-all ${levelColor}`}
                              style={{ width: `${levelPct ?? 0}%` }}
                            />
                          </div>
                        </div>
                      )}

                      {/* Suggested refill */}
                      {cantSugerida !== null && cantSugerida > 0 && (
                        <div className="mt-3 rounded-lg bg-blue-50 border border-blue-200 px-3 py-2">
                          <p className="text-sm text-blue-700 font-medium">
                            Rellenar: ~{Number(Math.round(cantSugerida)).toLocaleString('es-CL')} L
                          </p>
                        </div>
                      )}
                    </CardContent>
                  </Card>
                )
              })}
            </div>
          )}
        </div>
      )}

      {/* Modals */}
      <NuevaRutaModal
        open={showNuevaRuta}
        onClose={() => setShowNuevaRuta(false)}
        faenaOptions={faenaOptions}
        onSubmit={handleCreateRuta}
        loading={createRuta.isPending}
      />

      <NuevoAbastecimientoModal
        open={showNuevoAbastecimiento}
        onClose={() => {
          setShowNuevoAbastecimiento(false)
          setAbastecimientoRutaId(null)
        }}
        rutaId={abastecimientoRutaId}
        onSubmit={handleCreateAbastecimiento}
        loading={createAbast.isPending}
      />
    </div>
  )
}
