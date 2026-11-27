'use client'

// ============================================================================
// Copiloto Prevención Centinela — chat (MIG734)
// Lo usan /m/copiloto-sso (teléfono: supervisores ENEX y APR) y
// /dashboard/prevencion/copiloto (oficina). Tres atajos: ART de la tarea,
// charla de 5 minutos desde una Lección Aprendida y «¿puede subir?».
// ============================================================================

import { useRef, useState } from 'react'
import { ClipboardList, Megaphone, UserCheck, Send, ShieldAlert, ThumbsUp, ThumbsDown, FileText, X } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { RespuestaMarkdown } from '@/components/copiloto/partes'
import type { AtajoSso, EventoSso, FuenteSso } from '@/lib/copiloto-sso/tipos'

type Mensaje = { rol: 'user' | 'assistant'; texto: string; atajo?: AtajoSso | null; fuentes?: FuenteSso[]; consultaId?: string; util?: boolean }

const ATAJOS: { id: AtajoSso; titulo: string; Icono: typeof ClipboardList; ayuda: string; ejemplo: string }[] = [
  { id: 'art', titulo: 'ART de la tarea', Icono: ClipboardList, ayuda: 'Describa la tarea, el lugar y quiénes la hacen.',
    ejemplo: 'Cambio de filtro y calibración del surtidor 2 en Semimóvil 2, con Fabián Castillo e Iván Lobos' },
  { id: 'charla', titulo: 'Charla 5 min', Icono: Megaphone, ayuda: 'Tema o N.º de Lección Aprendida (puede dejarlo vacío).',
    ejemplo: 'Energía eléctrica: corte de cable energizado' },
  { id: 'subir', titulo: '¿Puede subir?', Icono: UserCheck, ayuda: 'Nombre o RUT del trabajador.',
    ejemplo: 'Fabián Castillo' },
]

