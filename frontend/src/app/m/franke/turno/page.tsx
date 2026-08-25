'use client'

// ============================================================================
// El turno de siete días (MIG392)
// ----------------------------------------------------------------------------
// Franke trabaja 7x7. El sistema sabía hacer la pauta diaria y la entrega de
// turno, pero no en qué día del turno estaba: cada día empezaba igual al
// anterior y nada avisaba que mañana había que entregar.
//
// LOS SIETE DÍAS JUNTOS, NO UNO A LA VEZ
// La tentación es hacer una lista de tareas por día. Pero en Franke lo que toca
// cada día es lo mismo —la pauta del camión y la de la camioneta— y lo que
// cambia es si se hizo o no. Ver los siete juntos muestra los huecos; repetir
// siete veces la misma lista no ordena nada.
//
// EL DÍA 7 TIENE NOMBRE PROPIO
// Lleva el objetivo del turno: entregar el estado de los equipos al que llega.
// Y ese estado no se escribe a mano — se calcula de los siete días. Un status
// que hay que redactar termina siendo una frase amable.
// ============================================================================

import { useEffect, useState } from 'react'
import Link from 'next/link'
import { useQuery } from '@tanstack/react-query'
import {
  ChevronLeft, CalendarDays, Loader2, CheckCircle2, AlertTriangle, Truck,
  Fuel, ClipboardCheck, Play, Printer,
} from 'lucide-react'
import { useToast } from '@/contexts/toast-context'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useAuth } from '@/contexts/auth-context'
import { getFaenaPorCodigo } from '@/lib/services/combustible-faena'
import {
  getCalendarioCiclo, abrirCicloTurno, getStatusCamiones,
  type DiaCiclo, type EquipoStatus, type StatusCamiones,
} from '@/lib/services/faena-entrega'
import { cn } from '@/lib/utils'

const FAENA_FRANKE = 'FAE-FRANCKE'

