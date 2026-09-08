'use client'

// ============================================================================
// Copiloto Técnico — chat de diagnóstico para el mecánico (2026-09-08)
// MIG543: además del chat, el diagnóstico es un OBJETO que queda registrado:
// síntoma → comprobaciones (con resultado) → causa raíz. Un caso resuelto se
// vuelve conocimiento: el copiloto lo cita la próxima vez que un equipo del
// mismo modelo falle parecido. Necesita señal: acá no hay offline.
// ============================================================================

import { Suspense, useEffect, useRef, useState } from 'react'
import Link from 'next/link'
import { useSearchParams } from 'next/navigation'
import {
  ArrowLeft, Send, Camera, X, Loader2, WifiOff, Bot, ThumbsUp, ThumbsDown, Sparkles,
  Stethoscope, ClipboardCheck, CheckCircle2, ChevronDown, ChevronUp,
} from 'lucide-react'
import { Spinner } from '@/components/ui/spinner'
import { Modal, ModalFooter } from '@/components/ui/modal'
import { Button } from '@/components/ui/button'
import { supabase } from '@/lib/supabase'
import { useNetworkStatus } from '@/hooks/use-taller-mecanico'
import {
  getDiagnosticoDeOT, crearDiagnostico, agregarComprobacion, resolverDiagnostico,
  SISTEMAS, type Diagnostico,
} from '@/lib/services/copiloto'

type Mensaje = {
  rol: 'user' | 'assistant'
  texto: string
  foto?: string
  consultaId?: string
  feedback?: 'util' | 'no_util'
}

const SUGERENCIAS = [
  'El equipo no parte, ¿por dónde empiezo?',
  '¿Qué fusible controla las luces de trabajo?',
  'Sale un código de falla en el tablero',
  'Ruido en la caja al hacer cambios',
]

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

