'use client'

import { useState, useEffect, useCallback } from 'react'
import {
  Truck,
  Clock,
  Package,
  Coffee,
  Wrench,
  Moon,
  ArrowRightLeft,
  CircleCheck,
  AlertTriangle,
  MapPin,
  Timer,
  BarChart3,
  User,
  Shield,
} from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Spinner } from '@/components/ui/spinner'
import { cn } from '@/lib/utils'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useConductores } from '@/hooks/use-flota'
import {
  useRegistrarActividad,
  useActividadActual,
  useResumenDia,
  useResumenMes,
  useConductoresTiempoReal,
} from '@/hooks/use-jornada-conductor'
import {
  ACTIVIDAD_LABELS,
  ACTIVIDAD_COLORS,
  ACTIVIDAD_BG,
  obtenerUbicacionActual,
  type ActividadConductor,
} from '@/lib/services/jornada-conductor'

/* ─── Iconos por actividad ─────────────────────────────── */

const ACTIVIDAD_ICON_MAP: Record<ActividadConductor, typeof Truck> = {
  conduccion: Truck,
  espera: Clock,
  carga_descarga: Package,
  descanso: Coffee,
  mantencion: Wrench,
  pernocte: Moon,
  traslado_interno: ArrowRightLeft,
  disponible: CircleCheck,
}

/* ─── Botones de actividad para el conductor ───────────── */

const ACTIVIDADES_PRINCIPALES: ActividadConductor[] = [
  'conduccion',
  'espera',
  'carga_descarga',
  'descanso',
  'mantencion',
  'pernocte',
]

/* ─── Helpers ──────────────────────────────────────────── */

function formatDuracion(minutos: number): string {
  if (minutos < 60) return `${Math.round(minutos)} min`
  const hrs = Math.floor(minutos / 60)
  const min = Math.round(minutos % 60)
  return `${hrs}h ${min}m`
}

function formatHoras(horas: number): string {
  return `${horas.toFixed(1)} hrs`
}

/* ─── Page ─────────────────────────────────────────────── */

