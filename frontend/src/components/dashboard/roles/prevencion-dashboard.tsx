'use client'

import Link from 'next/link'
import { useQuery } from '@tanstack/react-query'
import {
  HardHat, ShieldAlert, AlertTriangle, Truck, Footprints,
  ArrowRight, Mail, CheckCircle2, Clock,
} from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Spinner } from '@/components/ui/spinner'
import { supabase } from '@/lib/supabase'

// ============================================================================
// Dashboard de Prevención de Riesgos
// ----------------------------------------------------------------------------
// El prevencionista caía al dashboard genérico, que le mostraba OT, ICEO e
// inventario valorizado — nada de su trabajo, y ningún dato accionable para
// él. Acá ve lo suyo: documental de personal, documental de equipos y sus
// recorridos de terreno, con acceso directo a actuar sobre cada cosa.
// ============================================================================

type Dash = {
  generado_at: string
  personal: {
    personas: number, no_conformes: number, criticos: number, observados: number,
    por_vencer: number, conformes: number, exam_vencidos: number, exam_sin_dato: number
    exam_criticos: number
  }
  personal_urgente: {
    persona: string, rut: string, tipo: string,
    vence: string | null, dias: number | null, estado: string
  }[]
  equipos: { con_vencidos: number, docs_vencidos: number, por_vencer_30: number }
  recorridos: { mis_pendientes: number, del_mes: number, hallazgos_abiertos: number }
  ultimo_envio: { at: string, faena: string | null, destinatarios: string } | null
}

function Kpi({ label, value, tone = 'neutral', sub, href }: {
  label: string
  value: number | string
  tone?: 'bad' | 'warn' | 'ok' | 'neutral'
  sub?: string
  href?: string
}) {
  const color = {
    bad: 'text-red-600', warn: 'text-amber-600',
    ok: 'text-emerald-600', neutral: 'text-foreground',
  }[tone]
  const inner = (
    <div className={`rounded-lg border bg-card px-4 py-3 h-full ${href ? 'transition-colors hover:bg-accent' : ''}`}>
      <div className="text-[11px] uppercase tracking-wide text-muted-foreground">{label}</div>
      <div className={`text-3xl font-bold leading-tight ${color}`}>{value}</div>
      {sub && <div className="text-[11px] text-muted-foreground">{sub}</div>}
    </div>
  )
  return href ? <Link href={href} className="block h-full">{inner}</Link> : inner
}

