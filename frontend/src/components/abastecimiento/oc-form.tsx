'use client'

import { useMemo, useState } from 'react'
import { useRouter } from 'next/navigation'
import { Plus, Save, ArrowLeft, AlertCircle } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Spinner } from '@/components/ui/spinner'
import { formatCLP, todayISO } from '@/lib/utils'
import { useProveedoresActivos, useCrearOC } from '@/hooks/use-bodega-oc'
import { useProductos } from '@/hooks/use-inventario'
import { useToast } from '@/contexts/toast-context'
import { OCItemForm, type OCItemFormValue } from './oc-item-form'
import type { CrearOCPayload } from '@/lib/services/bodega-oc'

function nuevoItem(): OCItemFormValue {
  return {
    producto_id: null,
    descripcion: '',
    unidad: 'unidad',
    cantidad_comprada: '',
    precio_unitario_clp: '',
    observacion: '',
  }
}

interface ItemErrors {
  descripcion?: string
  cantidad_comprada?: string
  precio_unitario_clp?: string
}
interface FormErrors {
  proveedor_id?: string
  items?: string
  itemRows?: Record<number, ItemErrors>
}

export function OCForm() {
  const router = useRouter()
  const toast = useToast()

  const [proveedorId, setProveedorId]   = useState('')
  const [numeroOC, setNumeroOC]         = useState('')
  const [fechaOC, setFechaOC]           = useState<string>(todayISO())
  const [observacion, setObservacion]   = useState('')
  const [items, setItems]               = useState<OCItemFormValue[]>([nuevoItem()])
  const [errors, setErrors]             = useState<FormErrors>({})

  const { data: proveedores, isLoading: loadProv } = useProveedoresActivos()
  // Productos NO combustible (D2 MIG37). categoria 'combustible' se gestiona en MIG38.
  const { data: productosAll, isLoading: loadProd } = useProductos()
  const productos = useMemo(
    () => (productosAll ?? [])
      .filter((p) => p.categoria !== 'combustible')
      .map((p) => ({
        id: p.id, codigo: p.codigo, nombre: p.nombre,
        unidad_medida: p.unidad_medida, categoria: p.categoria,
      })),
    [productosAll],
  )

  const crear = useCrearOC()

  const totalGeneral = items.reduce((s, it) => {
    const cant = typeof it.cantidad_comprada === 'number' ? it.cantidad_comprada : 0
    const prec = typeof it.precio_unitario_clp === 'number' ? it.precio_unitario_clp : 0
    return s + cant * prec
  }, 0)

  const validar = (): FormErrors => {
    const errs: FormErrors = {}
    if (!proveedorId) errs.proveedor_id = 'Proveedor obligatorio'
    if (items.length === 0) {
      errs.items = 'Al menos 1 item'
    } else {
      const rowErrs: Record<number, ItemErrors> = {}
      items.forEach((it, idx) => {
        const e: ItemErrors = {}
        const cant = typeof it.cantidad_comprada === 'number' ? it.cantidad_comprada : 0
        const prec = typeof it.precio_unitario_clp === 'number' ? it.precio_unitario_clp : -1
        if (cant <= 0) e.cantidad_comprada = 'Debe ser > 0'
        if (prec < 0)  e.precio_unitario_clp = 'Debe ser >= 0'
        if (!it.producto_id && (!it.descripcion || it.descripcion.trim().length === 0)) {
          e.descripcion = 'Descripción obligatoria sin producto'
        }
        if (Object.keys(e).length > 0) rowErrs[idx] = e
      })
      if (Object.keys(rowErrs).length > 0) errs.itemRows = rowErrs
    }
    return errs
  }

  const onSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    const errs = validar()
    setErrors(errs)
    if (Object.keys(errs).length > 0) {
      toast.error('Revisa los campos marcados')
      return
    }

    const payload: CrearOCPayload = {
      proveedor_id: proveedorId,
      numero_oc: numeroOC.trim() || null,
      fecha_oc: fechaOC,
      observacion: observacion.trim() || null,
      items: items.map((it) => ({
        producto_id: it.producto_id,
        descripcion: it.descripcion.trim() || (productos.find((p) => p.id === it.producto_id)?.nombre ?? ''),
        unidad: it.unidad || 'unidad',
        cantidad_comprada: typeof it.cantidad_comprada === 'number' ? it.cantidad_comprada : 0,
        precio_unitario_clp: typeof it.precio_unitario_clp === 'number' ? it.precio_unitario_clp : 0,
        observacion: it.observacion.trim() || null,
      })),
    }

    crear.mutate(payload, {
      onSuccess: (data) => {
        toast.success(`OC ${data.numero_oc} creada (${data.items_count} items, ${formatCLP(data.monto_total_clp)})`)
        router.push(`/dashboard/abastecimiento/oc/${data.orden_compra_id}`)
      },
      onError: (err: unknown) => {
        const msg = err instanceof Error ? err.message : 'Error al crear OC'
        if (msg.toLowerCase().includes('rol') && msg.toLowerCase().includes('autorizado')) {
          toast.error('No tienes permiso para crear OC')
        } else if (msg.toLowerCase().includes('no autenticado')) {
          toast.error('Sesión expirada. Refresca la página.')
        } else {
          toast.error(msg)
        }
      },
    })
  }

  const setItem = (idx: number, v: OCItemFormValue) => {
    setItems((prev) => prev.map((it, i) => (i === idx ? v : it)))
  }
  const removeItem = (idx: number) => {
    setItems((prev) => prev.filter((_, i) => i !== idx))
  }
  const addItem = () => setItems((prev) => [...prev, nuevoItem()])

  if (loadProv || loadProd) {
    return <div className="flex justify-center py-10"><Spinner /></div>
  }

  return (
    <form onSubmit={onSubmit} className="space-y-4">
      <div className="flex items-center gap-2">
        <Button type="button" variant="outline" size="sm" onClick={() => router.back()}>
          <ArrowLeft className="h-4 w-4 mr-1" /> Volver
        </Button>
        <h1 className="text-xl font-bold">Nueva Orden de Compra</h1>
      </div>

      <div className="rounded-lg border border-amber-200 bg-amber-50 p-3 text-xs text-amber-800 flex items-start gap-2">
        <AlertCircle className="h-4 w-4 mt-0.5 shrink-0" />
        <div>
          <strong>Nuevo flujo OC/FIFO.</strong> Las recepciones y salidas FIFO se habilitarán en las
          siguientes etapas. Crear una OC <strong>no afecta stock</strong>; solo registra la orden.
        </div>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Datos de la OC</CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
            <div className="md:col-span-2">
              <label className="block text-xs font-medium text-gray-700 mb-1">
                Proveedor *
              </label>
              <select
                value={proveedorId}
                onChange={(e) => setProveedorId(e.target.value)}
                className={`w-full rounded-md border ${errors.proveedor_id ? 'border-red-500' : 'border-gray-300'} bg-white px-3 py-2 text-sm`}
              >
                <option value="">— Selecciona proveedor —</option>
                {(proveedores ?? []).map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.codigo} — {p.nombre} [{p.tipo}]
                  </option>
                ))}
              </select>
              {errors.proveedor_id && (
                <p className="text-[11px] text-red-600 mt-0.5">{errors.proveedor_id}</p>
              )}
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">Fecha OC</label>
              <Input
                type="date"
                value={fechaOC}
                onChange={(e) => setFechaOC(e.target.value)}
                required
              />
            </div>
          </div>

          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">
              N° OC (opcional)
            </label>
            <Input
              value={numeroOC}
              onChange={(e) => setNumeroOC(e.target.value)}
              placeholder="Auto-genera OC-YYYY-NNNNN si lo dejas vacío"
            />
          </div>

          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">
              Observación (opcional)
            </label>
            <Input
              value={observacion}
              onChange={(e) => setObservacion(e.target.value)}
              placeholder="Notas internas..."
            />
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <div className="flex items-center justify-between">
            <CardTitle className="text-base">Items ({items.length})</CardTitle>
            <Button type="button" size="sm" variant="outline" onClick={addItem}>
              <Plus className="h-4 w-4 mr-1" /> Agregar ítem
            </Button>
          </div>
          {errors.items && (
            <p className="text-xs text-red-600 mt-1">{errors.items}</p>
          )}
        </CardHeader>
        <CardContent className="space-y-2">
          {items.map((it, idx) => (
            <OCItemForm
              key={idx}
              idx={idx}
              value={it}
              onChange={(v) => setItem(idx, v)}
              onRemove={() => removeItem(idx)}
              productos={productos}
              errors={errors.itemRows?.[idx]}
              removable={items.length > 1}
            />
          ))}
        </CardContent>
      </Card>

      <Card>
        <CardContent className="flex items-center justify-between py-4">
          <div>
            <div className="text-xs text-gray-600">Total general</div>
            <div className="text-2xl font-bold tabular-nums">{formatCLP(totalGeneral)}</div>
          </div>
          <Button type="submit" disabled={crear.isPending}>
            {crear.isPending ? <Spinner className="h-4 w-4 mr-2" /> : <Save className="h-4 w-4 mr-2" />}
            {crear.isPending ? 'Creando...' : 'Crear OC'}
          </Button>
        </CardContent>
      </Card>
    </form>
  )
}
