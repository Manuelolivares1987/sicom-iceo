'use client'

// ============================================================================
// Copiloto Técnico — piezas de la conversación persistente (MIG583).
// Historial de hilos para retomar, tarjeta de seguimiento («¿cómo terminó
// esto?»), propuesta de solución del copiloto para confirmar, estado del caso
// (resuelto / la falla volvió) y motivos del 👎.
// ============================================================================

import { useEffect, useState } from 'react'
import {
  CheckCircle2, RotateCcw, MessageSquare, Sparkles, X, Truck, History, Search, Loader2, ShieldCheck, AlertTriangle,
} from 'lucide-react'
import { Modal, ModalFooter } from '@/components/ui/modal'
import { Button } from '@/components/ui/button'
import { listarConversaciones } from '@/lib/services/copiloto'
import type { ConversacionCopiloto, DiagnosticoCopiloto, PropuestaSolucion } from '@/lib/copiloto/tipos'
import { describirPausa } from '@/lib/copiloto/conversacion'

export const ESTADO_CONV: Record<string, { t: string; c: string }> = {
  abierta: { t: 'En curso', c: 'bg-amber-100 text-amber-700' },
  resuelta: { t: 'Resuelta', c: 'bg-green-100 text-green-700' },
  descartada: { t: 'Consulta', c: 'bg-gray-100 text-gray-500' },
}

export function etiquetaEquipo(c: ConversacionCopiloto): string | null {
  return c.activo?.patente ?? c.activo?.codigo ?? null
}

// ── Historial de conversaciones ─────────────────────────────────────────────
export function HistorialConversaciones({ open, onClose, activoId, actualId, onElegir }: {
  open: boolean
  onClose: () => void
  activoId: string | null
  actualId: string | null
  onElegir: (c: ConversacionCopiloto) => void
}) {
  const [lista, setLista] = useState<ConversacionCopiloto[] | null>(null)
  const [filtro, setFiltro] = useState<'todas' | 'abierta' | 'resuelta'>('todas')
  const [soloEquipo, setSoloEquipo] = useState(!!activoId)
  const [texto, setTexto] = useState('')

  useEffect(() => {
    if (!open) return
    setLista(null)
    listarConversaciones({
      activoId: soloEquipo && activoId ? activoId : undefined,
      estado: filtro === 'todas' ? undefined : filtro,
      limit: 60,
    }).then(setLista).catch(() => setLista([]))
  }, [open, filtro, soloEquipo, activoId])

  const visibles = (lista ?? []).filter((c) => !texto.trim()
    || c.titulo.toLowerCase().includes(texto.toLowerCase())
    || (etiquetaEquipo(c) ?? '').toLowerCase().includes(texto.toLowerCase()))

  return (
    <Modal open={open} onClose={onClose} title="Mis conversaciones">
      <div className="space-y-2">
        <div className="flex gap-1.5">
          {([['todas', 'Todas'], ['abierta', 'En curso'], ['resuelta', 'Resueltas']] as const).map(([v, l]) => (
            <button key={v} onClick={() => setFiltro(v)}
                    className={`rounded-full px-2.5 py-1 text-[11px] font-semibold ${filtro === v ? 'bg-indigo-600 text-white' : 'bg-gray-100 text-gray-600'}`}>
              {l}
            </button>
          ))}
          {activoId && (
            <button onClick={() => setSoloEquipo((v) => !v)}
                    className={`ml-auto flex items-center gap-1 rounded-full px-2.5 py-1 text-[11px] font-semibold ${soloEquipo ? 'bg-indigo-100 text-indigo-700' : 'bg-gray-100 text-gray-600'}`}>
              <Truck className="h-3 w-3" /> Este equipo
            </button>
          )}
        </div>
        <div className="relative">
          <Search className="absolute left-2 top-2.5 h-3.5 w-3.5 text-gray-400" />
          <input value={texto} onChange={(e) => setTexto(e.target.value)} placeholder="Buscar por síntoma o patente"
                 className="w-full rounded-lg border border-gray-200 py-2 pl-7 pr-3 text-sm outline-none focus:border-indigo-400" />
        </div>
        <div className="max-h-[55vh] divide-y overflow-y-auto rounded-lg border">
          {lista === null && <p className="flex items-center gap-2 px-3 py-4 text-xs text-gray-400"><Loader2 className="h-3.5 w-3.5 animate-spin" /> Cargando…</p>}
          {lista !== null && visibles.length === 0 && <p className="px-3 py-4 text-xs text-gray-400">Sin conversaciones.</p>}
          {visibles.map((c) => {
            const e = ESTADO_CONV[c.estado] ?? ESTADO_CONV.abierta
            const equipo = etiquetaEquipo(c)
            return (
              <button key={c.id} onClick={() => onElegir(c)}
                      className={`block w-full px-3 py-2 text-left hover:bg-gray-50 ${c.id === actualId ? 'bg-indigo-50' : ''}`}>
                <div className="flex items-center gap-2">
                  {equipo && <span className="font-mono text-[11px] font-bold text-gray-700">{equipo}</span>}
                  <span className={`rounded-full px-1.5 py-0.5 text-[9.5px] font-semibold ${e.c}`}>{e.t}</span>
                  <span className="ml-auto text-[10.5px] text-gray-400">{describirPausa(c.ultimo_at)}</span>
                </div>
                <p className="mt-0.5 truncate text-[12.5px] text-gray-800">{c.titulo}</p>
                <p className="text-[10.5px] text-gray-400"><MessageSquare className="mr-0.5 inline h-3 w-3" />{c.mensajes} mensaje{c.mensajes === 1 ? '' : 's'}</p>
              </button>
            )
          })}
        </div>
      </div>
      <ModalFooter>
        <Button variant="outline" onClick={onClose}>Cerrar</Button>
      </ModalFooter>
    </Modal>
  )
}