export default function TurnoFrankePage() {
  useRequireAuth()
  const { perfil } = useAuth()
  const toast = useToast()
  const [faenaId, setFaenaId] = useState<string | null>(null)
  const [verStatus, setVerStatus] = useState(false)
  const [abriendo, setAbriendo] = useState(false)

  useEffect(() => {
    getFaenaPorCodigo(FAENA_FRANKE)
      .then((f) => setFaenaId(f?.id ?? null))
      .catch(() => setFaenaId(null))
  }, [])

  const { data: cal, isLoading, refetch } = useQuery({
    queryKey: ['ciclo-franke', faenaId],
    queryFn: () => getCalendarioCiclo(faenaId!),
    enabled: !!faenaId,
    staleTime: 60_000,
  })

  const { data: status } = useQuery({
    queryKey: ['status-camiones', faenaId, cal?.ciclo_id],
    queryFn: () => getStatusCamiones(faenaId!, cal?.ciclo_id),
    enabled: !!faenaId && !!cal?.hay_ciclo && verStatus,
    staleTime: 30_000,
  })

  const abrir = async () => {
    if (!faenaId) return
    setAbriendo(true)
    try {
      const r = await abrirCicloTurno({ faenaId })
      toast.success(`Turno ${r.numero} abierto: del ${fecha(r.fecha_inicio)} al ${fecha(r.fecha_fin)}.`)
      refetch()
    } catch (e) {
      toast.error(e instanceof Error ? e.message : 'No se pudo abrir el turno')
    } finally { setAbriendo(false) }
  }

  if (isLoading || !faenaId) {
    return <div className="flex min-h-[60vh] items-center justify-center">
      <Loader2 className="h-6 w-6 animate-spin text-gray-400" />
    </div>
  }

  return (
    <div className="space-y-3 p-3 pb-24">
      <div className="flex items-center gap-2">
        <Link href="/m/franke" className="rounded-lg border border-gray-300 p-2">
          <ChevronLeft className="h-4 w-4 text-gray-600" />
        </Link>
        <div className="min-w-0 flex-1">
          <h1 className="text-base font-bold text-gray-900">El turno</h1>
          <p className="text-[11px] text-gray-500">Siete días · el último se entrega el status</p>
        </div>
      </div>

      {!cal?.hay_ciclo ? (
        <div className="rounded-xl border-2 border-dashed border-gray-300 p-6 text-center">
          <CalendarDays className="mx-auto h-8 w-8 text-gray-300" />
          <p className="mt-2 text-sm font-bold text-gray-700">No hay turno abierto</p>
          <p className="mt-1 text-xs text-gray-500">
            El turno se abre el día que entra la gente. De ahí el sistema cuenta solo.
          </p>
          <button onClick={abrir} disabled={abriendo}
                  className="mt-3 inline-flex items-center gap-1.5 rounded-lg bg-gray-900 px-4 py-2 text-xs font-bold text-white disabled:opacity-50">
            {abriendo ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Play className="h-3.5 w-3.5" />}
            Abrir el turno hoy
          </button>
        </div>
      ) : (
        <>
          {/* Cabecera del ciclo */}
          <div className="rounded-xl border-2 border-gray-800 bg-white p-3">
            <div className="flex items-start justify-between gap-2">
              <div className="min-w-0">
                <p className="text-sm font-bold text-gray-900">
                  Turno {cal.numero}{cal.turno ? ` · ${cal.turno}` : ''}
                </p>
                <p className="text-[11px] text-gray-500">
                  Del {fecha(cal.fecha_inicio)} al {fecha(cal.fecha_fin)}
                </p>
              </div>
              {cal.dia_actual != null ? (
                <span className="shrink-0 rounded-lg bg-gray-900 px-3 py-1.5 text-center text-white">
                  <span className="block text-[9px] uppercase tracking-wide opacity-70">día</span>
                  <span className="block text-lg font-black leading-none">{cal.dia_actual}</span>
                </span>
              ) : (
                <span className="shrink-0 rounded-lg bg-amber-100 px-2.5 py-1.5 text-[11px] font-bold text-amber-900">
                  Turno corrido
                </span>
              )}
            </div>

            {/* Un turno que se pasó de largo se dice, no se disimula con un
                número que ya no significa nada. */}
            {cal.vencido && (
              <p className="mt-2 flex items-start gap-1.5 rounded-lg bg-amber-50 p-2 text-[11px] leading-snug text-amber-900">
                <AlertTriangle className="mt-px h-3.5 w-3.5 shrink-0" />
                Van {cal.dias_corridos} días desde que entró el turno y el ciclo era de {cal.dias_total}.
                Abra el turno nuevo cuando entre la gente.
              </p>
            )}

            {cal.es_dia_de_entrega && (
              <p className="mt-2 flex items-start gap-1.5 rounded-lg bg-orange-50 p-2 text-[11px] font-semibold leading-snug text-orange-900">
                <ClipboardCheck className="mt-px h-3.5 w-3.5 shrink-0" />
                Hoy es el último día: toca entregar el status de los camiones.
              </p>
            )}
          </div>

          {/* Los siete días */}
          <div className="space-y-1.5">
            {(cal.dias ?? []).map((d) => <FilaDia key={d.dia} d={d} />)}
          </div>

          {/* El status */}
          <button onClick={() => setVerStatus((v) => !v)}
                  className={cn('flex w-full items-center justify-center gap-2 rounded-xl px-4 py-3 text-sm font-bold',
                    cal.es_dia_de_entrega
                      ? 'bg-orange-600 text-white'
                      : 'border-2 border-gray-300 bg-white text-gray-700')}>
            <ClipboardCheck className="h-4 w-4" />
            {verStatus ? 'Ocultar el status' : 'Ver el status de los camiones'}
          </button>

          {verStatus && (
            status ? <Status s={status} /> : (
              <div className="flex justify-center py-6">
                <Loader2 className="h-5 w-5 animate-spin text-gray-400" />
              </div>
            )
          )}

          <button onClick={abrir} disabled={abriendo}
                  className="flex w-full items-center justify-center gap-1.5 rounded-lg border border-dashed border-gray-300 py-2.5 text-xs font-semibold text-gray-500">
            {abriendo ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Play className="h-3.5 w-3.5" />}
            Entró un turno nuevo — abrirlo hoy
          </button>
          <p className="text-center text-[10px] leading-snug text-gray-400">
            Al abrir el turno nuevo, el anterior se cierra solo. Su status queda guardado.
          </p>
        </>
      )}

      {perfil?.nombre_completo && (
        <p className="text-center text-[10px] text-gray-400">{perfil.nombre_completo}</p>
      )}
    </div>
  )
}

