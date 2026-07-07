'use client'

import { useMemo, useRef, useState } from 'react'
import Link from 'next/link'
import { useParams } from 'next/navigation'
import {
  ArrowLeft, Camera, Check, X, Minus, Play, Pause, CheckCircle2, Loader2, WifiOff, AlertTriangle, Clock,
} from 'lucide-react'
import { Spinner } from '@/components/ui/spinner'
import { Button } from '@/components/ui/button'
import { Modal, ModalFooter } from '@/components/ui/modal'
import { SignaturePad } from '@/components/ui/signature-pad'
import { useAuth } from '@/contexts/auth-context'
import { BLOQUE_LABELS } from '@/lib/services/checklist-v2'
import type { ChecklistV3Item } from '@/lib/services/taller-plan-semanal'
import {
  useMecanicoOTs, useMecanicoChecklist, useMarcarItem, useTimingMecanico,
  useAutoSyncTaller, useNetworkStatus,
} from '@/hooks/use-taller-mecanico'

function dataUrlToBlob(dataUrl: string): Blob {
  const [meta, b64] = dataUrl.split(',')
  const mime = meta.match(/:(.*?);/)?.[1] ?? 'image/png'
  const bin = atob(b64)
  const arr = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) arr[i] = bin.charCodeAt(i)
  return new Blob([arr], { type: mime })
}

function bloqueLabel(b: string): string {
  const known = (BLOQUE_LABELS as Record<string, string>)[b]
  if (known) return known
  const t = b.replace(/^b[0-9]*_?/i, '').replace(/_/g, ' ').trim() || b
  return t.charAt(0).toUpperCase() + t.slice(1)
}

function ResultRadio({ value, disabled, onChange }: {
  value: string | null; disabled?: boolean; onChange: (v: 'ok' | 'no_ok' | 'na') => void
}) {
  const opts = [
    { val: 'ok', label: 'OK', color: 'bg-green-500', icon: Check },
    { val: 'no_ok', label: 'NO OK', color: 'bg-red-500', icon: X },
    { val: 'na', label: 'N/A', color: 'bg-gray-400', icon: Minus },
  ] as const
  return (
    <div className="flex gap-1.5">
      {opts.map((o) => {
        const active = value === o.val
        const Icon = o.icon
        return (
          <button key={o.val} type="button" disabled={disabled} onClick={() => onChange(o.val)}
                  className={`flex h-9 flex-1 items-center justify-center gap-1 rounded-lg border text-xs font-semibold disabled:opacity-50 ${
                    active ? `${o.color} border-transparent text-white` : 'border-gray-200 bg-white text-gray-500'}`}>
            <Icon className="h-3.5 w-3.5" /> {o.label}
          </button>
        )
      })}
    </div>
  )
}

