'use client'

// ============================================================================
// Historial de mantenimiento del equipo (MIG310)
// ----------------------------------------------------------------------------
// Antes esta pantalla era una lista de folios: número, tipo, estado, costo. La
// pregunta que la gente le hace a un equipo no es "¿cuántas OT tuvo?", es "¿qué
// le hicieron y cuándo?". Así que cada intervención se abre y muestra las
// tareas ejecutadas, los repuestos que salieron de bodega y lo que quedó
// pendiente.
//
// Incluye las órdenes de servicio anteriores al sistema. Un equipo con 25
// intervenciones desde 2024 no puede aparecer con 7 porque las otras 18 son
// de antes de SICOM.
// ============================================================================

import { useMemo, useState } from 'react'
import Link from 'next/link'
import { useQuery } from '@tanstack/react-query'
import {
  Wrench, ChevronDown, ChevronRight, Package, AlertTriangle,
  Clock, Gauge, User, Archive, CheckCircle2, XCircle, Camera,
} from 'lucide-react'
import { Spinner } from '@/components/ui/spinner'
import { cn, formatDate, formatCLP } from '@/lib/utils'
import { getHistorialMantenimientoEquipo } from '@/lib/services/activos'
import type { IntervencionHistorial } from '@/lib/services/activos'

const TIPO_UI: Record<string, { label: string; cls: string }> = {
  preventivo: { label: 'Preventivo', cls: 'bg-blue-100 text-blue-700' },
  correctivo: { label: 'Correctivo', cls: 'bg-orange-100 text-orange-700' },
  predictivo: { label: 'Predictivo', cls: 'bg-purple-100 text-purple-700' },
  inspeccion: { label: 'Inspección', cls: 'bg-cyan-100 text-cyan-700' },
  servicio:   { label: 'Servicio',   cls: 'bg-gray-100 text-gray-700' },
}
const tipoUI = (t: string) => TIPO_UI[t] ?? { label: t, cls: 'bg-gray-100 text-gray-700' }

const num = (n: number | null | undefined) =>
  n == null ? null : Number(n).toLocaleString('es-CL', { maximumFractionDigits: 1 })

function Dato({ icon: Icon, children }: { icon: any; children: React.ReactNode }) {
  return (
    <span className="inline-flex items-center gap-1 text-xs text-gray-500">
      <Icon className="h-3.5 w-3.5 shrink-0 text-gray-400" />
      {children}
    </span>
  )
}

