'use client'

import { useState, useRef } from 'react'
import { useParams } from 'next/navigation'
import Link from 'next/link'
import { useAuth } from '@/contexts/auth-context'
import {
  ArrowLeft,
  Camera,
  Check,
  X,
  Minus,
  Upload,
  CheckCircle2,
  XCircle,
  Image as ImageIcon,
  ClipboardList,
  Package,
  History,
  AlertTriangle,
} from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Spinner } from '@/components/ui/spinner'
import {
  Table,
  TableHeader,
  TableBody,
  TableRow,
  TableHead,
  TableCell,
} from '@/components/ui/table'
import { formatCLP, formatDate, formatDateTime, getEstadoOTColor, getEstadoOTLabel } from '@/lib/utils'
import {
  useOrdenTrabajo,
  useChecklistOT,
  useEvidenciasOT,
  useMaterialesOT,
  useHistorialOT,
  useIniciarOT,
  usePausarOT,
  useFinalizarOT,
  useNoEjecutarOT,
  useUpdateChecklistItem,
  useAddEvidencia,
} from '@/hooks/use-ordenes-trabajo'
import { OTInfoHeader } from '@/components/ot/ot-info-header'
import { OTActionBar } from '@/components/ot/ot-action-bar'

// ---------------------------------------------------------------------------
// Tabs
// ---------------------------------------------------------------------------
const tabs = [
  { id: 'checklist', label: 'Checklist', icon: ClipboardList },
  { id: 'evidencias', label: 'Evidencias', icon: ImageIcon },
  { id: 'materiales', label: 'Materiales', icon: Package },
  { id: 'historial', label: 'Historial', icon: History },
]

// ---------------------------------------------------------------------------
// Confirmation dialog
// ---------------------------------------------------------------------------
function ConfirmDialog({
  open,
  title,
  message,
  confirmLabel,
  variant = 'primary',
  loading,
  onConfirm,
  onCancel,
  children,
}: {
  open: boolean
  title: string
  message: string
  confirmLabel: string
  variant?: 'primary' | 'danger'
  loading?: boolean
  onConfirm: () => void
  onCancel: () => void
  children?: React.ReactNode
}) {
  if (!open) return null
  return (
    <div className="fixed inset-0 z-[100] flex items-center justify-center bg-black/40 p-4">
      <div className="w-full max-w-md rounded-2xl bg-white p-6 shadow-xl">
        <div className="mb-2 flex items-center gap-2">
          <AlertTriangle className={`h-5 w-5 ${variant === 'danger' ? 'text-red-500' : 'text-pillado-green-500'}`} />
          <h3 className="text-lg font-bold text-gray-900">{title}</h3>
        </div>
        <p className="mb-4 text-sm text-gray-600">{message}</p>
        {children}
        <div className="mt-4 flex justify-end gap-2">
          <Button variant="secondary" onClick={onCancel} disabled={loading}>
            Cancelar
          </Button>
          <Button
            variant={variant === 'danger' ? 'danger' : 'primary'}
            onClick={onConfirm}
            disabled={loading}
          >
            {loading && <Spinner size="sm" className="mr-1" />}
            {confirmLabel}
          </Button>
        </div>
      </div>
    </div>
  )
}

// ---------------------------------------------------------------------------
// Sub-components
// ---------------------------------------------------------------------------
function ResultRadio({
  value,
  onChange,
  disabled,
}: {
  value: string | null
  onChange: (v: string) => void
  disabled?: boolean
}) {
  const options = [
    { val: 'ok', label: 'OK', color: 'bg-green-500', icon: Check },
    { val: 'no_ok', label: 'NO OK', color: 'bg-red-500', icon: X },
    { val: 'na', label: 'N/A', color: 'bg-gray-400', icon: Minus },
  ]
  return (
    <div className="flex gap-2">
      {options.map((o) => {
        const active = value === o.val
        return (
          <button
            key={o.val}
            type="button"
            disabled={disabled}
            onClick={() => onChange(o.val)}
            className={`flex h-9 items-center gap-1 rounded-lg border px-3 text-xs font-semibold transition-colors disabled:opacity-50 ${
              active
                ? `${o.color} border-transparent text-white`
                : 'border-gray-200 bg-white text-gray-500 hover:bg-gray-50'
            }`}
          >
            <o.icon className="h-3.5 w-3.5" />
            {o.label}
          </button>
        )
      })}
    </div>
  )
}

