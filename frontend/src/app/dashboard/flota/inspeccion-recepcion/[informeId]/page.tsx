'use client'

import { useMemo, useState } from 'react'
import { useParams, useRouter } from 'next/navigation'
import {
  ClipboardCheck, Camera, AlertTriangle, ChevronRight, ChevronLeft,
  CheckCircle2, XCircle, Plus, Trash2, PenTool, Send, Package, Wrench,
} from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Badge } from '@/components/ui/badge'
import { Spinner } from '@/components/ui/spinner'
import { SignaturePad } from '@/components/ui/signature-pad'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useChecklistOT } from '@/hooks/use-verificacion'
import { useBuscarProductos } from '@/hooks/use-ot-materiales'
import {
  useInformeRecepcion,
  useHallazgosInforme,
  useCostosInforme,
  useTarifasHH,
  useAgregarHallazgo,
  useActualizarHallazgo,
  useEliminarHallazgo,
  useAgregarCosto,
  useEliminarCosto,
  useCerrarInspeccionRecepcion,
} from '@/hooks/use-informe-recepcion'
import {
  subirFotoHallazgo, subirFirmaInforme,
  type GravedadHallazgo, type TipoCostoRecepcion,
} from '@/lib/services/informe-recepcion'
import { cn } from '@/lib/utils'

type Step = 1 | 2 | 3 | 4

