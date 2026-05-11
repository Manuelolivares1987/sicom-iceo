'use client'

import { useMemo, useState } from 'react'
import { useRouter } from 'next/navigation'
import {
  ArrowLeft, Save, AlertTriangle, AlertCircle, CheckCircle2, X, Package, FileCheck,
} from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Badge } from '@/components/ui/badge'
import { Spinner } from '@/components/ui/spinner'
import { formatCLP, cn } from '@/lib/utils'
import { useToast } from '@/contexts/toast-context'
import { useOCById, useRecepcionarOC } from '@/hooks/use-bodega-oc'
import { useBodegas, useProductos } from '@/hooks/use-inventario'
import type {
  DocTipoProveedor, RecepcionarOCPayload, RecepcionarOCItemInput, TipoItemOC,
} from '@/lib/services/bodega-oc'

interface ItemRecepcionState {
  seleccionado: boolean
  cantidad: number | ''
  producto_id: string | null  // para mapeo en recepcion si el item OC no lo tiene
  lote: string
  vencimiento: string
  observacion: string
}

function tipoBadgeColor(t: TipoItemOC): string {
  switch (t) {
    case 'servicio': return 'bg-purple-100 text-purple-700'
    case 'inventariable': return 'bg-blue-100 text-blue-700'
    case 'combustible': return 'bg-amber-100 text-amber-700'
    case 'lubricante': return 'bg-amber-50 text-amber-800'
    case 'repuesto': return 'bg-cyan-100 text-cyan-700'
    case 'consumible': return 'bg-emerald-100 text-emerald-700'
    case 'activo': return 'bg-indigo-100 text-indigo-700'
    case 'otro': return 'bg-gray-100 text-gray-700'
    default: return 'bg-gray-100 text-gray-700'
  }
}

