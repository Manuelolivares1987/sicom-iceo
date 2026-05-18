'use client'

import { useEffect, useMemo, useState } from 'react'
import { useParams, useRouter } from 'next/navigation'
import Link from 'next/link'
import {
  ArrowLeft, ClipboardList, AlertTriangle, CheckCircle2, Save, FileSignature,
} from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Badge } from '@/components/ui/badge'
import { Spinner } from '@/components/ui/spinner'
import { SignaturePad } from '@/components/ui/signature-pad'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useAuth } from '@/contexts/auth-context'
import { supabase } from '@/lib/supabase'
import { ChecklistV2ItemRow } from '@/components/flota/checklist-v2-item'
import {
  iniciarChecklistEntrega, cargarInstance, cargarItemsInstance,
  subirFirma, cerrarChecklist,
  BLOQUE_LABELS,
  type ChecklistV2Item, type ChecklistV2Instance, type BloqueChecklist,
} from '@/lib/services/checklist-v2'

type ActivoInfo = {
  id: string
  codigo: string
  nombre: string | null
  patente: string | null
  tipo_equipamiento: string
  contrato_id: string | null
  contrato_codigo: string | null
  cliente: string | null
  horas_uso_actual: number | null
  kilometraje_actual: number | null
}

function dataUrlToBlob(dataUrl: string): Blob {
  const base64 = dataUrl.split(',')[1] ?? ''
  const bin = atob(base64)
  const buf = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i)
  return new Blob([buf], { type: 'image/png' })
}

export default function ChecklistSalidaWizardPage() {
  useRequireAuth()
  const { user } = useAuth()
  const params = useParams<{ activoId: string }>()
  const router = useRouter()
  const activoId = params.activoId

  const [activo, setActivo]       = useState<ActivoInfo | null>(null)
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
      // 1. Activo + contrato
      const { data: act, error: errA } = await supabase
        .from('activos')
        .select(`
          id, codigo, nombre, patente, tipo_equipamiento,
          horas_uso_actual, kilometraje_actual,
          contrato:contratos!contrato_id ( id, codigo, cliente )
        `)
        .eq('id', activoId)
        .single()
      if (errA || !act) throw errA ?? new Error('Activo no encontrado')

      type ActRow = {
        id: string; codigo: string; nombre: string | null; patente: string | null
        tipo_equipamiento: string; horas_uso_actual: number | null
        kilometraje_actual: number | null
        contrato: { id: string; codigo: string; cliente: string } | null
      }
      const a = act as unknown as ActRow
      const info: ActivoInfo = {
        id: a.id, codigo: a.codigo, nombre: a.nombre, patente: a.patente,
        tipo_equipamiento: a.tipo_equipamiento,
        horas_uso_actual: a.horas_uso_actual,
        kilometraje_actual: a.kilometraje_actual,
        contrato_id: a.contrato?.id ?? null,
        contrato_codigo: a.contrato?.codigo ?? null,
        cliente: a.contrato?.cliente ?? null,
      }
      setActivo(info)

      // 2. Iniciar (o reabrir) checklist
      const { instanceId } = await iniciarChecklistEntrega({
        activoId:    info.id,
        contratoId:  info.contrato_id,
        horometro:   info.horas_uso_actual,
        kilometraje: info.kilometraje_actual,
        operadorId:  user?.id ?? null,
      })

      // 3. Cargar cabecera + items
      const [inst, its] = await Promise.all([
        cargarInstance(instanceId),
        cargarItemsInstance(instanceId),
      ])
      setInstance(inst)
      setItems(its)
      // Primer bloque con items pendientes
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

  useEffect(() => { cargar() /* eslint-disable-line react-hooks/exhaustive-deps */ }, [activoId])

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
      router.push('/dashboard/flota/checklist-salida?ok=1')
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setSubmitting(false)
    }
  }

  if (loading) {
    return <div className="flex h-96 items-center justify-center"><Spinner /></div>
  }
  if (!activo || !instance) {
    return (
      <div className="p-6">
        <Card className="border-red-200 bg-red-50">
          <CardContent className="flex items-center gap-2 p-4 text-sm text-red-700">
            <AlertTriangle className="h-4 w-4" /> {error ?? 'No se pudo cargar el checklist'}
          </CardContent>
        </Card>
      </div>
    )
  }

  const bloqueado = instance.estado === 'cerrado'

  return (
    <div className="space-y-4 p-4 sm:p-6">
      {/* Header */}
      <div className="flex flex-wrap items-center gap-3">
        <Link href="/dashboard/flota/checklist-salida">
          <Button variant="ghost" size="sm" className="gap-1">
            <ArrowLeft className="h-4 w-4" /> Volver
          </Button>
        </Link>
        <div className="flex-1">
          <h1 className="flex items-center gap-2 text-xl font-bold">
            <ClipboardList className="h-5 w-5 text-blue-600" />
            Check-List Entrega V02 — {activo.codigo}
          </h1>
          <p className="text-xs text-muted-foreground">
            {activo.patente && `${activo.patente} · `}
            {activo.cliente ? `Cliente: ${activo.cliente}` : 'Sin contrato'}
            {activo.contrato_codigo && ` · Contrato ${activo.contrato_codigo}`}
          </p>
        </div>
        <Badge variant="operativo">{activo.tipo_equipamiento.replace(/_/g, ' ')}</Badge>
        {bloqueado && <Badge variant="ejecutada_ok">CERRADO</Badge>}
      </div>

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
                <h3 className="text-sm font-semibold">Operador Pillado (entrega)</h3>
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
                <h3 className="text-sm font-semibold">Representante cliente (recibe)</h3>
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
              <div className="text-xs text-muted-foreground">
                Una vez cerrado, el activo podrá cambiar a estado <b>arrendado</b>.
                Tienes 48 horas para usar este check-list.
              </div>
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
