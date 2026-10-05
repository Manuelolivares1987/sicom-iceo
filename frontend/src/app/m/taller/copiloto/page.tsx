'use client'

// ============================================================================
// Copiloto Técnico — chat de diagnóstico para el mecánico
// 2026-09-08  v1 chat + MIG543 diagnóstico guiado (síntoma → comprobaciones
//             → causa raíz; un caso resuelto se vuelve conocimiento).
// 2026-09-19  v2: respuesta en markdown con citas [Fn] tocables, fuentes con
//             la página del diagrama (visor con zoom), progreso de lo que el
//             copiloto está buscando, códigos de falla al instante (sin IA),
//             ficha técnica del camión, selector de equipo sin OT y dictado
//             por voz (manos sucias). Necesita señal: acá no hay offline.
//             Adjuntos: varias fotos y PDFs desde el teléfono, subidos directo
//             al storage del corpus; un PDF se puede proponer a la biblioteca.
// 2026-10-05  v3 (MIG583): la conversación persiste y se retoma (?c=<id>);
//             historial de hilos; al volver tras horas pregunta cómo terminó;
//             el copiloto anota las comprobaciones que el mecánico informa y
//             PROPONE la solución, que se confirma con un toque; «La falla
//             volvió» reabre el caso dejando la reparación como intento
//             fallido; 👎 con motivo.
// ============================================================================

import { Suspense, useCallback, useEffect, useRef, useState } from 'react'
import Link from 'next/link'
import { useRouter, useSearchParams } from 'next/navigation'
import {
  ArrowLeft, Send, Camera, X, Loader2, WifiOff, Bot, ThumbsUp, ThumbsDown, Sparkles,
  Stethoscope, ClipboardCheck, CheckCircle2, Mic, MicOff, Hash, Search, Truck,
  Paperclip, FileText, AlertCircle, BookPlus, History, MessageSquarePlus,
} from 'lucide-react'
import { Spinner } from '@/components/ui/spinner'
import { Modal, ModalFooter } from '@/components/ui/modal'
import { Button } from '@/components/ui/button'
import { supabase } from '@/lib/supabase'
import { useNetworkStatus } from '@/hooks/use-taller-mecanico'
import {
  getDiagnosticoDeOT, crearDiagnostico, agregarComprobacion, resolverDiagnostico,
  listarConversaciones, cargarConversacion, resolverConversacion, reabrirConversacion,
  cambiarEstadoConversacion, enviarFeedback, SISTEMAS,
} from '@/lib/services/copiloto'
import type {
  EventoCopiloto, FuenteCopiloto, CodigoCopiloto, DiagnosticoCopiloto, PropuestaSolucion, ConversacionCopiloto,
} from '@/lib/copiloto/tipos'
import { describirPausa, necesitaSeguimiento } from '@/lib/copiloto/conversacion'
import {
  RespuestaMarkdown, ListaFuentes, VisorPagina, TarjetasCodigos, FichaEquipoCard, type FichaCliente,
} from '@/components/copiloto/partes'
import {
  HistorialConversaciones, ListaRetomar, TarjetaSeguimiento, TarjetaPropuesta, TarjetaCaso, MotivosNoUtil, ESTADO_CONV,
} from '@/components/copiloto/conversaciones'

type Adjunto = {
  id: string
  nombre: string
  tipo: string
  bytes: number
  preview?: string          // dataURL de la foto (miniatura)
  base64?: string           // respaldo si el storage no está: la 1ª foto va inline
  path?: string             // ruta en el storage del corpus cuando subió
  estado: 'subiendo' | 'listo' | 'error'
  error?: string
  proponer?: boolean        // aporte a la biblioteca del taller (PDF o foto)
}

type Mensaje = {
  rol: 'user' | 'assistant'
  texto: string
  foto?: string
  adjuntos?: { nombre: string; tipo: string; preview?: string | null }[]
  consultaId?: string
  feedback?: 'util' | 'no_util'
  fuentes?: FuenteCopiloto[]
  codigos?: CodigoCopiloto[]
  propuesta?: PropuestaSolucion | null
  fecha?: string
}

const SUGERENCIAS_EQUIPO = [
  'El equipo no parte, ¿por dónde empiezo?',
  '¿Qué diagramas eléctricos tienes de este equipo?',
  '¿Cómo leo los códigos de falla en el tablero?',
  'La PTO no engancha para la bomba',
]
const SUGERENCIAS_GENERAL = [
  '¿Qué fusible controla las luces de trabajo en un Actros?',
  'Explícame SPN 3251 FMI 0',
  'Cómo medir la resistencia de la red CAN',
  'Pérdida de potencia en altura, ¿qué reviso?',
]

const MAX_ADJUNTOS = 6
const MAX_MB = 20

async function comprimirFoto(file: File): Promise<{ dataUrl: string; base64: string }> {
  const bitmap = await createImageBitmap(file)
  const escala = Math.min(1, 1280 / Math.max(bitmap.width, bitmap.height))
  const canvas = document.createElement('canvas')
  canvas.width = Math.round(bitmap.width * escala)
  canvas.height = Math.round(bitmap.height * escala)
  canvas.getContext('2d')!.drawImage(bitmap, 0, 0, canvas.width, canvas.height)
  const dataUrl = canvas.toDataURL('image/jpeg', 0.8)
  return { dataUrl, base64: dataUrl.split(',')[1] }
}

async function token(): Promise<string> {
  const { data: { session } } = await supabase.auth.getSession()
  if (!session?.access_token) throw new Error('Tu sesión expiró. Vuelve a entrar.')
  return session.access_token
}

// Dictado por voz (Web Speech API; Chrome Android y Safari iOS 14.5+)
type Reconocedor = {
  lang: string; interimResults: boolean; continuous: boolean
  onresult: ((e: { results: ArrayLike<ArrayLike<{ transcript: string }>> }) => void) | null
  onend: (() => void) | null; onerror: (() => void) | null
  start: () => void; stop: () => void
}
function crearReconocedor(): Reconocedor | null {
  if (typeof window === 'undefined') return null
  const w = window as unknown as { SpeechRecognition?: new () => Reconocedor; webkitSpeechRecognition?: new () => Reconocedor }
  const C = w.SpeechRecognition ?? w.webkitSpeechRecognition
  if (!C) return null
  const r = new C()
  r.lang = 'es-CL'; r.interimResults = true; r.continuous = false
  return r
}

function urlConversacion(c: { id: string; activo_id: string | null; ot_id: string | null; activo?: { patente: string | null; codigo: string | null } | null }, equipo?: string | null) {
  const p = new URLSearchParams({ c: c.id })
  if (c.ot_id) p.set('ot', c.ot_id)
  if (c.activo_id) p.set('activo', c.activo_id)
  const label = equipo ?? c.activo?.patente ?? c.activo?.codigo
  if (label) p.set('equipo', label)
  return `/m/taller/copiloto?${p.toString()}`
}

