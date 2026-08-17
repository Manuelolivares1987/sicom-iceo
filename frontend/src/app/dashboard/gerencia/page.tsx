'use client'

import { useMemo, useState, useEffect } from 'react'
import Link from 'next/link'
import {
  Building2, Wrench, Fuel, AlertTriangle, CheckCircle2, Clock,
  MessageSquare, Save, ChevronLeft, ChevronRight, Database, Mountain,
  TrendingDown, FileWarning, CalendarDays,
} from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Spinner } from '@/components/ui/spinner'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { usePanelGerencia, useGuardarComentario } from '@/hooks/use-panel-gerencia'
import type {
  EquipoDetenido, FaenaEnex, PanelTaller, CalidadDato,
  CierreCombustibleFaena, CombustibleCoquimbo,
} from '@/lib/services/panel-gerencia'

// ============================================================================
// Panel de Gerencia — cuadrante Coquimbo · cuadrante Calama (MIG295)
// ============================================================================

// ── helpers ────────────────────────────────────────────────────────────────
const lunesDe = (d: Date) => {
  const x = new Date(d)
  const dia = (x.getDay() + 6) % 7          // 0 = lunes
  x.setDate(x.getDate() - dia)
  return x
}
const iso = (d: Date) => d.toISOString().slice(0, 10)
const fmtFecha = (s: string | null) =>
  s ? new Date(s + (s.length === 10 ? 'T12:00:00' : '')).toLocaleDateString('es-CL',
    { day: '2-digit', month: 'short' }) : '—'
const fmtClp = (n: number | null | undefined) =>
  n == null ? '—' : `$${Math.round(n).toLocaleString('es-CL')}`
const pct = (n: number | null | undefined) =>
  n == null ? '—' : `${Number(n).toFixed(1)}%`

const ESTADO_LABEL: Record<string, string> = {
  A: 'Arrendado', C: 'En contrato', D: 'Disponible', L: 'Leasing',
  U: 'Uso interno', R: 'Recepción', H: 'Habilitación', M: 'Mantención',
  T: 'Taller', F: 'Fuera de servicio', V: 'Venta',
}