function Intervencion({ i, mostrarCostos }: { i: IntervencionHistorial; mostrarCostos: boolean }) {
  const [abierto, setAbierto] = useState(false)
  const ui = tipoUI(i.tipo)
  const esLegacy = i.origen === 'os_legacy'
  const hayDetalle =
    i.tareas.length > 0 || i.repuestos.length > 0 || i.hallazgos.length > 0 || !!i.trabajo_realizado

  return (
    <div className="overflow-hidden rounded-lg border border-gray-200 bg-white">
      <button
        onClick={() => hayDetalle && setAbierto((v) => !v)}
        className={cn(
          'flex w-full items-start gap-3 px-4 py-3 text-left',
          hayDetalle ? 'hover:bg-gray-50' : 'cursor-default',
        )}
      >
        {hayDetalle ? (
          abierto ? <ChevronDown className="mt-0.5 h-4 w-4 shrink-0 text-gray-400" />
                  : <ChevronRight className="mt-0.5 h-4 w-4 shrink-0 text-gray-400" />
        ) : (
          <span className="w-4 shrink-0" />
        )}

        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2">
            {esLegacy ? (
              <span className="font-mono text-sm font-bold text-gray-600">{i.folio}</span>
            ) : (
              <Link
                href={`/dashboard/ordenes-trabajo/${i.ref_id}`}
                onClick={(e) => e.stopPropagation()}
                className="font-mono text-sm font-bold text-blue-600 hover:underline"
              >
                {i.folio}
              </Link>
            )}
            <span className={cn('rounded-full px-2 py-0.5 text-[10px] font-bold', ui.cls)}>
              {ui.label}
            </span>
            {esLegacy && (
              <span
                className="inline-flex items-center gap-1 rounded-full bg-gray-100 px-2 py-0.5 text-[10px] font-semibold text-gray-500"
                title="Orden de servicio anterior al sistema, importada del registro histórico"
              >
                <Archive className="h-3 w-3" /> Registro anterior
              </span>
            )}
            <span className="text-xs text-gray-400">{i.fecha ? formatDate(i.fecha) : 'sin fecha'}</span>
          </div>

          {/* La primera línea de lo que se hizo, sin tener que abrir */}
          <p className="mt-1 line-clamp-2 text-xs text-gray-700">
            {i.trabajo_realizado?.split('\n')[0] ??
              i.motivo ??
              <span className="text-gray-400">Sin registro de trabajo ejecutado.</span>}
          </p>

          <div className="mt-1.5 flex flex-wrap gap-x-4 gap-y-1">
            {i.tareas_total > 0 && (
              <Dato icon={CheckCircle2}>
                {i.tareas_ok}/{i.tareas_total} tareas
                {i.tareas_no_ok > 0 && <span className="ml-1 font-semibold text-red-600">· {i.tareas_no_ok} no conforme</span>}
              </Dato>
            )}
            {i.repuestos_total > 0 && <Dato icon={Package}>{i.repuestos_total} repuesto(s)</Dato>}
            {i.hallazgos_total > 0 && (
              <Dato icon={AlertTriangle}>
                <span className="font-semibold text-amber-600">{i.hallazgos_total} hallazgo(s)</span>
              </Dato>
            )}
            {i.horas_hombre != null && Number(i.horas_hombre) > 0 && (
              <Dato icon={Clock}>{num(i.horas_hombre)} h</Dato>
            )}
            {i.km_al_cierre != null && Number(i.km_al_cierre) > 0 && (
              <Dato icon={Gauge}>{num(i.km_al_cierre)} km</Dato>
            )}
            {i.horas_al_cierre != null && Number(i.horas_al_cierre) > 0 && (
              <Dato icon={Gauge}>{num(i.horas_al_cierre)} hrs equipo</Dato>
            )}
            {i.responsable && <Dato icon={User}>{i.responsable}</Dato>}
          </div>
        </div>

        {mostrarCostos && i.costo != null && Number(i.costo) > 0 && (
          <span className="shrink-0 text-sm font-semibold text-gray-700">{formatCLP(Number(i.costo))}</span>
        )}
      </button>

      {abierto && (
        <div className="space-y-3 border-t border-gray-100 bg-gray-50/70 px-4 py-3">
          {i.trabajo_realizado && (
            <div>
              <p className="mb-1 text-[10px] font-bold uppercase tracking-wide text-gray-400">
                Trabajo realizado
              </p>
              <p className="whitespace-pre-line text-xs leading-relaxed text-gray-700">
                {i.trabajo_realizado}
              </p>
            </div>
          )}

          {i.motivo && (
            <div>
              <p className="mb-1 text-[10px] font-bold uppercase tracking-wide text-gray-400">
                {i.origen === 'ot' ? 'Motivo de la orden' : 'Observaciones'}
              </p>
              <p className="whitespace-pre-line text-xs leading-relaxed text-gray-600">{i.motivo}</p>
            </div>
          )}

          {i.tareas.length > 0 && (
            <div>
              <p className="mb-1 text-[10px] font-bold uppercase tracking-wide text-gray-400">
                Tareas de la pauta
              </p>
              <div className="space-y-1">
                {i.tareas.map((t, idx) => (
                  <div key={idx} className="flex items-start gap-2 rounded bg-white px-2 py-1.5">
                    {t.resultado === 'ok' ? (
                      <CheckCircle2 className="mt-0.5 h-3.5 w-3.5 shrink-0 text-emerald-500" />
                    ) : t.resultado === 'no_ok' ? (
                      <XCircle className="mt-0.5 h-3.5 w-3.5 shrink-0 text-red-500" />
                    ) : (
                      <span className="mt-1 h-3.5 w-3.5 shrink-0 rounded-full border border-gray-300" />
                    )}
                    <div className="min-w-0 flex-1">
                      <p className="text-xs text-gray-800">{t.descripcion}</p>
                      {t.observacion && (
                        <p className="text-[10px] text-gray-500">{t.observacion}</p>
                      )}
                      {!t.resultado && (
                        <p className="text-[10px] text-gray-400">No marcada</p>
                      )}
                    </div>
                    {t.foto_url && (
                      <a
                        href={t.foto_url}
                        target="_blank"
                        rel="noreferrer"
                        className="shrink-0 text-gray-400 hover:text-gray-600"
                        title="Ver foto"
                      >
                        <Camera className="h-3.5 w-3.5" />
                      </a>
                    )}
                  </div>
                ))}
              </div>
            </div>
          )}

          {i.repuestos.length > 0 && (
            <div>
              <p className="mb-1 text-[10px] font-bold uppercase tracking-wide text-gray-400">
                Repuestos y consumibles
              </p>
              <div className="space-y-1">
                {i.repuestos.map((r, idx) => (
                  <div key={idx} className="flex items-center gap-2 rounded bg-white px-2 py-1.5 text-xs">
                    <Package className="h-3.5 w-3.5 shrink-0 text-gray-300" />
                    <span className="min-w-0 flex-1 truncate text-gray-800">{r.producto}</span>
                    <span className="shrink-0 tabular-nums text-gray-500">x{num(r.cantidad)}</span>
                    {mostrarCostos && r.costo != null && (
                      <span className="shrink-0 tabular-nums text-gray-600">{formatCLP(Number(r.costo))}</span>
                    )}
                  </div>
                ))}
              </div>
            </div>
          )}

          {i.fuente && (
            <p className="text-[10px] italic text-gray-400">Fuente: {i.fuente}</p>
          )}

          {i.hallazgos.length > 0 && (
            <div>
              <p className="mb-1 text-[10px] font-bold uppercase tracking-wide text-gray-400">
                Hallazgos levantados en esta intervención
              </p>
              <div className="space-y-1">
                {i.hallazgos.map((h, idx) => (
                  <div key={idx} className="flex items-start gap-2 rounded bg-white px-2 py-1.5">
                    <AlertTriangle className="mt-0.5 h-3.5 w-3.5 shrink-0 text-amber-500" />
                    <p className="min-w-0 flex-1 text-xs text-gray-800">{h.descripcion}</p>
                    <span
                      className={cn(
                        'shrink-0 rounded-full px-2 py-0.5 text-[9px] font-bold',
                        h.resuelto ? 'bg-emerald-100 text-emerald-700' : 'bg-amber-100 text-amber-700',
                      )}
                    >
                      {h.resuelto ? 'Resuelto' : h.estado ?? 'Abierto'}
                    </span>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  )
}

export function HistorialMantenimiento({
  activoId,
  mostrarCostos = true,
}: {
  activoId: string
  mostrarCostos?: boolean
}) {
  const [filtro, setFiltro] = useState<'todo' | 'preventivo' | 'correctivo'>('todo')

  const { data, isLoading, error } = useQuery({
    queryKey: ['historial-mantenimiento', activoId],
    queryFn: async () => {
      const { data, error } = await getHistorialMantenimientoEquipo(activoId)
      if (error) throw error
      return data
    },
    enabled: !!activoId,
  })

  const lista = useMemo(() => {
    if (!data) return []
    if (filtro === 'todo') return data
    return data.filter((i) => i.tipo === filtro)
  }, [data, filtro])

  const resumen = useMemo(() => {
    if (!data?.length) return null
    const conFecha = data.filter((i) => i.fecha)
    const ultima = conFecha[0]?.fecha ?? null
    const kms = data.map((i) => Number(i.km_al_cierre)).filter((k) => k > 0)
    return {
      total: data.length,
      preventivos: data.filter((i) => i.tipo === 'preventivo').length,
      correctivos: data.filter((i) => i.tipo === 'correctivo').length,
      ultima,
      desde: conFecha[conFecha.length - 1]?.fecha ?? null,
      kmUltimo: kms.length ? Math.max(...kms) : null,
    }
  }, [data])

  if (isLoading) {
    return <div className="flex justify-center py-12"><Spinner className="h-8 w-8" /></div>
  }
  if (error) {
    return (
      <p className="py-10 text-center text-sm text-red-500">
        No se pudo cargar el historial: {(error as Error).message}
      </p>
    )
  }
  if (!data || data.length === 0) {
    return (
      <div className="py-12 text-center">
        <Wrench className="mx-auto mb-3 h-10 w-10 text-gray-300" />
        <p className="text-sm font-medium text-gray-500">Sin intervenciones registradas</p>
        <p className="mt-1 text-xs text-gray-400">
          Este equipo no tiene órdenes de trabajo ni órdenes de servicio históricas.
        </p>
      </div>
    )
  }

  return (
    <div className="space-y-3">
      {/* Encabezado: la vida del equipo en una línea */}
      {resumen && (
        <div className="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-gray-200 bg-white px-4 py-3">
          <div>
            <p className="text-sm font-semibold text-gray-900">
              {resumen.total} intervenciones
              {resumen.desde && (
                <span className="font-normal text-gray-500"> desde {formatDate(resumen.desde)}</span>
              )}
            </p>
            <p className="mt-0.5 text-xs text-gray-500">
              {resumen.preventivos} preventivas · {resumen.correctivos} correctivas
              {resumen.ultima && ` · última el ${formatDate(resumen.ultima)}`}
              {resumen.kmUltimo && ` · ${num(resumen.kmUltimo)} km en la última lectura`}
            </p>
          </div>
          <div className="flex flex-wrap items-center gap-2">
          {/* [04-09] El informe emitible del historial: lo que el cliente/mandante pide en papel. */}
          <Link href={`/dashboard/flota/historial-informe/${activoId}`} target="_blank"
                className="rounded-md border border-emerald-300 bg-emerald-50 px-2.5 py-1 text-xs font-semibold text-emerald-700 hover:bg-emerald-100">
            🖨 Informe del historial
          </Link>
          <div className="flex gap-1 rounded-lg bg-gray-100 p-1">
            {([
              ['todo', 'Todo'],
              ['preventivo', 'Preventivas'],
              ['correctivo', 'Correctivas'],
            ] as const).map(([k, label]) => (
              <button
                key={k}
                onClick={() => setFiltro(k)}
                className={cn(
                  'rounded-md px-2.5 py-1 text-xs font-medium transition-colors',
                  filtro === k ? 'bg-white text-gray-900 shadow-sm' : 'text-gray-500 hover:text-gray-700',
                )}
              >
                {label}
              </button>
            ))}
          </div>
          </div>
        </div>
      )}

      {lista.length === 0 ? (
        <p className="py-8 text-center text-sm text-gray-400">
          Sin intervenciones de ese tipo.
        </p>
      ) : (
        <div className="space-y-2">
          {lista.map((i) => (
            <Intervencion key={`${i.origen}-${i.ref_id}`} i={i} mostrarCostos={mostrarCostos} />
          ))}
        </div>
      )}
    </div>
  )
}