export default function InspeccionRecepcionPage() {
  useRequireAuth()
  const { informeId } = useParams<{ informeId: string }>()
  const router = useRouter()

  const [step, setStep] = useState<Step>(1)
  const [errorMsg, setErrorMsg] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)
  const [firmaDataUrl, setFirmaDataUrl] = useState<string | null>(null)

  const { data: informe, isLoading: loadingInf } = useInformeRecepcion(informeId)
  const { data: checklist = [], isLoading: loadingCL } = useChecklistOT(informe?.ot_inspeccion_id ?? undefined)
  const { data: hallazgos = [] } = useHallazgosInforme(informeId)
  const { data: costos = [] } = useCostosInforme(informeId)

  const addHal = useAgregarHallazgo()
  const updHal = useActualizarHallazgo()
  const delHal = useEliminarHallazgo()
  const addCosto = useAgregarCosto()
  const delCosto = useEliminarCosto()
  const cerrarMut = useCerrarInspeccionRecepcion()

  const totalCobrable = useMemo(
    () => costos.filter((c) => c.cobrable_cliente).reduce((s, c) => s + Number(c.total), 0),
    [costos],
  )
  const totalNoCobrable = useMemo(
    () => costos.filter((c) => !c.cobrable_cliente).reduce((s, c) => s + Number(c.total), 0),
    [costos],
  )

  // Ítems agrupados por sección
  const grupos = useMemo(() => {
    const map = new Map<string, typeof checklist>()
    for (const it of checklist) {
      const sec = it.seccion ?? 'GENERAL'
      if (!map.has(sec)) map.set(sec, [])
      map.get(sec)!.push(it)
    }
    return Array.from(map.entries())
  }, [checklist])

  const enviar = async () => {
    if (!informeId || !firmaDataUrl) {
      setErrorMsg('Falta firma del técnico')
      return
    }
    setSaving(true); setErrorMsg(null)
    try {
      const { data: firmaUrl, error: fErr } = await subirFirmaInforme(informeId, 'tecnico', firmaDataUrl)
      if (fErr || !firmaUrl) throw fErr ?? new Error('Error subiendo firma')
      await cerrarMut.mutateAsync({ informeId, firmaTecnicoUrl: firmaUrl })
      router.push('/dashboard/flota')
    } catch (err) {
      setErrorMsg(err instanceof Error ? err.message : 'Error al cerrar')
    } finally {
      setSaving(false)
    }
  }

  if (loadingInf || loadingCL) {
    return <div className="flex h-64 items-center justify-center"><Spinner className="h-8 w-8" /></div>
  }
  if (!informe) {
    return (
      <Card>
        <CardContent className="py-10 text-center space-y-2">
          <AlertTriangle className="h-10 w-10 text-amber-500 mx-auto" />
          <h3 className="text-lg font-semibold">Informe no encontrado</h3>
        </CardContent>
      </Card>
    )
  }

  const stepLabels: Record<Step, string> = {
    1: 'Checklist',
    2: 'Costos base',
    3: 'Firma',
    4: 'Enviar',
  }

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="rounded-xl bg-gradient-to-r from-orange-600 to-red-700 p-5 text-white">
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-xl font-bold flex items-center gap-2">
              <ClipboardCheck className="h-6 w-6" />
              Inspección de Recepción · {informe.folio ?? informe.id.slice(0, 8)}
            </h1>
            <p className="text-xs text-white/80 mt-1">
              Cliente: {informe.cliente_nombre ?? '—'} · Entregado: {informe.fecha_entrega_arriendo ?? '—'} ·
              Recibido: {informe.fecha_recepcion}
            </p>
          </div>
          <div className="text-right">
            <div className="text-xs text-white/70">Cobrable al cliente</div>
            <div className="text-2xl font-bold">${fmt(totalCobrable)}</div>
          </div>
        </div>
        <div className="mt-4 flex gap-2">
          {([1, 2, 3, 4] as Step[]).map((s) => (
            <button
              key={s}
              className={cn(
                'flex-1 rounded-md px-2 py-1 text-xs font-medium transition',
                step === s ? 'bg-white text-orange-700' : 'bg-white/20 text-white',
              )}
              onClick={() => setStep(s)}
            >
              {s}. {stepLabels[s]}
            </button>
          ))}
        </div>
      </div>

      {errorMsg && (
        <div className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">{errorMsg}</div>
      )}

      {/* ─── Step 1 — Checklist + hallazgos ─── */}
      {step === 1 && (
        <div className="space-y-4">
          <p className="text-xs text-gray-500 rounded border bg-blue-50 border-blue-200 p-2">
            Revisa cada ítem como vino de vuelta del cliente. Si encuentras un daño, haz click en
            "Registrar daño" — el sistema lo anotará como hallazgo (por defecto atribuible al cliente,
            se puede editar después).
          </p>

          {grupos.map(([seccion, items]) => (
            <Card key={seccion}>
              <CardHeader className="pb-2 bg-gray-50">
                <CardTitle className="text-sm text-gray-700">{seccion}</CardTitle>
              </CardHeader>
              <CardContent className="divide-y">
                {items.map((it) => {
                  const existeHallazgo = hallazgos.find((h) => h.checklist_item_id === it.id)
                  return (
                    <div key={it.id} className="flex items-start gap-2 py-2 text-sm">
                      <span className="text-xs text-gray-400 font-mono w-8">#{it.orden}</span>
                      <div className="flex-1">
                        <div>{it.descripcion}</div>
                        {existeHallazgo && (
                          <div className="mt-1 text-xs text-red-700">
                            ⚠ Daño registrado ({existeHallazgo.gravedad}) —
                            {existeHallazgo.atribuible_cliente ? ' cobrable' : ' no cobrable'}
                          </div>
                        )}
                      </div>
                      {existeHallazgo ? (
                        <button
                          className="text-xs text-red-600 hover:underline"
                          onClick={() => delHal.mutate({ id: existeHallazgo.id, informeId: informeId! })}
                        >
                          Quitar daño
                        </button>
                      ) : (
                        <button
                          className="text-xs text-amber-700 hover:underline"
                          onClick={() => addHal.mutate({
                            informe_id: informeId!,
                            checklist_item_id: it.id,
                            seccion,
                            descripcion: it.descripcion,
                            gravedad: 'menor',
                            atribuible_cliente: true,
                          })}
                        >
                          + Registrar daño
                        </button>
                      )}
                    </div>
                  )
                })}
              </CardContent>
            </Card>
          ))}

          {/* Hallazgos con edición */}
          {hallazgos.length > 0 && (
            <Card>
              <CardHeader className="pb-2">
                <CardTitle className="text-base">Hallazgos registrados ({hallazgos.length})</CardTitle>
              </CardHeader>
              <CardContent className="space-y-2">
                {hallazgos.map((h) => (
                  <HallazgoEditor
                    key={h.id}
                    hallazgo={h}
                    informeId={informeId!}
                    onEliminar={() => delHal.mutate({ id: h.id, informeId: informeId! })}
                  />
                ))}
              </CardContent>
            </Card>
          )}

          <div className="flex justify-end">
            <Button variant="primary" onClick={() => setStep(2)}>
              Costos base <ChevronRight className="h-4 w-4" />
            </Button>
          </div>
        </div>
      )}

      {/* ─── Step 2 — Costos base ─── */}
      {step === 2 && (
        <div className="space-y-4">
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-base">Pre-estimación de costos</CardTitle>
              <p className="text-xs text-gray-500">
                Agrega lo que sabes HOY (repuestos, HH mecánico, servicios). El encargado de cobros
                refinará y marcará qué se cobra al cliente.
              </p>
            </CardHeader>
            <CardContent className="space-y-3">
              <FormAgregarCosto informeId={informeId!} onAdd={(p) => addCosto.mutate(p)} />

              {costos.length > 0 && (
                <div className="divide-y rounded border">
                  {costos.map((c) => (
                    <div key={c.id} className="p-2 flex items-center gap-2 text-sm">
                      <Badge className="bg-gray-100 text-gray-700 text-[10px]">{c.tipo}</Badge>
                      <div className="flex-1 min-w-0">
                        <div className="truncate">{c.descripcion}</div>
                        <div className="text-[11px] text-gray-500">
                          {c.cantidad} {c.unidad ?? ''} × ${fmt(c.precio_unitario)}
                        </div>
                      </div>
                      <div className="text-right">
                        <div className="font-semibold">${fmt(c.total)}</div>
                        <div className="text-[10px] text-gray-500">
                          {c.cobrable_cliente ? 'Cobrable' : 'Absorbido'}
                        </div>
                      </div>
                      <button
                        className="text-gray-400 hover:text-red-600"
                        onClick={() => delCosto.mutate({ id: c.id, informeId: informeId! })}
                      >
                        <Trash2 className="h-4 w-4" />
                      </button>
                    </div>
                  ))}
                </div>
              )}

              <div className="grid grid-cols-2 gap-3 pt-2 border-t">
                <SummaryCell label="Cobrable al cliente" value={`$${fmt(totalCobrable)}`} color="text-green-700" />
                <SummaryCell label="Absorbido empresa" value={`$${fmt(totalNoCobrable)}`} color="text-gray-700" />
              </div>
            </CardContent>
          </Card>

          <div className="flex justify-between">
            <Button variant="ghost" onClick={() => setStep(1)}><ChevronLeft className="h-4 w-4" /> Checklist</Button>
            <Button variant="primary" onClick={() => setStep(3)}>Firma <ChevronRight className="h-4 w-4" /></Button>
          </div>
        </div>
      )}

      {/* ─── Step 3 — Firma ─── */}
      {step === 3 && (
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-base flex items-center gap-2">
              <PenTool className="h-4 w-4" /> Firma del técnico inspector
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            <p className="text-xs text-gray-500">
              Al firmar pasas el informe a "borrador". Un encargado de cobros distinto a ti lo revisará,
              ajustará costos, marcará lo cobrable y emitirá el informe final con PDF.
            </p>
            <SignaturePad onCapture={setFirmaDataUrl} label="Firma del técnico" />
            <div className="flex justify-between">
              <Button variant="ghost" onClick={() => setStep(2)}><ChevronLeft className="h-4 w-4" /> Costos</Button>
              <Button variant="primary" onClick={() => setStep(4)} disabled={!firmaDataUrl}>
                Enviar <ChevronRight className="h-4 w-4" />
              </Button>
            </div>
          </CardContent>
        </Card>
      )}

      {/* ─── Step 4 — Resumen y enviar ─── */}
      {step === 4 && (
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-base">Resumen y envío a revisión</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            <div className="grid grid-cols-2 gap-3 text-sm">
              <SummaryCell label="Hallazgos" value={String(hallazgos.length)} />
              <SummaryCell label="Atribuibles cliente" value={String(hallazgos.filter((h) => h.atribuible_cliente).length)} color="text-red-700" />
              <SummaryCell label="Ítems de costo" value={String(costos.length)} />
              <SummaryCell label="Total cobrable estimado" value={`$${fmt(totalCobrable)}`} color="text-green-700" />
            </div>
            <p className="text-xs text-gray-500">
              Al enviar, el informe queda en estado <strong>borrador</strong>. Un encargado de cobros lo
              revisará desde <code>/dashboard/flota/recepcion/{informeId}/emitir</code>.
            </p>
            <div className="flex justify-between">
              <Button variant="ghost" onClick={() => setStep(3)}><ChevronLeft className="h-4 w-4" /> Firma</Button>
              <Button variant="primary" onClick={enviar} loading={saving} disabled={!firmaDataUrl}>
                <Send className="h-4 w-4" /> Enviar a revisión
              </Button>
            </div>
          </CardContent>
        </Card>
      )}
    </div>
  )
}

