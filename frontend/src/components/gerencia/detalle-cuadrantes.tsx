'use client'

import { useState } from 'react'
import {
  AlertTriangle, Building2, CalendarDays, CheckCircle2, ChevronDown, ChevronRight,
  Clock, FileWarning, Fuel, Mountain, Pencil, Save, TrendingDown, Wrench,
} from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { useCorregirResumenCombustible, useCorregirFluctuacion } from '@/hooks/use-panel-gerencia'
import type {
  CierreCombustibleFaena, CombustibleCoquimbo, EquipoDetenido,
  EquipoDisponibilidad, FaenaEnex, PanelGerencia, PanelTaller,
} from '@/lib/services/panel-gerencia'
import {
  aNum, ComentarioEditor, ESTADO_LABEL, fmtClp, fmtFecha, Metric, pct,
} from './comunes'

// ============================================================================
// Detalle por cuadrante — el material de respaldo (MIG295-297, reordenado)
// ----------------------------------------------------------------------------
// Todo esto ya existía; lo que cambia es su lugar. Antes era la primera —y
// única— cosa que se veía al abrir el panel. Ahora vive colapsado debajo de la
// portada: se abre cuando alguien pregunta "¿de dónde sale ese número?".
// ============================================================================

type GuardarPlan = (v: {
  texto: string; planAccion: string; responsable: string; fechaCompromiso: string
}) => void

/**
 * Taller. Dos bloques deliberadamente separados: lo que produjo el proceso
 * digital este mes, y el arrastre heredado. Sumarlos hacía ver 50 OT abiertas
 * como si el checklist digital las hubiera generado, cuando 43 vienen de junio
 * y julio.
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
 * Formulario de corrección manual. El motivo es obligatorio —lo exige también
 * la base— porque este número llega al Gerente General y alguien tiene que
 * responder por él. Los campos vacíos no se tocan: se corrige la fluctuación
 * sin reescribir los litros.
 */
function CorreccionManual({
  titulo, ayuda, campos, onGuardar, guardando, error,
}: {
  titulo: string
  ayuda?: string
  campos: { key: string, label: string, valor: string, sufijo?: string }[]
  guardando: boolean
  error?: string | null
  onGuardar: (valores: Record<string, string>, motivo: string) => void
}) {
  const [abierto, setAbierto] = useState(false)
  const [vals, setVals] = useState<Record<string, string>>(
    () => Object.fromEntries(campos.map((c) => [c.key, c.valor])))
  const [motivo, setMotivo] = useState('')

  if (!abierto) {
    return (
      <button onClick={() => setAbierto(true)}
        className="flex items-center gap-1 text-[11px] font-medium text-blue-700 underline">
        <Pencil className="h-3 w-3" /> Corregir a mano
      </button>
    )
  }

  return (
    <div className="space-y-2 rounded-lg border-2 border-blue-300 bg-blue-50/60 p-3">
      <div className="text-xs font-semibold text-blue-900">{titulo}</div>
      {ayuda && <p className="text-[11px] text-blue-800">{ayuda}</p>}

      <div className="grid gap-2 sm:grid-cols-2">
        {campos.map((c) => (
          <label key={c.key} className="block">
            <span className="text-[10px] uppercase text-muted-foreground">{c.label}</span>
            <div className="flex items-center gap-1">
              <Input
                value={vals[c.key] ?? ''}
                onChange={(e) => setVals((v) => ({ ...v, [c.key]: e.target.value }))}
                inputMode="decimal"
                placeholder="—"
                className="h-8 text-sm"
              />
              {c.sufijo && <span className="text-[11px] text-muted-foreground">{c.sufijo}</span>}
            </div>
          </label>
        ))}
      </div>

      <label className="block">
        <span className="text-[10px] uppercase text-muted-foreground">
          Motivo de la corrección (obligatorio)
        </span>
        <textarea
          value={motivo}
          onChange={(e) => setMotivo(e.target.value)}
          rows={2}
          placeholder="Ej.: el cierre de la planilla no incluía el trasvasije del día 12"
          className="w-full resize-y rounded-md border bg-background px-2 py-1.5 text-sm
                     focus:outline-none focus:ring-2 focus:ring-ring"
        />
      </label>

      {error && (
        <div className="rounded bg-red-100 px-2 py-1 text-[11px] text-red-800">{error}</div>
      )}

      <div className="flex justify-end gap-2">
        <Button size="sm" variant="outline" onClick={() => { setAbierto(false); setMotivo('') }}>
          Cancelar
        </Button>
        <Button size="sm" variant="primary"
          disabled={guardando || motivo.trim().length === 0}
          onClick={() => onGuardar(vals, motivo.trim())}>
          <Save className="mr-1 h-3.5 w-3.5" />
          {guardando ? 'Guardando…' : 'Guardar corrección'}
        </Button>
      </div>
    </div>
  )
}