function CopilotoInner() {
  const params = useSearchParams()
  const otId = params.get('ot')
  const activoId = params.get('activo')
  const equipoLabel = params.get('equipo')
  const online = useNetworkStatus()

  const [mensajes, setMensajes] = useState<Mensaje[]>([])
  const [input, setInput] = useState('')
  const [foto, setFoto] = useState<{ dataUrl: string; base64: string } | null>(null)
  const [enviando, setEnviando] = useState(false)
  const scrollRef = useRef<HTMLDivElement>(null)
  const fileRef = useRef<HTMLInputElement>(null)

  // ── Diagnóstico guiado (MIG543) ───────────────────────────────────────────
  const [dx, setDx] = useState<Diagnostico | null>(null)
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

  useEffect(() => {
    if (otId) getDiagnosticoDeOT(otId).then(setDx).catch(() => { /* sin señal: chat igual sirve */ })
  }, [otId])

  useEffect(() => {
    scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight, behavior: 'smooth' })
  }, [mensajes, enviando])

  async function enviar(texto?: string) {
    const pregunta = (texto ?? input).trim()
    if ((!pregunta && !foto) || enviando) return

    const fotoActual = foto
    setInput(''); setFoto(null); setEnviando(true)
    const historial = mensajes.map((m) => ({ rol: m.rol, texto: m.texto }))
    setMensajes((p) => [...p, { rol: 'user', texto: pregunta || '(foto)', foto: fotoActual?.dataUrl }])

    try {
      const { data: { session } } = await supabase.auth.getSession()
      const token = session?.access_token
      if (!token) throw new Error('Tu sesión expiró. Vuelve a entrar.')

      const res = await fetch('/api/copiloto/consulta', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
        body: JSON.stringify({
          pregunta,
          activoId: activoId || undefined,
          otId: otId || undefined,
          diagnosticoId: dx?.estado === 'abierto' ? dx.id : undefined,
          historial: historial.slice(-6),
          fotoBase64: fotoActual?.base64,
          fotoTipo: 'image/jpeg',
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
      for (;;) {
        const { done, value } = await reader.read()
        if (done) break
        const trozo = decoder.decode(value, { stream: true })
        setMensajes((p) => {
          const copia = [...p]
          copia[copia.length - 1] = { ...copia[copia.length - 1], texto: copia[copia.length - 1].texto + trozo }
          return copia
        })
      }
    } catch (err) {
      setMensajes((p) => [...p, {
        rol: 'assistant',
        texto: `⚠️ ${err instanceof Error ? err.message : 'No se pudo consultar. Revisa la señal e intenta de nuevo.'}`,
      }])
    } finally {
      setEnviando(false)
    }
  }

  async function marcarFeedback(idx: number, fb: 'util' | 'no_util') {
    const m = mensajes[idx]
    if (!m.consultaId || m.feedback) return
    setMensajes((p) => p.map((x, i) => (i === idx ? { ...x, feedback: fb } : x)))
    try { await supabase.rpc('rpc_copiloto_feedback', { p_consulta_id: m.consultaId, p_feedback: fb }) }
    catch { /* el feedback no puede botar el chat */ }
  }

  async function onFoto(e: React.ChangeEvent<HTMLInputElement>) {
    const f = e.target.files?.[0]
    e.target.value = ''
    if (!f) return
    try { setFoto(await comprimirFoto(f)) } catch { /* foto ilegible: se ignora */ }
  }

  // ── Acciones del diagnóstico ──────────────────────────────────────────────
  async function iniciarDx() {
    if (!activoId || fSintoma.trim().length < 5 || guardando) return
    setGuardando(true)
    try {
      const nuevo = await crearDiagnostico({
        otId, activoId, sintoma: fSintoma, sistema: fSistema || null,
      })
      setDx(nuevo)
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
      setDx({ ...dx, comprobaciones })
      setModalComprobacion(false)
      const resumen = `Registré la comprobación: ${fDesc.trim()} → ${
        fResultado === 'valor' ? fValor.trim() : fResultado === 'ok' ? 'OK' : 'NO OK'}. ¿Siguiente paso?`
      setFDesc(''); setFValor('')
      await enviar(resumen)
    } catch (e) {
      alert(e instanceof Error ? e.message : 'No se pudo registrar')
    } finally { setGuardando(false) }
  }

  async function resolverDx() {
    if (!dx || fCausa.trim().length < 5 || guardando) return
    setGuardando(true)
    try {
      await resolverDiagnostico(dx.id, fCausa, fReparacion, fSistema || dx.sistema)
      setDx({ ...dx, estado: 'resuelto', causa_raiz: fCausa.trim(), reparacion: fReparacion.trim() || null })
      setModalCausa(false)
      setMensajes((p) => [...p, {
        rol: 'assistant',
        texto: `✅ Caso guardado. La próxima vez que un equipo como este falle parecido, voy a partir por lo que encontraste: "${fCausa.trim()}". Buen trabajo.`,
      }])
      setFCausa(''); setFReparacion('')
    } catch (e) {
      alert(e instanceof Error ? e.message : 'No se pudo guardar la causa')
    } finally { setGuardando(false) }
  }

  const nComprob = dx?.comprobaciones?.length ?? 0

  return (
    <div className="flex h-dvh flex-col bg-gray-50">
      {/* Header */}
      <header className="flex items-center gap-3 border-b bg-white px-4 py-3">
        <Link href={otId ? `/m/taller/ot/${otId}` : '/m/taller'} className="text-gray-500">
          <ArrowLeft className="h-5 w-5" />
        </Link>
        <div className="flex h-9 w-9 items-center justify-center rounded-full bg-indigo-100">
          <Bot className="h-5 w-5 text-indigo-600" />
        </div>
        <div className="min-w-0 flex-1">
          <h1 className="text-sm font-bold text-gray-900">Copiloto Técnico</h1>
          <p className="truncate text-[11px] text-gray-500">
            {equipoLabel ? `Equipo ${equipoLabel}` : 'Diagnóstico con manuales de la flota'}
          </p>
        </div>
        {!online && (
          <span className="flex items-center gap-1 rounded-full bg-amber-100 px-2 py-1 text-[10px] font-semibold text-amber-700">
            <WifiOff className="h-3 w-3" /> Sin señal
          </span>
        )}
      </header>

      {/* Panel de diagnóstico (solo con OT) */}
      {otId && activoId && (
        <div className="border-b bg-white px-3 py-2">
          {!dx && (
            <button onClick={() => setModalSintoma(true)} disabled={!online}
                    className="flex w-full items-center justify-center gap-2 rounded-xl border-2 border-dashed border-indigo-300 bg-indigo-50 px-3 py-2.5 text-sm font-semibold text-indigo-700 disabled:opacity-50">
              <Stethoscope className="h-4 w-4" /> Iniciar diagnóstico guiado
            </button>
          )}
          {dx && dx.estado === 'abierto' && (
            <div className="rounded-xl border border-indigo-200 bg-indigo-50/60 px-3 py-2">
              <button onClick={() => setDxAbierto((v) => !v)} className="flex w-full items-center gap-2 text-left">
                <Stethoscope className="h-4 w-4 shrink-0 text-indigo-600" />
                <span className="min-w-0 flex-1 truncate text-xs font-semibold text-indigo-900">
                  Diagnóstico: {dx.sintoma}
                </span>
                <span className="rounded-full bg-indigo-600 px-1.5 py-0.5 text-[10px] font-bold text-white">{nComprob}</span>
                {dxAbierto ? <ChevronUp className="h-4 w-4 text-indigo-400" /> : <ChevronDown className="h-4 w-4 text-indigo-400" />}
              </button>
              {dxAbierto && (
                <div className="mt-2 space-y-1.5">
                  {dx.comprobaciones.map((c, i) => (
                    <div key={i} className="flex items-start gap-1.5 text-[12px] text-gray-700">
                      <span className={`mt-0.5 h-2 w-2 shrink-0 rounded-full ${
                        c.resultado === 'ok' ? 'bg-green-500' : c.resultado === 'no_ok' ? 'bg-red-500' : 'bg-blue-500'}`} />
                      <span className="min-w-0">{c.descripcion}{c.valor ? ` = ${c.valor}` : ''}
                        <span className="text-gray-400"> · {c.resultado === 'valor' ? 'medición' : c.resultado.toUpperCase()}</span>
                      </span>
                    </div>
                  ))}
                  <div className="flex gap-2 pt-1">
                    <button onClick={() => setModalComprobacion(true)} disabled={!online}
                            className="flex flex-1 items-center justify-center gap-1 rounded-lg border border-indigo-300 bg-white px-2 py-2 text-[11.5px] font-semibold text-indigo-700 disabled:opacity-50">
                      <ClipboardCheck className="h-3.5 w-3.5" /> Registrar comprobación
                    </button>
                    <button onClick={() => { setFSistema(dx.sistema ?? ''); setModalCausa(true) }} disabled={!online}
                            className="flex flex-1 items-center justify-center gap-1 rounded-lg bg-green-600 px-2 py-2 text-[11.5px] font-semibold text-white disabled:opacity-50">
                      <CheckCircle2 className="h-3.5 w-3.5" /> Encontré la causa
                    </button>
                  </div>
                </div>
              )}
            </div>
          )}
          {dx && dx.estado === 'resuelto' && (
            <div className="flex items-start gap-2 rounded-xl border border-green-200 bg-green-50 px-3 py-2">
              <CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0 text-green-600" />
              <div className="min-w-0 text-[12px] text-green-900">
                <b>Caso resuelto y guardado.</b> Causa: {dx.causa_raiz}
              </div>
            </div>
          )}
        </div>
      )}

      {/* Chat */}
      <div ref={scrollRef} className="flex-1 space-y-3 overflow-y-auto px-3 py-4">
        {mensajes.length === 0 && (
          <div className="mx-auto mt-6 max-w-sm text-center">
            <Sparkles className="mx-auto h-8 w-8 text-indigo-400" />
            <p className="mt-2 text-sm font-semibold text-gray-800">¿Qué le pasa al equipo?</p>
            <p className="mt-1 text-xs text-gray-500">
              Describe el síntoma o manda una foto. Respondo con los manuales de la flota,
              los casos ya resueltos y el historial {equipoLabel ? `del ${equipoLabel}` : 'del equipo'}, citando la fuente.
            </p>
            <div className="mt-4 space-y-2">
              {SUGERENCIAS.map((s) => (
                <button key={s} onClick={() => enviar(s)} disabled={!online || enviando}
                        className="block w-full rounded-xl border border-indigo-200 bg-white px-3 py-2 text-left text-xs text-indigo-700 disabled:opacity-50">
                  {s}
                </button>
              ))}
            </div>
          </div>
        )}

        {mensajes.map((m, i) => (
          <div key={i} className={`flex ${m.rol === 'user' ? 'justify-end' : 'justify-start'}`}>
            <div className={`max-w-[85%] rounded-2xl px-3 py-2 text-sm ${
              m.rol === 'user' ? 'rounded-br-sm bg-indigo-600 text-white' : 'rounded-bl-sm border bg-white text-gray-800'}`}>
              {m.foto && <img src={m.foto} alt="foto enviada" className="mb-2 max-h-40 rounded-lg" />}
              <div className="whitespace-pre-wrap">{m.texto || (enviando && i === mensajes.length - 1 ? '…' : '')}</div>
              {m.rol === 'assistant' && m.consultaId && m.texto && (!enviando || i < mensajes.length - 1) && (
                <div className="mt-2 flex items-center gap-2 border-t pt-1.5">
                  <span className="text-[10px] text-gray-400">¿Te sirvió?</span>
                  <button onClick={() => marcarFeedback(i, 'util')}
                          className={`rounded p-1 ${m.feedback === 'util' ? 'bg-green-100 text-green-600' : 'text-gray-400'}`}>
                    <ThumbsUp className="h-3.5 w-3.5" />
                  </button>
                  <button onClick={() => marcarFeedback(i, 'no_util')}
                          className={`rounded p-1 ${m.feedback === 'no_util' ? 'bg-red-100 text-red-600' : 'text-gray-400'}`}>
                    <ThumbsDown className="h-3.5 w-3.5" />
                  </button>
                </div>
              )}
            </div>
          </div>
        ))}

        {enviando && mensajes[mensajes.length - 1]?.rol === 'user' && (
          <div className="flex justify-start">
            <div className="flex items-center gap-2 rounded-2xl rounded-bl-sm border bg-white px-3 py-2 text-xs text-gray-500">
              <Loader2 className="h-3.5 w-3.5 animate-spin" /> Revisando manuales, casos e historial…
            </div>
          </div>
        )}
      </div>

      <p className="border-t bg-amber-50 px-3 py-1 text-center text-[10px] text-amber-700">
        Apoyo al diagnóstico — los trabajos de riesgo se validan con el jefe de taller.
      </p>

      {/* Input */}
      <div className="border-t bg-white p-3 pb-[max(12px,env(safe-area-inset-bottom))]">
        {foto && (
          <div className="mb-2 flex items-center gap-2">
            <img src={foto.dataUrl} alt="foto adjunta" className="h-12 w-12 rounded-lg object-cover" />
            <button onClick={() => setFoto(null)} className="rounded-full bg-gray-100 p-1 text-gray-500">
              <X className="h-4 w-4" />
            </button>
          </div>
        )}
        <div className="flex items-end gap-2">
          <button onClick={() => fileRef.current?.click()} disabled={enviando}
                  className="rounded-xl border border-gray-200 p-2.5 text-gray-500 disabled:opacity-50">
            <Camera className="h-5 w-5" />
          </button>
          <input ref={fileRef} type="file" accept="image/*" capture="environment" hidden onChange={onFoto} />
          <textarea
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={(e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); enviar() } }}
            placeholder={online ? 'Describe el síntoma…' : 'Necesitas señal para usar el copiloto'}
            disabled={!online || enviando}
            rows={1}
            className="max-h-28 flex-1 resize-none rounded-xl border border-gray-200 px-3 py-2.5 text-sm outline-none focus:border-indigo-400 disabled:bg-gray-50"
          />
          <button onClick={() => enviar()} disabled={!online || enviando || (!input.trim() && !foto)}
                  className="rounded-xl bg-indigo-600 p-2.5 text-white disabled:opacity-40">
            {enviando ? <Loader2 className="h-5 w-5 animate-spin" /> : <Send className="h-5 w-5" />}
          </button>
        </div>
      </div>

      {/* ── Modales del diagnóstico ── */}
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

      <Modal open={modalCausa} onClose={() => setModalCausa(false)} title="Causa encontrada">
        <div className="space-y-3">
          <div>
            <label className="text-xs font-semibold text-gray-700">Causa raíz *</label>
            <textarea value={fCausa} onChange={(e) => setFCausa(e.target.value)} rows={2}
                      placeholder="Ej: masa del chasis sulfatada detrás de la caja de baterías"
                      className="mt-1 w-full rounded-lg border border-gray-200 px-3 py-2 text-sm outline-none focus:border-indigo-400" />
          </div>
          <div>
            <label className="text-xs font-semibold text-gray-700">¿Cómo se reparó?</label>
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
            Esto queda como caso técnico: el copiloto lo citará cuando otro equipo igual falle parecido.
          </p>
        </div>
        <ModalFooter>
          <Button variant="outline" onClick={() => setModalCausa(false)}>Cancelar</Button>
          <Button onClick={resolverDx} disabled={fCausa.trim().length < 5 || guardando}>
            {guardando ? 'Guardando…' : 'Guardar caso'}
          </Button>
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