// ── bloques chicos ─────────────────────────────────────────────────────────
function Metric({ label, value, tone = 'neutral', sub }: {
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
type ComentarioValor = {
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
function ComentarioEditor({
  titulo, comentario, conPlan = false, onGuardar, guardando,
}: {
  titulo: string
  comentario: ComentarioValor | null
  conPlan?: boolean
  guardando: boolean
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
    <div className="space-y-2 rounded-lg border border-dashed bg-muted/30 p-3">
      <div className="flex items-center gap-1.5 text-xs font-medium text-muted-foreground">
        <MessageSquare className="h-3.5 w-3.5" />
        {titulo}
      </div>
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

/**
 * Taller. Se muestra en dos bloques deliberadamente separados: lo que produjo
 * el proceso digital este mes, y el arrastre heredado. Sumarlos hacía ver 50 OT
 * abiertas como si el checklist digital las hubiera generado, cuando 43 vienen
 * de junio y julio.
 */
function TallerBloque({ t }: { t: PanelTaller }) {
  const p = t.periodo
  const origenes = Object.entries(p.nc_por_origen ?? {})
  const digital = origenes
    .filter(([k]) => k === 'ejecucion_ot' || k === 'inspeccion_ot')
    .reduce((a, [, v]) => a + v, 0)

  return (
    <div className="space-y-3">
      {/* Proceso digital — el mes en curso */}
      <div>
        <div className="mb-1.5 flex items-center gap-1.5 text-xs font-semibold text-emerald-700">
          <CheckCircle2 className="h-3.5 w-3.5" />
          Proceso digital — este mes
        </div>
        <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
          <Metric label="OT creadas" value={p.ot_creadas}
            sub={`${p.ot_correctivas} corr · ${p.ot_preventivas} prev`} />
          <Metric label="OT cerradas" value={p.ot_cerradas}
            tone={p.ot_cerradas < p.ot_creadas ? 'warn' : 'ok'}
            sub={`${p.ot_abiertas} siguen abiertas`} />
          <Metric label="NC detectadas" value={p.nc_creadas}
            tone={p.nc_creadas > 0 ? 'ok' : 'warn'}
            sub={digital > 0 ? `${digital} desde checklist` : 'ninguna desde checklist'} />
          <Metric label="NC sin resolver" value={p.nc_abiertas}
            tone={p.nc_abiertas === p.nc_creadas && p.nc_creadas > 0 ? 'bad' : 'warn'}
            sub={`${p.nc_altas} de severidad alta`} />
        </div>
        <div className="mt-1 flex flex-wrap gap-x-4 gap-y-1 px-1 text-[11px] text-muted-foreground">
          {p.ot_primera && (
            <span>OT: <b className="text-foreground">{fmtFecha(p.ot_primera)} → {fmtFecha(p.ot_ultima)}</b></span>
          )}
          {p.nc_primera && (
            <span>NC: <b className="text-foreground">{fmtFecha(p.nc_primera)} → {fmtFecha(p.nc_ultima)}</b></span>
          )}
          {origenes.length > 0 && (
            <span>Origen: {origenes.map(([k, v]) => `${k.replace('_', ' ')} ${v}`).join(' · ')}</span>
          )}
        </div>
      </div>

      {/* Resumen por fecha */}
      {t.por_fecha?.length > 0 && (
        <div className="rounded-lg border bg-muted/30 p-2">
          <div className="mb-1.5 flex items-center justify-between text-[11px] font-medium text-muted-foreground">
            <span>Actividad día a día</span>
            <span>{t.por_fecha.length} día{t.por_fecha.length === 1 ? '' : 's'} con registro</span>
          </div>
          <div className="flex flex-wrap gap-1.5">
            {t.por_fecha.map((d) => (
              <div key={d.fecha}
                className="rounded border bg-card px-2 py-1 text-center"
                title={`${d.ot} OT · ${d.nc} NC`}>
                <div className="text-[10px] text-muted-foreground">{fmtFecha(d.fecha)}</div>
                <div className="flex items-center justify-center gap-1.5 text-xs font-semibold">
                  {d.ot > 0 && <span className="text-blue-700">{d.ot} OT</span>}
                  {d.nc > 0 && <span className="text-amber-700">{d.nc} NC</span>}
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Arrastre */}
      {(t.arrastre.ot_abiertas > 0 || t.arrastre.nc_abiertas > 0) && (
        <div>
          <div className="mb-1.5 flex items-center gap-1.5 text-xs font-semibold text-amber-700">
            <Clock className="h-3.5 w-3.5" />
            Arrastre de meses anteriores
          </div>
          <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
            <Metric label="OT abiertas" value={t.arrastre.ot_abiertas}
              tone={t.arrastre.ot_abiertas > 30 ? 'bad' : 'warn'}
              sub={t.arrastre.ot_mas_antigua ? `desde ${fmtFecha(t.arrastre.ot_mas_antigua)}` : undefined} />
            <Metric label="Antigüedad prom." value={t.arrastre.ot_dias_prom != null ? `${t.arrastre.ot_dias_prom} d` : '—'}
              tone={(t.arrastre.ot_dias_prom ?? 0) > 30 ? 'bad' : 'warn'} />
            <Metric label="NC sin resolver" value={t.arrastre.nc_abiertas}
              tone={t.arrastre.nc_abiertas > 20 ? 'bad' : 'warn'}
              sub={t.arrastre.nc_mas_antigua ? `desde ${fmtFecha(t.arrastre.nc_mas_antigua)}` : undefined} />
            <Metric label="Sin responsable" value={t.ot_sin_responsable}
              tone={t.ot_sin_responsable > 0 ? 'warn' : 'ok'}
              sub={`${t.ot_en_ejecucion} en ejecución`} />
          </div>
        </div>
      )}
    </div>
  )
}

/**
 * Cierre mensual de combustible de una faena. Los litros vienen de la planilla
 * de operación, no del sistema, así que la tarjeta declara siempre el archivo
 * de origen: un número de gerencia sin dueño no se puede defender en reunión.
 */
function FaenaCombustible({ f }: { f: CierreCombustibleFaena }) {
  const [abierto, setAbierto] = useState(false)
  // La fluctuación llega como fracción (-0.0008 = -0,08%). En combustible el
  // umbral de gestión habitual es 0,5%.
  const fluctPct = f.fluctuacion_pct != null ? f.fluctuacion_pct * 100 : null
  const fluctFuera = fluctPct != null && Math.abs(fluctPct) > 0.5

  return (
    <div className="space-y-2 rounded-lg border p-3">
      <div className="flex items-baseline justify-between gap-2">
        <div className="text-sm font-semibold">{f.nombre}</div>
        <span className="rounded bg-emerald-100 px-1.5 py-0.5 text-[10px] font-medium text-emerald-800">
          {f.transacciones} transacciones
        </span>
      </div>

      <div className="grid grid-cols-2 gap-2">
        <Metric label="Litros del mes" value={Math.round(f.litros_total).toLocaleString('es-CL')}
          sub={f.litros_trasvasije > 0
            ? `${Math.round(f.litros_venta).toLocaleString('es-CL')} venta · ${Math.round(f.litros_trasvasije).toLocaleString('es-CL')} trasv.`
            : 'despacho a equipos'} />
        <Metric label="Fluctuación"
          value={fluctPct != null ? `${fluctPct.toFixed(2)}%` : '—'}
          tone={fluctPct == null ? 'neutral' : fluctFuera ? 'bad' : 'ok'}
          sub={f.fluctuacion_lt != null ? `${f.fluctuacion_lt} L` : 'no declarada en el cierre'} />
      </div>

      <div className="text-[11px] text-muted-foreground">
        {f.dias_con_registro} días con registro · {fmtFecha(f.fecha_min)} → {fmtFecha(f.fecha_max)}
      </div>

      <button onClick={() => setAbierto((v) => !v)}
        className="text-[11px] font-medium text-blue-700 underline">
        {abierto ? 'Ocultar detalle' : 'Ver detalle por punto y cliente'}
      </button>

      {abierto && (
        <div className="grid gap-2 sm:grid-cols-2">
          <div>
            <div className="mb-1 text-[10px] uppercase text-muted-foreground">Por punto</div>
            {f.detalle_por_punto.slice(0, 6).map((d) => (
              <div key={d.clave} className="flex justify-between gap-2 text-[11px]">
                <span className="truncate">{d.clave}</span>
                <b>{d.litros.toLocaleString('es-CL')}</b>
              </div>
            ))}
          </div>
          <div>
            <div className="mb-1 text-[10px] uppercase text-muted-foreground">Por cliente</div>
            {f.detalle_por_empresa.slice(0, 6).map((d) => (
              <div key={d.clave} className="flex justify-between gap-2 text-[11px]">
                <span className="truncate">{d.clave}</span>
                <b>{d.litros.toLocaleString('es-CL')}</b>
              </div>
            ))}
          </div>
        </div>
      )}

      {f.fuente_archivo && (
        <div className="truncate text-[10px] text-muted-foreground" title={f.fuente_archivo}>
          Fuente: {f.fuente_archivo}
        </div>
      )}
    </div>
  )
}

/**
 * La brecha entre lo que se controla (Excel) y lo que está trazado en el
 * sistema. Es la pregunta de gerencia sobre combustible: no "¿cuánto se
 * despachó?" sino "¿cuánto de eso puedo auditar?".
 */
function BrechaTrazabilidad({ c }: { c: CombustibleCoquimbo }) {
  const trazado = c.trazado_en_sistema.movimientos_franke + c.trazado_en_sistema.despachos_romeral
  if (c.con_cierre_cargado === 0) return null
  return (
    <div className="rounded-lg border border-amber-300 bg-amber-50 px-3 py-2 text-xs text-amber-900">
      <div className="flex items-start gap-2">
        <FileWarning className="mt-0.5 h-4 w-4 shrink-0" />
        <div>
          <b>{Math.round(c.litros_total_periodo).toLocaleString('es-CL')} litros</b> controlados
          este mes en planillas de operación, contra <b>{trazado}</b> movimiento
          {trazado === 1 ? '' : 's'} registrado{trazado === 1 ? '' : 's'} en el sistema.
          El volumen se está midiendo; lo que falta es la trazabilidad transaccional
          —quién despachó, a qué equipo, con qué respaldo—.
          <div className="mt-1 text-[11px] opacity-80">
            Infraestructura ya montada y ociosa: {c.infraestructura.camiones_activos} camiones,{' '}
            {c.infraestructura.estanques_fijos} estanques fijos,{' '}
            {c.infraestructura.romeral_ubicaciones} ubicaciones y{' '}
            {c.infraestructura.romeral_equipos} equipos configurados en Romeral.
          </div>
        </div>
      </div>
    </div>
  )
}

function FilaDetenido({ e, onGuardar, guardando }: {
  e: EquipoDetenido
  guardando: boolean
  onGuardar: (activoId: string, v: {
    texto: string; planAccion: string; responsable: string; fechaCompromiso: string
  }) => void
}) {
  const [abierto, setAbierto] = useState(false)
  const critico = e.dias_consecutivos >= 10
  return (
    <div className={`rounded-lg border ${critico ? 'border-red-300 bg-red-50/50' : 'bg-card'}`}>
      <button
        onClick={() => setAbierto((v) => !v)}
        className="flex w-full items-center gap-2 px-3 py-2 text-left"
      >
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2">
            <span className="font-semibold">{e.codigo}</span>
            {e.patente && <span className="text-xs text-muted-foreground">{e.patente}</span>}
            <span className={`rounded px-1.5 py-0.5 text-[10px] font-medium
              ${e.estado_actual === 'F' ? 'bg-red-100 text-red-700' : 'bg-amber-100 text-amber-700'}`}>
              {ESTADO_LABEL[e.estado_actual ?? ''] ?? e.estado_actual}
            </span>
          </div>
          <div className="truncate text-xs text-muted-foreground">{e.nombre}</div>
        </div>
        <div className="text-right">
          <div className={`text-lg font-bold leading-none ${critico ? 'text-red-600' : 'text-amber-600'}`}>
            {e.dias_consecutivos} d
          </div>
          <div className="text-[10px] text-muted-foreground">
            {e.dias_detenido}/{e.dias_obs} del mes
          </div>
        </div>
        {e.plan_accion
          ? <CheckCircle2 className="h-4 w-4 shrink-0 text-emerald-600" />
          : <AlertTriangle className="h-4 w-4 shrink-0 text-amber-500" />}
      </button>

      {abierto && (
        <div className="space-y-2 border-t px-3 py-2">
          <div className="flex flex-wrap gap-x-4 gap-y-1 text-xs text-muted-foreground">
            <span>Detenido desde <b className="text-foreground">{fmtFecha(e.detenido_desde)}</b></span>
            {e.ot_folio
              ? <span>OT <b className="text-foreground">{e.ot_folio}</b> ({e.ot_estado})</span>
              : <span className="font-medium text-red-600">Sin OT abierta</span>}
          </div>
          <ComentarioEditor
            titulo="Comentario y plan de acción"
            comentario={{
              texto: e.comentario, plan_accion: e.plan_accion,
              responsable: e.responsable, fecha_compromiso: e.fecha_compromiso,
            }}
            conPlan
            guardando={guardando}
            onGuardar={(v) => onGuardar(e.activo_id, v)}
          />
        </div>
      )}
    </div>
  )
}

function FaenaEnexCard({ f, onGuardar, guardando }: {
  f: FaenaEnex
  guardando: boolean
  onGuardar: (faenaId: string, v: {
    texto: string; planAccion: string; responsable: string; fechaCompromiso: string
  }) => void
}) {
  const [abierto, setAbierto] = useState(false)
  return (
    <div className={`rounded-lg border ${f.sin_plan ? 'border-amber-300 bg-amber-50/40' : 'bg-card'}`}>
      <button onClick={() => setAbierto((v) => !v)} className="w-full px-3 py-2 text-left">
        <div className="flex items-start justify-between gap-2">
          <div className="min-w-0">
            <div className="flex flex-wrap items-center gap-2">
              <span className="font-semibold">{f.nombre}</span>
              <span className="rounded bg-muted px-1.5 py-0.5 text-[10px] text-muted-foreground">
                {f.codigo}
              </span>
              {f.operador && (
                <span className="rounded bg-slate-100 px-1.5 py-0.5 text-[10px] text-slate-600">
                  {f.operador}
                </span>
              )}
            </div>
            <div className="text-xs text-muted-foreground">
              {f.lineas} · {fmtClp(f.facturacion_mensual)}/mes ({pct(f.pct_facturacion)} del contrato)
            </div>
          </div>
          <div className="shrink-0 text-right">
            {f.sin_plan ? (
              <span className="rounded bg-amber-200 px-2 py-1 text-[11px] font-semibold text-amber-900">
                SIN PLAN
              </span>
            ) : (
              <>
                <div className={`text-lg font-bold leading-none
                  ${(f.cumplimiento_pct ?? 0) >= 90 ? 'text-emerald-600'
                    : (f.cumplimiento_pct ?? 0) >= 50 ? 'text-amber-600' : 'text-red-600'}`}>
                  {pct(f.cumplimiento_pct)}
                </div>
                <div className="text-[10px] text-muted-foreground">
                  {f.ejecutados}/{f.programados} ejecutados
                </div>
              </>
            )}
          </div>
        </div>
      </button>

      {abierto && (
        <div className="space-y-2 border-t px-3 py-2">
          <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
            <Metric label="Instalaciones" value={f.instalaciones}
              tone={f.instalaciones === 0 ? 'bad' : 'neutral'} />
            <Metric label="Programados" value={f.programados}
              tone={f.programados === 0 ? 'warn' : 'neutral'} />
            <Metric label="Firmados" value={f.firmados}
              tone={f.firmados < f.ejecutados ? 'warn' : 'ok'}
              sub={f.firmados < f.ejecutados ? 'faltan firmas del mandante' : undefined} />
            <Metric label="Requerimientos" value={f.requerimientos_mes}
              tone={f.requerimientos_sin_firmar > 0 ? 'warn' : 'neutral'}
              sub={`${f.requerimientos_sin_firmar} sin firmar`} />
          </div>
          <div className="flex flex-wrap gap-x-4 gap-y-1 text-[11px] text-muted-foreground">
            <span>Última ejecución: <b className="text-foreground">{fmtFecha(f.ultima_ejecucion)}</b></span>
            <span>Vigencia hasta: <b className="text-foreground">{fmtFecha(f.vigencia_hasta)}</b></span>
          </div>
          {f.sin_plan && (
            <div className="flex items-start gap-2 rounded-md bg-amber-100 px-3 py-2 text-xs text-amber-900">
              <FileWarning className="mt-0.5 h-4 w-4 shrink-0" />
              <span>
                Esta faena no tiene instalaciones ni programación cargadas, así que
                no hay avance que medir. Es {pct(f.pct_facturacion)} de la facturación
                del contrato sin control. Al cargar el plan, el avance aparece solo.
              </span>
            </div>
          )}
          <ComentarioEditor
            titulo="Comentario y plan de acción"
            comentario={{
              texto: f.comentario, plan_accion: f.plan_accion,
              responsable: f.responsable, fecha_compromiso: f.fecha_compromiso,
            }}
            conPlan
            guardando={guardando}
            onGuardar={(v) => onGuardar(f.faena_id, v)}
          />
        </div>
      )}
    </div>
  )
}

function BandaCalidad({ c }: { c: CalidadDato }) {
  const alerta = c.dias_rezago > 1 || (c.cobertura_pct ?? 100) < 95
  return (
    <div className={`flex flex-wrap items-center gap-x-5 gap-y-1 rounded-lg border px-3 py-2 text-xs
      ${alerta ? 'border-amber-300 bg-amber-50 text-amber-900' : 'border-emerald-200 bg-emerald-50 text-emerald-900'}`}>
      <span className="flex items-center gap-1.5 font-medium">
        <Database className="h-3.5 w-3.5" />
        Calidad del dato
      </span>
      <span>Último día cargado: <b>{fmtFecha(c.ultimo_dia)}</b></span>
      <span>Rezago: <b>{c.dias_rezago} día{c.dias_rezago === 1 ? '' : 's'}</b></span>
      <span>Cobertura del mes: <b>{pct(c.cobertura_pct)}</b> ({c.dias_cargados}/{c.dias_transcurridos} días)</span>
      <span>{c.equipos_ultimo_dia ?? '—'} equipos el último día</span>
      {c.sugerencias_pendientes > 0 && (
        <Link href="/dashboard/flota/sugerencias" className="font-semibold underline">
          {c.sugerencias_pendientes} sugerencias por aplicar
        </Link>
      )}
      {alerta && (
        <span className="w-full text-[11px]">
          El estado diario lo carga el planificador a mano en{' '}
          <Link href="/dashboard/flota/sugerencias" className="underline">Sugerencias de estado</Link>.
          Los días sin cargar no se cuentan, así que la disponibilidad del mes está
          calculada sobre {c.dias_cargados} días, no {c.dias_transcurridos}.
        </span>
      )}
    </div>
  )
}

// ── página ─────────────────────────────────────────────────────────────────
export default function PanelGerenciaPage() {
  useRequireAuth()
  const [semana, setSemana] = useState(() => iso(lunesDe(new Date())))

  const { data, isLoading, error } = usePanelGerencia(semana)
  const guardar = useGuardarComentario(semana)

  const mueveSemana = (dias: number) => {
    const d = new Date(semana + 'T12:00:00')
    d.setDate(d.getDate() + dias)
    setSemana(iso(lunesDe(d)))
  }

  const rango = useMemo(() => {
    if (!data) return ''
    const i = new Date(data.semana.inicio + 'T12:00:00')
    const f = new Date(data.semana.fin + 'T12:00:00')
    return `${i.toLocaleDateString('es-CL', { day: '2-digit', month: 'short' })} — ${
      f.toLocaleDateString('es-CL', { day: '2-digit', month: 'short', year: 'numeric' })}`
  }, [data])

  if (error?.name === 'PanelNoAutorizadoError') {
    return (
      <div className="p-6">
        <Card>
          <CardContent className="flex flex-col items-center gap-2 py-10 text-center">
            <AlertTriangle className="h-8 w-8 text-amber-500" />
            <p className="font-medium">No tienes permiso para ver el Panel de Gerencia.</p>
            <p className="text-sm text-muted-foreground">
              Pídele a un administrador el permiso <code>gerencia · view</code> en
              Admin → Perfiles y roles.
            </p>
          </CardContent>
        </Card>
      </div>
    )
  }

  return (
    <div className="space-y-4 p-4 sm:p-6">
      {/* Encabezado */}
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="flex items-center gap-2 text-2xl font-bold">
            <Building2 className="h-6 w-6 text-blue-700" />
            Panel de Gerencia
          </h1>
          <p className="text-sm text-muted-foreground">
            Cuadrantes Coquimbo y Calama · semana {rango}
          </p>
        </div>
        <div className="flex items-center gap-1">
          <Button variant="outline" size="sm" onClick={() => mueveSemana(-7)}>
            <ChevronLeft className="h-4 w-4" />
          </Button>
          <Input
            type="date"
            value={semana}
            onChange={(e) => e.target.value && setSemana(iso(lunesDe(new Date(e.target.value + 'T12:00:00'))))}
            className="h-9 w-[150px]"
          />
          <Button variant="outline" size="sm" onClick={() => mueveSemana(7)}>
            <ChevronRight className="h-4 w-4" />
          </Button>
          <Button variant="outline" size="sm" onClick={() => setSemana(iso(lunesDe(new Date())))}>
            Hoy
          </Button>
        </div>
      </div>

      {isLoading && (
        <div className="flex justify-center py-16"><Spinner /></div>
      )}

      {error && error.name !== 'PanelNoAutorizadoError' && (
        <div className="rounded-lg border border-red-300 bg-red-50 px-4 py-3 text-sm text-red-800">
          No se pudo cargar el panel: {error.message}
        </div>
      )}

      {data && (
        <>
          <BandaCalidad c={data.calidad_dato} />

          {/* ── LOS DOS CUADRANTES ─────────────────────────────────────── */}
          <div className="grid gap-4 xl:grid-cols-2">

            {/* ══ CUADRANTE COQUIMBO ══ */}
            <div className="space-y-3">
              <div className="flex items-center gap-2 rounded-lg bg-blue-700 px-3 py-2 text-white">
                <Building2 className="h-5 w-5" />
                <h2 className="text-lg font-bold">Coquimbo</h2>
                <span className="ml-auto text-sm opacity-90">
                  {data.coquimbo.disponibilidad.equipos} equipos ·
                  disponibilidad {pct(data.coquimbo.disponibilidad.promedio)}
                </span>
              </div>

              <Card>
                <CardHeader className="pb-2">
                  <CardTitle className="flex items-center gap-2 text-base">
                    <Wrench className="h-4 w-4" /> Taller
                  </CardTitle>
                </CardHeader>
                <CardContent><TallerBloque t={data.coquimbo.taller} /></CardContent>
              </Card>

              <Card>
                <CardHeader className="pb-2">
                  <CardTitle className="flex items-center gap-2 text-base">
                    <CalendarDays className="h-4 w-4" />
                    Disponibilidad del mes
                  </CardTitle>
                </CardHeader>
                <CardContent className="space-y-2">
                  <div className="grid grid-cols-3 gap-2">
                    <Metric label="Promedio" value={pct(data.coquimbo.disponibilidad.promedio)}
                      tone={(data.coquimbo.disponibilidad.promedio ?? 0) >= 90 ? 'ok'
                        : (data.coquimbo.disponibilidad.promedio ?? 0) >= 80 ? 'warn' : 'bad'} />
                    <Metric label="Equipos" value={data.coquimbo.disponibilidad.equipos} />
                    <Metric label="Bajo 90%" value={data.coquimbo.disponibilidad.bajo_90}
                      tone={data.coquimbo.disponibilidad.bajo_90 > 0 ? 'warn' : 'ok'} />
                  </div>
                  <div className="max-h-56 overflow-y-auto rounded-md border">
                    <table className="w-full text-xs">
                      <thead className="sticky top-0 bg-muted">
                        <tr>
                          <th className="px-2 py-1 text-left font-medium">Equipo</th>
                          <th className="px-2 py-1 text-right font-medium">Días</th>
                          <th className="px-2 py-1 text-right font-medium">Detenido</th>
                          <th className="px-2 py-1 text-right font-medium">Disp.</th>
                        </tr>
                      </thead>
                      <tbody>
                        {data.coquimbo.disponibilidad.detalle.map((d) => (
                          <tr key={d.activo_id} className="border-t">
                            <td className="px-2 py-1">
                              <span className="font-medium">{d.codigo}</span>
                              {d.patente && <span className="ml-1 text-muted-foreground">{d.patente}</span>}
                            </td>
                            <td className="px-2 py-1 text-right text-muted-foreground">{d.dias_obs}</td>
                            <td className="px-2 py-1 text-right">{d.dias_down}</td>
                            <td className={`px-2 py-1 text-right font-semibold
                              ${(d.disponibilidad_pct ?? 0) >= 90 ? 'text-emerald-600'
                                : (d.disponibilidad_pct ?? 0) >= 80 ? 'text-amber-600' : 'text-red-600'}`}>
                              {pct(d.disponibilidad_pct)}
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                </CardContent>
              </Card>

              <Card>
                <CardHeader className="pb-2">
                  <CardTitle className="flex items-center gap-2 text-base">
                    <TrendingDown className="h-4 w-4" />
                    Equipos con mayor tiempo detenido
                  </CardTitle>
                  <p className="text-xs text-muted-foreground">
                    Toca un equipo para escribir el plan de acción a seguir.
                  </p>
                </CardHeader>
                <CardContent className="space-y-2">
                  {data.coquimbo.detenidos.length === 0 && (
                    <p className="py-4 text-center text-sm text-muted-foreground">
                      Ningún equipo con días detenidos en el mes.
                    </p>
                  )}
                  {data.coquimbo.detenidos.map((e) => (
                    <FilaDetenido
                      key={e.activo_id} e={e}
                      guardando={guardar.isPending}
                      onGuardar={(activoId, v) => guardar.mutate({
                        semana, ambito: 'equipo', activoId,
                        texto: v.texto, planAccion: v.planAccion,
                        responsable: v.responsable, fechaCompromiso: v.fechaCompromiso || null,
                      })}
                    />
                  ))}
                </CardContent>
              </Card>

              <Card>
                <CardHeader className="pb-2">
                  <CardTitle className="flex items-center gap-2 text-base">
                    <Fuel className="h-4 w-4" /> Control de combustible
                  </CardTitle>
                </CardHeader>
                <CardContent className="space-y-3">
                  {data.coquimbo.combustible.faenas.length === 0 && (
                    <p className="py-3 text-center text-sm text-muted-foreground">
                      No hay cierre de combustible cargado para este mes.
                    </p>
                  )}
                  <div className="grid gap-3 sm:grid-cols-2">
                    {data.coquimbo.combustible.faenas.map((f) => (
                      <FaenaCombustible key={f.codigo} f={f} />
                    ))}
                  </div>
                  <BrechaTrazabilidad c={data.coquimbo.combustible} />
                </CardContent>
              </Card>

              <ComentarioEditor
                titulo="Comentario del cuadrante Coquimbo"
                comentario={data.coquimbo.comentario}
                guardando={guardar.isPending}
                onGuardar={(v) => guardar.mutate({
                  semana, ambito: 'cuadrante', cuadrante: 'coquimbo', texto: v.texto,
                })}
              />
            </div>

            {/* ══ CUADRANTE CALAMA ══ */}
            <div className="space-y-3">
              <div className="flex items-center gap-2 rounded-lg bg-orange-700 px-3 py-2 text-white">
                <Mountain className="h-5 w-5" />
                <h2 className="text-lg font-bold">Calama</h2>
                <span className="ml-auto text-sm opacity-90">
                  Contrato ENEX · {fmtClp(data.calama.facturacion_total)}/mes
                </span>
              </div>

              {data.calama.faenas_sin_plan > 0 && (
                <div className="flex items-start gap-2 rounded-lg border border-amber-300 bg-amber-50 px-3 py-2 text-xs text-amber-900">
                  <FileWarning className="mt-0.5 h-4 w-4 shrink-0" />
                  <span>
                    <b>{data.calama.faenas_sin_plan} de {data.calama.faenas.length} faenas sin plan cargado.</b>{' '}
                    Representan{' '}
                    {fmtClp(data.calama.faenas.filter((f) => f.sin_plan)
                      .reduce((a, f) => a + (f.facturacion_mensual ?? 0), 0))}/mes
                    de facturación sin control de avance. Terminar el plan es lo que
                    enciende estos cuadrantes.
                  </span>
                </div>
              )}

              <Card>
                <CardHeader className="pb-2">
                  <CardTitle className="text-base">Avance del mes por faena</CardTitle>
                  <p className="text-xs text-muted-foreground">
                    Toca una faena para ver el detalle y dejar el plan de acción.
                  </p>
                </CardHeader>
                <CardContent className="space-y-2">
                  {data.calama.faenas.map((f) => (
                    <FaenaEnexCard
                      key={f.faena_id} f={f}
                      guardando={guardar.isPending}
                      onGuardar={(faenaId, v) => guardar.mutate({
                        semana, ambito: 'faena_enex', enexFaenaId: faenaId,
                        texto: v.texto, planAccion: v.planAccion,
                        responsable: v.responsable, fechaCompromiso: v.fechaCompromiso || null,
                      })}
                    />
                  ))}
                </CardContent>
              </Card>

              <Card>
                <CardHeader className="pb-2">
                  <CardTitle className="flex items-center gap-2 text-base">
                    <Wrench className="h-4 w-4" /> Taller y flota Calama
                  </CardTitle>
                </CardHeader>
                <CardContent className="space-y-3">
                  <TallerBloque t={data.calama.taller} />
                  <div className="grid grid-cols-2 gap-2">
                    <Metric label="Equipos" value={data.calama.disponibilidad.equipos} />
                    <Metric label="Disponibilidad" value={pct(data.calama.disponibilidad.promedio)}
                      tone={(data.calama.disponibilidad.promedio ?? 0) >= 90 ? 'ok'
                        : (data.calama.disponibilidad.promedio ?? 0) >= 80 ? 'warn' : 'bad'} />
                  </div>
                  {data.calama.detenidos.length > 0 && (
                    <div className="space-y-2">
                      <div className="text-xs font-medium text-muted-foreground">
                        Equipos detenidos
                      </div>
                      {data.calama.detenidos.map((e) => (
                        <FilaDetenido
                          key={e.activo_id} e={e}
                          guardando={guardar.isPending}
                          onGuardar={(activoId, v) => guardar.mutate({
                            semana, ambito: 'equipo', activoId,
                            texto: v.texto, planAccion: v.planAccion,
                            responsable: v.responsable, fechaCompromiso: v.fechaCompromiso || null,
                          })}
                        />
                      ))}
                    </div>
                  )}
                </CardContent>
              </Card>

              <ComentarioEditor
                titulo="Comentario del cuadrante Calama"
                comentario={data.calama.comentario}
                guardando={guardar.isPending}
                onGuardar={(v) => guardar.mutate({
                  semana, ambito: 'cuadrante', cuadrante: 'calama', texto: v.texto,
                })}
              />
            </div>
          </div>

          {/* ── COMENTARIOS DE LA SEMANA ─────────────────────────────────── */}
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="flex items-center gap-2 text-base">
                <MessageSquare className="h-4 w-4" />
                Comentarios de la semana
              </CardTitle>
              <p className="text-xs text-muted-foreground">
                Lo que hay que decir de esta semana completa, más allá de cada
                cuadrante. Es lo que encabeza el correo al Gerente General.
              </p>
            </CardHeader>
            <CardContent>
              <ComentarioEditor
                titulo={`Semana ${rango}`}
                comentario={data.comentario_semana}
                guardando={guardar.isPending}
                onGuardar={(v) => guardar.mutate({
                  semana, ambito: 'semana', texto: v.texto,
                })}
              />
            </CardContent>
          </Card>

          <p className="text-center text-[11px] text-muted-foreground">
            Generado {new Date(data.semana.generado_at).toLocaleString('es-CL')} ·
            disponibilidad calculada del {fmtFecha(data.semana.mes_inicio)} al {fmtFecha(data.semana.mes_fin)}
          </p>
        </>
      )}
    </div>
  )
}
