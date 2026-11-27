'use client'

// ============================================================================
// Inicio Seguro (MIG735) — antes de tocar la pauta de un servicio ENEX
// ----------------------------------------------------------------------------
// Manuel (27-11-2026): antes de empezar, SIEMPRE foto de los bloqueos y visto
// bueno de Hersaly; la app ayuda a armar la ART. Sin visto bueno no se inicia;
// a los 10 min sin respuesta se escala. Cualquiera puede «Detener tarea».
// Al cerrar, retiro de bloqueos con foto.
//
// Todo lo que se llena queda en el teléfono (fotos en IndexedDB, el resto en
// localStorage) hasta que haya señal para pedir el visto bueno.
// ============================================================================

import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import {
  Camera, CheckCircle2, Clock, Hand, Loader2, Lock, LockOpen, ShieldAlert, ShieldCheck, Sparkles, Trash2, Users, WifiOff, XCircle,
} from 'lucide-react'
import { useToast } from '@/contexts/toast-context'
import { useNetworkStatus } from '@/hooks/use-calama-offline'
import { supabase } from '@/lib/supabase'
import { uuidV4 } from '@/lib/uuid'
import { guardarFotoLocal, getFotoLocal } from '@/lib/offline/enex-offline'
import { EDC_PSGCC, ENERGIAS, type EdcId } from '@/lib/inicio-seguro/psgcc'
import {
  cerrarInicio, detenerInicio, getCuadrillaCalama, getEstadoInicio, pedirCorreo, solicitarInicio, subirFotoInicio,
  type InicioSeguro, type PersonaHabilitacion,
} from '@/lib/services/inicio-seguro'
import type { EnexPendiente } from '@/lib/services/enex'

const hoy = () => new Date().toLocaleDateString('sv-SE', { timeZone: 'America/Santiago' })
const leer = <T,>(k: string): T | null => { try { const v = localStorage.getItem(k); return v ? JSON.parse(v) as T : null } catch { return null } }
const escribir = (k: string, v: unknown) => { try { localStorage.setItem(k, JSON.stringify(v)) } catch { /* sin almacenamiento */ } }
const borrar = (k: string) => { try { localStorage.removeItem(k) } catch { /* no-op */ } }

type BloqueoLocal = { energia: string; punto: string; fotoBloqueo?: string; fotoCero?: string }
type Borrador = {
  clientUuid: string
  tarea: string
  cuadrilla: string[]           // personal_id
  leyoArt: string[]
  art: string
  artAsistida: boolean
  edc: EdcId[]
  psgcc: Record<string, 'si' | 'no' | 'na'>
  bloqueos: BloqueoLocal[]
  sinBloqueo: boolean
  sinBloqueoMotivo: string
}

const borradorVacio = (): Borrador => ({
  clientUuid: uuidV4(), tarea: '', cuadrilla: [], leyoArt: [], art: '', artAsistida: false, edc: [], psgcc: {},
  bloqueos: [{ energia: 'electrica', punto: '' }], sinBloqueo: false, sinBloqueoMotivo: '',
})

/** Estado del Inicio Seguro de hoy para este servicio (lo consulta cada 15 s mientras espera). */
export function useInicioSeguro(programacionId: string | undefined) {
  const online = useNetworkStatus()
  const clave = `inicio-seguro-estado:${programacionId}:${hoy()}`
  return useQuery<InicioSeguro | null>({
    queryKey: ['inicio-seguro', programacionId],
    enabled: !!programacionId,
    networkMode: 'always',
    queryFn: async () => {
      if (!online) return leer<InicioSeguro>(clave)
      try {
        const r = await getEstadoInicio(programacionId!)
        if (r) escribir(clave, r); else borrar(clave)
        return r
      } catch { return leer<InicioSeguro>(clave) }
    },
    refetchInterval: (q) => (q.state.data?.estado === 'pendiente' ? 15_000 : false),
    staleTime: 10_000,
  })
}

