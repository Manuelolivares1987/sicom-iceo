'use client'

import { useMemo, useState, useEffect } from 'react'
import Link from 'next/link'
import {
  ArrowLeft, CheckCircle2, X, Send, AlertTriangle, Camera, PenLine,
  Clock, MapPin, ClipboardCheck, RefreshCw, Eye, Radio, Calendar, Activity,
  Pause, Play, AlertCircle, CircleDashed, ChevronDown, ChevronRight,
} from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { Modal, ModalFooter } from '@/components/ui/modal'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useToast } from '@/contexts/toast-context'
import { useCalamaPlanificaciones } from '@/hooks/use-calama'
import {
  useJornadasPendientesSupervision, useEvidenciasPorOT, useFirmasPorJornada,
  useSupervisarJornada, useDevolverJornadaCorreccion,
  useJornadasPorPeriodo,
} from '@/hooks/use-calama-supervision'
import type {
  JornadaPendienteSupervision, JornadaEnVivo, CategoriaVivo, PeriodoFiltro,
} from '@/lib/services/calama-supervision'

const fmtHms = (s: number | null) => {
  if (!s || s <= 0) return '—'
  const h = Math.floor(s / 3600)
  const m = Math.floor((s % 3600) / 60)
  return h > 0 ? `${h}h ${m}m` : `${m}m`
}

type Tab = 'en_vivo' | 'pendientes' | 'hoy'

type RangoPreset = 'hoy' | 'ayer' | 'manana' | 'esta_semana' | 'prox_7d' | 'mes_actual' | 'personalizado'

