'use client'

import { useState } from 'react'
import {
  CalendarClock,
  RefreshCw,
  Truck,
  Wrench,
  Briefcase,
  HardHat,
  AlertTriangle,
  Activity,
  Printer,
} from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Spinner } from '@/components/ui/spinner'
import { cn } from '@/lib/utils'
import { useRequireAuth } from '@/hooks/use-require-auth'
import {
  useReporteDiario,
  useReportesHistoricos,
  useRegenerarReporteDiario,
  useTendenciaReporte,
  useCambiosEstadoDia,
} from '@/hooks/use-reporte-diario'
import { ESTADO_DIARIO_LABELS, ESTADO_DIARIO_COLORS } from '@/lib/services/flota'
import { TendenciaFlotaChart } from '@/components/flota/tendencia-flota-chart'
import { DistribucionEstadosChart } from '@/components/flota/distribucion-estados-chart'
import { CambiosEstadoDiaTimeline } from '@/components/flota/cambios-estado-dia-timeline'

function Section({
  icon: Icon,
  title,
  color,
  children,
}: {
  icon: any
  title: string
  color: string
  children: React.ReactNode
}) {
  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-base flex items-center gap-2">
          <Icon className={cn('h-5 w-5', color)} />
          {title}
        </CardTitle>
      </CardHeader>
      <CardContent>{children}</CardContent>
    </Card>
  )
}

function Metric({ label, value, sub }: { label: string; value: string | number; sub?: string }) {
  return (
    <div>
      <div className="text-xs text-gray-500">{label}</div>
      <div className="text-2xl font-bold text-gray-900">{value}</div>
      {sub && <div className="text-xs text-gray-400">{sub}</div>}
    </div>
  )
}

