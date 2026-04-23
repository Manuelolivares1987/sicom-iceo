'use client'

import { useMemo } from 'react'
import Link from 'next/link'
import {
  ClipboardList, ShieldCheck, AlertTriangle, Wrench, CheckCircle2,
  ArrowUpRight, Clock, Truck, Zap,
} from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Spinner } from '@/components/ui/spinner'
import { Badge } from '@/components/ui/badge'
import { cn } from '@/lib/utils'
import { useAuth } from '@/contexts/auth-context'
import { useOrdenesTrabajo, useOTsStats } from '@/hooks/use-ordenes-trabajo'
import { useVerificacionesPendientes } from '@/hooks/use-verificacion'
import { useAlertasNoLeidas } from '@/hooks/use-alertas'
import { useFlotaVehicular } from '@/hooks/use-flota'

// ────────────────────────────────────────────────────────────
// Dashboard Operaciones — supervisor / jefe_mantenimiento / planificador
// Foco: acción operacional diaria.
// ────────────────────────────────────────────────────────────
export function OperationsDashboard() {
  const { perfil } = useAuth()

  const { data: flota } = useFlotaVehicular()
  const { data: ots = [], isLoading: loadingOts } = useOrdenesTrabajo({})
  const { data: otsStats } = useOTsStats()
  const { data: pendientesVerif = [] } = useVerificacionesPendientes()
  const { data: alertasData } = useAlertasNoLeidas()
  const alertas = alertasData ?? []

  // ─── Métricas operacionales ───
  const otsPorEstado = useMemo(() => {
    const o = { creada: 0, asignada: 0, en_ejecucion: 0, pausada: 0 }
    for (const ot of (ots as any[])) {
      if (ot.estado in o) o[ot.estado as keyof typeof o]++
    }
    return o
  }, [ots])

  const otsEmergencia = useMemo(
    () => (ots as any[])
      .filter((o) => o.prioridad === 'emergencia' &&
        ['creada', 'asignada', 'en_ejecucion', 'pausada'].includes(o.estado))
      .slice(0, 5),
    [ots],
  )

  const otsAsignadasAbiertas = useMemo(
    () => (ots as any[])
      .filter((o) => ['creada', 'asignada', 'en_ejecucion', 'pausada'].includes(o.estado))
      .sort((a, b) => {
        const pOrder = { emergencia: 0, urgente: 1, alta: 2, normal: 3, baja: 4 }
        return (pOrder[a.prioridad as keyof typeof pOrder] ?? 5) -
               (pOrder[b.prioridad as keyof typeof pOrder] ?? 5)
      })
      .slice(0, 10),
    [ots],
  )

  const estadoFlota = useMemo(() => {
    if (!flota) return null
    let operativos = 0, en_taller = 0, fuera = 0
    for (const a of flota as any[]) {
      if (a.estado === 'operativo') operativos++
      else if (a.estado === 'en_mantenimiento') en_taller++
      else if (a.estado === 'fuera_servicio') fuera++
    }
    return { operativos, en_taller, fuera, total: flota.length }
  }, [flota])

  const alertasCriticas = useMemo(
    () => alertas.filter((a) => a.severidad === 'critical').slice(0, 5),
    [alertas],
  )

  const isLoading = loadingOts

  return (
    <div className="space-y-6">
      {/* ─── Hero operaciones ─── */}
      <div className="rounded-2xl bg-gradient-to-r from-amber-600 via-orange-600 to-red-600 p-6 text-white shadow-lg">
        <div className="flex flex-col gap-2 md:flex-row md:items-center md:justify-between">
          <div>
            <div className="text-xs uppercase tracking-widest text-white/70">Operaciones</div>
            <h1 className="text-2xl font-bold flex items-center gap-2">
              <Wrench className="h-6 w-6" />
              {perfil?.nombre_completo ? `Hola, ${perfil.nombre_completo.split(' ')[0]}` : 'Panel Operaciones'}
            </h1>
            <p className="text-sm text-white/80 mt-1">
              {otsAsignadasAbiertas.length} OTs abiertas · {pendientesVerif.length} verificaciones pendientes · {alertasCriticas.length} bloqueos
            </p>
          </div>
          <div className="flex items-center gap-3">
            <BigMetric label="OTs Abiertas" value={String(otsPorEstado.creada + otsPorEstado.asignada + otsPorEstado.en_ejecucion + otsPorEstado.pausada)} sub={`${otsPorEstado.en_ejecucion} en ejecución`} />
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
          {/* ─── KPI Tiles ─── */}
          <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
            <KpiTile
              icon={<Zap className="h-5 w-5" />}
              label="Emergencia"
              value={String(otsEmergencia.length)}
              hint="OTs prioridad emergencia abiertas"
              color={otsEmergencia.length > 0 ? 'red' : 'gray'}
            />
            <KpiTile
              icon={<ClipboardList className="h-5 w-5" />}
              label="Por Asignar"
              value={String(otsPorEstado.creada)}
              hint="Esperando responsable"
              color="amber"
            />
            <KpiTile
              icon={<Wrench className="h-5 w-5" />}
              label="En Ejecución"
              value={String(otsPorEstado.en_ejecucion)}
              hint={`${otsPorEstado.pausada} pausadas`}
              color="blue"
            />
            <KpiTile
              icon={<ShieldCheck className="h-5 w-5" />}
              label="Verif. Pendientes"
              value={String(pendientesVerif.length)}
              hint="Por aprobar/ejecutar"
              color="emerald"
            />
          </div>

          {/* ─── Alertas críticas (bloqueos normativos) ─── */}
          {alertasCriticas.length > 0 && (
            <Card className="border-red-300 bg-red-50">
              <CardHeader className="pb-2">
                <CardTitle className="text-base text-red-800 flex items-center gap-2">
                  <AlertTriangle className="h-5 w-5" />
                  Bloqueos Normativos ({alertasCriticas.length})
                </CardTitle>
              </CardHeader>
              <CardContent className="space-y-2">
                {alertasCriticas.map((a, i) => (
                  <div key={i} className="text-sm text-red-800 border-b border-red-200 pb-1 last:border-0">
                    <strong>{a.titulo}</strong>
                  </div>
                ))}
              </CardContent>
            </Card>
          )}

          {/* ─── OTs de emergencia (prioridad máxima) ─── */}
          {otsEmergencia.length > 0 && (
            <Card className="border-red-300">
              <CardHeader className="pb-2">
                <CardTitle className="text-base text-red-700 flex items-center gap-2">
                  <Zap className="h-5 w-5" />
                  OTs Emergencia (atender primero)
                </CardTitle>
              </CardHeader>
              <CardContent className="space-y-2">
                {otsEmergencia.map((ot: any) => (
                  <Link
                    key={ot.id}
                    href={`/dashboard/ordenes-trabajo/${ot.id}`}
                    className="flex items-center justify-between gap-2 rounded border border-red-200 bg-white p-2 hover:bg-red-50 text-sm"
                  >
                    <div>
                      <span className="font-mono font-semibold">{ot.folio}</span>
                      <span className="ml-2 text-gray-600">{ot.activo?.nombre ?? ot.activo?.codigo ?? '—'}</span>
                    </div>
                    <div className="flex items-center gap-2">
                      <Badge className="bg-red-200 text-red-800">{ot.estado}</Badge>
                      <ArrowUpRight className="h-4 w-4 text-gray-400" />
                    </div>
                  </Link>
                ))}
              </CardContent>
            </Card>
          )}

          {/* ─── Grid: OTs abiertas + Verificaciones pendientes ─── */}
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
            <Card>
              <CardHeader className="pb-2">
                <CardTitle className="text-base flex items-center justify-between text-gray-700">
                  <span className="flex items-center gap-2">
                    <ClipboardList className="h-5 w-5" />
                    OTs Abiertas (top 10 por prioridad)
                  </span>
                  <Link href="/dashboard/ordenes-trabajo" className="text-xs text-blue-600 hover:underline">
                    Ver todas
                  </Link>
                </CardTitle>
              </CardHeader>
              <CardContent className="space-y-1">
                {otsAsignadasAbiertas.length === 0 ? (
                  <p className="text-sm text-gray-400 py-4 text-center">
                    Sin OTs abiertas ✓
                  </p>
                ) : (
                  otsAsignadasAbiertas.map((ot: any) => (
                    <Link
                      key={ot.id}
                      href={`/dashboard/ordenes-trabajo/${ot.id}`}
                      className="flex items-center justify-between border-b py-1.5 hover:bg-gray-50 text-sm last:border-0"
                    >
                      <div className="flex-1 min-w-0">
                        <div className="font-mono text-xs text-gray-600">{ot.folio}</div>
                        <div className="truncate">{ot.activo?.nombre ?? '—'}</div>
                      </div>
                      <div className="flex items-center gap-1 shrink-0">
                        <PrioridadBadge prioridad={ot.prioridad} />
                        <Badge className="text-[10px]">{ot.estado}</Badge>
                      </div>
                    </Link>
                  ))
                )}
              </CardContent>
            </Card>

            <Card>
              <CardHeader className="pb-2">
                <CardTitle className="text-base flex items-center justify-between text-gray-700">
                  <span className="flex items-center gap-2">
                    <ShieldCheck className="h-5 w-5" />
                    Verificaciones Pendientes
                  </span>
                  <Badge>{pendientesVerif.length}</Badge>
                </CardTitle>
              </CardHeader>
              <CardContent className="space-y-1">
                {pendientesVerif.length === 0 ? (
                  <p className="text-sm text-gray-400 py-4 text-center">
                    Sin verificaciones pendientes ✓
                  </p>
                ) : (
                  pendientesVerif.slice(0, 10).map((v) => (
                    <Link
                      key={v.verificacion_id}
                      href={`/dashboard/flota/aprobar/${v.ot_id}`}
                      className="flex items-center justify-between border-b py-1.5 hover:bg-amber-50 text-sm last:border-0"
                    >
                      <div className="flex-1 min-w-0">
                        <div className="font-mono font-semibold">{v.patente ?? v.codigo}</div>
                        <div className="text-xs text-gray-500 truncate">{v.equipo}</div>
                      </div>
                      <div className="text-xs text-amber-700">
                        {v.checklist_progreso
                          ? `${v.checklist_progreso.ok + v.checklist_progreso.na}/${v.checklist_progreso.total}`
                          : '—'}
                      </div>
                    </Link>
                  ))
                )}
              </CardContent>
            </Card>
          </div>

          {/* ─── Resumen flota ─── */}
          {estadoFlota && (
            <Card>
              <CardHeader className="pb-2">
                <CardTitle className="text-base flex items-center justify-between text-gray-700">
                  <span className="flex items-center gap-2">
                    <Truck className="h-5 w-5" />
                    Resumen Flota
                  </span>
                  <Link href="/dashboard/flota" className="text-xs text-blue-600 hover:underline">
                    Ver detalle
                  </Link>
                </CardTitle>
              </CardHeader>
              <CardContent className="grid grid-cols-3 gap-3">
                <MiniStat label="Operativos" value={estadoFlota.operativos} color="text-green-700" total={estadoFlota.total} />
                <MiniStat label="En taller" value={estadoFlota.en_taller} color="text-amber-700" total={estadoFlota.total} />
                <MiniStat label="Fuera de servicio" value={estadoFlota.fuera} color="text-red-700" total={estadoFlota.total} />
              </CardContent>
            </Card>
          )}

          {/* ─── Atajos ─── */}
          <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
            <ShortcutCard href="/dashboard/ordenes-trabajo" icon={<ClipboardList className="h-5 w-5" />} title="Órdenes de Trabajo" subtitle="Crear, asignar, ejecutar" />
            <ShortcutCard href="/dashboard/mantenimiento" icon={<Wrench className="h-5 w-5" />} title="Mantenimiento" subtitle="Planes y pautas" />
            <ShortcutCard href="/dashboard/flota" icon={<Truck className="h-5 w-5" />} title="Flota" subtitle="Maestro y estados" />
            <ShortcutCard href="/dashboard/fiabilidad" icon={<ShieldCheck className="h-5 w-5" />} title="Fiabilidad" subtitle="MTBF, MTTR, OEE" />
          </div>
        </>
      )}
    </div>
  )
}

