'use client'

import { ArrowDownRight, ArrowRight, ArrowUpRight, Database, Info } from 'lucide-react'
import { useState } from 'react'
import Link from 'next/link'
import type { CalidadDato, PanelResumen } from '@/lib/services/panel-gerencia'
import { fmtClpCorto, fmtFecha, fmtNum, pct } from './comunes'

// ============================================================================
// Portada — los seis números del negocio completo (MIG305)
// ----------------------------------------------------------------------------
// La regla de esta franja: cada tarjeta responde una pregunta de gerencia y
// trae SIEMPRE su comparación. Un 84,8% suelto no significa nada; un 84,8%
// contra 85,1% del mes anterior con meta 90% ya es una conversación.
// ============================================================================

type Tono = 'ok' | 'warn' | 'bad' | 'neutral'

const TONO_BORDE: Record<Tono, string> = {
  ok:      'border-emerald-200 bg-emerald-50/60',
  warn:    'border-amber-200 bg-amber-50/60',
  bad:     'border-red-200 bg-red-50/60',
  neutral: 'border-border bg-card',
}
const TONO_VALOR: Record<Tono, string> = {
  ok: 'text-emerald-700', warn: 'text-amber-700',
  bad: 'text-red-700', neutral: 'text-foreground',
}

/**
 * `mejorEsMas` decide de qué color pintar la flecha. Sin este dato una subida
 * de NC abiertas se vería verde, que es exactamente al revés.
 */
function Delta({ actual, anterior, sufijo = '', mejorEsMas = true, decimales = 1 }: {
  actual: number | null | undefined
  anterior: number | null | undefined
  sufijo?: string
  mejorEsMas?: boolean
  decimales?: number
}) {
  if (actual == null || anterior == null) {
    return <span className="text-[11px] text-muted-foreground">sin base de comparación</span>
  }
  const d = actual - anterior
  // Umbral de indiferencia: variaciones bajo 0,05 son ruido de redondeo.
  const plano = Math.abs(d) < 0.05
  const bueno = mejorEsMas ? d > 0 : d < 0
  const color = plano ? 'text-muted-foreground' : bueno ? 'text-emerald-600' : 'text-red-600'
  const Icono = plano ? ArrowRight : d > 0 ? ArrowUpRight : ArrowDownRight
  return (
    <span className={`inline-flex items-center gap-0.5 text-[11px] font-medium ${color}`}>
      <Icono className="h-3 w-3" />
      {plano ? 'igual' : `${d > 0 ? '+' : ''}${d.toFixed(decimales).replace('.', ',')}${sufijo}`}
      <span className="font-normal text-muted-foreground"> vs mes ant.</span>
    </span>
  )
}

function Kpi({ etiqueta, valor, tono = 'neutral', pie, delta, href }: {
  etiqueta: string
  valor: string
  tono?: Tono
  pie?: React.ReactNode
  delta?: React.ReactNode
  href?: string
}) {
  const cuerpo = (
    <div className={`h-full rounded-xl border px-3 py-2.5 ${TONO_BORDE[tono]}
                     ${href ? 'transition-colors hover:brightness-[0.98]' : ''}`}>
      <div className="text-[10px] font-semibold uppercase tracking-wide text-muted-foreground">
        {etiqueta}
      </div>
      <div className={`mt-0.5 text-2xl font-bold leading-none ${TONO_VALOR[tono]}`}>{valor}</div>
      <div className="mt-1 space-y-0.5">
        {delta}
        {pie && <div className="text-[11px] leading-tight text-muted-foreground">{pie}</div>}
      </div>
    </div>
  )
  return href ? <Link href={href} className="block h-full">{cuerpo}</Link> : cuerpo
}