function FotoBoton({ blobId, etiqueta, onFoto, onQuitar }: {
  blobId?: string; etiqueta: string; onFoto: (f: File) => void; onQuitar: () => void
}) {
  const [url, setUrl] = useState<string | null>(null)
  useEffect(() => {
    let u: string | null = null
    if (blobId) void getFotoLocal(blobId).then((b) => { if (b) { u = URL.createObjectURL(b); setUrl(u) } })
    else setUrl(null)
    return () => { if (u) URL.revokeObjectURL(u) }
  }, [blobId])
  if (blobId && url) return (
    <div className="relative">
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src={url} alt={etiqueta} width={320} height={96} className="h-24 w-full rounded-lg object-cover" />
      <span className="absolute left-1 top-1 rounded bg-black/60 px-1 text-[10px] text-white">{etiqueta}</span>
      <button type="button" onClick={onQuitar} aria-label={`Quitar foto ${etiqueta}`}
              className="absolute right-1 top-1 inline-flex h-8 w-8 items-center justify-center rounded-full bg-white/90 text-red-600">
        <Trash2 className="h-4 w-4" aria-hidden="true" />
      </button>
    </div>
  )
  return (
    <label className="flex h-24 cursor-pointer flex-col items-center justify-center gap-1 rounded-lg border-2 border-dashed border-amber-400 bg-amber-50 text-center text-[11px] font-semibold text-amber-800">
      <Camera className="h-5 w-5" aria-hidden="true" /> {etiqueta}
      <input type="file" accept="image/*" capture="environment" className="sr-only"
             onChange={(e) => { const f = e.target.files?.[0]; if (f) onFoto(f); e.target.value = '' }} />
    </label>
  )
}