function ChecklistTab({ otId }: { otId: string }) {
  const { data: items, isLoading } = useChecklistOT(otId)
  const updateItem = useUpdateChecklistItem()
  const [observations, setObservations] = useState<Record<string, string>>({})

  if (isLoading) {
    return (
      <div className="flex justify-center py-8">
        <Spinner size="md" className="text-pillado-green-500" />
      </div>
    )
  }

  if (!items || items.length === 0) {
    return <p className="py-8 text-center text-gray-400">No hay items en el checklist</p>
  }

  return (
    <div className="space-y-3">
      {(items as any[]).map((item: any, idx: number) => (
        <Card key={item.id}>
          <CardContent className="p-4">
            <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
              <div className="flex-1">
                <p className="text-sm font-medium text-gray-900">
                  {idx + 1}. {item.descripcion}
                </p>
                {item.observacion && (
                  <p className="mt-1 text-xs text-gray-500">{item.observacion}</p>
                )}
              </div>
              <ResultRadio
                value={item.resultado}
                disabled={updateItem.isPending}
                onChange={(v) => {
                  updateItem.mutate({
                    otId,
                    itemId: item.id,
                    completado: v === 'ok',
                    observacion: observations[item.id] || item.observacion || undefined,
                  })
                }}
              />
            </div>
            <div className="mt-3 flex gap-2">
              <input
                type="text"
                placeholder="Observación..."
                value={observations[item.id] ?? item.observacion ?? ''}
                onChange={(e) =>
                  setObservations((prev) => ({ ...prev, [item.id]: e.target.value }))
                }
                onBlur={() => {
                  const obs = observations[item.id]
                  if (obs !== undefined && obs !== (item.observacion ?? '')) {
                    updateItem.mutate({
                      otId,
                      itemId: item.id,
                      completado: item.resultado === 'ok',
                      observacion: obs,
                    })
                  }
                }}
                className="flex-1 rounded-lg border border-gray-200 px-3 py-2 text-sm placeholder:text-gray-400 focus:border-pillado-green-500 focus:outline-none"
              />
              <button
                type="button"
                className="flex h-10 w-10 items-center justify-center rounded-lg border border-gray-200 text-gray-400 hover:bg-gray-50"
              >
                <Camera className="h-4 w-4" />
              </button>
            </div>
          </CardContent>
        </Card>
      ))}
    </div>
  )
}