export function RecepcionOCForm({ ocId }: { ocId: string }) {
  const router = useRouter()
  const toast = useToast()
  const { data: oc, isLoading: loadOC } = useOCById(ocId)
  const { data: bodegas } = useBodegas()
  const { data: productosAll } = useProductos()
  const recepcionar = useRecepcionarOC()

  const productos = useMemo(
    () => (productosAll ?? []).filter((p) => p.categoria !== 'combustible'),
    [productosAll],
  )

  const itemsPendientes = useMemo(
    () => (oc?.items ?? []).filter((it) =>
      Number(it.cantidad_pendiente) > 0 && it.estado !== 'completo',
    ),
    [oc],
  )

  // Estado del form
  const [seleccion, setSeleccion] = useState<Record<string, ItemRecepcionState>>({})
  const [bodegaId, setBodegaId] = useState('')
  const [docTipo, setDocTipo] = useState<DocTipoProveedor>('factura')
  const [docNumero, setDocNumero] = useState('')
  const [observacion, setObservacion] = useState('')
  const [overrideAdmin, setOverrideAdmin] = useState(false)
  const [permiteSobre, setPermiteSobre] = useState(false)
  const [permitePrecio, setPermitePrecio] = useState(false)
  const [justificacion, setJustificacion] = useState('')

  if (loadOC) return <div className="flex justify-center py-10"><Spinner /></div>
  if (!oc) return (
    <div className="rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-800">
      OC no encontrada.
    </div>
  )

  // Helpers para item state
  const getItem = (id: string): ItemRecepcionState => seleccion[id] ?? {
    seleccionado: false, cantidad: '', producto_id: null,
    lote: '', vencimiento: '', observacion: '',
  }
  const setItem = (id: string, patch: Partial<ItemRecepcionState>) => {
    setSeleccion((prev) => ({ ...prev, [id]: { ...getItem(id), ...patch } }))
  }
  const toggleSel = (id: string, ocItem: typeof itemsPendientes[number]) => {
    const cur = getItem(id)
    if (cur.seleccionado) {
      setItem(id, { seleccionado: false })
    } else {
      setItem(id, {
        seleccionado: true,
        cantidad: Number(ocItem.cantidad_pendiente),
        producto_id: ocItem.producto_id,
      })
    }
  }

  // Items seleccionados con su estado
  const seleccionados = itemsPendientes.filter((it) => getItem(it.id).seleccionado)
  const tieneInventariables = seleccionados.some((it) => it.requiere_stock)
  const tieneServicios = seleccionados.some((it) => !it.requiere_stock)

  // Validaciones cliente
  const errores: string[] = []
  if (seleccionados.length === 0) errores.push('Selecciona al menos 1 item.')
  if (!docNumero.trim()) errores.push('N° de documento obligatorio.')
  if (tieneInventariables && !bodegaId) errores.push('Bodega obligatoria para items inventariables.')
  for (const it of seleccionados) {
    const s = getItem(it.id)
    const cant = typeof s.cantidad === 'number' ? s.cantidad : 0
    if (cant <= 0) {
      errores.push(`Item "${it.descripcion.slice(0, 30)}…": cantidad debe ser > 0.`)
      continue
    }
    if (it.requiere_stock) {
      const productoId = s.producto_id ?? it.producto_id
      if (!productoId) {
        errores.push(`Item "${it.descripcion.slice(0, 30)}…" es inventariable y requiere producto mapeado.`)
      }
    }
    const pendiente = Number(it.cantidad_pendiente)
    if (cant > pendiente && !permiteSobre) {
      errores.push(`Item "${it.descripcion.slice(0, 30)}…": cantidad (${cant}) supera pendiente (${pendiente}). Activa override admin.`)
    }
  }
  if ((permiteSobre || permitePrecio) && justificacion.trim().length < 10) {
    errores.push('Override admin requiere justificación de mínimo 10 caracteres.')
  }

  const canSubmit = errores.length === 0

  const onSubmit = () => {
    if (!canSubmit) {
      toast.error('Revisa los errores marcados')
      return
    }

    const items: RecepcionarOCItemInput[] = seleccionados.map((it) => {
      const s = getItem(it.id)
      const cant = typeof s.cantidad === 'number' ? s.cantidad : 0
      // Si el item OC ya tiene producto_id, usar ese. Si no, usar el mapeado en recepcion.
      const productoId = it.producto_id ?? s.producto_id ?? null
      return {
        oc_item_id: it.id,
        producto_id: productoId,
        cantidad: cant,
        unidad: it.unidad,
        costo_unitario: Number(it.precio_unitario_clp),
        lote: s.lote.trim() || null,
        vencimiento: s.vencimiento || null,
        observacion: s.observacion.trim() || null,
      }
    })

    // Bodega: si solo hay servicios, igual debe pasarse (la RPC valida no NULL).
    // Tomamos la primera bodega si el user no eligio.
    const bodegaFinal = bodegaId || (bodegas?.[0]?.id ?? '')
    if (!bodegaFinal) {
      toast.error('No hay bodega disponible')
      return
    }

    const payload: RecepcionarOCPayload = {
      orden_compra_id: oc.id,
      proveedor_id: oc.proveedor_id,
      bodega_id: bodegaFinal,
      doc_tipo: docTipo,
      doc_numero: docNumero.trim(),
      items,
      observacion: observacion.trim() || null,
      permite_sobrecantidad: permiteSobre,
      permite_precio_distinto: permitePrecio,
      justificacion_override: (permiteSobre || permitePrecio) ? justificacion.trim() : null,
    }

    recepcionar.mutate(payload, {
      onSuccess: (data) => {
        const partes: string[] = []
        if (data.items_stock > 0) partes.push(`${data.items_stock} con stock`)
        if (data.items_documentales > 0) partes.push(`${data.items_documentales} conformidad`)
        toast.success(`Recepción ${data.folio} registrada (${partes.join(', ')})`)
        router.push(`/dashboard/abastecimiento/oc/${oc.id}`)
      },
      onError: (err: unknown) => {
        const msg = err instanceof Error ? err.message : 'Error al recepcionar'
        if (msg.toLowerCase().includes('rol') && msg.toLowerCase().includes('autorizado')) {
          toast.error('No tienes permiso para recepcionar')
        } else if (msg.toLowerCase().includes('override')) {
          toast.error(msg)
        } else if (msg.toLowerCase().includes('cantidad') && msg.toLowerCase().includes('pendiente')) {
          toast.error(msg)
        } else if (msg.toLowerCase().includes('precio')) {
          toast.error(msg)
        } else if (msg.toLowerCase().includes('cerrada') || msg.toLowerCase().includes('anulada')) {
          toast.error(msg)
        } else {
          toast.error(msg)
        }
      },
    })
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-2 flex-wrap">
        <Button type="button" variant="outline" size="sm" onClick={() => router.back()}>
          <ArrowLeft className="h-4 w-4 mr-1" /> Volver
        </Button>
        <h1 className="text-xl font-bold flex items-center gap-2">
          <Package className="h-5 w-5 text-amber-700" />
          Recepcionar OC {oc.numero_oc}
        </h1>
        {oc.numero_oc_externo && (
          <span className="text-sm text-gray-600 font-mono">ext: {oc.numero_oc_externo}</span>
        )}
        <Badge className={oc.origen === 'externa' ? 'bg-purple-100 text-purple-700' : 'bg-gray-100 text-gray-700'}>
          {oc.origen}
        </Badge>
      </div>

      <div className="rounded-lg border border-blue-200 bg-blue-50 p-3 text-xs text-blue-900 flex items-start gap-2">
        <AlertCircle className="h-4 w-4 mt-0.5 shrink-0" />
        <div>
          <strong>Recepción diferenciada.</strong> Los items <span className="font-semibold">inventariables</span> generan stock + capa FIFO.
          Los <span className="font-semibold">servicios</span> generan conformidad documental sin tocar stock.
        </div>
      </div>

      {/* Cabecera del documento */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base">Documento de recepción</CardTitle>
        </CardHeader>
        <CardContent className="grid grid-cols-1 md:grid-cols-3 gap-3">
          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">Tipo *</label>
            <select
              value={docTipo}
              onChange={(e) => setDocTipo(e.target.value as DocTipoProveedor)}
              className="w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-sm"
            >
              <option value="factura">Factura</option>
              <option value="guia">Guía de despacho</option>
              <option value="vale">Vale</option>
              <option value="boleta">Boleta</option>
              <option value="otro">Otro</option>
            </select>
          </div>
          <div className="md:col-span-2">
            <label className="block text-xs font-medium text-gray-700 mb-1">N° documento *</label>
            <Input
              value={docNumero}
              onChange={(e) => setDocNumero(e.target.value)}
              placeholder="ej: 12345"
            />
          </div>
          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">
              Bodega {tieneInventariables && '*'}
            </label>
            <select
              value={bodegaId}
              onChange={(e) => setBodegaId(e.target.value)}
              className={cn(
                'w-full rounded-md border bg-white px-3 py-2 text-sm',
                tieneInventariables && !bodegaId ? 'border-red-400' : 'border-gray-300',
              )}
            >
              <option value="">— Seleccionar —</option>
              {(bodegas ?? []).map((b) => (
                <option key={b.id} value={b.id}>
                  {b.codigo} — {b.nombre}
                </option>
              ))}
            </select>
            {!tieneInventariables && tieneServicios && (
              <div className="text-[11px] text-gray-500 mt-1">
                Solo servicios — bodega es formal, no se mueve stock.
              </div>
            )}
          </div>
          <div className="md:col-span-2">
            <label className="block text-xs font-medium text-gray-700 mb-1">Observación</label>
            <Input
              value={observacion}
              onChange={(e) => setObservacion(e.target.value)}
              placeholder="Notas internas de esta recepción"
            />
          </div>
        </CardContent>
      </Card>

      {/* Items pendientes */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base">
            Items pendientes ({itemsPendientes.length})
            <span className="text-xs font-normal text-gray-600 ml-2">
              {seleccionados.length} seleccionado(s)
            </span>
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-2">
          {itemsPendientes.length === 0 ? (
            <div className="text-center text-sm text-gray-500 py-6 flex flex-col items-center gap-2">
              <CheckCircle2 className="h-8 w-8 text-green-500" />
              No hay items pendientes. La OC está completa.
            </div>
          ) : itemsPendientes.map((it) => {
            const s = getItem(it.id)
            const productoIdFinal = s.producto_id ?? it.producto_id
            const necesitaMapeo = it.requiere_stock && !productoIdFinal
            return (
              <div
                key={it.id}
                className={cn(
                  'rounded-lg border p-3 space-y-2',
                  s.seleccionado ? 'border-amber-300 bg-amber-50' : 'border-gray-200 bg-white',
                )}
              >
                <div className="flex items-start gap-2">
                  <input
                    type="checkbox"
                    checked={s.seleccionado}
                    onChange={() => toggleSel(it.id, it)}
                    className="mt-1 h-4 w-4 cursor-pointer"
                  />
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 flex-wrap">
                      <Badge className={tipoBadgeColor(it.tipo_item)}>{it.tipo_item}</Badge>
                      {it.requiere_stock ? (
                        <Badge className="bg-blue-100 text-blue-700">requiere stock</Badge>
                      ) : (
                        <Badge className="bg-gray-100 text-gray-700">documental</Badge>
                      )}
                      {necesitaMapeo && (
                        <Badge className="bg-amber-100 text-amber-700">pendiente mapeo</Badge>
                      )}
                    </div>
                    <div className="text-sm font-medium mt-1">{it.descripcion}</div>
                    <div className="text-[11px] text-gray-500 font-mono">
                      {it.codigo_externo && <>ext: {it.codigo_externo} · </>}
                      pendiente: {Number(it.cantidad_pendiente).toFixed(2)} {it.unidad}
                      · precio: {formatCLP(Number(it.precio_unitario_clp))}
                      {it.centro_costo_codigo_externo && <> · CC: {it.centro_costo_codigo_externo}</>}
                    </div>
                  </div>
                </div>

                {s.seleccionado && (
                  <div className="pl-6 space-y-2 border-l-2 border-amber-200 ml-2">
                    <div className="grid grid-cols-1 md:grid-cols-3 gap-2">
                      <div>
                        <label className="block text-[11px] font-medium text-gray-700 mb-1">
                          Cantidad a recibir *
                        </label>
                        <Input
                          type="number" step="0.01" min="0.01"
                          value={s.cantidad}
                          onChange={(e) => setItem(it.id, {
                            cantidad: e.target.value === '' ? '' : Number(e.target.value),
                          })}
                        />
                        <div className="text-[10px] text-gray-500 mt-0.5">
                          Pendiente: {Number(it.cantidad_pendiente).toFixed(2)}
                        </div>
                      </div>
                      {it.requiere_stock && (
                        <>
                          <div>
                            <label className="block text-[11px] font-medium text-gray-700 mb-1">Lote</label>
                            <Input
                              value={s.lote}
                              onChange={(e) => setItem(it.id, { lote: e.target.value })}
                              placeholder="opcional"
                            />
                          </div>
                          <div>
                            <label className="block text-[11px] font-medium text-gray-700 mb-1">Vencimiento</label>
                            <Input
                              type="date"
                              value={s.vencimiento}
                              onChange={(e) => setItem(it.id, { vencimiento: e.target.value })}
                            />
                          </div>
                        </>
                      )}
                    </div>

                    {necesitaMapeo && (
                      <div>
                        <label className="block text-[11px] font-medium text-amber-800 mb-1">
                          Mapear a producto *
                        </label>
                        <select
                          value={s.producto_id ?? ''}
                          onChange={(e) => setItem(it.id, { producto_id: e.target.value || null })}
                          className="w-full rounded-md border border-amber-400 bg-white px-2 py-1.5 text-sm"
                        >
                          <option value="">— Seleccionar producto —</option>
                          {productos.map((p) => (
                            <option key={p.id} value={p.id}>{p.codigo} — {p.nombre}</option>
                          ))}
                        </select>
                        <div className="text-[10px] text-amber-700 mt-0.5">
                          Este item es inventariable y no tiene producto asociado en la OC. Debes mapearlo para crear capa FIFO.
                        </div>
                      </div>
                    )}

                    <div>
                      <label className="block text-[11px] font-medium text-gray-700 mb-1">Observación de este item</label>
                      <Input
                        value={s.observacion}
                        onChange={(e) => setItem(it.id, { observacion: e.target.value })}
                        placeholder={!it.requiere_stock ? 'ej: servicio recibido conforme' : 'opcional'}
                      />
                    </div>
                  </div>
                )}
              </div>
            )
          })}
        </CardContent>
      </Card>

      {/* Override admin */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base flex items-center gap-2">
            <FileCheck className="h-4 w-4 text-gray-600" />
            Override admin (opcional)
          </CardTitle>
          <p className="text-xs text-gray-600">
            Solo administradores. Permite recibir más cantidad que pendiente o a precio distinto al OC.
          </p>
        </CardHeader>
        <CardContent className="space-y-2">
          <div className="flex items-center gap-3 flex-wrap">
            <label className="flex items-center gap-2 text-sm">
              <input
                type="checkbox"
                checked={overrideAdmin}
                onChange={(e) => {
                  setOverrideAdmin(e.target.checked)
                  if (!e.target.checked) {
                    setPermiteSobre(false)
                    setPermitePrecio(false)
                  }
                }}
                className="h-4 w-4"
              />
              Activar override
            </label>
            {overrideAdmin && (
              <>
                <label className="flex items-center gap-2 text-sm">
                  <input type="checkbox" checked={permiteSobre} onChange={(e) => setPermiteSobre(e.target.checked)} className="h-4 w-4" />
                  Permitir sobrecantidad
                </label>
                <label className="flex items-center gap-2 text-sm">
                  <input type="checkbox" checked={permitePrecio} onChange={(e) => setPermitePrecio(e.target.checked)} className="h-4 w-4" />
                  Permitir precio distinto
                </label>
              </>
            )}
          </div>
          {overrideAdmin && (permiteSobre || permitePrecio) && (
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">Justificación * (mín 10 caracteres)</label>
              <Input
                value={justificacion}
                onChange={(e) => setJustificacion(e.target.value)}
                placeholder="ej: proveedor entregó más unidades sin costo adicional, autorizado por jefe operaciones"
              />
            </div>
          )}
        </CardContent>
      </Card>

      {/* Errores y submit */}
      {errores.length > 0 && seleccionados.length > 0 && (
        <div className="rounded-lg border border-amber-200 bg-amber-50 p-3 text-xs text-amber-900 space-y-1">
          <div className="font-semibold flex items-center gap-1">
            <AlertTriangle className="h-4 w-4" /> Antes de guardar:
          </div>
          <ul className="list-disc list-inside">
            {errores.map((e, i) => <li key={i}>{e}</li>)}
          </ul>
        </div>
      )}

      <Card>
        <CardContent className="flex items-center justify-between py-4">
          <Button type="button" variant="outline" onClick={() => router.back()} disabled={recepcionar.isPending}>
            Cancelar
          </Button>
          <Button type="button" onClick={onSubmit} disabled={!canSubmit || recepcionar.isPending}>
            {recepcionar.isPending ? <Spinner className="h-4 w-4 mr-2" /> : <Save className="h-4 w-4 mr-2" />}
            {recepcionar.isPending ? 'Recepcionando...' : 'Registrar recepción'}
          </Button>
        </CardContent>
      </Card>
    </div>
  )
}
