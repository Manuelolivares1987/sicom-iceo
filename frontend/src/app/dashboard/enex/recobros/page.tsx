'use client'

// Recobros y reprogramación (MIG234).
//  · RECOBROS: 2ª+ atención/calibración del mismo punto/patente dentro del
//    trimestre contractual (facturable adicional a ENEX).
//  · REPROGRAMACIONES: registros formato ESM/PILLADO entregados a ENEX; se
//    puede regenerar/descargar el PDF de cada uno.

import { useMemo, useState } from 'react'
import Link from 'next/link'
import { useQuery } from '@tanstack/react-query'
import {
  ArrowLeft, RefreshCcw, RepeatIcon, CalendarClock, FileSpreadsheet, Download, Truck, Building2,
} from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { useToast } from '@/contexts/toast-context'
import { useRequireAuth } from '@/hooks/use-require-auth'
import {
  getRecobros, getReprogramaciones, REPROG_RESPONSABLE, REPROG_CAUSA,
  TIPO_INSTALACION_LABEL, SERVICIO_LABEL_SHORT,
} from '@/lib/services/enex'
import { generarReprogramacionPdf } from '@/components/enex/pdf-reprogramacion-enex'

function fmtFecha(iso?: string | null): string {
  if (!iso) return '—'
  const [y, m, d] = iso.slice(0, 10).split('-')
  return `${d}-${m}-${y}`
}