function CopilotoInner() {
  const params = useSearchParams()
  const router = useRouter()
  const otId = params.get('ot')
  const activoId = params.get('activo')
  const equipoLabel = params.get('equipo')
  const convParam = params.get('c')
  const online = useNetworkStatus()

  const [mensajes, setMensajes] = useState<Mensaje[]>([])
  const [input, setInput] = useState('')
  const [adjuntos, setAdjuntos] = useState<Adjunto[]>([])
  const [enviando, setEnviando] = useState(false)
  const [estado, setEstado] = useState<string | null>(null)
  const [visor, setVisor] = useState<FuenteCopiloto | null>(null)
  const [citaResaltada, setCitaResaltada] = useState<{ msg: number; n: number } | null>(null)
  const scrollRef = useRef<HTMLDivElement>(null)
  const fileRef = useRef<HTMLInputElement>(null)
  const archivoRef = useRef<HTMLInputElement>(null)
  const inputRef = useRef<HTMLTextAreaElement>(null)
  // Aporte a la biblioteca: foto (etiqueta de fusibles, placa) o PDF con descripción
  const [aporteDe, setAporteDe] = useState<Adjunto | null>(null)
  const [fAporte, setFAporte] = useState('')

  // ── Conversación persistente (MIG583) ─────────────────────────────────────
  const [conv, setConv] = useState<ConversacionCopiloto | null>(null)
  const [cargandoConv, setCargandoConv] = useState(false)
  const [modalHistorial, setModalHistorial] = useState(false)
  const [retomables, setRetomables] = useState<ConversacionCopiloto[]>([])
  const [seguimiento, setSeguimiento] = useState(false)
  const [modalVolvio, setModalVolvio] = useState(false)
  const [fMotivoVolvio, setFMotivoVolvio] = useState('')
  const [motivoDe, setMotivoDe] = useState<number | null>(null)   // índice del mensaje con 👎 pendiente de motivo
  const convRef = useRef<ConversacionCopiloto | null>(null)
  convRef.current = conv
  // «Nueva conversación» desde una OT: no volver a retomar la última de esa OT
  const nuevaRef = useRef(false)

  // ── Ficha técnica y selector de equipo ────────────────────────────────────
  const [ficha, setFicha] = useState<FichaCliente | null>(null)
  const [modalEquipo, setModalEquipo] = useState(false)
  const [busqEquipo, setBusqEquipo] = useState('')
  const [equipos, setEquipos] = useState<{ id: string; patente: string | null; codigo: string | null; nombre: string | null }[]>([])

  // ── Códigos de falla directos ─────────────────────────────────────────────
  const [modalCodigo, setModalCodigo] = useState(false)
  const [fCodigo, setFCodigo] = useState('')
  const [codigosRes, setCodigosRes] = useState<CodigoCopiloto[] | null>(null)
  const [buscandoCodigo, setBuscandoCodigo] = useState(false)
  const [errorCodigo, setErrorCodigo] = useState<string | null>(null)

  // ── Voz ───────────────────────────────────────────────────────────────────
  const [escuchando, setEscuchando] = useState(false)
  const [vozDisponible, setVozDisponible] = useState(false)
  const recRef = useRef<Reconocedor | null>(null)
  useEffect(() => { setVozDisponible(!!crearReconocedor()) }, [])

  // ── Caso (MIG543 + MIG583) ────────────────────────────────────────────────
  const [dx, setDx] = useState<DiagnosticoCopiloto | null>(null)
  const [dxAbierto, setDxAbierto] = useState(true)
  const [modalSintoma, setModalSintoma] = useState(false)
  const [modalComprobacion, setModalComprobacion] = useState(false)
  const [modalCausa, setModalCausa] = useState(false)
  const [guardando, setGuardando] = useState(false)
  const [fSintoma, setFSintoma] = useState('')
  const [fSistema, setFSistema] = useState('')
  const [fDesc, setFDesc] = useState('')
  const [fResultado, setFResultado] = useState<'ok' | 'no_ok' | 'valor'>('no_ok')
  const [fValor, setFValor] = useState('')
  const [fCausa, setFCausa] = useState('')
  const [fReparacion, setFReparacion] = useState('')

  // Cargar un hilo guardado (?c=) o, desde una OT, el último hilo de esa OT
  useEffect(() => {
    let cancelado = false
    async function cargar() {
      let id = convParam
      if (!id && otId && !nuevaRef.current) {
        try {
          const lista = await listarConversaciones({ otId, limit: 1 })
          if (lista[0]) id = lista[0].id
        } catch { /* sin señal */ }
      }
      nuevaRef.current = false
      if (!id) {
        setConv(null); setMensajes([]); setSeguimiento(false)
        if (otId) getDiagnosticoDeOT(otId).then((d) => { if (!cancelado) setDx(d as DiagnosticoCopiloto | null) }).catch(() => { /* sin señal */ })
        else setDx(null)
        return
      }
      if (convRef.current?.id === id) return
      setCargandoConv(true)
      try {
        const r = await cargarConversacion(id)
        if (cancelado) return
        setConv(r.conversacion)
        setDx(r.diagnostico)
        setMensajes(r.mensajes.flatMap((m): Mensaje[] => [
          { rol: 'user', texto: m.pregunta, adjuntos: m.adjuntos, fecha: m.created_at },
          ...(m.respuesta ? [{
            rol: 'assistant' as const, texto: m.respuesta, consultaId: m.consultaId,
            feedback: m.feedback ?? undefined, fuentes: m.fuentes, codigos: m.codigos, fecha: m.created_at,
          }] : [{
            rol: 'assistant' as const, texto: '⚠️ Esta respuesta no alcanzó a guardarse (se cortó la señal). Vuelve a preguntar.',
            fecha: m.created_at,
          }]),
        ]))
        setSeguimiento(necesitaSeguimiento(r.conversacion))
        if (!convParam) router.replace(urlConversacion(r.conversacion, equipoLabel))
      } catch (e) {
        if (!cancelado) setMensajes([{ rol: 'assistant', texto: `⚠️ ${e instanceof Error ? e.message : 'No se pudo cargar la conversación.'}` }])
      } finally { if (!cancelado) setCargandoConv(false) }
    }
    cargar()
    return () => { cancelado = true }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [convParam, otId])

  // Hilos para retomar en la pantalla vacía (los de este equipo, o los abiertos)
  useEffect(() => {
    if (convParam || mensajes.length) return
    listarConversaciones({ activoId: activoId ?? undefined, estado: activoId ? undefined : 'abierta', limit: 3 })
      .then(setRetomables).catch(() => setRetomables([]))
  }, [activoId, convParam, mensajes.length])

  useEffect(() => {
    setFicha(null)
    if (!activoId) return
    token()
      .then((t) => fetch(`/api/copiloto/ficha?activo=${activoId}`, { headers: { Authorization: `Bearer ${t}` } }))
      .then((r) => (r.ok ? r.json() : null))
      .then((j) => setFicha(j?.ficha ?? null))
      .catch(() => { /* la ficha es opcional */ })
  }, [activoId])

  useEffect(() => {
    scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight, behavior: 'smooth' })
  }, [mensajes, enviando])

  // Búsqueda de equipos por patente/código (RLS de SICOM filtra lo visible)
  useEffect(() => {
    if (!modalEquipo) return
    const q = busqEquipo.trim()
    const h = setTimeout(async () => {
      let query = supabase.from('activos').select('id, patente, codigo, nombre').limit(15)
      if (q) query = query.or(`patente.ilike.%${q.replace(/[%,()]/g, '')}%,codigo.ilike.%${q.replace(/[%,()]/g, '')}%,nombre.ilike.%${q.replace(/[%,()]/g, '')}%`)
      const { data } = await query.order('patente', { ascending: true })
      setEquipos((data ?? []) as typeof equipos)
    }, 250)
    return () => clearTimeout(h)
  }, [busqEquipo, modalEquipo])

  function elegirEquipo(e: { id: string; patente: string | null; codigo: string | null }) {
    setModalEquipo(false)
    nuevaConversacion(`/m/taller/copiloto?activo=${e.id}&equipo=${encodeURIComponent(e.patente ?? e.codigo ?? '')}`)
  }

  function nuevaConversacion(url?: string) {
    nuevaRef.current = true
    setMensajes([]); setConv(null); setDx(null); setSeguimiento(false); setAdjuntos([])
    const p = new URLSearchParams()
    if (otId) p.set('ot', otId)
    if (activoId) p.set('activo', activoId)
    if (equipoLabel) p.set('equipo', equipoLabel)
    router.replace(url ?? `/m/taller/copiloto${p.toString() ? `?${p}` : ''}`)
  }

  function abrirConversacion(c: ConversacionCopiloto) {
    setModalHistorial(false)
    if (c.id === conv?.id) return
    setMensajes([]); setConv(null); setDx(null); setSeguimiento(false)
    router.replace(urlConversacion(c))
  }

  const actualizarUltimo = useCallback((fn: (m: Mensaje) => Mensaje) => {
    setMensajes((p) => {
      const copia = [...p]
      copia[copia.length - 1] = fn(copia[copia.length - 1])
      return copia
    })
  }, [])

  async function enviar(texto?: string) {
    const pregunta = (texto ?? input).trim()
    // Los adjuntos solo viajan cuando el usuario envía (no en sugerencias ni
    // mensajes automáticos del diagnóstico)
    const usarAdjuntos = texto === undefined
    const listos = usarAdjuntos ? adjuntos.filter((a) => a.estado === 'listo') : []
    if ((!pregunta && !listos.length) || enviando) return
    if (usarAdjuntos && adjuntos.some((a) => a.estado === 'subiendo')) return

    const subidos = listos.filter((a) => a.path)
    // Respaldo: sin storage, la primera foto viaja inline como antes
    const inline = listos.find((a) => !a.path && a.base64)
    if (usarAdjuntos) setAdjuntos([])
    setInput(''); setEnviando(true); setEstado('Revisando manuales, casos e historial…'); setSeguimiento(false)
    const historial = mensajes.map((m) => ({ rol: m.rol, texto: m.texto }))
    setMensajes((p) => [...p, {
      rol: 'user',
      texto: pregunta || (listos.length ? `(${listos.length} adjunto${listos.length > 1 ? 's' : ''})` : ''),
      adjuntos: listos.map((a) => ({ nombre: a.nombre, tipo: a.tipo, preview: a.preview })),
    }])

    try {
      const res = await fetch('/api/copiloto/consulta', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${await token()}` },
        body: JSON.stringify({
          pregunta,
          conversacionId: convRef.current?.id,
          activoId: activoId || undefined,
          otId: otId || undefined,
          diagnosticoId: dx?.estado === 'abierto' ? dx.id : undefined,
          historial: historial.slice(-6),
          fotoBase64: inline?.base64,
          fotoTipo: 'image/jpeg',
          adjuntos: subidos.map((a) => ({ path: a.path, tipo: a.tipo, nombre: a.nombre })),
          formato: 'ndjson',
        }),
      })
      if (!res.ok) {
        const j = await res.json().catch(() => null)
        throw new Error(j?.error ?? `Error ${res.status}`)
      }

      const consultaId = res.headers.get('X-Copiloto-Id') ?? undefined
      setMensajes((p) => [...p, { rol: 'assistant', texto: '', consultaId }])

      const reader = res.body!.getReader()
      const decoder = new TextDecoder()
      let buffer = ''
      const procesar = (linea: string) => {
        if (!linea.trim()) return
        let ev: EventoCopiloto
        try { ev = JSON.parse(linea) } catch { return }
        if (ev.t === 'texto') { setEstado(null); actualizarUltimo((m) => ({ ...m, texto: m.texto + ev.d })) }
        else if (ev.t === 'estado') setEstado(ev.d)
        else if (ev.t === 'fuentes') actualizarUltimo((m) => ({ ...m, fuentes: ev.d }))
        else if (ev.t === 'codigos') actualizarUltimo((m) => ({ ...m, codigos: ev.d }))
        else if (ev.t === 'diagnostico') setDx(ev.d)
        else if (ev.t === 'propuesta') actualizarUltimo((m) => ({ ...m, propuesta: ev.d }))
        else if (ev.t === 'conversacion') {
          if (!convRef.current) {
            const nueva: ConversacionCopiloto = {
              id: ev.id, titulo: ev.titulo, usuario_id: '', activo_id: activoId, ot_id: otId, diagnostico_id: null,
              estado: 'abierta', mensajes: 1, ultimo_at: new Date().toISOString(), created_at: new Date().toISOString(),
            }
            setConv(nueva)
            // La URL lleva el hilo: al recargar o volver, se retoma
            window.history.replaceState(null, '', urlConversacion(nueva, equipoLabel))
          }
        }
      }
      for (;;) {
        const { done, value } = await reader.read()
        if (done) break
        buffer += decoder.decode(value, { stream: true })
        const lineas = buffer.split('\n')
        buffer = lineas.pop() ?? ''
        lineas.forEach(procesar)
      }
      procesar(buffer)
    } catch (err) {
      setMensajes((p) => [...p, {
        rol: 'assistant',
        texto: `⚠️ ${err instanceof Error ? err.message : 'No se pudo consultar. Revisa la señal e intenta de nuevo.'}`,
      }])
    } finally {
      setEnviando(false); setEstado(null)
    }
  }

  async function marcarFeedback(idx: number, fb: 'util' | 'no_util', nota?: string) {
    const m = mensajes[idx]
    if (!m.consultaId || (m.feedback && !nota)) return
    setMensajes((p) => p.map((x, i) => (i === idx ? { ...x, feedback: fb } : x)))
    setMotivoDe(fb === 'no_util' && !nota ? idx : null)
    try { await enviarFeedback(m.consultaId, fb, nota) }
    catch { /* el feedback no puede botar el chat */ }
  }

  // Sube cada archivo al storage del corpus con URL firmada (directo desde el
  // teléfono: Netlify corta requests de más de ~6 MB). Las fotos se comprimen.
  async function subirArchivo(file: File) {
    const id = `${Date.now()}-${Math.random().toString(36).slice(2)}`
    const esPdf = file.type === 'application/pdf' || /\.pdf$/i.test(file.name)
    const esImagen = file.type.startsWith('image/')
    const actualizar = (patch: Partial<Adjunto>) =>
      setAdjuntos((p) => p.map((a) => (a.id === id ? { ...a, ...patch } : a)))

    if (!esPdf && !esImagen) {
      setAdjuntos((p) => [...p, { id, nombre: file.name, tipo: file.type, bytes: file.size, estado: 'error',
        error: 'Solo fotos o PDF' }])
      return
    }
    if (file.size > MAX_MB * 1024 * 1024 && esPdf) {
      setAdjuntos((p) => [...p, { id, nombre: file.name, tipo: file.type, bytes: file.size, estado: 'error',
        error: `Supera ${MAX_MB} MB` }])
      return
    }

    let blob: Blob = file
    let tipo = esPdf ? 'application/pdf' : file.type
    let preview: string | undefined
    let base64: string | undefined
    if (esImagen) {
      try {
        const c = await comprimirFoto(file)
        preview = c.dataUrl; base64 = c.base64; tipo = 'image/jpeg'
        blob = await (await fetch(c.dataUrl)).blob()
      } catch {
        setAdjuntos((p) => [...p, { id, nombre: file.name, tipo: file.type, bytes: file.size, estado: 'error',
          error: 'Foto ilegible' }])
        return
      }
    }
    const nombre = esImagen && /^image\.|^IMG_|^\d+\./i.test(file.name) ? `foto-${new Date().toLocaleTimeString('es-CL')}.jpg` : file.name
    setAdjuntos((p) => [...p, { id, nombre, tipo, bytes: blob.size, preview, base64, estado: 'subiendo' }])

    try {
      const res = await fetch('/api/copiloto/adjunto', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${await token()}` },
        body: JSON.stringify({ nombre, tipo, bytes: blob.size, activoId: activoId || undefined }),
      })
      const j = await res.json().catch(() => null)
      if (!res.ok) throw new Error(j?.error ?? `Error ${res.status}`)
      // Mismo formato que storage-js uploadToSignedUrl
      const form = new FormData()
      form.append('cacheControl', '3600')
      form.append('', blob, nombre)
      const up = await fetch(j.uploadUrl, { method: 'PUT', body: form, headers: { 'x-upsert': 'false' } })
      if (!up.ok) throw new Error('No se pudo subir')
      actualizar({ estado: 'listo', path: j.path, base64: undefined })
    } catch (e) {
      // Sin storage: la foto igual sirve inline (como antes); el PDF no
      if (esImagen && base64) actualizar({ estado: 'listo' })
      else actualizar({ estado: 'error', error: e instanceof Error ? e.message : 'Error al subir' })
    }
  }

  async function onArchivos(e: React.ChangeEvent<HTMLInputElement>) {
    const files = Array.from(e.target.files ?? [])
    e.target.value = ''
    const cupo = MAX_ADJUNTOS - adjuntos.length
    for (const f of files.slice(0, Math.max(0, cupo))) void subirArchivo(f)
  }

  async function guardarAporte(a: Adjunto, proponer: boolean, descripcion?: string) {
    if (!a.path) return
    setAdjuntos((p) => p.map((x) => (x.id === a.id ? { ...x, proponer } : x)))
    try {
      await fetch('/api/copiloto/adjunto', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${await token()}` },
        body: JSON.stringify({ path: a.path, proponer, descripcion }),
      })
    } catch { /* no bloquea el chat */ }
  }

  function toggleVoz() {
    if (escuchando) { recRef.current?.stop(); return }
    const r = crearReconocedor()
    if (!r) return
    const base = input ? input.trimEnd() + ' ' : ''
    r.onresult = (e) => {
      const t = Array.from(e.results).map((x) => x[0]?.transcript ?? '').join('')
      setInput(base + t)
    }
    r.onend = () => setEscuchando(false)
    r.onerror = () => setEscuchando(false)
    recRef.current = r
    setEscuchando(true)
    r.start()
  }

  function onCita(msgIdx: number, n: number) {
    const f = mensajes[msgIdx]?.fuentes?.find((x) => x.n === n)
    if (f?.imagen) { setVisor(f); return }
    setCitaResaltada({ msg: msgIdx, n })
    document.getElementById(`m${msgIdx}-fuente-${n}`)?.scrollIntoView({ behavior: 'smooth', block: 'center' })
  }

  async function buscarCodigoDirecto() {
    const t = fCodigo.trim()
    if (t.length < 2 || buscandoCodigo) return
    setBuscandoCodigo(true); setErrorCodigo(null); setCodigosRes(null)
    try {
      const res = await fetch('/api/copiloto/codigo', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${await token()}` },
        body: JSON.stringify({ texto: t, activoId: activoId || undefined }),
      })
      const j = await res.json()
      if (!res.ok) throw new Error(j?.error ?? `Error ${res.status}`)
      setCodigosRes(j.codigos ?? [])
    } catch (e) {
      setErrorCodigo(e instanceof Error ? e.message : 'No se pudo buscar')
    } finally { setBuscandoCodigo(false) }
  }

  // ── Acciones del caso ─────────────────────────────────────────────────────
  async function iniciarDx() {
    if (!activoId || fSintoma.trim().length < 5 || guardando) return
    setGuardando(true)
    try {
      const nuevo = await crearDiagnostico({ otId, activoId, sintoma: fSintoma, sistema: fSistema || null })
      setDx(nuevo as unknown as DiagnosticoCopiloto)
      setModalSintoma(false)
      // El síntoma parte la conversación: el copiloto responde ya en modo guiado
      await enviar(`Diagnóstico iniciado. Síntoma: ${fSintoma.trim()}. ¿Por dónde parto?`)
      setFSintoma('')
    } catch (e) {
      alert(e instanceof Error ? e.message : 'No se pudo iniciar el diagnóstico')
    } finally { setGuardando(false) }
  }

  async function registrarComprobacion() {
    if (!dx || fDesc.trim().length < 3 || guardando) return
    if (fResultado === 'valor' && !fValor.trim()) return
    setGuardando(true)
    try {
      const comprobaciones = await agregarComprobacion(dx.id, fDesc, fResultado, fValor || undefined)
      setDx({ ...dx, comprobaciones: comprobaciones as DiagnosticoCopiloto['comprobaciones'] })
      setModalComprobacion(false)
      const resumen = `Registré la comprobación: ${fDesc.trim()} → ${
        fResultado === 'valor' ? fValor.trim() : fResultado === 'ok' ? 'OK' : 'NO OK'}. ¿Siguiente paso?`
      setFDesc(''); setFValor('')
      await enviar(resumen)
    } catch (e) {
      alert(e instanceof Error ? e.message : 'No se pudo registrar')
    } finally { setGuardando(false) }
  }

  // Abre el modal de solución, con la propuesta del copiloto si la hay
  function abrirSolucion(prop?: PropuestaSolucion | null) {
    setFCausa(prop?.causa_raiz ?? ''); setFReparacion(prop?.reparacion ?? '')
    setFSistema(prop?.sistema ?? dx?.sistema ?? '')
    setFSintoma(prop?.sintoma ?? dx?.sintoma ?? conv?.titulo ?? '')
    setModalCausa(true)
  }

  async function guardarSolucion() {
    if (fCausa.trim().length < 5 || fReparacion.trim().length < 5 || guardando) return
    setGuardando(true)
    try {
      let leccion: string | null = null
      if (conv) {
        const r = await resolverConversacion({
          conversacionId: conv.id, causa: fCausa, reparacion: fReparacion,
          sistema: fSistema || null, sintoma: fSintoma || null,
        })
        leccion = r.leccion
        if (r.diagnostico) setDx(r.diagnostico)
        setConv({ ...conv, estado: 'resuelta', diagnostico_id: r.diagnosticoId })
      } else if (dx) {
        // Sin conversación guardada (PWA vieja): el camino de MIG543
        await resolverDiagnostico(dx.id, fCausa, fReparacion, fSistema || dx.sistema)
        setDx({ ...dx, estado: 'resuelto', causa_raiz: fCausa.trim(), reparacion: fReparacion.trim() || null })
      }
      setModalCausa(false)
      const cierre: Mensaje = {
        rol: 'assistant',
        texto: `✅ Caso guardado. Causa: **${fCausa.trim()}**. Solución: **${fReparacion.trim()}**.`
          + (leccion ? `\n\n**Lo que aprendí para la próxima:** ${leccion.split('\nPalabras clave:')[0]}` : '')
          + '\n\nLa próxima vez que un equipo como este falle parecido, parto por aquí. Buen trabajo.',
      }
      setMensajes((p) => [...p.map((m): Mensaje => ({ ...m, propuesta: null })), cierre])
      setFCausa(''); setFReparacion('')
    } catch (e) {
      alert(e instanceof Error ? e.message : 'No se pudo guardar la solución')
    } finally { setGuardando(false) }
  }

  async function confirmarVolvio() {
    if (!conv || guardando) return
    setGuardando(true)
    try {
      await reabrirConversacion(conv.id, fMotivoVolvio.trim() || undefined)
      setConv({ ...conv, estado: 'abierta' })
      setDx(dx ? { ...dx, estado: 'abierto', causa_raiz: null, reparacion: null, leccion: null, validado_at: null, reaperturas: dx.reaperturas + 1 } : dx)
      setModalVolvio(false)
      const motivo = fMotivoVolvio.trim()
      setFMotivoVolvio('')
      await enviar(`La falla volvió después de la reparación${motivo ? `: ${motivo}` : ''}. ¿Qué reviso ahora?`)
      // El caso real (con la reparación fallida en la bitácora) llega al recargar
      try { const r = await cargarConversacion(conv.id); setDx(r.diagnostico) } catch { /* opcional */ }
    } catch (e) {
      alert(e instanceof Error ? e.message : 'No se pudo reabrir')
    } finally { setGuardando(false) }
  }

  async function marcarSoloConsulta() {
    if (!conv) return
    setSeguimiento(false)
    try { await cambiarEstadoConversacion(conv.id, 'descartada'); setConv({ ...conv, estado: 'descartada' }) } catch { /* opcional */ }
  }

  const sugerencias = activoId ? SUGERENCIAS_EQUIPO : SUGERENCIAS_GENERAL
  const estadoConv = conv ? (ESTADO_CONV[conv.estado] ?? ESTADO_CONV.abierta) : null
  const hayRespuesta = mensajes.some((m) => m.rol === 'assistant' && m.consultaId)

  return (
    <div className="flex h-dvh flex-col bg-gray-50">
      {/* Header */}
      <header className="flex items-center gap-2 border-b bg-white px-3 py-3">
        <Link href={otId ? `/m/taller/ot/${otId}` : '/m/taller'} className="text-gray-500">
          <ArrowLeft className="h-5 w-5" />
        </Link>
        <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-indigo-100">
          <Bot className="h-5 w-5 text-indigo-600" />
        </div>
        <div className="min-w-0 flex-1">
          <h1 className="flex items-center gap-1.5 text-sm font-bold text-gray-900">
            <span className="truncate">{conv ? conv.titulo : 'Copiloto Técnico'}</span>
            {estadoConv && <span className={`shrink-0 rounded-full px-1.5 py-0.5 text-[9.5px] font-semibold ${estadoConv.c}`}>{estadoConv.t}</span>}
          </h1>
          {otId ? (
            <p className="truncate text-[11px] text-gray-500">{equipoLabel ? `Equipo ${equipoLabel}` : 'Diagnóstico con manuales de la flota'}</p>
          ) : (
            <button onClick={() => setModalEquipo(true)} className="flex max-w-full items-center gap-1 truncate text-[11px] font-semibold text-indigo-600">
              <Truck className="h-3 w-3 shrink-0" />
              {equipoLabel ? `Equipo ${equipoLabel} · cambiar` : 'Elegir equipo (opcional)'}
            </button>
          )}
        </div>
        {!online && (
          <span className="flex items-center gap-1 rounded-full bg-amber-100 px-2 py-1 text-[10px] font-semibold text-amber-700">
            <WifiOff className="h-3 w-3" /> Sin señal
          </span>
        )}
        <button onClick={() => setModalHistorial(true)} aria-label="Mis conversaciones" title="Mis conversaciones"
                className="rounded-xl border border-gray-200 p-2 text-gray-500">
          <History className="h-5 w-5" />
        </button>
        {mensajes.length > 0 && (
          <button onClick={() => nuevaConversacion()} aria-label="Nueva conversación" title="Nueva conversación"
                  className="rounded-xl border border-gray-200 p-2 text-gray-500">
            <MessageSquarePlus className="h-5 w-5" />
          </button>
        )}
      </header>

      {/* Ficha + caso */}
      {(ficha || dx || (otId && activoId)) && (
        <div className="space-y-2 border-b bg-white px-3 py-2">
          {ficha && <FichaEquipoCard ficha={ficha} />}
          {otId && activoId && !dx && (
            <button onClick={() => setModalSintoma(true)} disabled={!online}
                    className="flex w-full items-center justify-center gap-2 rounded-xl border-2 border-dashed border-indigo-300 bg-indigo-50 px-3 py-2.5 text-sm font-semibold text-indigo-700 disabled:opacity-50">
              <Stethoscope className="h-4 w-4" /> Iniciar diagnóstico guiado
            </button>
          )}
          {dx && (
            <TarjetaCaso dx={dx} abierto={dxAbierto} onToggle={() => setDxAbierto((v) => !v)}
                         onSolucion={() => abrirSolucion()} onVolvio={() => setModalVolvio(true)} online={online} />
          )}
          {dx && dx.estado === 'abierto' && dxAbierto && (
            <button onClick={() => setModalComprobacion(true)} disabled={!online}
                    className="flex w-full items-center justify-center gap-1 rounded-lg border border-indigo-200 bg-white px-2 py-1.5 text-[11px] font-semibold text-indigo-700 disabled:opacity-50">
              <ClipboardCheck className="h-3.5 w-3.5" /> Anotar una comprobación a mano
            </button>
          )}
        </div>
      )}

      {/* Chat */}
      <div ref={scrollRef} className="flex-1 space-y-3 overflow-y-auto px-3 py-4">
        {cargandoConv && (
          <p className="flex items-center justify-center gap-2 py-6 text-xs text-gray-400"><Loader2 className="h-4 w-4 animate-spin" /> Cargando la conversación…</p>
        )}
        {!cargandoConv && mensajes.length === 0 && (
          <div className="mx-auto mt-6 max-w-sm text-center">
            <Sparkles className="mx-auto h-8 w-8 text-indigo-400" />
            <p className="mt-2 text-sm font-semibold text-gray-800">¿Qué le pasa al equipo?</p>
            <p className="mt-1 text-xs text-gray-500">
              Describe el síntoma, dicta con el micrófono, manda fotos o un PDF (informe del escáner, manual) o busca un código de falla.
              Respondo con los manuales y diagramas de la flota, los casos ya resueltos y el historial
              {equipoLabel ? ` del ${equipoLabel}` : ' del equipo'}, citando la fuente. Si no está en la biblioteca, lo busco en la web.
              La conversación queda guardada: puedes volver después y contarme cómo terminó.
            </p>
            <div className="mt-4 space-y-2">
              {sugerencias.map((s) => (
                <button key={s} onClick={() => enviar(s)} disabled={!online || enviando}
                        className="block w-full rounded-xl border border-indigo-200 bg-white px-3 py-2 text-left text-xs text-indigo-700 disabled:opacity-50">
                  {s}
                </button>
              ))}
              <button onClick={() => setModalCodigo(true)}
                      className="flex w-full items-center justify-center gap-1.5 rounded-xl border border-orange-200 bg-orange-50 px-3 py-2 text-xs font-semibold text-orange-700">
                <Hash className="h-3.5 w-3.5" /> Buscar un código de falla
              </button>
            </div>
            <ListaRetomar conversaciones={retomables} onElegir={abrirConversacion} onVerTodas={() => setModalHistorial(true)} />
          </div>
        )}

        {mensajes.map((m, i) => {
          const ultimo = i === mensajes.length - 1
          return (
            <div key={i} className={`flex ${m.rol === 'user' ? 'justify-end' : 'justify-start'}`}>
              <div className={`max-w-[92%] rounded-2xl px-3 py-2 text-sm ${
                m.rol === 'user' ? 'max-w-[85%] rounded-br-sm bg-indigo-600 text-white' : 'rounded-bl-sm border bg-white text-gray-800'}`}>
                {m.foto && (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img src={m.foto} alt="foto enviada" className="mb-2 max-h-40 rounded-lg" />
                )}
                {m.adjuntos && m.adjuntos.length > 0 && (
                  <div className="mb-1.5 flex flex-wrap gap-1.5">
                    {m.adjuntos.map((a, k) => a.preview ? (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img key={k} src={a.preview} alt={a.nombre} className="h-20 w-20 rounded-lg object-cover" />
                    ) : (
                      <span key={k} className="flex max-w-[180px] items-center gap-1 rounded-lg bg-white/20 px-2 py-1 text-[11px]">
                        <FileText className="h-3.5 w-3.5 shrink-0" /> <span className="truncate">{a.nombre}</span>
                      </span>
                    ))}
                  </div>
                )}
                {m.rol === 'user' ? (
                  <div className="whitespace-pre-wrap">{m.texto}</div>
                ) : (
                  <>
                    {m.codigos && m.codigos.length > 0 && (
                      <div className="mb-2"><TarjetasCodigos codigos={m.codigos} /></div>
                    )}
                    {m.texto
                      ? <RespuestaMarkdown texto={m.texto} onCita={(n) => onCita(i, n)} />
                      : (enviando && ultimo ? <span className="text-gray-400">…</span> : null)}
                    {enviando && ultimo && estado && m.texto && (
                      <p className="mt-1 flex items-center gap-1.5 text-[11px] text-gray-400">
                        <Loader2 className="h-3 w-3 animate-spin" /> {estado}
                      </p>
                    )}
                    {m.fuentes && m.fuentes.length > 0 && (
                      <div>
                        <ListaFuentes
                          fuentes={m.fuentes.map((f) => ({ ...f }))}
                          resaltada={citaResaltada?.msg === i ? citaResaltada.n : null}
                          onVer={setVisor}
                        />
                        {/* anclas para el scroll desde las citas */}
                        {m.fuentes.map((f) => <span key={f.n} id={`m${i}-fuente-${f.n}`} />)}
                      </div>
                    )}
                    {m.propuesta && (!enviando || !ultimo) && (
                      <TarjetaPropuesta propuesta={m.propuesta} onRevisar={() => abrirSolucion(m.propuesta)}
                                        onDescartar={() => setMensajes((p) => p.map((x, k) => (k === i ? { ...x, propuesta: null } : x)))} />
                    )}
                  </>
                )}
                {m.rol === 'assistant' && m.consultaId && m.texto && (!enviando || !ultimo) && (
                  <div className="mt-2 border-t pt-1.5">
                    <div className="flex items-center gap-2">
                      <span className="text-[10px] text-gray-400">¿Te sirvió?</span>
                      <button onClick={() => marcarFeedback(i, 'util')}
                              className={`rounded p-1 ${m.feedback === 'util' ? 'bg-green-100 text-green-600' : 'text-gray-400'}`}>
                        <ThumbsUp className="h-3.5 w-3.5" />
                      </button>
                      <button onClick={() => marcarFeedback(i, 'no_util')}
                              className={`rounded p-1 ${m.feedback === 'no_util' ? 'bg-red-100 text-red-600' : 'text-gray-400'}`}>
                        <ThumbsDown className="h-3.5 w-3.5" />
                      </button>
                      {m.fecha && <span className="ml-auto text-[10px] text-gray-300">{m.fecha.slice(5, 16).replace('T', ' ')}</span>}
                    </div>
                    {motivoDe === i && <MotivosNoUtil onElegir={(mot) => marcarFeedback(i, 'no_util', mot)} />}
                  </div>
                )}
              </div>
            </div>
          )
        })}

        {enviando && (mensajes[mensajes.length - 1]?.rol === 'user' || !mensajes[mensajes.length - 1]?.texto) && (
          <div className="flex justify-start">
            <div className="flex items-center gap-2 rounded-2xl rounded-bl-sm border bg-white px-3 py-2 text-xs text-gray-500">
              <Loader2 className="h-3.5 w-3.5 animate-spin" /> {estado ?? 'Revisando manuales, casos e historial…'}
            </div>
          </div>
        )}

        {seguimiento && conv && !enviando && (
          <TarjetaSeguimiento titulo={conv.titulo} pausa={describirPausa(conv.ultimo_at)}
                              onResuelto={() => { setSeguimiento(false); abrirSolucion() }}
                              onSigue={() => { setSeguimiento(false); setInput('Sigue fallando. '); inputRef.current?.focus() }}
                              onConsulta={marcarSoloConsulta} />
        )}
      </div>

      {/* Cierre siempre a mano cuando ya hubo diálogo y no hay caso resuelto */}
      {conv && conv.estado !== 'resuelta' && hayRespuesta && !dx && !enviando && (
        <div className="border-t bg-white px-3 py-1.5">
          <button onClick={() => abrirSolucion()} disabled={!online}
                  className="flex w-full items-center justify-center gap-1 rounded-lg border border-green-300 bg-green-50 px-2 py-1.5 text-[11.5px] font-semibold text-green-800 disabled:opacity-50">
            <CheckCircle2 className="h-3.5 w-3.5" /> ¿Quedó resuelto? Registrar la solución definitiva
          </button>
        </div>
      )}

      <p className="border-t bg-amber-50 px-3 py-1 text-center text-[10px] text-amber-700">
        Apoyo al diagnóstico — los trabajos de riesgo se validan con el jefe de taller.
      </p>

      {/* Input */}
      <div className="border-t bg-white p-3 pb-[max(12px,env(safe-area-inset-bottom))]">
        {adjuntos.length > 0 && (
          <div className="-mx-1 mb-2 flex gap-2 overflow-x-auto px-1 pb-1">
            {adjuntos.map((a) => (
              <div key={a.id} className={`relative shrink-0 rounded-lg border ${a.estado === 'error' ? 'border-red-300 bg-red-50' : 'border-gray-200 bg-gray-50'}`}>
                {a.preview ? (
                  <div className="relative">
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img src={a.preview} alt={a.nombre} className="h-14 w-14 rounded-lg object-cover" />
                    {a.estado === 'listo' && a.path && (
                      <button onClick={() => (a.proponer ? guardarAporte(a, false) : (setFAporte(''), setAporteDe(a)))}
                              aria-label="Aportar a biblioteca" title="Aportar a biblioteca"
                              className={`absolute bottom-0.5 left-0.5 rounded p-0.5 text-white ${a.proponer ? 'bg-green-600' : 'bg-black/60'}`}>
                        <BookPlus className="h-3 w-3" />
                      </button>
                    )}
                  </div>
                ) : (
                  <div className="flex h-14 w-36 flex-col justify-center px-2">
                    <p className="flex items-center gap-1 truncate text-[11px] font-semibold text-gray-700">
                      <FileText className="h-3.5 w-3.5 shrink-0 text-red-500" /> <span className="truncate">{a.nombre}</span>
                    </p>
                    {a.estado === 'listo' && a.path && (
                      <button onClick={() => (a.proponer ? guardarAporte(a, false) : (setFAporte(''), setAporteDe(a)))}
                              className={`mt-0.5 flex items-center gap-0.5 text-[10px] font-semibold ${a.proponer ? 'text-green-600' : 'text-indigo-600'}`}>
                        <BookPlus className="h-3 w-3" /> {a.proponer ? 'Aportado a biblioteca ✓' : 'Aportar a biblioteca'}
                      </button>
                    )}
                    {a.estado === 'error' && <p className="text-[10px] text-red-600">{a.error}</p>}
                  </div>
                )}
                {a.estado === 'subiendo' && (
                  <div className="absolute inset-0 flex items-center justify-center rounded-lg bg-white/70">
                    <Loader2 className="h-4 w-4 animate-spin text-indigo-600" />
                  </div>
                )}
                {a.estado === 'error' && a.preview && (
                  <div className="absolute inset-0 flex items-center justify-center rounded-lg bg-red-50/80" title={a.error}>
                    <AlertCircle className="h-4 w-4 text-red-600" />
                  </div>
                )}
                <button onClick={() => setAdjuntos((p) => p.filter((x) => x.id !== a.id))} aria-label="Quitar"
                        className="absolute -right-1.5 -top-1.5 rounded-full bg-gray-700 p-0.5 text-white">
                  <X className="h-3 w-3" />
                </button>
              </div>
            ))}
          </div>
        )}
        <div className="flex items-end gap-1.5">
          <button onClick={() => fileRef.current?.click()} disabled={enviando || adjuntos.length >= MAX_ADJUNTOS} aria-label="Foto"
                  className="rounded-xl border border-gray-200 p-2.5 text-gray-500 disabled:opacity-50">
            <Camera className="h-5 w-5" />
          </button>
          <button onClick={() => archivoRef.current?.click()} disabled={enviando || adjuntos.length >= MAX_ADJUNTOS} aria-label="Adjuntar archivo"
                  className="rounded-xl border border-gray-200 p-2.5 text-gray-500 disabled:opacity-50">
            <Paperclip className="h-5 w-5" />
          </button>
          <button onClick={() => setModalCodigo(true)} aria-label="Código de falla"
                  className="rounded-xl border border-gray-200 p-2.5 text-gray-500">
            <Hash className="h-5 w-5" />
          </button>
          <input ref={fileRef} type="file" accept="image/*" capture="environment" hidden onChange={onArchivos} />
          <input ref={archivoRef} type="file" accept="image/*,application/pdf,.pdf" multiple hidden onChange={onArchivos} />
          <textarea
            ref={inputRef}
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={(e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); enviar() } }}
            placeholder={online ? (escuchando ? 'Escuchando…' : (dx?.estado === 'abierto' ? 'Cuéntame qué mediste o qué pasó…' : 'Describe el síntoma…')) : 'Necesitas señal para usar el copiloto'}
            disabled={!online || enviando || cargandoConv}
            rows={1}
            className="max-h-28 min-w-0 flex-1 resize-none rounded-xl border border-gray-200 px-3 py-2.5 text-sm outline-none focus:border-indigo-400 disabled:bg-gray-50"
          />
          {vozDisponible && !input.trim() && !adjuntos.length ? (
            <button onClick={toggleVoz} disabled={!online || enviando} aria-label="Dictar"
                    className={`rounded-xl p-2.5 text-white disabled:opacity-40 ${escuchando ? 'animate-pulse bg-red-500' : 'bg-indigo-600'}`}>
              {escuchando ? <MicOff className="h-5 w-5" /> : <Mic className="h-5 w-5" />}
            </button>
          ) : (
            <button onClick={() => { recRef.current?.stop(); enviar() }}
                    disabled={!online || enviando || adjuntos.some((a) => a.estado === 'subiendo')
                      || (!input.trim() && !adjuntos.some((a) => a.estado === 'listo'))}
                    aria-label="Enviar" className="rounded-xl bg-indigo-600 p-2.5 text-white disabled:opacity-40">
              {enviando ? <Loader2 className="h-5 w-5 animate-spin" /> : <Send className="h-5 w-5" />}
            </button>
          )}
        </div>
      </div>

      <VisorPagina fuente={visor} onClose={() => setVisor(null)} />

      <HistorialConversaciones open={modalHistorial} onClose={() => setModalHistorial(false)}
                               activoId={activoId} actualId={conv?.id ?? null} onElegir={abrirConversacion} />

      {/* ── Aporte a la biblioteca del taller ── */}
      <Modal open={!!aporteDe} onClose={() => setAporteDe(null)} title="Aportar a la biblioteca">
        <div className="space-y-3">
          {aporteDe?.preview && (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={aporteDe.preview} alt="aporte" className="max-h-40 rounded-lg" />
          )}
          <div>
            <label className="text-xs font-semibold text-gray-700">¿Qué es? *</label>
            <textarea value={fAporte} onChange={(e) => setFAporte(e.target.value)} rows={3} autoFocus
                      placeholder={aporteDe?.preview
                        ? 'Ej: Etiqueta de fusibles de la tapa de la central eléctrica, Scania TRSS-13'
                        : 'Ej: Manual de servicio de la bomba Blackmer del aljibe HHWB-42'}
                      className="mt-1 w-full rounded-lg border border-gray-200 px-3 py-2 text-sm outline-none focus:border-indigo-400" />
          </div>
          <p className="text-[11px] text-gray-500">
            Jefatura lo revisa y lo incorpora a la biblioteca: después el copiloto lo encontrará y lo citará para
            todo el taller. Sirve mucho: etiquetas de fusibles y relés, placas de motor, bomba, grúa o PTO, diagramas pegados en el equipo.
          </p>
        </div>
        <ModalFooter>
          <Button variant="outline" onClick={() => setAporteDe(null)}>Cancelar</Button>
          <Button disabled={fAporte.trim().length < 8}
                  onClick={() => { if (aporteDe) guardarAporte(aporteDe, true, fAporte.trim()); setAporteDe(null) }}>
            Aportar
          </Button>
        </ModalFooter>
      </Modal>

      {/* ── Código de falla directo ── */}
      <Modal open={modalCodigo} onClose={() => setModalCodigo(false)} title="Código de falla">
        <div className="space-y-3">
          <div className="flex gap-2">
            <input value={fCodigo} onChange={(e) => setFCodigo(e.target.value)} autoFocus
                   onKeyDown={(e) => { if (e.key === 'Enter') buscarCodigoDirecto() }}
                   placeholder="Ej: SPN 3251 FMI 0 · 3251-0 · P0420 · MID 128 PID 100"
                   className="min-w-0 flex-1 rounded-lg border border-gray-200 px-3 py-2 text-sm outline-none focus:border-indigo-400" />
            <Button onClick={buscarCodigoDirecto} disabled={fCodigo.trim().length < 2 || buscandoCodigo}>
              {buscandoCodigo ? <Loader2 className="h-4 w-4 animate-spin" /> : <Search className="h-4 w-4" />}
            </Button>
          </div>
          <p className="text-[11px] text-gray-500">
            {activoId ? `Prioriza los códigos de la marca del ${equipoLabel ?? 'equipo'}; incluye genéricos J1939.` : 'Sin equipo elegido: busca en todas las marcas.'}
          </p>
          {errorCodigo && <p className="text-xs text-red-600">{errorCodigo}</p>}
          {codigosRes && codigosRes.length === 0 && (
            <p className="rounded-lg bg-gray-50 p-2 text-xs text-gray-600">
              No está en la tabla cargada. Pregúntale al copiloto: buscará en los manuales y te dirá cómo leer el código completo en el tablero.
            </p>
          )}
          {codigosRes && codigosRes.length > 0 && (
            <div className="max-h-[50vh] overflow-y-auto">
              <TarjetasCodigos codigos={codigosRes} onPreguntar={(c) => {
                setModalCodigo(false)
                enviar(`Tengo el código ${c.codigo} (${c.descripcion}). ¿Cómo lo diagnostico en este equipo?`)
              }} />
            </div>
          )}
        </div>
        <ModalFooter>
          <Button variant="outline" onClick={() => setModalCodigo(false)}>Cerrar</Button>
          {fCodigo.trim().length >= 2 && (
            <Button onClick={() => { setModalCodigo(false); enviar(`Sale el código de falla ${fCodigo.trim()}. ¿Qué significa y cómo lo diagnostico?`) }}>
              Preguntar al copiloto
            </Button>
          )}
        </ModalFooter>
      </Modal>

      {/* ── Selector de equipo ── */}
      <Modal open={modalEquipo} onClose={() => setModalEquipo(false)} title="¿Qué equipo?">
        <div className="space-y-2">
          <input value={busqEquipo} onChange={(e) => setBusqEquipo(e.target.value)} autoFocus
                 placeholder="Patente o código (ej: KCBY-30)"
                 className="w-full rounded-lg border border-gray-200 px-3 py-2 text-sm outline-none focus:border-indigo-400" />
          <div className="max-h-[50vh] divide-y overflow-y-auto rounded-lg border">
            {equipos.map((e) => (
              <button key={e.id} onClick={() => elegirEquipo(e)} className="block w-full px-3 py-2 text-left text-sm hover:bg-gray-50">
                <b>{e.patente ?? e.codigo}</b> <span className="text-xs text-gray-500">{e.nombre}</span>
              </button>
            ))}
            {!equipos.length && <p className="px-3 py-3 text-xs text-gray-400">Sin resultados</p>}
          </div>
          <p className="text-[11px] text-gray-500">
            Con el equipo elegido el copiloto filtra los manuales por su marca y modelo y usa su ficha técnica e historial.
          </p>
        </div>
        <ModalFooter>
          <Button variant="outline" onClick={() => setModalEquipo(false)}>Cancelar</Button>
        </ModalFooter>
      </Modal>

      {/* ── Modales del caso ── */}
      <Modal open={modalSintoma} onClose={() => setModalSintoma(false)} title="Iniciar diagnóstico">
        <div className="space-y-3">
          <div>
            <label className="text-xs font-semibold text-gray-700">¿Cuál es el síntoma? *</label>
            <textarea value={fSintoma} onChange={(e) => setFSintoma(e.target.value)} rows={3}
                      placeholder="Ej: no encienden las luces del tablero y a ratos se apaga"
                      className="mt-1 w-full rounded-lg border border-gray-200 px-3 py-2 text-sm outline-none focus:border-indigo-400" />
          </div>
          <div>
            <label className="text-xs font-semibold text-gray-700">Sistema (si lo sabes)</label>
            <select value={fSistema} onChange={(e) => setFSistema(e.target.value)}
                    className="mt-1 w-full rounded-lg border border-gray-200 bg-white px-3 py-2 text-sm">
              <option value="">No estoy seguro</option>
              {SISTEMAS.map((s) => <option key={s.value} value={s.value}>{s.label}</option>)}
            </select>
          </div>
          <p className="text-[11px] text-gray-500">
            El diagnóstico queda registrado en la OT: síntoma, lo que compruebes y la causa que encuentres.
          </p>
        </div>
        <ModalFooter>
          <Button variant="outline" onClick={() => setModalSintoma(false)}>Cancelar</Button>
          <Button onClick={iniciarDx} disabled={fSintoma.trim().length < 5 || guardando}>
            {guardando ? 'Iniciando…' : 'Partir'}
          </Button>
        </ModalFooter>
      </Modal>

      <Modal open={modalComprobacion} onClose={() => setModalComprobacion(false)} title="Registrar comprobación">
        <div className="space-y-3">
          <div>
            <label className="text-xs font-semibold text-gray-700">¿Qué comprobaste? *</label>
            <textarea value={fDesc} onChange={(e) => setFDesc(e.target.value)} rows={2}
                      placeholder="Ej: voltaje entre borne negativo y chasis con luces encendidas"
                      className="mt-1 w-full rounded-lg border border-gray-200 px-3 py-2 text-sm outline-none focus:border-indigo-400" />
          </div>
          <div>
            <label className="text-xs font-semibold text-gray-700">Resultado</label>
            <div className="mt-1 flex gap-1.5">
              {([['ok', 'OK', 'bg-green-500'], ['no_ok', 'NO OK', 'bg-red-500'], ['valor', 'Medición', 'bg-blue-500']] as const).map(([v, l, c]) => (
                <button key={v} onClick={() => setFResultado(v)}
                        className={`flex-1 rounded-lg border px-2 py-2 text-xs font-semibold ${
                          fResultado === v ? `${c} border-transparent text-white` : 'border-gray-200 bg-white text-gray-500'}`}>
                  {l}
                </button>
              ))}
            </div>
          </div>
          {fResultado === 'valor' && (
            <input value={fValor} onChange={(e) => setFValor(e.target.value)} placeholder="Ej: 0,8 V de caída"
                   className="w-full rounded-lg border border-gray-200 px-3 py-2 text-sm outline-none focus:border-indigo-400" />
          )}
        </div>
        <ModalFooter>
          <Button variant="outline" onClick={() => setModalComprobacion(false)}>Cancelar</Button>
          <Button onClick={registrarComprobacion}
                  disabled={fDesc.trim().length < 3 || (fResultado === 'valor' && !fValor.trim()) || guardando}>
            {guardando ? 'Guardando…' : 'Registrar'}
          </Button>
        </ModalFooter>
      </Modal>

      <Modal open={modalCausa} onClose={() => setModalCausa(false)} title="Solución definitiva">
        <div className="space-y-3">
          <div>
            <label className="text-xs font-semibold text-gray-700">Síntoma</label>
            <input value={fSintoma} onChange={(e) => setFSintoma(e.target.value)}
                   placeholder="Ej: no parte en frío"
                   className="mt-1 w-full rounded-lg border border-gray-200 px-3 py-2 text-sm outline-none focus:border-indigo-400" />
          </div>
          <div>
            <label className="text-xs font-semibold text-gray-700">Causa raíz *</label>
            <textarea value={fCausa} onChange={(e) => setFCausa(e.target.value)} rows={2}
                      placeholder="Ej: masa del chasis sulfatada detrás de la caja de baterías"
                      className="mt-1 w-full rounded-lg border border-gray-200 px-3 py-2 text-sm outline-none focus:border-indigo-400" />
          </div>
          <div>
            <label className="text-xs font-semibold text-gray-700">¿Qué lo solucionó definitivamente? *</label>
            <textarea value={fReparacion} onChange={(e) => setFReparacion(e.target.value)} rows={2}
                      placeholder="Ej: se limpió y reapretó la masa, se protegió con grasa dieléctrica"
                      className="mt-1 w-full rounded-lg border border-gray-200 px-3 py-2 text-sm outline-none focus:border-indigo-400" />
          </div>
          <div>
            <label className="text-xs font-semibold text-gray-700">Sistema</label>
            <select value={fSistema} onChange={(e) => setFSistema(e.target.value)}
                    className="mt-1 w-full rounded-lg border border-gray-200 bg-white px-3 py-2 text-sm">
              <option value="">—</option>
              {SISTEMAS.map((s) => <option key={s.value} value={s.value}>{s.label}</option>)}
            </select>
          </div>
          <p className="text-[11px] text-gray-500">
            Queda como caso técnico del taller: el copiloto lo citará cuando otro equipo igual falle parecido y guardará
            una lección con lo aprendido. Si todavía no está reparado, espera: aquí va lo que DEFINITIVAMENTE lo solucionó.
          </p>
        </div>
        <ModalFooter>
          <Button variant="outline" onClick={() => setModalCausa(false)}>Cancelar</Button>
          <Button onClick={guardarSolucion} disabled={fCausa.trim().length < 5 || fReparacion.trim().length < 5 || guardando}>
            {guardando ? 'Guardando y aprendiendo…' : 'Guardar caso'}
          </Button>
        </ModalFooter>
      </Modal>

      <Modal open={modalVolvio} onClose={() => setModalVolvio(false)} title="La falla volvió">
        <div className="space-y-3">
          <p className="text-sm text-gray-700">
            El caso se reabre y la reparación anterior queda registrada como intento que <b>no</b> resolvió la falla,
            para que el copiloto no la vuelva a proponer.
          </p>
          <div>
            <label className="text-xs font-semibold text-gray-700">¿Qué pasó? (opcional)</label>
            <textarea value={fMotivoVolvio} onChange={(e) => setFMotivoVolvio(e.target.value)} rows={2}
                      placeholder="Ej: a los 3 días volvió a quedar sin luces, ahora también en caliente"
                      className="mt-1 w-full rounded-lg border border-gray-200 px-3 py-2 text-sm outline-none focus:border-indigo-400" />
          </div>
        </div>
        <ModalFooter>
          <Button variant="outline" onClick={() => setModalVolvio(false)}>Cancelar</Button>
          <Button onClick={confirmarVolvio} disabled={guardando}>{guardando ? 'Reabriendo…' : 'Reabrir el caso'}</Button>
        </ModalFooter>
      </Modal>
    </div>
  )
}

export default function CopilotoPage() {
  return (
    <Suspense fallback={<div className="flex h-dvh items-center justify-center"><Spinner /></div>}>
      <CopilotoInner />
    </Suspense>
  )
}