export default function MecanicoOTPage() {
  useAutoSyncTaller()
  const params = useParams()
  const otId = params?.id as string
  const { user } = useAuth()
  const userId = user?.id ?? ''
  const online = useNetworkStatus()

  const { data: ots } = useMecanicoOTs()
  const ot = useMemo(() => (ots ?? []).find((o) => o.ot_id === otId), [ots, otId])
  const { data: items, isLoading } = useMecanicoChecklist(otId)
  const marcar = useMarcarItem(otId)
  const timing = useTimingMecanico(otId)

  const [observations, setObservations] = useState<Record<string, string>>({})
  const fileRefs = useRef<Record<string, HTMLInputElement | null>>({})
  const [finalizar, setFinalizar] = useState(false)
  const [firma, setFirma] = useState('')
  const [conObs, setConObs] = useState(false)
  const [obsFin, setObsFin] = useState('')

  const estado = ot?.ot_estado ?? 'asignada'

  const visibles = (items ?? []).filter((i) => !i.excluido)
  const grupos = useMemo(() => {
    const g: { bloque: string; items: ChecklistV3Item[] }[] = []
    for (const it of visibles) {
      let x = g.find((y) => y.bloque === it.bloque)
      if (!x) { x = { bloque: it.bloque, items: [] }; g.push(x) }
      x.items.push(it)
    }
    return g
  }, [visibles])

  const total = visibles.length
  const hechos = visibles.filter((i) => i.resultado && i.resultado !== 'pendiente').length
  const pendientesOblig = visibles.filter((i) => i.obligatorio && (!i.resultado || i.resultado === 'pendiente')).length

  function doTiming(accion: 'iniciar' | 'pausar') {
    timing.mutate({ accion, userId })
  }
  function abrirFinalizar() {
    if (pendientesOblig > 0 && !confirm(`Quedan ${pendientesOblig} tareas obligatorias sin marcar. ¿Finalizar igual?`)) return
    setFirma(''); setConObs(false); setObsFin(''); setFinalizar(true)
  }
  function confirmFinalizar() {
    if (!firma) return
    timing.mutate(
      { accion: 'finalizar', userId, firma: dataUrlToBlob(firma), conObservaciones: conObs, observaciones: obsFin.trim() || null },
      { onSuccess: () => setFinalizar(false) },
    )
  }

  function setResultado(it: ChecklistV3Item, v: 'ok' | 'no_ok' | 'na') {
    marcar.mutate({ instanceItemId: it.instance_item_id, instanceId: it.instance_id, resultado: v })
  }
  function saveObs(it: ChecklistV3Item) {
    const o = observations[it.instance_item_id]
    if (o === undefined || o === (it.observacion ?? '')) return
    marcar.mutate({ instanceItemId: it.instance_item_id, instanceId: it.instance_id, observacion: o })
  }
  function onPhoto(it: ChecklistV3Item, file: File) {
    marcar.mutate({ instanceItemId: it.instance_item_id, instanceId: it.instance_id, file })
  }

  return (
    <div className="p-3 space-y-3">
      <Link href="/m/taller" className="inline-flex items-center gap-1 text-sm text-gray-500">
        <ArrowLeft className="h-4 w-4" /> Mis OTs
      </Link>

      {/* Cabecera */}
      <div className="rounded-xl border border-gray-200 bg-white p-3">
        <div className="flex items-center gap-2">
          <span className="font-mono text-sm font-bold">{ot?.ot_folio ?? '…'}</span>
          {!online && <span className="ml-auto flex items-center gap-1 text-[11px] text-amber-700"><WifiOff className="h-3.5 w-3.5" /> sin conexión</span>}
        </div>
        <div className="mt-1 text-sm font-medium text-gray-800">
          {ot?.activo_codigo} {ot?.activo_patente && <span className="text-gray-500">· {ot.activo_patente}</span>}
        </div>
        <div className="text-xs text-gray-500">{ot?.activo_nombre}</div>
        <div className="mt-2 flex items-center gap-2 text-xs text-gray-600">
          <span className="font-semibold">{hechos}/{total} tareas</span>
          {total > 0 && (
            <div className="h-1.5 flex-1 rounded-full bg-gray-100">
              <div className="h-1.5 rounded-full bg-orange-500" style={{ width: `${Math.min(100, Math.round((hechos / total) * 100))}%` }} />
            </div>
          )}
        </div>
      </div>

      {/* Cronómetro de jornada */}
      <div className="flex gap-2">
        {estado === 'asignada' && (
          <button onClick={() => doTiming('iniciar')} disabled={timing.isPending}
                  className="flex flex-1 items-center justify-center gap-1.5 rounded-xl bg-green-600 py-3 text-sm font-semibold text-white disabled:opacity-50">
            <Play className="h-4 w-4" /> Iniciar jornada
          </button>
        )}
        {estado === 'pausada' && (
          <button onClick={() => doTiming('iniciar')} disabled={timing.isPending}
                  className="flex flex-1 items-center justify-center gap-1.5 rounded-xl bg-green-600 py-3 text-sm font-semibold text-white disabled:opacity-50">
            <Play className="h-4 w-4" /> Reanudar
          </button>
        )}
        {estado === 'en_ejecucion' && (
          <button onClick={() => doTiming('pausar')} disabled={timing.isPending}
                  className="flex flex-1 items-center justify-center gap-1.5 rounded-xl bg-amber-500 py-3 text-sm font-semibold text-white disabled:opacity-50">
            <Pause className="h-4 w-4" /> Pausar (fin jornada)
          </button>
        )}
        {(estado === 'en_ejecucion' || estado === 'pausada') && (
          <button onClick={abrirFinalizar} disabled={timing.isPending}
                  className="flex flex-1 items-center justify-center gap-1.5 rounded-xl bg-blue-600 py-3 text-sm font-semibold text-white disabled:opacity-50">
            <CheckCircle2 className="h-4 w-4" /> Finalizar
          </button>
        )}
      </div>
      {timing.isError && (
        <p className="rounded-lg border border-red-200 bg-red-50 px-3 py-2 text-xs font-medium text-red-700">
          No se pudo registrar la acción: {(timing.error as Error).message}
        </p>
      )}
      <p className="text-[11px] text-gray-500 flex items-center gap-1">
        <AlertTriangle className="h-3 w-3 text-amber-500" />
        Al pausar o finalizar, las tareas NO OK se reportan como No Conformidad al jefe.
      </p>

      {/* Checklist */}
      {isLoading ? (
        <div className="flex justify-center py-8"><Spinner /></div>
      ) : total === 0 ? (
        <p className="py-8 text-center text-sm text-gray-400">Esta OT no tiene checklist (¿se cargó con conexión?).</p>
      ) : (
        grupos.map((g) => (
          <div key={g.bloque}>
            <div className="sticky top-0 z-10 bg-gray-100 rounded px-2 py-1 text-xs font-semibold text-gray-700">
              {bloqueLabel(g.bloque)}
            </div>
            <div className="space-y-2 pt-2">
              {g.items.map((it) => (
                <div key={it.instance_item_id} className="rounded-xl border border-gray-200 bg-white p-3">
                  <div className="flex items-start gap-1.5">
                    {it.codigo && <span className="text-[10px] font-mono text-gray-400">{it.codigo}</span>}
                    <p className="flex-1 text-sm text-gray-800">{it.descripcion}</p>
                    {it.tiempo_min != null && (
                      <span className="flex items-center gap-0.5 text-[10px] text-gray-400"><Clock className="h-3 w-3" />{it.tiempo_min}m</span>
                    )}
                  </div>
                  <div className="mt-1 flex flex-wrap gap-1">
                    {it.requiere_foto && <span className="text-[9px] px-1 rounded bg-blue-100 text-blue-700">pide foto</span>}
                    {it.critico && <span className="text-[9px] px-1 rounded bg-red-100 text-red-700">crítica</span>}
                  </div>

                  <div className="mt-2"><ResultRadio value={it.resultado} onChange={(v) => setResultado(it, v)} /></div>

                  {it.foto_url && (
                    <div className="mt-2">
                      {/* eslint-disable-next-line @next/next/no-img-element */}
                      <img src={it.foto_url} alt="foto" className="h-20 w-20 rounded-lg border object-cover" />
                    </div>
                  )}

                  <div className="mt-2 flex gap-2">
                    <input type="text" placeholder="Observación…"
                           value={observations[it.instance_item_id] ?? it.observacion ?? ''}
                           onChange={(e) => setObservations((p) => ({ ...p, [it.instance_item_id]: e.target.value }))}
                           onBlur={() => saveObs(it)}
                           className="flex-1 rounded-lg border border-gray-200 px-3 py-2 text-sm" />
                    <button type="button" onClick={() => fileRefs.current[it.instance_item_id]?.click()}
                            className={`flex h-10 w-10 items-center justify-center rounded-lg border ${
                              it.foto_url ? 'border-green-300 bg-green-50 text-green-600'
                                : it.requiere_foto ? 'border-blue-300 bg-blue-50 text-blue-600' : 'border-gray-200 text-gray-500'}`}>
                      {marcar.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Camera className="h-4 w-4" />}
                    </button>
                    <input ref={(el) => { fileRefs.current[it.instance_item_id] = el }} type="file"
                           accept="image/*" capture="environment" className="hidden"
                           onChange={(e) => { const f = e.target.files?.[0]; if (f) onPhoto(it, f); e.target.value = '' }} />
                  </div>
                </div>
              ))}
            </div>
          </div>
        ))
      )}

      {/* Modal finalizar con firma del técnico */}
      {finalizar && (
        <Modal open onClose={() => setFinalizar(false)} title="Finalizar OT">
          <div className="space-y-3">
            <p className="text-sm text-gray-600">
              Firma para cerrar tu trabajo. Las tareas NO OK ya se reportaron como No Conformidad.
            </p>
            <label className="flex items-center gap-2 text-sm">
              <input type="checkbox" checked={conObs} onChange={(e) => setConObs(e.target.checked)} />
              Finalizar con observaciones
            </label>
            {conObs && (
              <textarea value={obsFin} onChange={(e) => setObsFin(e.target.value)} rows={2}
                        placeholder="Observaciones…" className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm" />
            )}
            <SignaturePad label="Firma del técnico (obligatoria)" onCapture={setFirma} />
            {timing.isError && (
              <p className="rounded-lg border border-red-200 bg-red-50 px-3 py-2 text-xs font-medium text-red-700">
                No se pudo finalizar: {(timing.error as Error).message}
              </p>
            )}
          </div>
          <ModalFooter>
            <Button variant="outline" onClick={() => setFinalizar(false)}>Cancelar</Button>
            <Button disabled={!firma || (conObs && !obsFin.trim()) || timing.isPending} onClick={confirmFinalizar}>
              {timing.isPending ? <Spinner className="h-4 w-4 mr-1" /> : <CheckCircle2 className="h-4 w-4 mr-1" />}
              Finalizar
            </Button>
          </ModalFooter>
        </Modal>
      )}
    </div>
  )
}