// ── Hilos para retomar (pantalla vacía) ─────────────────────────────────────
export function ListaRetomar({ conversaciones, onElegir, onVerTodas }: {
  conversaciones: ConversacionCopiloto[]
  onElegir: (c: ConversacionCopiloto) => void
  onVerTodas: () => void
}) {
  if (!conversaciones.length) return null
  return (
    <div className="mt-5 text-left">
      <p className="mb-1.5 flex items-center gap-1 text-[11px] font-semibold uppercase tracking-wide text-gray-400">
        <History className="h-3.5 w-3.5" /> Retomar
      </p>
      <div className="space-y-1.5">
        {conversaciones.map((c) => {
          const e = ESTADO_CONV[c.estado] ?? ESTADO_CONV.abierta
          const equipo = etiquetaEquipo(c)
          return (
            <button key={c.id} onClick={() => onElegir(c)}
                    className="block w-full rounded-xl border border-gray-200 bg-white px-3 py-2 text-left">
              <div className="flex items-center gap-2 text-[10.5px]">
                {equipo && <span className="font-mono font-bold text-gray-700">{equipo}</span>}
                <span className={`rounded-full px-1.5 py-0.5 font-semibold ${e.c}`}>{e.t}</span>
                <span className="ml-auto text-gray-400">{describirPausa(c.ultimo_at)}</span>
              </div>
              <p className="truncate text-xs text-gray-800">{c.titulo}</p>
            </button>
          )
        })}
      </div>
      <button onClick={onVerTodas} className="mt-1.5 text-[11px] font-semibold text-indigo-600">Ver todas las conversaciones</button>
    </div>
  )
}

// ── «¿Cómo terminó esto?» al retomar un hilo abierto ────────────────────────
export function TarjetaSeguimiento({ titulo, pausa, onResuelto, onSigue, onConsulta }: {
  titulo: string
  pausa: string
  onResuelto: () => void
  onSigue: () => void
  onConsulta: () => void
}) {
  return (
    <div className="rounded-xl border border-amber-200 bg-amber-50 px-3 py-2.5">
      <p className="text-[12.5px] font-semibold text-amber-900">Retomaste «{titulo}» ({pausa}). ¿Cómo terminó?</p>
      <div className="mt-2 grid grid-cols-3 gap-1.5">
        <button onClick={onResuelto} className="rounded-lg bg-green-600 px-2 py-2 text-[11px] font-semibold text-white">✅ Se solucionó</button>
        <button onClick={onSigue} className="rounded-lg border border-amber-300 bg-white px-2 py-2 text-[11px] font-semibold text-amber-800">Sigue fallando</button>
        <button onClick={onConsulta} className="rounded-lg border border-gray-200 bg-white px-2 py-2 text-[11px] font-semibold text-gray-600">Era solo consulta</button>
      </div>
    </div>
  )
}

// ── Propuesta de solución del copiloto ──────────────────────────────────────
export function TarjetaPropuesta({ propuesta, onRevisar, onDescartar }: {
  propuesta: PropuestaSolucion
  onRevisar: () => void
  onDescartar: () => void
}) {
  return (
    <div className="mt-2 rounded-xl border border-green-300 bg-green-50 px-3 py-2.5">
      <p className="flex items-center gap-1 text-[12px] font-bold text-green-900">
        <Sparkles className="h-3.5 w-3.5" /> El copiloto propone guardar la solución
      </p>
      <p className="mt-1 text-[12px] text-gray-800"><b>Causa:</b> {propuesta.causa_raiz}</p>
      <p className="text-[12px] text-gray-800"><b>Solución:</b> {propuesta.reparacion}</p>
      <div className="mt-2 flex gap-1.5">
        <button onClick={onRevisar} className="flex flex-1 items-center justify-center gap-1 rounded-lg bg-green-600 px-2 py-2 text-[11.5px] font-semibold text-white">
          <CheckCircle2 className="h-3.5 w-3.5" /> Revisar y guardar
        </button>
        <button onClick={onDescartar} aria-label="Todavía no" className="rounded-lg border border-gray-200 bg-white px-2.5 text-gray-500">
          <X className="h-4 w-4" />
        </button>
      </div>
    </div>
  )
}