export default function ReporteDiarioPage() {
  useRequireAuth()

  const [fechaSeleccionada, setFechaSeleccionada] = useState<string | undefined>(undefined)
  const [diasTendencia, setDiasTendencia] = useState(30)
  const { data: reporte, isLoading } = useReporteDiario(fechaSeleccionada)
  const { data: historicos } = useReportesHistoricos(7)
  const { data: tendencia, isLoading: loadingTendencia } = useTendenciaReporte(diasTendencia)
  const { data: cambios, isLoading: loadingCambios } = useCambiosEstadoDia(fechaSeleccionada)
  const regenerar = useRegenerarReporteDiario()

  const payload = reporte?.payload

  if (isLoading) {
    return (
      <div className="flex h-64 items-center justify-center">
        <Spinner className="h-8 w-8" />
      </div>
    )
  }

  return (
    <div className="space-y-6">
      {/* ── Header ── */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-gray-900 flex items-center gap-2">
            <CalendarClock className="h-7 w-7 text-indigo-600" />
            Reporte Diario Automático
          </h1>
          <p className="text-sm text-gray-500 mt-1">
            Snapshot operacional del servicio · Generado: {reporte?.generado_en
              ? new Date(reporte.generado_en).toLocaleString('es-CL')
              : '—'}
          </p>
        </div>
        <div className="flex gap-2 print:hidden">
          <select
            className="rounded-md border border-gray-300 px-3 py-2 text-sm"
            value={fechaSeleccionada ?? ''}
            onChange={(e) => setFechaSeleccionada(e.target.value || undefined)}
          >
            <option value="">Más reciente</option>
            {historicos?.map((h) => (
              <option key={h.id} value={h.fecha}>{h.fecha}</option>
            ))}
          </select>
          <button
            className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-700 flex items-center gap-1"
            onClick={() => regenerar.mutate(undefined)}
            disabled={regenerar.isPending}
          >
            <RefreshCw className={cn('h-4 w-4', regenerar.isPending && 'animate-spin')} />
            {regenerar.isPending ? 'Regenerando...' : 'Regenerar ahora'}
          </button>
          <button
            className="rounded-md border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 flex items-center gap-1"
            onClick={() => window.print()}
            title="Imprimir / guardar como PDF"
          >
            <Printer className="h-4 w-4" />
            Imprimir / PDF
          </button>
        </div>
      </div>

      {!payload && (
        <Card>
          <CardContent className="py-12 text-center text-gray-500">
            <CalendarClock className="h-12 w-12 mx-auto mb-3 text-gray-300" />
            <p>Sin reporte disponible.</p>
            <p className="text-xs mt-1">Haz click en "Regenerar ahora" para crear el snapshot del día actual.</p>
          </CardContent>
        </Card>
      )}

      {payload && (
        <>
          {/* ── Resumen ejecutivo ── */}
          <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
            <Card className="border-gray-200">
              <CardContent className="pt-6">
                <Metric label="Total Flota" value={payload.flota?.total_equipos ?? 0} sub="Equipos activos" />
              </CardContent>
            </Card>
            <Card className="border-green-200 bg-green-50">
              <CardContent className="pt-6">
                <Metric
                  label="OEE Mes"
                  value={`${payload.oee_mes?.total?.oee_promedio?.toFixed(1) ?? 0}%`}
                  sub={payload.oee_mes?.total?.clasificacion ?? ''}
                />
              </CardContent>
            </Card>
            <Card className="border-amber-200 bg-amber-50">
              <CardContent className="pt-6">
                <Metric
                  label="OTs Abiertas"
                  value={payload.mantenimiento?.ots_abiertas ?? 0}
                  sub={`${payload.mantenimiento?.tipo_correctivo_abierto ?? 0} correctivas`}
                />
              </CardContent>
            </Card>
            <Card className={cn('border', (payload.alertas?.criticas_activas ?? 0) > 0 ? 'border-red-200 bg-red-50' : 'border-gray-200')}>
              <CardContent className="pt-6">
                <Metric
                  label="Alertas Críticas"
                  value={payload.alertas?.criticas_activas ?? 0}
                  sub={`${payload.alertas?.total_activas ?? 0} totales`}
                />
              </CardContent>
            </Card>
          </div>

          {/* ── Tendencia + Distribución ── */}
          <div className="grid grid-cols-1 xl:grid-cols-2 gap-4">
            <TendenciaFlotaChart
              data={tendencia ?? []}
              isLoading={loadingTendencia}
              dias={diasTendencia}
              onChangeDias={setDiasTendencia}
            />
            <DistribucionEstadosChart
              data={tendencia ?? []}
              isLoading={loadingTendencia}
            />
          </div>

          {/* ── Cambios del día ── */}
          <CambiosEstadoDiaTimeline
            data={cambios ?? []}
            isLoading={loadingCambios}
            fecha={fechaSeleccionada}
          />

          {/* ── Flota ── */}
          <Section icon={Truck} title="Flota — Estado del Día" color="text-blue-600">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <h4 className="text-xs font-semibold text-gray-500 uppercase mb-2">Por estado del día</h4>
                <div className="space-y-1.5 text-sm">
                  {payload.flota?.por_estado_hoy ? Object.entries(payload.flota.por_estado_hoy)
                    .sort(([, a], [, b]) => (b as number) - (a as number))
                    .map(([k, v]) => (
                    <div key={k} className="flex items-center justify-between">
                      <span className="flex items-center gap-2">
                        <span className={cn(
                          'inline-block w-6 text-center rounded px-1 py-0.5 text-xs font-bold',
                          ESTADO_DIARIO_COLORS[k] || 'bg-gray-200 text-gray-700'
                        )}>
                          {k}
                        </span>
                        <span className="text-gray-600">{ESTADO_DIARIO_LABELS[k] || k}</span>
                      </span>
                      <span className="font-mono font-semibold">{v}</span>
                    </div>
                  )) : <p className="text-xs text-gray-400">Sin datos</p>}
                </div>
              </div>
              <div>
                <h4 className="text-xs font-semibold text-gray-500 uppercase mb-2">Por operación</h4>
                <div className="space-y-1 text-sm">
                  {payload.flota?.por_operacion ? Object.entries(payload.flota.por_operacion).map(([k, v]) => (
                    <div key={k} className="flex justify-between">
                      <span className="text-gray-600">{k}</span>
                      <span className="font-mono font-semibold">{v}</span>
                    </div>
                  )) : <p className="text-xs text-gray-400">Sin datos</p>}
                </div>
              </div>
            </div>
            {(payload.flota?.cambios_24h ?? 0) > 0 && (
              <div className="mt-3 rounded bg-blue-50 p-3 text-xs text-blue-800">
                <Activity className="h-3 w-3 inline mr-1" />
                {payload.flota?.cambios_24h} cambios manuales en las últimas 24 horas
              </div>
            )}
          </Section>

          {/* ── OEE ── */}
          <Section icon={Activity} title="OEE del Mes" color="text-green-600">
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
              {['total', 'coquimbo', 'calama'].map((key) => {
                const oee = (payload.oee_mes as any)?.[key]
                return (
                  <div key={key} className="rounded border border-gray-200 p-3">
                    <div className="text-xs font-semibold text-gray-500 uppercase">{key}</div>
                    <div className="mt-1 text-2xl font-bold">
                      {oee?.oee_promedio?.toFixed(1) ?? 0}%
                    </div>
                    <div className="text-xs text-gray-500">{oee?.clasificacion ?? '—'}</div>
                    <div className="mt-2 grid grid-cols-3 gap-1 text-xs">
                      <div><div className="text-gray-500">D</div><div className="font-semibold">{oee?.disponibilidad_promedio?.toFixed(0) ?? 0}%</div></div>
                      <div><div className="text-gray-500">U</div><div className="font-semibold">{oee?.utilizacion_promedio?.toFixed(0) ?? 0}%</div></div>
                      <div><div className="text-gray-500">Q</div><div className="font-semibold">{oee?.calidad_promedio?.toFixed(0) ?? 0}%</div></div>
                    </div>
                  </div>
                )
              })}
            </div>
          </Section>

          {/* ── Mantenimiento ── */}
          <Section icon={Wrench} title="Mantenimiento" color="text-orange-600">
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
              <Metric label="OTs abiertas" value={payload.mantenimiento?.ots_abiertas ?? 0} />
              <Metric label="Creadas ayer" value={payload.mantenimiento?.ots_creadas_ayer ?? 0} />
              <Metric label="Cerradas ayer" value={payload.mantenimiento?.ots_cerradas_ayer ?? 0} />
              <Metric label="Correctivas" value={payload.mantenimiento?.tipo_correctivo_abierto ?? 0} />
            </div>
            {payload.mantenimiento?.por_prioridad && (
              <div className="mt-4">
                <h4 className="text-xs font-semibold text-gray-500 uppercase mb-2">Por prioridad</h4>
                <div className="flex flex-wrap gap-2">
                  {Object.entries(payload.mantenimiento.por_prioridad).map(([k, v]) => (
                    <span key={k} className="inline-block rounded bg-orange-100 px-2 py-1 text-xs text-orange-700">
                      {k}: <strong>{v}</strong>
                    </span>
                  ))}
                </div>
              </div>
            )}
          </Section>

          {/* ── Comercial ── */}
          <Section icon={Briefcase} title="Comercial" color="text-purple-600">
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
              <Metric label="Arrendados" value={payload.comercial?.arrendados ?? 0} />
              <Metric label="Disponibles (pérdida)" value={payload.comercial?.disponibles_perdida ?? 0} />
              <Metric label="Uso interno" value={payload.comercial?.uso_interno ?? 0} />
              <Metric label="Leasing" value={payload.comercial?.leasing ?? 0} />
            </div>
            {payload.comercial?.por_cliente && (
              <div className="mt-4">
                <h4 className="text-xs font-semibold text-gray-500 uppercase mb-2">Distribución por cliente</h4>
                <div className="space-y-1 text-xs">
                  {Object.entries(payload.comercial.por_cliente).map(([cliente, cantidad]) => (
                    <div key={cliente} className="flex justify-between">
                      <span className="text-gray-600">{cliente}</span>
                      <span className="font-mono font-semibold">{cantidad}</span>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </Section>

          {/* ── Prevención ── */}
          <Section icon={HardHat} title="Prevención y Cumplimiento" color="text-amber-500">
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
              <Metric
                label="Cert. vencidas"
                value={payload.prevencion?.certificaciones_vencidas ?? 0}
                sub="Bloqueantes"
              />
              <Metric
                label="Cert. por vencer 30d"
                value={payload.prevencion?.certificaciones_por_vencer_30d ?? 0}
              />
              <Metric
                label="SEMEP vencidos"
                value={payload.prevencion?.conductores_semep_vencido ?? 0}
                sub="Conductores"
              />
              <Metric
                label="Fatiga crítica"
                value={payload.prevencion?.conductores_fatiga_critica ?? 0}
                sub="≥88 hrs espera"
              />
            </div>
            <div className="mt-4 grid grid-cols-2 md:grid-cols-4 gap-4">
              <Metric
                label="RESPEL generado mes"
                value={`${payload.prevencion?.respel_generado_mes_kg ?? 0} kg`}
              />
              <Metric
                label="RESPEL retirado mes"
                value={`${payload.prevencion?.respel_retirado_mes_kg ?? 0} kg`}
              />
              <Metric
                label="SIDREP pendientes"
                value={payload.prevencion?.retiros_sin_sidrep ?? 0}
              />
              <Metric
                label="Bodegas"
                value={payload.prevencion?.bodegas_total ?? 0}
                sub={`${payload.prevencion?.bodegas_autorizacion_vencida ?? 0} aut. vencidas`}
              />
            </div>
          </Section>

          {/* ── Alertas ── */}
          {(payload.alertas?.total_activas ?? 0) > 0 && (
            <Card className="border-red-200 bg-red-50">
              <CardHeader className="pb-2">
                <CardTitle className="text-red-700 flex items-center gap-2 text-base">
                  <AlertTriangle className="h-5 w-5" />
                  Alertas activas del sistema: {payload.alertas.total_activas}
                </CardTitle>
              </CardHeader>
              <CardContent className="text-sm text-red-800">
                {payload.alertas.criticas_activas > 0 && (
                  <p><strong>{payload.alertas.criticas_activas}</strong> son críticas. Revisar en el módulo de alertas.</p>
                )}
              </CardContent>
            </Card>
          )}

          <Card>
            <CardContent className="pt-6 text-xs text-gray-500">
              <p><strong>¿Cómo funciona este reporte?</strong></p>
              <p className="mt-1">
                El sistema genera un snapshot automático todos los días a las 06:30 de la mañana (hora Chile).
                El reporte contiene el estado consolidado de flota, OEE, mantenimiento, comercial y cumplimiento
                normativo. Se puede regenerar en cualquier momento con el botón de arriba.
              </p>
            </CardContent>
          </Card>
        </>
      )}
    </div>
  )
}
