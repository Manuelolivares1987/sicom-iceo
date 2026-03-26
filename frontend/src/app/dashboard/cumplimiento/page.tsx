'use client'

import { useState, useEffect } from 'react'
import {
  ShieldCheck,
  AlertTriangle,
  CheckCircle2,
  Lock,
  Calendar,
  ChevronDown,
} from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { StatCard } from '@/components/ui/stat-card'
import { Spinner } from '@/components/ui/spinner'
import { EmptyState } from '@/components/ui/empty-state'
import {
  Table,
  TableHeader,
  TableBody,
  TableRow,
  TableHead,
  TableCell,
} from '@/components/ui/table'
import { formatDate } from '@/lib/utils'
import { useAllCertificaciones, useCertificacionStats } from '@/hooks/use-certificaciones'
import { getFaenas } from '@/lib/services/faenas'

// ---------------------------------------------------------------------------
// Filter options
// ---------------------------------------------------------------------------
const estadoOptions: { value: string; label: string }[] = [
  { value: '', label: 'Todos' },
  { value: 'vigente', label: 'Vigente' },
  { value: 'por_vencer', label: 'Por Vencer' },
  { value: 'vencido', label: 'Vencido' },
]

const tipoOptions: { value: string; label: string }[] = [
  { value: '', label: 'Todos' },
  { value: 'SEC', label: 'SEC' },
  { value: 'SEREMI', label: 'SEREMI' },
  { value: 'SISS', label: 'SISS' },
  { value: 'Revisión Técnica', label: 'Revisión Técnica' },
  { value: 'SOAP', label: 'SOAP' },
  { value: 'Calibración', label: 'Calibración' },
  { value: 'Licencia', label: 'Licencia' },
  { value: 'Otro', label: 'Otro' },
]

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
function getEstadoBadge(estado: string) {
  const config: Record<string, { className: string; label: string }> = {
    vigente: { className: 'bg-green-100 text-green-700', label: 'Vigente' },
    por_vencer: { className: 'bg-yellow-100 text-yellow-700', label: 'Por Vencer' },
    vencido: { className: 'bg-red-100 text-red-700', label: 'Vencido' },
  }
  const c = config[estado] || { className: 'bg-gray-100 text-gray-700', label: estado }
  return <Badge className={c.className}>{c.label}</Badge>
}

