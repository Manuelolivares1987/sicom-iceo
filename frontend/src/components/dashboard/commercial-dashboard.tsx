'use client'

import { useMemo } from 'react'
import Link from 'next/link'
import {
  Briefcase, TrendingUp, TrendingDown, ShieldCheck, ShieldAlert,
  DollarSign, Users, MapPin, ArrowUpRight, Timer, Clock, Truck,
} from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Spinner } from '@/components/ui/spinner'
import { Badge } from '@/components/ui/badge'
import { cn } from '@/lib/utils'
import { useAuth } from '@/contexts/auth-context'
import { useFlotaVehicular } from '@/hooks/use-flota'
import {
  useEquiposDisponiblesArriendo,
  useEquiposPendientesVerif,
} from '@/hooks/use-verificacion'

// ────────────────────────────────────────────────────────────
// Dashboard Comercial — rol 'comercial'
// Foco: qué puedo arrendar HOY y qué está trabado.
// ────────────────────────────────────────────────────────────
export function CommercialDashboard() {
  const { perfil } = useAuth()

  const { data: flota, isLoading: loadingFlota } = useFlotaVehicular()
  const { data: rentables = [], isLoading: loadingRent } = useEquiposDisponiblesArriendo()
  const { data: pendientes = [], isLoading: loadingPend } = useEquiposPendientesVerif()

  // ─── Agregaciones ───
  const stats = useMemo(() => {
    if (!flota) return null
    let arrendados = 0, usoInterno = 0, leasing = 0, disponibles = 0, enTaller = 0
    const porCliente: Record<string, number> = {}

    for (const a of flota as any[]) {
      if (a.estado === 'operativo') {
        switch (a.estado_comercial) {
          case 'arrendado':   arrendados++; break
          case 'disponible':  disponibles++; break
          case 'uso_interno': usoInterno++; break
          case 'leasing':     leasing++; break
        }
        const c = a.cliente_actual || 'Sin cliente'
        porCliente[c] = (porCliente[c] || 0) + 1
      } else if (a.estado === 'en_mantenimiento' || a.estado === 'fuera_servicio') {
        enTaller++
      }
    }

    const total = flota.length
    const tasaOcupacion = total > 0 ? ((arrendados + usoInterno + leasing) / total) * 100 : 0
    return {
      total,
      arrendados, usoInterno, leasing, disponibles, enTaller,
      tasaOcupacion,
      perdidaPct: total > 0 ? (disponibles / total * 100) : 0,
      clientesActivos: Object.keys(porCliente).filter((k) => k !== 'Sin cliente').length,
      porCliente,
    }
  }, [flota])

  // ─── Rentables ordenados por vencimiento (urgentes arriba) ───
  const rentablesUrgentes = useMemo(
    () => rentables.filter((e) => e.horas_restantes <= 12),
    [rentables],
  )

  // ─── Top 5 clientes con más equipos ───
  const topClientes = useMemo(() => {
    if (!stats) return []
    return Object.entries(stats.porCliente)
      .filter(([k]) => k !== 'Sin cliente')
      .map(([cliente, cantidad]) => ({ cliente, cantidad }))
      .sort((a, b) => b.cantidad - a.cantidad)
      .slice(0, 5)
  }, [stats])

  const isLoading = loadingFlota || loadingRent || loadingPend

  return (
    <div className="space-y-6">
      {/* ─── Hero comercial ─── */}
      <div className="rounded-2xl bg-gradient-to-r from-purple-700 via-violet-700 to-indigo-700 p-6 text-white shadow-lg">
        <div className="flex flex-col gap-2 md:flex-row md:items-center md:justify-between">
          <div>
            <div className="text-xs uppercase tracking-widest text-white/60">Vista Comercial</div>
            <h1 className="text-2xl font-bold flex items-center gap-2">
              <Briefcase className="h-6 w-6" />
              {perfil?.nombre_completo ? `Hola, ${perfil.nombre_completo.split(' ')[0]}` : 'Panel Comercial'}
            </h1>
            <p className="text-sm text-white/80 mt-1">
              {rentables.length} equipos listos para arrendar · {pendientes.length} trabados
            </p>
          </div>
          <div className="flex items-center gap-3">
            <BigMetric
              label="Tasa Ocupación"
              value={stats ? `${stats.tasaOcupacion.toFixed(1)}%` : '—'}
              sub={`${stats?.arrendados ?? 0} arrendados / ${stats?.total ?? 0}`}
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
          {/* ─── KPI Tiles ─── */}
          <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
            <KpiTile
              icon={<ShieldCheck className="h-5 w-5" />}
              label="Rentables Ahora"
              value={String(rentables.length)}
              hint="Con verificación vigente"
              color="emerald"
            />
            <KpiTile
              icon={<ShieldAlert className="h-5 w-5" />}
              label="Sin Verificación"
              value={String(pendientes.length)}
              hint="Marcados disponibles pero bloqueados"
              color="amber"
            />
            <KpiTile
              icon={<DollarSign className="h-5 w-5" />}
              label="Arrendados"
              value={String(stats?.arrendados ?? 0)}
              hint={`${stats?.total ? ((stats.arrendados / stats.total) * 100).toFixed(1) : 0}% de flota`}
              color="blue"
            />
            <KpiTile
              icon={<TrendingDown className="h-5 w-5" />}
              label="Pérdida Comercial"
              value={String(stats?.disponibles ?? 0)}
              hint={`${stats?.perdidaPct.toFixed(1) ?? 0}% sin cliente`}
              color="rose"
            />
          </div>

          {/* ─── Alerta: rentables con vigencia crítica (<12h) ─── */}
          {rentablesUrgentes.length > 0 && (
            <Card className="border-amber-300 bg-amber-50">
              <CardHeader className="pb-2">
                <CardTitle className="text-sm text-amber-900 flex items-center gap-2">
                  <Timer className="h-4 w-4" />
                  Urgente: {rentablesUrgentes.length} equipo(s) con verificación por vencer en &lt; 12h
                </CardTitle>
              </CardHeader>
              <CardContent>
                <div className="flex flex-wrap gap-2">
                  {rentablesUrgentes.map((e) => (
                    <span key={e.id} className="rounded-full bg-amber-200 px-3 py-1 text-xs font-mono">
                      {e.patente ?? e.codigo} · {Math.round(e.horas_restantes)}h
                    </span>
                  ))}
                </div>
                <p className="text-xs text-amber-800 mt-2">
                  Asigne a cliente HOY o vuelve a verificación.
                </p>
              </CardContent>
            </Card>
          )}

          {/* ─── Tabla: Equipos Rentables (verificación vigente) ─── */}
          <Card className="border-emerald-200">
            <CardHeader className="pb-2">
              <CardTitle className="text-base flex items-center justify-between text-emerald-800">
                <span className="flex items-center gap-2">
                  <ShieldCheck className="h-5 w-5" />
                  Equipos Disponibles para Arrendar
                </span>
                <Badge className="bg-emerald-100 text-emerald-800">{rentables.length}</Badge>
              </CardTitle>
            </CardHeader>
            <CardContent className="overflow-x-auto">
              {rentables.length === 0 ? (
                <p className="text-sm text-gray-400 py-6 text-center">
                  Sin equipos con verificación vigente. Pide al Jefe de Taller que apruebe verificaciones pendientes.
                </p>
              ) : (
                <table className="w-full text-sm">
                  <thead>
                    <tr className="border-b text-left text-xs text-gray-500 uppercase">
                      <th className="px-2 py-2">Patente</th>
                      <th className="px-2 py-2">Equipo</th>
                      <th className="px-2 py-2">Ubicación</th>
                      <th className="px-2 py-2">Operación</th>
                      <th className="px-2 py-2 text-right">Vence</th>
                      <th className="px-2 py-2"></th>
                    </tr>
                  </thead>
                  <tbody>
                    {rentables.map((e) => (
                      <tr key={e.id} className="border-b hover:bg-emerald-50/40">
                        <td className="px-2 py-2 font-mono font-semibold">{e.patente ?? e.codigo}</td>
                        <td className="px-2 py-2">{e.nombre ?? '—'}</td>
                        <td className="px-2 py-2 text-gray-500 max-w-[180px] truncate">{e.ubicacion_actual ?? '—'}</td>
                        <td className="px-2 py-2 text-gray-500">{e.operacion ?? '—'}</td>
                        <td className={cn(
                          'px-2 py-2 text-right font-semibold',
                          e.horas_restantes <= 12 ? 'text-red-600' :
                          e.horas_restantes <= 24 ? 'text-amber-600' :
                          'text-gray-600',
                        )}>
                          {formatHoras(e.horas_restantes)}
                        </td>
                        <td className="px-2 py-2 text-right">
                          <Link href={`/dashboard/activos/${e.id}`} className="text-xs text-blue-600 hover:underline">
                            ver
                          </Link>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )}
            </CardContent>
          </Card>

          {/* ─── Tabla: Equipos trabados (marcados disponibles sin verif) ─── */}
          {pendientes.length > 0 && (
            <Card className="border-amber-200">
              <CardHeader className="pb-2">
                <CardTitle className="text-base flex items-center justify-between text-amber-800">
                  <span className="flex items-center gap-2">
                    <ShieldAlert className="h-5 w-5" />
                    Trabados: Marcados "Disponible" SIN verificación vigente
                  </span>
                  <Badge className="bg-amber-100 text-amber-800">{pendientes.length}</Badge>
                </CardTitle>
              </CardHeader>
              <CardContent className="overflow-x-auto">
                <p className="text-xs text-amber-700 mb-3">
                  Estos equipos aparecen como disponibles en el maestro pero NO pueden arrendarse
                  hasta tener checklist aprobado. Pide a mantención que ejecute la verificación.
                </p>
                <table className="w-full text-sm">
                  <thead>
                    <tr className="border-b text-left text-xs text-gray-500 uppercase">
                      <th className="px-2 py-2">Patente</th>
                      <th className="px-2 py-2">Equipo</th>
                      <th className="px-2 py-2">Última verificación</th>
                      <th className="px-2 py-2"></th>
                    </tr>
                  </thead>
                  <tbody>
                    {pendientes.map((e) => (
                      <tr key={e.id} className="border-b hover:bg-amber-50/40">
                        <td className="px-2 py-2 font-mono font-semibold">{e.patente ?? e.codigo}</td>
                        <td className="px-2 py-2">{e.nombre ?? '—'}</td>
                        <td className="px-2 py-2 text-gray-500 text-xs">
                          {e.ultima_verificacion?.resultado ?? 'Nunca verificado'}
                          {e.ultima_verificacion?.vigente_hasta && (
                            <span className="ml-1 text-red-500">
                              (venció {new Date(e.ultima_verificacion.vigente_hasta).toLocaleDateString('es-CL')})
                            </span>
                          )}
                        </td>
                        <td className="px-2 py-2 text-right">
                          <Link href={`/dashboard/activos/${e.id}`} className="text-xs text-blue-600 hover:underline">
                            ver
                          </Link>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </CardContent>
            </Card>
          )}

          {/* ─── Grid: Top clientes + Snapshot flota ─── */}
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
            <Card>
              <CardHeader className="pb-2">
                <CardTitle className="text-base flex items-center gap-2 text-gray-700">
                  <Users className="h-5 w-5" />
                  Top 5 Clientes
                </CardTitle>
              </CardHeader>
              <CardContent>
                {topClientes.length === 0 ? (
                  <p className="text-sm text-gray-400">Sin clientes con equipos asignados</p>
                ) : (
                  <div className="space-y-2">
                    {topClientes.map((c) => (
                      <div key={c.cliente} className="flex items-center gap-2">
                        <span className="flex-1 text-sm truncate">{c.cliente}</span>
                        <Badge className="bg-indigo-100 text-indigo-700">{c.cantidad}</Badge>
                      </div>
                    ))}
                  </div>
                )}
              </CardContent>
            </Card>

            <Card>
              <CardHeader className="pb-2">
                <CardTitle className="text-base flex items-center gap-2 text-gray-700">
                  <Truck className="h-5 w-5" />
                  Distribución Estado
                </CardTitle>
              </CardHeader>
              <CardContent className="space-y-1 text-sm">
                <StateRow label="Arrendados" value={stats?.arrendados ?? 0} color="bg-green-500" total={stats?.total ?? 1} />
                <StateRow label="Disponibles" value={stats?.disponibles ?? 0} color="bg-amber-500" total={stats?.total ?? 1} />
                <StateRow label="Uso Interno" value={stats?.usoInterno ?? 0} color="bg-cyan-500" total={stats?.total ?? 1} />
                <StateRow label="Leasing" value={stats?.leasing ?? 0} color="bg-blue-500" total={stats?.total ?? 1} />
                <StateRow label="En Taller/Fuera" value={stats?.enTaller ?? 0} color="bg-red-500" total={stats?.total ?? 1} />
              </CardContent>
            </Card>
          </div>

          {/* ─── Atajos ─── */}
          <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
            <ShortcutCard href="/dashboard/flota" icon={<Truck className="h-5 w-5" />} title="Flota" subtitle="Maestro y pie charts" />
            <ShortcutCard href="/dashboard/comercial" icon={<Briefcase className="h-5 w-5" />} title="Comercial detalle" subtitle="Clientes y pie" />
            <ShortcutCard href="/dashboard/contratos" icon={<DollarSign className="h-5 w-5" />} title="Contratos" subtitle="Vigentes" />
            <ShortcutCard href="/dashboard/reportes" icon={<MapPin className="h-5 w-5" />} title="Reportes" subtitle="Exportar datos" />
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
      <div className="text-[10px] uppercase text-white/60">{label}</div>
      <div className="text-2xl font-bold">{value}</div>
      <div className="text-[10px] text-white/70">{sub}</div>
    </div>
  )
}

function KpiTile({
  icon, label, value, hint, color,
}: {
  icon: React.ReactNode
  label: string; value: string; hint?: string
  color: 'emerald' | 'amber' | 'blue' | 'rose' | 'indigo'
}) {
  const bg: Record<string, string> = {
    emerald: 'from-emerald-50 to-white border-emerald-200 text-emerald-700',
    amber: 'from-amber-50 to-white border-amber-200 text-amber-700',
    blue: 'from-blue-50 to-white border-blue-200 text-blue-700',
    rose: 'from-rose-50 to-white border-rose-200 text-rose-700',
    indigo: 'from-indigo-50 to-white border-indigo-200 text-indigo-700',
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

function StateRow({ label, value, color, total }: { label: string; value: number; color: string; total: number }) {
  const pct = total > 0 ? (value / total) * 100 : 0
  return (
    <div>
      <div className="flex items-center justify-between text-xs mb-0.5">
        <span>{label}</span>
        <span className="font-semibold">{value}</span>
      </div>
      <div className="h-1.5 w-full rounded bg-gray-100 overflow-hidden">
        <div className={cn('h-full', color)} style={{ width: `${pct}%` }} />
      </div>
    </div>
  )
}

function ShortcutCard({ href, icon, title, subtitle }: { href: string; icon: React.ReactNode; title: string; subtitle: string }) {
  return (
    <Link href={href}>
      <div className="rounded-lg border border-gray-200 bg-white p-3 transition hover:shadow-md hover:border-purple-400">
        <div className="flex items-center justify-between">
          <div className="text-purple-700">{icon}</div>
          <ArrowUpRight className="h-4 w-4 text-gray-400" />
        </div>
        <div className="mt-2 text-sm font-semibold text-gray-900">{title}</div>
        <div className="text-xs text-gray-500">{subtitle}</div>
      </div>
    </Link>
  )
}

function formatHoras(h: number | null | undefined): string {
  if (h == null) return '—'
  if (h < 1) return `${Math.round(h * 60)}m`
  if (h < 24) return `${h.toFixed(1)}h`
  const dias = Math.floor(h / 24)
  const horas = Math.round(h % 24)
  return horas > 0 ? `${dias}d ${horas}h` : `${dias}d`
}