/** Formulario + espera del visto bueno. Se muestra en vez de la pauta hasta que Hersaly aprueba. */
export function InicioSeguroPanel({ prog, inicio, onCambio }: {
  prog: EnexPendiente; inicio: InicioSeguro | null; onCambio: () => void
}) {
  const toast = useToast()
  const online = useNetworkStatus()
  const claveBorrador = `inicio-seguro-borrador:${prog.programacion_id}:${hoy()}`
  const [b, setB] = useState<Borrador>(() => leer<Borrador>(claveBorrador) ?? borradorVacio())
  const set = useCallback((patch: Partial<Borrador>) => setB((p) => { const n = { ...p, ...patch }; escribir(claveBorrador, n); return n }), [claveBorrador])
  const [enviando, setEnviando] = useState(false)

  const { data: personas = [] } = useQuery<PersonaHabilitacion[]>({
    queryKey: ['inicio-seguro-cuadrilla'],
    networkMode: 'always',
    staleTime: 30 * 60_000,
    queryFn: async () => {
      try { const r = await getCuadrillaCalama(); escribir('inicio-seguro-cuadrilla', r); return r }
      catch { return leer<PersonaHabilitacion[]>('inicio-seguro-cuadrilla') ?? [] }
    },
  })

  // Rechazado: se corrige y se manda de nuevo con otro client_uuid.
  const rechazado = inicio?.estado === 'rechazado'
  const pendiente = inicio?.estado === 'pendiente'
  const detenido = inicio?.estado === 'detenido'

  const controles = useMemo(() => b.edc.flatMap((e) => EDC_PSGCC[e].controles.map((c) => ({ ...c, edc: e }))), [b.edc])
  const algunNo = controles.some((c) => b.psgcc[c.id] === 'no')
  const sinResponder = controles.filter((c) => !b.psgcc[c.id])
  const seleccion = personas.filter((p) => b.cuadrilla.includes(p.personal_id))
  const noHabilitados = seleccion.filter((p) => !p.habilitado)
  const bloqueosOk = b.sinBloqueo
    ? b.sinBloqueoMotivo.trim().length >= 10
    : b.bloqueos.length > 0 && b.bloqueos.every((x) => x.punto.trim() && x.fotoBloqueo && x.fotoCero)

  const faltantes = [
    !b.tarea.trim() && 'qué tarea se hará',
    b.cuadrilla.length === 0 && 'la cuadrilla',
    b.art.trim().length < 30 && 'la ART',
    b.cuadrilla.some((id) => !b.leyoArt.includes(id)) && 'que toda la cuadrilla lea la ART',
    b.edc.length === 0 && 'las EDC que aplican',
    sinResponder.length > 0 && `${sinResponder.length} control(es) crítico(s) sin responder`,
    !bloqueosOk && (b.sinBloqueo ? 'el motivo de por qué no hay bloqueo' : 'los bloqueos con sus 2 fotos'),
  ].filter(Boolean) as string[]

  // ── ART asistida por el Copiloto Prevención ───────────────────────────────
  const [armandoArt, setArmandoArt] = useState(false)
  async function armarArt() {
    if (!b.tarea.trim()) { toast.error('Primero escribe qué tarea se hará'); return }
    setArmandoArt(true)
    try {
      const { data: { session } } = await supabase.auth.getSession()
      const pregunta = `ART para: ${b.tarea.trim()}. Instalación: ${prog.instalacion} (${prog.faena}). ` +
        `Servicio de ${prog.tipo_servicio === 'calibracion' ? 'calibración' : 'mantención'}. ` +
        `EDC que aplican: ${b.edc.map((e) => EDC_PSGCC[e].nombre).join(', ') || 'por definir'}. ` +
        'Formato corto para leer en el teléfono: pasos, riesgo y control de cada paso, y las preguntas PSGCC.'
      const res = await fetch('/api/copiloto-sso/consulta', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${session?.access_token ?? ''}` },
        body: JSON.stringify({ pregunta, atajo: 'art', historial: [] }),
      })
      if (!res.ok) throw new Error((await res.json().catch(() => null))?.error ?? `Error ${res.status}`)
      const reader = res.body!.getReader(); const dec = new TextDecoder()
      let buf = '', texto = ''
      const procesar = (l: string) => {
        if (!l.trim()) return
        try { const ev = JSON.parse(l); if (ev.t === 'texto') { texto += ev.d; set({ art: texto, artAsistida: true }) } } catch { /* línea parcial */ }
      }
      for (;;) {
        const { done, value } = await reader.read(); if (done) break
        buf += dec.decode(value, { stream: true }); const ls = buf.split('\n'); buf = ls.pop() ?? ''; ls.forEach(procesar)
      }
      procesar(buf)
      toast.success('ART armada: revísala y ajústala a lo que ven en terreno')
    } catch (e) { toast.error(`No se pudo armar la ART: ${(e as Error).message}`) } finally { setArmandoArt(false) }
  }

  async function foto(i: number, campo: 'fotoBloqueo' | 'fotoCero', f: File) {
    const id = await guardarFotoLocal(f)
    set({ bloqueos: b.bloqueos.map((x, j) => (j === i ? { ...x, [campo]: id } : x)) })
  }

  async function enviar() {
    if (faltantes.length) { toast.error(`Falta: ${faltantes[0]}`); return }
    if (algunNo) return
    if (!online) { toast.error('Sin señal. Todo queda guardado: busca señal para pedir el visto bueno.'); return }
    setEnviando(true)
    try {
      const subir = async (blobId?: string) => {
        const blob = blobId ? await getFotoLocal(blobId) : null
        if (!blob) throw new Error('Una foto no está en el teléfono: vuelve a sacarla')
        return subirFotoInicio(blob)
      }
      const bloqueos = b.sinBloqueo ? [] : await Promise.all(b.bloqueos.map(async (x) => ({
        energia: x.energia, punto: x.punto.trim(),
        foto_bloqueo: await subir(x.fotoBloqueo), foto_energia_cero: await subir(x.fotoCero),
      })))
      const r = await solicitarInicio({
        client_uuid: b.clientUuid,
        programacion_id: prog.programacion_id,
        tarea: b.tarea.trim(),
        cuadrilla: seleccion.map((p) => ({
          personal_id: p.personal_id, nombre: p.nombre, habilitado: p.habilitado, leyo_art: b.leyoArt.includes(p.personal_id),
          pendientes: p.requisitos.filter((q) => q.aplica_a === 'todos' && !q.ok).map((q) => q.nombre),
        })),
        art: { texto: b.art.trim(), asistida: b.artAsistida },
        psgcc: controles.map((c) => ({ edc: c.edc, control: c.id, pregunta: c.pregunta, fuente: c.fuente, respuesta: b.psgcc[c.id] })),
        bloqueos,
        sin_bloqueo_motivo: b.sinBloqueo ? b.sinBloqueoMotivo.trim() : null,
      })
      void pedirCorreo(r.id, 'solicitud')
      toast.success('Enviado a Hersaly. Espera el visto bueno antes de empezar.')
      onCambio()
    } catch (e) { toast.error((e as Error).message) } finally { setEnviando(false) }
  }

  // Escalamiento: el teléfono que espera pide el correo cuando se cumple el plazo.
  useEffect(() => {
    if (!pendiente || !inicio || inicio.escalado_at) return
    const plazo = new Date(inicio.solicitado_at).getTime() + (inicio.minutos_escalamiento ?? 10) * 60_000
    const t = setTimeout(() => { void pedirCorreo(inicio.id, 'escalamiento').then(onCambio) }, Math.max(0, plazo - Date.now()) + 2000)
    return () => clearTimeout(t)
  }, [pendiente, inicio, onCambio])

  if (pendiente && inicio) return <EsperandoVistoBueno inicio={inicio} />
  if (detenido && inicio) return (
    <div className="rounded-xl border-2 border-red-400 bg-red-50 p-3 text-sm text-red-800">
      <p className="flex items-center gap-1.5 font-bold"><Hand className="h-5 w-5" aria-hidden="true" /> Tarea DETENIDA</p>
      <p className="mt-1">{inicio.detenido_motivo}</p>
      <p className="mt-2 text-xs">Para retomar, corrige la condición y pide un nuevo visto bueno.</p>
      <button type="button" onClick={() => { const n = borradorVacio(); set({ ...b, clientUuid: n.clientUuid }); borrar(`inicio-seguro-estado:${prog.programacion_id}:${hoy()}`); onCambio() }}
              className="mt-2 min-h-11 w-full rounded-lg bg-red-600 px-3 text-sm font-semibold text-white">Pedir nuevo visto bueno</button>
    </div>
  )

  const caja = 'rounded-xl border border-gray-200 bg-white p-3'
  const titulo = 'text-sm font-bold text-gray-900'
  return (
    <div className="space-y-3" data-testid="inicio-seguro">
      <div className="rounded-xl border-2 border-amber-400 bg-amber-50 p-3">
        <p className="flex items-center gap-1.5 text-sm font-bold text-amber-900"><ShieldAlert className="h-5 w-5" aria-hidden="true" /> Inicio seguro</p>
        <p className="mt-1 text-xs text-amber-900">
          Antes de tocar la pauta: cuadrilla, ART, controles críticos y bloqueos con foto. Sin el visto bueno de Hersaly <b>no se inicia</b>.
        </p>
      </div>

      {rechazado && inicio && (
        <div className="rounded-xl border-2 border-red-300 bg-red-50 p-3 text-sm text-red-800" role="alert">
          <p className="flex items-center gap-1.5 font-bold"><XCircle className="h-5 w-5" aria-hidden="true" /> {inicio.decidido_por_nombre ?? 'Prevención'} pidió corregir</p>
          <p className="mt-1">{inicio.comentario}</p>
          {inicio.client_uuid === b.clientUuid && (
            <button type="button" onClick={() => set({ clientUuid: uuidV4() })}
                    className="mt-2 min-h-11 w-full rounded-lg bg-red-600 px-3 text-sm font-semibold text-white">Corregir y volver a enviar</button>
          )}
        </div>
      )}

      <section className={caja}>
        <h2 className={titulo}>1. ¿Qué se va a hacer?</h2>
        <textarea value={b.tarea} onChange={(e) => set({ tarea: e.target.value })} rows={2}
                  aria-label="Tarea a realizar" placeholder="Ej. Cambio de filtro en bomba 2 de sala de bombas…"
                  className="mt-2 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm" />
      </section>

      <section className={caja}>
        <h2 className={`${titulo} flex items-center gap-1.5`}><Users className="h-4 w-4" aria-hidden="true" /> 2. Cuadrilla</h2>
        {personas.length === 0 && <p className="mt-1 text-xs text-gray-600">{online ? 'Cargando…' : 'Sin señal y sin lista guardada: ábrelo una vez con señal.'}</p>}
        <div className="mt-2 space-y-1">
          {personas.map((p) => {
            const sel = b.cuadrilla.includes(p.personal_id)
            const pend = p.requisitos.filter((q) => q.aplica_a === 'todos' && !q.ok)
            return (
              <label key={p.personal_id} className={`flex min-h-11 items-start gap-2 rounded-lg border px-2 py-2 text-sm ${sel ? 'border-blue-400 bg-blue-50' : 'border-gray-200'}`}>
                <input type="checkbox" checked={sel} className="mt-0.5 h-5 w-5"
                       onChange={() => set({ cuadrilla: sel ? b.cuadrilla.filter((x) => x !== p.personal_id) : [...b.cuadrilla, p.personal_id] })} />
                <span className="min-w-0 flex-1">
                  <span className="font-medium">{p.nombre}</span>
                  {p.habilitado
                    ? <span className="ml-1 text-xs text-emerald-700">habilitado</span>
                    : <span className="block text-xs text-amber-700">Aviso: le falta {pend.map((q) => q.nombre).join(', ') || 'algún curso o requisito'}</span>}
                </span>
              </label>
            )
          })}
        </div>
        {noHabilitados.length > 0 && (
          <p className="mt-2 rounded-lg bg-amber-50 p-2 text-xs text-amber-800">
            Aviso: {noHabilitados.length} persona(s) con cursos o requisitos pendientes. Igual puedes seguir; queda registrado.
          </p>
        )}
      </section>

      <section className={caja}>
        <h2 className={titulo}>3. Controles críticos (EDC Centinela)</h2>
        <p className="text-xs text-gray-600">Marca las EDC que aplican a esta tarea.</p>
        <div className="mt-2 space-y-1">
          {(Object.keys(EDC_PSGCC) as EdcId[]).map((e) => {
            const sel = b.edc.includes(e)
            return (
              <label key={e} className={`flex min-h-11 items-start gap-2 rounded-lg border px-2 py-2 text-sm ${sel ? 'border-blue-400 bg-blue-50' : 'border-gray-200'}`}>
                <input type="checkbox" checked={sel} className="mt-0.5 h-5 w-5"
                       onChange={() => set({ edc: sel ? b.edc.filter((x) => x !== e) : [...b.edc, e] })} />
                <span className="min-w-0"><span className="font-medium">{EDC_PSGCC[e].nombre}</span>
                  <span className="block text-[11px] text-gray-600">{EDC_PSGCC[e].cuando}</span></span>
              </label>
            )
          })}
        </div>
        {controles.length > 0 && (
          <ol className="mt-3 space-y-2">
            {controles.map((c) => (
              <li key={c.id} className={`rounded-lg border p-2 ${b.psgcc[c.id] === 'no' ? 'border-red-400 bg-red-50' : 'border-gray-200'}`}>
                <p className="text-sm text-gray-900">{c.pregunta}</p>
                <p className="text-[10px] text-gray-600">{c.fuente}</p>
                <div className="mt-1 grid grid-cols-3 gap-1" role="radiogroup" aria-label={c.pregunta}>
                  {(['si', 'no', 'na'] as const).map((v) => (
                    <button key={v} type="button" role="radio" aria-checked={b.psgcc[c.id] === v}
                            onClick={() => set({ psgcc: { ...b.psgcc, [c.id]: v } })}
                            className={`min-h-11 rounded-lg border text-sm font-semibold ${b.psgcc[c.id] === v
                              ? v === 'si' ? 'border-emerald-600 bg-emerald-700 text-white' : v === 'no' ? 'border-red-600 bg-red-600 text-white' : 'border-gray-600 bg-gray-600 text-white'
                              : 'border-gray-300 bg-white text-gray-700'}`}>
                      {v === 'si' ? 'Sí' : v === 'no' ? 'No' : 'No aplica'}
                    </button>
                  ))}
                </div>
              </li>
            ))}
          </ol>
        )}
        {algunNo && (
          <div className="mt-2 rounded-lg border-2 border-red-500 bg-red-50 p-2 text-sm font-semibold text-red-800" role="alert">
            Un control crítico NO está implementado: la tarea no se inicia. Corrige la condición o avisa al supervisor.
          </div>
        )}
      </section>

      <section className={caja}>
        <div className="flex items-center justify-between gap-2">
          <h2 className={titulo}>4. ART</h2>
          <button type="button" onClick={armarArt} disabled={armandoArt || !online}
                  className="inline-flex min-h-11 items-center gap-1 rounded-lg border border-emerald-400 bg-emerald-50 px-3 text-xs font-semibold text-emerald-800 disabled:opacity-40">
            {armandoArt ? <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" /> : <Sparkles className="h-4 w-4" aria-hidden="true" />} Armar con el copiloto
          </button>
        </div>
        <textarea value={b.art} onChange={(e) => set({ art: e.target.value })} rows={8}
                  aria-label="ART" placeholder="Pasos de la tarea, riesgo de cada paso y su control…"
                  className="mt-2 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm" />
        {b.artAsistida && <p className="text-[11px] text-amber-700">Armada con el copiloto: la cuadrilla la revisa y la ajusta a lo que ve en terreno.</p>}
        {seleccion.length > 0 && (
          <div className="mt-2 space-y-1">
            <p className="text-xs font-semibold text-gray-700">Leyó y entendió la ART:</p>
            {seleccion.map((p) => (
              <label key={p.personal_id} className="flex min-h-11 items-center gap-2 text-sm">
                <input type="checkbox" className="h-5 w-5" checked={b.leyoArt.includes(p.personal_id)}
                       onChange={(e) => set({ leyoArt: e.target.checked ? [...b.leyoArt, p.personal_id] : b.leyoArt.filter((x) => x !== p.personal_id) })} />
                {p.nombre}
              </label>
            ))}
          </div>
        )}
      </section>

      <section className={caja}>
        <h2 className={`${titulo} flex items-center gap-1.5`}><Lock className="h-4 w-4" aria-hidden="true" /> 5. Bloqueos y energía cero</h2>
        <label className="mt-2 flex min-h-11 items-center gap-2 text-sm">
          <input type="checkbox" className="h-5 w-5" checked={b.sinBloqueo} onChange={(e) => set({ sinBloqueo: e.target.checked })} />
          Esta tarea no interviene ninguna energía
        </label>
        {b.sinBloqueo ? (
          <textarea value={b.sinBloqueoMotivo} onChange={(e) => set({ sinBloqueoMotivo: e.target.value })} rows={2}
                    aria-label="Motivo sin bloqueo" placeholder="Explica por qué no hay que bloquear (Hersaly lo revisa)…"
                    className="mt-1 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm" />
        ) : (
          <div className="mt-2 space-y-3">
            {b.bloqueos.map((x, i) => (
              <div key={i} className="rounded-lg border border-gray-200 p-2">
                <div className="flex gap-2">
                  <select value={x.energia} aria-label="Energía"
                          onChange={(e) => set({ bloqueos: b.bloqueos.map((y, j) => (j === i ? { ...y, energia: e.target.value } : y)) })}
                          className="min-h-11 rounded-lg border border-gray-300 px-2 text-sm">
                    {ENERGIAS.map((en) => <option key={en.id} value={en.id}>{en.nombre}</option>)}
                  </select>
                  <input value={x.punto} placeholder="Punto de bloqueo (ej. tablero TG-1)…" aria-label="Punto de bloqueo"
                         onChange={(e) => set({ bloqueos: b.bloqueos.map((y, j) => (j === i ? { ...y, punto: e.target.value } : y)) })}
                         className="min-h-11 min-w-0 flex-1 rounded-lg border border-gray-300 px-2 text-sm" />
                  {b.bloqueos.length > 1 && (
                    <button type="button" aria-label="Quitar bloqueo" onClick={() => set({ bloqueos: b.bloqueos.filter((_, j) => j !== i) })}
                            className="inline-flex h-11 w-11 shrink-0 items-center justify-center rounded-lg text-red-600"><Trash2 className="h-4 w-4" aria-hidden="true" /></button>
                  )}
                </div>
                <div className="mt-2 grid grid-cols-2 gap-2">
                  <FotoBoton blobId={x.fotoBloqueo} etiqueta="Candado y tarjeta" onFoto={(f) => void foto(i, 'fotoBloqueo', f)}
                             onQuitar={() => set({ bloqueos: b.bloqueos.map((y, j) => (j === i ? { ...y, fotoBloqueo: undefined } : y)) })} />
                  <FotoBoton blobId={x.fotoCero} etiqueta="Energía cero (medición)" onFoto={(f) => void foto(i, 'fotoCero', f)}
                             onQuitar={() => set({ bloqueos: b.bloqueos.map((y, j) => (j === i ? { ...y, fotoCero: undefined } : y)) })} />
                </div>
              </div>
            ))}
            <button type="button" onClick={() => set({ bloqueos: [...b.bloqueos, { energia: 'electrica', punto: '' }] })}
                    className="min-h-11 w-full rounded-lg border border-dashed border-gray-400 text-sm font-semibold text-gray-700">
              + Otro punto de bloqueo
            </button>
          </div>
        )}
      </section>

      {faltantes.length > 0 && !algunNo && (
        <p className="text-xs text-gray-600">Falta: {faltantes.join(' · ')}</p>
      )}
      {!online && <p className="flex items-center gap-1 text-xs text-amber-700"><WifiOff className="h-3.5 w-3.5" aria-hidden="true" /> Sin señal: todo queda guardado en el teléfono. Para pedir el visto bueno hace falta señal.</p>}
      <button type="button" onClick={enviar} disabled={enviando || algunNo || faltantes.length > 0 || (rechazado && inicio?.client_uuid === b.clientUuid)}
              className="flex min-h-12 w-full items-center justify-center gap-2 rounded-xl bg-blue-600 px-3 text-sm font-bold text-white disabled:opacity-40">
        {enviando ? <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" /> : <ShieldCheck className="h-4 w-4" aria-hidden="true" />} Pedir visto bueno a Hersaly
      </button>
    </div>
  )
}

function EsperandoVistoBueno({ inicio }: { inicio: InicioSeguro }) {
  const [ahora, setAhora] = useState(Date.now())
  useEffect(() => { const t = setInterval(() => setAhora(Date.now()), 1000); return () => clearInterval(t) }, [])
  const seg = Math.max(0, Math.floor((ahora - new Date(inicio.solicitado_at).getTime()) / 1000))
  const mm = String(Math.floor(seg / 60)).padStart(2, '0'), ss = String(seg % 60).padStart(2, '0')
  return (
    <div className="rounded-xl border-2 border-blue-400 bg-blue-50 p-4 text-center" data-testid="inicio-seguro-esperando" role="status">
      <Clock className="mx-auto h-8 w-8 text-blue-600" aria-hidden="true" />
      <p className="mt-2 text-base font-bold text-blue-900">Esperando el visto bueno de Hersaly</p>
      <p className="text-3xl font-bold tabular-nums text-blue-900">{mm}:{ss}</p>
      <p className="mt-2 text-sm font-semibold text-blue-900">NO inicies la tarea todavía.</p>
      <p className="mt-1 text-xs text-blue-800">
        {inicio.escalado_at ? 'Pasaron más de 10 minutos: se avisó también a Manuel.' : `A los ${inicio.minutos_escalamiento ?? 10} minutos se avisa también a Manuel.`}
      </p>
    </div>
  )
}

/** Barra fija mientras se trabaja: «Detener tarea» siempre a mano. */
export function BarraDetener({ inicio, onCambio }: { inicio: InicioSeguro; onCambio: () => void }) {
  const toast = useToast()
  const [abierto, setAbierto] = useState(false)
  const [motivo, setMotivo] = useState('')
  const [enviando, setEnviando] = useState(false)
  const ref = useRef<HTMLDialogElement>(null)
  useEffect(() => { if (abierto) ref.current?.showModal(); else ref.current?.close() }, [abierto])
  async function detener() {
    if (!motivo.trim()) { toast.error('Indica por qué se detiene'); return }
    setEnviando(true)
    try { await detenerInicio(inicio.id, motivo.trim()); toast.warning('Tarea detenida. Se avisó a prevención.'); void pedirCorreo(inicio.id, 'detencion'); setAbierto(false); onCambio() }
    catch (e) { toast.error((e as Error).message) } finally { setEnviando(false) }
  }
  return (
    <>
      <div className="flex items-center gap-2 rounded-xl border border-emerald-300 bg-emerald-50 p-2 text-xs text-emerald-900">
        <ShieldCheck className="h-4 w-4 shrink-0" aria-hidden="true" />
        <span className="min-w-0 flex-1">Visto bueno de {inicio.decidido_por_nombre ?? 'prevención'}{inicio.comentario ? ` · «${inicio.comentario}»` : ''}</span>
        <button type="button" onClick={() => setAbierto(true)}
                className="inline-flex min-h-11 shrink-0 items-center gap-1 rounded-lg bg-red-600 px-3 text-sm font-bold text-white">
          <Hand className="h-4 w-4" aria-hidden="true" /> Detener tarea
        </button>
      </div>
      <dialog ref={ref} onClose={() => setAbierto(false)} className="w-[min(100%-2rem,28rem)] rounded-xl p-0 backdrop:bg-black/50">
        <div className="space-y-3 p-4">
          <p className="text-base font-bold text-red-700">Detener la tarea</p>
          <p className="text-sm text-gray-700">Cualquier persona puede detener si ve un control crítico que falla o una condición insegura.</p>
          <textarea value={motivo} onChange={(e) => setMotivo(e.target.value)} rows={3} 
                    aria-label="Motivo de la detención" placeholder="¿Qué condición viste?…" className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm" />
          <div className="grid grid-cols-2 gap-2">
            <button type="button" onClick={() => setAbierto(false)} className="min-h-11 rounded-lg border border-gray-300 text-sm font-semibold">Cancelar</button>
            <button type="button" onClick={detener} disabled={enviando} className="min-h-11 rounded-lg bg-red-600 text-sm font-bold text-white disabled:opacity-40">
              {enviando ? 'Deteniendo…' : 'Detener'}
            </button>
          </div>
        </div>
      </dialog>
    </>
  )
}

/** Retiro de bloqueos con foto, antes del cierre. Se guarda local y se envía cuando hay señal. */
export function RetiroBloqueos({ inicio, onCambio }: { inicio: InicioSeguro; onCambio: () => void }) {
  const toast = useToast()
  const online = useNetworkStatus()
  const qc = useQueryClient()
  const clave = `inicio-seguro-retiro:${inicio.id}`
  const [fotos, setFotos] = useState<Record<number, string>>(() => leer<RetiroLocal>(clave)?.fotos ?? {})
  const [enviando, setEnviando] = useState(false)
  const completo = inicio.bloqueos.every((_, i) => fotos[i])
  const guardar = (n: Record<number, string>) => {
    setFotos(n); escribir(clave, { id: inicio.id, puntos: inicio.bloqueos.map((x) => x.punto), fotos: n } satisfies RetiroLocal)
  }

  const enviar = useCallback(async () => {
    setEnviando(true)
    try {
      await enviarRetiro({ id: inicio.id, puntos: inicio.bloqueos.map((x) => x.punto), fotos })
      qc.invalidateQueries({ queryKey: ['inicio-seguro', inicio.programacion_id] })
      toast.success('Bloqueos retirados y registrados')
      onCambio()
    } catch (e) { toast.error((e as Error).message) } finally { setEnviando(false) }
  }, [inicio, fotos, qc, toast, onCambio])

  if (inicio.bloqueos.length === 0) return null
  return (
    <section className="rounded-xl border-2 border-gray-300 bg-white p-3" data-testid="retiro-bloqueos">
      <h2 className="flex items-center gap-1.5 text-sm font-bold text-gray-900"><LockOpen className="h-4 w-4" aria-hidden="true" /> Retiro de bloqueos</h2>
      <p className="text-xs text-gray-600">Al terminar, foto de cada punto ya liberado (sin candado ni tarjeta). Es obligatorio para cerrar.</p>
      <div className="mt-2 grid grid-cols-2 gap-2">
        {inicio.bloqueos.map((x, i) => (
          <div key={i}>
            <p className="truncate text-[11px] font-semibold text-gray-700">{x.punto}</p>
            <FotoBoton blobId={fotos[i]} etiqueta="Bloqueo retirado"
                       onFoto={(f) => void guardarFotoLocal(f).then((id) => guardar({ ...fotos, [i]: id }))}
                       onQuitar={() => { const n = { ...fotos }; delete n[i]; guardar(n) }} />
          </div>
        ))}
      </div>
      <button type="button" onClick={enviar} disabled={!completo || enviando || !online}
              className="mt-2 flex min-h-11 w-full items-center justify-center gap-2 rounded-lg bg-gray-900 text-sm font-semibold text-white disabled:opacity-40">
        {enviando ? <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" /> : <CheckCircle2 className="h-4 w-4" aria-hidden="true" />}
        {online ? 'Registrar retiro de bloqueos' : 'Sin señal: se registra cuando haya'}
      </button>
    </section>
  )
}

type RetiroLocal = { id: string; puntos: string[]; fotos: Record<number, string> }

async function enviarRetiro(r: RetiroLocal): Promise<void> {
  const retiro = await Promise.all(r.puntos.map(async (punto, i) => {
    const blob = r.fotos[i] ? await getFotoLocal(r.fotos[i]) : null
    if (!blob) throw new Error('Falta una foto de retiro')
    return { punto, foto_retiro: await subirFotoInicio(blob) }
  }))
  await cerrarInicio(r.id, retiro)
  borrar(`inicio-seguro-retiro:${r.id}`)
}

/** ¿Están las fotos del retiro (aunque falte enviarlas)? Deja cerrar el servicio sin señal. */
export function retiroCapturado(inicio: InicioSeguro): boolean {
  const f = leer<RetiroLocal>(`inicio-seguro-retiro:${inicio.id}`)?.fotos ?? {}
  return inicio.bloqueos.every((_, i) => f[i])
}

/** Envía los retiros que quedaron en el teléfono (servicio cerrado sin señal). Lo llama la lista de servicios. */
export async function enviarRetirosPendientes(): Promise<number> {
  let n = 0
  let claves: string[] = []
  try { claves = Object.keys(localStorage).filter((k) => k.startsWith('inicio-seguro-retiro:')) } catch { return 0 }
  for (const k of claves) {
    const r = leer<RetiroLocal>(k)
    if (!r || !r.puntos.every((_, i) => r.fotos[i])) continue
    try { await enviarRetiro(r); n++ } catch { /* se reintenta la próxima vez */ }
  }
  return n
}
