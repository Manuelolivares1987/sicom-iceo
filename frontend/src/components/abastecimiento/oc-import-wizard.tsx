'use client'

import { useMemo, useState } from 'react'
import { useRouter } from 'next/navigation'
import {
  Upload, FileText, Check, ArrowLeft, ArrowRight, Save, Trash2, Plus,
  AlertTriangle, AlertCircle, CheckCircle2, X,
} from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Badge } from '@/components/ui/badge'
import { Spinner } from '@/components/ui/spinner'
import { formatCLP, todayISO, cn } from '@/lib/utils'
import { useToast } from '@/contexts/toast-context'
import {
  useProveedoresActivos, useImportarOCExterna, useSubirDocumentoOC,
} from '@/hooks/use-bodega-oc'
import { useProductos } from '@/hooks/use-inventario'
import {
  TIPO_ITEM_OPCIONES, TIPO_ITEM_NO_INVENTARIABLE,
  type TipoItemOC, type ImportarOCExternaPayload,
} from '@/lib/services/bodega-oc'

type StepNum = 1 | 2 | 3 | 4

interface DocumentoState {
  file?: File
  url?: string
  path?: string
  error?: string
}

interface CabeceraState {
  numero_oc_externo: string
  proveedor_id: string
  proveedor_rut: string
  fecha_emision: string
  fecha_entrega: string
  neto_clp: number | ''
  iva_clp: number | ''
  total_clp: number | ''
  forma_pago: string
  observacion: string
}

interface ItemState {
  codigo_externo: string
  descripcion: string
  cantidad_comprada: number | ''
  unidad: string
  unidad_externa: string
  centro_costo_codigo_externo: string
  precio_unitario_clp: number | ''
  tipo_item: TipoItemOC
  requiere_stock: boolean
  producto_id: string | null
  observacion: string
}

const REGEX_SERVICIO = /SERVICIO|CERTIFICAC|OPERATIVIDAD|MANTENIMIENTO|CALIBRAC|REPARAC|TRANSPORT|TRASLADO|ARRIEND|ALQUILE/i

function nuevoItem(): ItemState {
  return {
    codigo_externo: '',
    descripcion: '',
    cantidad_comprada: '',
    unidad: 'unidad',
    unidad_externa: '',
    centro_costo_codigo_externo: '',
    precio_unitario_clp: '',
    tipo_item: 'inventariable',
    requiere_stock: true,
    producto_id: null,
    observacion: '',
  }
}

function tipoBadgeColor(t: TipoItemOC): string {
  switch (t) {
    case 'servicio': return 'bg-purple-100 text-purple-700'
    case 'inventariable': return 'bg-blue-100 text-blue-700'
    case 'combustible': return 'bg-amber-100 text-amber-700'
    case 'lubricante': return 'bg-amber-50 text-amber-800'
    case 'filtro' as TipoItemOC: return 'bg-gray-100 text-gray-700'
    case 'repuesto': return 'bg-cyan-100 text-cyan-700'
    case 'consumible': return 'bg-emerald-100 text-emerald-700'
    case 'activo': return 'bg-indigo-100 text-indigo-700'
    case 'otro': return 'bg-gray-100 text-gray-700'
    default: return 'bg-gray-100 text-gray-700'
  }
}