export default function JornadaConductorPage() {
  useRequireAuth()

  const [selectedConductor, setSelectedConductor] = useState<string>('')
  const [vista, setVista] = useState<'conductor' | 'supervisor'>('supervisor')

  const { data: conductores, isLoading: loadingConductores } = useConductores(true)
  const { data: conductoresTR } = useConductoresTiempoReal()
  const { data: actividadActual, isLoading: loadingActividad } = useActividadActual(
    selectedConductor || undefined
  )
  const { data: resumenDia } = useResumenDia(selectedConductor || undefined)
  const { data: resumenMes } = useResumenMes(selectedConductor || undefined)
  const registrar = useRegistrarActividad()

  const handleRegistrar = useCallback(
    async (actividad: ActividadConductor) => {
      if (!selectedConductor) return

      // Intentar obtener ubicación del navegador
      const ubicacion = await obtenerUbicacionActual()

      registrar.mutate({
        conductor_id: selectedConductor,
        actividad,
        latitud: ubicacion?.lat,
        longitud: ubicacion?.lon,
      })
    },
    [selectedConductor, registrar]
  )

  if (loadingConductores) {
    return (
      <div className="flex items-center justify-center h-64">
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
            <Timer className="h-7 w-7 text-blue-600" />
            Control de Jornada
          </h1>
          <p className="text-sm text-gray-500 mt-1">
            Ley 21.561 — Control de tiempos de espera y conduccion
          </p>
        </div>
        <div className="flex gap-2">
          <button
            className={cn(
              'px-3 py-1.5 rounded-md text-sm font-medium',
              vista === 'supervisor' ? 'bg-blue-600 text-white' : 'bg-gray-100 text-gray-700'
            )}
            onClick={() => setVista('supervisor')}
          >
            Vista Supervisor
          </button>
          <button
            className={cn(
              'px-3 py-1.5 rounded-md text-sm font-medium',
              vista === 'conductor' ? 'bg-blue-600 text-white' : 'bg-gray-100 text-gray-700'
            )}
            onClick={() => setVista('conductor')}
          >
            Vista Conductor
          </button>
        </div>
      </div>

      {/* ════════════════════════════════════════════════════ */}
      {/* VISTA SUPERVISOR: Panel de todos los conductores     */}
      {/* ════════════════════════════════════════════════════ */}
      {vista === 'supervisor' && (
        <div className="space-y-4">
          {/* Resumen rápido */}
          <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
            <Card className="bg-green-50 border-green-200">
              <CardContent className="p-4 text-center">
                <div className="text-2xl font-bold text-green-700">
                  {conductoresTR?.filter((c) => c.actividad_actual === 'conduccion').length ?? 0}
                </div>
                <div className="text-xs text-green-600">Conduciendo</div>
              </CardContent>
            </Card>
            <Card className="bg-amber-50 border-amber-200">
              <CardContent className="p-4 text-center">
                <div className="text-2xl font-bold text-amber-700">
                  {conductoresTR?.filter((c) => c.actividad_actual === 'espera').length ?? 0}
                </div>
                <div className="text-xs text-amber-600">En Espera</div>
              </CardContent>
            </Card>
            <Card className="bg-cyan-50 border-cyan-200">
              <CardContent className="p-4 text-center">
                <div className="text-2xl font-bold text-cyan-700">
                  {conductoresTR?.filter((c) => c.actividad_actual === 'descanso').length ?? 0}
                </div>
                <div className="text-xs text-cyan-600">En Descanso</div>
              </CardContent>
            </Card>
            <Card className="bg-red-50 border-red-200">
              <CardContent className="p-4 text-center">
                <div className="text-2xl font-bold text-red-700">
                  {conductoresTR?.filter((c) => c.estado_espera_mes !== 'OK').length ?? 0}
                </div>
                <div className="text-xs text-red-600">Con Alerta</div>
              </CardContent>
            </Card>
          </div>

          {/* Tabla de conductores en tiempo real */}
          <Card>
            <CardHeader>
              <CardTitle className="text-base flex items-center gap-2">
                <User className="h-5 w-5 text-gray-600" />
                Conductores en Tiempo Real
              </CardTitle>
            </CardHeader>
            <CardContent className="overflow-x-auto">
              <table className="w-full text-xs">
                <thead>
                  <tr className="border-b text-left text-gray-500 uppercase">
                    <th className="px-2 py-2">Conductor</th>
                    <th className="px-2 py-2">Vehiculo</th>
                    <th className="px-2 py-2">Actividad</th>
                    <th className="px-2 py-2">Duracion</th>
                    <th className="px-2 py-2">Conduccion Hoy</th>
                    <th className="px-2 py-2">Espera Hoy</th>
                    <th className="px-2 py-2">Cond. Continua</th>
                    <th className="px-2 py-2">Espera Mes</th>
                    <th className="px-2 py-2">SEMEP</th>
                    <th className="px-2 py-2">Estado</th>
                  </tr>
                </thead>
                <tbody>
                  {conductoresTR?.map((c) => {
                    const IconComp = c.actividad_actual
                      ? ACTIVIDAD_ICON_MAP[c.actividad_actual]
                      : CircleCheck

                    return (
                      <tr
                        key={c.conductor_id}
                        className={cn(
                          'border-b hover:bg-gray-50 cursor-pointer',
                          selectedConductor === c.conductor_id && 'bg-blue-50'
                        )}
                        onClick={() => {
                          setSelectedConductor(c.conductor_id)
                          setVista('conductor')
                        }}
                      >
                        <td className="px-2 py-2">
                          <div className="font-semibold">{c.nombre_completo}</div>
                          <div className="text-gray-400">{c.rut}</div>
                        </td>
                        <td className="px-2 py-2 font-mono">
                          {c.patente || '—'}
                        </td>
                        <td className="px-2 py-2">
                          {c.actividad_actual ? (
                            <span className={cn(
                              'inline-flex items-center gap-1 px-2 py-0.5 rounded text-xs',
                              ACTIVIDAD_COLORS[c.actividad_actual]
                            )}>
                              <IconComp className="h-3 w-3" />
                              {ACTIVIDAD_LABELS[c.actividad_actual]}
                            </span>
                          ) : (
                            <span className="text-gray-400">Sin registro</span>
                          )}
                        </td>
                        <td className="px-2 py-2">
                          {c.minutos_en_actividad
                            ? formatDuracion(c.minutos_en_actividad)
                            : '—'}
                        </td>
                        <td className="px-2 py-2">{formatHoras(c.hrs_conduccion_hoy)}</td>
                        <td className="px-2 py-2">{formatHoras(c.hrs_espera_hoy)}</td>
                        <td className="px-2 py-2">
                          <span className={cn(
                            c.hrs_conduccion_continua >= 5 ? 'text-red-600 font-bold' :
                            c.hrs_conduccion_continua >= 4 ? 'text-amber-600' : ''
                          )}>
                            {formatHoras(c.hrs_conduccion_continua)}
                          </span>
                        </td>
                        <td className="px-2 py-2">
                          <span className={cn(
                            c.estado_espera_mes === 'EXCEDIDO' ? 'text-red-600 font-bold' :
                            c.estado_espera_mes === 'ALERTA' ? 'text-amber-600 font-bold' : ''
                          )}>
                            {formatHoras(c.horas_espera_mes_actual)}
                          </span>
                        </td>
                        <td className="px-2 py-2">
                          {c.semep_vencido ? (
                            <span className="text-red-600 font-bold flex items-center gap-1">
                              <AlertTriangle className="h-3 w-3" /> Vencido
                            </span>
                          ) : (
                            <span className="text-green-600">OK</span>
                          )}
                        </td>
                        <td className="px-2 py-2">
                          {c.estado_espera_mes === 'EXCEDIDO' ? (
                            <span className="bg-red-100 text-red-700 px-2 py-0.5 rounded text-xs font-bold">
                              BLOQUEADO
                            </span>
                          ) : c.estado_espera_mes === 'ALERTA' ? (
                            <span className="bg-amber-100 text-amber-700 px-2 py-0.5 rounded text-xs font-bold">
                              ALERTA
                            </span>
                          ) : (
                            <span className="bg-green-100 text-green-700 px-2 py-0.5 rounded text-xs">
                              OK
                            </span>
                          )}
                        </td>
                      </tr>
                    )
                  })}
                  {(!conductoresTR || conductoresTR.length === 0) && (
                    <tr>
                      <td colSpan={10} className="px-4 py-8 text-center text-gray-400">
                        No hay conductores registrados. Registre conductores desde Administracion.
                      </td>
                    </tr>
                  )}
                </tbody>
              </table>
            </CardContent>
          </Card>
        </div>
      )}

      {/* ════════════════════════════════════════════════════ */}
      {/* VISTA CONDUCTOR: Botones de actividad + resumen      */}
      {/* ════════════════════════════════════════════════════ */}
      {vista === 'conductor' && (
        <div className="space-y-4">
          {/* Selector de conductor */}
          <Card>
            <CardContent className="p-4">
              <label className="block text-sm font-medium text-gray-700 mb-2">
                Conductor
              </label>
              <select
                className="w-full rounded-md border border-gray-300 px-3 py-2 text-sm"
                value={selectedConductor}
                onChange={(e) => setSelectedConductor(e.target.value)}
              >
                <option value="">Seleccionar conductor...</option>
                {conductores?.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.nombre_completo} ({c.rut})
                  </option>
                ))}
              </select>
            </CardContent>
          </Card>

          {selectedConductor && (
            <>
              {/* Actividad actual */}
              {actividadActual && (
                <Card className={cn(
                  'border-2',
                  actividadActual.actividad
                    ? ACTIVIDAD_BG[actividadActual.actividad as ActividadConductor]
                    : 'bg-gray-50'
                )}>
                  <CardContent className="p-6 text-center">
                    <div className="text-sm text-gray-500 mb-1">Actividad actual</div>
                    <div className="text-2xl font-bold mb-2">
                      {ACTIVIDAD_LABELS[actividadActual.actividad as ActividadConductor] || 'Sin actividad'}
                    </div>
                    <div className="text-lg text-gray-600">
                      {actividadActual.duracion_actual_min
                        ? formatDuracion(actividadActual.duracion_actual_min)
                        : ''}
                    </div>
                    {actividadActual.actividad === 'conduccion' && actividadActual.duracion_actual_min >= 240 && (
                      <div className="mt-2 bg-amber-100 text-amber-800 rounded-lg p-2 text-sm font-medium flex items-center justify-center gap-2">
                        <AlertTriangle className="h-4 w-4" />
                        {actividadActual.duracion_actual_min >= 300
                          ? 'DETENERSE: Supero 5 hrs de conduccion continua'
                          : `Atencion: ${formatDuracion(300 - actividadActual.duracion_actual_min)} para descanso obligatorio`
                        }
                      </div>
                    )}
                  </CardContent>
                </Card>
              )}

              {/* Botones de actividad - INTERFAZ PRINCIPAL DEL CONDUCTOR */}
              <Card>
                <CardHeader className="pb-2">
                  <CardTitle className="text-base">Cambiar Actividad</CardTitle>
                </CardHeader>
                <CardContent>
                  <div className="grid grid-cols-2 md:grid-cols-3 gap-3">
                    {ACTIVIDADES_PRINCIPALES.map((act) => {
                      const IconComp = ACTIVIDAD_ICON_MAP[act]
                      const isActive = actividadActual?.actividad === act

                      return (
                        <button
                          key={act}
                          onClick={() => handleRegistrar(act)}
                          disabled={registrar.isPending || isActive}
                          className={cn(
                            'flex flex-col items-center justify-center gap-2 p-4 rounded-xl border-2 transition-all',
                            'text-sm font-medium min-h-[80px]',
                            isActive
                              ? cn(ACTIVIDAD_COLORS[act], 'ring-2 ring-offset-2 ring-blue-500')
                              : 'bg-white border-gray-200 text-gray-700 hover:border-gray-400 hover:bg-gray-50',
                            registrar.isPending && 'opacity-50 cursor-not-allowed'
                          )}
                        >
                          <IconComp className="h-6 w-6" />
                          {ACTIVIDAD_LABELS[act]}
                        </button>
                      )
                    })}
                  </div>
                  {registrar.isPending && (
                    <div className="flex items-center justify-center gap-2 mt-3 text-sm text-gray-500">
                      <Spinner className="h-4 w-4" /> Registrando...
                    </div>
                  )}
                </CardContent>
              </Card>

              {/* Resumen del día */}
              <Card>
                <CardHeader className="pb-2">
                  <CardTitle className="text-base flex items-center gap-2">
                    <BarChart3 className="h-5 w-5 text-gray-600" />
                    Resumen del Dia
                  </CardTitle>
                </CardHeader>
                <CardContent>
                  {resumenDia && resumenDia.length > 0 ? (
                    <div className="space-y-2">
                      {resumenDia.map((r) => {
                        const act = r.actividad as ActividadConductor
                        return (
                          <div key={act} className="flex items-center gap-3">
                            <span className={cn(
                              'inline-flex items-center gap-1 px-2 py-0.5 rounded text-xs w-32',
                              ACTIVIDAD_COLORS[act]
                            )}>
                              {ACTIVIDAD_LABELS[act]}
                            </span>
                            <div className="flex-1 bg-gray-100 rounded-full h-4 overflow-hidden">
                              <div
                                className={cn(
                                  'h-full rounded-full',
                                  act === 'conduccion' ? 'bg-green-500' :
                                  act === 'espera' ? 'bg-amber-500' :
                                  act === 'descanso' ? 'bg-cyan-500' :
                                  'bg-gray-400'
                                )}
                                style={{ width: `${Math.min(r.porcentaje, 100)}%` }}
                              />
                            </div>
                            <span className="text-sm font-mono w-20 text-right">
                              {formatHoras(r.total_horas)}
                            </span>
                          </div>
                        )
                      })}
                    </div>
                  ) : (
                    <p className="text-sm text-gray-400 text-center py-4">
                      Sin actividades registradas hoy
                    </p>
                  )}
                </CardContent>
              </Card>

              {/* Cumplimiento mensual Ley 21.561 */}
              <Card>
                <CardHeader className="pb-2">
                  <CardTitle className="text-base flex items-center gap-2">
                    <Shield className="h-5 w-5 text-gray-600" />
                    Cumplimiento Ley 21.561 — Mes Actual
                  </CardTitle>
                </CardHeader>
                <CardContent>
                  {resumenMes && resumenMes.length > 0 ? (
                    <div className="space-y-3">
                      {resumenMes.map((r) => {
                        const act = r.actividad as ActividadConductor
                        return (
                          <div key={act} className="flex items-center justify-between">
                            <div>
                              <span className="font-medium text-sm">{ACTIVIDAD_LABELS[act]}</span>
                              <span className="text-gray-500 text-xs ml-2">({r.dias_con_actividad} dias)</span>
                            </div>
                            <div className="flex items-center gap-3">
                              <span className="text-sm font-mono">{formatHoras(r.total_horas)}</span>
                              {r.limite_legal && (
                                <>
                                  <span className="text-gray-400 text-xs">/ {r.limite_legal} hrs</span>
                                  <span className={cn(
                                    'px-2 py-0.5 rounded text-xs font-bold',
                                    r.estado_cumplimiento === 'EXCEDIDO' ? 'bg-red-100 text-red-700' :
                                    r.estado_cumplimiento === 'ALERTA' ? 'bg-amber-100 text-amber-700' :
                                    'bg-green-100 text-green-700'
                                  )}>
                                    {r.estado_cumplimiento}
                                    {r.porcentaje_limite && ` (${r.porcentaje_limite}%)`}
                                  </span>
                                </>
                              )}
                            </div>
                          </div>
                        )
                      })}
                    </div>
                  ) : (
                    <p className="text-sm text-gray-400 text-center py-4">
                      Sin datos del mes actual
                    </p>
                  )}
                </CardContent>
              </Card>
            </>
          )}
        </div>
      )}
    </div>
  )
}
