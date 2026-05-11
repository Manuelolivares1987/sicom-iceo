'use client'

import { useEffect, useMemo, useState } from 'react'
import { useRouter } from 'next/navigation'
import {
  ArrowLeft, Save, Trash2, Plus, AlertTriangle, AlertCircle, ArrowDownRight, Layers,
} from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Badge } from '@/components/ui/badge'
import { Spinner } from '@/components/ui/spinner'
import { formatCLP, formatDate, cn } from '@/lib/utils'
import { useToast } from '@/contexts/toast-context'
import {
  useOTsValidasSalida, useBodegasPorFaena, useCECO,
  useStockDisponible, usePreviewFIFO, useRegistrarSalidaFifo,
} from '@/hooks/use-bodega-salida-fifo'
import type { SalidaFifoPayload, OTValidaSalida } from '@/lib/services/bodega-salida-fifo'

interface ItemState {
  producto_id: string
  cantidad: number | ''
}

function nuevoItem(): ItemState {
  return { producto_id: '', cantidad: '' }
}

export function SalidaFifoForm() {
  const router = useRouter()
  const toast = useToast()
  const [otId, setOtId] = useState('')
  const [bodegaId, setBodegaId] = useState('')
  const [cecoId, setCecoId] = useState('')
  const [motivo, setMotivo] = useState('')
  const [entregadoA, setEntregadoA] = useState('')
  const [observacion, setObservacion] = useState('')
  const [items, setItems] = useState<ItemState[]>([nuevoItem()])

  const { data: ots, isLoading: loadOTs } = useOTsValidasSalida()
  const otSeleccionada: OTValidaSalida | undefined = ots?.find((o) => o.id === otId)
  const faenaId = otSeleccionada?.faena_id
  const { data: bodegas, isLoading: loadBodegas } = useBodegasPorFaena(faenaId)
  const { data: cecos, isLoading: loadCecos } = useCECO()
  const { data: stockEnBodega, isLoading: loadStock } = useStockDisponible(bodegaId || null)
  const registrar = useRegistrarSalidaFifo()

  // Reset bodega cuando cambia la OT (porque faena puede ser distinta)
  useEffect(() => {
    setBodegaId('')
  }, [otId])

  // Reset items cuando cambia la bodega (porque stock disponible cambia)
  useEffect(() => {
    setItems([nuevoItem()])
  }, [bodegaId])

  const stockMap = useMemo(() => {
    const m = new Map<string, typeof stockEnBodega extends Array<infer T> | undefined ? T : never>()
    for (const s of (stockEnBodega ?? [])) m.set(s.producto_id, s)
    return m
  }, [stockEnBodega])

  // Validaciones
  const errores: string[] = []
  if (!otId) errores.push('Selecciona una OT.')
  if (!bodegaId) errores.push('Selecciona la bodega.')
  if (!cecoId) errores.push('Selecciona el centro de costo.')
  if (motivo.trim().length < 5) errores.push('Motivo debe tener mínimo 5 caracteres.')
  const itemsActivos = items.filter((it) => it.producto_id && (typeof it.cantidad === 'number' ? it.cantidad : 0) > 0)
  if (itemsActivos.length === 0) errores.push('Agrega al menos 1 item con producto y cantidad.')
  for (const it of itemsActivos) {
    const stock = stockMap.get(it.producto_id)
    const cant = typeof it.cantidad === 'number' ? it.cantidad : 0
    if (!stock) {
      errores.push('Item sin stock disponible.')
      continue
    }
    if (cant > stock.cantidad_disponible) {
      errores.push(`${stock.producto_codigo}: cantidad ${cant} supera stock ${stock.cantidad_disponible}.`)
    }
  }
  const canSubmit = errores.length === 0

  const setItem = (idx: number, patch: Partial<ItemState>) => {
    setItems((prev) => prev.map((it, i) => (i === idx ? { ...it, ...patch } : it)))
  }
  const addItem = () => setItems((prev) => [...prev, nuevoItem()])
  const removeItem = (idx: number) => setItems((prev) => prev.filter((_, i) => i !== idx))

  const onSubmit = () => {
    if (!canSubmit) {
      toast.error('Revisa los errores antes de enviar.')
      return
    }
    const payload: SalidaFifoPayload = {
      bodega_id: bodegaId,
      ceco_id: cecoId,
      ot_id: otId,
      motivo: motivo.trim(),
      entregado_a: entregadoA.trim() || null,
      observacion: observacion.trim() || null,
      items: itemsActivos.map((it) => ({
        producto_id: it.producto_id,
        cantidad: typeof it.cantidad === 'number' ? it.cantidad : 0,
      })),
    }
    registrar.mutate(payload, {
      onSuccess: (data) => {
        const totalCosto = data.items.reduce((s, x) => s + Number(x.costo_total ?? 0), 0)
        toast.success(`Salida ${data.folio} registrada (${data.items_count} item${data.items_count > 1 ? 's' : ''}, ${formatCLP(totalCosto)})`)
        // Volver al listado o detalle OT
        router.push('/dashboard/inventario')
      },
      onError: (err: unknown) => {
        const msg = err instanceof Error ? err.message : 'Error al registrar salida'
        if (msg.toLowerCase().includes('rol') && msg.toLowerCase().includes('autorizado')) {
          toast.error('No tienes permiso para registrar salidas')
        } else if (msg.toLowerCase().includes('stock insuficiente')) {
          toast.error(msg)
        } else if (msg.toLowerCase().includes('asignada') || msg.toLowerCase().includes('en_ejecucion')) {
          toast.error('La OT debe estar en estado asignada o en ejecución.')
        } else if (msg.toLowerCase().includes('faena')) {
          toast.error('La bodega no pertenece a la faena de la OT.')
        } else {
          toast.error(msg)
        }
      },
    })
  }

  if (loadOTs || loadCecos) {
    return <div className="flex justify-center py-10"><Spinner /></div>
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-2 flex-wrap">
        <Button type="button" variant="outline" size="sm" onClick={() => router.back()}>
          <ArrowLeft className="h-4 w-4 mr-1" /> Volver
        </Button>
        <h1 className="text-xl font-bold flex items-center gap-2">
          <ArrowDownRight className="h-5 w-5 text-amber-700" />
          Salida con OT (FIFO)
        </h1>
      </div>

      <div className="rounded-lg border border-blue-200 bg-blue-50 p-3 text-xs text-blue-900 flex items-start gap-2">
        <AlertCircle className="h-4 w-4 mt-0.5 shrink-0" />
        <div>
          <strong>Flujo nuevo OC/FIFO.</strong> La salida consume capas FIFO automáticamente y descuenta stock_bodega.
          La OT debe estar en estado <span className="font-semibold">asignada</span> o <span className="font-semibold">en ejecución</span> y la bodega pertenecer a su faena.
        </div>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Datos de la salida</CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">OT *</label>
              <select
                value={otId}
                onChange={(e) => setOtId(e.target.value)}
                className="w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-sm"
              >
                <option value="">— Selecciona OT —</option>
                {(ots ?? []).map((o) => (
                  <option key={o.id} value={o.id}>
                    {o.folio} · {o.tipo} · {o.estado} {o.faena_nombre ? `· ${o.faena_nombre}` : ''}
                  </option>
                ))}
              </select>
              {otSeleccionada && (
                <div className="text-[11px] text-gray-600 mt-1 flex items-center gap-2 flex-wrap">
                  <Badge className="bg-amber-100 text-amber-700">{otSeleccionada.estado}</Badge>
                  {otSeleccionada.faena_nombre && <span>Faena: {otSeleccionada.faena_nombre}</span>}
                  {otSeleccionada.responsable_nombre && <span>Resp: {otSeleccionada.responsable_nombre}</span>}
                  {otSeleccionada.fecha_programada && <span>Prog: {formatDate(otSeleccionada.fecha_programada)}</span>}
                </div>
              )}
            </div>

            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">Bodega *</label>
              <select
                value={bodegaId}
                onChange={(e) => setBodegaId(e.target.value)}
                disabled={!otId || loadBodegas}
                className="w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-sm disabled:bg-gray-50"
              >
                <option value="">
                  {!otId ? '— Selecciona OT primero —'
                    : loadBodegas ? 'Cargando...'
                    : '— Selecciona bodega —'}
                </option>
                {(bodegas ?? []).map((b) => (
                  <option key={b.id} value={b.id}>{b.codigo} — {b.nombre}</option>
                ))}
              </select>
              {otId && (bodegas?.length ?? 0) === 0 && !loadBodegas && (
                <div className="text-[11px] text-red-700 mt-1">
                  No hay bodegas en la faena de esta OT.
                </div>
              )}
            </div>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">Centro de Costo *</label>
              <select
                value={cecoId}
                onChange={(e) => setCecoId(e.target.value)}
                className="w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-sm"
              >
                <option value="">— Selecciona CECO —</option>
                {(cecos ?? []).map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.codigo} — {c.nombre}{c.area ? ` (${c.area})` : ''}
                  </option>
                ))}
              </select>
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">Entregado a (opcional)</label>
              <Input
                value={entregadoA}
                onChange={(e) => setEntregadoA(e.target.value)}
                placeholder="Nombre del que recibe"
              />
            </div>
          </div>

          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">Motivo * (mín 5)</label>
            <Input
              value={motivo}
              onChange={(e) => setMotivo(e.target.value)}
              placeholder="ej: Mantención correctiva camión OT-2025-001"
            />
            <div className="flex gap-1 mt-1 flex-wrap">
              {['Consumo en OT', 'Reposición en terreno', 'Mantención correctiva', 'Mantención preventiva'].map((m) => (
                <button
                  key={m}
                  type="button"
                  onClick={() => setMotivo(m)}
                  className="text-[10px] rounded bg-gray-100 hover:bg-gray-200 px-2 py-0.5"
                >{m}</button>
              ))}
            </div>
          </div>

          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">Observación (opcional)</label>
            <Input
              value={observacion}
              onChange={(e) => setObservacion(e.target.value)}
              placeholder="Notas internas"
            />
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <div className="flex items-center justify-between">
            <CardTitle className="text-base">Items a entregar ({items.length})</CardTitle>
            <Button
              type="button" size="sm" variant="outline"
              onClick={addItem}
              disabled={!bodegaId}
            >
              <Plus className="h-4 w-4 mr-1" /> Agregar item
            </Button>
          </div>
          {!bodegaId && (
            <p className="text-[11px] text-gray-500 mt-1">Selecciona bodega antes de agregar items.</p>
          )}
        </CardHeader>
        <CardContent className="space-y-2">
          {!bodegaId ? (
            <div className="text-center text-sm text-gray-500 py-6">
              Sin bodega seleccionada.
            </div>
          ) : loadStock ? (
            <div className="flex justify-center py-6"><Spinner /></div>
          ) : (stockEnBodega?.length ?? 0) === 0 ? (
            <div className="text-center text-sm text-gray-500 py-6">
              No hay productos con stock disponible en esta bodega.
            </div>
          ) : items.map((it, idx) => (
            <ItemRow
              key={idx}
              idx={idx}
              value={it}
              onChange={(patch) => setItem(idx, patch)}
              onRemove={() => removeItem(idx)}
              removable={items.length > 1}
              stockOpciones={stockEnBodega ?? []}
              bodegaId={bodegaId}
            />
          ))}
        </CardContent>
      </Card>

      {/* Errores y submit */}
      {errores.length > 0 && (otId || bodegaId || cecoId || motivo.length > 0) && (
        <div className="rounded-lg border border-amber-200 bg-amber-50 p-3 text-xs text-amber-900 space-y-1">
          <div className="font-semibold flex items-center gap-1">
            <AlertTriangle className="h-4 w-4" /> Antes de registrar:
          </div>
          <ul className="list-disc list-inside">
            {errores.map((e, i) => <li key={i}>{e}</li>)}
          </ul>
        </div>
      )}

      <Card>
        <CardContent className="flex items-center justify-between py-4">
          <Button type="button" variant="outline" onClick={() => router.back()} disabled={registrar.isPending}>
            Cancelar
          </Button>
          <Button type="button" onClick={onSubmit} disabled={!canSubmit || registrar.isPending}>
            {registrar.isPending ? <Spinner className="h-4 w-4 mr-2" /> : <Save className="h-4 w-4 mr-2" />}
            {registrar.isPending ? 'Registrando...' : 'Registrar salida'}
          </Button>
        </CardContent>
      </Card>
    </div>
  )
}