// ────────────────────────────────────────────────────────
// Subcomponentes
// ────────────────────────────────────────────────────────
function HallazgoEditor({
  hallazgo, informeId, onEliminar,
}: {
  hallazgo: any
  informeId: string
  onEliminar: () => void
}) {
  const upd = useActualizarHallazgo()
  const [uploading, setUploading] = useState(false)

  const handleFoto = async (file: File) => {
    setUploading(true)
    try {
      const { data, error } = await subirFotoHallazgo(informeId, hallazgo.id, file)
      if (error || !data) throw error
      upd.mutate({
        id: hallazgo.id,
        informeId,
        patch: { fotos: [...(hallazgo.fotos ?? []), data] },
      })
    } finally {
      setUploading(false)
    }
  }

  return (
    <div className="rounded border border-amber-200 bg-amber-50/40 p-2 space-y-2 text-sm">
      <div className="flex items-start gap-2">
        <div className="flex-1">
          <div className="font-medium">{hallazgo.descripcion}</div>
          <div className="text-xs text-gray-500">{hallazgo.seccion}</div>
        </div>
        <button className="text-red-500" onClick={onEliminar}>
          <Trash2 className="h-4 w-4" />
        </button>
      </div>
      <div className="grid grid-cols-2 gap-2">
        <select
          className="h-9 rounded border border-gray-300 px-2 text-sm"
          value={hallazgo.gravedad}
          onChange={(e) => upd.mutate({ id: hallazgo.id, informeId, patch: { gravedad: e.target.value as GravedadHallazgo } })}
        >
          <option value="menor">Daño menor</option>
          <option value="mayor">Daño mayor</option>
          <option value="critica">Crítico</option>
        </select>
        <label className="flex items-center gap-2 text-xs">
          <input
            type="checkbox"
            checked={hallazgo.atribuible_cliente}
            onChange={(e) => upd.mutate({
              id: hallazgo.id, informeId,
              patch: { atribuible_cliente: e.target.checked },
            })}
          />
          Atribuible al cliente (cobrable)
        </label>
      </div>
      <textarea
        className="w-full rounded border border-gray-300 p-1.5 text-xs"
        placeholder="Observación / detalle del daño"
        defaultValue={hallazgo.observacion ?? ''}
        onBlur={(e) => upd.mutate({ id: hallazgo.id, informeId, patch: { observacion: e.target.value } })}
      />
      <div className="flex items-center gap-2">
        {(hallazgo.fotos ?? []).map((url: string, i: number) => (
          <img key={i} src={url} alt="" className="h-16 w-16 rounded border object-cover" />
        ))}
        <label className="cursor-pointer inline-flex items-center gap-1 rounded bg-blue-600 px-2 py-1 text-[11px] text-white hover:bg-blue-700">
          <Camera className="h-3 w-3" />
          {uploading ? 'Subiendo…' : 'Foto'}
          <input
            type="file"
            accept="image/*"
            capture="environment"
            className="hidden"
            disabled={uploading}
            onChange={(e) => {
              const f = e.target.files?.[0]
              if (f) handleFoto(f)
            }}
          />
        </label>
      </div>
    </div>
  )
}