function FilaDia({ d }: { d: DiaCiclo }) {
  const sinPauta = d.pasado && d.pautas_hechas === 0
  return (
    <div className={cn('flex items-center gap-3 rounded-lg border-2 p-2.5',
      d.es_hoy ? 'border-gray-800 bg-gray-50'
      : d.entrega_status ? 'border-orange-300 bg-orange-50/40'
      : sinPauta ? 'border-amber-200 bg-amber-50/40'
      : 'border-gray-200 bg-white')}>
      <span className={cn('flex h-9 w-9 shrink-0 items-center justify-center rounded-lg text-sm font-black',
        d.es_hoy ? 'bg-gray-900 text-white'
        : d.entrega_status ? 'bg-orange-500 text-white'
        : d.pasado ? 'bg-gray-200 text-gray-600' : 'bg-gray-100 text-gray-400')}>
        {d.dia}
      </span>
      <div className="min-w-0 flex-1">
        <p className="text-sm font-semibold text-gray-900">
          {fecha(d.fecha)}
          {d.entrega_status && (
            <span className="ml-1.5 text-[10px] font-bold uppercase text-orange-700">
              status de los camiones
            </span>
          )}
        </p>
        <p className="truncate text-[11px] text-gray-500">
          {d.pautas_hechas > 0
            ? `${d.pautas_hechas} pauta${d.pautas_hechas === 1 ? '' : 's'} · ${d.equipos_revisados.join(', ')}`
            : sinPauta ? 'Sin pautas registradas'
            : d.es_hoy ? 'Todavía sin registrar' : '—'}
        </p>
      </div>
      {d.pautas_abiertas > 0 && (
        <span className="shrink-0 rounded-full bg-amber-100 px-2 py-0.5 text-[10px] font-bold text-amber-800">
          {d.pautas_abiertas} sin cerrar
        </span>
      )}
      {d.pautas_hechas > 0 && d.pautas_abiertas === 0 && (
        <CheckCircle2 className="h-4 w-4 shrink-0 text-green-600" />
      )}
      {sinPauta && <AlertTriangle className="h-4 w-4 shrink-0 text-amber-500" />}
    </div>
  )
}

