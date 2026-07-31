'use client'

// Ejecución de pauta en terreno (MIG208 · MIG265): el mantenedor marca cada
// ítem, mide (con tolerancia automática), saca fotos del ANTES y del DESPUÉS
// —varias si quiere—, firma él y el mandante. La app cronometra el trabajo y
// cada ítem se puede comprimir para no perderse en pautas largas.

import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import Link from 'next/link'
import { useParams, useRouter } from 'next/navigation'
import {
  ArrowLeft, Camera, Check, X, Minus, CheckCircle2, Loader2, Ruler, AlertTriangle, Repeat,
  ChevronDown, ChevronRight, Timer, Plus, Trash2, WifiOff,
} from 'lucide-react'
import { Spinner } from '@/components/ui/spinner'
import { Button } from '@/components/ui/button'
import { SignaturePad } from '@/components/ui/signature-pad'
import { useAuth } from '@/contexts/auth-context'
import { useToast } from '@/contexts/toast-context'
import { getEjecucionIdDeProgramacion, type EnexPautaItem, type EnexPendiente } from '@/lib/services/enex'
import { generarYGuardarInformeEnex } from '@/components/enex/pdf-informe-enex'
import {
  getPendientesOffline, getPautaItemsOffline, getEjecucionItemsOffline, queueEjecucion,
} from '@/lib/offline/enex-offline'
import { useNetworkStatus } from '@/hooks/use-calama-offline'
import { useQuery, useQueryClient } from '@tanstack/react-query'

function dataUrlToBlob(dataUrl: string): Blob {
  const [meta, b64] = dataUrl.split(',')
  const mime = meta.match(/:(.*?);/)?.[1] ?? 'image/png'
  const bin = atob(b64); const arr = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) arr[i] = bin.charCodeAt(i)
  return new Blob([arr], { type: mime })
}

type Estado = {
  resultado?: string; valor?: string; obs?: string
  // [MIG265] Galerías: fotos nuevas (File) y las ya subidas (URL).
  antesFiles?: File[]; despuesFiles?: File[]
  fotosAntes?: string[]; fotosDespues?: string[]
}

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

const nAntes   = (st: Estado) => (st.fotosAntes?.length ?? 0) + (st.antesFiles?.length ?? 0)
const nDespues = (st: Estado) => (st.fotosDespues?.length ?? 0) + (st.despuesFiles?.length ?? 0)
/** Un ítem marcado N/A no necesita evidencia: no se hizo nada sobre él. */
const exigeFotos = (st: Estado) => st.resultado !== 'na'
const itemListo  = (st: Estado) =>
  !exigeFotos(st) ? true : nAntes(st) > 0 && nDespues(st) > 0

function hhmmss(seg: number): string {
  const h = Math.floor(seg / 3600), m = Math.floor((seg % 3600) / 60), s = seg % 60
  return h > 0
    ? `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`
    : `${m}:${String(s).padStart(2, '0')}`
}

