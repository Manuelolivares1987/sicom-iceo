'use client'

import { useState, useRef, useEffect } from 'react'
import { useQuery, useQueryClient, useMutation } from '@tanstack/react-query'
import { useParams } from 'next/navigation'
import Link from 'next/link'
import { useAuth } from '@/contexts/auth-context'
import {
  getJornadasDeOT, getChecklistV3OT, type ChecklistV3Item,
  rpcV3SetTiempo, rpcV3SetExcluido, rpcV3AgregarItem, rpcV3EliminarCustom,
  rpcLiberarEjecucion, rpcReabrirPreparacion,
} from '@/lib/services/taller-plan-semanal'
import {
  actualizarItem as actualizarItemV3,
  subirFotoItem as subirFotoItemV3,
  BLOQUE_LABELS,
} from '@/lib/services/checklist-v2'
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
  DollarSign,
  Plus,
  Search,
  Loader2,
  Pencil,
  Clock,
  Lock,
  Unlock,
  Trash2,
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
  useEvidenciasOT,
  useMaterialesOT,
  useHistorialOT,
  useIniciarOT,
  usePausarOT,
  useFinalizarOT,
  useNoEjecutarOT,
  useCerrarOTSupervisor,
  useAddEvidencia,
  useUpdateOT,
} from '@/hooks/use-ordenes-trabajo'
import { PanelMateriales } from '@/components/ot/panel-materiales'
import { useBuscarProductos } from '@/hooks/use-ot-materiales'
import { useStockBodega, useBodegas, useRegistrarSalida } from '@/hooks/use-inventario'
import { supabase } from '@/lib/supabase'
import { calcularKPIs } from '@/lib/services/kpi-iceo'
import { OTInfoHeader } from '@/components/ot/ot-info-header'
import { OTActionBar } from '@/components/ot/ot-action-bar'
import { isImmutableState, isAwaitingClosure } from '@/domain/ot/transitions'

