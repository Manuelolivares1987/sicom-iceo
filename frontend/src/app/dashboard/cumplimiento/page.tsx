'use client'

import { useState, useEffect, useRef } from 'react'
import {
  ShieldCheck,
  AlertTriangle,
  CheckCircle2,
  Lock,
  Calendar,
  ChevronDown,
  Plus,
  RefreshCw,
  Upload,
  Search,
} from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { StatCard } from '@/components/ui/stat-card'
import { Spinner } from '@/components/ui/spinner'
import { EmptyState } from '@/components/ui/empty-state'
import { Modal, ModalFooter } from '@/components/ui/modal'
import {
  Table,
  TableHeader,
  TableBody,
  TableRow,
  TableHead,
  TableCell,
} from '@/components/ui/table'
import { formatDate } from '@/lib/utils'
import {
  useAllCertificaciones,
  useCertificacionStats,
  useCreateCertificacion,
} from '@/hooks/use-certificaciones'
import { useActivos } from '@/hooks/use-activos'
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

const tipoCertValues = ['SEC', 'SEREMI', 'SISS', 'Revisión Técnica', 'SOAP', 'Calibración', 'Licencia', 'Otro']

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
// Activo search/dropdown
// ---------------------------------------------------------------------------
function ActivoSearchSelect({
  value,
  onChange,
}: {
  value: string
  onChange: (id: string) => void
}) {
  const [searchTerm, setSearchTerm] = useState('')
  const [isOpen, setIsOpen] = useState(false)
  const wrapperRef = useRef<HTMLDivElement>(null)
  const { data: activos } = useActivos()

  const filtered = (activos ?? []).filter((a: any) => {
    if (!searchTerm) return true
    const term = searchTerm.toLowerCase()
    return (
      (a.codigo ?? '').toLowerCase().includes(term) ||
      (a.nombre ?? '').toLowerCase().includes(term)
    )
  }).slice(0, 30)

  const selected = (activos ?? []).find((a: any) => a.id === value)

  useEffect(() => {
    function handleClickOutside(e: MouseEvent) {
      if (wrapperRef.current && !wrapperRef.current.contains(e.target as Node)) {
        setIsOpen(false)
      }
    }
    document.addEventListener('mousedown', handleClickOutside)
    return () => document.removeEventListener('mousedown', handleClickOutside)
  }, [])

  return (
    <div ref={wrapperRef} className="relative">
      <label className="mb-1 block text-xs font-medium text-gray-500">Activo *</label>
      <div
        className="flex h-10 cursor-pointer items-center rounded-lg border border-gray-300 bg-white px-3 text-sm text-gray-700 focus-within:border-pillado-green-500 focus-within:ring-2 focus-within:ring-pillado-green-500/20"
        onClick={() => setIsOpen(true)}
      >
        <Search className="mr-2 h-4 w-4 text-gray-400" />
        {isOpen ? (
          <input
            autoFocus
            className="w-full bg-transparent outline-none"
            placeholder="Buscar activo..."
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
          />
        ) : (
          <span className={selected ? '' : 'text-gray-400'}>
            {selected ? `${selected.codigo} - ${selected.nombre ?? ''}` : 'Seleccionar activo...'}
          </span>
        )}
      </div>
      {isOpen && (
        <div className="absolute z-20 mt-1 max-h-48 w-full overflow-y-auto rounded-lg border border-gray-200 bg-white shadow-lg">
          {filtered.length === 0 && (
            <div className="px-3 py-2 text-sm text-gray-400">Sin resultados</div>
          )}
          {filtered.map((a: any) => (
            <button
              key={a.id}
              type="button"
              className="w-full px-3 py-2 text-left text-sm hover:bg-pillado-green-50"
              onClick={() => {
                onChange(a.id)
                setIsOpen(false)
                setSearchTerm('')
              }}
            >
              <span className="font-semibold">{a.codigo}</span>
              <span className="ml-2 text-gray-500">{a.nombre ?? ''}</span>
            </button>
          ))}
        </div>
      )}
    </div>
  )
}

