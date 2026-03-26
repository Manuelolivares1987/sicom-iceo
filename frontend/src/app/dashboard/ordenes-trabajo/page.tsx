'use client'

import { useState, useEffect, useCallback } from 'react'
import Link from 'next/link'
import { Search, Plus, ChevronDown, Eye } from 'lucide-react'
import { CrearOTModal } from '@/components/ot/crear-ot-modal'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Input } from '@/components/ui/input'
import { Spinner } from '@/components/ui/spinner'
import {
  Table,
  TableHeader,
  TableBody,
  TableRow,
  TableHead,
  TableCell,
} from '@/components/ui/table'
import { formatCLP, formatDate, getEstadoOTColor, getEstadoOTLabel } from '@/lib/utils'
import { useOrdenesTrabajo } from '@/hooks/use-ordenes-trabajo'
import { getFaenas } from '@/lib/services/faenas'
// Types used: TipoOT, EstadoOT, Prioridad — from filter values

// ---------------------------------------------------------------------------
// Filter options
// ---------------------------------------------------------------------------
const tipoOptions: { value: string; label: string }[] = [
  { value: '', label: 'Todos' },
  { value: 'inspeccion', label: 'Inspección' },
  { value: 'preventivo', label: 'Preventivo' },
  { value: 'correctivo', label: 'Correctivo' },
  { value: 'abastecimiento', label: 'Abastecimiento' },
  { value: 'lubricacion', label: 'Lubricación' },
  { value: 'inventario', label: 'Inventario' },
  { value: 'regularizacion', label: 'Regularización' },
]

const estadoOptions: { value: string; label: string }[] = [
  { value: '', label: 'Todos' },
  { value: 'creada', label: 'Creada' },
  { value: 'asignada', label: 'Asignada' },
  { value: 'en_ejecucion', label: 'En Ejecución' },
  { value: 'pausada', label: 'Pausada' },
  { value: 'ejecutada_ok', label: 'Ejecutada OK' },
  { value: 'ejecutada_con_observaciones', label: 'Con Observaciones' },
  { value: 'no_ejecutada', label: 'No Ejecutada' },
  { value: 'cancelada', label: 'Cancelada' },
]

const prioridadOptions: { value: string; label: string }[] = [
  { value: '', label: 'Todas' },
  { value: 'emergencia', label: 'Emergencia' },
  { value: 'urgente', label: 'Urgente' },
  { value: 'alta', label: 'Alta' },
  { value: 'normal', label: 'Normal' },
  { value: 'baja', label: 'Baja' },
]

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
const tipoLabels: Record<string, string> = {
  inspeccion: 'Inspección',
  preventivo: 'Preventivo',
  correctivo: 'Correctivo',
  abastecimiento: 'Abastecimiento',
  lubricacion: 'Lubricación',
  inventario: 'Inventario',
  regularizacion: 'Regularización',
}

function getPrioridadBadge(p: string) {
  const labels: Record<string, string> = {
    emergencia: 'Emergencia',
    urgente: 'Urgente',
    critica: 'Crítica',
    alta: 'Alta',
    normal: 'Normal',
    media: 'Media',
    baja: 'Baja',
  }
  return (
    <Badge variant={(p || 'default') as any}>
      {labels[p] || p}
    </Badge>
  )
}

