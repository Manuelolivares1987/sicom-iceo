'use client'

// ============================================================================
// Copiloto Técnico — chat de diagnóstico para el mecánico (2026-09-08)
// Entra desde la OT (con contexto del equipo) o desde el home del taller.
// La respuesta llega en streaming desde /api/copiloto/consulta, con citas de
// los manuales cargados en el corpus. Necesita señal: acá no hay offline.
// ============================================================================

import { Suspense, useEffect, useRef, useState } from 'react'
import Link from 'next/link'
import { useSearchParams } from 'next/navigation'
import {
  ArrowLeft, Send, Camera, X, Loader2, WifiOff, Bot, ThumbsUp, ThumbsDown, Sparkles,
} from 'lucide-react'
import { Spinner } from '@/components/ui/spinner'
import { supabase } from '@/lib/supabase'
import { useNetworkStatus } from '@/hooks/use-taller-mecanico'

type Mensaje = {
  rol: 'user' | 'assistant'
  texto: string
  foto?: string          // dataURL para previsualizar lo que mandó
  consultaId?: string    // para el feedback 👍/👎
  feedback?: 'util' | 'no_util'
}

const SUGERENCIAS = [
  'El equipo no parte, ¿por dónde empiezo?',
  '¿Qué fusible controla las luces de trabajo?',
  'Sale un código de falla en el tablero',
  'Ruido en la caja al hacer cambios',
]

// Comprime la foto del teléfono a JPEG ~1280px para no mandar 8 MB por 4G.
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

      {/* Chat */}
      <div ref={scrollRef} className="flex-1 space-y-3 overflow-y-auto px-3 py-4">
        {mensajes.length === 0 && (
          <div className="mx-auto mt-6 max-w-sm text-center">
            <Sparkles className="mx-auto h-8 w-8 text-indigo-400" />
            <p className="mt-2 text-sm font-semibold text-gray-800">¿Qué le pasa al equipo?</p>
            <p className="mt-1 text-xs text-gray-500">
              Describe el síntoma o manda una foto. Respondo con los manuales de la flota
              y el historial {equipoLabel ? `del ${equipoLabel}` : 'del equipo'}, citando la fuente.
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
              <Loader2 className="h-3.5 w-3.5 animate-spin" /> Revisando manuales e historial…
            </div>
          </div>
        )}
      </div>

      {/* Advertencia fija */}
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