// ─── Subcomponentes ──────────────────────────────────────
function BigMetric({ label, value, sub }: { label: string; value: string; sub: string }) {
  return (
    <div className="rounded-lg bg-white/10 px-4 py-2 backdrop-blur">
      <div className="text-[10px] uppercase text-white/70">{label}</div>
      <div className="text-2xl font-bold">{value}</div>
      <div className="text-[10px] text-white/80">{sub}</div>
    </div>
  )
}

function KpiTile({
  icon, label, value, hint, color,
}: {
  icon: React.ReactNode
  label: string; value: string; hint?: string
  color: 'red' | 'amber' | 'blue' | 'emerald' | 'gray'
}) {
  const bg: Record<string, string> = {
    red: 'from-red-50 to-white border-red-200 text-red-700',
    amber: 'from-amber-50 to-white border-amber-200 text-amber-700',
    blue: 'from-blue-50 to-white border-blue-200 text-blue-700',
    emerald: 'from-emerald-50 to-white border-emerald-200 text-emerald-700',
    gray: 'from-gray-50 to-white border-gray-200 text-gray-700',
  }
  return (
    <div className={cn('rounded-xl border bg-gradient-to-br p-4 shadow-sm', bg[color])}>
      <div className="flex items-center justify-between">
        <span className="text-xs uppercase tracking-wide opacity-70">{label}</span>
        {icon}
      </div>
      <div className="mt-2 text-3xl font-bold text-gray-900">{value}</div>
      {hint && <div className="text-[11px] opacity-70 mt-1">{hint}</div>}
    </div>
  )
}