// ---------------------------------------------------------------------------
// Certification form state
// ---------------------------------------------------------------------------
interface CertFormData {
  activo_id: string
  tipo: string
  fecha_emision: string
  fecha_vencimiento: string
  numero_certificado: string
  entidad_certificadora: string
  bloqueante: boolean
  estado: string
  notas: string
}

const emptyCertForm: CertFormData = {
  activo_id: '',
  tipo: 'SEC',
  fecha_emision: '',
  fecha_vencimiento: '',
  numero_certificado: '',
  entidad_certificadora: '',
  bloqueante: false,
  estado: 'vigente',
  notas: '',
}

// ---------------------------------------------------------------------------
// CertificacionModal
// ---------------------------------------------------------------------------
function CertificacionModal({
  open,
  onClose,
  initialData,
  title,
}: {
  open: boolean
  onClose: () => void
  initialData?: Partial<CertFormData>
  title: string
}) {
  const [form, setForm] = useState<CertFormData>({ ...emptyCertForm, ...initialData })
  const [file, setFile] = useState<File | undefined>(undefined)
  const [formError, setFormError] = useState('')
  const createMutation = useCreateCertificacion()

  // Reset form when modal opens with new data
  useEffect(() => {
    if (open) {
      setForm({ ...emptyCertForm, ...initialData })
      setFile(undefined)
      setFormError('')
    }
  }, [open, initialData])

  function updateField<K extends keyof CertFormData>(key: K, value: CertFormData[K]) {
    setForm((prev) => ({ ...prev, [key]: value }))
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setFormError('')

    if (!form.activo_id) {
      setFormError('Debe seleccionar un activo.')
      return
    }
    if (!form.fecha_emision || !form.fecha_vencimiento) {
      setFormError('Las fechas de emision y vencimiento son obligatorias.')
      return
    }

    try {
      await createMutation.mutateAsync({
        data: {
          activo_id: form.activo_id,
          tipo: form.tipo,
          fecha_emision: form.fecha_emision,
          fecha_vencimiento: form.fecha_vencimiento,
          numero_certificado: form.numero_certificado || null,
          entidad_certificadora: form.entidad_certificadora || null,
          bloqueante: form.bloqueante,
          estado: form.estado,
          notas: form.notas || null,
          created_by: null,
        },
        file,
      })
      onClose()
    } catch (err: any) {
      setFormError(err?.message ?? 'Error al crear certificacion.')
    }
  }

  return (
    <Modal open={open} onClose={onClose} title={title}>
      <form onSubmit={handleSubmit} className="space-y-4">
        <ActivoSearchSelect value={form.activo_id} onChange={(id) => updateField('activo_id', id)} />

        <div>
          <label className="mb-1 block text-xs font-medium text-gray-500">Tipo *</label>
          <div className="relative">
            <select
              value={form.tipo}
              onChange={(e) => updateField('tipo', e.target.value)}
              className="h-10 w-full appearance-none rounded-lg border border-gray-300 bg-white px-3 pr-8 text-sm text-gray-700 focus:border-pillado-green-500 focus:outline-none focus:ring-2 focus:ring-pillado-green-500/20"
            >
              {tipoCertValues.map((t) => (
                <option key={t} value={t}>{t}</option>
              ))}
            </select>
            <ChevronDown className="pointer-events-none absolute right-2 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400" />
          </div>
        </div>

        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="mb-1 block text-xs font-medium text-gray-500">Fecha Emision *</label>
            <input
              type="date"
              value={form.fecha_emision}
              onChange={(e) => updateField('fecha_emision', e.target.value)}
              className="h-10 w-full rounded-lg border border-gray-300 bg-white px-3 text-sm text-gray-700 focus:border-pillado-green-500 focus:outline-none focus:ring-2 focus:ring-pillado-green-500/20"
            />
          </div>
          <div>
            <label className="mb-1 block text-xs font-medium text-gray-500">Fecha Vencimiento *</label>
            <input
              type="date"
              value={form.fecha_vencimiento}
              onChange={(e) => updateField('fecha_vencimiento', e.target.value)}
              className="h-10 w-full rounded-lg border border-gray-300 bg-white px-3 text-sm text-gray-700 focus:border-pillado-green-500 focus:outline-none focus:ring-2 focus:ring-pillado-green-500/20"
            />
          </div>
        </div>

        <div>
          <label className="mb-1 block text-xs font-medium text-gray-500">N Certificado</label>
          <input
            type="text"
            value={form.numero_certificado}
            onChange={(e) => updateField('numero_certificado', e.target.value)}
            placeholder="Ej: 2024-00123"
            className="h-10 w-full rounded-lg border border-gray-300 bg-white px-3 text-sm text-gray-700 focus:border-pillado-green-500 focus:outline-none focus:ring-2 focus:ring-pillado-green-500/20"
          />
        </div>

        <div>
          <label className="mb-1 block text-xs font-medium text-gray-500">Entidad Certificadora</label>
          <input
            type="text"
            value={form.entidad_certificadora}
            onChange={(e) => updateField('entidad_certificadora', e.target.value)}
            placeholder="Ej: SGS Chile"
            className="h-10 w-full rounded-lg border border-gray-300 bg-white px-3 text-sm text-gray-700 focus:border-pillado-green-500 focus:outline-none focus:ring-2 focus:ring-pillado-green-500/20"
          />
        </div>

        <div className="flex items-center gap-2">
          <input
            type="checkbox"
            id="bloqueante"
            checked={form.bloqueante}
            onChange={(e) => updateField('bloqueante', e.target.checked)}
            className="h-4 w-4 rounded border-gray-300 text-pillado-green-600 focus:ring-pillado-green-500"
          />
          <label htmlFor="bloqueante" className="text-sm text-gray-700">
            Bloqueante (impide operacion si esta vencido)
          </label>
        </div>

        <div>
          <label className="mb-1 block text-xs font-medium text-gray-500">Archivo (opcional)</label>
          <label className="flex h-10 cursor-pointer items-center gap-2 rounded-lg border border-dashed border-gray-300 bg-gray-50 px-3 text-sm text-gray-500 hover:border-pillado-green-400 hover:bg-pillado-green-50">
            <Upload className="h-4 w-4" />
            <span>{file ? file.name : 'Seleccionar archivo...'}</span>
            <input
              type="file"
              className="hidden"
              accept=".pdf,.jpg,.jpeg,.png,.doc,.docx"
              onChange={(e) => setFile(e.target.files?.[0])}
            />
          </label>
        </div>

        {formError && (
          <div className="rounded-lg border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700">
            {formError}
          </div>
        )}

        <ModalFooter className="-mx-6 -mb-6 mt-4">
          <Button type="button" variant="outline" onClick={onClose}>
            Cancelar
          </Button>
          <Button type="submit" variant="primary" disabled={createMutation.isPending}>
            {createMutation.isPending ? 'Guardando...' : 'Guardar'}
          </Button>
        </ModalFooter>
      </form>
    </Modal>
  )
}