function Status({ s }: { s: StatusCamiones }) {
  const comb = s.combustible
  return (
    <div className="space-y-3 rounded-xl border-2 border-orange-300 bg-white p-3">
      <div className="flex items-center justify-between gap-2">
        <div>
          <p className="text-sm font-bold text-gray-900">Status de los camiones</p>
          <p className="text-[11px] text-gray-500">
            Turno {s.numero} · del {fecha(s.desde)} al {fecha(s.hasta)}
          </p>
        </div>
        <button onClick={() => window.print()} title="Imprimir"
                className="shrink-0 rounded-lg border border-gray-300 p-2 text-gray-500 print:hidden">
          <Printer className="h-4 w-4" />
        </button>
      </div>

      {/* Cumplimiento del turno, arriba: es la pregunta que se hace primero */}
      <div className="flex items-center gap-3 rounded-lg bg-gray-50 p-2.5">
        <ClipboardCheck className="h-4 w-4 shrink-0 text-gray-500" />
        <p className="text-[11px] text-gray-700">
          <span className="font-bold text-gray-900">
            {s.pautas_cerradas} de {s.pautas_del_turno}
          </span>{' '}
          pautas cerradas en el turno
        </p>
      </div>

      {/* Equipo por equipo */}
      <div className="space-y-2">
        {(s.equipos ?? []).map((e) => <FichaEquipo key={e.activo_id} e={e} />)}
      </div>

      {/* Combustible */}
      {comb && (
        <div className="rounded-lg border border-gray-200 p-2.5">
          <p className="flex items-center gap-1.5 text-[11px] font-bold text-gray-700">
            <Fuel className="h-3.5 w-3.5" /> Combustible del turno
          </p>
          <p className="mt-1 text-[11px] text-gray-600">
            Despachado <b className="tabular-nums">{miles(comb.despachado_lt)} L</b>
            {' · '}recibido <b className="tabular-nums">{miles(comb.recibido_lt)} L</b>
          </p>
          <div className="mt-1.5 space-y-0.5">
            {comb.estanques.map((t) => (
              <p key={t.codigo} className="flex items-center gap-2 text-[11px]">
                <span className="min-w-0 flex-1 truncate text-gray-600">
                  {t.patente ?? t.codigo}
                </span>
                <span className="shrink-0 font-semibold tabular-nums text-gray-800">
                  {miles(t.stock_lt)} / {miles(t.capacidad_lt)} L
                </span>
              </p>
            ))}
          </div>
        </div>
      )}

      <p className="text-center text-[10px] text-gray-400">
        Calculado de los siete días, no escrito a mano.
      </p>
    </div>
  )
}

function FichaEquipo({ e }: { e: EquipoStatus }) {
  const cumple = e.dias_del_turno > 0 ? e.dias_con_pauta / e.dias_del_turno : 0
  return (
    <div className="rounded-lg border border-gray-200 p-2.5">
      <div className="flex items-center gap-2">
        <Truck className="h-4 w-4 shrink-0 text-gray-400" />
        <span className="text-sm font-bold text-gray-900">{e.patente}</span>
        <span className="min-w-0 flex-1 truncate text-[11px] text-gray-500">{e.nombre}</span>
        {e.estado && (
          <span className={cn('shrink-0 rounded-full px-2 py-0.5 text-[10px] font-semibold',
            e.estado === 'operativo' || e.estado === 'disponible'
              ? 'bg-green-100 text-green-700' : 'bg-amber-100 text-amber-800')}>
            {e.estado.replace(/_/g, ' ')}
          </span>
        )}
      </div>

      <p className="mt-1 flex flex-wrap gap-x-3 text-[11px] text-gray-600">
        {e.horometro != null && <span>Horómetro <b className="tabular-nums">{miles(e.horometro)} h</b></span>}
        {e.kilometraje != null && <span>Km <b className="tabular-nums">{miles(e.kilometraje)}</b></span>}
        <span className={cn(cumple < 1 && 'font-semibold text-amber-700')}>
          Pauta {e.dias_con_pauta}/{e.dias_del_turno} días
        </span>
      </p>

      {e.nc_abiertas > 0 && (
        <div className="mt-1.5 rounded bg-red-50 p-2">
          <p className="text-[11px] font-bold text-red-800">
            {e.nc_abiertas} no conformidad{e.nc_abiertas === 1 ? '' : 'es'} sin cerrar
          </p>
          {e.nc_detalle.slice(0, 3).map((n, i) => (
            <p key={i} className="mt-0.5 text-[10px] leading-snug text-red-700">
              · {n.descripcion}
            </p>
          ))}
          {e.nc_detalle.length > 3 && (
            <p className="mt-0.5 text-[10px] text-red-600">y {e.nc_detalle.length - 3} más</p>
          )}
        </div>
      )}
    </div>
  )
}

function fecha(f?: string | null) {
  if (!f) return '—'
  return new Date(`${f}T12:00:00`).toLocaleDateString('es-CL', {
    day: '2-digit', month: 'short',
  })
}

function miles(n: number | null | undefined) {
  return Number(n ?? 0).toLocaleString('es-CL', { maximumFractionDigits: 0 })
}