export function OCImportWizard() {
  const router = useRouter()
  const toast = useToast()
  const [step, setStep] = useState<StepNum>(1)
  const [documento, setDocumento] = useState<DocumentoState | null>(null)
  const [cabecera, setCabecera] = useState<CabeceraState>({
    numero_oc_externo: '',
    proveedor_id: '',
    proveedor_rut: '',
    fecha_emision: todayISO(),
    fecha_entrega: todayISO(),
    neto_clp: '',
    iva_clp: '',
    total_clp: '',
    forma_pago: '30 días',
    observacion: '',
  })
  const [items, setItems] = useState<ItemState[]>([nuevoItem()])

  const { data: proveedores, isLoading: loadProv } = useProveedoresActivos()
  const { data: productosAll, isLoading: loadProd } = useProductos()
  const productos = useMemo(
    () => (productosAll ?? []).map((p) => ({
      id: p.id, codigo: p.codigo, nombre: p.nombre,
      unidad_medida: p.unidad_medida, categoria: p.categoria,
    })),
    [productosAll],
  )

  const subir = useSubirDocumentoOC()
  const importar = useImportarOCExterna()

  const subtotalItems = useMemo(
    () => items.reduce((acc, it) => {
      const cant = typeof it.cantidad_comprada === 'number' ? it.cantidad_comprada : 0
      const prec = typeof it.precio_unitario_clp === 'number' ? it.precio_unitario_clp : 0
      return acc + cant * prec
    }, 0),
    [items],
  )
  const netoNum = typeof cabecera.neto_clp === 'number' ? cabecera.neto_clp : 0
  const ivaNum = typeof cabecera.iva_clp === 'number' ? cabecera.iva_clp : 0
  const totalNum = typeof cabecera.total_clp === 'number' ? cabecera.total_clp : 0
  const diffSubtotalVsNeto = subtotalItems - netoNum
  const diffNetoIvaVsTotal = (netoNum + ivaNum) - totalNum
  const itemsPendientesMapeo = items.filter((it) => it.requiere_stock && !it.producto_id).length

  if (loadProv || loadProd) {
    return <div className="flex justify-center py-10"><Spinner /></div>
  }

  // ── Validaciones por paso ────────────────────────────────────────────────
  const canAdvanceFrom1 = true  // documento opcional
  const canAdvanceFrom2 =
    cabecera.numero_oc_externo.trim().length > 0 &&
    !!cabecera.proveedor_id
  const canAdvanceFrom3 =
    items.length > 0 &&
    items.every((it) => {
      const cant = typeof it.cantidad_comprada === 'number' ? it.cantidad_comprada : 0
      const prec = typeof it.precio_unitario_clp === 'number' ? it.precio_unitario_clp : -1
      return it.descripcion.trim().length > 0 && cant > 0 && prec >= 0
    })

  // ── Submit ────────────────────────────────────────────────────────────────
  const onSubmit = () => {
    const payload: ImportarOCExternaPayload = {
      proveedor_id: cabecera.proveedor_id,
      numero_oc_externo: cabecera.numero_oc_externo.trim(),
      fecha_emision: cabecera.fecha_emision || null,
      fecha_entrega: cabecera.fecha_entrega || null,
      proveedor_rut: cabecera.proveedor_rut.trim() || null,
      neto_clp: typeof cabecera.neto_clp === 'number' ? cabecera.neto_clp : null,
      iva_clp: typeof cabecera.iva_clp === 'number' ? cabecera.iva_clp : null,
      forma_pago: cabecera.forma_pago.trim() || null,
      observacion: cabecera.observacion.trim() || null,
      documento_url: documento?.url ?? null,
      documento_storage_path: documento?.path ?? null,
      items: items.map((it) => ({
        codigo_externo: it.codigo_externo.trim() || null,
        descripcion: it.descripcion.trim(),
        cantidad_comprada: typeof it.cantidad_comprada === 'number' ? it.cantidad_comprada : 0,
        precio_unitario_clp: typeof it.precio_unitario_clp === 'number' ? it.precio_unitario_clp : 0,
        unidad: it.unidad || 'unidad',
        unidad_externa: it.unidad_externa.trim() || null,
        centro_costo_codigo_externo: it.centro_costo_codigo_externo.trim() || null,
        tipo_item: it.tipo_item,
        requiere_stock: it.requiere_stock,
        producto_id: it.producto_id ?? null,
        observacion: it.observacion.trim() || null,
      })),
    }

    importar.mutate(payload, {
      onSuccess: (data) => {
        toast.success(`OC ${data.numero_oc} importada (externa ${data.numero_oc_externo})`)
        router.push(`/dashboard/abastecimiento/oc/${data.orden_compra_id}`)
      },
      onError: (err: unknown) => {
        const msg = err instanceof Error ? err.message : 'Error al importar OC'
        if (msg.toLowerCase().includes('duplicad')) {
          toast.error(`OC duplicada: ya existe una OC ${cabecera.numero_oc_externo} para este proveedor`)
        } else if (msg.toLowerCase().includes('rol') && msg.toLowerCase().includes('autorizado')) {
          toast.error('No tienes permiso para importar OC')
        } else if (msg.toLowerCase().includes('no autenticado')) {
          toast.error('Sesión expirada. Refresca la página.')
        } else {
          toast.error(msg)
        }
      },
    })
  }

  // ── Render ────────────────────────────────────────────────────────────────
  return (
    <div className="space-y-4">
      <div className="flex items-center gap-2">
        <Button type="button" variant="outline" size="sm" onClick={() => router.back()}>
          <ArrowLeft className="h-4 w-4 mr-1" /> Volver
        </Button>
        <h1 className="text-xl font-bold flex items-center gap-2">
          <Upload className="h-5 w-5 text-amber-700" />
          Importar OC externa
        </h1>
      </div>

      <Stepper step={step} />

      {step === 1 && (
        <Step1Documento
          documento={documento}
          onUpload={async (file) => {
            setDocumento({ file })
            const res = await subir.mutateAsync(file).catch((e) => {
              setDocumento({ file, error: e instanceof Error ? e.message : String(e) })
              return null
            })
            if (res) {
              setDocumento({ file, url: res.url, path: res.path })
              toast.success('Documento subido')
            }
          }}
          subiendo={subir.isPending}
          onSkip={() => setStep(2)}
          onNext={() => setStep(2)}
        />
      )}

      {step === 2 && (
        <Step2Cabecera
          cabecera={cabecera}
          setCabecera={setCabecera}
          proveedores={proveedores ?? []}
          onPrev={() => setStep(1)}
          onNext={() => setStep(3)}
          canAdvance={canAdvanceFrom2}
        />
      )}

      {step === 3 && (
        <Step3Items
          items={items}
          setItems={setItems}
          productos={productos}
          subtotal={subtotalItems}
          onPrev={() => setStep(2)}
          onNext={() => setStep(4)}
          canAdvance={canAdvanceFrom3}
          itemsPendientesMapeo={itemsPendientesMapeo}
        />
      )}

      {step === 4 && (
        <Step4Validar
          cabecera={cabecera}
          items={items}
          subtotal={subtotalItems}
          diffSubtotalVsNeto={diffSubtotalVsNeto}
          diffNetoIvaVsTotal={diffNetoIvaVsTotal}
          itemsPendientesMapeo={itemsPendientesMapeo}
          documento={documento}
          onPrev={() => setStep(3)}
          onSubmit={onSubmit}
          loading={importar.isPending}
        />
      )}
    </div>
  )
}