// ---------------------------------------------------------------------------
// Tabs
// ---------------------------------------------------------------------------
const tabs = [
  { id: 'checklist', label: 'Checklist', icon: ClipboardList },
  { id: 'evidencias', label: 'Evidencias', icon: ImageIcon },
  { id: 'materiales', label: 'Materiales', icon: Package },
  { id: 'valorizacion', label: 'Costos', icon: DollarSign },
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

function bloqueLabel(b: string): string {
  const known = (BLOQUE_LABELS as Record<string, string>)[b]
  if (known) return known
  const t = b.replace(/^b[0-9]*_?/i, '').replace(/_/g, ' ').trim() || b
  return t.charAt(0).toUpperCase() + t.slice(1)
}

function ChecklistTab({
  otId, mode, readOnly, liberadoAt, onLiberar, onReabrir, liberando, reabriendo,
}: {
  otId: string
  mode: 'edit' | 'exec'
  readOnly?: boolean
  liberadoAt?: string | null
  onLiberar: () => void
  onReabrir: () => void
  liberando?: boolean
  reabriendo?: boolean
}) {
  const qc = useQueryClient()
  const { data: items, isLoading } = useQuery({
    queryKey: ['checklist-v3', otId], queryFn: () => getChecklistV3OT(otId), enabled: !!otId,
  })
  // estado ejecución
  const [observations, setObservations] = useState<Record<string, string>>({})
  const [savingId, setSavingId] = useState<string | null>(null)
  const [uploadingItemId, setUploadingItemId] = useState<string | null>(null)
  const fileInputRefs = useRef<Record<string, HTMLInputElement | null>>({})
  // estado edición (jefe)
  const [tiempos, setTiempos] = useState<Record<string, string>>({})
  const [nuevaTarea, setNuevaTarea] = useState('')
  const [nuevoTiempo, setNuevoTiempo] = useState('')
  const [busy, setBusy] = useState(false)

  function invalidate() { qc.invalidateQueries({ queryKey: ['checklist-v3', otId] }) }

  // — ejecución —
  async function setResultado(it: ChecklistV3Item, v: 'ok' | 'no_ok' | 'na') {
    setSavingId(it.instance_item_id)
    try {
      await actualizarItemV3(it.instance_item_id, {
        resultado: v, observacion: observations[it.instance_item_id] ?? it.observacion ?? undefined,
      })
      invalidate()
    } catch { /* retry */ } finally { setSavingId(null) }
  }
  async function saveObs(it: ChecklistV3Item) {
    const o = observations[it.instance_item_id]
    if (o === undefined || o === (it.observacion ?? '')) return
    try { await actualizarItemV3(it.instance_item_id, { observacion: o }); invalidate() } catch { /* retry */ }
  }
  async function handlePhoto(it: ChecklistV3Item, file: File) {
    setUploadingItemId(it.instance_item_id)
    try {
      const url = await subirFotoItemV3(it.instance_id, it.instance_item_id, file)
      await actualizarItemV3(it.instance_item_id, { foto_url: url })
      invalidate()
    } catch { /* retry */ } finally { setUploadingItemId(null) }
  }
  // — edición (jefe) —
  async function guardarTiempo(it: ChecklistV3Item) {
    const raw = tiempos[it.instance_item_id]
    if (raw === undefined) return
    const nuevo = raw ? Number(raw) : null
    if (nuevo === (it.tiempo_min ?? null)) return
    try { await rpcV3SetTiempo(it.instance_item_id, nuevo); invalidate() } catch { /* retry */ }
  }
  async function toggleExcluido(it: ChecklistV3Item) {
    try { await rpcV3SetExcluido(it.instance_item_id, !it.excluido); invalidate() } catch { /* retry */ }
  }
  async function eliminarCustom(it: ChecklistV3Item) {
    try { await rpcV3EliminarCustom(it.instance_item_id); invalidate() } catch { /* retry */ }
  }
  async function agregarTarea() {
    if (!nuevaTarea.trim()) return
    setBusy(true)
    try {
      await rpcV3AgregarItem(otId, nuevaTarea.trim(), nuevoTiempo ? Number(nuevoTiempo) : null)
      setNuevaTarea(''); setNuevoTiempo(''); invalidate()
    } catch { /* retry */ } finally { setBusy(false) }
  }

  if (isLoading) {
    return <div className="flex justify-center py-8"><Spinner size="md" className="text-pillado-green-500" /></div>
  }

  const all = items ?? []
  // edición: ver todo (incl. excluidos); ejecución: ocultar excluidos
  const visibles = mode === 'edit' ? all : all.filter((i) => !i.excluido)
  if (all.length === 0) {
    return <p className="py-8 text-center text-gray-400">Esta OT no tiene checklist</p>
  }

  const grupos: { bloque: string; items: ChecklistV3Item[] }[] = []
  for (const it of visibles) {
    let g = grupos.find((x) => x.bloque === it.bloque)
    if (!g) { g = { bloque: it.bloque, items: [] }; grupos.push(g) }
    g.items.push(it)
  }
  const activos = all.filter((i) => !i.excluido)
  const hechos = activos.filter((i) => i.resultado && i.resultado !== 'pendiente').length
  const tiempoTotal = activos.reduce((s, i) => s + (i.tiempo_min ?? 0), 0)

  return (
    <div className="space-y-4">
      {/* Banner de modo / handoff */}
      {mode === 'edit' && (
        <div className="rounded-lg bg-amber-50 border border-amber-200 p-3 text-sm">
          <div className="flex items-center gap-2 text-amber-800 font-medium">
            <Pencil className="h-4 w-4 shrink-0" /> Preparación del jefe de taller
          </div>
          <p className="mt-1 text-amber-700 text-xs">
            Ajusta los tiempos, marca las tareas que no aplican y agrega las que falten.
            Cuando esté listo, libera a ejecución.
          </p>
          <div className="mt-2">
            <Button variant="primary" onClick={onLiberar} disabled={liberando}>
              {liberando ? <Spinner size="sm" className="mr-1" /> : <Unlock className="h-4 w-4 mr-1" />}
              Liberar a ejecución
            </Button>
          </div>
        </div>
      )}
      {mode === 'exec' && !readOnly && liberadoAt && (
        <div className="flex flex-wrap items-center gap-2 rounded-lg bg-green-50 border border-green-200 p-3 text-sm text-green-700">
          <CheckCircle2 className="h-4 w-4 shrink-0" />
          <span>Liberado a ejecución el {formatDateTime(liberadoAt)}.</span>
          <button onClick={onReabrir} disabled={reabriendo}
                  className="ml-auto inline-flex items-center gap-1 rounded-lg border border-amber-300 bg-white px-2 py-1 text-xs text-amber-700 hover:bg-amber-50 disabled:opacity-50">
            <Lock className="h-3.5 w-3.5" /> Reabrir preparación
          </button>
        </div>
      )}
      {readOnly && (
        <div className="flex items-center gap-2 rounded-lg bg-amber-50 border border-amber-200 p-3 text-sm text-amber-700">
          <AlertTriangle className="h-4 w-4 shrink-0" /> Esta OT está cerrada. El checklist no puede modificarse.
        </div>
      )}

      <div className="flex flex-wrap items-center gap-3 rounded-lg bg-blue-50 border border-blue-200 p-3 text-sm text-blue-700">
        <span className="font-semibold">{hechos}/{activos.length} tareas</span>
        <span className="text-blue-400">|</span>
        <span>{tiempoTotal} min ({(tiempoTotal / 60).toFixed(1)} h) estimados</span>
      </div>

      {grupos.map((g) => {
        const tBloque = g.items.filter((i) => !i.excluido).reduce((s, i) => s + (i.tiempo_min ?? 0), 0)
        return (
          <div key={g.bloque}>
            <div className="flex items-center justify-between rounded-t-lg bg-gray-100 px-3 py-2">
              <h4 className="text-sm font-semibold text-gray-700">{bloqueLabel(g.bloque)}</h4>
              <span className="text-xs text-gray-500">{g.items.filter((i) => !i.excluido).length} · {tBloque} min</span>
            </div>
            <div className="space-y-2 pt-2">
              {g.items.map((item, idx) => mode === 'edit' ? (
                /* ───── modo preparación (jefe) ───── */
                <Card key={item.instance_item_id} className={item.excluido ? 'opacity-60' : ''}>
                  <CardContent className="p-3">
                    <div className="flex items-center gap-2">
                      {item.codigo && <span className="text-[10px] font-mono text-gray-400 shrink-0">{item.codigo}</span>}
                      <span className={`flex-1 text-sm ${item.excluido ? 'line-through text-gray-400' : 'text-gray-800'}`}>
                        {item.descripcion}
                        {item.requiere_foto && <Camera className="inline h-3 w-3 ml-1 text-blue-500" />}
                        {item.critico && <span className="ml-1 text-[9px] px-1 rounded bg-red-100 text-red-700">crítica</span>}
                        {item.es_custom && <span className="ml-1 text-[9px] px-1 rounded bg-purple-100 text-purple-700">añadida</span>}
                      </span>
                      <Clock className="h-3.5 w-3.5 text-gray-400 shrink-0" />
                      <input
                        type="number" min="0" placeholder="min" disabled={item.excluido}
                        value={tiempos[item.instance_item_id] ?? (item.tiempo_min != null ? String(item.tiempo_min) : '')}
                        onChange={(e) => setTiempos((p) => ({ ...p, [item.instance_item_id]: e.target.value }))}
                        onBlur={() => guardarTiempo(item)}
                        className="h-8 w-16 rounded-lg border border-gray-300 px-2 text-sm disabled:bg-gray-100"
                      />
                      {item.es_custom ? (
                        <button onClick={() => eliminarCustom(item)} title="Eliminar tarea añadida"
                                className="rounded-lg bg-red-50 px-1.5 py-1 text-red-600 hover:bg-red-100">
                          <Trash2 className="h-4 w-4" />
                        </button>
                      ) : (
                        <button onClick={() => toggleExcluido(item)}
                                title={item.excluido ? 'Incluir en esta OT' : 'No aplica a esta OT'}
                                className={`rounded-lg px-2 py-1 text-xs ${item.excluido
                                  ? 'bg-green-100 text-green-700 hover:bg-green-200'
                                  : 'bg-gray-100 text-gray-600 hover:bg-gray-200'}`}>
                          {item.excluido ? 'Incluir' : 'No aplica'}
                        </button>
                      )}
                    </div>
                  </CardContent>
                </Card>
              ) : (
                /* ───── modo ejecución (ejecutor) ───── */
                <Card key={item.instance_item_id}>
                  <CardContent className="p-4">
                    <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
                      <div className="flex-1">
                        <div className="flex items-center gap-1.5">
                          {item.codigo && <span className="text-[10px] font-mono text-gray-400">{item.codigo}</span>}
                          <p className="text-sm font-medium text-gray-900">{idx + 1}. {item.descripcion}</p>
                          {item.requiere_foto && (
                            <span title="Requiere foto"><Camera className="h-3.5 w-3.5 text-blue-500 shrink-0" /></span>
                          )}
                          {item.critico && <span className="text-[9px] px-1 rounded bg-red-100 text-red-700 font-medium">crítica</span>}
                          {item.es_custom && <span className="text-[9px] px-1 rounded bg-purple-100 text-purple-700">añadida</span>}
                          {item.tiempo_min != null && <span className="text-[10px] text-gray-400">· {item.tiempo_min} min</span>}
                        </div>
                        {item.resultado === 'no_ok' && (
                          <p className="mt-1 text-xs font-medium text-red-600 flex items-center gap-1">
                            <AlertTriangle className="h-3 w-3" /> NO OK — generará No Conformidad
                          </p>
                        )}
                      </div>
                      <ResultRadio
                        value={item.resultado}
                        disabled={readOnly || savingId === item.instance_item_id}
                        onChange={(v) => setResultado(item, v as 'ok' | 'no_ok' | 'na')}
                      />
                    </div>

                    {item.foto_url && (
                      <div className="mt-2">
                        {/* eslint-disable-next-line @next/next/no-img-element */}
                        <img src={item.foto_url} alt={`Foto ${idx + 1}`}
                             className="h-20 w-20 rounded-lg border border-gray-200 object-cover" />
                      </div>
                    )}

                    <div className="mt-3 flex gap-2">
                      <input
                        type="text" placeholder="Observación..." disabled={readOnly}
                        value={observations[item.instance_item_id] ?? item.observacion ?? ''}
                        onChange={(e) => setObservations((prev) => ({ ...prev, [item.instance_item_id]: e.target.value }))}
                        onBlur={() => saveObs(item)}
                        className="flex-1 rounded-lg border border-gray-200 px-3 py-2 text-sm placeholder:text-gray-400 focus:border-pillado-green-500 focus:outline-none disabled:bg-gray-100 disabled:opacity-50"
                      />
                      <button
                        type="button" disabled={readOnly || uploadingItemId === item.instance_item_id}
                        onClick={() => fileInputRefs.current[item.instance_item_id]?.click()}
                        className={`flex h-10 w-10 items-center justify-center rounded-lg border transition-colors disabled:opacity-50 ${
                          item.foto_url ? 'border-green-300 bg-green-50 text-green-600'
                            : item.requiere_foto ? 'border-blue-300 bg-blue-50 text-blue-600 hover:bg-blue-100'
                            : 'border-gray-200 text-gray-500 hover:bg-blue-50 hover:text-blue-600 hover:border-blue-300'}`}
                      >
                        {uploadingItemId === item.instance_item_id ? <Loader2 className="h-4 w-4 animate-spin" /> : <Camera className="h-4 w-4" />}
                      </button>
                      <input
                        ref={(el) => { fileInputRefs.current[item.instance_item_id] = el }}
                        type="file" accept="image/*" capture="environment" className="hidden"
                        onChange={(e) => { const f = e.target.files?.[0]; if (f) handlePhoto(item, f); e.target.value = '' }}
                      />
                    </div>
                  </CardContent>
                </Card>
              ))}
            </div>
          </div>
        )
      })}

      {/* Agregar tarea (solo en preparación) */}
      {mode === 'edit' && (
        <div className="flex items-end gap-2 border-t pt-3">
          <div className="flex-1">
            <label className="mb-1 block text-xs font-medium text-gray-500">Agregar tarea a esta OT</label>
            <input
              type="text" value={nuevaTarea} onChange={(e) => setNuevaTarea(e.target.value)}
              placeholder="Descripción de la tarea"
              onKeyDown={(e) => { if (e.key === 'Enter') agregarTarea() }}
              className="h-10 w-full rounded-lg border border-gray-300 px-3 text-sm"
            />
          </div>
          <div className="w-20">
            <label className="mb-1 block text-xs font-medium text-gray-500">Min</label>
            <input type="number" min="0" value={nuevoTiempo} onChange={(e) => setNuevoTiempo(e.target.value)}
                   className="h-10 w-full rounded-lg border border-gray-300 px-3 text-sm" />
          </div>
          <Button variant="secondary" onClick={agregarTarea} disabled={!nuevaTarea.trim() || busy}>
            <Plus className="h-4 w-4 mr-1" /> Agregar
          </Button>
        </div>
      )}
    </div>
  )
}

function EvidenciasTab({ otId, disabled }: { otId: string; disabled?: boolean }) {
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

  // Count by tipo
  const countByTipo = evidenciasList.reduce((acc: Record<string, number>, e: any) => {
    const t = e.tipo || 'otro'
    acc[t] = (acc[t] || 0) + 1
    return acc
  }, {} as Record<string, number>)
  const tipoLabels = ['antes', 'durante', 'después', 'documento', 'firma']

  return (
    <div className="space-y-6">
      {/* Summary */}
      {evidenciasList.length > 0 ? (
        <div className="flex flex-wrap items-center gap-2 rounded-lg bg-blue-50 border border-blue-200 p-3 text-sm text-blue-700">
          <span className="font-semibold">{evidenciasList.length} evidencia{evidenciasList.length !== 1 ? 's' : ''} cargada{evidenciasList.length !== 1 ? 's' : ''}</span>
          <span className="text-blue-400">|</span>
          {tipoLabels.filter((t) => countByTipo[t]).map((t) => (
            <Badge key={t} className="bg-blue-100 text-blue-700 text-xs">
              {t.charAt(0).toUpperCase() + t.slice(1)}: {countByTipo[t]}
            </Badge>
          ))}
        </div>
      ) : (
        <div className="flex items-center gap-2 rounded-lg bg-amber-50 border border-amber-200 p-3 text-sm text-amber-700">
          <AlertTriangle className="h-4 w-4 shrink-0" />
          Sin evidencias
        </div>
      )}

      {/* Upload controls */}
      <div className="space-y-3">
        {disabled && (
          <div className="flex items-center gap-2 rounded-lg bg-amber-50 border border-amber-200 p-3 text-sm text-amber-700">
            <AlertTriangle className="h-4 w-4 shrink-0" />
            Esta OT está cerrada. No se puede agregar evidencia.
          </div>
        )}
        {!disabled && !showUploadForm && (
          <Button
            variant="primary"
            size="lg"
            className="w-full sm:w-auto"
            onClick={() => setShowUploadForm(true)}
          >
            <Camera className="h-5 w-5" />
            Subir Evidencia
          </Button>
        )}
        {!disabled && showUploadForm && (
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

function MaterialesTab({ otId, faenaId, activoId, disabled, userId }: { otId: string; faenaId?: string; activoId?: string; disabled?: boolean; userId?: string }) {
  return (
    <div className="space-y-4">
      <PanelMateriales otId={otId} otCerrada={disabled} puedeDespachar />
      <MaterialesMovimientos otId={otId} faenaId={faenaId} activoId={activoId} disabled={disabled} userId={userId} />
    </div>
  )
}

function MaterialesMovimientos({ otId, faenaId, activoId, disabled, userId }: { otId: string; faenaId?: string; activoId?: string; disabled?: boolean; userId?: string }) {
  const { data: materiales, isLoading } = useMaterialesOT(otId)
  const { data: bodegas } = useBodegas(faenaId)
  const [selectedBodega, setSelectedBodega] = useState('')
  const { data: stockData } = useStockBodega(selectedBodega ? { bodega_id: selectedBodega } : undefined)
  const registrarSalida = useRegistrarSalida()

  const [showForm, setShowForm] = useState(false)
  const [selectedProducto, setSelectedProducto] = useState<any>(null)
  const [cantidad, setCantidad] = useState('')
  const [searchTerm, setSearchTerm] = useState('')
  const [formError, setFormError] = useState<string | null>(null)
  const [formSuccess, setFormSuccess] = useState(false)

  // Auto-select first bodega
  const bodegasList = (bodegas ?? []) as any[]
  useEffect(() => {
    if (bodegasList.length > 0 && !selectedBodega) {
      setSelectedBodega(bodegasList[0].id)
    }
  }, [bodegasList.length]) // eslint-disable-line react-hooks/exhaustive-deps

  const stockItems = (stockData ?? []) as any[]
  const stockById = new Map<string, any>()
  for (const s of stockItems) stockById.set(s.producto_id || s.producto?.id, s)
  // Sugerencias sobre TODO el catálogo; el stock de la bodega se anexa por producto.
  const { data: catalogo = [] } = useBuscarProductos(searchTerm)
  const sugerencias = (catalogo as any[]).map((p) => {
    const stk = stockById.get(p.id)
    return {
      producto_id: p.id,
      producto: { id: p.id, nombre: p.nombre, codigo: p.codigo, unidad_medida: p.unidad_medida, costo_unitario_actual: p.costo_unitario_actual },
      cantidad: stk?.cantidad ?? 0,
      costo_promedio: stk?.costo_promedio ?? p.costo_unitario_actual ?? 0,
      bodega_id: selectedBodega,
    }
  })

  function handleRegistrarConsumo() {
    if (!selectedProducto) { setFormError('Seleccione un producto'); return }
    const qty = parseFloat(cantidad)
    if (!qty || qty <= 0) { setFormError('Ingrese una cantidad válida'); return }
    if (qty > (selectedProducto.cantidad ?? 0)) { setFormError('Stock insuficiente'); return }
    if (!userId) { setFormError('Usuario no identificado'); return }

    setFormError(null)
    registrarSalida.mutate(
      {
        bodega_id: selectedBodega,
        producto_id: selectedProducto.producto_id || selectedProducto.producto?.id,
        cantidad: qty,
        ot_id: otId,
        activo_id: activoId || null,
        usuario_id: userId,
        motivo: 'Consumo en OT',
      },
      {
        onSuccess: () => {
          setFormSuccess(true)
          setSelectedProducto(null)
          setCantidad('')
          setSearchTerm('')
          setTimeout(() => setFormSuccess(false), 3000)
        },
        onError: (err: any) => {
          setFormError(err?.message || 'Error al registrar consumo')
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

  const items = (materiales ?? []) as any[]
  const total = items.reduce((s: number, m: any) => s + (m.costo_total ?? m.cantidad * m.costo_unitario), 0)

  return (
    <div>
      {/* Formulario de registro de materiales */}
      {!disabled && (
        <div className="mb-6">
          {!showForm ? (
            <Button variant="primary" className="w-full sm:w-auto" onClick={() => setShowForm(true)}>
              <Plus className="h-4 w-4" />
              Registrar Consumo de Material
            </Button>
          ) : (
            <Card>
              <CardContent className="space-y-3 p-4">
                <h4 className="text-sm font-semibold text-gray-700">Registrar Consumo</h4>
                {bodegasList.length > 1 && (
                  <div>
                    <label className="mb-1 block text-xs font-medium text-gray-500">Bodega</label>
                    <select
                      value={selectedBodega}
                      onChange={(e) => { setSelectedBodega(e.target.value); setSelectedProducto(null) }}
                      className="h-10 w-full rounded-lg border border-gray-300 bg-white px-3 text-sm"
                    >
                      {bodegasList.map((b: any) => (
                        <option key={b.id} value={b.id}>{b.nombre}</option>
                      ))}
                    </select>
                  </div>
                )}
                <div>
                  <label className="mb-1 block text-xs font-medium text-gray-500">Producto</label>
                  {selectedProducto ? (
                    <div className="flex items-center justify-between rounded-lg border border-green-300 bg-green-50 px-3 py-2">
                      <div>
                        <p className="text-sm font-medium text-gray-900">{selectedProducto.producto?.nombre}</p>
                        <p className="text-xs text-gray-500">
                          Stock: {selectedProducto.cantidad} {selectedProducto.producto?.unidad_medida} | Costo: {formatCLP(selectedProducto.costo_promedio ?? selectedProducto.producto?.costo_unitario_actual ?? 0)}
                        </p>
                      </div>
                      <button onClick={() => { setSelectedProducto(null); setSearchTerm('') }} className="text-gray-400 hover:text-gray-600">
                        <X className="h-4 w-4" />
                      </button>
                    </div>
                  ) : (
                    <div className="space-y-2">
                      <div className="relative">
                        <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400" />
                        <input
                          type="text"
                          value={searchTerm}
                          onChange={(e) => setSearchTerm(e.target.value)}
                          placeholder="Buscar por nombre o código..."
                          className="h-10 w-full rounded-lg border border-gray-300 pl-10 pr-3 text-sm"
                        />
                      </div>
                      {searchTerm && sugerencias.length > 0 && (
                        <div className="max-h-40 overflow-y-auto rounded-lg border border-gray-200 bg-white">
                          {sugerencias.slice(0, 8).map((s: any) => (
                            <button
                              key={`${s.producto_id}-${s.bodega_id}`}
                              type="button"
                              onClick={() => { setSelectedProducto(s); setSearchTerm('') }}
                              className="flex w-full items-center justify-between px-3 py-2 text-left text-sm hover:bg-gray-50"
                            >
                              <span className="font-medium">{s.producto?.codigo} · {s.producto?.nombre}</span>
                              <span className={`text-xs ${s.cantidad > 0 ? 'text-gray-500' : 'text-amber-600'}`}>
                                {s.cantidad > 0 ? `${s.cantidad} ${s.producto?.unidad_medida}` : 'sin stock'}
                              </span>
                            </button>
                          ))}
                        </div>
                      )}
                      {searchTerm && sugerencias.length === 0 && (
                        <p className="text-xs text-gray-400">Sin resultados</p>
                      )}
                    </div>
                  )}
                </div>
                <div>
                  <label className="mb-1 block text-xs font-medium text-gray-500">Cantidad</label>
                  <input
                    type="number"
                    value={cantidad}
                    onChange={(e) => setCantidad(e.target.value)}
                    min="0.01"
                    step="0.01"
                    max={selectedProducto?.cantidad ?? undefined}
                    placeholder={selectedProducto ? `Máx: ${selectedProducto.cantidad}` : 'Cantidad'}
                    className="h-10 w-full rounded-lg border border-gray-300 px-3 text-sm"
                  />
                </div>
                {formError && (
                  <div className="flex items-center gap-2 rounded-lg bg-red-50 p-2 text-xs text-red-700">
                    <XCircle className="h-3.5 w-3.5" /> {formError}
                  </div>
                )}
                {formSuccess && (
                  <div className="flex items-center gap-2 rounded-lg bg-green-50 p-2 text-xs text-green-700">
                    <CheckCircle2 className="h-3.5 w-3.5" /> Material registrado correctamente
                  </div>
                )}
                <div className="flex gap-2">
                  <Button
                    variant="primary"
                    onClick={handleRegistrarConsumo}
                    disabled={registrarSalida.isPending || !selectedProducto || !cantidad}
                  >
                    {registrarSalida.isPending ? <Spinner size="sm" className="mr-1" /> : <Plus className="h-4 w-4 mr-1" />}
                    Registrar
                  </Button>
                  <Button variant="secondary" onClick={() => { setShowForm(false); setFormError(null) }}>
                    Cancelar
                  </Button>
                </div>
              </CardContent>
            </Card>
          )}
        </div>
      )}

      {/* Resumen de Costos */}
      {items.length > 0 && (
        <>
          <div className="mb-4 rounded-lg bg-gray-50 border border-gray-200 p-4 flex items-center justify-between">
            <div>
              <p className="text-xs font-medium text-gray-500 uppercase tracking-wider">Resumen de Costos</p>
              <p className="text-sm text-gray-700 mt-1">{items.length} material{items.length !== 1 ? 'es' : ''} consumido{items.length !== 1 ? 's' : ''}</p>
            </div>
            <div className="text-right">
              <p className="text-xs text-gray-500">Costo Total</p>
              <p className="text-lg font-bold text-gray-900">{formatCLP(total)}</p>
            </div>
          </div>

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
        </>
      )}

      {items.length === 0 && !showForm && (
        <div className="py-8 text-center">
          <Package className="mx-auto h-10 w-10 text-gray-300 mb-2" />
          <p className="text-gray-400">No se han registrado materiales en esta OT</p>
        </div>
      )}
    </div>
  )
}

function ValorizacionTab({ ot, otId, userId, disabled }: { ot: any; otId: string; userId: string; disabled?: boolean }) {
  const { data: materialesData } = useMaterialesOT(otId)
  const [horasHombre, setHorasHombre] = useState(String(ot.horas_hombre ?? ''))
  const [tarifaHora, setTarifaHora] = useState(String(ot.tarifa_hora ?? ''))
  const [saving, setSaving] = useState(false)
  const [saved, setSaved] = useState(false)

  const materiales = (materialesData ?? []) as any[]
  const costoMateriales = materiales.reduce((s: number, m: any) => s + (m.costo_total ?? m.cantidad * m.costo_unitario), 0)
  const hh = parseFloat(horasHombre) || 0
  const th = parseFloat(tarifaHora) || 0
  const costoManoObra = hh * th
  const costoTotal = costoMateriales + costoManoObra

  async function handleSaveCostos() {
    setSaving(true)
    try {
      await supabase
        .from('ordenes_trabajo')
        .update({
          horas_hombre: hh,
          tarifa_hora: th,
          costo_mano_obra: costoManoObra,
        })
        .eq('id', otId)
      setSaved(true)
      setTimeout(() => setSaved(false), 3000)
    } catch {
      // silently fail
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="space-y-6">
      {/* Resumen general */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
        <div className="rounded-xl bg-blue-50 border border-blue-200 p-4 text-center">
          <p className="text-xs font-medium text-blue-600 uppercase tracking-wider">Materiales</p>
          <p className="mt-1 text-2xl font-bold text-blue-700">{formatCLP(costoMateriales)}</p>
          <p className="text-xs text-blue-500">{materiales.length} item{materiales.length !== 1 ? 's' : ''}</p>
        </div>
        <div className="rounded-xl bg-purple-50 border border-purple-200 p-4 text-center">
          <p className="text-xs font-medium text-purple-600 uppercase tracking-wider">Mano de Obra</p>
          <p className="mt-1 text-2xl font-bold text-purple-700">{formatCLP(costoManoObra)}</p>
          <p className="text-xs text-purple-500">{hh} hrs x {formatCLP(th)}/hr</p>
        </div>
        <div className="rounded-xl bg-green-50 border border-green-200 p-4 text-center">
          <p className="text-xs font-medium text-green-600 uppercase tracking-wider">Costo Total</p>
          <p className="mt-1 text-2xl font-bold text-green-700">{formatCLP(costoTotal)}</p>
        </div>
      </div>

      {/* Editar costos mano de obra */}
      {!disabled && (
        <Card>
          <CardContent className="space-y-3 p-4">
            <h4 className="text-sm font-semibold text-gray-700">Costos de Mano de Obra</h4>
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="mb-1 block text-xs font-medium text-gray-500">Horas Hombre</label>
                <input
                  type="number"
                  value={horasHombre}
                  onChange={(e) => setHorasHombre(e.target.value)}
                  min="0"
                  step="0.5"
                  placeholder="0"
                  className="h-10 w-full rounded-lg border border-gray-300 px-3 text-sm"
                />
              </div>
              <div>
                <label className="mb-1 block text-xs font-medium text-gray-500">Tarifa/Hora (CLP)</label>
                <input
                  type="number"
                  value={tarifaHora}
                  onChange={(e) => setTarifaHora(e.target.value)}
                  min="0"
                  step="100"
                  placeholder="0"
                  className="h-10 w-full rounded-lg border border-gray-300 px-3 text-sm"
                />
              </div>
            </div>
            <div className="flex items-center gap-3">
              <Button variant="primary" onClick={handleSaveCostos} disabled={saving}>
                {saving ? <Spinner size="sm" className="mr-1" /> : <DollarSign className="h-4 w-4 mr-1" />}
                Guardar Costos
              </Button>
              {saved && (
                <span className="flex items-center gap-1 text-xs text-green-600">
                  <CheckCircle2 className="h-3.5 w-3.5" /> Guardado
                </span>
              )}
            </div>
          </CardContent>
        </Card>
      )}

      {/* Desglose de materiales */}
      {materiales.length > 0 && (
        <div>
          <h4 className="mb-2 text-sm font-semibold text-gray-700">Desglose de Materiales</h4>
          <div className="space-y-1">
            {materiales.map((m: any) => (
              <div key={m.id} className="flex items-center justify-between rounded-lg bg-gray-50 px-3 py-2 text-sm">
                <span>{m.producto?.nombre || m.producto_id}</span>
                <span className="font-medium">
                  {m.cantidad} {m.producto?.unidad_medida} x {formatCLP(m.costo_unitario)} = {formatCLP(m.costo_total ?? m.cantidad * m.costo_unitario)}
                </span>
              </div>
            ))}
          </div>
        </div>
      )}
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
// Editar OT Card
// ---------------------------------------------------------------------------
function EditarOTCard({ otData, otId }: { otData: any; otId: string }) {
  const updateOT = useUpdateOT()
  const [prioridad, setPrioridad] = useState(otData.prioridad || 'normal')
  const [fechaProgramada, setFechaProgramada] = useState(otData.fecha_programada || '')
  const [responsableId, setResponsableId] = useState(otData.responsable_id || '')
  const [observaciones, setObservaciones] = useState(otData.observaciones || '')
  const [responsables, setResponsables] = useState<{id: string; nombre: string}[]>([])
  const [editSuccess, setEditSuccess] = useState(false)
  const [editError, setEditError] = useState<string | null>(null)

  useEffect(() => {
    supabase.from('usuarios_perfil').select('id, nombre_completo').eq('activo', true).order('nombre_completo')
      .then(({ data }) => {
        if (data) setResponsables(data.map(r => ({ id: r.id, nombre: r.nombre_completo })))
      })
  }, [])

  function handleGuardar() {
    setEditError(null)
    setEditSuccess(false)
    updateOT.mutate(
      {
        id: otId,
        data: {
          prioridad,
          fecha_programada: fechaProgramada || null,
          responsable_id: responsableId || null,
          observaciones: observaciones || null,
        },
      },
      {
        onSuccess: () => {
          setEditSuccess(true)
          setTimeout(() => setEditSuccess(false), 4000)
        },
        onError: (err: any) => {
          setEditError(err?.message || 'Error al guardar cambios')
        },
      }
    )
  }

  return (
    <Card className="mb-4 mt-4">
      <CardContent className="p-4 sm:p-6">
        <div className="mb-4 flex items-center gap-2">
          <Pencil className="h-4 w-4 text-pillado-green-600" />
          <h3 className="text-sm font-bold text-gray-900">Editar Orden</h3>
        </div>
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <div>
            <label className="mb-1 block text-xs font-medium text-gray-500">Prioridad</label>
            <select
              value={prioridad}
              onChange={(e) => setPrioridad(e.target.value)}
              className="h-10 w-full rounded-lg border border-gray-300 bg-white px-3 text-sm text-gray-700 focus:border-pillado-green-500 focus:outline-none focus:ring-2 focus:ring-pillado-green-500/20"
            >
              <option value="emergencia">Emergencia</option>
              <option value="urgente">Urgente</option>
              <option value="alta">Alta</option>
              <option value="normal">Normal</option>
              <option value="baja">Baja</option>
            </select>
          </div>
          <div>
            <label className="mb-1 block text-xs font-medium text-gray-500">Fecha Programada</label>
            <input
              type="date"
              value={fechaProgramada}
              onChange={(e) => setFechaProgramada(e.target.value)}
              className="h-10 w-full rounded-lg border border-gray-300 bg-white px-3 text-sm text-gray-700 focus:border-pillado-green-500 focus:outline-none focus:ring-2 focus:ring-pillado-green-500/20"
            />
          </div>
          <div>
            <label className="mb-1 block text-xs font-medium text-gray-500">Responsable</label>
            <select
              value={responsableId}
              onChange={(e) => setResponsableId(e.target.value)}
              className="h-10 w-full rounded-lg border border-gray-300 bg-white px-3 text-sm text-gray-700 focus:border-pillado-green-500 focus:outline-none focus:ring-2 focus:ring-pillado-green-500/20"
            >
              <option value="">Sin asignar</option>
              {responsables.map((r) => (
                <option key={r.id} value={r.id}>{r.nombre}</option>
              ))}
            </select>
          </div>
          <div>
            <label className="mb-1 block text-xs font-medium text-gray-500">Observaciones</label>
            <textarea
              value={observaciones}
              onChange={(e) => setObservaciones(e.target.value)}
              placeholder="Observaciones..."
              rows={2}
              className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm text-gray-700 focus:border-pillado-green-500 focus:outline-none focus:ring-2 focus:ring-pillado-green-500/20"
            />
          </div>
        </div>
        <div className="mt-4 flex items-center gap-3">
          <Button
            variant="primary"
            onClick={handleGuardar}
            disabled={updateOT.isPending}
          >
            {updateOT.isPending ? <Spinner size="sm" className="mr-1" /> : <Pencil className="h-4 w-4 mr-1" />}
            Guardar Cambios
          </Button>
          {editSuccess && (
            <span className="flex items-center gap-1 text-xs text-green-600">
              <CheckCircle2 className="h-3.5 w-3.5" /> Cambios guardados
            </span>
          )}
          {editError && (
            <span className="flex items-center gap-1 text-xs text-red-600">
              <XCircle className="h-3.5 w-3.5" /> {editError}
            </span>
          )}
        </div>
      </CardContent>
    </Card>
  )
}

// ---------------------------------------------------------------------------
// Main page
// ---------------------------------------------------------------------------
function PlanSemanalBanner({ otId }: { otId: string }) {
  const { data: jornadas = [] } = useQuery({ queryKey: ['ot-jornadas', otId], queryFn: () => getJornadasDeOT(otId), enabled: !!otId, staleTime: 30_000 })
  if (jornadas.length === 0) return null
  const cuadrillas = Array.from(new Set(jornadas.map((j) => j.cuadrilla).filter(Boolean))) as string[]
  const responsable = cuadrillas.length ? cuadrillas.join(' · ') : (jornadas.find((j) => j.responsable)?.responsable ?? 'Sin asignar')
  return (
    <div className="mb-4 rounded-lg border border-blue-200 bg-blue-50 p-3">
      <div className="text-sm font-medium text-blue-800">
        📅 Programada en el plan semanal — {jornadas.length} jornada{jornadas.length > 1 ? 's' : ''}
      </div>
      <div className="mt-1.5 flex flex-wrap gap-1.5">
        {jornadas.map((j, i) => (
          <span key={i} className="rounded border border-blue-200 bg-white px-2 py-0.5 text-xs capitalize text-blue-900">
            {(j.dia_nombre ?? '').slice(0, 3)} {new Date(j.dia_fecha + 'T12:00:00').toLocaleDateString('es-CL', { day: '2-digit', month: 'short' })}
            {j.horas_planificadas ? ` · ${j.horas_planificadas}h` : ''}
          </span>
        ))}
      </div>
      <div className="mt-1.5 text-xs text-blue-700">Responsable / cuadrilla del plan: <b>{responsable}</b></div>
    </div>
  )
}

export default function OrdenTrabajoDetailPage() {
  const params = useParams()
  const id = params?.id as string | undefined
  const { user } = useAuth()
  const userId = user?.id ?? ''

  const { data: ot, isLoading, error } = useOrdenTrabajo(id)
  const { data: checklistData } = useQuery({
    queryKey: ['checklist-v3', id], queryFn: () => getChecklistV3OT(id!), enabled: !!id,
  })
  const { data: evidenciasData } = useEvidenciasOT(id)
  const { data: materialesData } = useMaterialesOT(id)

  const [activeTab, setActiveTab] = useState('checklist')

  // Mutations
  const qc = useQueryClient()
  const iniciarMut = useIniciarOT()
  const pausarMut = usePausarOT()
  const finalizarMut = useFinalizarOT()
  const noEjecutarMut = useNoEjecutarOT()
  const cerrarMut = useCerrarOTSupervisor()
  const liberarMut = useMutation({
    mutationFn: () => rpcLiberarEjecucion(id!),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['orden-trabajo', id] }); showSuccess('Checklist liberado a ejecución') },
    onError: (e) => setActionError((e as Error).message),
  })
  const reabrirMut = useMutation({
    mutationFn: () => rpcReabrirPreparacion(id!),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['orden-trabajo', id] }); showSuccess('Preparación reabierta') },
    onError: (e) => setActionError((e as Error).message),
  })

  // Confirmation dialogs
  const [showIniciar, setShowIniciar] = useState(false)
  const [showPausar, setShowPausar] = useState(false)
  const [showFinalizar, setShowFinalizar] = useState(false)
  const [showNoEjecutada, setShowNoEjecutada] = useState(false)
  const [showCerrar, setShowCerrar] = useState(false)
  const [cerrarObs, setCerrarObs] = useState('')
  const [finalizarObs, setFinalizarObs] = useState('')
  const [finalizarError, setFinalizarError] = useState<string | null>(null)
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
  const isOTClosed = isImmutableState(otData.estado)
  const awaitsClosure = isAwaitingClosure(otData.estado)

  // Modo del checklist: el jefe prepara (edita) hasta liberar; luego ejecución.
  const liberado = !!otData.preparacion_ok_at
  const enEjecucionOMas = ['en_ejecucion', 'pausada', 'ejecutada_ok', 'ejecutada_con_observaciones', 'cerrada'].includes(otData.estado)
  const checklistMode: 'edit' | 'exec' = (isOTClosed || liberado || enEjecucionOMas) ? 'exec' : 'edit'

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

      {/* Concordancia con el plan semanal: días programados + cuadrilla */}
      {id && <PlanSemanalBanner otId={id} />}

      {/* Editar OT — only visible for creada/asignada */}
      {(otData.estado === 'creada' || otData.estado === 'asignada') && id && (
        <EditarOTCard otData={otData} otId={id} />
      )}

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
          {activeTab === 'checklist' && id && (
            <ChecklistTab
              otId={id}
              mode={checklistMode}
              readOnly={isOTClosed}
              liberadoAt={otData.preparacion_ok_at}
              onLiberar={() => liberarMut.mutate()}
              onReabrir={() => reabrirMut.mutate()}
              liberando={liberarMut.isPending}
              reabriendo={reabrirMut.isPending}
            />
          )}
          {activeTab === 'evidencias' && id && <EvidenciasTab otId={id} disabled={isOTClosed} />}
          {activeTab === 'materiales' && id && <MaterialesTab otId={id} faenaId={otData.faena_id} activoId={otData.activo_id} disabled={isOTClosed} userId={userId} />}
          {activeTab === 'valorizacion' && id && <ValorizacionTab ot={otData} otId={id} userId={userId} disabled={isOTClosed} />}
          {activeTab === 'historial' && id && <HistorialTab otId={id} />}
        </CardContent>
      </Card>

      {/* Bottom action bar — technician actions */}
      <OTActionBar
        estado={otData.estado}
        onIniciar={() => { clearFeedback(); setShowIniciar(true) }}
        onPausar={() => { clearFeedback(); setShowPausar(true) }}
        onFinalizar={() => { clearFeedback(); setShowFinalizar(true) }}
        onNoEjecutada={() => { clearFeedback(); setShowNoEjecutada(true) }}
        loading={iniciarMut.isPending || pausarMut.isPending || finalizarMut.isPending || noEjecutarMut.isPending}
      />

      {/* Supervisor closure bar — only when OT awaits closure */}
      {awaitsClosure && (
        <div className="fixed bottom-0 left-0 right-0 z-40 border-t border-purple-200 bg-purple-50 p-4 lg:left-64">
          <div className="mx-auto flex max-w-4xl items-center justify-between gap-4">
            <div className="text-sm text-purple-700">
              <span className="font-semibold">Pendiente de cierre supervisor.</span> Revise checklist, evidencia y costos antes de cerrar.
            </div>
            <Button
              variant="primary"
              onClick={() => { clearFeedback(); setShowCerrar(true) }}
              loading={cerrarMut.isPending}
              className="!bg-purple-600 hover:!bg-purple-700 shrink-0"
            >
              Cerrar OT
            </Button>
          </div>
        </div>
      )}

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
        onCancel={() => { setShowFinalizar(false); setFinalizarObs(''); setFinalizarError(null) }}
        onConfirm={() => {
          const pendingMandatory = (checklistData ?? []).filter(
            (item) => !item.excluido && item.obligatorio && (!item.resultado || item.resultado === 'pendiente')
          )
          if (pendingMandatory.length > 0) {
            setFinalizarError(`Hay ${pendingMandatory.length} items obligatorios sin completar en el checklist. Vaya a la tab "Checklist" y complete todos los ítems obligatorios.`)
            return
          }
          if ((evidenciasData ?? []).length === 0) {
            setFinalizarError('No se puede finalizar sin evidencia fotográfica. Vaya a la tab "Evidencias" y suba al menos 1 foto.')
            return
          }
          setFinalizarError(null)
          finalizarMut.mutate(
            { id: id!, userId, observaciones: finalizarObs || undefined },
            {
              onSuccess: () => {
                setShowFinalizar(false)
                setFinalizarObs('')
                showSuccess('OT finalizada correctamente')
                // Auto-recalculate KPIs/ICEO after OT finalization
                if (otData.contrato_id) {
                  const now = new Date()
                  const periodoInicio = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-01`
                  const periodoFin = now.toISOString().slice(0, 10)
                  calcularKPIs(otData.contrato_id, otData.faena_id, periodoInicio, periodoFin)
                    .catch(() => { /* KPI calc failure is non-blocking */ })
                }
              },
              onError: (err: any) => {
                setShowFinalizar(false)
                setActionError(err?.message || 'Error al finalizar la OT')
              },
            }
          )
        }}
      >
        <div className="space-y-3">
          {finalizarError && (
            <div className="flex items-start gap-2 rounded-lg bg-red-50 border border-red-200 p-3 text-sm text-red-700">
              <AlertTriangle className="h-5 w-5 shrink-0 mt-0.5 text-red-500" />
              <div>
                <p className="font-semibold">No se puede finalizar</p>
                <p className="mt-1">{finalizarError}</p>
              </div>
            </div>
          )}
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

      {/* Supervisor closure dialog */}
      <ConfirmDialog
        open={showCerrar}
        title="Cierre Supervisor"
        message={`Cerrará definitivamente la OT ${otData.folio}. Esto congela costos, actualiza plan PM y bloquea toda modificación.`}
        confirmLabel="Cerrar Definitivamente"
        variant="primary"
        loading={cerrarMut.isPending}
        onCancel={() => { setShowCerrar(false); setCerrarObs('') }}
        onConfirm={() => {
          cerrarMut.mutate(
            { id: id!, supervisorId: userId, observaciones: cerrarObs || undefined },
            {
              onSuccess: () => {
                setShowCerrar(false)
                setCerrarObs('')
                showSuccess('OT cerrada definitivamente por supervisor. Recalculando KPIs...')
                // Auto-recalculate KPIs/ICEO after OT closure
                if (otData.contrato_id) {
                  const now = new Date()
                  const periodoInicio = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-01`
                  const periodoFin = now.toISOString().slice(0, 10)
                  calcularKPIs(otData.contrato_id, otData.faena_id, periodoInicio, periodoFin)
                    .then(() => showSuccess('OT cerrada y KPIs actualizados'))
                    .catch(() => { /* KPI calc failure is non-blocking */ })
                }
              },
              onError: (err: any) => {
                setShowCerrar(false)
                setActionError(err?.message || 'Error al cerrar la OT')
              },
            }
          )
        }}
      >
        <div className="space-y-4">
          {/* Resumen de costos para el supervisor */}
          <div className="rounded-lg bg-gray-50 p-3 space-y-2">
            <p className="text-xs font-semibold text-gray-600 uppercase">Resumen de Costos</p>
            <div className="grid grid-cols-2 gap-2 text-sm">
              <div>
                <span className="text-gray-500">Materiales:</span>
                <span className="ml-1 font-mono font-medium">{formatCLP(otData.costo_materiales ?? 0)}</span>
              </div>
              <div>
                <span className="text-gray-500">Mano de obra:</span>
                <span className="ml-1 font-mono font-medium">{formatCLP(otData.costo_mano_obra ?? 0)}</span>
              </div>
              <div>
                <span className="text-gray-500">Horas hombre:</span>
                <span className="ml-1 font-mono">{otData.horas_hombre ?? 0} hrs</span>
              </div>
              <div>
                <span className="text-gray-500">Tarifa/hora:</span>
                <span className="ml-1 font-mono">{formatCLP(otData.tarifa_hora ?? 0)}</span>
              </div>
            </div>
            <div className="border-t border-gray-200 pt-2 flex justify-between">
              <span className="font-semibold text-gray-700">Costo Total:</span>
              <span className="font-mono font-bold text-pillado-green-600">
                {formatCLP((otData.costo_materiales ?? 0) + (otData.costo_mano_obra ?? 0))}
              </span>
            </div>
            {(otData.horas_hombre ?? 0) === 0 && (
              <p className="text-xs text-amber-600 flex items-center gap-1">
                <AlertTriangle className="h-3 w-3" />
                Sin horas hombre registradas — el costo de MO puede estar incompleto
              </p>
            )}
          </div>
          {/* Contadores de completitud */}
          <div className="grid grid-cols-3 gap-2 text-center text-xs">
            <div className="rounded bg-green-50 p-2">
              <div className="font-bold text-green-700">{(evidenciasData ?? []).length}</div>
              <div className="text-green-600">Evidencias</div>
            </div>
            <div className="rounded bg-blue-50 p-2">
              <div className="font-bold text-blue-700">
                {(checklistData ?? []).filter((c) => !c.excluido && c.resultado && c.resultado !== 'pendiente').length}/{(checklistData ?? []).filter((c) => !c.excluido).length}
              </div>
              <div className="text-blue-600">Checklist</div>
            </div>
            <div className="rounded bg-purple-50 p-2">
              <div className="font-bold text-purple-700">
                {(materialesData ?? []).length}
              </div>
              <div className="text-purple-600">Materiales</div>
            </div>
          </div>
          {/* Observaciones */}
          <div>
            <label className="mb-1 block text-xs font-medium text-gray-500">
              Observaciones del supervisor (opcional)
            </label>
            <textarea
              value={cerrarObs}
              onChange={(e) => setCerrarObs(e.target.value)}
              placeholder="Observaciones de cierre..."
              rows={3}
              className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-purple-500 focus:outline-none"
            />
          </div>
        </div>
      </ConfirmDialog>
    </div>
  )
}
