'use client'

import { useState } from 'react'
import { useParams, useRouter } from 'next/navigation'
import {
  AlertTriangle, CheckCircle2, FileCheck, PenTool, Send,
  Trash2, Plus, DollarSign, ShieldCheck,
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
import {
  useInformeRecepcion,
  useHallazgosInforme,
  useCostosInforme,
  useActualizarHallazgo,
  useActualizarCosto,
  useEliminarCosto,
  useAgregarCosto,
  useEmitirInformeRecepcion,
} from '@/hooks/use-informe-recepcion'
import { subirFirmaInforme } from '@/lib/services/informe-recepcion'
import { generarPDFInforme } from '@/components/recepcion/pdf-informe'
import { cn } from '@/lib/utils'

const ROLES_CON_PERMISO = new Set([
  'administrador',
  'encargado_cobros',
  'subgerente_operaciones',
  'gerencia',
])

export default function EmitirInformeRecepcionPage() {
  useRequireAuth()
  const { perfil, user } = useAuth()
  const { informeId } = useParams<{ informeId: string }>()
  const router = useRouter()

  const [observaciones, setObservaciones] = useState('')
  const [firmaDataUrl, setFirmaDataUrl] = useState<string | null>(null)
  const [errorMsg, setErrorMsg] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)
  const [activoData, setActivoData] = useState<any>(null)

  const { data: informe, isLoading: loadingInf } = useInformeRecepcion(informeId)
  const { data: hallazgos = [] } = useHallazgosInforme(informeId)
  const { data: costos = [] } = useCostosInforme(informeId)

  const updHal = useActualizarHallazgo()
  const updCosto = useActualizarCosto()
  const delCosto = useEliminarCosto()
  const addCosto = useAgregarCosto()
  const emitir = useEmitirInformeRecepcion()

  // Cargar datos del activo (para el PDF)
  useState(() => {
    if (!informe?.activo_id) return
    supabase
      .from('activos')
      .select('patente, codigo, nombre, modelo:modelos(nombre, marca:marcas(nombre))')
      .eq('id', informe.activo_id)
      .single()
      .then(({ data }: any) => {
        if (data) {
          setActivoData({
            patente: data.patente,
            codigo: data.codigo,
            nombre: data.nombre,
            marca: data.modelo?.marca?.nombre ?? null,
            modelo: data.modelo?.nombre ?? null,
          })
        }
      })
  })

  const puedeEmitir = perfil?.rol && ROLES_CON_PERMISO.has(perfil.rol)
  const esMismoInspector = informe?.inspector_id && user?.id === informe.inspector_id

  const handleEmitir = async () => {
    if (!informeId || !informe || !firmaDataUrl) {
      setErrorMsg('Falta firma del encargado')
      return
    }
    if (esMismoInspector) {
      setErrorMsg('No puedes emitir tu propio informe (doble firma obligatoria)')
      return
    }

    setSaving(true); setErrorMsg(null)
    try {
      // 1) Subir firma
      const { data: firmaUrl, error: fErr } = await subirFirmaInforme(informeId, 'encargado', firmaDataUrl)
      if (fErr || !firmaUrl) throw fErr ?? new Error('Error al subir firma')

      // 2) Guardar observaciones primero
      if (observaciones.trim()) {
        await supabase
          .from('informes_recepcion')
          .update({ observaciones_finales: observaciones })
          .eq('id', informeId)
      }

      // 3) Generar PDF con los datos actualizados
      const informeActualizado = {
        ...informe,
        observaciones_finales: observaciones.trim() || informe.observaciones_finales,
        encargado_firma_url: firmaUrl,
        emitido_en: new Date().toISOString(),
      }
      const blob = await generarPDFInforme({
        informe: informeActualizado as any,
        activo: activoData ?? { patente: null, codigo: null, nombre: null },
        hallazgos,
        costos,
      })

      // 4) Subir PDF al storage
      const path = `recepcion/${informeId}/informe-${informe.folio ?? informeId.slice(0, 8)}.pdf`
      const { error: pdfErr } = await supabase.storage
        .from('evidencias-verificacion')
        .upload(path, blob, { upsert: true, contentType: 'application/pdf' })
      if (pdfErr) throw pdfErr
      const { data: pub } = supabase.storage.from('evidencias-verificacion').getPublicUrl(path)

      // 5) Llamar RPC de emisión
      await emitir.mutateAsync({
        informeId,
        firmaEncargadoUrl: firmaUrl,
        pdfUrl: pub.publicUrl,
        observaciones: observaciones.trim() || undefined,
      })

      // 6) Abrir PDF en nueva pestaña
      window.open(pub.publicUrl, '_blank')
      router.push('/dashboard/flota/recepcion')
    } catch (err) {
      setErrorMsg(err instanceof Error ? err.message : 'Error al emitir')
    } finally {
      setSaving(false)
    }
  }

  if (loadingInf) {
    return <div className="flex h-64 items-center justify-center"><Spinner className="h-8 w-8" /></div>
  }
  if (!informe) {
    return <Card><CardContent className="py-10 text-center"><AlertTriangle className="h-10 w-10 text-amber-500 mx-auto" /><h3>No encontrado</h3></CardContent></Card>
  }

  const fmt = (n: number) => `$${Number(n).toLocaleString('es-CL')}`

  return (
    <div className="space-y-4">
      <div className="rounded-xl bg-gradient-to-r from-blue-700 to-indigo-800 p-5 text-white">
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-xl font-bold flex items-center gap-2">
              <FileCheck className="h-6 w-6" />
              Emitir Informe · {informe.folio}
            </h1>
            <p className="text-xs text-white/80 mt-1">
              Cliente: {informe.cliente_nombre ?? '—'} · {hallazgos.length} hallazgos · {costos.length} líneas de costo
            </p>
          </div>
          <Badge className={cn(
            informe.estado === 'borrador' ? 'bg-amber-100 text-amber-800' :
            informe.estado === 'emitido' ? 'bg-green-100 text-green-800' :
            'bg-gray-100 text-gray-700',
          )}>
            {informe.estado}
          </Badge>
        </div>
      </div>

      {!puedeEmitir && (
        <div className="rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm text-amber-700">
          Solo administrador, encargado de cobros o subgerencia pueden emitir informes.
        </div>
      )}
      {esMismoInspector && (
        <div className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">
          <AlertTriangle className="inline h-4 w-4 mr-1" />
          Doble firma obligatoria: otro usuario distinto al inspector debe emitir.
        </div>
      )}
      {informe.estado === 'emitido' && (
        <div className="rounded-lg border border-green-200 bg-green-50 p-3 text-sm text-green-700 flex items-center gap-2">
          <CheckCircle2 className="h-4 w-4" />
          Informe ya emitido el {informe.emitido_en ? new Date(informe.emitido_en).toLocaleString('es-CL') : ''}.
          {informe.pdf_url && <a href={informe.pdf_url} target="_blank" rel="noreferrer" className="text-blue-600 underline ml-auto">Ver PDF</a>}
        </div>
      )}
      {errorMsg && (
        <div className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">{errorMsg}</div>
      )}

      {/* ─── Hallazgos con toggle cobrable ─── */}
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-base">Hallazgos ({hallazgos.length})</CardTitle>
        </CardHeader>
        <CardContent className="space-y-2">
          {hallazgos.length === 0 ? (
            <p className="text-sm text-gray-400 py-3 text-center">Sin hallazgos registrados.</p>
          ) : hallazgos.map((h) => (
            <div key={h.id} className="rounded border p-2 text-sm space-y-1">
              <div className="flex items-start gap-2">
                <div className="flex-1">
                  <div className="font-medium">{h.descripcion}</div>
                  <div className="text-xs text-gray-500">{h.seccion} · Gravedad: {h.gravedad}</div>
                  {h.observacion && <div className="text-xs italic text-gray-600 mt-1">"{h.observacion}"</div>}
                </div>
                <label className="flex items-center gap-1 text-xs">
                  <input
                    type="checkbox"
                    checked={h.atribuible_cliente}
                    disabled={informe.estado === 'emitido'}
                    onChange={(e) => updHal.mutate({
                      id: h.id, informeId: informeId!,
                      patch: { atribuible_cliente: e.target.checked },
                    })}
                  />
                  Cobrable cliente
                </label>
              </div>
              {(h.fotos ?? []).length > 0 && (
                <div className="flex gap-1">
                  {(h.fotos ?? []).map((url, i) => (
                    <img key={i} src={url} alt="" className="h-16 w-16 rounded border object-cover" />
                  ))}
                </div>
              )}
            </div>
          ))}
        </CardContent>
      </Card>

      {/* ─── Costos editables ─── */}
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-base flex items-center gap-2">
            <DollarSign className="h-5 w-5" />
            Costos ({costos.length})
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-2">
          {costos.length === 0 ? (
            <p className="text-sm text-gray-400 py-3 text-center">Sin ítems de costo.</p>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-xs">
                <thead>
                  <tr className="border-b bg-gray-50 text-left text-gray-500 uppercase">
                    <th className="px-2 py-1">Tipo</th>
                    <th className="px-2 py-1">Descripción</th>
                    <th className="px-2 py-1 text-right">Cant.</th>
                    <th className="px-2 py-1 text-right">Precio</th>
                    <th className="px-2 py-1 text-right">Total</th>
                    <th className="px-2 py-1 text-center">Cobrable</th>
                    <th className="px-2 py-1"></th>
                  </tr>
                </thead>
                <tbody>
                  {costos.map((c) => (
                    <tr key={c.id} className={cn('border-b', !c.cobrable_cliente && 'bg-gray-50')}>
                      <td className="px-2 py-1.5"><Badge className="text-[10px] bg-gray-100">{c.tipo}</Badge></td>
                      <td className="px-2 py-1.5">
                        <input
                          className="w-full rounded border-transparent bg-transparent hover:bg-white hover:border-gray-300"
                          defaultValue={c.descripcion}
                          disabled={informe.estado === 'emitido'}
                          onBlur={(e) => updCosto.mutate({ id: c.id, informeId: informeId!, patch: { descripcion: e.target.value } })}
                        />
                      </td>
                      <td className="px-2 py-1.5 text-right">
                        <input
                          type="number" step="0.01"
                          className="w-16 text-right rounded border-transparent bg-transparent hover:bg-white hover:border-gray-300"
                          defaultValue={c.cantidad}
                          disabled={informe.estado === 'emitido'}
                          onBlur={(e) => updCosto.mutate({ id: c.id, informeId: informeId!, patch: { cantidad: Number(e.target.value) } })}
                        />
                      </td>
                      <td className="px-2 py-1.5 text-right">
                        <input
                          type="number" step="1"
                          className="w-24 text-right rounded border-transparent bg-transparent hover:bg-white hover:border-gray-300"
                          defaultValue={c.precio_unitario}
                          disabled={informe.estado === 'emitido'}
                          onBlur={(e) => updCosto.mutate({ id: c.id, informeId: informeId!, patch: { precio_unitario: Number(e.target.value) } })}
                        />
                      </td>
                      <td className="px-2 py-1.5 text-right font-semibold">{fmt(Number(c.total))}</td>
                      <td className="px-2 py-1.5 text-center">
                        <input
                          type="checkbox"
                          checked={c.cobrable_cliente}
                          disabled={informe.estado === 'emitido'}
                          onChange={(e) => updCosto.mutate({ id: c.id, informeId: informeId!, patch: { cobrable_cliente: e.target.checked } })}
                        />
                      </td>
                      <td className="px-2 py-1.5 text-right">
                        <button
                          className="text-red-400 hover:text-red-700"
                          disabled={informe.estado === 'emitido'}
                          onClick={() => delCosto.mutate({ id: c.id, informeId: informeId! })}
                        >
                          <Trash2 className="h-4 w-4" />
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}

          <div className="grid grid-cols-3 gap-3 pt-3 border-t text-sm">
            <SummaryCell label="Neto cobrable" value={fmt(Number(informe.total_cobrable_cliente))} color="text-gray-700" />
            <SummaryCell label="IVA 19%" value={fmt(Number(informe.iva))} color="text-gray-700" />
            <SummaryCell label="Total cliente" value={fmt(Number(informe.total))} color="text-green-700" big />
          </div>
          <div className="text-xs text-gray-500 text-center">
            Absorbido por la empresa: {fmt(Number(informe.total_no_cobrable))}
          </div>
        </CardContent>
      </Card>

      {/* ─── Observaciones finales ─── */}
      {informe.estado === 'borrador' && (
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-base">Observaciones finales</CardTitle>
          </CardHeader>
          <CardContent>
            <textarea
              className="w-full rounded border p-2 text-sm min-h-[80px]"
              placeholder="Texto que aparecerá en el PDF…"
              value={observaciones}
              onChange={(e) => setObservaciones(e.target.value)}
            />
          </CardContent>
        </Card>
      )}

      {/* ─── Firma del encargado y emitir ─── */}
      {informe.estado === 'borrador' && puedeEmitir && !esMismoInspector && (
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-base flex items-center gap-2">
              <PenTool className="h-4 w-4" />
              Tu firma como encargado
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            <SignaturePad label="Firma Encargado de Cobros" onCapture={setFirmaDataUrl} />
            <Button
              variant="primary"
              size="lg"
              className="w-full"
              loading={saving}
              disabled={!firmaDataUrl}
              onClick={handleEmitir}
            >
              <Send className="h-5 w-5" />
              Emitir informe final y generar PDF
            </Button>
            <p className="text-xs text-gray-500">
              Al emitir: se sube el PDF al storage, se marca el informe como <strong>emitido</strong>
              (inmutable) y se abre el PDF en nueva pestaña.
            </p>
          </CardContent>
        </Card>
      )}

      {informe.estado === 'emitido' && informe.pdf_url && (
        <Button
          variant="primary"
          size="lg"
          className="w-full"
          onClick={() => window.open(informe.pdf_url!, '_blank')}
        >
          <ShieldCheck className="h-5 w-5" />
          Descargar PDF del informe emitido
        </Button>
      )}
    </div>
  )
}

function SummaryCell({ label, value, color, big }: { label: string; value: string; color?: string; big?: boolean }) {
  return (
    <div className="rounded border p-2 text-center">
      <div className="text-[10px] uppercase text-gray-500">{label}</div>
      <div className={cn(big ? 'text-xl' : 'text-base', 'font-bold', color ?? 'text-gray-900')}>
        {value}
      </div>
    </div>
  )
}