export function FranjaKpi({ r }: { r: PanelResumen }) {
  const disp = r.disponibilidad
  const dispTono: Tono = disp.actual == null ? 'neutral'
    : disp.actual >= disp.meta ? 'ok' : disp.actual >= 80 ? 'warn' : 'bad'

  // Flujo de taller: lo que importa no es el stock de OT sino si se cierra más
  // de lo que se abre. Bajo 1 el backlog crece por definición.
  const ratio = r.taller.creadas > 0 ? r.taller.cerradas / r.taller.creadas : null
  const tallerTono: Tono = ratio == null ? 'neutral'
    : ratio >= 1 ? 'ok' : ratio >= 0.6 ? 'warn' : 'bad'

  const enexTono: Tono = r.enex.actual == null ? 'neutral'
    : r.enex.actual >= 90 ? 'ok' : r.enex.actual >= 60 ? 'warn' : 'bad'

  const flucPct = r.combustible.fluctuacion_peor_pct != null
    ? r.combustible.fluctuacion_peor_pct * 100 : null
  const combTono: Tono = r.combustible.con_cierre === 0 ? 'neutral'
    : r.combustible.puntos_fuera > 0 ? 'bad' : 'ok'

  const compTono: Tono = r.compromisos.vencidos > 0 ? 'bad'
    : r.compromisos.pendientes > 0 ? 'warn' : 'ok'

  return (
    <div className="grid grid-cols-2 gap-2 md:grid-cols-3 xl:grid-cols-6">
      <Kpi
        etiqueta="Disponibilidad flota"
        valor={pct(disp.actual)}
        tono={dispTono}
        delta={<Delta actual={disp.actual} anterior={disp.anterior} sufijo=" pts" />}
        pie={`meta ${disp.meta}% · ${disp.bajo_meta} de ${disp.equipos} equipos bajo meta`}
        href="/dashboard/fiabilidad"
      />

      <Kpi
        etiqueta="OT cerradas / creadas"
        valor={`${r.taller.cerradas}/${r.taller.creadas}`}
        tono={tallerTono}
        delta={<Delta actual={r.taller.cerradas} anterior={r.taller.cerradas_ant}
          decimales={0} sufijo=" cerradas" />}
        pie={`${r.taller.abiertas_total} abiertas · ${r.taller.arrastre} arrastradas`}
        href="/dashboard/mantenimiento/plan-semanal-taller"
      />

      <Kpi
        etiqueta="No conformidades"
        valor={fmtNum(r.nc.abiertas)}
        tono={r.nc.criticas > 0 ? 'warn' : 'ok'}
        delta={<Delta actual={r.nc.creadas} anterior={r.nc.creadas_ant}
          decimales={0} sufijo=" detectadas" mejorEsMas />}
        pie={`${r.nc.criticas} de severidad alta sin resolver`}
        href="/dashboard/mantenimiento/no-conformidades"
      />

      <Kpi
        etiqueta="Contrato ENEX"
        valor={pct(r.enex.actual)}
        tono={enexTono}
        delta={<Delta actual={r.enex.actual} anterior={r.enex.anterior} sufijo=" pts" />}
        pie={r.enex.sin_plan > 0
          ? `${r.enex.sin_plan} de ${r.enex.faenas} faenas sin plan · ${fmtClpCorto(r.enex.facturacion_sin_control)}/mes sin control`
          : `${r.enex.faenas} faenas · ${fmtClpCorto(r.enex.facturacion_total)}/mes`}
        href="/dashboard/enex"
      />

      <Kpi
        etiqueta="Combustible"
        valor={r.combustible.con_cierre === 0 ? 'sin cierre' : `${fmtNum(r.combustible.litros)} L`}
        tono={combTono}
        delta={r.combustible.litros_ant > 0
          ? <Delta actual={r.combustible.litros} anterior={r.combustible.litros_ant}
              decimales={0} sufijo=" L" mejorEsMas={false} />
          : <span className="text-[11px] text-muted-foreground">mes anterior sin cierre cargado</span>}
        pie={flucPct != null
          ? `peor fluctuación ${flucPct.toFixed(2).replace('.', ',')}% · ${r.combustible.puntos_fuera} estanque(s) sobre 0,5%`
          : 'fluctuación no declarada'}
        href="/dashboard/combustible/control"
      />

      <Kpi
        etiqueta="Compromisos"
        valor={r.compromisos.vencidos > 0
          ? `${r.compromisos.vencidos} vencidos`
          : `${r.compromisos.pendientes} pend.`}
        tono={compTono}
        pie={`${r.compromisos.pendientes} pendientes · ${r.compromisos.cumplidos} cumplidos esta semana`}
      />
    </div>
  )
}

/**
 * Calidad del dato. Colapsada por defecto a una sola línea: cuando está en
 * verde no debe robar espacio a los KPI, pero cuando el planificador dejó de
 * cargar tiene que gritar, porque invalida todo lo que está más abajo.
 */
export function BandaCalidad({ c }: { c: CalidadDato }) {
  const [abierto, setAbierto] = useState(false)
  const alerta = c.dias_rezago > 1 || (c.cobertura_pct ?? 100) < 95

  return (
    <div className={`rounded-lg border px-3 py-1.5 text-xs
      ${alerta ? 'border-amber-300 bg-amber-50 text-amber-900'
               : 'border-emerald-200 bg-emerald-50/70 text-emerald-900'}`}>
      <button onClick={() => setAbierto((v) => !v)}
        className="flex w-full flex-wrap items-center gap-x-4 gap-y-1 text-left">
        <span className="flex items-center gap-1.5 font-medium">
          <Database className="h-3.5 w-3.5" />
          Calidad del dato
        </span>
        <span>
          {alerta
            ? `Rezago de ${c.dias_rezago} día${c.dias_rezago === 1 ? '' : 's'} · cobertura ${pct(c.cobertura_pct)}`
            : `Al día · último cargado ${fmtFecha(c.ultimo_dia)} · cobertura ${pct(c.cobertura_pct)}`}
        </span>
        {c.sugerencias_pendientes > 0 && (
          <span className="font-semibold">{c.sugerencias_pendientes} sugerencias por aplicar</span>
        )}
        <Info className="ml-auto h-3.5 w-3.5 opacity-60" />
      </button>

      {abierto && (
        <div className="mt-2 space-y-1 border-t pt-2 text-[11px]">
          <div className="flex flex-wrap gap-x-4 gap-y-1">
            <span>Último día cargado: <b>{fmtFecha(c.ultimo_dia)}</b></span>
            <span>Días cargados: <b>{c.dias_cargados}/{c.dias_transcurridos}</b></span>
            <span>Equipos el último día: <b>{c.equipos_ultimo_dia ?? '—'}</b></span>
            <span>Carga manual: <b>{c.carga_manual}</b> · automática: <b>{c.carga_auto}</b></span>
          </div>
          <p>
            El estado diario lo carga el planificador a mano en{' '}
            <Link href="/dashboard/flota/sugerencias" className="underline">
              Sugerencias de estado
            </Link>. Los días sin cargar no se cuentan: la disponibilidad del mes
            está calculada sobre {c.dias_cargados} días, no {c.dias_transcurridos}.
          </p>
        </div>
      )}
    </div>
  )
}
