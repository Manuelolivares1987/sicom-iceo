'use client'

import { useEffect, useMemo, useState } from 'react'
import {
  AlertTriangle, CheckCircle2, Save, FileSignature,
} from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Spinner } from '@/components/ui/spinner'
import { SignaturePad } from '@/components/ui/signature-pad'
import { ChecklistV2ItemRow } from '@/components/flota/checklist-v2-item'
import {
  cargarInstance, cargarItemsInstance,
  subirFirma, cerrarChecklist,
  BLOQUE_LABELS,
  type ChecklistV2Item, type ChecklistV2Instance, type BloqueChecklist,
} from '@/lib/services/checklist-v2'

function dataUrlToBlob(dataUrl: string): Blob {
  const base64 = dataUrl.split(',')[1] ?? ''
  const bin = atob(base64)
  const buf = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i)
  return new Blob([buf], { type: 'image/png' })
}

interface Props {
  instanceId: string
  onClosed?: () => void
}

/**
 * Wizard reutilizable para llenar un checklist V02 (entrega o recepcion).
 * Asume que el `checklist_v2_instance` YA fue creado (por trigger o
 * por fn_inicializar_checklist_v2). Si esta cerrado lo muestra read-only.
 */
export function ChecklistV2Wizard({ instanceId, onClosed }: Props) {
  const [instance, setInstance]   = useState<ChecklistV2Instance | null>(null)
  const [items, setItems]         = useState<ChecklistV2Item[]>([])
  const [loading, setLoading]     = useState(true)
  const [error, setError]         = useState<string | null>(null)
  const [bloqueActivo, setBloqueActivo] = useState<BloqueChecklist | null>(null)

  const [operadorRut, setOperadorRut]       = useState('')
  const [operadorNombre, setOperadorNombre] = useState('')
  const [clienteRut, setClienteRut]         = useState('')
  const [clienteNombre, setClienteNombre]   = useState('')
  const [firmaOperadorDU, setFirmaOperadorDU] = useState<string | null>(null)
  const [firmaClienteDU, setFirmaClienteDU]   = useState<string | null>(null)
  const [submitting, setSubmitting] = useState(false)

  const cargar = async () => {
    setLoading(true); setError(null)
    try {
      const [inst, its] = await Promise.all([
        cargarInstance(instanceId),
        cargarItemsInstance(instanceId),
      ])
      setInstance(inst)
      setItems(its)
      const bloques = Array.from(new Set(its.map((i) => i.bloque))) as BloqueChecklist[]
      const primero = bloques.find((b) => its.some((i) => i.bloque === b && i.resultado === 'pendiente'))
                  ?? bloques[0]
      setBloqueActivo(primero ?? null)
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { cargar() /* eslint-disable-line react-hooks/exhaustive-deps */ }, [instanceId])

  const bloques = useMemo(
    () => Array.from(new Set(items.map((i) => i.bloque))) as BloqueChecklist[],
    [items]
  )

  const stats = useMemo(() => {
    const total      = items.length
    const ok         = items.filter((i) => i.resultado === 'ok').length
    const no_ok      = items.filter((i) => i.resultado === 'no_ok').length
    const na         = items.filter((i) => i.resultado === 'na').length
    const pendientes = items.filter((i) => i.resultado === 'pendiente').length
    const obligPend  = items.filter((i) => i.obligatorio && i.resultado === 'pendiente').length
    const fotoPend   = items.filter((i) => i.requiere_foto && i.obligatorio && !i.foto_url).length
    return { total, ok, no_ok, na, pendientes, obligPend, fotoPend }
  }, [items])

  const itemsBloque = useMemo(
    () => bloqueActivo ? items.filter((i) => i.bloque === bloqueActivo).sort((a, b) => a.orden - b.orden) : [],
    [bloqueActivo, items]
  )

  const handleItemChange = (updated: ChecklistV2Item) => {
    setItems((prev) => prev.map((i) => (i.id === updated.id ? updated : i)))
  }

  const handleCerrar = async () => {
    if (!instance) return
    if (!firmaOperadorDU || !firmaClienteDU) {
      setError('Faltan firmas: operador y cliente son obligatorias.')
      return
    }
    if (stats.obligPend > 0) {
      setError(`Faltan ${stats.obligPend} ítems obligatorios por responder.`)
      return
    }
    if (stats.fotoPend > 0) {
      setError(`Faltan ${stats.fotoPend} fotos obligatorias.`)
      return
    }
    setSubmitting(true); setError(null)
    try {
      const [urlOp, urlCli] = await Promise.all([
        subirFirma(instance.id, 'operador', dataUrlToBlob(firmaOperadorDU)),
        subirFirma(instance.id, 'cliente',  dataUrlToBlob(firmaClienteDU)),
      ])
      await cerrarChecklist({
        instanceId:        instance.id,
        firmaOperadorUrl:  urlOp,
        firmaClienteUrl:   urlCli,
        operadorRut, operadorNombre,
        clienteRut,   clienteNombre,
      })
      await cargar()
      onClosed?.()
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setSubmitting(false)
    }
  }

  if (loading) {
    return <div className="flex h-64 items-center justify-center"><Spinner /></div>
  }
  if (!instance) {
    return (
      <Card className="border-red-200 bg-red-50">
        <CardContent className="flex items-center gap-2 p-4 text-sm text-red-700">
          <AlertTriangle className="h-4 w-4" /> {error ?? 'No se pudo cargar el checklist'}
        </CardContent>
      </Card>
    )
  }

  const bloqueado    = instance.estado === 'cerrado'
  const esEntrega    = instance.momento_uso === 'entrega_arriendo'
  const cierreLabel  = esEntrega
    ? 'Una vez cerrado, el activo podrá cambiar a estado arrendado. Tienes 48 horas para usar este check-list.'
    : 'Al cerrar quedan registrados los hallazgos. Después puedes aplicar el diff al informe de recepción.'

  return (
    <div className="space-y-4">
      {/* Stats */}
      <div className="grid grid-cols-2 gap-2 sm:grid-cols-5">
        <StatBox color="bg-green-50 text-green-700"  label="OK"        v={stats.ok} />
        <StatBox color="bg-red-50 text-red-700"      label="NO OK"     v={stats.no_ok} />
        <StatBox color="bg-gray-50 text-gray-700"    label="N/A"       v={stats.na} />
        <StatBox color="bg-amber-50 text-amber-700"  label="Pendientes" v={stats.pendientes} />
        <StatBox color="bg-blue-50 text-blue-700"    label="Total"     v={stats.total} />
      </div>

      {/* Tabs de bloques */}
      <div className="flex flex-wrap gap-2 border-b pb-2">
        {bloques.map((b) => {
          const tot = items.filter((i) => i.bloque === b).length
          const pend = items.filter((i) => i.bloque === b && i.resultado === 'pendiente').length
          return (
            <button
              key={b}
              onClick={() => setBloqueActivo(b)}
              className={`rounded-t-md px-3 py-1.5 text-sm transition-colors ${
                bloqueActivo === b
                  ? 'border-b-2 border-blue-600 bg-blue-50 font-semibold text-blue-700'
                  : 'text-gray-600 hover:bg-gray-50'
              }`}>
              {BLOQUE_LABELS[b]}
              <span className="ml-1 text-xs text-gray-500">
                {pend > 0 ? `(${pend}/${tot} pend)` : `(${tot})`}
              </span>
            </button>
          )
        })}
      </div>

      {/* Ítems del bloque activo */}
      <div className="space-y-2">
        {itemsBloque.length === 0 ? (
          <div className="rounded-lg border border-dashed p-6 text-center text-sm text-muted-foreground">
            No hay ítems en este bloque para este tipo de equipamiento.
          </div>
        ) : (
          itemsBloque.map((i) => (
            <ChecklistV2ItemRow
              key={i.id}
              item={i}
              instanceId={instance.id}
              bloqueado={bloqueado}
              onChange={handleItemChange}
            />
          ))
        )}
      </div>

      {/* Cierre — firmas */}
      {!bloqueado && (
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-base">
              <FileSignature className="h-4 w-4" /> Cierre del check-list
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="grid gap-4 sm:grid-cols-2">
              <div className="space-y-2">
                <h3 className="text-sm font-semibold">Operador Pillado</h3>
                <Input placeholder="RUT operador" value={operadorRut}
                       onChange={(e) => setOperadorRut(e.target.value)} />
                <Input placeholder="Nombre operador" value={operadorNombre}
                       onChange={(e) => setOperadorNombre(e.target.value)} />
                <div className="rounded border bg-white p-1">
                  <SignaturePad label="Firma operador"
                                onCapture={(d) => setFirmaOperadorDU(d)}
                                existingUrl={firmaOperadorDU} />
                </div>
              </div>
              <div className="space-y-2">
                <h3 className="text-sm font-semibold">Representante cliente</h3>
                <Input placeholder="RUT cliente" value={clienteRut}
                       onChange={(e) => setClienteRut(e.target.value)} />
                <Input placeholder="Nombre cliente" value={clienteNombre}
                       onChange={(e) => setClienteNombre(e.target.value)} />
                <div className="rounded border bg-white p-1">
                  <SignaturePad label="Firma cliente"
                                onCapture={(d) => setFirmaClienteDU(d)}
                                existingUrl={firmaClienteDU} />
                </div>
              </div>
            </div>

            {error && (
              <div className="flex items-center gap-2 rounded border border-red-200 bg-red-50 p-2 text-sm text-red-700">
                <AlertTriangle className="h-4 w-4" /> {error}
              </div>
            )}

            <div className="flex flex-wrap items-center justify-between gap-2">
              <div className="text-xs text-muted-foreground">{cierreLabel}</div>
              <Button onClick={handleCerrar} disabled={submitting}
                      className="gap-1 bg-green-600 hover:bg-green-700">
                {submitting ? <Save className="h-4 w-4 animate-pulse" /> : <CheckCircle2 className="h-4 w-4" />}
                Cerrar check-list y firmar
              </Button>
            </div>
          </CardContent>
        </Card>
      )}
    </div>
  )
}

function StatBox({ color, label, v }: { color: string; label: string; v: number }) {
  return (
    <div className={`rounded-lg border px-3 py-2 ${color}`}>
      <div className="text-xs font-medium opacity-80">{label}</div>
      <div className="text-xl font-bold">{v}</div>
    </div>
  )
}