// ── Stepper ──────────────────────────────────────────────────────────────

function Stepper({ step }: { step: StepNum }) {
  const labels = ['Documento', 'Cabecera', 'Items', 'Validar'] as const
  return (
    <div className="flex items-center gap-2 px-1">
      {labels.map((label, idx) => {
        const n = (idx + 1) as StepNum
        const active = step === n
        const done = step > n
        return (
          <div key={label} className="flex items-center gap-2">
            <div className={cn(
              'h-7 w-7 rounded-full flex items-center justify-center text-xs font-bold',
              active && 'bg-amber-700 text-white',
              done && 'bg-green-600 text-white',
              !active && !done && 'bg-gray-200 text-gray-600',
            )}>
              {done ? <Check className="h-4 w-4" /> : n}
            </div>
            <span className={cn(
              'text-xs',
              active ? 'font-bold text-amber-800' : done ? 'text-green-700' : 'text-gray-500',
            )}>{label}</span>
            {idx < labels.length - 1 && (
              <div className={cn('w-6 h-px', done ? 'bg-green-600' : 'bg-gray-300')} />
            )}
          </div>
        )
      })}
    </div>
  )
}

// ── Step 1: Documento ────────────────────────────────────────────────────

function Step1Documento({
  documento, onUpload, subiendo, onSkip, onNext,
}: {
  documento: DocumentoState | null
  onUpload: (f: File) => void
  subiendo: boolean
  onSkip: () => void
  onNext: () => void
}) {
  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Paso 1 · Documento original</CardTitle>
        <p className="text-xs text-gray-600">
          Subí el PDF/imagen/Excel de la OC. Opcional — podés continuar con captura manual.
        </p>
      </CardHeader>
      <CardContent className="space-y-3">
        <label className="flex flex-col items-center justify-center border-2 border-dashed border-gray-300 rounded-lg p-8 cursor-pointer hover:border-amber-400 transition-colors">
          <Upload className="h-8 w-8 text-gray-400 mb-2" />
          <span className="text-sm text-gray-700">
            {subiendo ? 'Subiendo...' : 'Haz click o arrastra un archivo'}
          </span>
          <span className="text-[11px] text-gray-500 mt-1">PDF, imagen o Excel</span>
          <input
            type="file"
            accept=".pdf,image/*,.xlsx,.xls,.csv"
            className="hidden"
            disabled={subiendo}
            onChange={(e) => {
              const f = e.target.files?.[0]
              if (f) onUpload(f)
            }}
          />
        </label>

        {documento?.file && (
          <div className="rounded-lg border border-gray-200 bg-gray-50 p-3 flex items-center gap-2">
            <FileText className="h-5 w-5 text-gray-600 shrink-0" />
            <div className="flex-1 min-w-0">
              <div className="text-sm font-medium truncate">{documento.file.name}</div>
              <div className="text-[11px] text-gray-500">
                {(documento.file.size / 1024).toFixed(1)} KB
                {documento.url && <span className="text-green-700 ml-2">· Subido OK</span>}
                {documento.error && <span className="text-red-700 ml-2">· Error: {documento.error}</span>}
              </div>
            </div>
          </div>
        )}

        {documento?.error && (
          <div className="rounded-lg border border-amber-200 bg-amber-50 p-2 text-xs text-amber-800 flex items-start gap-2">
            <AlertTriangle className="h-4 w-4 mt-0.5 shrink-0" />
            <div>
              La subida falló pero podés continuar igual. El documento queda como pendiente.
            </div>
          </div>
        )}

        <div className="flex items-center justify-between pt-2">
          <Button type="button" variant="outline" onClick={onSkip}>
            Continuar sin documento
          </Button>
          <Button type="button" onClick={onNext} disabled={subiendo}>
            Siguiente <ArrowRight className="h-4 w-4 ml-1" />
          </Button>
        </div>
      </CardContent>
    </Card>
  )
}