// ── Item row con preview FIFO ───────────────────────────────────────────────

function ItemRow({
  idx, value, onChange, onRemove, removable, stockOpciones, bodegaId,
}: {
  idx: number
  value: ItemState
  onChange: (patch: Partial<ItemState>) => void
  onRemove: () => void
  removable: boolean
  stockOpciones: Array<{
    producto_id: string; producto_codigo: string; producto_nombre: string
    producto_categoria: string; unidad_medida: string; cantidad_disponible: number
    costo_promedio: number
  }>
  bodegaId: string
}) {
  const stock = stockOpciones.find((s) => s.producto_id === value.producto_id)
  const cantNum = typeof value.cantidad === 'number' ? value.cantidad : 0
  const excedeStock = stock != null && cantNum > stock.cantidad_disponible
  const { data: capas, isLoading: loadPreview } = usePreviewFIFO(
    value.producto_id || null,
    bodegaId || null,
  )

  // Cálculo de costo estimado consumiendo capas FIFO
  const estimacion = useMemo(() => {
    if (!capas || cantNum <= 0) return null
    let pendiente = cantNum
    let costoTotal = 0
    const consumidas: Array<{
      capa_id: string; cantidad: number; costo_unitario: number; fecha: string
    }> = []
    for (const c of capas) {
      if (pendiente <= 0) break
      const consumir = Math.min(pendiente, c.cantidad_disponible)
      costoTotal += consumir * c.costo_unitario
      consumidas.push({
        capa_id: c.capa_id, cantidad: consumir, costo_unitario: c.costo_unitario,
        fecha: c.fecha_recepcion,
      })
      pendiente -= consumir
    }
    return {
      cubierto: pendiente <= 0,
      faltante: Math.max(0, pendiente),
      costoTotal,
      costoUnitarioPromedio: cantNum > 0 ? costoTotal / cantNum : 0,
      consumidas,
    }
  }, [capas, cantNum])

  return (
    <div className={cn(
      'rounded-lg border p-3 space-y-2',
      excedeStock ? 'border-red-300 bg-red-50' : 'border-gray-200 bg-white',
    )}>
      <div className="flex items-center justify-between">
        <span className="text-xs font-semibold text-gray-600">Item {idx + 1}</span>
        {removable && (
          <button
            type="button"
            onClick={onRemove}
            className="text-red-600 hover:bg-red-50 rounded p-1"
          >
            <Trash2 className="h-4 w-4" />
          </button>
        )}
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-2">
        <div className="md:col-span-2">
          <label className="block text-[11px] font-medium text-gray-700 mb-1">Producto *</label>
          <select
            value={value.producto_id}
            onChange={(e) => onChange({ producto_id: e.target.value, cantidad: '' })}
            className="w-full rounded-md border border-gray-300 bg-white px-2 py-1.5 text-sm"
          >
            <option value="">— Selecciona producto —</option>
            {stockOpciones.map((s) => (
              <option key={s.producto_id} value={s.producto_id}>
                {s.producto_codigo} — {s.producto_nombre} (stock: {s.cantidad_disponible.toFixed(2)} {s.unidad_medida})
              </option>
            ))}
          </select>
          {stock && (
            <div className="text-[10px] text-gray-500 mt-1 flex items-center gap-2 flex-wrap">
              <Badge className="bg-blue-50 text-blue-700">{stock.producto_categoria}</Badge>
              <span>Disponible: <strong>{stock.cantidad_disponible.toFixed(2)} {stock.unidad_medida}</strong></span>
              <span>CPP: <strong>{formatCLP(stock.costo_promedio)}</strong></span>
            </div>
          )}
        </div>
        <div>
          <label className="block text-[11px] font-medium text-gray-700 mb-1">Cantidad *</label>
          <Input
            type="number" step="0.01" min="0.01"
            max={stock?.cantidad_disponible}
            value={value.cantidad}
            onChange={(e) => onChange({ cantidad: e.target.value === '' ? '' : Number(e.target.value) })}
            disabled={!stock}
            className={excedeStock ? 'border-red-500' : ''}
          />
          {excedeStock && stock && (
            <div className="text-[10px] text-red-700 mt-0.5">
              Excede stock disponible ({stock.cantidad_disponible.toFixed(2)})
            </div>
          )}
        </div>
      </div>

      {/* Preview FIFO */}
      {stock && cantNum > 0 && (
        <div className="rounded border border-gray-200 bg-gray-50 p-2 text-[11px] space-y-1">
          <div className="font-semibold text-gray-700 flex items-center gap-1">
            <Layers className="h-3 w-3" /> Preview FIFO
          </div>
          {loadPreview ? (
            <div className="text-gray-500">Calculando...</div>
          ) : !capas || capas.length === 0 ? (
            <div className="text-amber-700">Sin capas FIFO disponibles para este producto.</div>
          ) : estimacion ? (
            <>
              <div className="text-gray-600">
                {estimacion.consumidas.length} capa(s) consumidas · Costo total estimado <strong>{formatCLP(estimacion.costoTotal)}</strong> · CPP <strong>{formatCLP(estimacion.costoUnitarioPromedio)}</strong>
              </div>
              {!estimacion.cubierto && (
                <div className="text-red-700">
                  ⚠ FIFO sólo cubre {(cantNum - estimacion.faltante).toFixed(2)}, faltan {estimacion.faltante.toFixed(2)} unidades.
                </div>
              )}
              <ul className="list-disc list-inside text-gray-600">
                {estimacion.consumidas.map((c) => (
                  <li key={c.capa_id} className="font-mono">
                    {formatDate(c.fecha)} · {c.cantidad.toFixed(2)} × {formatCLP(c.costo_unitario)} = {formatCLP(c.cantidad * c.costo_unitario)}
                  </li>
                ))}
              </ul>
            </>
          ) : null}
        </div>
      )}
    </div>
  )
}