// ---------------------------------------------------------------------------
// Mobile card
// ---------------------------------------------------------------------------
function MobileCard({ cert, onRenovar }: { cert: any; onRenovar: (cert: any) => void }) {
  const activo = cert.activo
  const activoLabel = activo ? `${activo.codigo} - ${activo.nombre || ''}` : '--'

  return (
    <Card className="mb-3">
      <CardContent className="p-4">
        <div className="flex items-start justify-between">
          <div className="min-w-0 flex-1">
            <p className="truncate text-sm font-bold text-gray-900">{activoLabel}</p>
            <p className="text-xs text-gray-500">{activo?.faena?.nombre || '--'}</p>
          </div>
          <div className="ml-2 flex shrink-0 items-center gap-2">
            {cert.bloqueante && <Lock className="h-4 w-4 text-red-500" />}
            {getEstadoBadge(cert.estado)}
          </div>
        </div>
        <div className="mt-3 flex flex-wrap items-center gap-2">
          {getTipoBadge(cert.tipo)}
          {cert.numero_certificado && (
            <span className="text-xs text-gray-500">N {cert.numero_certificado}</span>
          )}
        </div>
        <div className="mt-3 grid grid-cols-2 gap-y-1 text-xs text-gray-600">
          <span>Entidad: {cert.entidad_certificadora || '--'}</span>
          <span>Emision: {formatDate(cert.fecha_emision)}</span>
          <span className="font-medium text-gray-900">
            Vence: {formatDate(cert.fecha_vencimiento)}
          </span>
        </div>
        <div className="mt-3 flex justify-end">
          <button
            onClick={() => onRenovar(cert)}
            className="inline-flex items-center gap-1 rounded-lg bg-pillado-green-50 px-3 py-1.5 text-xs font-medium text-pillado-green-700 hover:bg-pillado-green-100"
          >
            <RefreshCw className="h-3 w-3" />
            Renovar
          </button>
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

  // Modal state
  const [modalOpen, setModalOpen] = useState(false)
  const [modalTitle, setModalTitle] = useState('Nueva Certificacion')
  const [modalInitial, setModalInitial] = useState<Partial<CertFormData> | undefined>(undefined)

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

  function handleNuevaCertificacion() {
    setModalTitle('Nueva Certificacion')
    setModalInitial(undefined)
    setModalOpen(true)
  }

  function handleRenovar(cert: any) {
    setModalTitle('Renovar Certificacion')
    setModalInitial({
      activo_id: cert.activo_id,
      tipo: cert.tipo,
      numero_certificado: cert.numero_certificado ?? '',
      entidad_certificadora: cert.entidad_certificadora ?? '',
      bloqueante: cert.bloqueante ?? false,
      fecha_emision: '',
      fecha_vencimiento: '',
    })
    setModalOpen(true)
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <h1 className="text-2xl font-bold text-gray-900">Cumplimiento Documental</h1>
        <Button variant="primary" onClick={handleNuevaCertificacion}>
          <Plus className="mr-2 h-4 w-4" />
          Nueva Certificacion
        </Button>
      </div>

      {/* Stats */}
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <StatCard
          title="Total Certificaciones"
          value={stats?.total ?? '--'}
          icon={ShieldCheck}
          color="blue"
        />
        <StatCard
          title="Vigentes"
          value={stats?.vigentes ?? '--'}
          icon={CheckCircle2}
          color="green"
        />
        <StatCard
          title="Por Vencer"
          value={stats?.por_vencer ?? '--'}
          icon={Calendar}
          color="orange"
        />
        <StatCard
          title="Vencidas"
          value={stats?.vencidas ?? '--'}
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
                      <TableHead>N Certificado</TableHead>
                      <TableHead>Entidad</TableHead>
                      <TableHead>Emision</TableHead>
                      <TableHead>Vencimiento</TableHead>
                      <TableHead>Estado</TableHead>
                      <TableHead className="text-center">Bloqueante</TableHead>
                      <TableHead className="text-center">Acciones</TableHead>
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
                                {activo?.codigo || '--'}
                              </p>
                              <p className="text-xs text-gray-500">
                                {activo?.nombre || '--'}
                              </p>
                            </div>
                          </TableCell>
                          <TableCell>{getTipoBadge(cert.tipo)}</TableCell>
                          <TableCell className="text-sm text-gray-700">
                            {cert.numero_certificado || '--'}
                          </TableCell>
                          <TableCell className="text-sm text-gray-700">
                            {cert.entidad_certificadora || '--'}
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
                          <TableCell className="text-center">
                            <button
                              onClick={() => handleRenovar(cert)}
                              className="inline-flex items-center gap-1 rounded-lg bg-pillado-green-50 px-3 py-1.5 text-xs font-medium text-pillado-green-700 hover:bg-pillado-green-100"
                              title="Renovar certificacion"
                            >
                              <RefreshCw className="h-3 w-3" />
                              Renovar
                            </button>
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
                  <MobileCard key={cert.id} cert={cert} onRenovar={handleRenovar} />
                ))}
              </div>
            </>
          )}
        </>
      )}

      {/* Modal */}
      <CertificacionModal
        open={modalOpen}
        onClose={() => setModalOpen(false)}
        initialData={modalInitial}
        title={modalTitle}
      />
    </div>
  )
}