// ── Step 2: Cabecera ─────────────────────────────────────────────────────

function Step2Cabecera({
  cabecera, setCabecera, proveedores, onPrev, onNext, canAdvance,
}: {
  cabecera: CabeceraState
  setCabecera: React.Dispatch<React.SetStateAction<CabeceraState>>
  proveedores: Array<{ id: string; codigo: string; nombre: string; tipo: string }>
  onPrev: () => void
  onNext: () => void
  canAdvance: boolean
}) {
  const proveedorSeleccionado = proveedores.find((p) => p.id === cabecera.proveedor_id)
  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Paso 2 · Cabecera de la OC</CardTitle>
        <p className="text-xs text-gray-600">
          Datos del documento. Auto-detectados o ingresados manualmente.
        </p>
      </CardHeader>
      <CardContent className="space-y-3">
        <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">
              N° OC externo *
            </label>
            <Input
              value={cabecera.numero_oc_externo}
              onChange={(e) => setCabecera({ ...cabecera, numero_oc_externo: e.target.value })}
              placeholder="ej: 13559"
            />
          </div>
          <div className="md:col-span-2">
            <label className="block text-xs font-medium text-gray-700 mb-1">
              Proveedor *
            </label>
            <select
              value={cabecera.proveedor_id}
              onChange={(e) => {
                const p = proveedores.find((pp) => pp.id === e.target.value)
                setCabecera({
                  ...cabecera,
                  proveedor_id: e.target.value,
                  // Auto-rellena el RUT snapshot si el proveedor lo tiene en su perfil; el snapshot
                  // queda editable para el caso "en el PDF el RUT difiere del maestro".
                  proveedor_rut: cabecera.proveedor_rut || (p ? '' : ''),
                })
              }}
              className="w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-sm"
            >
              <option value="">— Selecciona proveedor —</option>
              {proveedores.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.codigo} — {p.nombre} [{p.tipo}]
                </option>
              ))}
            </select>
            {proveedorSeleccionado && (
              <div className="text-[11px] text-gray-600 mt-1">{proveedorSeleccionado.nombre}</div>
            )}
          </div>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">RUT proveedor (snapshot)</label>
            <Input
              value={cabecera.proveedor_rut}
              onChange={(e) => setCabecera({ ...cabecera, proveedor_rut: e.target.value })}
              placeholder="76.284.920-8"
            />
          </div>
          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">Fecha emisión</label>
            <Input
              type="date"
              value={cabecera.fecha_emision}
              onChange={(e) => setCabecera({ ...cabecera, fecha_emision: e.target.value })}
            />
          </div>
          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">Fecha entrega</label>
            <Input
              type="date"
              value={cabecera.fecha_entrega}
              onChange={(e) => setCabecera({ ...cabecera, fecha_entrega: e.target.value })}
            />
          </div>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">Neto CLP</label>
            <Input
              type="number"
              step="1"
              min="0"
              value={cabecera.neto_clp}
              onChange={(e) => setCabecera({
                ...cabecera,
                neto_clp: e.target.value === '' ? '' : Number(e.target.value),
              })}
            />
          </div>
          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">IVA CLP</label>
            <Input
              type="number"
              step="1"
              min="0"
              value={cabecera.iva_clp}
              onChange={(e) => setCabecera({
                ...cabecera,
                iva_clp: e.target.value === '' ? '' : Number(e.target.value),
              })}
            />
          </div>
          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">Total CLP</label>
            <Input
              type="number"
              step="1"
              min="0"
              value={cabecera.total_clp}
              onChange={(e) => setCabecera({
                ...cabecera,
                total_clp: e.target.value === '' ? '' : Number(e.target.value),
              })}
            />
          </div>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">Forma de pago</label>
            <Input
              value={cabecera.forma_pago}
              onChange={(e) => setCabecera({ ...cabecera, forma_pago: e.target.value })}
              placeholder="ej: 30 días"
            />
          </div>
          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">Observación</label>
            <Input
              value={cabecera.observacion}
              onChange={(e) => setCabecera({ ...cabecera, observacion: e.target.value })}
              placeholder="Notas internas"
            />
          </div>
        </div>

        <div className="flex items-center justify-between pt-2">
          <Button type="button" variant="outline" onClick={onPrev}>
            <ArrowLeft className="h-4 w-4 mr-1" /> Atrás
          </Button>
          <Button type="button" onClick={onNext} disabled={!canAdvance}>
            Siguiente <ArrowRight className="h-4 w-4 ml-1" />
          </Button>
        </div>
      </CardContent>
    </Card>
  )
}

