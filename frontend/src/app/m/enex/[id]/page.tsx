'use client'

// Ejecución de pauta en terreno (MIG208): el mantenedor marca cada ítem, mide
// (con tolerancia automática), saca fotos, firma él y el mandante.

import { useEffect, useMemo, useRef, useState } from 'react'
import Link from 'next/link'
import { useParams, useRouter } from 'next/navigation'
import {
  ArrowLeft, Camera, Check, X, Minus, CheckCircle2, Loader2, Ruler, AlertTriangle,
} from 'lucide-react'
import { Spinner } from '@/components/ui/spinner'
import { Button } from '@/components/ui/button'
import { SignaturePad } from '@/components/ui/signature-pad'
import { useAuth } from '@/contexts/auth-context'
import { useToast } from '@/contexts/toast-context'
import {
  getTerrenoPendientes, getPautaItems, ejecutarPauta, getEjecucionItems,
  subirEvidenciaEnex, subirFirmaEnex,
  type EnexPautaItem, type EnexPendiente,
} from '@/lib/services/enex'
import { useQuery } from '@tanstack/react-query'

type Estado = { resultado?: string; valor?: string; file?: File; fotoUrl?: string; obs?: string }

function toleranciaTexto(it: EnexPautaItem): string {
  const ref = it.valor_referencia ?? 0
  const lo = it.tolerancia_min != null ? ref + it.tolerancia_min : null
  const hi = it.tolerancia_max != null ? ref + it.tolerancia_max : null
  if (lo != null && hi != null) return `${lo} a ${hi} ${it.unidad ?? ''}`
  if (hi != null) return `≤ ${hi} ${it.unidad ?? ''}`
  if (lo != null) return `≥ ${lo} ${it.unidad ?? ''}`
  return it.unidad ?? ''
}
function dentroTol(it: EnexPautaItem, v: string | undefined): boolean | null {
  if (it.tipo_campo !== 'medicion' || v == null || v === '') return null
  if (it.tolerancia_min == null && it.tolerancia_max == null) return null
  const val = Number(v), ref = it.valor_referencia ?? 0
  const okMin = it.tolerancia_min == null || val >= ref + it.tolerancia_min
  const okMax = it.tolerancia_max == null || val <= ref + it.tolerancia_max
  return okMin && okMax
}