function FormAgregarCosto({
  informeId, onAdd,
}: {
  informeId: string
  onAdd: (payload: {
    informe_id: string
    tipo: TipoCostoRecepcion
    descripcion: string
    cantidad: number
    unidad?: string | null
    precio_unitario: number
    producto_id?: string | null
    tarifa_hh_id?: string | null
    cobrable_cliente?: boolean
  }) => void
}) {
  const [tipo, setTipo] = useState<TipoCostoRecepcion>('repuesto')
  const [desc, setDesc] = useState('')
  const [cant, setCant] = useState('1')
  const [precio, setPrecio] = useState('')
  const [unidad, setUnidad] = useState('')
  const [prodId, setProdId] = useState<string | null>(null)
  const [tarifaId, setTarifaId] = useState<string | null>(null)
  const [cobrable, setCobrable] = useState(true)
  const [busqueda, setBusqueda] = useState('')

  const { data: productos = [] } = useBuscarProductos(busqueda)
  const { data: tarifas = [] } = useTarifasHH()

  const handleAdd = () => {
    if (!desc || !cant || !precio) return
    onAdd({
      informe_id: informeId,
      tipo, descripcion: desc,
      cantidad: Number(cant),
      unidad: unidad || null,
      precio_unitario: Number(precio),
      producto_id: prodId,
      tarifa_hh_id: tarifaId,
      cobrable_cliente: cobrable,
    })
    // reset
    setDesc(''); setCant('1'); setPrecio(''); setUnidad(''); setProdId(null); setTarifaId(null); setBusqueda('')
  }

  return (
    <div className="rounded border border-dashed p-3 space-y-2 bg-gray-50/50">
      <div className="grid grid-cols-1 sm:grid-cols-4 gap-2">
        <select
          className="h-10 rounded border border-gray-300 px-2 text-sm"
          value={tipo}
          onChange={(e) => {
            setTipo(e.target.value as TipoCostoRecepcion)
            setProdId(null); setTarifaId(null); setDesc('')
          }}
        >
          <option value="repuesto">Repuesto</option>
          <option value="mano_obra">Mano de obra</option>
          <option value="servicio_externo">Servicio externo</option>
          <option value="otro">Otro</option>
        </select>

        {tipo === 'repuesto' ? (
          <div className="sm:col-span-3 relative">
            <Input
              placeholder="Buscar producto…"
              value={busqueda}
              onChange={(e) => setBusqueda(e.target.value)}
            />
            {busqueda.length >= 2 && productos.length > 0 && (
              <div className="absolute z-10 mt-1 w-full max-h-48 overflow-y-auto rounded border bg-white shadow">
                {productos.map((p: any) => (
                  <button
                    key={p.id}
                    className="w-full px-2 py-1 text-left text-xs hover:bg-blue-50"
                    onClick={() => {
                      setProdId(p.id)
                      setDesc(`${p.codigo} — ${p.nombre}`)
                      setUnidad(p.unidad_medida)
                      setBusqueda('')
                    }}
                  >
                    <span className="font-mono text-gray-500">{p.codigo}</span> {p.nombre}
                  </button>
                ))}
              </div>
            )}
          </div>
        ) : tipo === 'mano_obra' ? (
          <select
            className="h-10 rounded border border-gray-300 px-2 text-sm sm:col-span-3"
            value={tarifaId ?? ''}
            onChange={(e) => {
              const t = tarifas.find((t) => t.id === e.target.value)
              if (t) {
                setTarifaId(t.id)
                setDesc(`HH ${t.nombre}`)
                setUnidad('hora')
                setPrecio(String(t.tarifa_clp))
              }
            }}
          >
            <option value="">Seleccionar tarifa HH…</option>
            {tarifas.map((t) => (
              <option key={t.id} value={t.id}>
                {t.nombre} — ${t.tarifa_clp.toLocaleString('es-CL')}/h
              </option>
            ))}
          </select>
        ) : (
          <Input
            className="sm:col-span-3"
            placeholder="Descripción"
            value={desc}
            onChange={(e) => setDesc(e.target.value)}
          />
        )}
      </div>

      <div className="grid grid-cols-3 gap-2 items-end">
        <div>
          <label className="text-[10px] text-gray-500">Cantidad</label>
          <Input type="number" step="0.01" value={cant} onChange={(e) => setCant(e.target.value)} />
        </div>
        <div>
          <label className="text-[10px] text-gray-500">Unidad</label>
          <Input value={unidad} onChange={(e) => setUnidad(e.target.value)} placeholder="un / hora / m" />
        </div>
        <div>
          <label className="text-[10px] text-gray-500">Precio unitario (CLP)</label>
          <Input type="number" step="1" value={precio} onChange={(e) => setPrecio(e.target.value)} />
        </div>
      </div>

      <div className="flex items-center justify-between gap-2">
        <label className="flex items-center gap-2 text-xs">
          <input
            type="checkbox"
            checked={cobrable}
            onChange={(e) => setCobrable(e.target.checked)}
          />
          Cobrable al cliente
        </label>
        <Button variant="primary" size="sm" onClick={handleAdd} disabled={!desc || !precio}>
          <Plus className="h-3 w-3" /> Agregar
        </Button>
      </div>
    </div>
  )
}

function SummaryCell({ label, value, color }: { label: string; value: string; color?: string }) {
  return (
    <div className="rounded border p-2 text-center">
      <div className="text-[10px] uppercase text-gray-500">{label}</div>
      <div className={cn('text-lg font-bold', color ?? 'text-gray-900')}>{value}</div>
    </div>
  )
}

function fmt(n: number): string {
  return Number(n).toLocaleString('es-CL')
}