// ── Step 3: Items ────────────────────────────────────────────────────────

function Step3Items({
  items, setItems, productos, subtotal, onPrev, onNext, canAdvance, itemsPendientesMapeo,
}: {
  items: ItemState[]
  setItems: React.Dispatch<React.SetStateAction<ItemState[]>>
  productos: Array<{ id: string; codigo: string; nombre: string; unidad_medida: string; categoria: string }>
  subtotal: number
  onPrev: () => void
  onNext: () => void
  canAdvance: boolean
  itemsPendientesMapeo: number
}) {
  const setItem = (idx: number, patch: Partial<ItemState>) => {
    setItems((prev) => prev.map((it, i) => (i === idx ? { ...it, ...patch } : it)))
  }
  const addItem = () => setItems((prev) => [...prev, nuevoItem()])
  const removeItem = (idx: number) => setItems((prev) => prev.filter((_, i) => i !== idx))

  // Heuristica al cambiar descripcion: si contiene palabras clave, sugerir servicio
  const onDescripcionChange = (idx: number, desc: string) => {
    const sugiereServicio = REGEX_SERVICIO.test(desc)
    setItems((prev) => prev.map((it, i) => {
      if (i !== idx) return it
      // Solo sugerir si el usuario no ha cambiado explicitamente tipo_item
      if (it.tipo_item === 'inventariable' && sugiereServicio) {
        return { ...it, descripcion: desc, tipo_item: 'servicio', requiere_stock: false }
      }
      return { ...it, descripcion: desc }
    }))
  }

  const onProductoChange = (idx: number, productoId: string) => {
    if (!productoId) {
      setItem(idx, { producto_id: null })
      return
    }
    const p = productos.find((pp) => pp.id === productoId)
    if (!p) { setItem(idx, { producto_id: productoId }); return }
    const tipoSugerido: TipoItemOC =
      p.categoria === 'combustible' ? 'combustible'
      : p.categoria === 'lubricante' ? 'lubricante'
      : p.categoria === 'filtro' ? 'inventariable'
      : p.categoria === 'repuesto' ? 'repuesto'
      : p.categoria === 'consumible' ? 'consumible'
      : 'inventariable'
    setItem(idx, {
      producto_id: productoId,
      descripcion: items[idx].descripcion || p.nombre,
      unidad: items[idx].unidad || p.unidad_medida,
      tipo_item: tipoSugerido,
      requiere_stock: !TIPO_ITEM_NO_INVENTARIABLE.includes(tipoSugerido),
    })
  }

  const onTipoChange = (idx: number, tipo: TipoItemOC) => {
    setItem(idx, {
      tipo_item: tipo,
      requiere_stock: !TIPO_ITEM_NO_INVENTARIABLE.includes(tipo),
    })
  }

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between">
          <div>
            <CardTitle className="text-base">Paso 3 · Items ({items.length})</CardTitle>
            <p className="text-xs text-gray-600">
              Subtotal: <span className="font-mono font-semibold">{formatCLP(subtotal)}</span>
              {itemsPendientesMapeo > 0 && (
                <span className="ml-3 text-amber-700">
                  · {itemsPendientesMapeo} pendiente(s) de mapeo producto
                </span>
              )}
            </p>
          </div>
          <Button type="button" size="sm" variant="outline" onClick={addItem}>
            <Plus className="h-4 w-4 mr-1" /> Agregar ítem
          </Button>
        </div>
      </CardHeader>
      <CardContent className="space-y-3">
        {items.map((it, idx) => (
          <div key={idx} className="rounded-lg border border-gray-200 bg-white p-3 space-y-2">
            <div className="flex items-center justify-between">
              <span className="text-xs font-semibold text-gray-600">Item {idx + 1}</span>
              <div className="flex items-center gap-2">
                <Badge className={tipoBadgeColor(it.tipo_item)}>{it.tipo_item}</Badge>
                {it.requiere_stock ? (
                  <Badge className="bg-blue-100 text-blue-700">requiere stock</Badge>
                ) : (
                  <Badge className="bg-gray-100 text-gray-700">sin stock</Badge>
                )}
                {it.requiere_stock && !it.producto_id && (
                  <Badge className="bg-amber-100 text-amber-700">pendiente mapeo</Badge>
                )}
                {items.length > 1 && (
                  <button
                    type="button"
                    onClick={() => removeItem(idx)}
                    className="text-red-600 hover:bg-red-50 rounded p-1"
                  >
                    <Trash2 className="h-4 w-4" />
                  </button>
                )}
              </div>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-3 gap-2">
              <div>
                <label className="block text-xs font-medium text-gray-700 mb-1">Código externo</label>
                <Input
                  value={it.codigo_externo}
                  onChange={(e) => setItem(idx, { codigo_externo: e.target.value })}
                  placeholder="ej: SERSEGCER006"
                />
              </div>
              <div className="md:col-span-2">
                <label className="block text-xs font-medium text-gray-700 mb-1">Descripción *</label>
                <Input
                  value={it.descripcion}
                  onChange={(e) => onDescripcionChange(idx, e.target.value)}
                  placeholder="ej: SERVICIO CERTIFICACION OPERATIVIDAD"
                />
              </div>
            </div>

            <div className="grid grid-cols-2 md:grid-cols-5 gap-2">
              <div>
                <label className="block text-xs font-medium text-gray-700 mb-1">Cantidad *</label>
                <Input
                  type="number" step="0.01" min="0.01"
                  value={it.cantidad_comprada}
                  onChange={(e) => setItem(idx, {
                    cantidad_comprada: e.target.value === '' ? '' : Number(e.target.value),
                  })}
                />
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-700 mb-1">Unidad ext.</label>
                <Input
                  value={it.unidad_externa}
                  onChange={(e) => setItem(idx, { unidad_externa: e.target.value })}
                  placeholder="UN, KG, LT..."
                />
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-700 mb-1">CC externo</label>
                <Input
                  value={it.centro_costo_codigo_externo}
                  onChange={(e) => setItem(idx, { centro_costo_codigo_externo: e.target.value })}
                  placeholder="CC-15-15"
                />
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-700 mb-1">Precio CLP *</label>
                <Input
                  type="number" step="1" min="0"
                  value={it.precio_unitario_clp}
                  onChange={(e) => setItem(idx, {
                    precio_unitario_clp: e.target.value === '' ? '' : Number(e.target.value),
                  })}
                />
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-700 mb-1">Subtotal</label>
                <div className="h-[42px] flex items-center justify-end px-3 rounded-md bg-gray-50 border border-gray-200 text-sm tabular-nums font-semibold">
                  {formatCLP(
                    (typeof it.cantidad_comprada === 'number' ? it.cantidad_comprada : 0) *
                    (typeof it.precio_unitario_clp === 'number' ? it.precio_unitario_clp : 0)
                  )}
                </div>
              </div>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-2">
              <div>
                <label className="block text-xs font-medium text-gray-700 mb-1">Tipo de ítem</label>
                <select
                  value={it.tipo_item}
                  onChange={(e) => onTipoChange(idx, e.target.value as TipoItemOC)}
                  className="w-full rounded-md border border-gray-300 bg-white px-2 py-1.5 text-sm"
                >
                  {TIPO_ITEM_OPCIONES.map((t) => (
                    <option key={t} value={t}>{t}</option>
                  ))}
                </select>
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-700 mb-1">
                  Producto (mapeado) {it.requiere_stock && '*'}
                </label>
                <select
                  value={it.producto_id ?? ''}
                  onChange={(e) => onProductoChange(idx, e.target.value)}
                  className={cn(
                    'w-full rounded-md border bg-white px-2 py-1.5 text-sm',
                    it.requiere_stock && !it.producto_id ? 'border-amber-400' : 'border-gray-300',
                  )}
                >
                  <option value="">
                    {it.requiere_stock ? '— Pendiente mapeo —' : '— Sin producto (servicio) —'}
                  </option>
                  {productos.map((p) => (
                    <option key={p.id} value={p.id}>{p.codigo} — {p.nombre}</option>
                  ))}
                </select>
              </div>
            </div>
          </div>
        ))}

        <div className="flex items-center justify-between pt-2">
          <Button type="button" variant="outline" onClick={onPrev}>
            <ArrowLeft className="h-4 w-4 mr-1" /> Atrás
          </Button>
          <Button type="button" onClick={onNext} disabled={!canAdvance}>
            Siguiente <ArrowRight className="h-4 w-4 ml-1" />
          </Button>
        </div>
      </CardContent>
    </Card>
  )
}