function EvidenciasTab({ otId }: { otId: string }) {
  const { data: evidencias, isLoading } = useEvidenciasOT(otId)
  const addEvidencia = useAddEvidencia()
  const fileInputRef = useRef<HTMLInputElement>(null)
  const [uploadTipo, setUploadTipo] = useState('durante')
  const [uploadDesc, setUploadDesc] = useState('')
  const [showUploadForm, setShowUploadForm] = useState(false)
  const [uploadError, setUploadError] = useState<string | null>(null)
  const [uploadSuccess, setUploadSuccess] = useState(false)

  const categorias = ['antes', 'durante', 'después']

  function handleFileSelect(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    if (!file) return

    setUploadError(null)
    setUploadSuccess(false)

    addEvidencia.mutate(
      { otId, archivo: file, tipo: uploadTipo, descripcion: uploadDesc || undefined },
      {
        onSuccess: () => {
          setUploadSuccess(true)
          setUploadDesc('')
          setShowUploadForm(false)
          if (fileInputRef.current) fileInputRef.current.value = ''
          setTimeout(() => setUploadSuccess(false), 3000)
        },
        onError: (err: any) => {
          setUploadError(err?.message || 'Error al subir evidencia')
        },
      }
    )
  }

  if (isLoading) {
    return (
      <div className="flex justify-center py-8">
        <Spinner size="md" className="text-pillado-green-500" />
      </div>
    )
  }

  const evidenciasList = (evidencias ?? []) as any[]

  return (
    <div className="space-y-6">
      {/* Upload controls */}
      <div className="space-y-3">
        {!showUploadForm ? (
          <Button
            variant="primary"
            size="lg"
            className="w-full sm:w-auto"
            onClick={() => setShowUploadForm(true)}
          >
            <Camera className="h-5 w-5" />
            Subir Evidencia
          </Button>
        ) : (
          <Card>
            <CardContent className="space-y-3 p-4">
              <div className="flex gap-3">
                <div className="flex-1">
                  <label className="mb-1 block text-xs font-medium text-gray-500">Tipo</label>
                  <select
                    value={uploadTipo}
                    onChange={(e) => setUploadTipo(e.target.value)}
                    className="h-10 w-full rounded-lg border border-gray-300 bg-white px-3 text-sm"
                  >
                    <option value="antes">Antes</option>
                    <option value="durante">Durante</option>
                    <option value="después">Después</option>
                  </select>
                </div>
                <div className="flex-[2]">
                  <label className="mb-1 block text-xs font-medium text-gray-500">Descripción</label>
                  <input
                    type="text"
                    value={uploadDesc}
                    onChange={(e) => setUploadDesc(e.target.value)}
                    placeholder="Descripción de la foto..."
                    className="h-10 w-full rounded-lg border border-gray-300 px-3 text-sm"
                  />
                </div>
              </div>
              <div className="flex gap-2">
                <Button
                  variant="primary"
                  onClick={() => fileInputRef.current?.click()}
                  disabled={addEvidencia.isPending}
                >
                  {addEvidencia.isPending ? (
                    <Spinner size="sm" className="mr-1" />
                  ) : (
                    <Upload className="mr-1 h-4 w-4" />
                  )}
                  Seleccionar archivo
                </Button>
                <Button variant="secondary" onClick={() => setShowUploadForm(false)}>
                  Cancelar
                </Button>
              </div>
              <input
                ref={fileInputRef}
                type="file"
                accept="image/*"
                capture="environment"
                className="hidden"
                onChange={handleFileSelect}
              />
            </CardContent>
          </Card>
        )}

        {uploadSuccess && (
          <div className="flex items-center gap-2 rounded-lg bg-green-50 p-3 text-sm text-green-700">
            <CheckCircle2 className="h-4 w-4" />
            Evidencia subida correctamente
          </div>
        )}
        {uploadError && (
          <div className="flex items-center gap-2 rounded-lg bg-red-50 p-3 text-sm text-red-700">
            <XCircle className="h-4 w-4" />
            {uploadError}
          </div>
        )}
      </div>

      {/* Evidence by category */}
      {categorias.map((cat) => {
        const fotos = evidenciasList.filter((e: any) => e.tipo === cat)
        return (
          <div key={cat}>
            <h4 className="mb-3 text-sm font-semibold uppercase tracking-wider text-gray-500">
              {cat.charAt(0).toUpperCase() + cat.slice(1)} ({fotos.length})
            </h4>
            {fotos.length === 0 ? (
              <p className="text-sm text-gray-400">Sin evidencias</p>
            ) : (
              <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
                {fotos.map((f: any) => (
                  <div
                    key={f.id}
                    className="group relative aspect-square overflow-hidden rounded-xl border border-gray-200 bg-gray-100"
                  >
                    {f.archivo_url ? (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img
                        src={f.archivo_url}
                        alt={f.descripcion || 'Evidencia'}
                        className="h-full w-full object-cover"
                      />
                    ) : (
                      <div className="flex h-full items-center justify-center">
                        <ImageIcon className="h-10 w-10 text-gray-300" />
                      </div>
                    )}
                    <div className="absolute bottom-0 left-0 right-0 bg-gradient-to-t from-black/60 to-transparent p-2">
                      <p className="text-xs font-medium text-white">{f.descripcion || '—'}</p>
                      <p className="text-[10px] text-white/70">
                        {f.created_at ? formatDateTime(f.created_at) : ''}
                      </p>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        )
      })}

      {evidenciasList.length === 0 && (
        <p className="py-4 text-center text-gray-400">No hay evidencias registradas</p>
      )}
    </div>
  )
}

function MaterialesTab({ otId }: { otId: string }) {
  const { data: materiales, isLoading } = useMaterialesOT(otId)

  if (isLoading) {
    return (
      <div className="flex justify-center py-8">
        <Spinner size="md" className="text-pillado-green-500" />
      </div>
    )
  }

  const items = (materiales ?? []) as any[]

  if (items.length === 0) {
    return <p className="py-8 text-center text-gray-400">No hay materiales registrados</p>
  }

  const total = items.reduce((s: number, m: any) => s + (m.costo_total ?? m.cantidad * m.costo_unitario), 0)

  return (
    <div>
      {/* Desktop */}
      <div className="hidden sm:block">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Producto</TableHead>
              <TableHead className="text-center">Cantidad</TableHead>
              <TableHead className="text-right">Costo Unit.</TableHead>
              <TableHead className="text-right">Costo Total</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {items.map((m: any) => (
              <TableRow key={m.id}>
                <TableCell className="font-medium">
                  {m.producto?.nombre || m.producto_id}
                </TableCell>
                <TableCell className="text-center">
                  {m.cantidad} {m.producto?.unidad_medida || ''}
                </TableCell>
                <TableCell className="text-right">{formatCLP(m.costo_unitario)}</TableCell>
                <TableCell className="text-right font-medium">
                  {formatCLP(m.costo_total ?? m.cantidad * m.costo_unitario)}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>

      {/* Mobile */}
      <div className="space-y-2 sm:hidden">
        {items.map((m: any) => (
          <Card key={m.id}>
            <CardContent className="p-3">
              <p className="text-sm font-medium">{m.producto?.nombre || m.producto_id}</p>
              <div className="mt-1 flex justify-between text-xs text-gray-500">
                <span>
                  {m.cantidad} {m.producto?.unidad_medida || ''} x {formatCLP(m.costo_unitario)}
                </span>
                <span className="font-semibold text-gray-900">
                  {formatCLP(m.costo_total ?? m.cantidad * m.costo_unitario)}
                </span>
              </div>
            </CardContent>
          </Card>
        ))}
      </div>

      <div className="mt-4 flex justify-end border-t border-gray-200 pt-4">
        <div className="text-right">
          <p className="text-sm text-gray-500">Total Materiales</p>
          <p className="text-xl font-bold text-gray-900">{formatCLP(total)}</p>
        </div>
      </div>
    </div>
  )
}

function HistorialTab({ otId }: { otId: string }) {
  const { data: historial, isLoading } = useHistorialOT(otId)

  if (isLoading) {
    return (
      <div className="flex justify-center py-8">
        <Spinner size="md" className="text-pillado-green-500" />
      </div>
    )
  }

  const items = (historial ?? []) as any[]

  if (items.length === 0) {
    return <p className="py-8 text-center text-gray-400">No hay historial registrado</p>
  }

  return (
    <div className="relative ml-4 border-l-2 border-gray-200 pl-6">
      {items.map((h: any, idx: number) => (
        <div key={h.id || idx} className="relative mb-8 last:mb-0">
          <div className="absolute -left-[31px] top-0 flex h-5 w-5 items-center justify-center rounded-full border-2 border-white bg-gray-200">
            <div
              className={`h-2.5 w-2.5 rounded-full ${
                idx === items.length - 1 ? 'bg-pillado-green-500' : 'bg-gray-400'
              }`}
            />
          </div>
          <div>
            <div className="flex flex-wrap items-center gap-2">
              <Badge className={getEstadoOTColor(h.estado_nuevo || h.estado || '')}>
                {getEstadoOTLabel(h.estado_nuevo || h.estado || '')}
              </Badge>
              <span className="text-xs text-gray-400">
                {h.created_at ? formatDateTime(h.created_at) : ''}
              </span>
            </div>
            <p className="mt-1 text-sm text-gray-700">{h.detalle || h.observacion || ''}</p>
            <p className="text-xs text-gray-400">{h.usuario_nombre || h.usuario_id || ''}</p>
          </div>
        </div>
      ))}
    </div>
  )
}

// ---------------------------------------------------------------------------
// Main page
// ---------------------------------------------------------------------------
export default function OrdenTrabajoDetailPage() {
  const params = useParams()
  const id = params?.id as string | undefined
  const { user } = useAuth()
  const userId = user?.id ?? ''

  const { data: ot, isLoading, error } = useOrdenTrabajo(id)

  const [activeTab, setActiveTab] = useState('checklist')

  // Mutations
  const iniciarMut = useIniciarOT()
  const pausarMut = usePausarOT()
  const finalizarMut = useFinalizarOT()
  const noEjecutarMut = useNoEjecutarOT()

  // Confirmation dialogs
  const [showIniciar, setShowIniciar] = useState(false)
  const [showPausar, setShowPausar] = useState(false)
  const [showFinalizar, setShowFinalizar] = useState(false)
  const [showNoEjecutada, setShowNoEjecutada] = useState(false)
  const [finalizarObs, setFinalizarObs] = useState('')
  const [noEjecutadaCausa, setNoEjecutadaCausa] = useState('')
  const [noEjecutadaDetalle, setNoEjecutadaDetalle] = useState('')

  // Error/success feedback
  const [actionError, setActionError] = useState<string | null>(null)
  const [actionSuccess, setActionSuccess] = useState<string | null>(null)

  function clearFeedback() {
    setActionError(null)
    setActionSuccess(null)
  }

  function showSuccess(msg: string) {
    setActionSuccess(msg)
    setTimeout(() => setActionSuccess(null), 4000)
  }

  // Loading state
  if (isLoading) {
    return (
      <div className="flex items-center justify-center py-24">
        <Spinner size="lg" className="text-pillado-green-500" />
      </div>
    )
  }

  if (error || !ot) {
    return (
      <div className="space-y-4 py-12 text-center">
        <p className="text-gray-400">No se pudo cargar la orden de trabajo</p>
        <Link href="/dashboard/ordenes-trabajo">
          <Button variant="secondary">
            <ArrowLeft className="h-4 w-4" />
            Volver
          </Button>
        </Link>
      </div>
    )
  }

  const otData = ot as any

  return (
    <div className="pb-24">
      {/* Back */}
      <Link
        href="/dashboard/ordenes-trabajo"
        className="mb-4 inline-flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700"
      >
        <ArrowLeft className="h-4 w-4" />
        Volver a Ordenes
      </Link>

      {/* Header + Info grid */}
      <OTInfoHeader ot={otData} />

      {/* Feedback */}
      {actionError && (
        <div className="mb-4 flex items-center gap-2 rounded-lg bg-red-50 p-3 text-sm text-red-700">
          <XCircle className="h-4 w-4 shrink-0" />
          {actionError}
          <button onClick={() => setActionError(null)} className="ml-auto text-red-400 hover:text-red-600">
            <X className="h-4 w-4" />
          </button>
        </div>
      )}
      {actionSuccess && (
        <div className="mb-4 flex items-center gap-2 rounded-lg bg-green-50 p-3 text-sm text-green-700">
          <CheckCircle2 className="h-4 w-4 shrink-0" />
          {actionSuccess}
        </div>
      )}

      {/* Tabs */}
      <div className="mb-4 flex gap-1 overflow-x-auto rounded-xl bg-gray-100 p-1">
        {tabs.map((tab) => {
          const Icon = tab.icon
          return (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`flex flex-1 items-center justify-center gap-1.5 whitespace-nowrap rounded-lg px-3 py-2 text-sm font-medium transition-colors ${
                activeTab === tab.id
                  ? 'bg-white text-pillado-green-600 shadow-sm'
                  : 'text-gray-500 hover:text-gray-700'
              }`}
            >
              <Icon className="h-4 w-4" />
              <span className="hidden sm:inline">{tab.label}</span>
            </button>
          )
        })}
      </div>

      {/* Tab content */}
      <Card>
        <CardContent className="p-4 sm:p-6">
          {activeTab === 'checklist' && id && <ChecklistTab otId={id} />}
          {activeTab === 'evidencias' && id && <EvidenciasTab otId={id} />}
          {activeTab === 'materiales' && id && <MaterialesTab otId={id} />}
          {activeTab === 'historial' && id && <HistorialTab otId={id} />}
        </CardContent>
      </Card>

      {/* Bottom action bar */}
      <OTActionBar
        estado={otData.estado}
        onIniciar={() => { clearFeedback(); setShowIniciar(true) }}
        onPausar={() => { clearFeedback(); setShowPausar(true) }}
        onFinalizar={() => { clearFeedback(); setShowFinalizar(true) }}
        onNoEjecutada={() => { clearFeedback(); setShowNoEjecutada(true) }}
        loading={iniciarMut.isPending || pausarMut.isPending || finalizarMut.isPending || noEjecutarMut.isPending}
      />

      {/* Confirmation dialogs */}
      <ConfirmDialog
        open={showIniciar}
        title={otData.estado === 'pausada' ? 'Reanudar OT' : 'Iniciar OT'}
        message={`Se ${otData.estado === 'pausada' ? 'reanudará' : 'iniciará'} la ejecución de ${otData.folio}. ¿Confirma?`}
        confirmLabel={otData.estado === 'pausada' ? 'Reanudar' : 'Iniciar'}
        loading={iniciarMut.isPending}
        onCancel={() => setShowIniciar(false)}
        onConfirm={() => {
          iniciarMut.mutate({ id: id!, userId }, {
            onSuccess: () => {
              setShowIniciar(false)
              showSuccess('OT iniciada correctamente')
            },
            onError: (err: any) => {
              setShowIniciar(false)
              setActionError(err?.message || 'Error al iniciar la OT')
            },
          })
        }}
      />

      <ConfirmDialog
        open={showPausar}
        title="Pausar OT"
        message={`Se pausará la ejecución de ${otData.folio}. ¿Confirma?`}
        confirmLabel="Pausar"
        loading={pausarMut.isPending}
        onCancel={() => setShowPausar(false)}
        onConfirm={() => {
          pausarMut.mutate(
            { id: id!, userId },
            {
              onSuccess: () => {
                setShowPausar(false)
                showSuccess('OT pausada correctamente')
              },
              onError: (err: any) => {
                setShowPausar(false)
                setActionError(err?.message || 'Error al pausar la OT')
              },
            }
          )
        }}
      />

      <ConfirmDialog
        open={showFinalizar}
        title="Finalizar OT"
        message={`Se finalizará ${otData.folio}. Si tiene observaciones, la OT quedará como "Ejecutada con Observaciones".`}
        confirmLabel="Finalizar"
        loading={finalizarMut.isPending}
        onCancel={() => { setShowFinalizar(false); setFinalizarObs('') }}
        onConfirm={() => {
          finalizarMut.mutate(
            { id: id!, userId, observaciones: finalizarObs || undefined },
            {
              onSuccess: () => {
                setShowFinalizar(false)
                setFinalizarObs('')
                showSuccess('OT finalizada correctamente')
              },
              onError: (err: any) => {
                setShowFinalizar(false)
                setActionError(err?.message || 'Error al finalizar la OT')
              },
            }
          )
        }}
      >
        <div>
          <label className="mb-1 block text-xs font-medium text-gray-500">
            Observaciones (opcional)
          </label>
          <textarea
            value={finalizarObs}
            onChange={(e) => setFinalizarObs(e.target.value)}
            placeholder="Agregar observaciones..."
            rows={3}
            className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-pillado-green-500 focus:outline-none"
          />
        </div>
      </ConfirmDialog>

      <ConfirmDialog
        open={showNoEjecutada}
        title="Marcar como No Ejecutada"
        message={`Se marcará ${otData.folio} como no ejecutada. Debe indicar la causa.`}
        confirmLabel="Confirmar"
        variant="danger"
        loading={noEjecutarMut.isPending}
        onCancel={() => {
          setShowNoEjecutada(false)
          setNoEjecutadaCausa('')
          setNoEjecutadaDetalle('')
        }}
        onConfirm={() => {
          if (!noEjecutadaCausa.trim()) {
            setActionError('La causa de no ejecución es obligatoria')
            return
          }
          noEjecutarMut.mutate(
            { id: id!, userId, causa: noEjecutadaCausa, detalle: noEjecutadaDetalle || undefined },
            {
              onSuccess: () => {
                setShowNoEjecutada(false)
                setNoEjecutadaCausa('')
                setNoEjecutadaDetalle('')
                showSuccess('OT marcada como no ejecutada')
              },
              onError: (err: any) => {
                setShowNoEjecutada(false)
                setActionError(err?.message || 'Error al marcar como no ejecutada')
              },
            }
          )
        }}
      >
        <div className="space-y-3">
          <div>
            <label className="mb-1 block text-xs font-medium text-gray-500">
              Causa de no ejecución <span className="text-red-500">*</span>
            </label>
            <input
              type="text"
              value={noEjecutadaCausa}
              onChange={(e) => setNoEjecutadaCausa(e.target.value)}
              placeholder="Ej: Falta de repuestos, condiciones climáticas..."
              className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-pillado-green-500 focus:outline-none"
            />
          </div>
          <div>
            <label className="mb-1 block text-xs font-medium text-gray-500">
              Detalle (opcional)
            </label>
            <textarea
              value={noEjecutadaDetalle}
              onChange={(e) => setNoEjecutadaDetalle(e.target.value)}
              placeholder="Información adicional..."
              rows={3}
              className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-pillado-green-500 focus:outline-none"
            />
          </div>
        </div>
      </ConfirmDialog>
    </div>
  )
}
