'use client'

import { useState, useEffect } from 'react'
import { MessageSquare, Save } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'

// ============================================================================
// Piezas compartidas del Panel de Gerencia
// ============================================================================

export const lunesDe = (d: Date) => {
  const x = new Date(d)
  const dia = (x.getDay() + 6) % 7          // 0 = lunes
  x.setDate(x.getDate() - dia)
  return x
}

export const iso = (d: Date) => d.toISOString().slice(0, 10)

export const fmtFecha = (s: string | null) =>
  s ? new Date(s + (s.length === 10 ? 'T12:00:00' : '')).toLocaleDateString('es-CL',
    { day: '2-digit', month: 'short' }) : '—'

export const fmtClp = (n: number | null | undefined) =>
  n == null ? '—' : `$${Math.round(n).toLocaleString('es-CL')}`

/** Cifras de gerencia: $28.652.634 se lee peor que $28,7M en una franja de KPI. */
export const fmtClpCorto = (n: number | null | undefined) => {
  if (n == null) return '—'
  const a = Math.abs(n)
  if (a >= 1_000_000) return `$${(n / 1_000_000).toFixed(1).replace('.', ',')}M`
  if (a >= 1_000) return `$${Math.round(n / 1_000)}k`
  return `$${Math.round(n)}`
}

export const fmtNum = (n: number | null | undefined) =>
  n == null ? '—' : Math.round(n).toLocaleString('es-CL')

export const pct = (n: number | null | undefined) =>
  n == null ? '—' : `${Number(n).toFixed(1)}%`

export const ESTADO_LABEL: Record<string, string> = {
  A: 'Arrendado', C: 'En contrato', D: 'Disponible', L: 'Leasing',
  U: 'Uso interno', R: 'Recepción', H: 'Habilitación', M: 'Mantención',
  T: 'Taller', F: 'Fuera de servicio', V: 'Venta',
}

/**
 * Acepta "1.234,5" y "1234.5". En Chile el separador de miles es el punto, así
 * que un parseFloat directo convierte 1.234 en 1,234.
 */
export const aNum = (s: string): number | null => {
  const t = String(s ?? '').trim().replace(/\./g, '').replace(',', '.')
  if (t === '') return null
  const n = Number(t)
  return Number.isFinite(n) ? n : null
}

export function Metric({ label, value, tone = 'neutral', sub }: {
  label: string
  value: string | number
  tone?: 'neutral' | 'ok' | 'warn' | 'bad'
  sub?: string
}) {
  const color = {
    neutral: 'text-foreground',
    ok: 'text-emerald-600',
    warn: 'text-amber-600',
    bad: 'text-red-600',
  }[tone]
  return (
    <div className="rounded-lg border bg-card px-3 py-2">
      <div className="text-[11px] uppercase tracking-wide text-muted-foreground">{label}</div>
      <div className={`text-xl font-bold leading-tight ${color}`}>{value}</div>
      {sub && <div className="text-[11px] text-muted-foreground">{sub}</div>}
    </div>
  )
}

/**
 * Forma mínima que necesita el editor. Se declara aparte de `Comentario`
 * porque las filas de equipo y de faena traen el comentario embebido (con
 * `texto` posiblemente nulo), no una fila completa de panel_comentarios.
 */
export type ComentarioValor = {
  texto: string | null
  plan_accion: string | null
  responsable: string | null
  fecha_compromiso: string | null
}

/**
 * Editor de comentario / plan de acción. Guarda con botón explícito: en un
 * tablero que se revisa en reunión, el autoguardado hace que un roce del
 * teclado pise lo que otro acaba de escribir.
 */
export function ComentarioEditor({
  titulo, comentario, conPlan = false, onGuardar, guardando, compacto = false,
}: {
  titulo: string
  comentario: ComentarioValor | null
  conPlan?: boolean
  guardando: boolean
  /** Sin marco ni encabezado: para cuando ya vive dentro de una tarjeta. */
  compacto?: boolean
  onGuardar: (v: {
    texto: string; planAccion: string; responsable: string; fechaCompromiso: string
  }) => void
}) {
  const [texto, setTexto] = useState(comentario?.texto ?? '')
  const [plan, setPlan] = useState(comentario?.plan_accion ?? '')
  const [resp, setResp] = useState(comentario?.responsable ?? '')
  const [fecha, setFecha] = useState(comentario?.fecha_compromiso ?? '')

  // Si cambia la semana o llegan datos frescos del servidor, refrescar el form.
  useEffect(() => {
    setTexto(comentario?.texto ?? '')
    setPlan(comentario?.plan_accion ?? '')
    setResp(comentario?.responsable ?? '')
    setFecha(comentario?.fecha_compromiso ?? '')
  }, [comentario?.texto, comentario?.plan_accion, comentario?.responsable, comentario?.fecha_compromiso])

  const sucio = texto !== (comentario?.texto ?? '')
    || plan !== (comentario?.plan_accion ?? '')
    || resp !== (comentario?.responsable ?? '')
    || fecha !== (comentario?.fecha_compromiso ?? '')

  return (
    <div className={compacto
      ? 'space-y-2'
      : 'space-y-2 rounded-lg border border-dashed bg-muted/30 p-3'}>
      {!compacto && (
        <div className="flex items-center gap-1.5 text-xs font-medium text-muted-foreground">
          <MessageSquare className="h-3.5 w-3.5" />
          {titulo}
        </div>
      )}
      <textarea
        value={texto}
        onChange={(e) => setTexto(e.target.value)}
        rows={conPlan ? 2 : 3}
        placeholder="Comentario…"
        className="w-full resize-y rounded-md border bg-background px-2 py-1.5 text-sm
                   focus:outline-none focus:ring-2 focus:ring-ring"
      />
      {conPlan && (
        <>
          <textarea
            value={plan}
            onChange={(e) => setPlan(e.target.value)}
            rows={2}
            placeholder="Plan de acción a seguir…"
            className="w-full resize-y rounded-md border bg-background px-2 py-1.5 text-sm
                       focus:outline-none focus:ring-2 focus:ring-ring"
          />
          <div className="flex flex-wrap gap-2">
            <Input
              value={resp}
              onChange={(e) => setResp(e.target.value)}
              placeholder="Responsable"
              className="h-8 flex-1 min-w-[140px] text-sm"
            />
            <Input
              type="date"
              value={fecha ?? ''}
              onChange={(e) => setFecha(e.target.value)}
              className="h-8 w-[150px] text-sm"
            />
          </div>
          {plan.trim() !== '' && (!resp.trim() || !fecha) && (
            <p className="text-[11px] text-amber-700">
              Un plan sin responsable y sin fecha no aparece en la lista de
              compromisos, así que nadie lo va a revisar la semana que viene.
            </p>
          )}
        </>
      )}
      <div className="flex items-center justify-between">
        <span className="text-[11px] text-muted-foreground">
          {texto.trim() === '' && comentario ? 'Guardar vacío elimina el comentario' : ''}
        </span>
        <Button
          size="sm"
          variant={sucio ? 'primary' : 'outline'}
          disabled={!sucio || guardando}
          onClick={() => onGuardar({
            texto, planAccion: plan, responsable: resp, fechaCompromiso: fecha,
          })}
        >
          <Save className="mr-1 h-3.5 w-3.5" />
          {guardando ? 'Guardando…' : 'Guardar'}
        </Button>
      </div>
    </div>
  )
}