function getTipoBadge(tipo: string) {
  const colors: Record<string, string> = {
    preventivo: 'bg-blue-100 text-blue-700',
    correctivo: 'bg-red-100 text-red-700',
    abastecimiento: 'bg-pillado-orange-100 text-pillado-orange-700',
    inspeccion: 'bg-purple-100 text-purple-700',
    lubricacion: 'bg-cyan-100 text-cyan-700',
    inventario: 'bg-indigo-100 text-indigo-700',
    regularizacion: 'bg-pink-100 text-pink-700',
  }
  const label = tipoLabels[tipo] || tipo
  return (
    <span className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-semibold ${colors[tipo] || 'bg-gray-100 text-gray-700'}`}>
      {label}
    </span>
  )
}

// ---------------------------------------------------------------------------
// Mobile card sub-component
// ---------------------------------------------------------------------------
interface OTRow {
  id: string
  folio: string
  tipo: string
  prioridad: string
  estado: string
  fecha_programada: string | null
  costo_total: number
  activo?: { id: string; codigo: string; nombre: string | null; tipo: string } | null
  faena?: { id: string; codigo: string; nombre: string } | null
  responsable?: { id: string; nombre_completo: string; cargo: string | null } | null
}

function MobileCard({ ot }: { ot: OTRow }) {
  const activoLabel = ot.activo ? (ot.activo.nombre || ot.activo.codigo) : '—'
  const faenaLabel = ot.faena?.nombre || '—'
  const responsableLabel = ot.responsable?.nombre_completo || '—'

  return (
    <Link href={`/dashboard/ordenes-trabajo/${ot.id}`}>
      <Card className="mb-3">
        <CardContent className="p-4">
          <div className="flex items-start justify-between">
            <div>
              <p className="text-sm font-bold text-gray-900">{ot.folio}</p>
              <p className="text-xs text-gray-500">{activoLabel}</p>
            </div>
            <Badge className={getEstadoOTColor(ot.estado)}>
              {getEstadoOTLabel(ot.estado)}
            </Badge>
          </div>
          <div className="mt-3 flex flex-wrap items-center gap-2">
            {getTipoBadge(ot.tipo)}
            {getPrioridadBadge(ot.prioridad)}
          </div>
          <div className="mt-3 grid grid-cols-2 gap-y-1 text-xs text-gray-600">
            <span>Faena: {faenaLabel}</span>
            <span>Resp: {responsableLabel}</span>
            <span>Fecha: {ot.fecha_programada ? formatDate(ot.fecha_programada) : '—'}</span>
            <span className="font-medium text-gray-900">
              {ot.costo_total > 0 ? formatCLP(ot.costo_total) : '—'}
            </span>
          </div>
        </CardContent>
      </Card>
    </Link>
  )
}

// ---------------------------------------------------------------------------
// Select component (simple)
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
// Main page
// ---------------------------------------------------------------------------
export default function OrdenesTrabajoPage() {
  const [tipoFilter, setTipoFilter] = useState('')
  const [estadoFilter, setEstadoFilter] = useState('')
  const [faenaFilter, setFaenaFilter] = useState('')
  const [prioridadFilter, setPrioridadFilter] = useState('')
  const [search, setSearch] = useState('')
  const [showCrearModal, setShowCrearModal] = useState(false)

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

  // Build filters for Supabase query
  const filters: Record<string, unknown> = {}
  if (tipoFilter) filters.tipo = tipoFilter
  if (estadoFilter) filters.estado = estadoFilter
  if (faenaFilter) filters.faena_id = faenaFilter
  if (prioridadFilter) filters.prioridad = prioridadFilter

  const { data: ordenes, isLoading, error } = useOrdenesTrabajo(filters)

  // Client-side search filtering (folio, activo, responsable)
  const filtered = (ordenes ?? []).filter((ot: any) => {
    if (!search) return true
    const s = search.toLowerCase()
    const activoName = ot.activo?.nombre || ot.activo?.codigo || ''
    const responsableName = ot.responsable?.nombre_completo || ''
    return (
      ot.folio.toLowerCase().includes(s) ||
      activoName.toLowerCase().includes(s) ||
      responsableName.toLowerCase().includes(s)
    )
  }) as OTRow[]

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <h1 className="text-2xl font-bold text-gray-900">Ordenes de Trabajo</h1>
        <Button
          variant="primary"
          size="lg"
          className="w-full sm:w-auto"
          onClick={() => setShowCrearModal(true)}
        >
          <Plus className="h-5 w-5" />
          Nueva OT
        </Button>
      </div>

      {/* Filters */}
      <Card>
        <CardContent className="p-4">
          <div className="flex flex-col gap-3 sm:flex-row sm:flex-wrap sm:items-end">
            <div className="flex-1 sm:max-w-xs">
              <Input
                placeholder="Buscar folio, activo, responsable..."
                value={search}
                onChange={(e) => setSearch(e.target.value)}
              />
            </div>
            <Select
              label="Tipo OT"
              value={tipoFilter}
              onChange={setTipoFilter}
              options={tipoOptions}
            />
            <Select
              label="Estado"
              value={estadoFilter}
              onChange={setEstadoFilter}
              options={estadoOptions}
            />
            <Select
              label="Faena"
              value={faenaFilter}
              onChange={setFaenaFilter}
              options={faenaOptions}
            />
            <Select
              label="Prioridad"
              value={prioridadFilter}
              onChange={setPrioridadFilter}
              options={prioridadOptions}
            />
          </div>
        </CardContent>
      </Card>

      {/* Loading */}
      {isLoading && (
        <div className="flex items-center justify-center py-12">
          <Spinner size="lg" className="text-pillado-green-500" />
        </div>
      )}

      {/* Error */}
      {error && (
        <div className="rounded-xl border border-red-200 bg-red-50 p-4 text-sm text-red-700">
          <p className="font-semibold">Error al cargar órdenes de trabajo</p>
          <p className="mt-1 text-xs text-red-500 font-mono">{(error as any)?.message || String(error)}</p>
        </div>
      )}

      {/* Content */}
      {!isLoading && !error && (
        <>
          {/* Desktop table */}
          <Card className="hidden md:block">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Folio</TableHead>
                  <TableHead>Tipo</TableHead>
                  <TableHead>Activo</TableHead>
                  <TableHead>Faena</TableHead>
                  <TableHead>Prioridad</TableHead>
                  <TableHead>Estado</TableHead>
                  <TableHead>Responsable</TableHead>
                  <TableHead>Fecha Prog.</TableHead>
                  <TableHead className="text-right">Costo Total</TableHead>
                  <TableHead className="text-center">Acciones</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {filtered.map((ot) => (
                  <TableRow key={ot.id}>
                    <TableCell className="font-semibold text-gray-900">{ot.folio}</TableCell>
                    <TableCell>{getTipoBadge(ot.tipo)}</TableCell>
                    <TableCell>{ot.activo ? (ot.activo.nombre || ot.activo.codigo) : '—'}</TableCell>
                    <TableCell className="text-xs">{ot.faena?.nombre || '—'}</TableCell>
                    <TableCell>{getPrioridadBadge(ot.prioridad)}</TableCell>
                    <TableCell>
                      <Badge className={getEstadoOTColor(ot.estado)}>
                        {getEstadoOTLabel(ot.estado)}
                      </Badge>
                    </TableCell>
                    <TableCell>{ot.responsable?.nombre_completo || '—'}</TableCell>
                    <TableCell>{ot.fecha_programada ? formatDate(ot.fecha_programada) : '—'}</TableCell>
                    <TableCell className="text-right font-medium">
                      {ot.costo_total > 0 ? formatCLP(ot.costo_total) : '—'}
                    </TableCell>
                    <TableCell className="text-center">
                      <Link href={`/dashboard/ordenes-trabajo/${ot.id}`}>
                        <Button variant="ghost" size="sm">
                          <Eye className="h-4 w-4" />
                        </Button>
                      </Link>
                    </TableCell>
                  </TableRow>
                ))}
                {filtered.length === 0 && (
                  <TableRow>
                    <TableCell colSpan={10} className="py-12 text-center text-gray-400">
                      No hay ordenes de trabajo
                    </TableCell>
                  </TableRow>
                )}
              </TableBody>
            </Table>
          </Card>

          {/* Mobile cards */}
          <div className="md:hidden">
            {filtered.map((ot) => (
              <MobileCard key={ot.id} ot={ot} />
            ))}
            {filtered.length === 0 && (
              <p className="py-12 text-center text-gray-400">
                No hay ordenes de trabajo
              </p>
            )}
          </div>
        </>
      )}

      {/* Crear OT Modal */}
      <CrearOTModal
        open={showCrearModal}
        onClose={() => setShowCrearModal(false)}
        onCreated={() => {
          setShowCrearModal(false)
          alert('Orden de trabajo creada exitosamente')
        }}
        contratoId=""
        faenaId={faenaFilter || undefined}
      />
    </div>
  )
}
