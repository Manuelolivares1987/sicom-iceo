'use client'

import { useEffect, useMemo, useState } from 'react'
import Link from 'next/link'
import {
  ArrowLeft, Wrench, AlertTriangle, CalendarClock, RefreshCw, Check, ClipboardList, ClipboardCheck,
} from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { useRequireAuth } from '@/hooks/use-require-auth'
import {
  getEquiposEnTaller, getOtsAbiertasActivo, getTecnicos, getPlanesActivo, programarOtTaller,
  getTareasRecepcion, programarOtRecepcion,
  type EquipoEnTaller, type OtAbierta, type Tecnico, type PlanActivo,
  type TipoOtTaller, type PrioridadTaller, type TareaRecepcion,
} from '@/lib/services/taller-planificacion'
import { todayISO } from '@/lib/utils'

const ESTADO = {
  M: ['Mantención', '#F59E0B'], T: ['Taller', '#FB923C'], F: ['Fuera de servicio', '#DC2626'],
} as Record<string, [string, string]>

export default function PlanificacionTallerPage() {
  useRequireAuth()
  const [equipos, setEquipos] = useState<EquipoEnTaller[]>([])
  const [tecnicos, setTecnicos] = useState<Tecnico[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [sel, setSel] = useState<string | null>(null)

  const cargar = async () => {
    setError(null)
    try {
      const [e, t] = await Promise.all([getEquiposEnTaller(), getTecnicos()])
      setEquipos(e); setTecnicos(t)
    } catch (err) { setError((err as Error).message) }
    finally { setLoading(false) }
  }
  useEffect(() => { cargar() }, [])

  const equipoSel = useMemo(() => equipos.find((e) => e.activo_id === sel) ?? null, [equipos, sel])

  return (
    <div className="space-y-4 p-4 sm:p-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-3">
          <Link href="/dashboard/mantenimiento">
            <Button variant="ghost" size="sm" className="gap-1"><ArrowLeft className="h-4 w-4" /> Mantenimiento</Button>
          </Link>
          <div>
            <h1 className="flex items-center gap-2 text-2xl font-bold">
              <Wrench className="h-6 w-6 text-amber-600" /> Planificación de Taller
            </h1>
            <p className="text-sm text-muted-foreground">
              Equipos en mantención / fuera de servicio — selecciona una patente y programa su trabajo
            </p>
          </div>
        </div>
        <Button onClick={cargar} variant="outline" size="sm" className="gap-1" disabled={loading}>
          <RefreshCw className={`h-4 w-4 ${loading ? 'animate-spin' : ''}`} /> Refrescar
        </Button>
      </div>

      {error && (
        <Card className="border-red-200 bg-red-50"><CardContent className="flex items-center gap-2 p-3 text-sm text-red-700">
          <AlertTriangle className="h-4 w-4" /> {error}
        </CardContent></Card>
      )}

      {loading ? (
        <div className="flex h-64 items-center justify-center"><Spinner /></div>
      ) : (
        <div className="grid gap-4 lg:grid-cols-[320px_1fr]">
          {/* ── Izquierda: patentes en taller ── */}
          <Card>
            <CardContent className="p-3">
              <div className="mb-2 text-xs font-semibold uppercase text-gray-500">
                En taller ({equipos.length})
              </div>
              {equipos.length === 0 ? (
                <p className="py-8 text-center text-sm text-gray-400">No hay equipos en mantención ni fuera de servicio.</p>
              ) : (
                <div className="space-y-1.5">
                  {equipos.map((e) => {
                    const est = ESTADO[e.estado_codigo] ?? ['—', '#6b7280']
                    const activo = sel === e.activo_id
                    return (
                      <button
                        key={e.activo_id}
                        onClick={() => setSel(e.activo_id)}
                        className={`w-full rounded-lg border p-2.5 text-left transition-colors ${activo ? 'border-amber-400 bg-amber-50' : 'border-gray-200 hover:bg-gray-50'}`}
                      >
                        <div className="flex items-center justify-between">
                          <span className="font-mono font-bold text-gray-800">{e.patente}</span>
                          <span className="rounded px-1.5 py-0.5 text-[10px] font-semibold text-white" style={{ background: est[1] }}>{est[0]}</span>
                        </div>
                        <div className="mt-0.5 truncate text-xs text-gray-500">{e.equipamiento ?? '—'}</div>
                        <div className="mt-0.5 text-[11px] text-gray-400">
                          {e.dias_mantencion != null ? `${e.dias_mantencion} d en estado` : ''}
                          {e.ultimo_contrato ? ` · ${e.ultimo_contrato.split(' · ')[1] ?? e.ultimo_contrato}` : ''}
                        </div>
                      </button>
                    )
                  })}
                </div>
              )}
            </CardContent>
          </Card>

          {/* ── Derecha: programar ── */}
          {equipoSel ? (
            <PanelProgramar key={equipoSel.activo_id} equipo={equipoSel} tecnicos={tecnicos} onProgramada={cargar} />
          ) : (
            <Card><CardContent className="flex h-full items-center justify-center p-10 text-center text-sm text-gray-400">
              Selecciona una patente de la izquierda para programar su trabajo.
            </CardContent></Card>
          )}
        </div>
      )}
    </div>
  )
}

function PanelProgramar({ equipo, tecnicos, onProgramada }: {
  equipo: EquipoEnTaller; tecnicos: Tecnico[]; onProgramada: () => void
}) {
  const [ots, setOts] = useState<OtAbierta[]>([])
  const [planes, setPlanes] = useState<PlanActivo[]>([])
  const [tareasRec, setTareasRec] = useState<TareaRecepcion[]>([])
  const [cargandoDet, setCargandoDet] = useState(true)
  const [progRec, setProgRec] = useState(false)
  const [msgRec, setMsgRec] = useState<string | null>(null)

  const [tipo, setTipo] = useState<TipoOtTaller>('correctivo')
  const [prioridad, setPrioridad] = useState<PrioridadTaller>('normal')
  const [fecha, setFecha] = useState(todayISO())
  const [responsableId, setResponsableId] = useState('')
  const [planId, setPlanId] = useState('')
  const [enviando, setEnviando] = useState(false)
  const [msg, setMsg] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  const cargarDet = async () => {
    setCargandoDet(true)
    try {
      const [o, p, tr] = await Promise.all([
        getOtsAbiertasActivo(equipo.activo_id),
        getPlanesActivo(equipo.activo_id),
        getTareasRecepcion(equipo.activo_id),
      ])
      setOts(o); setPlanes(p); setTareasRec(tr)
    } finally { setCargandoDet(false) }
  }
  useEffect(() => { cargarDet() }, [equipo.activo_id])

  const programarRecepcion = async () => {
    setProgRec(true); setMsgRec(null)
    try {
      const r = await programarOtRecepcion({ activoId: equipo.activo_id, prioridad: 'alta', fecha: todayISO(), responsableId: null })
      setMsgRec(`OT ${r.folio} creada con ${r.tareas_cargadas} tareas del checklist de recepción.`)
      await cargarDet(); onProgramada()
    } catch (e) { setMsgRec((e as Error).message) }
    finally { setProgRec(false) }
  }

  // Si elige una pauta preventiva, fijar tipo preventivo
  useEffect(() => { if (planId) setTipo('preventivo') }, [planId])

  const planSel = planes.find((p) => p.id === planId) ?? null

  const programar = async () => {
    setEnviando(true); setMsg(null); setError(null)
    try {
      const r = await programarOtTaller({
        activoId: equipo.activo_id, tipo, prioridad,
        fecha: fecha || null, responsableId: responsableId || null, planId: planId || null,
      })
      setMsg(`OT ${r.folio} programada (${r.estado}).`)
      await cargarDet()
      onProgramada()
    } catch (e) { setError((e as Error).message) }
    finally { setEnviando(false) }
  }

  return (
    <Card>
      <CardContent className="space-y-4 p-4">
        {/* Header equipo */}
        <div className="flex flex-wrap items-center justify-between gap-2 border-b pb-3">
          <div>
            <div className="text-lg font-bold">{equipo.patente} <span className="text-sm font-normal text-gray-500">· {equipo.equipamiento ?? '—'}</span></div>
            <div className="text-xs text-gray-500">{equipo.ultimo_contrato ?? 'Sin contrato'} · motivo: {equipo.motivo ?? '—'}</div>
          </div>
        </div>

        {/* Tareas desde checklist de recepción */}
        <div className="rounded-lg border border-blue-200 bg-blue-50/40 p-3">
          <div className="mb-1 flex items-center justify-between">
            <div className="flex items-center gap-1 text-xs font-semibold uppercase text-blue-700">
              <ClipboardCheck className="h-3.5 w-3.5" /> Tareas del checklist de recepción ({tareasRec.length})
            </div>
            {tareasRec.length > 0 && (
              <Button size="sm" className="gap-1 bg-blue-600 hover:bg-blue-700" disabled={progRec} onClick={programarRecepcion}>
                <CalendarClock className="h-4 w-4" /> {progRec ? 'Creando…' : `Programar OT con estas ${tareasRec.length} tareas`}
              </Button>
            )}
          </div>
          {cargandoDet ? <Spinner className="h-4 w-4" /> : tareasRec.length === 0 ? (
            <p className="text-xs text-gray-500">Sin checklist de recepción con fallas. (Las tareas salen de los ítems <b>no_ok</b> de la recepción del equipo.)</p>
          ) : (
            <ul className="space-y-1">
              {tareasRec.map((t) => (
                <li key={t.item_id} className="flex items-start gap-2 rounded bg-white px-2 py-1 text-xs">
                  <span className="mt-0.5 inline-block h-1.5 w-1.5 shrink-0 rounded-full bg-red-500" />
                  <span className="flex-1">
                    <b>{t.descripcion}</b>
                    {t.observacion && <span className="text-gray-500"> — {t.observacion}</span>}
                    <span className="ml-1 text-[10px] text-gray-400">[{t.bloque}]</span>
                  </span>
                </li>
              ))}
            </ul>
          )}
          {msgRec && <div className="mt-2 rounded bg-green-50 px-2 py-1 text-xs text-green-700">{msgRec}</div>}
        </div>

        {/* OTs abiertas */}
        <div>
          <div className="mb-1 flex items-center gap-1 text-xs font-semibold uppercase text-gray-500">
            <ClipboardList className="h-3.5 w-3.5" /> OTs abiertas ({ots.length})
          </div>
          {cargandoDet ? <Spinner className="h-4 w-4" /> : ots.length === 0 ? (
            <p className="text-xs text-gray-400">No tiene OTs abiertas.</p>
          ) : (
            <div className="space-y-1">
              {ots.map((o) => (
                <div key={o.id} className="flex items-center justify-between rounded border border-gray-200 px-2 py-1 text-xs">
                  <span className="font-mono font-semibold">{o.folio}</span>
                  <span className="text-gray-500">{o.tipo} · {o.estado} · {o.prioridad}</span>
                  <span className="text-gray-400">{o.fecha_programada ?? 'sin fecha'}</span>
                </div>
              ))}
            </div>
          )}
        </div>

        {/* Programar */}
        <div className="rounded-lg border border-gray-200 p-3">
          <div className="mb-2 flex items-center gap-1 text-sm font-semibold text-gray-700">
            <CalendarClock className="h-4 w-4" /> Programar trabajo
          </div>
          <div className="grid gap-3 sm:grid-cols-2">
            <label className="text-xs">
              <span className="mb-0.5 block text-gray-500">Pauta preventiva (opcional)</span>
              <select className="h-9 w-full rounded border border-gray-300 px-2 text-sm" value={planId} onChange={(e) => setPlanId(e.target.value)}>
                <option value="">— Tarea correctiva / libre —</option>
                {planes.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.pauta_nombre ?? p.nombre}{p.duracion_estimada_hrs != null ? ` (${p.duracion_estimada_hrs} h)` : ''}
                  </option>
                ))}
              </select>
            </label>
            <label className="text-xs">
              <span className="mb-0.5 block text-gray-500">Tipo</span>
              <select className="h-9 w-full rounded border border-gray-300 px-2 text-sm" value={tipo} disabled={!!planId} onChange={(e) => setTipo(e.target.value as TipoOtTaller)}>
                <option value="correctivo">Correctivo</option>
                <option value="preventivo">Preventivo</option>
                <option value="inspeccion">Inspección</option>
              </select>
            </label>
            <label className="text-xs">
              <span className="mb-0.5 block text-gray-500">Prioridad</span>
              <select className="h-9 w-full rounded border border-gray-300 px-2 text-sm" value={prioridad} onChange={(e) => setPrioridad(e.target.value as PrioridadTaller)}>
                <option value="emergencia">Emergencia</option>
                <option value="alta">Alta</option>
                <option value="normal">Normal</option>
                <option value="baja">Baja</option>
              </select>
            </label>
            <label className="text-xs">
              <span className="mb-0.5 block text-gray-500">Fecha programada</span>
              <input type="date" className="h-9 w-full rounded border border-gray-300 px-2 text-sm" value={fecha} onChange={(e) => setFecha(e.target.value)} />
            </label>
            <label className="text-xs sm:col-span-2">
              <span className="mb-0.5 block text-gray-500">Técnico responsable (opcional)</span>
              <select className="h-9 w-full rounded border border-gray-300 px-2 text-sm" value={responsableId} onChange={(e) => setResponsableId(e.target.value)}>
                <option value="">— Sin asignar —</option>
                {tecnicos.map((t) => (<option key={t.id} value={t.id}>{t.nombre_completo}{t.cargo ? ` · ${t.cargo}` : ''}</option>))}
              </select>
            </label>
          </div>

          {planSel?.duracion_estimada_hrs != null && (
            <p className="mt-2 text-[11px] text-gray-400">Duración estimada de la pauta: <b>{planSel.duracion_estimada_hrs} h</b></p>
          )}

          {msg && <div className="mt-2 flex items-center gap-1 rounded bg-green-50 px-2 py-1.5 text-sm text-green-700"><Check className="h-4 w-4" /> {msg}</div>}
          {error && <div className="mt-2 flex items-center gap-1 rounded bg-red-50 px-2 py-1.5 text-sm text-red-700"><AlertTriangle className="h-4 w-4" /> {error}</div>}

          <div className="mt-3 flex justify-end">
            <Button onClick={programar} disabled={enviando} className="gap-1 bg-amber-600 hover:bg-amber-700">
              <CalendarClock className="h-4 w-4" /> {enviando ? 'Programando…' : 'Programar OT'}
            </Button>
          </div>
        </div>
      </CardContent>
    </Card>
  )
}