export default function EnexRecobrosPage() {
  useRequireAuth()
  const toast = useToast()
  const [tab, setTab] = useState<'recobros' | 'reprog'>('recobros')
  const [generando, setGenerando] = useState<string | null>(null)

  const { data: recobros = [], isLoading: loadingRec, refetch: refetchRec } = useQuery({
    queryKey: ['enex-recobros'], queryFn: () => getRecobros(true), staleTime: 15_000,
  })
  const { data: reprogs = [], isLoading: loadingRep, refetch: refetchRep } = useQuery({
    queryKey: ['enex-reprogramaciones'], queryFn: getReprogramaciones, staleTime: 15_000,
  })

  const porTrimestre = useMemo(() => {
    const g: { trimestre: string; items: typeof recobros }[] = []
    for (const r of recobros) {
      let x = g.find((y) => y.trimestre === (r.trimestre ?? '—'))
      if (!x) { x = { trimestre: r.trimestre ?? '—', items: [] }; g.push(x) }
      x.items.push(r)
    }
    return g
  }, [recobros])

  async function descargarPdf(id: string, urlExistente?: string | null) {
    setGenerando(id)
    try {
      const url = urlExistente ?? await generarReprogramacionPdf(id)
      if (urlExistente) window.open(url, '_blank')
      toast.success('Registro PDF listo')
    } catch (e) { toast.error((e as Error).message) } finally { setGenerando(null) }
  }

  return (
    <div className="mx-auto max-w-5xl p-4 space-y-4">
      <div className="flex items-center gap-2">
        <Link href="/dashboard/enex"><Button variant="outline" size="sm"><ArrowLeft className="h-4 w-4" /></Button></Link>
        <div className="flex-1">
          <h1 className="text-lg font-bold">Recobros y reprogramación</h1>
          <p className="text-xs text-gray-500">Repeticiones facturables y registros de cambio de fecha para ENEX</p>
        </div>
        <Button variant="outline" size="sm" onClick={() => { refetchRec(); refetchRep() }}>
          <RefreshCcw className="h-4 w-4" />
        </Button>
      </div>

      <div className="flex gap-2">
        <button onClick={() => setTab('recobros')}
          className={`flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-sm font-medium ${tab === 'recobros' ? 'bg-amber-600 text-white' : 'bg-white border text-gray-600'}`}>
          <RepeatIcon className="h-4 w-4" /> Recobros {recobros.length > 0 && <span className="ml-1 rounded-full bg-white/30 px-1.5 text-xs">{recobros.length}</span>}
        </button>
        <button onClick={() => setTab('reprog')}
          className={`flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-sm font-medium ${tab === 'reprog' ? 'bg-indigo-600 text-white' : 'bg-white border text-gray-600'}`}>
          <CalendarClock className="h-4 w-4" /> Reprogramaciones {reprogs.length > 0 && <span className="ml-1 rounded-full bg-white/30 px-1.5 text-xs">{reprogs.length}</span>}
        </button>
      </div>

      {tab === 'recobros' ? (
        <Card>
          <CardContent className="p-4">
            <p className="mb-3 text-xs text-gray-500">
              Un <b>recobro</b> es cuando se vuelve a atender o calibrar el mismo punto/patente dentro del mismo
              trimestre contractual (May-Jul, Ago-Oct, …). La primera atención va incluida en el contrato; la
              segunda en adelante se factura como adicional a ENEX.
            </p>
            {loadingRec ? (
              <div className="flex justify-center py-8"><Spinner /></div>
            ) : recobros.length === 0 ? (
              <p className="py-8 text-center text-sm text-gray-400">Sin recobros por ahora — no hay repeticiones del mismo servicio en el trimestre.</p>
            ) : porTrimestre.map((g) => (
              <div key={g.trimestre} className="mb-4">
                <div className="mb-2 rounded bg-gray-100 px-2 py-1 text-xs font-semibold text-gray-700">Trimestre {g.trimestre}</div>
                <div className="space-y-2">
                  {g.items.map((r) => (
                    <div key={r.ejecucion_id} className="flex items-center gap-3 rounded-lg border border-amber-200 bg-amber-50/50 p-3">
                      {r.instalacion_tipo === 'camion' ? <Truck className="h-5 w-5 text-amber-600" /> : <Building2 className="h-5 w-5 text-amber-600" />}
                      <div className="flex-1">
                        <p className="text-sm font-medium text-gray-800">
                          {r.instalacion}{r.patente ? ` · ${r.patente}` : ''}
                        </p>
                        <p className="text-xs text-gray-500">
                          {r.faena} · {SERVICIO_LABEL_SHORT[r.tipo_servicio]} · {fmtFecha(r.fecha_ejecucion)}
                          {r.ot_numero ? ` · OT ${r.ot_numero}` : ''}
                        </p>
                      </div>
                      <span className="rounded-full bg-amber-600 px-2 py-0.5 text-[11px] font-bold text-white">
                        Recobro #{r.secuencia - 1}
                      </span>
                    </div>
                  ))}
                </div>
              </div>
            ))}
          </CardContent>
        </Card>
      ) : (
        <Card>
          <CardContent className="p-4">
            {loadingRep ? (
              <div className="flex justify-center py-8"><Spinner /></div>
            ) : reprogs.length === 0 ? (
              <p className="py-8 text-center text-sm text-gray-400">Sin reprogramaciones registradas. Se crean desde el panel (botón «Reprogramar» en cada servicio).</p>
            ) : (
              <div className="space-y-2">
                {reprogs.map((r) => (
                  <div key={r.id} className="flex flex-wrap items-center gap-3 rounded-lg border border-indigo-200 bg-indigo-50/40 p-3">
                    <CalendarClock className="h-5 w-5 text-indigo-600" />
                    <div className="min-w-[180px] flex-1">
                      <p className="text-sm font-medium text-gray-800">{r.instalacion}{r.patente ? ` · ${r.patente}` : ''}</p>
                      <p className="text-xs text-gray-500">
                        {r.faena} · {r.actividad === 'calibracion' ? 'Calibración' : 'Mantención'} ·
                        {' '}{fmtFecha(r.fecha_original)} → <b>{fmtFecha(r.nueva_fecha)}</b>
                      </p>
                      <p className="text-[11px] text-gray-500">
                        {r.responsable ? REPROG_RESPONSABLE[r.responsable] ?? r.responsable : '—'} ·
                        {' '}{r.causa ? REPROG_CAUSA[r.causa] ?? r.causa : '—'}
                        {r.descripcion ? ` · ${r.descripcion}` : ''}
                      </p>
                    </div>
                    <Button variant={r.pdf_url ? 'outline' : 'primary'} size="sm" disabled={generando === r.id}
                            onClick={() => descargarPdf(r.id, r.pdf_url)}>
                      {generando === r.id ? <Spinner className="h-4 w-4 mr-1" />
                        : r.pdf_url ? <Download className="h-4 w-4 mr-1" /> : <FileSpreadsheet className="h-4 w-4 mr-1" />}
                      {r.pdf_url ? 'PDF' : 'Generar PDF'}
                    </Button>
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>
      )}
    </div>
  )
}