// ── Step 4: Validar y guardar ────────────────────────────────────────────

function Step4Validar({
  cabecera, items, subtotal, diffSubtotalVsNeto, diffNetoIvaVsTotal,
  itemsPendientesMapeo, documento, onPrev, onSubmit, loading,
}: {
  cabecera: CabeceraState
  items: ItemState[]
  subtotal: number
  diffSubtotalVsNeto: number
  diffNetoIvaVsTotal: number
  itemsPendientesMapeo: number
  documento: DocumentoState | null
  onPrev: () => void
  onSubmit: () => void
  loading: boolean
}) {
  const tieneNeto = typeof cabecera.neto_clp === 'number' && cabecera.neto_clp > 0
  const tieneTotal = typeof cabecera.total_clp === 'number' && cabecera.total_clp > 0
  const itemsPorTipo = items.reduce((acc, it) => {
    acc[it.tipo_item] = (acc[it.tipo_item] ?? 0) + 1
    return acc
  }, {} as Record<TipoItemOC, number>)

  const warnings: Array<{ level: 'warn' | 'error' | 'info'; msg: string }> = []
  if (tieneNeto && Math.abs(diffSubtotalVsNeto) > 1) {
    warnings.push({
      level: Math.abs(diffSubtotalVsNeto) > 100 ? 'error' : 'warn',
      msg: `Suma ítems (${formatCLP(subtotal)}) difiere de neto (${formatCLP(cabecera.neto_clp as number)}) por ${formatCLP(diffSubtotalVsNeto)}`,
    })
  }
  if (tieneTotal && tieneNeto && Math.abs(diffNetoIvaVsTotal) > 1) {
    warnings.push({
      level: Math.abs(diffNetoIvaVsTotal) > 100 ? 'error' : 'warn',
      msg: `Neto + IVA (${formatCLP((cabecera.neto_clp as number) + (typeof cabecera.iva_clp === 'number' ? cabecera.iva_clp : 0))}) difiere de total (${formatCLP(cabecera.total_clp as number)}) por ${formatCLP(diffNetoIvaVsTotal)}`,
    })
  }
  if (itemsPendientesMapeo > 0) {
    warnings.push({
      level: 'warn',
      msg: `${itemsPendientesMapeo} ítem(s) inventariable(s) sin producto mapeado. No podrán recepcionarse hasta mapearlos.`,
    })
  }
  if (!documento?.url) {
    warnings.push({
      level: 'info',
      msg: 'OC sin documento adjunto. Podrás subirlo después desde el detalle.',
    })
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Paso 4 · Validar y guardar</CardTitle>
        <p className="text-xs text-gray-600">
          Revisa totales y advertencias. Importar OC NO mueve stock ni crea capas.
        </p>
      </CardHeader>
      <CardContent className="space-y-3">
        <div className="grid grid-cols-2 md:grid-cols-4 gap-3 text-sm">
          <Resumen label="N° OC externo" value={cabecera.numero_oc_externo || '—'} />
          <Resumen label="Fecha emisión" value={cabecera.fecha_emision || '—'} />
          <Resumen label="Items" value={items.length.toString()} />
          <Resumen label="Subtotal ítems" value={formatCLP(subtotal)} />
          <Resumen label="Neto" value={tieneNeto ? formatCLP(cabecera.neto_clp as number) : '—'} />
          <Resumen label="IVA" value={typeof cabecera.iva_clp === 'number' ? formatCLP(cabecera.iva_clp) : '—'} />
          <Resumen label="Total" value={tieneTotal ? formatCLP(cabecera.total_clp as number) : '—'} />
          <Resumen label="Forma pago" value={cabecera.forma_pago || '—'} />
        </div>

        <div className="rounded-lg border border-gray-200 bg-white p-3">
          <div className="text-xs font-semibold text-gray-700 mb-2">Items por tipo</div>
          <div className="flex flex-wrap gap-2">
            {(Object.keys(itemsPorTipo) as TipoItemOC[]).map((t) => (
              <Badge key={t} className={tipoBadgeColor(t)}>
                {t}: {itemsPorTipo[t]}
              </Badge>
            ))}
          </div>
        </div>

        {warnings.length > 0 && (
          <div className="space-y-2">
            {warnings.map((w, i) => (
              <div
                key={i}
                className={cn(
                  'rounded-lg border p-2 text-xs flex items-start gap-2',
                  w.level === 'error' && 'border-red-200 bg-red-50 text-red-800',
                  w.level === 'warn' && 'border-amber-200 bg-amber-50 text-amber-800',
                  w.level === 'info' && 'border-blue-200 bg-blue-50 text-blue-800',
                )}
              >
                {w.level === 'error' ? <X className="h-4 w-4 mt-0.5 shrink-0" />
                  : w.level === 'warn' ? <AlertTriangle className="h-4 w-4 mt-0.5 shrink-0" />
                  : <AlertCircle className="h-4 w-4 mt-0.5 shrink-0" />}
                <div>{w.msg}</div>
              </div>
            ))}
          </div>
        )}

        {warnings.length === 0 && (
          <div className="rounded-lg border border-green-200 bg-green-50 p-2 text-xs text-green-800 flex items-start gap-2">
            <CheckCircle2 className="h-4 w-4 mt-0.5 shrink-0" />
            <div>Totales cuadran y todos los ítems inventariables están mapeados.</div>
          </div>
        )}

        <div className="flex items-center justify-between pt-2">
          <Button type="button" variant="outline" onClick={onPrev} disabled={loading}>
            <ArrowLeft className="h-4 w-4 mr-1" /> Atrás
          </Button>
          <Button type="button" onClick={onSubmit} disabled={loading}>
            {loading ? <Spinner className="h-4 w-4 mr-2" /> : <Save className="h-4 w-4 mr-2" />}
            {loading ? 'Importando...' : 'Guardar OC'}
          </Button>
        </div>
      </CardContent>
    </Card>
  )
}

function Resumen({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <div className="text-[11px] uppercase text-gray-500 font-semibold">{label}</div>
      <div className="text-sm mt-0.5 font-mono">{value}</div>
    </div>
  )
}