function getTipoBadge(tipo: string) {
  const colors: Record<string, string> = {
    SEC: 'bg-blue-100 text-blue-700',
    SEREMI: 'bg-purple-100 text-purple-700',
    SISS: 'bg-cyan-100 text-cyan-700',
    'Revisión Técnica': 'bg-indigo-100 text-indigo-700',
    SOAP: 'bg-pillado-orange-100 text-pillado-orange-700',
    Calibración: 'bg-pink-100 text-pink-700',
    Licencia: 'bg-amber-100 text-amber-700',
    Otro: 'bg-gray-100 text-gray-700',
  }
  return (
    <span
      className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-semibold ${colors[tipo] || 'bg-gray-100 text-gray-700'}`}
    >
      {tipo}
    </span>
  )
}

// ---------------------------------------------------------------------------
// Select component (inline, matches OT page pattern)
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
// Mobile card
// ---------------------------------------------------------------------------
function MobileCard({ cert }: { cert: any }) {
  const activo = cert.activo
  const activoLabel = activo ? `${activo.codigo} - ${activo.nombre || ''}` : '—'

  return (
    <Card className="mb-3">
      <CardContent className="p-4">
        <div className="flex items-start justify-between">
          <div className="min-w-0 flex-1">
            <p className="truncate text-sm font-bold text-gray-900">{activoLabel}</p>
            <p className="text-xs text-gray-500">{activo?.faena?.nombre || '—'}</p>
          </div>
          <div className="ml-2 flex shrink-0 items-center gap-2">
            {cert.bloqueante && <Lock className="h-4 w-4 text-red-500" />}
            {getEstadoBadge(cert.estado)}
          </div>
        </div>
        <div className="mt-3 flex flex-wrap items-center gap-2">
          {getTipoBadge(cert.tipo)}
          {cert.numero_certificado && (
            <span className="text-xs text-gray-500">N° {cert.numero_certificado}</span>
          )}
        </div>
        <div className="mt-3 grid grid-cols-2 gap-y-1 text-xs text-gray-600">
          <span>Entidad: {cert.entidad_certificadora || '—'}</span>
          <span>Emisión: {formatDate(cert.fecha_emision)}</span>
          <span className="font-medium text-gray-900">
            Vence: {formatDate(cert.fecha_vencimiento)}
          </span>
        </div>
      </CardContent>
    </Card>
  )
}

// ---------------------------------------------------------------------------
// Main page
// ---------------------------------------------------------------------------
export default function CumplimientoPage() {
  const [estadoFilter, setEstadoFilter] = useState('')
  const [tipoFilter, setTipoFilter] = useState('')
  const [faenaFilter, setFaenaFilter] = useState('')

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
  const filters: { estado?: string; tipo?: string; faena_id?: string } = {}
  if (estadoFilter) filters.estado = estadoFilter
  if (tipoFilter) filters.tipo = tipoFilter
  if (faenaFilter) filters.faena_id = faenaFilter

  const { data: certificaciones, isLoading, error } = useAllCertificaciones(filters)
  const { data: stats } = useCertificacionStats()

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <h1 className="text-2xl font-bold text-gray-900">Cumplimiento Documental</h1>
      </div>

      {/* Stats */}
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <StatCard
          title="Total Certificaciones"
          value={stats?.total ?? '—'}
          icon={ShieldCheck}
          color="blue"
        />
        <StatCard
          title="Vigentes"
          value={stats?.vigentes ?? '—'}
          icon={CheckCircle2}
          color="green"
        />
        <StatCard
          title="Por Vencer"
          value={stats?.por_vencer ?? '—'}
          icon={Calendar}
          color="orange"
        />
        <StatCard
          title="Vencidas"
          value={stats?.vencidas ?? '—'}
          icon={AlertTriangle}
          color="red"
        />
      </div>

      {/* Filters */}
      <Card>
        <CardContent className="p-4">
          <div className="flex flex-col gap-3 sm:flex-row sm:flex-wrap sm:items-end">
            <Select
              label="Estado"
              value={estadoFilter}
              onChange={setEstadoFilter}
              options={estadoOptions}
            />
            <Select
              label="Tipo"
              value={tipoFilter}
              onChange={setTipoFilter}
              options={tipoOptions}
            />
            <Select
              label="Faena"
              value={faenaFilter}
              onChange={setFaenaFilter}
              options={faenaOptions}
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
        <div className="rounded-xl border border-red-200 bg-red-50 p-4 text-center text-sm text-red-700">
          Error al cargar certificaciones. Intente nuevamente.
        </div>
      )}

      {/* Content */}
      {!isLoading && !error && (
        <>
          {(!certificaciones || certificaciones.length === 0) ? (
            <Card>
              <EmptyState
                icon={ShieldCheck}
                title="Sin certificaciones"
                description="No se encontraron certificaciones con los filtros seleccionados."
              />
            </Card>
          ) : (
            <>
              {/* Desktop table */}
              <Card className="hidden md:block">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Activo</TableHead>
                      <TableHead>Tipo</TableHead>
                      <TableHead>N° Certificado</TableHead>
                      <TableHead>Entidad</TableHead>
                      <TableHead>Emisión</TableHead>
                      <TableHead>Vencimiento</TableHead>
                      <TableHead>Estado</TableHead>
                      <TableHead className="text-center">Bloqueante</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {certificaciones.map((cert: any) => {
                      const activo = cert.activo
                      return (
                        <TableRow key={cert.id}>
                          <TableCell>
                            <div>
                              <p className="text-sm font-semibold text-gray-900">
                                {activo?.codigo || '—'}
                              </p>
                              <p className="text-xs text-gray-500">
                                {activo?.nombre || '—'}
                              </p>
                            </div>
                          </TableCell>
                          <TableCell>{getTipoBadge(cert.tipo)}</TableCell>
                          <TableCell className="text-sm text-gray-700">
                            {cert.numero_certificado || '—'}
                          </TableCell>
                          <TableCell className="text-sm text-gray-700">
                            {cert.entidad_certificadora || '—'}
                          </TableCell>
                          <TableCell className="text-sm text-gray-700">
                            {formatDate(cert.fecha_emision)}
                          </TableCell>
                          <TableCell className="text-sm text-gray-700">
                            {formatDate(cert.fecha_vencimiento)}
                          </TableCell>
                          <TableCell>{getEstadoBadge(cert.estado)}</TableCell>
                          <TableCell className="text-center">
                            {cert.bloqueante && (
                              <Lock className="mx-auto h-4 w-4 text-red-500" />
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
                {certificaciones.map((cert: any) => (
                  <MobileCard key={cert.id} cert={cert} />
                ))}
              </div>
            </>
          )}
        </>
      )}
    </div>
  )
}