function PrioridadBadge({ prioridad }: { prioridad: string }) {
  const map: Record<string, string> = {
    emergencia: 'bg-red-200 text-red-800',
    urgente: 'bg-orange-200 text-orange-800',
    alta: 'bg-amber-100 text-amber-800',
    normal: 'bg-blue-100 text-blue-800',
    baja: 'bg-gray-100 text-gray-700',
  }
  return (
    <span className={cn('rounded-full px-2 py-0.5 text-[10px] font-semibold', map[prioridad] ?? 'bg-gray-100')}>
      {prioridad}
    </span>
  )
}

function MiniStat({ label, value, color, total }: { label: string; value: number; color: string; total: number }) {
  const pct = total > 0 ? ((value / total) * 100).toFixed(0) : '0'
  return (
    <div className="text-center rounded border p-2">
      <div className="text-xs text-gray-500">{label}</div>
      <div className={cn('text-2xl font-bold', color)}>{value}</div>
      <div className="text-[10px] text-gray-400">{pct}%</div>
    </div>
  )
}

function ShortcutCard({ href, icon, title, subtitle }: { href: string; icon: React.ReactNode; title: string; subtitle: string }) {
  return (
    <Link href={href}>
      <div className="rounded-lg border border-gray-200 bg-white p-3 transition hover:shadow-md hover:border-amber-400">
        <div className="flex items-center justify-between">
          <div className="text-amber-700">{icon}</div>
          <ArrowUpRight className="h-4 w-4 text-gray-400" />
        </div>
        <div className="mt-2 text-sm font-semibold text-gray-900">{title}</div>
        <div className="text-xs text-gray-500">{subtitle}</div>
      </div>
    </Link>
  )
}