export default function EnexEjecutarPage() {
  const params = useParams()
  const router = useRouter()
  const toast = useToast()
  const qc = useQueryClient()
  const online = useNetworkStatus()
  const { perfil } = useAuth()
  const progId = params?.id as string

  const hoyP = (() => { const d = new Date(); return { anio: d.getFullYear(), mes: d.getMonth() + 1 } })()
  const { data: pendientes = [] } = useQuery({
    queryKey: ['enex-terreno', hoyP.anio, hoyP.mes], queryFn: () => getPendientesOffline(hoyP.anio, hoyP.mes),
    networkMode: 'always', staleTime: 10_000,
  })
  const prog: EnexPendiente | undefined = useMemo(() => pendientes.find((p) => p.programacion_id === progId), [pendientes, progId])
  const { data: items = [], isLoading } = useQuery({
    queryKey: ['enex-pauta-items', prog?.pauta_id], queryFn: () => getPautaItemsOffline(prog!.pauta_id!),
    enabled: !!prog?.pauta_id, networkMode: 'always',
  })

  const [estado, setEstado] = useState<Record<string, Estado>>({})
  const [otNumero, setOtNumero] = useState('')
  const [obs, setObs] = useState('')
  const [firmaTec, setFirmaTec] = useState('')
  const [firmaMand, setFirmaMand] = useState('')
  const [firmante, setFirmante] = useState('')
  const [guardando, setGuardando] = useState(false)
  const [abiertos, setAbiertos] = useState<Record<string, boolean>>({})
  const fileRefs = useRef<Record<string, HTMLInputElement | null>>({})

  // ── [MIG265] Cronómetro del trabajo ──────────────────────────────────────
  // El inicio se guarda en el teléfono: si se recarga la página o se corta la
  // señal, el tiempo sigue contando desde que se abrió el servicio.
  const claveTimer = `enex-inicio:${progId}`
  const [inicioAt, setInicioAt] = useState<string | null>(null)
  const [ahora, setAhora] = useState<number>(() => Date.now())
  useEffect(() => {
    if (!progId) return
    let ini = typeof localStorage !== 'undefined' ? localStorage.getItem(claveTimer) : null
    if (!ini) {
      ini = new Date().toISOString()
      try { localStorage.setItem(claveTimer, ini) } catch { /* modo privado */ }
    }
    setInicioAt(ini)
  }, [progId, claveTimer])
  useEffect(() => {
    const t = setInterval(() => setAhora(Date.now()), 1000)
    return () => clearInterval(t)
  }, [])
  const segundos = inicioAt ? Math.max(0, Math.floor((ahora - new Date(inicioAt).getTime()) / 1000)) : 0

  // Precargar lo ya registrado (funciona sin señal: queda en cache)
  useEffect(() => {
    if (!prog?.ejecucion_id) return
    getEjecucionItemsOffline(prog.ejecucion_id).then((rows) => {
      const e: Record<string, Estado> = {}
      for (const r of rows) {
        e[r.pauta_item_id] = {
          resultado: r.resultado ?? undefined,
          valor: r.valor_medicion?.toString(),
          obs: r.observacion ?? undefined,
          fotosAntes: r.fotos_antes?.length ? r.fotos_antes : (r.foto_antes_url ? [r.foto_antes_url] : []),
          fotosDespues: r.fotos_despues?.length ? r.fotos_despues : (r.foto_despues_url ? [r.foto_despues_url] : []),
        }
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

  const upd = useCallback((id: string, patch: Partial<Estado>) => {
    setEstado((p) => ({ ...p, [id]: { ...p[id], ...patch } }))
  }, [])

  const agregarFotos = (id: string, tipo: 'antes' | 'despues', files: FileList) => {
    const nuevas = Array.from(files)
    setEstado((p) => {
      const st = p[id] ?? {}
      return {
        ...p,
        [id]: tipo === 'antes'
          ? { ...st, antesFiles: [...(st.antesFiles ?? []), ...nuevas] }
          : { ...st, despuesFiles: [...(st.despuesFiles ?? []), ...nuevas] },
      }
    })
  }
  const quitarFoto = (id: string, tipo: 'antes' | 'despues', idx: number, subida: boolean) => {
    setEstado((p) => {
      const st = p[id] ?? {}
      if (tipo === 'antes') {
        return subida
          ? { ...p, [id]: { ...st, fotosAntes: (st.fotosAntes ?? []).filter((_, i) => i !== idx) } }
          : { ...p, [id]: { ...st, antesFiles: (st.antesFiles ?? []).filter((_, i) => i !== idx) } }
      }
      return subida
        ? { ...p, [id]: { ...st, fotosDespues: (st.fotosDespues ?? []).filter((_, i) => i !== idx) } }
        : { ...p, [id]: { ...st, despuesFiles: (st.despuesFiles ?? []).filter((_, i) => i !== idx) } }
    })
  }

  // Avance: cuántos ítems tienen su antes y su después
  const listos = items.filter((it) => itemListo(estado[it.id] ?? {})).length
  const faltanFotos = items.filter((it) => !itemListo(estado[it.id] ?? {}))

  async function guardar(conFirmaMandante: boolean) {
    if (!prog) return
    if (conFirmaMandante && !firmaMand) { toast.error('Falta la firma del mandante'); return }
    // [MIG265] Cerrar cumplida exige el antes y el después de CADA actividad
    // (salvo las marcadas N/A, donde no se intervino).
    if (conFirmaMandante && faltanFotos.length > 0) {
      toast.error(`Faltan fotos de antes/después en ${faltanFotos.length} actividad(es). ` +
                  `La primera: ${faltanFotos[0].descripcion.slice(0, 40)}…`)
      const primera = faltanFotos[0]
      setAbiertos((a) => ({ ...a, [primera.id]: true }))
      document.getElementById(`item-${primera.id}`)?.scrollIntoView({ behavior: 'smooth', block: 'center' })
      return
    }
    setGuardando(true)
    try {
      const finAt = new Date().toISOString()
      const itemsPayload = items.map((it) => {
        const st = estado[it.id] ?? {}
        return {
          pauta_item_id: it.id, resultado: st.resultado ?? null, valor_medicion: st.valor ?? null,
          observacion: st.obs ?? null,
          antesFiles: st.antesFiles ?? [], despuesFiles: st.despuesFiles ?? [],
          fotosAntesUrls: st.fotosAntes ?? [], fotosDespuesUrls: st.fotosDespues ?? [],
        }
      }).filter((p) => p.resultado || p.valor_medicion || p.observacion ||
                       p.antesFiles.length || p.despuesFiles.length ||
                       p.fotosAntesUrls.length || p.fotosDespuesUrls.length)

      const r = await queueEjecucion({
        programacionId: prog.programacion_id, conMandante: conFirmaMandante,
        otNumero: otNumero || null, ejecutor: perfil?.nombre_completo ?? null,
        tecnicoNombre: perfil?.nombre_completo ?? null, observacion: obs || null,
        firmanteMandante: firmante || null, items: itemsPayload,
        firmaTecFile: firmaTec ? dataUrlToBlob(firmaTec) : null,
        firmaMandFile: conFirmaMandante && firmaMand ? dataUrlToBlob(firmaMand) : null,
        inicioAt, finAt, duracionSegundos: segundos,
      })
      qc.invalidateQueries({ queryKey: ['enex-terreno'] })
      qc.invalidateQueries({ queryKey: ['enex-pending-count'] })
      toast.success(r.synced
        ? (conFirmaMandante ? `Registrada y CUMPLIDA · ${hhmmss(segundos)} de trabajo` : 'Ejecución guardada')
        : 'Guardada local — se sube sola al recuperar señal')
      if (conFirmaMandante) {
        try { localStorage.removeItem(claveTimer) } catch { /* no-op */ }
      }
      if (conFirmaMandante && r.synced) {
        getEjecucionIdDeProgramacion(prog.programacion_id)
          .then((eid) => (eid ? generarYGuardarInformeEnex(eid) : null))
          .then((url) => { if (url) toast.success('Informe PDF generado y guardado') })
          .catch(() => toast.error('El informe PDF no se pudo generar — se puede generar desde el panel'))
      }
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
      <div className="flex items-center justify-between">
        <Link href="/m/enex" className="inline-flex items-center gap-1 text-sm text-gray-500"><ArrowLeft className="h-4 w-4" /> Servicios</Link>
        {/* [MIG265] Cronómetro: parte solo al abrir el servicio. */}
        <div className="flex items-center gap-1 rounded-full bg-gray-900 px-2.5 py-1 text-xs font-bold text-white tabular-nums">
          <Timer className="h-3.5 w-3.5" /> {hhmmss(segundos)}
        </div>
      </div>

      <div className="rounded-xl border border-gray-200 bg-white p-3">
        <div className="text-sm font-bold text-gray-900">{prog.instalacion}{prog.patente ? ` · ${prog.patente}` : ''}</div>
        <div className="text-xs text-gray-500">{prog.faena} · {prog.tipo_servicio === 'calibracion' ? 'Calibración' : 'Mantención'}</div>
        <div className="mt-1 text-[11px] text-gray-500">{prog.pauta_nombre}{prog.pauta_borrador ? ' (borrador)' : ''}</div>
        {items.length > 0 && (
          <div className="mt-2">
            <div className="flex items-center justify-between text-[11px] text-gray-500">
              <span>{listos}/{items.length} actividades con antes y después</span>
              {!online && <span className="flex items-center gap-1 text-amber-600"><WifiOff className="h-3 w-3" /> sin señal</span>}
            </div>
            <div className="mt-1 h-1.5 w-full overflow-hidden rounded-full bg-gray-200">
              <div className="h-full bg-blue-500 transition-all"
                   style={{ width: `${items.length ? Math.round((listos / items.length) * 100) : 0}%` }} />
            </div>
          </div>
        )}
      </div>

      {prog.es_recobro && !prog.cumplida && (
        <div className="flex items-start gap-2 rounded-xl border border-amber-300 bg-amber-50 p-3 text-xs text-amber-800">
          <Repeat className="mt-0.5 h-4 w-4 flex-shrink-0" />
          <span><b>Este servicio es un RECOBRO.</b> Ya se atendió/calibró este punto en el trimestre; esta repetición se factura como adicional a ENEX.</span>
        </div>
      )}

      <div className="grid grid-cols-2 gap-2">
        <input value={otNumero} onChange={(e) => setOtNumero(e.target.value)} placeholder="N° OT (mandante)"
               className="rounded-lg border border-gray-200 px-3 py-2 text-sm" />
        <input value={obs} onChange={(e) => setObs(e.target.value)} placeholder="Observación general"
               className="rounded-lg border border-gray-200 px-3 py-2 text-sm" />
      </div>

      {isLoading ? <div className="flex justify-center py-8"><Spinner /></div> : grupos.map((g) => {
        const listosG = g.items.filter((it) => itemListo(estado[it.id] ?? {})).length
        return (
        <div key={g.bloque}>
          <div className="sticky top-0 z-10 flex items-center justify-between gap-2 rounded bg-gray-100 px-2 py-1">
            <span className="text-xs font-semibold text-gray-700">{g.bloque}</span>
            <div className="flex items-center gap-2">
              <span className={`rounded-full px-1.5 py-0.5 text-[10px] font-bold ${
                listosG === g.items.length ? 'bg-green-200 text-green-800' : 'bg-white text-gray-500'}`}>
                {listosG}/{g.items.length}
              </span>
              <button onClick={() => setAbiertos((a) => {
                        const todos = { ...a }
                        const algunoAbierto = g.items.some((it) => todos[it.id])
                        for (const it of g.items) todos[it.id] = !algunoAbierto
                        return todos
                      })}
                      className="text-[10px] font-semibold text-blue-600">
                {g.items.some((it) => abiertos[it.id]) ? 'Comprimir' : 'Abrir'}
              </button>
            </div>
          </div>
          <div className="space-y-2 pt-2">
            {g.items.map((it) => {
              const st = estado[it.id] ?? {}
              const dt = dentroTol(it, st.valor)
              const abierto = abiertos[it.id] ?? false
              const completo = itemListo(st)
              return (
                <div key={it.id} id={`item-${it.id}`}
                     className={`rounded-xl border bg-white ${completo ? 'border-green-300' : 'border-gray-200'}`}>
                  {/* Cabecera: siempre visible, se toca para comprimir/abrir */}
                  <button onClick={() => setAbiertos((a) => ({ ...a, [it.id]: !abierto }))}
                          className="flex w-full items-start gap-1.5 p-3 text-left">
                    {abierto ? <ChevronDown className="mt-0.5 h-4 w-4 flex-shrink-0 text-gray-400" />
                             : <ChevronRight className="mt-0.5 h-4 w-4 flex-shrink-0 text-gray-400" />}
                    <div className="min-w-0 flex-1">
                      <div className="flex items-start gap-1.5">
                        {it.codigo && <span className="text-[10px] font-mono text-gray-400">{it.codigo}</span>}
                        <p className={`flex-1 text-sm text-gray-800 ${abierto ? '' : 'line-clamp-2'}`}>{it.descripcion}</p>
                      </div>
                      {/* Resumen cuando está comprimido */}
                      <div className="mt-1 flex flex-wrap items-center gap-1">
                        {st.resultado && (
                          <span className={`rounded px-1.5 py-0.5 text-[10px] font-bold ${
                            st.resultado === 'ok' || st.resultado === 'si' ? 'bg-green-100 text-green-700'
                            : st.resultado === 'na' ? 'bg-gray-100 text-gray-500'
                            : 'bg-red-100 text-red-700'}`}>
                            {st.resultado.toUpperCase().replace('_', ' ')}
                          </span>
                        )}
                        {st.valor && <span className="rounded bg-blue-50 px-1.5 py-0.5 text-[10px] text-blue-700">{st.valor} {it.unidad ?? ''}</span>}
                        <span className={`rounded px-1.5 py-0.5 text-[10px] font-semibold ${
                          nAntes(st) > 0 ? 'bg-green-100 text-green-700' : 'bg-amber-100 text-amber-700'}`}>
                          antes {nAntes(st)}
                        </span>
                        <span className={`rounded px-1.5 py-0.5 text-[10px] font-semibold ${
                          nDespues(st) > 0 ? 'bg-green-100 text-green-700' : 'bg-amber-100 text-amber-700'}`}>
                          después {nDespues(st)}
                        </span>
                        {it.critico && <span className="rounded bg-red-600 px-1 py-0.5 text-[9px] font-bold text-white">CRÍTICA</span>}
                      </div>
                    </div>
                  </button>

                  {abierto && (
                    <div className="border-t border-gray-100 p-3 pt-2">
                      {/* Campo por tipo */}
                      {(it.tipo_campo === 'ok_nook' || it.tipo_campo === 'si_no') && (
                        <div className="flex gap-1.5">
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
                        <div className="flex items-center gap-2">
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
                               className="w-full rounded-lg border border-gray-200 px-3 py-2 text-sm" />
                      )}

                      {/* [MIG265] Antes y después en TODA actividad, varias fotos */}
                      <div className={`mt-2 rounded-lg border p-2 ${completo ? 'border-green-200 bg-green-50/40' : 'border-amber-300 bg-amber-50'}`}>
                        <p className="mb-1.5 flex items-center gap-1 text-[11px] font-semibold text-gray-700">
                          {completo ? <Check className="h-3.5 w-3.5 text-green-600" /> : <AlertTriangle className="h-3.5 w-3.5 text-amber-700" />}
                          {st.resultado === 'na'
                            ? 'Marcada N/A — no necesita evidencia'
                            : 'Foto del antes y del después (puedes sacar varias)'}
                        </p>
                        <div className="grid grid-cols-2 gap-2">
                          {(['antes', 'despues'] as const).map((tipo) => {
                            const subidas = (tipo === 'antes' ? st.fotosAntes : st.fotosDespues) ?? []
                            const nuevas  = (tipo === 'antes' ? st.antesFiles : st.despuesFiles) ?? []
                            const total = subidas.length + nuevas.length
                            const refKey = `${it.id}:${tipo}`
                            return (
                              <div key={tipo}>
                                <button onClick={() => fileRefs.current[refKey]?.click()}
                                        className={`flex w-full items-center justify-center gap-1 rounded-lg border px-2 py-2 text-[11px] font-semibold ${
                                          total > 0 ? 'border-green-400 bg-green-50 text-green-700' : 'border-amber-400 bg-white text-amber-700'}`}>
                                  {total > 0 ? <Plus className="h-3.5 w-3.5" /> : <Camera className="h-3.5 w-3.5" />}
                                  {tipo === 'antes' ? 'Antes' : 'Después'}{total > 0 ? ` (${total})` : ''}
                                </button>
                                <div className="mt-1 flex flex-wrap gap-1">
                                  {subidas.map((url, i) => (
                                    <div key={`u${i}`} className="relative">
                                      {/* eslint-disable-next-line @next/next/no-img-element */}
                                      <img src={url} alt={tipo} className="h-12 w-12 rounded border object-cover" />
                                      <button onClick={() => quitarFoto(it.id, tipo, i, true)}
                                              className="absolute -right-1 -top-1 rounded-full bg-white p-0.5 shadow">
                                        <Trash2 className="h-3 w-3 text-red-500" />
                                      </button>
                                    </div>
                                  ))}
                                  {nuevas.map((f, i) => (
                                    <div key={`n${i}`} className="relative">
                                      {/* eslint-disable-next-line @next/next/no-img-element */}
                                      <img src={URL.createObjectURL(f)} alt={tipo} className="h-12 w-12 rounded border border-blue-300 object-cover" />
                                      <button onClick={() => quitarFoto(it.id, tipo, i, false)}
                                              className="absolute -right-1 -top-1 rounded-full bg-white p-0.5 shadow">
                                        <Trash2 className="h-3 w-3 text-red-500" />
                                      </button>
                                    </div>
                                  ))}
                                </div>
                                <input ref={(el) => { fileRefs.current[refKey] = el }} type="file" accept="image/*"
                                       capture="environment" multiple className="hidden"
                                       onChange={(e) => { if (e.target.files?.length) agregarFotos(it.id, tipo, e.target.files); e.target.value = '' }} />
                              </div>
                            )
                          })}
                        </div>
                      </div>
                    </div>
                  )}
                </div>
              )
            })}
          </div>
        </div>
        )
      })}

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
      <div className="fixed inset-x-0 bottom-0 mx-auto max-w-[480px] border-t bg-white p-3">
        {faltanFotos.length > 0 && (
          <p className="mb-1.5 text-center text-[11px] text-amber-700">
            Faltan antes/después en {faltanFotos.length} actividad(es) para poder cerrar
          </p>
        )}
        <div className="flex gap-2">
          <Button variant="outline" className="flex-1" disabled={guardando} onClick={() => guardar(false)}>
            {guardando ? <Loader2 className="h-4 w-4 mr-1 animate-spin" /> : null} Guardar avance
          </Button>
          <Button className="flex-1" disabled={guardando || !firmaMand} onClick={() => guardar(true)}>
            <CheckCircle2 className="h-4 w-4 mr-1" /> Cerrar (cumplida)
          </Button>
        </div>
      </div>
    </div>
  )
}