const isoDate = (d: Date) => {
  const y = d.getFullYear(), m = String(d.getMonth() + 1).padStart(2, '0'), day = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${day}`
}
const addDays = (d: Date, n: number) => { const r = new Date(d); r.setDate(r.getDate() + n); return r }
const startOfWeekMonday = (d: Date) => {
  const r = new Date(d)
  const dow = r.getDay() || 7  // 1..7, lunes=1
  r.setDate(r.getDate() - (dow - 1))
  return r
}

function rangoDePreset(preset: RangoPreset, personalDesde: string, personalHasta: string): { desde: string; hasta: string; label: string } {
  const hoy = new Date()
  switch (preset) {
    case 'hoy':            return { desde: isoDate(hoy),                    hasta: isoDate(hoy),                    label: 'Hoy' }
    case 'ayer':           return { desde: isoDate(addDays(hoy, -1)),       hasta: isoDate(addDays(hoy, -1)),       label: 'Ayer' }
    case 'manana':         return { desde: isoDate(addDays(hoy, 1)),        hasta: isoDate(addDays(hoy, 1)),        label: 'Mañana' }
    case 'esta_semana':    return { desde: isoDate(startOfWeekMonday(hoy)), hasta: isoDate(addDays(startOfWeekMonday(hoy), 6)), label: 'Esta semana' }
    case 'prox_7d':        return { desde: isoDate(hoy),                    hasta: isoDate(addDays(hoy, 6)),        label: 'Próximos 7 días' }
    case 'mes_actual': {
      const d1 = new Date(hoy.getFullYear(), hoy.getMonth(), 1)
      const d2 = new Date(hoy.getFullYear(), hoy.getMonth() + 1, 0)
      return { desde: isoDate(d1), hasta: isoDate(d2), label: 'Mes actual' }
    }
    case 'personalizado':  return { desde: personalDesde || isoDate(hoy), hasta: personalHasta || isoDate(hoy), label: 'Personalizado' }
  }
}

const CAT_LABEL: Record<CategoriaVivo, string> = {
  corriendo: 'En ejecución',
  pausada: 'En pausa',
  en_faena_sin_iniciar: 'Llegó pero no inició',
  pendiente_inicio: 'Pendiente de inicio',
  cerrada_hoy: 'Cerrada hoy',
}

const CAT_COLOR: Record<CategoriaVivo, string> = {
  corriendo: 'bg-emerald-100 text-emerald-700 border-emerald-300',
  pausada: 'bg-amber-100 text-amber-700 border-amber-300',
  en_faena_sin_iniciar: 'bg-sky-100 text-sky-700 border-sky-300',
  pendiente_inicio: 'bg-slate-100 text-slate-700 border-slate-300',
  cerrada_hoy: 'bg-purple-100 text-purple-700 border-purple-300',
}

const CAT_ICON: Record<CategoriaVivo, React.ComponentType<{ className?: string }>> = {
  corriendo: Play,
  pausada: Pause,
  en_faena_sin_iniciar: AlertCircle,
  pendiente_inicio: CircleDashed,
  cerrada_hoy: CheckCircle2,
}

// Tiempo efectivo "en vivo": para `corriendo` suma la fraccion desde last_event_at.
function tiempoEnVivoSeg(j: JornadaEnVivo, nowSeg: number): number {
  const base = Number(j.tiempo_efectivo_segundos ?? 0)
  if (j.ejecucion_estado === 'en_ejecucion' && j.last_event_at) {
    const last = Math.floor(new Date(j.last_event_at).getTime() / 1000)
    return base + Math.max(0, nowSeg - last)
  }
  return base
}

export default function AceptacionesPage() {
  useRequireAuth()
  const toast = useToast()

  const [tab, setTab] = useState<Tab>('en_vivo')
  const { data: planificaciones } = useCalamaPlanificaciones()
  const [planFiltro, setPlanFiltro] = useState<string>('')
  const filtro = useMemo(
    () => (planFiltro ? { planificacionId: planFiltro } : undefined),
    [planFiltro],
  )

  const { data: jornadas, isLoading, error, refetch, isFetching } =
    useJornadasPendientesSupervision(filtro)

  // Selector de período
  const [periodoPreset, setPeriodoPreset] = useState<RangoPreset>('hoy')
  const [personalDesde, setPersonalDesde] = useState('')
  const [personalHasta, setPersonalHasta] = useState('')
  const rango = useMemo(
    () => rangoDePreset(periodoPreset, personalDesde, personalHasta),
    [periodoPreset, personalDesde, personalHasta],
  )

  const periodoFiltro: PeriodoFiltro = useMemo(() => ({
    desde: rango.desde,
    hasta: rango.hasta,
    planificacionId: planFiltro || null,
    // Si el rango incluye HOY, agregamos las ejecuciones activas aunque
    // su fecha planificada sea otra (operador trabajando con jornada de
    // otro dia).
    incluirEjecucionesActivas:
      rango.desde <= isoDate(new Date()) && rango.hasta >= isoDate(new Date()),
  }), [rango, planFiltro])

  const enVivo = useJornadasPorPeriodo(periodoFiltro)

  // Resumen del periodo computado client-side desde el dataset
  const resumenPeriodo = useMemo(() => {
    const arr = enVivo.data ?? []
    return {
      total_jornadas: arr.length,
      corriendo:             arr.filter((j) => j.categoria_vivo === 'corriendo').length,
      pausadas:              arr.filter((j) => j.categoria_vivo === 'pausada').length,
      en_faena_sin_iniciar:  arr.filter((j) => j.categoria_vivo === 'en_faena_sin_iniciar').length,
      pendientes_inicio:     arr.filter((j) => j.categoria_vivo === 'pendiente_inicio').length,
      cerradas_hoy:          arr.filter((j) => j.categoria_vivo === 'cerrada_hoy').length,
      pendientes_supervision: arr.filter((j) => ['finalizada_operador','pendiente_aprobacion'].includes(j.estado_plan)).length,
      aceptadas_hoy:         arr.filter((j) => ['aceptada','cerrada'].includes(j.estado_plan)).length,
      requieren_correccion:  arr.filter((j) => j.estado_plan === 'requiere_correccion').length,
      total_seg_efectivo_cerradas: arr.reduce((s, j) => s + Number(j.tiempo_efectivo_trabajo_segundos ?? 0), 0),
      total_seg_efectivo_en_vivo:  arr.reduce((s, j) => s + Number(j.tiempo_efectivo_segundos ?? 0), 0),
      total_seg_interferencia:     arr.reduce((s, j) => s + Number(j.tiempo_interferencia_mandante_segundos ?? 0), 0),
    }
  }, [enVivo.data])

  // tick para que los timers en vivo se refresquen cada 5s sin polling extra
  const [nowSeg, setNowSeg] = useState(() => Math.floor(Date.now() / 1000))
  useEffect(() => {
    const id = setInterval(() => setNowSeg(Math.floor(Date.now() / 1000)), 5000)
    return () => clearInterval(id)
  }, [])

  const [detalleAbierto, setDetalleAbierto] = useState<JornadaPendienteSupervision | null>(null)
  const [aceptarAbierto, setAceptarAbierto] = useState<JornadaPendienteSupervision | null>(null)
  const [devolverAbierto, setDevolverAbierto] = useState<JornadaPendienteSupervision | null>(null)
  const [comentario, setComentario] = useState('')
  const [motivoDev, setMotivoDev] = useState('')
  const [obsDev, setObsDev] = useState('')

  const supervisar = useSupervisarJornada()
  const devolver = useDevolverJornadaCorreccion()

  const ejecutarAceptar = () => {
    if (!aceptarAbierto) return
    supervisar.mutate(
      { plan_semanal_ot_id: aceptarAbierto.plan_semanal_ot_id, comentario: comentario || undefined },
      {
        onSuccess: (d) => {
          const estado = (d as { estado_plan_nuevo?: string } | null)?.estado_plan_nuevo ?? 'aceptada'
          toast.success(`Jornada ${estado} (OT ${aceptarAbierto.folio.slice(-12)})`)
          setAceptarAbierto(null)
          setDetalleAbierto(null)
          setComentario('')
        },
        onError: (e) => {
          toast.error(e instanceof Error ? e.message : 'Error al supervisar')
        },
      },
    )
  }

  const ejecutarDevolver = () => {
    if (!devolverAbierto || !motivoDev.trim()) return
    devolver.mutate(
      {
        plan_semanal_ot_id: devolverAbierto.plan_semanal_ot_id,
        motivo: motivoDev.trim(),
        observacion: obsDev || undefined,
      },
      {
        onSuccess: () => {
          toast.success(`Jornada devuelta para corrección (OT ${devolverAbierto.folio.slice(-12)})`)
          setDevolverAbierto(null)
          setDetalleAbierto(null)
          setMotivoDev('')
          setObsDev('')
        },
        onError: (e) => {
          toast.error(e instanceof Error ? e.message : 'Error al devolver')
        },
      },
    )
  }

  return (
    <div className="space-y-4">
      <Link
        href="/dashboard/operacion-calama"
        className="inline-flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700"
      >
        <ArrowLeft className="h-4 w-4" />
        Volver al dashboard
      </Link>

      <div className="rounded-2xl bg-gradient-to-r from-emerald-700 to-teal-600 p-6 text-white shadow-lg">
        <h1 className="text-2xl font-bold flex items-center gap-2">
          <ClipboardCheck className="h-6 w-6" />
          Aceptaciones — Supervisor
        </h1>
        <p className="text-sm text-white/90 mt-1">
          Sigue el trabajo en vivo y valida el avance del día. Auto-refresh cada 30s.
        </p>
      </div>

      {/* Tabs */}
      <div className="flex gap-1 overflow-x-auto rounded-xl bg-gray-100 p-1">
        {([
          ['en_vivo',    'EN VIVO',       <Radio key="iv" className="h-4 w-4" />,
            (enVivo.data ?? []).filter((j) => j.categoria_vivo === 'corriendo' || j.categoria_vivo === 'pausada').length],
          ['pendientes', 'Pendientes OK', <ClipboardCheck key="ip" className="h-4 w-4" />, (jornadas ?? []).length],
          ['hoy',        `Resumen (${rango.label})`,  <Calendar key="ih" className="h-4 w-4" />, resumenPeriodo.total_jornadas],
        ] as Array<[Tab, string, React.ReactNode, number]>).map(([k, label, icon, badge]) => (
          <button
            key={k}
            onClick={() => setTab(k)}
            className={`flex-1 min-w-[140px] flex items-center justify-center gap-2 rounded-lg px-3 py-2 text-sm font-medium transition ${
              tab === k ? 'bg-white text-gray-900 shadow-sm' : 'text-gray-600 hover:text-gray-800'
            }`}
          >
            {icon}
            <span>{label}</span>
            {badge > 0 && (
              <span className={`rounded-full px-2 text-xs font-semibold ${
                tab === k ? 'bg-emerald-100 text-emerald-700' : 'bg-gray-200 text-gray-600'
              }`}>{badge}</span>
            )}
            {k === 'en_vivo' && tab === k && (
              <span className="relative flex h-2 w-2">
                <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75"></span>
                <span className="relative inline-flex rounded-full h-2 w-2 bg-emerald-500"></span>
              </span>
            )}
          </button>
        ))}
      </div>

      {/* Selector de período (aplica a EN VIVO y Resumen, no a Pendientes OK) */}
      <Card>
        <CardContent className="p-3 space-y-2">
          <div className="text-xs uppercase tracking-wide text-gray-500">
            Período {tab === 'pendientes' && <span className="text-gray-400 normal-case">(no aplica a Pendientes OK)</span>}
          </div>
          <div className="flex flex-wrap gap-1">
            {([
              ['hoy',         'Hoy'],
              ['ayer',        'Ayer'],
              ['manana',      'Mañana'],
              ['esta_semana', 'Esta semana'],
              ['prox_7d',     'Próx 7 días'],
              ['mes_actual',  'Mes actual'],
              ['personalizado', 'Personalizado'],
            ] as Array<[RangoPreset, string]>).map(([k, label]) => (
              <button
                key={k}
                onClick={() => setPeriodoPreset(k)}
                className={`rounded-full px-3 py-1 text-xs font-medium transition ${
                  periodoPreset === k
                    ? 'bg-emerald-600 text-white'
                    : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
                }`}
              >
                {label}
              </button>
            ))}
          </div>
          {periodoPreset === 'personalizado' && (
            <div className="flex flex-wrap items-end gap-2 pt-1">
              <div>
                <label className="text-[10px] text-gray-500 block">Desde</label>
                <input type="date" value={personalDesde} onChange={(e) => setPersonalDesde(e.target.value)}
                  className="rounded border border-gray-300 px-2 py-1 text-xs" />
              </div>
              <div>
                <label className="text-[10px] text-gray-500 block">Hasta</label>
                <input type="date" value={personalHasta} onChange={(e) => setPersonalHasta(e.target.value)}
                  className="rounded border border-gray-300 px-2 py-1 text-xs" />
              </div>
            </div>
          )}
          <div className="text-[11px] text-gray-500 pt-1">
            Rango activo: <strong>{rango.desde}</strong> → <strong>{rango.hasta}</strong>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardContent className="p-3 flex flex-wrap gap-3 items-end">
          <div className="flex-1 min-w-[220px]">
            <label className="text-xs text-gray-500">Planificación</label>
            <select
              value={planFiltro}
              onChange={(e) => setPlanFiltro(e.target.value)}
              className="mt-1 w-full rounded border border-gray-300 px-3 py-2 text-sm"
            >
              <option value="">Todas</option>
              {(planificaciones ?? []).map((p) => (
                <option key={p.id} value={p.id}>
                  {p.codigo} — {p.nombre}
                </option>
              ))}
            </select>
          </div>
          <Button
            variant="secondary"
            onClick={() => {
              refetch()
              enVivo.refetch()
            }}
            disabled={isFetching || enVivo.isFetching}
          >
            <RefreshCw className={`h-4 w-4 ${(isFetching || enVivo.isFetching) ? 'animate-spin' : ''}`} /> Refrescar
          </Button>
        </CardContent>
      </Card>

      {/* TAB EN VIVO */}
      {tab === 'en_vivo' && (
        <EnVivoTabContent
          jornadas={enVivo.data ?? []}
          isLoading={enVivo.isLoading}
          nowSeg={nowSeg}
          rango={rango}
          onRevisar={(j) => setDetalleAbierto({
            // Adaptador: re-usa el mismo modal de detalle del tab Pendientes.
            plan_semanal_ot_id: j.plan_semanal_ot_id,
            ot_id: j.ot_id, folio: j.folio, titulo: j.titulo,
            linea_negocio: '', avance_pct: j.avance_pct, estado_plan: j.estado_plan,
            plan_dia_id: null, fecha_jornada: j.fecha_jornada, nombre_dia: j.nombre_dia,
            llegada_faena_at: j.llegada_faena_at, cierre_jornada_at: j.cierre_jornada_at,
            responsable_id: j.responsable_id, responsable_email: j.responsable_email,
            tiempo_en_faena_segundos: j.tiempo_en_faena_segundos,
            tiempo_operativo_bruto_segundos: j.tiempo_operativo_bruto_segundos,
            tiempo_pausado_segundos: j.tiempo_pausado_segundos,
            tiempo_colacion_segundos: j.tiempo_colacion_segundos,
            tiempo_interferencia_mandante_segundos: j.tiempo_interferencia_mandante_segundos,
            tiempo_efectivo_trabajo_segundos: j.tiempo_efectivo_trabajo_segundos,
            evid_antes: j.evid_antes, evid_durante: j.evid_durante,
            evid_despues: j.evid_despues, firmas_operador: j.firmas_operador,
            planificacion_id: j.planificacion_id,
            planificacion_codigo: j.planificacion_codigo,
          } as JornadaPendienteSupervision)}
        />
      )}

      {/* TAB HOY */}
      {tab === 'hoy' && (
        <HoyTabContent
          resumen={resumenPeriodo}
          jornadas={enVivo.data ?? []}
          rangoLabel={rango.label}
          rango={rango}
          nowSeg={nowSeg}
          onRevisar={(j) => setDetalleAbierto({
            plan_semanal_ot_id: j.plan_semanal_ot_id,
            ot_id: j.ot_id, folio: j.folio, titulo: j.titulo,
            linea_negocio: '', avance_pct: j.avance_pct, estado_plan: j.estado_plan,
            plan_dia_id: null, fecha_jornada: j.fecha_jornada, nombre_dia: j.nombre_dia,
            llegada_faena_at: j.llegada_faena_at, cierre_jornada_at: j.cierre_jornada_at,
            responsable_id: j.responsable_id, responsable_email: j.responsable_email,
            tiempo_en_faena_segundos: j.tiempo_en_faena_segundos,
            tiempo_operativo_bruto_segundos: j.tiempo_operativo_bruto_segundos,
            tiempo_pausado_segundos: j.tiempo_pausado_segundos,
            tiempo_colacion_segundos: j.tiempo_colacion_segundos,
            tiempo_interferencia_mandante_segundos: j.tiempo_interferencia_mandante_segundos,
            tiempo_efectivo_trabajo_segundos: j.tiempo_efectivo_trabajo_segundos,
            evid_antes: j.evid_antes, evid_durante: j.evid_durante,
            evid_despues: j.evid_despues, firmas_operador: j.firmas_operador,
            planificacion_id: j.planificacion_id,
            planificacion_codigo: j.planificacion_codigo,
          } as JornadaPendienteSupervision)}
        />
      )}

      {/* TAB PENDIENTES (lo original) */}
      {tab === 'pendientes' && (
        <>
          {isLoading && (
            <div className="flex items-center gap-2 text-sm text-gray-500">
              <Spinner className="h-4 w-4" /> Cargando jornadas pendientes…
            </div>
          )}
          {error && (
            <div className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">
              Error: {error instanceof Error ? error.message : 'desconocido'}
            </div>
          )}

          {jornadas && jornadas.length === 0 && (
            <Card>
              <CardContent className="p-8 text-center text-sm text-gray-500">
                <CheckCircle2 className="h-8 w-8 mx-auto text-emerald-400 mb-2" />
                No hay jornadas pendientes de aceptación.
              </CardContent>
            </Card>
          )}

          <div className="space-y-2">
            {(jornadas ?? []).map((j) => (
              <JornadaCard
                key={j.plan_semanal_ot_id}
                j={j}
                onRevisar={() => setDetalleAbierto(j)}
                onAprobar={() => setAceptarAbierto(j)}
                onDevolver={() => setDevolverAbierto(j)}
              />
            ))}
          </div>
        </>
      )}

      {/* Modal detalle */}
      {detalleAbierto && (
        <DetalleJornadaModal
          j={detalleAbierto}
          onClose={() => setDetalleAbierto(null)}
          onAprobar={() => setAceptarAbierto(detalleAbierto)}
          onDevolver={() => setDevolverAbierto(detalleAbierto)}
        />
      )}

      {/* Modal aceptar */}
      <Modal
        open={!!aceptarAbierto}
        onClose={() => !supervisar.isPending && (setAceptarAbierto(null), setComentario(''))}
        title="OK supervisor"
      >
        {aceptarAbierto && (
          <div className="space-y-3 text-sm">
            <div className="rounded border bg-gray-50 p-2 text-xs">
              <div className="font-mono text-gray-500">{aceptarAbierto.folio}</div>
              <div className="text-gray-900 mt-0.5">{aceptarAbierto.titulo ?? '—'}</div>
              <div className="mt-1 text-gray-600">
                Avance: <strong>{Number(aceptarAbierto.avance_pct ?? 0).toFixed(0)}%</strong> ·{' '}
                Estado destino: <strong>
                  {Number(aceptarAbierto.avance_pct ?? 0) >= 100 ? 'cerrada' : 'aceptada'}
                </strong>
              </div>
            </div>
            <div>
              <label className="text-xs text-gray-500">Comentario (opcional)</label>
              <textarea
                rows={3}
                value={comentario}
                onChange={(e) => setComentario(e.target.value)}
                placeholder="Ej: trabajo conforme, cumple inspección visual…"
                className="mt-1 w-full rounded border border-gray-300 px-3 py-2 text-sm"
              />
            </div>
          </div>
        )}
        <ModalFooter className="-mx-6 -mb-6 mt-4 px-6 pb-6 pt-4 border-t border-gray-100">
          <Button
            variant="secondary"
            onClick={() => { setAceptarAbierto(null); setComentario('') }}
            disabled={supervisar.isPending}
          >
            <X className="h-4 w-4" /> Cancelar
          </Button>
          <Button variant="primary" onClick={ejecutarAceptar} loading={supervisar.isPending}>
            <CheckCircle2 className="h-4 w-4" /> Confirmar OK supervisor
          </Button>
        </ModalFooter>
      </Modal>

      {/* Modal devolver */}
      <Modal
        open={!!devolverAbierto}
        onClose={() => !devolver.isPending && (setDevolverAbierto(null), setMotivoDev(''), setObsDev(''))}
        title="Devolver para corrección"
      >
        {devolverAbierto && (
          <div className="space-y-3 text-sm">
            <div className="rounded border bg-amber-50 p-2 text-xs text-amber-900">
              <div className="flex items-center gap-1 font-medium">
                <AlertTriangle className="h-4 w-4" />
                Esto reabrirá la OT para que el operador corrija
              </div>
              <div className="mt-1 font-mono text-amber-700">{devolverAbierto.folio}</div>
            </div>
            <div>
              <label className="text-xs text-gray-500">Motivo *</label>
              <input
                value={motivoDev}
                onChange={(e) => setMotivoDev(e.target.value)}
                placeholder="Ej: foto despues no muestra el sello, falta firma…"
                className="mt-1 w-full rounded border border-orange-300 px-3 py-2 text-sm"
              />
            </div>
            <div>
              <label className="text-xs text-gray-500">Observación (opcional)</label>
              <textarea
                rows={3}
                value={obsDev}
                onChange={(e) => setObsDev(e.target.value)}
                className="mt-1 w-full rounded border border-gray-300 px-3 py-2 text-sm"
              />
            </div>
          </div>
        )}
        <ModalFooter className="-mx-6 -mb-6 mt-4 px-6 pb-6 pt-4 border-t border-gray-100">
          <Button
            variant="secondary"
            onClick={() => { setDevolverAbierto(null); setMotivoDev(''); setObsDev('') }}
            disabled={devolver.isPending}
          >
            <X className="h-4 w-4" /> Cancelar
          </Button>
          <Button
            variant="danger"
            onClick={ejecutarDevolver}
            disabled={!motivoDev.trim()}
            loading={devolver.isPending}
          >
            <Send className="h-4 w-4" /> Devolver al operador
          </Button>
        </ModalFooter>
      </Modal>
    </div>
  )
}

function JornadaCard({
  j, onRevisar, onAprobar, onDevolver,
}: {
  j: JornadaPendienteSupervision
  onRevisar: () => void
  onAprobar: () => void
  onDevolver: () => void
}) {
  return (
    <Card>
      <CardContent className="p-3">
        <div className="flex flex-wrap items-start gap-3 justify-between">
          <div className="flex-1 min-w-[220px]">
            <div className="flex items-center gap-2 flex-wrap">
              <span className="font-mono text-xs text-gray-500">{j.folio}</span>
              <span className={`rounded-full px-2 py-0.5 text-[10px] font-semibold ${
                j.estado_plan === 'pendiente_aprobacion'
                  ? 'bg-amber-100 text-amber-700'
                  : 'bg-sky-100 text-sky-700'
              }`}>{j.estado_plan}</span>
              <span className="text-[10px] text-gray-500 uppercase">{j.linea_negocio}</span>
            </div>
            <div className="text-sm text-gray-900 mt-1">{j.titulo ?? '—'}</div>
            <div className="text-xs text-gray-500 mt-1 flex flex-wrap gap-3">
              {j.fecha_jornada && <span>📅 {j.nombre_dia} {j.fecha_jornada}</span>}
              {j.responsable_email && <span>👷 {j.responsable_email}</span>}
              <span>Avance: <strong>{Number(j.avance_pct ?? 0).toFixed(0)}%</strong></span>
              <span>Efectivo: <strong>{fmtHms(j.tiempo_efectivo_trabajo_segundos)}</strong></span>
            </div>
            <div className="text-xs text-gray-500 mt-1 flex gap-3">
              <span><Camera className="inline h-3 w-3" /> Antes: {j.evid_antes}</span>
              <span><Camera className="inline h-3 w-3" /> Durante: {j.evid_durante}</span>
              <span><Camera className="inline h-3 w-3" /> Después: {j.evid_despues}</span>
              <span><PenLine className="inline h-3 w-3" /> Firma op: {j.firmas_operador}</span>
            </div>
          </div>
          <div className="flex gap-1 flex-wrap">
            <Button variant="secondary" onClick={onRevisar}>
              <Eye className="h-4 w-4" /> Revisar
            </Button>
            <Button variant="primary" onClick={onAprobar}>
              <CheckCircle2 className="h-4 w-4" /> OK
            </Button>
            <Button variant="danger" onClick={onDevolver}>
              <Send className="h-4 w-4" /> Devolver
            </Button>
          </div>
        </div>
      </CardContent>
    </Card>
  )
}

function DetalleJornadaModal({
  j, onClose, onAprobar, onDevolver,
}: {
  j: JornadaPendienteSupervision
  onClose: () => void
  onAprobar: () => void
  onDevolver: () => void
}) {
  const { data: evidencias } = useEvidenciasPorOT(j.ot_id)
  const { data: firmas } = useFirmasPorJornada(j.plan_semanal_ot_id)

  const evGroup = useMemo(() => {
    const g: Record<string, typeof evidencias> = {}
    for (const e of evidencias ?? []) {
      g[e.contexto] = g[e.contexto] ?? []
      g[e.contexto]!.push(e)
    }
    return g
  }, [evidencias])

  const tiempos = [
    ['En faena',       j.tiempo_en_faena_segundos],
    ['Operativo',      j.tiempo_operativo_bruto_segundos],
    ['Efectivo',       j.tiempo_efectivo_trabajo_segundos],
    ['Pausado',        j.tiempo_pausado_segundos],
    ['Colación',       j.tiempo_colacion_segundos],
    ['Interferencia',  j.tiempo_interferencia_mandante_segundos],
  ] as const

  return (
    <Modal open onClose={onClose} title={`Revisar jornada — ${j.folio}`}>
      <div className="space-y-4 text-sm max-h-[70vh] overflow-y-auto pr-1">
        <section>
          <div className="text-xs uppercase text-gray-500 mb-1">Identificación</div>
          <div className="rounded border bg-gray-50 p-2 space-y-1">
            <div className="font-mono text-xs text-gray-500">{j.folio}</div>
            <div className="text-gray-900">{j.titulo ?? '—'}</div>
            <div className="text-xs text-gray-600">
              {j.linea_negocio} · Plan {j.planificacion_codigo}
            </div>
            <div className="text-xs text-gray-600">
              {j.fecha_jornada && <span>📅 {j.nombre_dia} {j.fecha_jornada} · </span>}
              {j.responsable_email && <span>👷 {j.responsable_email} · </span>}
              <span>Avance: <strong>{Number(j.avance_pct ?? 0).toFixed(0)}%</strong></span>
            </div>
          </div>
        </section>

        <section>
          <div className="text-xs uppercase text-gray-500 mb-1 flex items-center gap-1">
            <Clock className="h-3 w-3" /> Tiempos
          </div>
          <div className="grid grid-cols-3 gap-2">
            {tiempos.map(([label, seg]) => (
              <div key={label} className="rounded border bg-white p-2 text-xs">
                <div className="text-gray-500">{label}</div>
                <div className="font-medium text-gray-900 mt-0.5">{fmtHms(seg)}</div>
              </div>
            ))}
          </div>
        </section>

        <section>
          <div className="text-xs uppercase text-gray-500 mb-1 flex items-center gap-1">
            <Camera className="h-3 w-3" /> Evidencias por momento ({(evidencias ?? []).length})
          </div>
          {['llegada_faena', 'jornada_antes', 'jornada_durante', 'jornada_despues',
            'interferencia_mandante', 'jornada_rechazo'].map((ctx) => {
            const arr = evGroup[ctx] ?? []
            if (arr.length === 0) return null
            return (
              <div key={ctx} className="mb-2">
                <div className="text-[10px] uppercase text-gray-400 mb-1">{ctx}</div>
                <div className="grid grid-cols-3 sm:grid-cols-4 gap-2">
                  {arr.map((e) => (
                    <a
                      key={e.id}
                      href={e.archivo_url}
                      target="_blank"
                      rel="noreferrer"
                      className="block aspect-square rounded border border-gray-200 overflow-hidden bg-gray-50 hover:ring-2 hover:ring-emerald-400 relative"
                    >
                      {/* eslint-disable-next-line @next/next/no-img-element */}
                      <img src={e.archivo_url} alt={e.contexto} className="w-full h-full object-cover" />
                      {e.gps_lat && e.gps_lng && (
                        <span className="absolute bottom-0 left-0 right-0 bg-black/50 text-white text-[9px] px-1 py-0.5 flex items-center gap-0.5">
                          <MapPin className="h-2.5 w-2.5" /> GPS
                        </span>
                      )}
                    </a>
                  ))}
                </div>
              </div>
            )
          })}
          {(evidencias ?? []).length === 0 && (
            <div className="rounded border border-dashed border-red-200 bg-red-50 p-3 text-xs text-red-700">
              ⚠ No hay evidencias registradas en BD para esta OT. Revisa sincronización offline (ver D1_diagnostico_evidencias_calama.sql).
            </div>
          )}
        </section>

        <section>
          <div className="text-xs uppercase text-gray-500 mb-1 flex items-center gap-1">
            <PenLine className="h-3 w-3" /> Firmas ({(firmas ?? []).length})
          </div>
          <div className="grid grid-cols-2 gap-2">
            {(firmas ?? []).map((f) => (
              <div key={f.id} className="rounded border p-2 bg-white">
                <div className="flex items-center justify-between text-xs">
                  <span className="font-medium">{f.firmante_tipo}</span>
                  <span className="text-gray-500">{f.contexto ?? '—'}</span>
                </div>
                {f.firmante_nombre && <div className="text-xs text-gray-700">{f.firmante_nombre}</div>}
                <a href={f.firma_url} target="_blank" rel="noreferrer" className="block mt-1 border rounded bg-gray-50 overflow-hidden">
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img src={f.firma_url} alt="firma" className="w-full h-24 object-contain" />
                </a>
                {f.observacion && <div className="text-[10px] text-gray-500 mt-1 italic">{f.observacion}</div>}
              </div>
            ))}
            {(firmas ?? []).length === 0 && (
              <div className="col-span-2 rounded border border-dashed border-gray-200 p-3 text-xs text-gray-400">
                Sin firmas registradas para esta jornada.
              </div>
            )}
          </div>
        </section>
      </div>
      <ModalFooter className="-mx-6 -mb-6 mt-4 px-6 pb-6 pt-4 border-t border-gray-100">
        <Button variant="secondary" onClick={onClose}>
          <X className="h-4 w-4" /> Cerrar
        </Button>
        <Button variant="danger" onClick={onDevolver}>
          <Send className="h-4 w-4" /> Devolver para corrección
        </Button>
        <Button variant="primary" onClick={onAprobar}>
          <CheckCircle2 className="h-4 w-4" /> OK supervisor
        </Button>
      </ModalFooter>
    </Modal>
  )
}

// ─── TAB EN VIVO ────────────────────────────────────────────────────────────

function EnVivoTabContent({
  jornadas, isLoading, nowSeg, rango, onRevisar,
}: {
  jornadas: JornadaEnVivo[]
  isLoading: boolean
  nowSeg: number
  rango: { desde: string; hasta: string; label: string }
  onRevisar: (j: JornadaEnVivo) => void
}) {
  // Agrupar por categoria_vivo
  const grupos = useMemo(() => {
    const g: Record<CategoriaVivo, JornadaEnVivo[]> = {
      corriendo: [], pausada: [], en_faena_sin_iniciar: [],
      pendiente_inicio: [], cerrada_hoy: [],
    }
    for (const j of jornadas) g[j.categoria_vivo].push(j)
    return g
  }, [jornadas])

  const esMultiDia = rango.desde !== rango.hasta

  if (isLoading) {
    return (
      <div className="flex items-center gap-2 text-sm text-gray-500">
        <Spinner className="h-4 w-4" /> Cargando jornadas en vivo…
      </div>
    )
  }

  if (jornadas.length === 0) {
    return (
      <Card>
        <CardContent className="p-8 text-center text-sm text-gray-500">
          <Activity className="h-8 w-8 mx-auto text-gray-300 mb-2" />
          No hay jornadas activas en el período seleccionado.
        </CardContent>
      </Card>
    )
  }

  // MULTI-DIA: render calendario (stack vertical por día)
  if (esMultiDia) {
    return <CalendarioPorDia jornadas={jornadas} rango={rango} nowSeg={nowSeg} onRevisar={onRevisar} />
  }

  // 1 DIA: agrupado por categoría (comportamiento anterior)
  const orden: CategoriaVivo[] = [
    'corriendo', 'pausada', 'en_faena_sin_iniciar', 'pendiente_inicio', 'cerrada_hoy',
  ]

  return (
    <div className="space-y-4">
      {orden.map((cat) => {
        const items = grupos[cat]
        if (items.length === 0) return null
        const Icon = CAT_ICON[cat]
        return (
          <section key={cat}>
            <h2 className="text-xs uppercase tracking-wide text-gray-500 mb-2 flex items-center gap-2">
              <Icon className="h-4 w-4" />
              {CAT_LABEL[cat]}
              <span className="rounded-full bg-gray-100 px-2 py-0.5 text-[10px] font-semibold text-gray-600">
                {items.length}
              </span>
            </h2>
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-2">
              {items.map((j) => (
                <EnVivoCard key={j.plan_semanal_ot_id} j={j} nowSeg={nowSeg} onRevisar={() => onRevisar(j)} />
              ))}
            </div>
          </section>
        )
      })}
    </div>
  )
}

function EnVivoCard({
  j, nowSeg, onRevisar,
}: { j: JornadaEnVivo; nowSeg: number; onRevisar: () => void }) {
  const cat = j.categoria_vivo
  const tEfectivo = tiempoEnVivoSeg(j, nowSeg)
  return (
    <Card className={`border-l-4 ${cat === 'corriendo' ? 'border-l-emerald-500' :
      cat === 'pausada' ? 'border-l-amber-500' :
      cat === 'en_faena_sin_iniciar' ? 'border-l-sky-500' :
      cat === 'cerrada_hoy' ? 'border-l-purple-500' : 'border-l-slate-300'}`}>
      <CardContent className="p-3">
        <div className="flex items-start gap-3">
          {j.ultima_evidencia_url ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={j.ultima_evidencia_url}
              alt="última evidencia"
              className="w-16 h-16 rounded object-cover border bg-gray-100 flex-shrink-0"
            />
          ) : (
            <div className="w-16 h-16 rounded border bg-gray-50 flex items-center justify-center flex-shrink-0">
              <Camera className="h-5 w-5 text-gray-300" />
            </div>
          )}
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2 flex-wrap">
              <span className={`rounded-full px-2 py-0.5 text-[10px] font-semibold border ${CAT_COLOR[cat]}`}>
                {CAT_LABEL[cat]}
              </span>
              <span className="font-mono text-[11px] text-gray-500">{j.folio}</span>
            </div>
            <div className="text-sm text-gray-900 truncate mt-0.5">{j.titulo ?? '—'}</div>
            <div className="text-[11px] text-gray-500 flex flex-wrap gap-x-3 gap-y-0.5 mt-1">
              {(j.ejecutor_nombre || j.responsable_nombre) && (
                <span>👷 {j.ejecutor_nombre || j.responsable_nombre}</span>
              )}
              <span>Avance: <strong>{Number(j.avance_pct ?? 0).toFixed(0)}%</strong></span>
              {j.ejecucion_estado && (
                <span className={cat === 'corriendo' ? 'text-emerald-700 font-semibold' : ''}>
                  <Clock className="inline h-3 w-3 mr-0.5" />
                  Efectivo: {fmtHms(tEfectivo)}
                </span>
              )}
              {cat === 'cerrada_hoy' && j.tiempo_efectivo_trabajo_segundos != null && (
                <span>
                  <Clock className="inline h-3 w-3 mr-0.5" />
                  Total efectivo: {fmtHms(j.tiempo_efectivo_trabajo_segundos)}
                </span>
              )}
            </div>
            <div className="text-[10px] text-gray-400 flex flex-wrap gap-x-3 gap-y-0.5 mt-1">
              <span>📷 {j.evid_antes + j.evid_durante + j.evid_despues + j.evid_llegada} evidencias</span>
              {j.ultimo_evento_tipo && j.evento_at && (
                <span>Último evento: <strong>{j.ultimo_evento_tipo}</strong> ({new Date(j.evento_at).toLocaleTimeString('es-CL', { hour: '2-digit', minute: '2-digit' })})</span>
              )}
              {j.ultima_evidencia_lat != null && j.ultima_evidencia_lng != null && (
                <span><MapPin className="inline h-3 w-3" /> GPS último</span>
              )}
            </div>
          </div>
          <Button variant="secondary" onClick={onRevisar}>
            <Eye className="h-4 w-4" />
          </Button>
        </div>
      </CardContent>
    </Card>
  )
}

// ─── TAB HOY ────────────────────────────────────────────────────────────────

function HoyTabContent({
  resumen, jornadas, rangoLabel, rango, nowSeg, onRevisar,
}: {
  resumen: import('@/lib/services/calama-supervision').ResumenHoy
  jornadas: JornadaEnVivo[]
  rangoLabel: string
  rango: { desde: string; hasta: string; label: string }
  nowSeg: number
  onRevisar: (j: JornadaEnVivo) => void
}) {
  const esMultiDia = rango.desde !== rango.hasta
  const kpis = [
    { label: 'En ejecución',  value: resumen.corriendo,              tone: 'emerald', icon: Play },
    { label: 'En pausa',      value: resumen.pausadas,               tone: 'amber',   icon: Pause },
    { label: 'En faena',      value: resumen.en_faena_sin_iniciar,   tone: 'sky',     icon: AlertCircle },
    { label: 'Por iniciar',   value: resumen.pendientes_inicio,      tone: 'slate',   icon: CircleDashed },
    { label: 'Cerradas',      value: resumen.cerradas_hoy,           tone: 'purple',  icon: CheckCircle2 },
    { label: 'Esperan OK',    value: resumen.pendientes_supervision, tone: 'orange',  icon: ClipboardCheck },
    { label: 'Aceptadas',     value: resumen.aceptadas_hoy,          tone: 'green',   icon: CheckCircle2 },
    { label: 'Para corregir', value: resumen.requieren_correccion,   tone: 'red',     icon: AlertTriangle },
  ]

  const totalEfectivoSeg = (resumen.total_seg_efectivo_cerradas ?? 0) + (resumen.total_seg_efectivo_en_vivo ?? 0)

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
        {kpis.map((k) => {
          const Icon = k.icon
          return (
            <Card key={k.label}>
              <CardContent className="p-3">
                <div className="flex items-center gap-2 text-xs text-gray-500">
                  <Icon className="h-3 w-3" /> {k.label}
                </div>
                <div className="text-2xl font-bold text-gray-900 mt-1">{k.value}</div>
              </CardContent>
            </Card>
          )
        })}
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
        <Card>
          <CardContent className="p-3">
            <div className="text-xs text-gray-500 flex items-center gap-1">
              <Clock className="h-3 w-3" /> Tiempo efectivo total del día
            </div>
            <div className="text-xl font-bold text-gray-900 mt-1">
              {fmtHms(totalEfectivoSeg)}
            </div>
            <div className="text-[10px] text-gray-500 mt-1">
              {fmtHms(resumen.total_seg_efectivo_cerradas)} cerradas +{' '}
              {fmtHms(resumen.total_seg_efectivo_en_vivo)} en vivo
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-3">
            <div className="text-xs text-gray-500 flex items-center gap-1">
              <AlertTriangle className="h-3 w-3" /> Tiempo en interferencia mandante
            </div>
            <div className="text-xl font-bold text-amber-700 mt-1">
              {fmtHms(resumen.total_seg_interferencia)}
            </div>
            <div className="text-[10px] text-gray-500 mt-1">
              Tiempo perdido por causas atribuibles al mandante
            </div>
          </CardContent>
        </Card>
      </div>

      <section>
        <h2 className="text-xs uppercase tracking-wide text-gray-500 mb-2">
          Detalle — {rangoLabel} ({jornadas.length} jornada{jornadas.length === 1 ? '' : 's'})
        </h2>
        {esMultiDia ? (
          <CalendarioPorDia jornadas={jornadas} rango={rango} nowSeg={nowSeg} onRevisar={onRevisar} />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-xs">
              <thead className="text-left text-gray-500">
                <tr className="border-b">
                  <th className="py-1.5 px-2">Estado</th>
                  <th className="py-1.5 px-2">Folio</th>
                  <th className="py-1.5 px-2">Operador</th>
                  <th className="py-1.5 px-2 text-right">Avance</th>
                  <th className="py-1.5 px-2 text-right">Efectivo</th>
                  <th className="py-1.5 px-2 text-right">Interf.</th>
                  <th className="py-1.5 px-2">Llegada</th>
                  <th className="py-1.5 px-2">Cierre</th>
                </tr>
              </thead>
              <tbody>
                {jornadas.map((j) => (
                  <tr key={j.plan_semanal_ot_id} className="border-b hover:bg-gray-50 cursor-pointer" onClick={() => onRevisar(j)}>
                    <td className="py-1 px-2">
                      <span className={`rounded-full px-1.5 py-0.5 text-[9px] font-semibold border ${CAT_COLOR[j.categoria_vivo]}`}>
                        {CAT_LABEL[j.categoria_vivo]}
                      </span>
                    </td>
                    <td className="py-1 px-2 font-mono text-[10px]">{j.folio.slice(-16)}</td>
                    <td className="py-1 px-2 truncate max-w-[140px]">{j.ejecutor_nombre || j.responsable_nombre || '—'}</td>
                    <td className="py-1 px-2 text-right">{Number(j.avance_pct ?? 0).toFixed(0)}%</td>
                    <td className="py-1 px-2 text-right">
                      {fmtHms(j.tiempo_efectivo_trabajo_segundos ?? j.tiempo_efectivo_segundos)}
                    </td>
                    <td className="py-1 px-2 text-right text-amber-700">
                      {fmtHms(j.tiempo_interferencia_mandante_segundos)}
                    </td>
                    <td className="py-1 px-2 text-[10px]">
                      {j.llegada_faena_at ? new Date(j.llegada_faena_at).toLocaleTimeString('es-CL', { hour: '2-digit', minute: '2-digit' }) : '—'}
                    </td>
                    <td className="py-1 px-2 text-[10px]">
                      {j.cierre_jornada_at ? new Date(j.cierre_jornada_at).toLocaleTimeString('es-CL', { hour: '2-digit', minute: '2-digit' }) : '—'}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </div>
  )
}

// ─── CALENDARIO POR DIA ─────────────────────────────────────────────────────

function CalendarioPorDia({
  jornadas, rango, nowSeg, onRevisar,
}: {
  jornadas: JornadaEnVivo[]
  rango: { desde: string; hasta: string }
  nowSeg: number
  onRevisar: (j: JornadaEnVivo) => void
}) {
  // Generar lista de dias entre desde y hasta (inclusive)
  const dias = useMemo(() => {
    const out: string[] = []
    const [yd, md, dd] = rango.desde.split('-').map(Number)
    const [yh, mh, dh] = rango.hasta.split('-').map(Number)
    const d1 = new Date(yd, md - 1, dd)
    const d2 = new Date(yh, mh - 1, dh)
    const cur = new Date(d1)
    while (cur <= d2) {
      out.push(isoDate(cur))
      cur.setDate(cur.getDate() + 1)
    }
    return out
  }, [rango.desde, rango.hasta])

  // Agrupar jornadas por fecha_efectiva
  const porDia = useMemo(() => {
    const map = new Map<string, JornadaEnVivo[]>()
    for (const j of jornadas) {
      if (!j.fecha_jornada && !j.llegada_faena_at && !j.cierre_jornada_at) continue
      // Usar la mejor fecha disponible (alineado con vista BD)
      const fe = j.fecha_jornada
        ?? (j.llegada_faena_at?.slice(0, 10))
        ?? (j.cierre_jornada_at?.slice(0, 10))
        ?? null
      if (!fe) continue
      const arr = map.get(fe) ?? []
      arr.push(j)
      map.set(fe, arr)
    }
    return map
  }, [jornadas])

  const hoy = isoDate(new Date())

  return (
    <div className="space-y-2">
      {dias.map((dia) => (
        <DiaSection
          key={dia}
          dia={dia}
          jornadas={porDia.get(dia) ?? []}
          esHoy={dia === hoy}
          nowSeg={nowSeg}
          onRevisar={onRevisar}
        />
      ))}
    </div>
  )
}

const DIAS_SEMANA = ['DOM', 'LUN', 'MAR', 'MIE', 'JUE', 'VIE', 'SAB']
const MESES_CORTOS = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic']

function DiaSection({
  dia, jornadas, esHoy, nowSeg, onRevisar,
}: {
  dia: string
  jornadas: JornadaEnVivo[]
  esHoy: boolean
  nowSeg: number
  onRevisar: (j: JornadaEnVivo) => void
}) {
  const [open, setOpen] = useState(esHoy || jornadas.length > 0)

  const [y, m, d] = dia.split('-').map(Number)
  const fechaObj = new Date(y, m - 1, d)
  const nombreDia = DIAS_SEMANA[fechaObj.getDay()]
  const mesNombre = MESES_CORTOS[m - 1]

  const conteos = useMemo(() => {
    const c: Record<CategoriaVivo, number> = {
      corriendo: 0, pausada: 0, en_faena_sin_iniciar: 0,
      pendiente_inicio: 0, cerrada_hoy: 0,
    }
    for (const j of jornadas) c[j.categoria_vivo]++
    return c
  }, [jornadas])

  const vacio = jornadas.length === 0

  return (
    <Card className={esHoy ? 'border-emerald-300 bg-emerald-50/30' : ''}>
      <button
        onClick={() => setOpen(!open)}
        className="w-full p-3 flex items-center gap-3 text-left hover:bg-gray-50 transition"
      >
        {open ? <ChevronDown className="h-4 w-4 text-gray-400" /> : <ChevronRight className="h-4 w-4 text-gray-400" />}
        <div className="flex items-baseline gap-2">
          <span className={`text-xs font-bold ${esHoy ? 'text-emerald-700' : 'text-gray-700'}`}>
            {nombreDia}
          </span>
          <span className={`text-sm font-semibold ${esHoy ? 'text-emerald-700' : 'text-gray-900'}`}>
            {d} {mesNombre}
          </span>
          {esHoy && <span className="rounded-full bg-emerald-600 text-white px-2 py-0.5 text-[9px] font-semibold">HOY</span>}
        </div>
        <span className="text-xs text-gray-500">
          {vacio ? 'sin jornadas' : `${jornadas.length} jornada${jornadas.length === 1 ? '' : 's'}`}
        </span>
        {!vacio && (
          <div className="ml-auto flex items-center gap-1 text-[10px]">
            {conteos.corriendo > 0 && (
              <span className="rounded-full bg-emerald-100 text-emerald-700 px-1.5 py-0.5 font-semibold flex items-center gap-0.5">
                <Play className="h-2.5 w-2.5" /> {conteos.corriendo}
              </span>
            )}
            {conteos.pausada > 0 && (
              <span className="rounded-full bg-amber-100 text-amber-700 px-1.5 py-0.5 font-semibold flex items-center gap-0.5">
                <Pause className="h-2.5 w-2.5" /> {conteos.pausada}
              </span>
            )}
            {conteos.en_faena_sin_iniciar > 0 && (
              <span className="rounded-full bg-sky-100 text-sky-700 px-1.5 py-0.5 font-semibold flex items-center gap-0.5">
                <AlertCircle className="h-2.5 w-2.5" /> {conteos.en_faena_sin_iniciar}
              </span>
            )}
            {conteos.pendiente_inicio > 0 && (
              <span className="rounded-full bg-slate-100 text-slate-600 px-1.5 py-0.5 font-semibold flex items-center gap-0.5">
                <CircleDashed className="h-2.5 w-2.5" /> {conteos.pendiente_inicio}
              </span>
            )}
            {conteos.cerrada_hoy > 0 && (
              <span className="rounded-full bg-purple-100 text-purple-700 px-1.5 py-0.5 font-semibold flex items-center gap-0.5">
                <CheckCircle2 className="h-2.5 w-2.5" /> {conteos.cerrada_hoy}
              </span>
            )}
          </div>
        )}
      </button>
      {open && !vacio && (
        <CardContent className="pt-0 pb-3 px-3 space-y-1.5">
          {jornadas.map((j) => (
            <EnVivoCard key={j.plan_semanal_ot_id} j={j} nowSeg={nowSeg} onRevisar={() => onRevisar(j)} />
          ))}
        </CardContent>
      )}
    </Card>
  )
}