/**
 * Cierre mensual de combustible de una faena. Los litros vienen de la planilla
 * de operación, no del sistema, así que la tarjeta declara siempre el archivo
 * de origen: un número de gerencia sin dueño no se puede defender en reunión.
 */
function FaenaCombustible({ f, periodo, semana }: {
  f: CierreCombustibleFaena
  periodo: { anio: number, mes: number }
  semana: string
}) {
  const [abierto, setAbierto] = useState(false)
  const corregirResumen = useCorregirResumenCombustible(semana)
  const corregirPunto = useCorregirFluctuacion(semana)
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

      {/* ── Fluctuación por estanque ── */}
      {f.puntos.length > 0 && (
        <div className="space-y-1.5 rounded-md border bg-muted/30 p-2">
          <div className="text-[10px] font-semibold uppercase text-muted-foreground">
            Fluctuación por estanque
          </div>
          {f.puntos.map((pt) => {
            const p = pt.fluctuacion_pct != null ? pt.fluctuacion_pct * 100 : null
            const fuera = p != null && Math.abs(p) > 0.5
            return (
              <div key={pt.punto} className="rounded border bg-card px-2 py-1.5">
                <div className="flex items-center justify-between gap-2">
                  <div className="flex min-w-0 items-center gap-1.5">
                    <span className="truncate text-xs font-medium">{pt.punto}</span>
                    {pt.corregido_manual && (
                      <span className="rounded bg-blue-100 px-1 text-[9px] font-semibold text-blue-800">
                        MANUAL
                      </span>
                    )}
                  </div>
                  <span className={`shrink-0 text-sm font-bold ${
                    p == null ? 'text-muted-foreground' : fuera ? 'text-red-600' : 'text-emerald-600'}`}>
                    {p == null ? 'sin dato' : `${p.toFixed(2)}%`}
                  </span>
                </div>
                <div className="text-[10px] text-muted-foreground">
                  {pt.fluctuacion_lt != null && <>{pt.fluctuacion_lt} L · </>}
                  {pt.litros_despachados != null
                    && <>{Math.round(pt.litros_despachados).toLocaleString('es-CL')} L despachados · </>}
                  {pt.dias_cuadrados} días
                </div>
                {pt.observacion && (
                  <div className="mt-1 rounded bg-amber-50 px-1.5 py-1 text-[10px] text-amber-900">
                    {pt.observacion}
                  </div>
                )}
                <div className="mt-1">
                  <CorreccionManual
                    titulo={`Corregir fluctuación — ${pt.punto}`}
                    ayuda="Deja en blanco lo que no quieras cambiar. Si das litros de fluctuación y litros despachados, el porcentaje se calcula solo."
                    guardando={corregirPunto.isPending}
                    error={corregirPunto.error?.message}
                    campos={[
                      { key: 'fl', label: 'Fluctuación', valor: pt.fluctuacion_lt?.toString() ?? '', sufijo: 'L' },
                      { key: 'de', label: 'Despachados', valor: pt.litros_despachados?.toString() ?? '', sufijo: 'L' },
                      { key: 'pc', label: 'Fluctuación', valor: p != null ? p.toFixed(2) : '', sufijo: '%' },
                      { key: 'di', label: 'Días cuadrados', valor: pt.dias_cuadrados?.toString() ?? '' },
                    ]}
                    onGuardar={(v, motivo) => corregirPunto.mutate({
                      faenaCodigo: f.codigo, anio: periodo.anio, mes: periodo.mes,
                      punto: pt.punto,
                      fluctuacionLt: aNum(v.fl),
                      litrosDespachados: aNum(v.de),
                      // La UI habla en %, la base guarda fracción.
                      fluctuacionPct: aNum(v.pc) != null ? aNum(v.pc)! / 100 : null,
                      diasCuadrados: aNum(v.di),
                      motivo,
                    })}
                  />
                </div>
              </div>
            )
          })}
        </div>
      )}

      {/* ── Corrección del total de la faena ── */}
      <CorreccionManual
        titulo={`Corregir cierre — ${f.nombre}`}
        ayuda="Corrige el total de la faena. Solo se modifica lo que escribas; el resto queda como vino de la planilla."
        guardando={corregirResumen.isPending}
        error={corregirResumen.error?.message}
        campos={[
          { key: 'lv', label: 'Litros venta', valor: String(Math.round(f.litros_venta)), sufijo: 'L' },
          { key: 'lt', label: 'Litros trasvasije', valor: String(Math.round(f.litros_trasvasije)), sufijo: 'L' },
          { key: 'fl', label: 'Fluctuación', valor: f.fluctuacion_lt?.toString() ?? '', sufijo: 'L' },
          { key: 'fp', label: 'Fluctuación', valor: fluctPct != null ? fluctPct.toFixed(3) : '', sufijo: '%' },
        ]}
        onGuardar={(v, motivo) => corregirResumen.mutate({
          faenaCodigo: f.codigo, anio: periodo.anio, mes: periodo.mes,
          litrosVenta: aNum(v.lv),
          litrosTrasvasije: aNum(v.lt),
          fluctuacionLt: aNum(v.fl),
          fluctuacionPct: aNum(v.fp) != null ? aNum(v.fp)! / 100 : null,
          motivo,
        })}
      />

      {f.corregido_manual && (
        <div className="rounded bg-blue-50 px-2 py-1 text-[10px] text-blue-900">
          <b>Corregido a mano</b>
          {f.corregido_por_nombre ? ` por ${f.corregido_por_nombre}` : ''}
          {f.corregido_at ? ` el ${fmtFecha(f.corregido_at.slice(0, 10))}` : ''}.
          {f.motivo_correccion && <> Motivo: {f.motivo_correccion}</>}
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

function TablaDisponibilidad({ detalle }: { detalle: EquipoDisponibilidad[] }) {
  return (
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
          {detalle.map((d) => (
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
  )
}

/**
 * Envoltorio colapsable. El encabezado tiene que valer por sí solo: si hay que
 * abrirlo para saber si el cuadrante está bien o mal, el colapso no sirvió de
 * nada.
 */
function Cuadrante({ titulo, icono: Icono, color, resumen, children, abiertoInicial = false }: {
  titulo: string
  icono: typeof Building2
  color: string
  resumen: React.ReactNode
  children: React.ReactNode
  abiertoInicial?: boolean
}) {
  const [abierto, setAbierto] = useState(abiertoInicial)
  return (
    <div className="space-y-3">
      <button onClick={() => setAbierto((v) => !v)}
        className={`flex w-full items-center gap-2 rounded-lg px-3 py-2 text-white ${color}`}>
        {abierto ? <ChevronDown className="h-4 w-4" /> : <ChevronRight className="h-4 w-4" />}
        <Icono className="h-5 w-5" />
        <h2 className="text-lg font-bold">{titulo}</h2>
        <span className="ml-auto text-right text-xs opacity-90 sm:text-sm">{resumen}</span>
      </button>
      {abierto && children}
    </div>
  )
}

// ── Coquimbo ───────────────────────────────────────────────────────────────
export function CuadranteCoquimbo({ data, semana, guardando, onGuardarEquipo, onGuardarCuadrante }: {
  data: PanelGerencia
  semana: string
  guardando: boolean
  onGuardarEquipo: (activoId: string, v: Parameters<GuardarPlan>[0]) => void
  onGuardarCuadrante: (v: Parameters<GuardarPlan>[0]) => void
}) {
  const c = data.coquimbo
  return (
    <Cuadrante
      titulo="Coquimbo"
      icono={Building2}
      color="bg-blue-700"
      resumen={`${c.disponibilidad.equipos} equipos · disponibilidad ${pct(c.disponibilidad.promedio)} · ${c.taller.ot_abiertas} OT abiertas`}
    >
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="flex items-center gap-2 text-base">
            <Wrench className="h-4 w-4" /> Taller
          </CardTitle>
        </CardHeader>
        <CardContent><TallerBloque t={c.taller} /></CardContent>
      </Card>

      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="flex items-center gap-2 text-base">
            <CalendarDays className="h-4 w-4" /> Disponibilidad del mes
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-2">
          <div className="grid grid-cols-3 gap-2">
            <Metric label="Promedio" value={pct(c.disponibilidad.promedio)}
              tone={(c.disponibilidad.promedio ?? 0) >= 90 ? 'ok'
                : (c.disponibilidad.promedio ?? 0) >= 80 ? 'warn' : 'bad'} />
            <Metric label="Equipos" value={c.disponibilidad.equipos} />
            <Metric label="Bajo 90%" value={c.disponibilidad.bajo_90}
              tone={c.disponibilidad.bajo_90 > 0 ? 'warn' : 'ok'} />
          </div>
          <TablaDisponibilidad detalle={c.disponibilidad.detalle} />
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="flex items-center gap-2 text-base">
            <TrendingDown className="h-4 w-4" /> Equipos con mayor tiempo detenido
          </CardTitle>
          <p className="text-xs text-muted-foreground">
            Toca un equipo para escribir el plan de acción a seguir.
          </p>
        </CardHeader>
        <CardContent className="space-y-2">
          {c.detenidos.length === 0 && (
            <p className="py-4 text-center text-sm text-muted-foreground">
              Ningún equipo con días detenidos en el mes.
            </p>
          )}
          {c.detenidos.map((e) => (
            <FilaDetenido key={e.activo_id} e={e} guardando={guardando}
              onGuardar={onGuardarEquipo} />
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
          {c.combustible.faenas.length === 0 && (
            <p className="py-3 text-center text-sm text-muted-foreground">
              No hay cierre de combustible cargado para este mes.
            </p>
          )}
          <div className="grid gap-3 sm:grid-cols-2">
            {c.combustible.faenas.map((f) => (
              <FaenaCombustible key={f.codigo} f={f}
                periodo={c.combustible.periodo} semana={semana} />
            ))}
          </div>
          <BrechaTrazabilidad c={c.combustible} />
        </CardContent>
      </Card>

      <ComentarioEditor
        titulo="Comentario del cuadrante Coquimbo"
        comentario={c.comentario}
        guardando={guardando}
        onGuardar={onGuardarCuadrante}
      />
    </Cuadrante>
  )
}

// ── Calama ─────────────────────────────────────────────────────────────────
export function CuadranteCalama({ data, guardando, onGuardarEquipo, onGuardarFaena, onGuardarCuadrante }: {
  data: PanelGerencia
  guardando: boolean
  onGuardarEquipo: (activoId: string, v: Parameters<GuardarPlan>[0]) => void
  onGuardarFaena: (faenaId: string, v: Parameters<GuardarPlan>[0]) => void
  onGuardarCuadrante: (v: Parameters<GuardarPlan>[0]) => void
}) {
  const c = data.calama
  return (
    <Cuadrante
      titulo="Calama"
      icono={Mountain}
      color="bg-orange-700"
      resumen={`Contrato ENEX ${fmtClp(c.facturacion_total)}/mes · ${c.faenas.length - c.faenas_sin_plan}/${c.faenas.length} faenas con plan`}
    >
      {c.faenas_sin_plan > 0 && (
        <div className="flex items-start gap-2 rounded-lg border border-amber-300 bg-amber-50 px-3 py-2 text-xs text-amber-900">
          <FileWarning className="mt-0.5 h-4 w-4 shrink-0" />
          <span>
            <b>{c.faenas_sin_plan} de {c.faenas.length} faenas sin plan cargado.</b>{' '}
            Representan{' '}
            {fmtClp(c.faenas.filter((f) => f.sin_plan)
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
          {c.faenas.map((f) => (
            <FaenaEnexCard key={f.faena_id} f={f} guardando={guardando}
              onGuardar={onGuardarFaena} />
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
          <TallerBloque t={c.taller} />
          <div className="grid grid-cols-3 gap-2">
            <Metric label="Equipos" value={c.disponibilidad.equipos} />
            <Metric label="Disponibilidad" value={pct(c.disponibilidad.promedio)}
              tone={(c.disponibilidad.promedio ?? 0) >= 90 ? 'ok'
                : (c.disponibilidad.promedio ?? 0) >= 80 ? 'warn' : 'bad'} />
            <Metric label="Bajo 90%" value={c.disponibilidad.bajo_90 ?? 0}
              tone={(c.disponibilidad.bajo_90 ?? 0) > 0 ? 'warn' : 'ok'} />
          </div>
          {c.disponibilidad.detalle?.length > 0 && (
            <TablaDisponibilidad detalle={c.disponibilidad.detalle} />
          )}
          {c.detenidos.length > 0 && (
            <div className="space-y-2">
              <div className="text-xs font-medium text-muted-foreground">Equipos detenidos</div>
              {c.detenidos.map((e) => (
                <FilaDetenido key={e.activo_id} e={e} guardando={guardando}
                  onGuardar={onGuardarEquipo} />
              ))}
            </div>
          )}
        </CardContent>
      </Card>

      <ComentarioEditor
        titulo="Comentario del cuadrante Calama"
        comentario={c.comentario}
        guardando={guardando}
        onGuardar={onGuardarCuadrante}
      />
    </Cuadrante>
  )
}