// ── Estado del caso en la cabecera ──────────────────────────────────────────
export function TarjetaCaso({ dx, abierto, onToggle, onSolucion, onVolvio, online }: {
  dx: DiagnosticoCopiloto
  abierto: boolean
  onToggle: () => void
  onSolucion: () => void
  onVolvio: () => void
  online: boolean
}) {
  if (dx.estado === 'resuelto') {
    return (
      <div className="rounded-xl border border-green-200 bg-green-50 px-3 py-2">
        <div className="flex items-start gap-2">
          <CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0 text-green-600" />
          <div className="min-w-0 flex-1 text-[12px] text-green-900">
            <p><b>Caso resuelto</b>{dx.validado_at ? <span className="ml-1 inline-flex items-center gap-0.5 rounded bg-green-200 px-1 text-[9.5px] font-semibold"><ShieldCheck className="h-3 w-3" />validado</span> : null}</p>
            <p><b>Causa:</b> {dx.causa_raiz}</p>
            <p><b>Solución:</b> {dx.reparacion}</p>
            {dx.leccion && abierto && <p className="mt-1 whitespace-pre-line text-[11.5px] text-green-800/90">{dx.leccion}</p>}
          </div>
        </div>
        <div className="mt-1.5 flex gap-2">
          {dx.leccion && (
            <button onClick={onToggle} className="text-[11px] font-semibold text-green-700">{abierto ? 'Ocultar lección' : 'Ver lección'}</button>
          )}
          <button onClick={onVolvio} disabled={!online}
                  className="ml-auto flex items-center gap-1 rounded-lg border border-red-200 bg-white px-2 py-1 text-[11px] font-semibold text-red-700 disabled:opacity-50">
            <RotateCcw className="h-3 w-3" /> La falla volvió
          </button>
        </div>
      </div>
    )
  }
  const n = dx.comprobaciones.length
  return (
    <div className="rounded-xl border border-indigo-200 bg-indigo-50/60 px-3 py-2">
      <button onClick={onToggle} className="flex w-full items-center gap-2 text-left">
        <span className="min-w-0 flex-1 truncate text-xs font-semibold text-indigo-900">Caso: {dx.sintoma}</span>
        {dx.reaperturas > 0 && <span className="rounded-full bg-red-100 px-1.5 py-0.5 text-[9.5px] font-bold text-red-700">reabierto ×{dx.reaperturas}</span>}
        <span className="rounded-full bg-indigo-600 px-1.5 py-0.5 text-[10px] font-bold text-white">{n}</span>
      </button>
      {abierto && (
        <div className="mt-2 space-y-1.5">
          {dx.comprobaciones.map((c, i) => (
            <div key={i} className="flex items-start gap-1.5 text-[12px] text-gray-700">
              {c.tipo === 'reparacion_fallida'
                ? <AlertTriangle className="mt-0.5 h-3 w-3 shrink-0 text-red-500" />
                : <span className={`mt-1 h-2 w-2 shrink-0 rounded-full ${c.resultado === 'ok' ? 'bg-green-500' : c.resultado === 'no_ok' ? 'bg-red-500' : 'bg-blue-500'}`} />}
              <span className="min-w-0">{c.descripcion}{c.valor ? ` = ${c.valor}` : ''}
                <span className="text-gray-400"> · {c.resultado === 'valor' ? 'medición' : c.resultado.toUpperCase()}</span>
              </span>
            </div>
          ))}
          {n === 0 && <p className="text-[11.5px] text-gray-500">Cuéntale al copiloto lo que vas midiendo: él lo anota aquí.</p>}
          <button onClick={onSolucion} disabled={!online}
                  className="flex w-full items-center justify-center gap-1 rounded-lg bg-green-600 px-2 py-2 text-[11.5px] font-semibold text-white disabled:opacity-50">
            <CheckCircle2 className="h-3.5 w-3.5" /> Registrar solución definitiva
          </button>
        </div>
      )}
    </div>
  )
}

// ── Motivo del 👎 ───────────────────────────────────────────────────────────
export const MOTIVOS_NO_UTIL = [
  'No encontró el dato', 'Respuesta equivocada', 'No aplica a este equipo', 'Muy larga o confusa',
]
export function MotivosNoUtil({ onElegir }: { onElegir: (m: string) => void }) {
  return (
    <div className="mt-1.5 flex flex-wrap gap-1">
      <span className="text-[10px] text-gray-400">¿Qué falló?</span>
      {MOTIVOS_NO_UTIL.map((m) => (
        <button key={m} onClick={() => onElegir(m)} className="rounded-full border border-gray-200 px-2 py-0.5 text-[10px] text-gray-600">{m}</button>
      ))}
    </div>
  )
}