export function ChatCopilotoSso({ compacto = false }: { compacto?: boolean }) {
  const [mensajes, setMensajes] = useState<Mensaje[]>([])
  const [texto, setTexto] = useState('')
  const [atajo, setAtajo] = useState<AtajoSso | null>(null)
  const [estado, setEstado] = useState<string | null>(null)
  const [enviando, setEnviando] = useState(false)
  const [fuenteAbierta, setFuenteAbierta] = useState<FuenteSso | null>(null)
  const finRef = useRef<HTMLDivElement>(null)

  const actualizarUltimo = (f: (m: Mensaje) => Mensaje) =>
    setMensajes((p) => (p.length ? [...p.slice(0, -1), f(p[p.length - 1])] : p))

  const enviar = async () => {
    const at = atajo
    const q = texto.trim() || (at === 'charla' ? 'La lección aprendida que más aplique a estaciones de combustible' : '')
    if (!q || enviando) return
    const historial = mensajes.filter((m) => m.texto).slice(-6).map((m) => ({ rol: m.rol, texto: m.texto }))
    setMensajes((p) => [...p, { rol: 'user', texto: q, atajo: at }])
    setTexto(''); setAtajo(null); setEnviando(true); setEstado('Revisando la base de Centinela…')
    try {
      const { data: { session } } = await supabase.auth.getSession()
      const res = await fetch('/api/copiloto-sso/consulta', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${session?.access_token ?? ''}` },
        body: JSON.stringify({ pregunta: q, atajo: at, historial }),
      })
      if (!res.ok) {
        const j = await res.json().catch(() => null)
        throw new Error(j?.error ?? `Error ${res.status}`)
      }
      setMensajes((p) => [...p, { rol: 'assistant', texto: '', consultaId: res.headers.get('X-Copiloto-Id') ?? undefined }])
      const reader = res.body!.getReader()
      const dec = new TextDecoder()
      let buf = ''
      const procesar = (l: string) => {
        if (!l.trim()) return
        let ev: EventoSso
        try { ev = JSON.parse(l) } catch { return }
        if (ev.t === 'texto') { setEstado(null); actualizarUltimo((m) => ({ ...m, texto: m.texto + ev.d })) }
        else if (ev.t === 'estado') setEstado(ev.d)
        else if (ev.t === 'fuentes') actualizarUltimo((m) => ({ ...m, fuentes: ev.d }))
      }
      for (;;) {
        const { done, value } = await reader.read()
        if (done) break
        buf += dec.decode(value, { stream: true })
        const ls = buf.split('\n'); buf = ls.pop() ?? ''
        ls.forEach(procesar)
        finRef.current?.scrollIntoView({ block: 'end' })
      }
      procesar(buf)
    } catch (e) {
      setMensajes((p) => [...p, { rol: 'assistant', texto: `[${(e as Error).message}]` }])
    } finally {
      setEnviando(false); setEstado(null)
      setTimeout(() => finRef.current?.scrollIntoView({ block: 'end' }), 50)
    }
  }

  const calificar = async (m: Mensaje, util: boolean) => {
    if (!m.consultaId) return
    setMensajes((p) => p.map((x) => (x === m ? { ...x, util } : x)))
    await supabase.rpc('rpc_copiloto_sso_feedback', { p_id: m.consultaId, p_util: util })
  }

  const at = ATAJOS.find((a) => a.id === atajo)

  return (
    <div className={`flex flex-col ${compacto ? 'min-h-[100dvh]' : 'min-h-[70vh]'} bg-gray-50`}>
      <div className="flex-1 space-y-3 p-3">
        {mensajes.length === 0 && (
          <div className="rounded-xl border border-emerald-200 bg-emerald-50 p-3 text-sm text-emerald-900">
            <p className="font-semibold">Copiloto de Prevención · Minera Centinela</p>
            <p className="mt-1 text-[13px]">Pregunte por el RECSS, las EDC y sus controles críticos, las Lecciones Aprendidas o la legislación. Cito la fuente y, ante la duda sobre un control crítico, la respuesta es <b>detener la tarea</b>.</p>
          </div>
        )}
        {mensajes.map((m, i) => (
          <div key={i} className={m.rol === 'user' ? 'flex justify-end' : ''}>
            {m.rol === 'user' ? (
              <div className="max-w-[85%] rounded-2xl rounded-br-sm bg-emerald-700 px-3 py-2 text-sm text-white">
                {m.atajo && <span className="mb-0.5 block text-[11px] font-semibold uppercase opacity-80">{ATAJOS.find((a) => a.id === m.atajo)?.titulo}</span>}
                {m.texto}
              </div>
            ) : (
              <div className="rounded-2xl rounded-bl-sm border border-gray-200 bg-white p-3">
                {m.texto ? <RespuestaMarkdown texto={m.texto} onCita={(n) => setFuenteAbierta(m.fuentes?.find((f) => f.n === n) ?? null)} />
                  : <p className="text-sm text-gray-400">…</p>}
                {!!m.fuentes?.length && (
                  <div className="mt-3 border-t pt-2">
                    <p className="mb-1 text-[11px] font-semibold uppercase text-gray-500">Fuentes</p>
                    <ul className="space-y-1">
                      {m.fuentes.map((f) => (
                        <li key={f.n}>
                          <button type="button" onClick={() => setFuenteAbierta(f)} className="flex w-full items-start gap-1.5 text-left text-[12px] text-gray-700 hover:text-emerald-800">
                            <span className="rounded bg-indigo-100 px-1 font-bold text-indigo-700">F{f.n}</span>
                            <span className="min-w-0 flex-1">{f.documento}{f.seccion ? <span className="text-gray-500"> · {f.seccion.split(' › ').slice(-1)[0]}</span> : null}</span>
                            {f.escaneado && <span className="shrink-0 rounded bg-amber-100 px-1 text-[10px] font-semibold text-amber-800" title="Leído por OCR: verificar cifras en el PDF original">OCR</span>}
                          </button>
                        </li>
                      ))}
                    </ul>
                  </div>
                )}
                {m.consultaId && m.texto && !enviando && (
                  <div className="mt-2 flex items-center gap-2 text-[11px] text-gray-500">
                    ¿Le sirvió?
                    <button type="button" aria-label="Me sirvió" onClick={() => calificar(m, true)}
                            className={`inline-flex h-8 w-8 items-center justify-center rounded-full ${m.util === true ? 'bg-emerald-100 text-emerald-700' : 'hover:bg-gray-100'}`}><ThumbsUp className="h-4 w-4" aria-hidden="true" /></button>
                    <button type="button" aria-label="No me sirvió" onClick={() => calificar(m, false)}
                            className={`inline-flex h-8 w-8 items-center justify-center rounded-full ${m.util === false ? 'bg-red-100 text-red-700' : 'hover:bg-gray-100'}`}><ThumbsDown className="h-4 w-4" aria-hidden="true" /></button>
                  </div>
                )}
              </div>
            )}
          </div>
        ))}
        {estado && <p className="animate-pulse text-xs text-gray-500">{estado}</p>}
        <div ref={finRef} />
      </div>

      <div className="sticky bottom-0 border-t bg-white p-3">
        <div className="mb-2 grid grid-cols-3 gap-2">
          {ATAJOS.map((a) => (
            <button key={a.id} type="button" onClick={() => setAtajo(atajo === a.id ? null : a.id)} aria-pressed={atajo === a.id}
                    className={`flex min-h-11 flex-col items-center justify-center gap-0.5 rounded-xl border px-1 py-1.5 text-[11px] font-semibold ${atajo === a.id ? 'border-emerald-600 bg-emerald-50 text-emerald-800' : 'border-gray-200 text-gray-700'}`}>
              <a.Icono className="h-4 w-4" aria-hidden="true" />{a.titulo}
            </button>
          ))}
        </div>
        {at && (
          <p className="mb-1 flex items-center justify-between gap-2 text-[12px] text-emerald-800">
            <span><b>{at.titulo}:</b> {at.ayuda}</span>
            <button type="button" aria-label="Quitar atajo" onClick={() => setAtajo(null)} className="inline-flex h-8 w-8 shrink-0 items-center justify-center rounded-full hover:bg-gray-100"><X className="h-4 w-4" aria-hidden="true" /></button>
          </p>
        )}
        <div className="flex items-end gap-2">
          <label className="sr-only" htmlFor="pregunta-sso">Pregunta</label>
          <textarea id="pregunta-sso" value={texto} onChange={(e) => setTexto(e.target.value)} rows={2}
                    onKeyDown={(e) => { if (e.key === 'Enter' && !e.shiftKey && !compacto) { e.preventDefault(); void enviar() } }}
                    placeholder={at ? `Ej.: ${at.ejemplo}` : 'Ej.: ¿Qué controles críticos aplican al bloquear una bomba?'}
                    className="min-h-11 flex-1 resize-none rounded-xl border border-gray-300 px-3 py-2 text-sm" />
          <button type="button" onClick={() => void enviar()} disabled={enviando || (!texto.trim() && atajo !== 'charla')} aria-label="Enviar"
                  className="inline-flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-emerald-700 text-white disabled:opacity-40">
            <Send className="h-5 w-5" aria-hidden="true" />
          </button>
        </div>
        <p className="mt-2 flex items-center gap-1 text-[10px] text-gray-500">
          <ShieldAlert className="h-3 w-3" aria-hidden="true" /> Apoyo al experto SSO y al ADC, no los reemplaza. Base: Campus Centinela al 26-11-2026.
        </p>
      </div>

      {fuenteAbierta && (
        <div role="dialog" aria-modal="true" aria-label="Fuente" className="fixed inset-0 z-50 flex items-end justify-center bg-black/40 sm:items-center" onClick={() => setFuenteAbierta(null)}>
          <div className="max-h-[80dvh] w-full max-w-lg overflow-y-auto rounded-t-2xl bg-white p-4 sm:rounded-2xl" onClick={(e) => e.stopPropagation()}>
            <div className="mb-2 flex items-start justify-between gap-2">
              <p className="flex items-start gap-1.5 text-sm font-semibold text-gray-900"><FileText className="mt-0.5 h-4 w-4 shrink-0" aria-hidden="true" />[F{fuenteAbierta.n}] {fuenteAbierta.documento}</p>
              <button type="button" aria-label="Cerrar" onClick={() => setFuenteAbierta(null)} className="inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-full hover:bg-gray-100"><X className="h-4 w-4" aria-hidden="true" /></button>
            </div>
            {fuenteAbierta.seccion && <p className="mb-2 text-xs text-gray-500">{fuenteAbierta.seccion}</p>}
            {fuenteAbierta.escaneado && <p className="mb-2 rounded bg-amber-50 px-2 py-1 text-xs text-amber-800">Texto leído por OCR: verifique las cifras en el PDF original o con el ADC.</p>}
            <p className="whitespace-pre-wrap text-[13px] text-gray-700">{fuenteAbierta.extracto}</p>
          </div>
        </div>
      )}
    </div>
  )
}
