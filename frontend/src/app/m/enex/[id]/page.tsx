'use client'

// Ejecución de pauta en terreno (MIG208 · MIG265): el mantenedor marca cada
// ítem, mide (con tolerancia automática), saca fotos del ANTES y del DESPUÉS
// —varias si quiere—, firma él y el mandante. La app cronometra el trabajo,
// cada ítem se puede comprimir y todo lo marcado se guarda solo en el teléfono.
//
// En terreno la pauta CASI NUNCA se hace completa: se ataca un punto en
// particular. Por eso la evidencia se exige en toda actividad que se haya
// trabajado, y las que no se tocaron no bloquean el cierre.

import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import Link from 'next/link'
import { useParams, useRouter } from 'next/navigation'
import {
  ArrowLeft, Camera, Check, X, Minus, CheckCircle2, Loader2, Ruler, AlertTriangle, Repeat,
  ChevronDown, ChevronRight, Timer, Plus, Trash2, WifiOff, Save,
} from 'lucide-react'
import { Spinner } from '@/components/ui/spinner'
import { Button } from '@/components/ui/button'
import { SignaturePad } from '@/components/ui/signature-pad'
import { useAuth } from '@/contexts/auth-context'
import { useToast } from '@/contexts/toast-context'
import { getEjecucionIdDeProgramacion, type EnexPautaItem, type EnexPendiente } from '@/lib/services/enex'
import { generarYGuardarInformeEnex } from '@/components/enex/pdf-informe-enex'
import {
  getPendienteOffline, getPautaItemsOffline, getEjecucionItemsOffline, queueEjecucion,
  guardarFotoLocal, getFotoLocal, guardarDraft, getDraft, borrarDraft,
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

/** Una foto: ya subida (url) o capturada en terreno (blob guardado local). */
type Foto = { id: string; url?: string; blobId?: string; preview: string }
type Estado = { resultado?: string; valor?: string; obs?: string; antes: Foto[]; despues: Foto[] }
const vacio = (): Estado => ({ antes: [], despues: [] })

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

/**
 * ¿Se intervino esta actividad en esta visita? Lo que no se tocó no exige
 * evidencia ni bloquea el cierre: la pauta se ataca por partes.
 * N/A es una decisión explícita de "no aplica", tampoco pide fotos.
 */
const trabajado = (st: Estado): boolean =>
  st.resultado === 'na'
    ? false
    : (!!st.resultado || !!st.valor || !!st.obs?.trim() ||
       // Sacar fotos ES intervenir: antes quedaban como «no intervenida» y su
       // evidencia no contaba para nadie.
       st.antes.length > 0 || st.despues.length > 0)
const conEvidencia = (st: Estado): boolean => st.antes.length > 0 && st.despues.length > 0
const itemListo = (st: Estado): boolean => !trabajado(st) || conEvidencia(st)

/** Lo trabajado necesita su dato: el resultado, la medición o la anotación. */
function faltaDato(it: EnexPautaItem, st: Estado): boolean {
  if (!trabajado(st)) return false
  if (it.tipo_campo === 'medicion') return !st.valor
  if (it.tipo_campo === 'texto') return !st.obs?.trim()
  return !st.resultado
}

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

  // El servicio se busca por su id, no dentro del mes en curso: un trabajo de
  // julio abierto el 2 de agosto se quedaba en «Cargando servicio…» para
  // siempre.
  const { data: prog, isLoading: buscandoProg } = useQuery<EnexPendiente | null>({
    queryKey: ['enex-servicio', progId], queryFn: () => getPendienteOffline(progId),
    networkMode: 'always', staleTime: 10_000, enabled: !!progId,
  })
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
  const [cargado, setCargado] = useState(false)
  const [borradorAt, setBorradorAt] = useState<string | null>(null)
  const fileRefs = useRef<Record<string, HTMLInputElement | null>>({})

  // ── Cronómetro ───────────────────────────────────────────────────────────
  // Mide el TRABAJO, no el rato que la pantalla estuvo abierta: arranca con la
  // primera marca real. Antes partía al abrir, así que mirar un servicio y
  // dejarlo abierto inflaba la duración (y un inicio de ayer contaba horas).
  const claveTimer = `enex-inicio:${progId}`
  const [inicioAt, setInicioAt] = useState<string | null>(null)
  const [ahora, setAhora] = useState<number>(() => Date.now())
  useEffect(() => {
    if (!progId) return
    const ini = typeof localStorage !== 'undefined' ? localStorage.getItem(claveTimer) : null
    if (!ini) return
    // Un inicio de otro día es basura: el trabajo no siguió toda la noche.
    if (new Date(ini).toDateString() !== new Date().toDateString()) {
      try { localStorage.removeItem(claveTimer) } catch { /* no-op */ }
      return
    }
    setInicioAt(ini)
  }, [progId, claveTimer])
  const arrancarCrono = useCallback(() => {
    setInicioAt((prev) => {
      if (prev) return prev
      const ini = new Date().toISOString()
      try { localStorage.setItem(claveTimer, ini) } catch { /* modo privado */ }
      return ini
    })
  }, [claveTimer])
  useEffect(() => {
    if (!inicioAt) return
    const t = setInterval(() => setAhora(Date.now()), 1000)
    return () => clearInterval(t)
  }, [inicioAt])
  const segundos = inicioAt ? Math.max(0, Math.floor((ahora - new Date(inicioAt).getTime()) / 1000)) : 0

  // ── Cargar: primero lo del servidor, encima el borrador local ────────────
  // Espera a tener el servicio: si corría antes, `ejecucion_id` todavía no
  // existía y lo ya registrado en el servidor nunca se leía.
  useEffect(() => {
    if (!prog || cargado) return
    let cancel = false
    ;(async () => {
      const base: Record<string, Estado> = {}
      if (prog?.ejecucion_id) {
        try {
          const rows = await getEjecucionItemsOffline(prog.ejecucion_id)
          for (const r of rows) {
            const urls = (arr: string[] | null, uno: string | null) =>
              (arr?.length ? arr : uno ? [uno] : []).map((u, i) => ({ id: `s${i}-${u}`, url: u, preview: u }))
            base[r.pauta_item_id] = {
              resultado: r.resultado ?? undefined,
              valor: r.valor_medicion?.toString(),
              obs: r.observacion ?? undefined,
              antes: urls(r.fotos_antes, r.foto_antes_url),
              despues: urls(r.fotos_despues, r.foto_despues_url),
            }
          }
        } catch { /* sin señal y sin cache: se parte de cero */ }
      }
      // El borrador local manda: es lo último que hizo el mantenedor.
      const d = await getDraft(progId)
      if (d) {
        for (const [itemId, di] of Object.entries(d.items ?? {})) {
          const rehidratar = async (fotos: { id: string; url?: string; blob_id?: string }[]): Promise<Foto[]> => {
            const out: Foto[] = []
            for (const f of fotos ?? []) {
              if (f.url) { out.push({ id: f.id, url: f.url, preview: f.url }); continue }
              if (f.blob_id) {
                const b = await getFotoLocal(f.blob_id)
                if (b) out.push({ id: f.id, blobId: f.blob_id, preview: URL.createObjectURL(b) })
              }
            }
            return out
          }
          // Red de seguridad: si el borrador apuntaba a blobs que ya no están
          // (los borra la cola al subirlos), se conservan las del servidor en
          // vez de dejar el ítem sin evidencia y bloquear el cierre.
          const conservar = async (
            locales: { id: string; url?: string; blob_id?: string }[], delServidor: Foto[],
          ): Promise<Foto[]> => {
            const vivas = await rehidratar(locales)
            if (vivas.length >= (locales?.length ?? 0)) return vivas
            const urls = new Set(vivas.map((f) => f.url).filter(Boolean))
            return [...delServidor.filter((f) => f.url && !urls.has(f.url)), ...vivas]
          }
          const previo = base[itemId]
          base[itemId] = {
            resultado: di.resultado ?? undefined,
            valor: di.valor ?? undefined,
            obs: di.obs ?? undefined,
            antes: await conservar(di.antes ?? [], previo?.antes ?? []),
            despues: await conservar(di.despues ?? [], previo?.despues ?? []),
          }
        }
        if (d.ot_numero) setOtNumero(d.ot_numero)
        if (d.observacion) setObs(d.observacion)
        if (d.firmante) setFirmante(d.firmante)
        setBorradorAt(d.updated_at)
      }
      if (!cancel) { setEstado(base); setCargado(true) }
    })()
    return () => { cancel = true }
  }, [progId, prog, cargado])

  // ── Guardado automático del borrador ─────────────────────────────────────
  const draftTimer = useRef<ReturnType<typeof setTimeout> | null>(null)
  useEffect(() => {
    if (!cargado || !progId) return
    if (draftTimer.current) clearTimeout(draftTimer.current)
    draftTimer.current = setTimeout(() => {
      const itemsDraft: Record<string, {
        resultado?: string | null; valor?: string | null; obs?: string | null
        antes: { id: string; url?: string; blob_id?: string }[]
        despues: { id: string; url?: string; blob_id?: string }[]
      }> = {}
      for (const [id, st] of Object.entries(estado)) {
        if (!trabajado(st) && st.antes.length === 0 && st.despues.length === 0) continue
        const map = (f: Foto) => ({ id: f.id, url: f.url, blob_id: f.blobId })
        itemsDraft[id] = {
          resultado: st.resultado ?? null, valor: st.valor ?? null, obs: st.obs ?? null,
          antes: st.antes.map(map), despues: st.despues.map(map),
        }
      }
      guardarDraft({
        programacion_id: progId, ot_numero: otNumero || null, observacion: obs || null,
        firmante: firmante || null, inicio_at: inicioAt, items: itemsDraft,
      }).then(() => setBorradorAt(new Date().toISOString())).catch(() => { /* no bloquear el trabajo */ })
    }, 600)
    return () => { if (draftTimer.current) clearTimeout(draftTimer.current) }
  }, [estado, otNumero, obs, firmante, inicioAt, cargado, progId])

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
    arrancarCrono()
    setEstado((p) => ({ ...p, [id]: { ...vacio(), ...p[id], ...patch } }))
  }, [arrancarCrono])

  // Las fotos se guardan en el teléfono apenas se sacan: si la app se cierra,
  // no se pierden.
  const agregarFotos = async (id: string, tipo: 'antes' | 'despues', files: FileList) => {
    arrancarCrono()
    const nuevas: Foto[] = []
    for (const f of Array.from(files)) {
      try {
        const blobId = await guardarFotoLocal(f)
        nuevas.push({ id: blobId, blobId, preview: URL.createObjectURL(f) })
      } catch {
        toast.error('No se pudo guardar la foto en el teléfono')
      }
    }
    if (nuevas.length === 0) return
    setEstado((p) => {
      const st = p[id] ?? vacio()
      return {
        ...p,
        [id]: tipo === 'antes'
          ? { ...st, antes: [...st.antes, ...nuevas] }
          : { ...st, despues: [...st.despues, ...nuevas] },
      }
    })
  }
  const quitarFoto = (id: string, tipo: 'antes' | 'despues', fotoId: string) => {
    setEstado((p) => {
      const st = p[id] ?? vacio()
      return {
        ...p,
        [id]: tipo === 'antes'
          ? { ...st, antes: st.antes.filter((f) => f.id !== fotoId) }
          : { ...st, despues: st.despues.filter((f) => f.id !== fotoId) },
      }
    })
  }

  const trabajadas = items.filter((it) => trabajado(estado[it.id] ?? vacio()))
  const faltanFotos = trabajadas.filter((it) => !conEvidencia(estado[it.id] ?? vacio()))
  const faltanDato = trabajadas.filter((it) => faltaDato(it, estado[it.id] ?? vacio()))

  /** Lleva al ítem que falta y lo abre. */
  const irAlItem = (it: EnexPautaItem) => {
    setAbiertos((a) => ({ ...a, [it.id]: true }))
    document.getElementById(`item-${it.id}`)?.scrollIntoView({ behavior: 'smooth', block: 'center' })
  }

  async function guardar(conFirmaMandante: boolean) {
    if (!prog) return
    if (conFirmaMandante && !firmaMand) { toast.error('Falta la firma del mandante'); return }
    // La evidencia se exige en lo que SE TRABAJÓ. Lo no intervenido no bloquea:
    // en terreno la pauta se ataca por partes.
    if (conFirmaMandante && faltanFotos.length > 0) {
      toast.error(`Faltan fotos de antes/después en ${faltanFotos.length} actividad(es) trabajada(s). ` +
                  `La primera: ${faltanFotos[0].descripcion.slice(0, 40)}…`)
      irAlItem(faltanFotos[0])
      return
    }
    if (conFirmaMandante && faltanDato.length > 0) {
      toast.error(`${faltanDato.length} actividad(es) con evidencia pero sin marcar. ` +
                  `La primera: ${faltanDato[0].descripcion.slice(0, 40)}…`)
      irAlItem(faltanDato[0])
      return
    }
    if (conFirmaMandante && trabajadas.length === 0) {
      toast.error('No hay ninguna actividad trabajada para cerrar el servicio')
      return
    }
    setGuardando(true)
    try {
      const finAt = new Date().toISOString()
      const itemsPayload = items.map((it) => {
        const st = estado[it.id] ?? vacio()
        return {
          pauta_item_id: it.id, resultado: st.resultado ?? null, valor_medicion: st.valor ?? null,
          observacion: st.obs ?? null,
          antesBlobIds: st.antes.filter((f) => f.blobId).map((f) => f.blobId!),
          despuesBlobIds: st.despues.filter((f) => f.blobId).map((f) => f.blobId!),
          fotosAntesUrls: st.antes.filter((f) => f.url).map((f) => f.url!),
          fotosDespuesUrls: st.despues.filter((f) => f.url).map((f) => f.url!),
        }
      }).filter((p) => p.resultado || p.valor_medicion || p.observacion ||
                       p.antesBlobIds.length || p.despuesBlobIds.length ||
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
      qc.invalidateQueries({ queryKey: ['enex-servicio', progId] })
      qc.invalidateQueries({ queryKey: ['enex-pending-count'] })
      toast.success(r.synced
        ? (conFirmaMandante ? `Registrada y CUMPLIDA · ${hhmmss(segundos)} de trabajo` : 'Avance guardado — puedes seguir')
        : 'Guardada local — se sube sola al recuperar señal')
      if (conFirmaMandante) {
        // Cerrado el servicio: el borrador y el cronómetro ya no hacen falta.
        await borrarDraft(prog.programacion_id).catch(() => undefined)
        try { localStorage.removeItem(claveTimer) } catch { /* no-op */ }
      }
      if (conFirmaMandante && r.synced) {
        getEjecucionIdDeProgramacion(prog.programacion_id)
          .then((eid) => (eid ? generarYGuardarInformeEnex(eid) : null))
          .then((url) => { if (url) toast.success('Informe PDF generado y guardado') })
          .catch(() => toast.error('El informe PDF no se pudo generar — se puede generar desde el panel'))
      }
      // Guardar avance NO saca de la pantalla: en terreno se sigue trabajando
      // el mismo punto. Solo el cierre vuelve a la lista de servicios.
      if (conFirmaMandante) router.push('/m/enex')
    } catch (e) { toast.error((e as Error).message) } finally { setGuardando(false) }
  }

  if (!prog && buscandoProg) return <div className="p-6 text-center text-sm text-gray-400">Cargando servicio…</div>
  if (!prog) return (
    <div className="p-4 space-y-3">
      <Link href="/m/enex" className="inline-flex items-center gap-1 text-sm text-gray-500"><ArrowLeft className="h-4 w-4" /> Volver</Link>
      <div className="rounded-lg border border-amber-300 bg-amber-50 p-3 text-sm text-amber-800">
        No se encontró este servicio.{!online && ' Estás sin señal y no está descargado en el teléfono: ábrelo con conexión para bajarlo.'}
      </div>
    </div>
  )
  if (!prog.pauta_id) return (
    <div className="p-4 space-y-3">
      <Link href="/m/enex" className="inline-flex items-center gap-1 text-sm text-gray-500"><ArrowLeft className="h-4 w-4" /> Volver</Link>
      <div className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">
        Esta instalación no tiene pauta asignada para este servicio. Avisa al supervisor para vincular la pauta.
      </div>
    </div>
  )

  return (
    <div className="p-3 space-y-3 pb-28">
      <div className="flex items-center justify-between">
        <Link href="/m/enex" className="inline-flex items-center gap-1 text-sm text-gray-500"><ArrowLeft className="h-4 w-4" /> Servicios</Link>
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
              <span>{trabajadas.length} de {items.length} actividades trabajadas
                {faltanFotos.length > 0 && <span className="text-amber-700"> · {faltanFotos.length} sin evidencia</span>}
              </span>
              {!online && <span className="flex items-center gap-1 text-amber-600"><WifiOff className="h-3 w-3" /> sin señal</span>}
            </div>
            <div className="mt-1 h-1.5 w-full overflow-hidden rounded-full bg-gray-200">
              <div className="h-full bg-blue-500 transition-all"
                   style={{ width: `${items.length ? Math.round((trabajadas.length / items.length) * 100) : 0}%` }} />
            </div>
            <p className="mt-1 flex items-center gap-1 text-[10px] text-gray-400">
              <Save className="h-3 w-3" />
              {borradorAt
                ? `guardado en el teléfono ${new Date(borradorAt).toLocaleTimeString('es-CL', { hour: '2-digit', minute: '2-digit' })}`
                : 'se guarda solo a medida que marcas'}
            </p>
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
        const trabG = g.items.filter((it) => trabajado(estado[it.id] ?? vacio())).length
        const faltaG = g.items.filter((it) => !itemListo(estado[it.id] ?? vacio())).length
        return (
        <div key={g.bloque}>
          <div className="sticky top-0 z-10 flex items-center justify-between gap-2 rounded bg-gray-100 px-2 py-1">
            <span className="text-xs font-semibold text-gray-700">{g.bloque}</span>
            <div className="flex items-center gap-2">
              <span className={`rounded-full px-1.5 py-0.5 text-[10px] font-bold ${
                faltaG > 0 ? 'bg-amber-200 text-amber-900'
                : trabG > 0 ? 'bg-green-200 text-green-800' : 'bg-white text-gray-500'}`}>
                {trabG}/{g.items.length}
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
              const st = estado[it.id] ?? vacio()
              const dt = dentroTol(it, st.valor)
              const abierto = abiertos[it.id] ?? false
              const trab = trabajado(st)
              const falta = trab && !conEvidencia(st)
              return (
                <div key={it.id} id={`item-${it.id}`}
                     className={`rounded-xl border bg-white ${
                       falta ? 'border-amber-400' : trab ? 'border-green-300' : 'border-gray-200'}`}>
                  <button onClick={() => setAbiertos((a) => ({ ...a, [it.id]: !abierto }))}
                          className="flex w-full items-start gap-1.5 p-3 text-left">
                    {abierto ? <ChevronDown className="mt-0.5 h-4 w-4 flex-shrink-0 text-gray-400" />
                             : <ChevronRight className="mt-0.5 h-4 w-4 flex-shrink-0 text-gray-400" />}
                    <div className="min-w-0 flex-1">
                      <div className="flex items-start gap-1.5">
                        {it.codigo && <span className="text-[10px] font-mono text-gray-400">{it.codigo}</span>}
                        <p className={`flex-1 text-sm ${trab ? 'text-gray-800' : 'text-gray-500'} ${abierto ? '' : 'line-clamp-2'}`}>{it.descripcion}</p>
                      </div>
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
                        {trab ? (
                          <>
                            <span className={`rounded px-1.5 py-0.5 text-[10px] font-semibold ${
                              st.antes.length > 0 ? 'bg-green-100 text-green-700' : 'bg-amber-100 text-amber-700'}`}>
                              antes {st.antes.length}
                            </span>
                            <span className={`rounded px-1.5 py-0.5 text-[10px] font-semibold ${
                              st.despues.length > 0 ? 'bg-green-100 text-green-700' : 'bg-amber-100 text-amber-700'}`}>
                              después {st.despues.length}
                            </span>
                          </>
                        ) : (
                          <span className="rounded bg-gray-100 px-1.5 py-0.5 text-[10px] text-gray-400">no intervenida</span>
                        )}
                        {it.critico && <span className="rounded bg-red-600 px-1 py-0.5 text-[9px] font-bold text-white">CRÍTICA</span>}
                      </div>
                    </div>
                  </button>

                  {abierto && (
                    <div className="border-t border-gray-100 p-3 pt-2">
                      {(it.tipo_campo === 'ok_nook' || it.tipo_campo === 'si_no') && (
                        <div className="flex gap-1.5">
                          {(it.tipo_campo === 'ok_nook'
                            ? [['ok', 'OK', 'bg-green-500', Check], ['no_ok', 'NO OK', 'bg-red-500', X], ['na', 'N/A', 'bg-gray-400', Minus]]
                            : [['si', 'Sí', 'bg-green-500', Check], ['no', 'No', 'bg-red-500', X]]
                          ).map(([val, label, color, Icon]) => {
                            const active = st.resultado === val
                            const I = Icon as typeof Check
                            return (
                              <button key={val as string}
                                      onClick={() => upd(it.id, { resultado: active ? undefined : (val as string) })}
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

                      {/* Antes y después: obligatorio en lo que se trabaja */}
                      <div className={`mt-2 rounded-lg border p-2 ${
                        !trab ? 'border-gray-200 bg-gray-50'
                        : falta ? 'border-amber-300 bg-amber-50' : 'border-green-200 bg-green-50/40'}`}>
                        <p className="mb-1.5 flex items-center gap-1 text-[11px] font-semibold text-gray-700">
                          {!trab ? <Minus className="h-3.5 w-3.5 text-gray-400" />
                            : falta ? <AlertTriangle className="h-3.5 w-3.5 text-amber-700" />
                            : <Check className="h-3.5 w-3.5 text-green-600" />}
                          {!trab
                            ? 'Si intervienes esta actividad, saca antes y después'
                            : 'Foto del antes y del después (puedes sacar varias)'}
                        </p>
                        <div className="grid grid-cols-2 gap-2">
                          {(['antes', 'despues'] as const).map((tipo) => {
                            const fotos = tipo === 'antes' ? st.antes : st.despues
                            const refKey = `${it.id}:${tipo}`
                            return (
                              <div key={tipo}>
                                <button onClick={() => fileRefs.current[refKey]?.click()}
                                        className={`flex w-full items-center justify-center gap-1 rounded-lg border px-2 py-2 text-[11px] font-semibold ${
                                          fotos.length > 0 ? 'border-green-400 bg-green-50 text-green-700'
                                          : trab ? 'border-amber-400 bg-white text-amber-700'
                                          : 'border-gray-300 bg-white text-gray-500'}`}>
                                  {fotos.length > 0 ? <Plus className="h-3.5 w-3.5" /> : <Camera className="h-3.5 w-3.5" />}
                                  {tipo === 'antes' ? 'Antes' : 'Después'}{fotos.length > 0 ? ` (${fotos.length})` : ''}
                                </button>
                                <div className="mt-1 flex flex-wrap gap-1">
                                  {fotos.map((f) => (
                                    <div key={f.id} className="relative">
                                      {/* eslint-disable-next-line @next/next/no-img-element */}
                                      <img src={f.preview} alt={tipo}
                                           className={`h-12 w-12 rounded border object-cover ${f.blobId ? 'border-blue-300' : ''}`} />
                                      <button onClick={() => quitarFoto(it.id, tipo, f.id)}
                                              className="absolute -right-1 -top-1 rounded-full bg-white p-0.5 shadow">
                                        <Trash2 className="h-3 w-3 text-red-500" />
                                      </button>
                                    </div>
                                  ))}
                                </div>
                                <input ref={(el) => { fileRefs.current[refKey] = el }} type="file" accept="image/*"
                                       capture="environment" multiple className="hidden"
                                       onChange={(e) => { if (e.target.files?.length) void agregarFotos(it.id, tipo, e.target.files); e.target.value = '' }} />
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
            {faltanFotos.length} actividad(es) trabajada(s) sin antes/después
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
