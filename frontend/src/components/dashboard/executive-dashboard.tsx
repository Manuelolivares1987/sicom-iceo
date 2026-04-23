'use client'

import { useMemo } from 'react'
import Link from 'next/link'
import {
  Activity, AlertTriangle, TrendingUp, TrendingDown,
  Gauge as GaugeIcon, Truck, Briefcase, ShieldCheck, ClipboardCheck,
  ArrowUpRight, Clock, Zap,
} from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Spinner } from '@/components/ui/spinner'
import { Badge } from '@/components/ui/badge'
import { cn, todayISO } from '@/lib/utils'
import { useAuth } from '@/contexts/auth-context'
import { useFlotaVehicular, useOEEFlota } from '@/hooks/use-flota'
import { useFiabilidadFlota, useDetalleFiabilidadFlota } from '@/hooks/use-fiabilidad'
import { useAlertasNoLeidas } from '@/hooks/use-alertas'
import { useVerificacionesPendientes } from '@/hooks/use-verificacion'
import { useICEOPeriodo } from '@/hooks/use-kpi-iceo'
import { useQuery } from '@tanstack/react-query'
import { getContratoActivo } from '@/lib/services/contratos'

// ────────────────────────────────────────────────────────────
// Dashboard Ejecutivo — para administrador/gerencia/subgerente/jefe_ops
// ────────────────────────────────────────────────────────────
export function ExecutiveDashboard() {
  const { perfil } = useAuth()

  const hoy = new Date()
  const firstOfMonth = `${hoy.getFullYear()}-${String(hoy.getMonth() + 1).padStart(2, '0')}-01`
  const hoyISO = todayISO()

  // Contrato activo para ICEO
  const { data: contrato } = useQuery({
    queryKey: ['contrato-activo'],
    queryFn: async () => {
      const { data, error } = await getContratoActivo()
      if (error) throw error
      return data
    },
  })
  const contratoId = contrato?.id ?? ''

  const { data: flota, isLoading: loadingFlota } = useFlotaVehicular()
  const { data: oeeHoy } = useOEEFlota(hoyISO, hoyISO)
  const { data: oeeMes } = useOEEFlota(firstOfMonth, hoyISO)
  const { data: detalles = [] } = useDetalleFiabilidadFlota(firstOfMonth, hoyISO)
  const { data: alertasData } = useAlertasNoLeidas()
  const alertas = alertasData ?? []
  const { data: pendientesVerif = [] } = useVerificacionesPendientes()
  const { data: iceoData } = useICEOPeriodo(contratoId)

  // ─── Snapshot de flota (por estado operativo) ───
  const snapshot = useMemo(() => {
    if (!flota) return null
    let operativo = 0, en_mant = 0, fuera = 0
    let arrendados_op = 0, disponibles_op = 0, uso_interno = 0, leasing = 0, sin_cat = 0
    for (const a of flota as any[]) {
      if (a.estado === 'operativo') operativo++
      else if (a.estado === 'en_mantenimiento') en_mant++
      else if (a.estado === 'fuera_servicio') fuera++
      if (a.estado === 'operativo') {
        switch (a.estado_comercial) {
          case 'arrendado':   arrendados_op++; break
          case 'disponible':  disponibles_op++; break
          case 'uso_interno': uso_interno++; break
          case 'leasing':     leasing++; break
          default: sin_cat++
        }
      }
    }
    const total = flota.length
    return {
      total, operativo, en_mant, fuera,
      arrendados_op, disponibles_op, uso_interno, leasing, sin_cat,
      tasa_ocupacion: total > 0 ? ((arrendados_op + uso_interno + leasing) / total) * 100 : 0,
    }
  }, [flota])

  // ─── Rankings rápidos ───
  const top3Criticos = useMemo(
    () => [...detalles]
      .filter((d) => d.dias_down > 0)
      .sort((a, b) => b.dias_down - a.dias_down)
      .slice(0, 3),
    [detalles],
  )
  const top3Mejor = useMemo(
    () => [...detalles]
      .filter((d) => d.oee_total != null && (d.categoria_uso === 'arriendo_comercial' || d.categoria_uso === 'leasing_operativo'))
      .sort((a, b) => (b.oee_total ?? 0) - (a.oee_total ?? 0))
      .slice(0, 3),
    [detalles],
  )

  // ─── Alertas prioritarias (top 5) ───
  const alertasCriticas = useMemo(
    () => alertas.filter((a) => a.severidad === 'critical' || a.severidad === 'warning').slice(0, 5),
    [alertas],
  )

  const iceoScore = Number(iceoData?.iceo_final ?? 0)
  const isLoading = loadingFlota

  return (
    <div className="space-y-6">
      {/* ─── Header ejecutivo ─── */}
      <div className="rounded-2xl bg-gradient-to-r from-slate-800 via-slate-900 to-gray-900 p-6 text-white shadow-xl">
        <div className="flex flex-col gap-2 md:flex-row md:items-center md:justify-between">
          <div>
            <div className="text-xs uppercase tracking-widest text-white/60">Executive Center</div>
            <h1 className="text-2xl font-bold">
              Buen día{perfil?.nombre_completo ? `, ${perfil.nombre_completo.split(' ')[0]}` : ''}
            </h1>
            <p className="text-sm text-white/70 mt-1">
              {new Date().toLocaleDateString('es-CL', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' })}
              {' · '}
              {snapshot?.total ?? 0} equipos · {alertas.length} alertas
            </p>
          </div>
          <div className="flex items-center gap-3">
            <BigMetric
              label="ICEO"
              value={iceoScore > 0 ? `${iceoScore.toFixed(1)}%` : '—'}
              sub={iceoData?.clasificacion ?? 'Sin datos'}
              color={iceoColorClass(iceoScore)}
            />
          </div>
        </div>
      </div>

      {isLoading && (
        <div className="flex h-40 items-center justify-center">
          <Spinner className="h-8 w-8" />
        </div>
      )}

      {!isLoading && (
        <>
          {/* ─── Fila principal de KPIs ─── */}
          <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
            <KpiBig
              label="OEE de Hoy"
              value={fmtPct(oeeHoy?.oee_promedio, 1)}
              hint={`Disp ${fmtPct(oeeHoy?.disponibilidad_promedio, 0)} · Util ${fmtPct(oeeHoy?.utilizacion_promedio, 0)}`}
              icon={<Zap className="h-5 w-5" />}
              color="emerald"
              href="/dashboard/fiabilidad"
            />
            <KpiBig
              label="OEE del Mes"
              value={fmtPct(oeeMes?.oee_promedio, 1)}
              hint={oeeMes?.clasificacion ?? ''}
              icon={<GaugeIcon className="h-5 w-5" />}
              color="blue"
              href="/dashboard/fiabilidad"
            />
            <KpiBig
              label="Disp. Física"
              value={fmtPct(oeeMes?.disponibilidad_promedio, 1)}
              hint="meta ≥ 92%"
              icon={<Activity className="h-5 w-5" />}
              color={
                (oeeMes?.disponibilidad_promedio ?? 0) >= 92 ? 'emerald' :
                (oeeMes?.disponibilidad_promedio ?? 0) >= 85 ? 'amber' : 'red'
              }
              href="/dashboard/flota"
            />
            <KpiBig
              label="Tasa Ocupación"
              value={snapshot ? `${snapshot.tasa_ocupacion.toFixed(1)}%` : '—'}
              hint={`${snapshot?.arrendados_op ?? 0} arrendados · ${snapshot?.disponibles_op ?? 0} libres`}
              icon={<Briefcase className="h-5 w-5" />}
              color="indigo"
              href="/dashboard/comercial"
            />
          </div>

          {/* ─── Estado de Flota (barra apilada) ─── */}
          {snapshot && (
            <Card>
              <CardHeader className="pb-2">
                <CardTitle className="text-base flex items-center justify-between text-gray-700">
                  <span className="flex items-center gap-2">
                    <Truck className="h-5 w-5" />
                    Estado de Flota Ahora
                  </span>
                  <Link href="/dashboard/flota" className="text-xs text-blue-600 hover:underline flex items-center gap-1">
                    Ver detalle <ArrowUpRight className="h-3 w-3" />
                  </Link>
                </CardTitle>
              </CardHeader>
              <CardContent>
                <StackedBar snapshot={snapshot} />
                <div className="mt-3 grid grid-cols-3 md:grid-cols-6 gap-2 text-xs">
                  <LegendCell color="bg-green-500" label="Arrendado" value={snapshot.arrendados_op} />
                  <LegendCell color="bg-amber-500" label="Disponible" value={snapshot.disponibles_op} />
                  <LegendCell color="bg-cyan-500" label="Uso interno" value={snapshot.uso_interno} />
                  <LegendCell color="bg-blue-500" label="Leasing" value={snapshot.leasing} />
                  <LegendCell color="bg-orange-500" label="Mantención" value={snapshot.en_mant} />
                  <LegendCell color="bg-red-500" label="Fuera servicio" value={snapshot.fuera} />
                </div>
              </CardContent>
            </Card>
          )}

          {/* ─── Alertas críticas + Verificaciones pendientes ─── */}
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
            <Card className="border-red-200">
              <CardHeader className="pb-2">
                <CardTitle className="text-base flex items-center justify-between text-red-700">
                  <span className="flex items-center gap-2">
                    <AlertTriangle className="h-5 w-5" />
                    Alertas Críticas ({alertasCriticas.length})
                  </span>
                  {alertas.length > 5 && (
                    <Link href="/dashboard/cumplimiento" className="text-xs text-red-600 hover:underline">
                      Ver todas ({alertas.length})
                    </Link>
                  )}
                </CardTitle>
              </CardHeader>
              <CardContent className="space-y-2">
                {alertasCriticas.length === 0 ? (
                  <p className="text-sm text-gray-400">Sin alertas críticas activas ✓</p>
                ) : (
                  alertasCriticas.map((a, i) => (
                    <div key={i} className="flex items-start gap-2 border-b pb-2 text-sm last:border-0 last:pb-0">
                      <Badge className={a.severidad === 'critical' ? 'bg-red-200 text-red-800' : 'bg-amber-200 text-amber-800'}>
                        {a.severidad === 'critical' ? 'BLOQUEO' : 'ALERTA'}
                      </Badge>
                      <span className="flex-1 text-gray-700">{a.titulo}</span>
                    </div>
                  ))
                )}
              </CardContent>
            </Card>

            <Card className="border-amber-200">
              <CardHeader className="pb-2">
                <CardTitle className="text-base flex items-center justify-between text-amber-700">
                  <span className="flex items-center gap-2">
                    <ShieldCheck className="h-5 w-5" />
                    Verificaciones Pendientes ({pendientesVerif.length})
                  </span>
                </CardTitle>
              </CardHeader>
              <CardContent className="space-y-2">
                {pendientesVerif.length === 0 ? (
                  <p className="text-sm text-gray-400">Sin verificaciones pendientes ✓</p>
                ) : (
                  pendientesVerif.slice(0, 5).map((v) => (
                    <Link
                      key={v.verificacion_id}
                      href={`/dashboard/flota/aprobar/${v.ot_id}`}
                      className="flex items-center justify-between gap-2 rounded border border-amber-100 bg-amber-50/50 p-2 text-sm hover:bg-amber-100"
                    >
                      <div>
                        <div className="font-mono font-semibold">{v.patente}</div>
                        <div className="text-xs text-gray-500">{v.equipo}</div>
                      </div>
                      <div className="text-xs text-amber-700">
                        {v.checklist_progreso
                          ? `${v.checklist_progreso.ok + v.checklist_progreso.na}/${v.checklist_progreso.total}`
                          : '—'}
                        <ArrowUpRight className="inline h-3 w-3 ml-1" />
                      </div>
                    </Link>
                  ))
                )}
              </CardContent>
            </Card>
          </div>

          {/* ─── Rankings Top 3 Crítico + Top 3 OEE ─── */}
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
            <Card>
              <CardHeader className="pb-2">
                <CardTitle className="text-sm text-red-700 flex items-center gap-2">
                  <TrendingDown className="h-4 w-4" />
                  Top 3 Equipos Críticos (Mes)
                </CardTitle>
              </CardHeader>
              <CardContent className="space-y-1">
                {top3Criticos.length === 0 ? (
                  <p className="text-xs text-gray-400">Sin eventos de falla este mes ✓</p>
                ) : (
                  top3Criticos.map((d) => (
                    <MiniRow
                      key={d.activo_id}
                      patente={d.patente}
                      label={d.equipamiento ?? ''}
                      value={`${d.dias_down}d DOWN`}
                      tone="red"
                    />
                  ))
                )}
              </CardContent>
            </Card>

            <Card>
              <CardHeader className="pb-2">
                <CardTitle className="text-sm text-green-700 flex items-center gap-2">
                  <TrendingUp className="h-4 w-4" />
                  Top 3 Mejor OEE (Rentables)
                </CardTitle>
              </CardHeader>
              <CardContent className="space-y-1">
                {top3Mejor.length === 0 ? (
                  <p className="text-xs text-gray-400">Sin datos de OEE</p>
                ) : (
                  top3Mejor.map((d) => (
                    <MiniRow
                      key={d.activo_id}
                      patente={d.patente}
                      label={d.equipamiento ?? ''}
                      value={fmtPct(Number(d.oee_total) * 100, 0)}
                      tone="green"
                    />
                  ))
                )}
              </CardContent>
            </Card>
          </div>

          {/* ─── Atajos a drill-downs ─── */}
          <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
            <ShortcutCard href="/dashboard/flota" icon={<Truck className="h-5 w-5" />} title="Flota" subtitle="Maestro completo" />
            <ShortcutCard href="/dashboard/fiabilidad" icon={<Activity className="h-5 w-5" />} title="Fiabilidad" subtitle="MTBF, MTTR, OEE" />
            <ShortcutCard href="/dashboard/comercial" icon={<Briefcase className="h-5 w-5" />} title="Comercial" subtitle="Tasa arriendo y clientes" />
            <ShortcutCard href="/dashboard/iceo" icon={<GaugeIcon className="h-5 w-5" />} title="ICEO" subtitle="Índice compuesto" />
          </div>
        </>
      )}
    </div>
  )
}

// ────────────────────────────────────────────────────────────
// Subcomponentes
// ────────────────────────────────────────────────────────────
function BigMetric({ label, value, sub, color }: { label: string; value: string; sub: string; color: string }) {
  return (
    <div className="rounded-lg bg-white/10 px-4 py-2 backdrop-blur">
      <div className="text-[10px] uppercase text-white/60">{label}</div>
      <div className={cn('text-2xl font-bold', color)}>{value}</div>
      <div className="text-[10px] text-white/70">{sub}</div>
    </div>
  )
}

function KpiBig({
  label, value, hint, icon, color, href,
}: {
  label: string; value: string; hint?: string
  icon: React.ReactNode
  color: 'emerald' | 'blue' | 'amber' | 'red' | 'indigo'
  href?: string
}) {
  const bg: Record<string, string> = {
    emerald: 'from-emerald-50 to-white border-emerald-200',
    blue: 'from-blue-50 to-white border-blue-200',
    amber: 'from-amber-50 to-white border-amber-200',
    red: 'from-red-50 to-white border-red-200',
    indigo: 'from-indigo-50 to-white border-indigo-200',
  }
  const textColor: Record<string, string> = {
    emerald: 'text-emerald-700',
    blue: 'text-blue-700',
    amber: 'text-amber-700',
    red: 'text-red-700',
    indigo: 'text-indigo-700',
  }
  const body = (
    <div className={cn('rounded-xl border bg-gradient-to-br p-4 shadow-sm transition hover:shadow-md', bg[color])}>
      <div className="flex items-center justify-between">
        <span className={cn('text-xs uppercase tracking-wide', textColor[color])}>{label}</span>
        <span className={textColor[color]}>{icon}</span>
      </div>
      <div className="mt-2 text-3xl font-bold text-gray-900">{value}</div>
      {hint && <div className="text-[11px] text-gray-500 mt-1">{hint}</div>}
    </div>
  )
  return href ? <Link href={href}>{body}</Link> : body
}

function StackedBar({ snapshot }: {
  snapshot: {
    total: number
    arrendados_op: number
    disponibles_op: number
    uso_interno: number
    leasing: number
    en_mant: number
    fuera: number
    sin_cat: number
  }
}) {
  const total = snapshot.total || 1
  const seg = (n: number) => `${(n / total * 100).toFixed(1)}%`
  return (
    <div className="flex h-8 w-full overflow-hidden rounded-md shadow-inner bg-gray-100">
      <Segment width={seg(snapshot.arrendados_op)} bg="bg-green-500" />
      <Segment width={seg(snapshot.disponibles_op)} bg="bg-amber-500" />
      <Segment width={seg(snapshot.uso_interno)} bg="bg-cyan-500" />
      <Segment width={seg(snapshot.leasing)} bg="bg-blue-500" />
      <Segment width={seg(snapshot.en_mant)} bg="bg-orange-500" />
      <Segment width={seg(snapshot.fuera)} bg="bg-red-500" />
    </div>
  )
}

function Segment({ width, bg }: { width: string; bg: string }) {
  return <div className={cn('h-full transition-all', bg)} style={{ width }} />
}

function LegendCell({ color, label, value }: { color: string; label: string; value: number }) {
  return (
    <div className="flex items-center gap-1.5">
      <span className={cn('h-2.5 w-2.5 rounded-sm', color)} />
      <span className="text-gray-600">{label}</span>
      <span className="font-semibold text-gray-900 ml-auto">{value}</span>
    </div>
  )
}

function MiniRow({ patente, label, value, tone }: { patente: string; label: string; value: string; tone: 'red' | 'green' }) {
  return (
    <div className="flex items-center gap-2 text-sm py-1 border-b last:border-0">
      <span className="font-mono font-semibold w-20">{patente}</span>
      <span className="flex-1 text-xs text-gray-500 truncate">{label}</span>
      <span className={cn('text-sm font-semibold', tone === 'red' ? 'text-red-700' : 'text-green-700')}>
        {value}
      </span>
    </div>
  )
}

function ShortcutCard({ href, icon, title, subtitle }: { href: string; icon: React.ReactNode; title: string; subtitle: string }) {
  return (
    <Link href={href}>
      <div className="rounded-lg border border-gray-200 bg-white p-3 transition hover:shadow-md hover:border-slate-400">
        <div className="flex items-center justify-between">
          <div className="text-slate-700">{icon}</div>
          <ArrowUpRight className="h-4 w-4 text-gray-400" />
        </div>
        <div className="mt-2 text-sm font-semibold text-gray-900">{title}</div>
        <div className="text-xs text-gray-500">{subtitle}</div>
      </div>
    </Link>
  )
}

// ────────────────────────────────────────────────────────────
function fmtPct(v: number | null | undefined, digits = 1): string {
  if (v == null) return '—'
  return `${Number(v).toFixed(digits)}%`
}

function iceoColorClass(v: number): string {
  if (v >= 85) return 'text-green-300'
  if (v >= 70) return 'text-blue-300'
  if (v >= 50) return 'text-amber-300'
  return 'text-red-300'
}