export default function EnexEjecutarPage() {
  const params = useParams()
  const router = useRouter()
  const toast = useToast()
  const { perfil } = useAuth()
  const progId = params?.id as string

  const hoyP = (() => { const d = new Date(); return { anio: d.getFullYear(), mes: d.getMonth() + 1 } })()
  const { data: pendientes = [] } = useQuery({
    queryKey: ['enex-terreno', hoyP.anio, hoyP.mes], queryFn: () => getTerrenoPendientes(hoyP.anio, hoyP.mes), staleTime: 10_000,
  })
  const prog: EnexPendiente | undefined = useMemo(() => pendientes.find((p) => p.programacion_id === progId), [pendientes, progId])
  const { data: items = [], isLoading } = useQuery({
    queryKey: ['enex-pauta-items', prog?.pauta_id], queryFn: () => getPautaItems(prog!.pauta_id!),
    enabled: !!prog?.pauta_id,
  })

  const [estado, setEstado] = useState<Record<string, Estado>>({})
  const [otNumero, setOtNumero] = useState('')
  const [obs, setObs] = useState('')
  const [firmaTec, setFirmaTec] = useState('')
  const [firmaMand, setFirmaMand] = useState('')
  const [firmante, setFirmante] = useState('')
  const [guardando, setGuardando] = useState(false)
  const fileRefs = useRef<Record<string, HTMLInputElement | null>>({})

  // Precargar lo ya registrado (si vuelve a editar)
  useEffect(() => {
    if (!prog?.ejecucion_id) return
    getEjecucionItems(prog.ejecucion_id).then((rows) => {
      const e: Record<string, Estado> = {}
      for (const r of rows as Array<{ pauta_item_id: string; resultado: string | null; valor_medicion: number | null; foto_url: string | null; observacion: string | null }>) {
        e[r.pauta_item_id] = { resultado: r.resultado ?? undefined, valor: r.valor_medicion?.toString(), fotoUrl: r.foto_url ?? undefined, obs: r.observacion ?? undefined }
      }
      setEstado(e)
    }).catch(() => {})
  }, [prog?.ejecucion_id])

  const grupos = useMemo(() => {
    const g: { bloque: string; items: EnexPautaItem[] }[] = []
    for (const it of items) {
      let x = g.find((y) => y.bloque === it.bloque)
      if (!x) { x = { bloque: it.bloque, items: [] }; g.push(x) }
      x.items.push(it)
    }
    return g
  }, [items])

  function upd(id: string, patch: Partial<Estado>) { setEstado((p) => ({ ...p, [id]: { ...p[id], ...patch } })) }

  async function guardar(conFirmaMandante: boolean) {
    if (!prog) return
    if (conFirmaMandante && !firmaMand) { toast.error('Falta la firma del mandante'); return }
    setGuardando(true)
    try {
      // subir fotos por ítem
      const itemsPayload = []
      for (const it of items) {
        const st = estado[it.id]
        if (!st) continue
        let fotoUrl = st.fotoUrl ?? null
        if (st.file) fotoUrl = await subirEvidenciaEnex(st.file)
        itemsPayload.push({
          pauta_item_id: it.id, resultado: st.resultado ?? null,
          valor_medicion: st.valor ?? null, foto_url: fotoUrl, observacion: st.obs ?? null,
        })
      }
      const firmaTecUrl = firmaTec ? await subirFirmaEnex(firmaTec) : null
      const firmaMandUrl = conFirmaMandante && firmaMand ? await subirFirmaEnex(firmaMand) : null
      const r = await ejecutarPauta({
        programacionId: prog.programacion_id, items: itemsPayload,
        otNumero: otNumero || null, ejecutor: perfil?.nombre_completo ?? null, observacion: obs || null,
        firmaTecnicoUrl: firmaTecUrl, tecnicoNombre: perfil?.nombre_completo ?? null,
        firmaMandanteUrl: firmaMandUrl, firmanteMandante: firmante || null,
      })
      toast.success(r.cumplida ? 'Registrada y CUMPLIDA (firma del mandante)' : 'Ejecución guardada — falta firma del mandante para cumplir')
      router.push('/m/enex')
    } catch (e) { toast.error((e as Error).message) } finally { setGuardando(false) }
  }

  if (!prog) return <div className="p-6 text-center text-sm text-gray-400">Cargando servicio…</div>
  if (!prog.pauta_id) return (
    <div className="p-4 space-y-3">
      <Link href="/m/enex" className="inline-flex items-center gap-1 text-sm text-gray-500"><ArrowLeft className="h-4 w-4" /> Volver</Link>
      <div className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">
        Esta instalación no tiene pauta asignada para este servicio. Avisa al supervisor para vincular la pauta.
      </div>
    </div>
  )

  return (
    <div className="p-3 space-y-3 pb-24">
      <Link href="/m/enex" className="inline-flex items-center gap-1 text-sm text-gray-500"><ArrowLeft className="h-4 w-4" /> Servicios</Link>

      <div className="rounded-xl border border-gray-200 bg-white p-3">
        <div className="text-sm font-bold text-gray-900">{prog.instalacion}{prog.patente ? ` · ${prog.patente}` : ''}</div>
        <div className="text-xs text-gray-500">{prog.faena} · {prog.tipo_servicio === 'calibracion' ? 'Calibración' : 'Mantención'}</div>
        <div className="mt-1 text-[11px] text-gray-500">{prog.pauta_nombre}{prog.pauta_borrador ? ' (borrador)' : ''}</div>
      </div>

      <div className="grid grid-cols-2 gap-2">
        <input value={otNumero} onChange={(e) => setOtNumero(e.target.value)} placeholder="N° OT (mandante)"
               className="rounded-lg border border-gray-200 px-3 py-2 text-sm" />
        <input value={obs} onChange={(e) => setObs(e.target.value)} placeholder="Observación general"
               className="rounded-lg border border-gray-200 px-3 py-2 text-sm" />
      </div>

      {isLoading ? <div className="flex justify-center py-8"><Spinner /></div> : grupos.map((g) => (
        <div key={g.bloque}>
          <div className="sticky top-0 z-10 bg-gray-100 rounded px-2 py-1 text-xs font-semibold text-gray-700">{g.bloque}</div>
          <div className="space-y-2 pt-2">
            {g.items.map((it) => {
              const st = estado[it.id] ?? {}
              const dt = dentroTol(it, st.valor)
              return (
                <div key={it.id} className="rounded-xl border border-gray-200 bg-white p-3">
                  <div className="flex items-start gap-1.5">
                    {it.codigo && <span className="text-[10px] font-mono text-gray-400">{it.codigo}</span>}
                    <p className="flex-1 text-sm text-gray-800">{it.descripcion}</p>
                    <span className="text-[9px] text-gray-400">{it.periodicidad}</span>
                  </div>

                  {/* Campo por tipo */}
                  {(it.tipo_campo === 'ok_nook' || it.tipo_campo === 'si_no') && (
                    <div className="mt-2 flex gap-1.5">
                      {(it.tipo_campo === 'ok_nook'
                        ? [['ok', 'OK', 'bg-green-500', Check], ['no_ok', 'NO OK', 'bg-red-500', X], ['na', 'N/A', 'bg-gray-400', Minus]]
                        : [['si', 'Sí', 'bg-green-500', Check], ['no', 'No', 'bg-red-500', X]]
                      ).map(([val, label, color, Icon]) => {
                        const active = st.resultado === val
                        const I = Icon as typeof Check
                        return (
                          <button key={val as string} onClick={() => upd(it.id, { resultado: val as string })}
                                  className={`flex h-9 flex-1 items-center justify-center gap-1 rounded-lg border text-xs font-semibold ${active ? `${color} border-transparent text-white` : 'border-gray-200 bg-white text-gray-500'}`}>
                            <I className="h-3.5 w-3.5" /> {label as string}
                          </button>
                        )
                      })}
                    </div>
                  )}
                  {it.tipo_campo === 'medicion' && (
                    <div className="mt-2 flex items-center gap-2">
                      <input type="number" inputMode="decimal" value={st.valor ?? ''} onChange={(e) => upd(it.id, { valor: e.target.value })}
                             placeholder={`valor ${it.unidad ?? ''}`} className="w-32 rounded-lg border border-gray-200 px-3 py-2 text-sm" />
                      {(it.tolerancia_min != null || it.tolerancia_max != null) && (
                        <span className="flex items-center gap-1 text-[11px] text-gray-500"><Ruler className="h-3 w-3" /> {toleranciaTexto(it)}</span>
                      )}
                      {dt === true && <span className="rounded-full bg-green-100 px-2 py-0.5 text-[10px] font-semibold text-green-700">dentro</span>}
                      {dt === false && <span className="rounded-full bg-red-100 px-2 py-0.5 text-[10px] font-semibold text-red-700">fuera de tolerancia</span>}
                    </div>
                  )}
                  {it.tipo_campo === 'texto' && (
                    <input value={st.obs ?? ''} onChange={(e) => upd(it.id, { obs: e.target.value })} placeholder="Anotar…"
                           className="mt-2 w-full rounded-lg border border-gray-200 px-3 py-2 text-sm" />
                  )}

                  {/* Foto */}
                  <div className="mt-2 flex items-center gap-2">
                    {(st.file || st.fotoUrl) ? (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img src={st.file ? URL.createObjectURL(st.file) : st.fotoUrl!} alt="ev" className="h-12 w-12 rounded-lg border object-cover" />
                    ) : null}
                    <button onClick={() => fileRefs.current[it.id]?.click()}
                            className={`flex items-center gap-1 rounded-lg border px-2 py-1.5 text-[11px] font-semibold ${it.requiere_foto && !st.file && !st.fotoUrl ? 'border-blue-300 bg-blue-50 text-blue-700' : 'border-gray-200 text-gray-500'}`}>
                      <Camera className="h-3.5 w-3.5" /> {it.requiere_foto ? 'Foto (pide)' : 'Foto'}
                    </button>
                    <input ref={(el) => { fileRefs.current[it.id] = el }} type="file" accept="image/*" capture="environment" className="hidden"
                           onChange={(e) => { const f = e.target.files?.[0]; if (f) upd(it.id, { file: f }); e.target.value = '' }} />
                  </div>
                </div>
              )
            })}
          </div>
        </div>
      ))}

      {/* Firmas */}
      <div className="rounded-xl border border-gray-200 bg-white p-3 space-y-3">
        <SignaturePad label="Firma del técnico" onCapture={setFirmaTec} />
        <div className="border-t pt-2">
          <input value={firmante} onChange={(e) => setFirmante(e.target.value)} placeholder="Nombre de quien firma (ESM/ENEX)"
                 className="mb-1.5 w-full rounded-lg border border-gray-200 px-3 py-2 text-sm" />
          <SignaturePad label="Firma del mandante (para cumplir el KPI)" onCapture={setFirmaMand} />
        </div>
      </div>

      {/* Barra de acción */}
      <div className="fixed inset-x-0 bottom-0 mx-auto flex max-w-[480px] gap-2 border-t bg-white p-3">
        <Button variant="outline" className="flex-1" disabled={guardando} onClick={() => guardar(false)}>
          {guardando ? <Loader2 className="h-4 w-4 mr-1 animate-spin" /> : null} Guardar avance
        </Button>
        <Button className="flex-1" disabled={guardando || !firmaMand} onClick={() => guardar(true)}>
          <CheckCircle2 className="h-4 w-4 mr-1" /> Cerrar (cumplida)
        </Button>
      </div>
    </div>
  )
}