export function PrevencionDashboard() {
  const { data, isLoading, error } = useQuery({
    queryKey: ['prevencion-dashboard'],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('fn_prevencion_dashboard')
      if (error) throw error
      return data as Dash
    },
    staleTime: 60_000,
  })

  if (isLoading) return <div className="flex justify-center py-20"><Spinner /></div>
  if (error) {
    return (
      <div className="rounded-lg border border-red-300 bg-red-50 px-4 py-3 text-sm text-red-800">
        No se pudo cargar el panel: {(error as Error).message}
      </div>
    )
  }
  if (!data) return null

  const p = data.personal
  const e = data.equipos
  const r = data.recorridos
  const totalBrechas = p.no_conformes + e.con_vencidos

  return (
    <div className="space-y-5">
      <div>
        <h1 className="flex items-center gap-2 text-2xl font-bold">
          <HardHat className="h-6 w-6 text-amber-500" />
          Prevención de Riesgos
        </h1>
        <p className="text-sm text-muted-foreground">
          Control documental de personal y equipos, y recorridos de terreno.
        </p>
      </div>

      {/* Lo que bloquea hoy */}
      {totalBrechas > 0 && (
        <div className="flex items-start gap-2 rounded-lg border border-red-300 bg-red-50 px-4 py-3 text-sm text-red-900">
          <AlertTriangle className="mt-0.5 h-5 w-5 shrink-0" />
          <div>
            <b>{p.no_conformes} persona{p.no_conformes === 1 ? '' : 's'} y {e.con_vencidos} equipo
            {e.con_vencidos === 1 ? '' : 's'} no pueden acreditar documentación al día.</b>
            <div className="mt-0.5 text-[13px]">
              {p.exam_vencidos} exámenes vencidos
              {p.exam_sin_dato > 0 && <> · {p.exam_sin_dato} sin registro</>}
              {' '}· {e.docs_vencidos} documentos de equipo vencidos.
              Es lo primero que mira una auditoría.
            </div>
          </div>
        </div>
      )}

      {/* ── Personal ── */}
      <div>
        <div className="mb-2 flex items-center justify-between">
          <h2 className="flex items-center gap-1.5 text-sm font-semibold uppercase tracking-wide text-muted-foreground">
            <ShieldAlert className="h-4 w-4" /> Documental de personal
          </h2>
          <Link href="/dashboard/prevencion/personal"
            className="flex items-center gap-1 text-xs font-medium text-blue-700 hover:underline">
            Ver y enviar reporte <ArrowRight className="h-3 w-3" />
          </Link>
        </div>
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-5">
          <Kpi label="Personas" value={p.personas} href="/dashboard/prevencion/personal" />
          <Kpi label="No conformes" value={p.no_conformes} tone="bad"
            sub="vencidos o sin dato" href="/dashboard/prevencion/personal" />
          <Kpi label="Observados" value={p.observados} tone="warn"
            sub="mandante no acepta" href="/dashboard/prevencion/personal" />
          <Kpi label="Vence esta semana" value={p.exam_criticos} tone="bad"
            sub="≤7 días" href="/dashboard/prevencion/personal" />
          <Kpi label="Conformes" value={p.conformes} tone="ok" />
        </div>

        {data.personal_urgente.length > 0 && (
          <Card className="mt-3">
            <CardHeader className="pb-2">
              <CardTitle className="text-sm">Lo más urgente</CardTitle>
            </CardHeader>
            <CardContent className="space-y-1">
              {data.personal_urgente.map((u, i) => (
                <Link key={`${u.rut}-${u.tipo}-${i}`} href="/dashboard/prevencion/personal"
                  className="flex flex-wrap items-center gap-2 rounded border bg-card px-2.5 py-1.5
                             text-xs transition-colors hover:bg-accent">
                  <span className="min-w-[190px] flex-1 font-medium">{u.persona}</span>
                  <span className="text-muted-foreground">{u.tipo}</span>
                  <span className={`rounded px-1.5 py-0.5 text-[10px] font-semibold
                    ${u.estado === 'vencido' || u.estado === 'sin_dato'
                      ? 'bg-red-100 text-red-800' : 'bg-amber-100 text-amber-800'}`}>
                    {u.dias == null ? 'sin dato'
                      : u.dias < 0 ? `vencido hace ${-u.dias} d` : `en ${u.dias} d`}
                  </span>
                </Link>
              ))}
            </CardContent>
          </Card>
        )}
      </div>

      {/* ── Equipos ── */}
      <div>
        <div className="mb-2 flex items-center justify-between">
          <h2 className="flex items-center gap-1.5 text-sm font-semibold uppercase tracking-wide text-muted-foreground">
            <Truck className="h-4 w-4" /> Documental de equipos
          </h2>
          <Link href="/dashboard/activos"
            className="flex items-center gap-1 text-xs font-medium text-blue-700 hover:underline">
            Ver equipos <ArrowRight className="h-3 w-3" />
          </Link>
        </div>
        <div className="grid grid-cols-3 gap-3">
          <Kpi label="Equipos con vencidos" value={e.con_vencidos} tone={e.con_vencidos > 0 ? 'bad' : 'ok'}
            href="/dashboard/activos" />
          <Kpi label="Documentos vencidos" value={e.docs_vencidos} tone={e.docs_vencidos > 0 ? 'bad' : 'ok'}
            sub="SOAP, rev. técnica, TC8…" href="/dashboard/activos" />
          <Kpi label="Por vencer" value={e.por_vencer_30} tone={e.por_vencer_30 > 0 ? 'warn' : 'ok'}
            sub="≤30 días" href="/dashboard/activos" />
        </div>
      </div>

      {/* ── Recorridos ── */}
      <div>
        <div className="mb-2 flex items-center justify-between">
          <h2 className="flex items-center gap-1.5 text-sm font-semibold uppercase tracking-wide text-muted-foreground">
            <Footprints className="h-4 w-4" /> Recorridos de terreno
          </h2>
          <Link href="/dashboard/gemba"
            className="flex items-center gap-1 text-xs font-medium text-blue-700 hover:underline">
            Ir a mis recorridos <ArrowRight className="h-3 w-3" />
          </Link>
        </div>
        <div className="grid grid-cols-3 gap-3">
          <Kpi label="Me toca hacer" value={r.mis_pendientes}
            tone={r.mis_pendientes > 0 ? 'warn' : 'ok'}
            sub={r.mis_pendientes > 0 ? 'según su cadencia' : 'al día'}
            href="/dashboard/gemba" />
          <Kpi label="Hechos este mes" value={r.del_mes} tone="neutral" href="/dashboard/gemba/reporte" />
          <Kpi label="Hallazgos abiertos" value={r.hallazgos_abiertos}
            tone={r.hallazgos_abiertos > 0 ? 'warn' : 'ok'} href="/dashboard/gemba/reporte" />
        </div>
        {r.mis_pendientes > 0 && (
          <Link href="/dashboard/gemba"
            className="mt-2 flex items-center gap-2 rounded-lg border border-amber-300 bg-amber-50
                       px-3 py-2 text-xs text-amber-900 transition-colors hover:bg-amber-100">
            <Clock className="h-4 w-4 shrink-0" />
            Tienes {r.mis_pendientes} recorrido{r.mis_pendientes === 1 ? '' : 's'} pendiente
            {r.mis_pendientes === 1 ? '' : 's'} según su cadencia.
            <ArrowRight className="ml-auto h-3.5 w-3.5" />
          </Link>
        )}
      </div>

      {/* ── Último envío ── */}
      <div className="flex flex-wrap items-center gap-2 rounded-lg border bg-muted/40 px-3 py-2 text-xs text-muted-foreground">
        <Mail className="h-3.5 w-3.5" />
        {data.ultimo_envio ? (
          <>
            Último reporte enviado el{' '}
            <b className="text-foreground">
              {new Date(data.ultimo_envio.at).toLocaleDateString('es-CL',
                { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' })}
            </b>
            {data.ultimo_envio.faena && <> · {data.ultimo_envio.faena}</>}
            <span className="truncate">a {data.ultimo_envio.destinatarios}</span>
          </>
        ) : (
          <>
            Todavía no se ha enviado ningún reporte a pedido.
            El aviso automático sí corre todos los días.
          </>
        )}
        <Link href="/dashboard/prevencion/personal"
          className="ml-auto font-medium text-blue-700 hover:underline">
          Enviar ahora
        </Link>
      </div>

      <p className="text-center text-[11px] text-muted-foreground">
        <CheckCircle2 className="mr-1 inline h-3 w-3" />
        Actualizado {new Date(data.generado_at).toLocaleString('es-CL')}
      </p>
    </div>
  )
}
