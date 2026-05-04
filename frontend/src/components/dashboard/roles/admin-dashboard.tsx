'use client'

import Link from 'next/link'
import { Settings, Users, Database, ShieldAlert, Activity, FileWarning } from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Spinner } from '@/components/ui/spinner'
import { useSystemStats } from '@/hooks/use-admin-stats'
import { useAlertasNoLeidas } from '@/hooks/use-alertas'

/**
 * Admin: salud del sistema, usuarios por rol, accesos rapidos.
 * Reutiliza datos existentes — no crea queries nuevas pesadas.
 */
export function AdminDashboard() {
  const { data: stats, isLoading: loadingStats } = useSystemStats()
  const { data: alertas } = useAlertasNoLeidas()

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">
          Panel de Administración
        </h1>
        <p className="text-sm text-gray-500">
          Salud del sistema, usuarios, accesos rápidos
        </p>
      </div>

      {/* KPIs sistema */}
      <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-4">
        <KPI label="Contratos" value={stats?.contratos} loading={loadingStats} icon={<Database className="h-5 w-5 text-blue-600" />} />
        <KPI label="Faenas" value={stats?.faenas} loading={loadingStats} icon={<Database className="h-5 w-5 text-green-600" />} />
        <KPI label="Activos" value={stats?.activos} loading={loadingStats} icon={<Database className="h-5 w-5 text-orange-600" />} />
        <KPI label="OTs" value={stats?.ordenes_trabajo} loading={loadingStats} icon={<Activity className="h-5 w-5 text-blue-600" />} />
        <KPI label="Productos" value={stats?.productos} loading={loadingStats} icon={<Database className="h-5 w-5 text-emerald-600" />} />
        <KPI label="Usuarios" value={stats?.usuarios} loading={loadingStats} icon={<Users className="h-5 w-5 text-purple-600" />} />
      </div>

      {/* Alertas y accesos rápidos */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-base">
              <ShieldAlert className="h-5 w-5 text-red-500" />
              Alertas activas
            </CardTitle>
          </CardHeader>
          <CardContent>
            {!alertas || alertas.length === 0 ? (
              <p className="text-sm text-gray-400 py-4 text-center">Sin alertas pendientes</p>
            ) : (
              <ul className="space-y-2">
                {alertas.slice(0, 5).map((a) => (
                  <li key={a.id} className="text-sm border-l-2 border-red-300 pl-3">
                    <strong className="text-gray-900">{a.titulo}</strong>
                    <span className="block text-xs text-gray-500">{a.tipo} · {a.severidad}</span>
                  </li>
                ))}
              </ul>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-base">
              <Settings className="h-5 w-5 text-gray-600" />
              Accesos rápidos
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="grid grid-cols-2 gap-2">
              <QuickLink href="/dashboard/admin" label="Administración" />
              <QuickLink href="/dashboard/auditoria" label="Auditoría" />
              <QuickLink href="/dashboard/reportes" label="Reportes" />
              <QuickLink href="/dashboard/iceo" label="ICEO" />
              <QuickLink href="/dashboard/cumplimiento" label="Cumplimiento" />
              <QuickLink href="/dashboard/admin/checklist-templates" label="Plantillas Checklist" />
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Notas migraciones pendientes */}
      <Card className="border-amber-200 bg-amber-50">
        <CardHeader>
          <CardTitle className="flex items-center gap-2 text-base text-amber-900">
            <FileWarning className="h-5 w-5" />
            Migraciones pendientes (FASE 5.6)
          </CardTitle>
        </CardHeader>
        <CardContent>
          <ul className="text-sm text-amber-800 space-y-1 list-disc pl-5">
            <li>52 — RLS hardening (solo Block A recomendado pre-demo)</li>
            <li>53 — Seed roles piloto (manual)</li>
            <li>54 — Verificaciones flota (Block 0 SAFE aplicable)</li>
            <li>55 — Bodega OC/CECO (base de 56 y 57)</li>
            <li>56 — FIFO repuestos (depende de 55)</li>
            <li>57 — Combustible CPP móvil (depende de 55)</li>
          </ul>
          <p className="mt-2 text-xs text-amber-700">
            Ver <code>PLAN_OPERACION_STAGING_MIGRACIONES.md</code> y{' '}
            <code>PLAN_PASO_PRODUCCION_CONTROLADO.md</code>.
          </p>
        </CardContent>
      </Card>
    </div>
  )
}

function KPI({
  label,
  value,
  loading,
  icon,
}: {
  label: string
  value: number | undefined
  loading: boolean
  icon: React.ReactNode
}) {
  return (
    <Card>
      <CardContent className="p-4">
        <div className="flex items-center justify-between">
          <p className="text-xs text-gray-500">{label}</p>
          {icon}
        </div>
        <p className="mt-1 text-2xl font-bold text-gray-900">
          {loading ? <Spinner size="sm" /> : value ?? 0}
        </p>
      </CardContent>
    </Card>
  )
}

function QuickLink({ href, label }: { href: string; label: string }) {
  return (
    <Link
      href={href}
      className="rounded-md border border-gray-200 bg-white px-3 py-2 text-sm text-gray-700 hover:bg-gray-50 hover:border-pillado-green-400"
    >
      {label}
    </Link>
  )
}
