'use client'

import { useEffect, useMemo, useState } from 'react'
import {
  DndContext, DragEndEvent, DragOverlay, DragStartEvent,
  PointerSensor, useDraggable, useDroppable, useSensor, useSensors,
} from '@dnd-kit/core'
import {
  Calendar, Save, ArrowLeft, ChevronLeft, ChevronRight, Lock, AlertTriangle,
  Trash2, User, Clock, MapPin, MessageSquare, BarChart3, Layers, X,
  CheckCircle2,
} from 'lucide-react'
import Link from 'next/link'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { Select } from '@/components/ui/select'
import { Modal, ModalFooter } from '@/components/ui/modal'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useCalamaPlanificaciones, useCalamaOTs, useCalamaZonas } from '@/hooks/use-calama'
import {
  useGetOrCreatePlanSemanal, usePlanSemanal, useDiasPlanSemanal, useOTsPlanSemanal,
  useMoverOTplanSemanal, useQuitarOTplanSemanal, useConfirmarPlanSemanal,
  useUsuariosAsignables, useAsignarResponsable,
  useActualizarComentarioPlanOT, useAvancePorArea, useResumenGeneral,
} from '@/hooks/use-calama-plan-semanal'
import { useActualizarAvanceManual } from '@/hooks/use-calama-avance'
import { lunesDe } from '@/lib/services/calama-plan-semanal'
import { zonaCodeFromFolio, excelCodigoFromFolio, type CalamaOTConRelaciones } from '@/lib/services/calama'
import { EstadoBadge } from '@/components/calama/gantt-table'

const BACKLOG_ID = 'backlog'
type Tab = 'planificacion' | 'general' | 'por_area'

export default function PlanSemanalPage() {
  useRequireAuth()

  const { data: planificaciones } = useCalamaPlanificaciones()
  const [planificacionId, setPlanificacionId] = useState<string>('')
  const [semanaIso, setSemanaIso] = useState<string>(() => lunesDe(new Date()))
  const [planSemanalId, setPlanSemanalId] = useState<string>('')
  const [errorMsg, setErrorMsg] = useState<string | null>(null)
  const [tab, setTab] = useState<Tab>('planificacion')
  const [lugarFisicoSel, setLugarFisicoSel] = useState<string>('') // codigo zona "1.0.0"

  const getOrCreate = useGetOrCreatePlanSemanal()
  const { data: planSem } = usePlanSemanal(planSemanalId || null)
  const { data: dias } = useDiasPlanSemanal(planSemanalId || null)
  const { data: planOts } = useOTsPlanSemanal(planSemanalId || null)
  const { data: ots } = useCalamaOTs(planificacionId ? { planificacionId } : undefined)
  const { data: zonas } = useCalamaZonas(planificacionId)
  const { data: usuarios } = useUsuariosAsignables()
  const { data: avancePorArea } = useAvancePorArea(planificacionId)
  const { data: resumenGeneral } = useResumenGeneral(planificacionId)

  const moverOT = useMoverOTplanSemanal()
  const quitarOT = useQuitarOTplanSemanal()
  const confirmarPlan = useConfirmarPlanSemanal()
  const asignarResp = useAsignarResponsable()
  const updateComentario = useActualizarComentarioPlanOT()

  // Modal comentario
  const [comentarioOpen, setComentarioOpen] = useState<string | null>(null) // ot_id
  const [comentarioTexto, setComentarioTexto] = useState('')

  // Modal actualizar avance
  const updateAvance = useActualizarAvanceManual()
  const [avanceOpen, setAvanceOpen] = useState<string | null>(null) // ot_id
  const [avanceValor, setAvanceValor] = useState<number>(0)
  const [avanceMotivo, setAvanceMotivo] = useState<string>('ajuste_manual')
  const [avanceComentario, setAvanceComentario] = useState<string>('')

  useEffect(() => {
    if (planificaciones && planificaciones.length > 0 && !planificacionId) {
      setPlanificacionId(planificaciones[0].id)
    }
  }, [planificaciones, planificacionId])

  useEffect(() => {
    if (!planificacionId || !semanaIso) return
    setErrorMsg(null)
    getOrCreate.mutate(
      { planificacionId, fechaInicio: semanaIso },
      {
        onSuccess: (d) => setPlanSemanalId(d.plan_semanal_id),
        onError: (e) => setErrorMsg(e instanceof Error ? e.message : 'Error al cargar plan semanal'),
      },
    )
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [planificacionId, semanaIso])

  const planOtsByOtId = useMemo(() => new Map((planOts ?? []).map((p) => [p.ot_id, p])), [planOts])
  const otsById = useMemo(() => new Map((ots ?? []).map((o) => [o.id, o])), [ots])

  // OTs filtradas por lugar físico (cuando hay selección)
  const otsLugar = useMemo(() => {
    if (!ots) return []
    if (!lugarFisicoSel) return ots
    return ots.filter((o) => zonaCodeFromFolio(o.folio) === lugarFisicoSel)
  }, [ots, lugarFisicoSel])

  // Backlog = OTs del lugar (o todas) que NO están en plan
  const backlog = useMemo(() => {
    return otsLugar.filter((o) => !planOtsByOtId.has(o.id) && o.estado !== 'finalizada' && o.estado !== 'cancelada')
  }, [otsLugar, planOtsByOtId])

  const otsByDia = useMemo(() => {
    const m = new Map<string, CalamaOTConRelaciones[]>()
    for (const dia of dias ?? []) m.set(dia.id, [])
    for (const p of planOts ?? []) {
      const ot = otsById.get(p.ot_id)
      if (!ot) continue
      // Si hay filtro por lugar físico, mostrar solo las de ese lugar
      if (lugarFisicoSel && zonaCodeFromFolio(ot.folio) !== lugarFisicoSel) continue
      const arr = m.get(p.plan_dia_id)
      if (arr) arr.push(ot)
    }
    return m
  }, [dias, planOts, otsById, lugarFisicoSel])

  const [activeOTId, setActiveOTId] = useState<string | null>(null)
  const sensors = useSensors(useSensor(PointerSensor, { activationConstraint: { distance: 5 } }))

  const handleDragStart = (e: DragStartEvent) => setActiveOTId(String(e.active.id))

  const handleDragEnd = (e: DragEndEvent) => {
    setActiveOTId(null)
    const otId = String(e.active.id)
    const overId = e.over?.id ? String(e.over.id) : null
    if (!overId || !planSemanalId) return

    if (overId === BACKLOG_ID) {
      if (!planOtsByOtId.has(otId)) return
      quitarOT.mutate({ planSemanalId, otId }, {
        onError: (err) => setErrorMsg(err instanceof Error ? err.message : 'Error al quitar OT'),
      })
      return
    }

    const dia = dias?.find((d) => d.id === overId)
    if (!dia) return
    moverOT.mutate({ planSemanalId, otId, fechaDestino: dia.fecha }, {
      onError: (err) => setErrorMsg(err instanceof Error ? err.message : 'Error al mover OT'),
    })
  }

  const handleConfirmar = () => {
    if (!planSemanalId) return
    if (!confirm('¿Confirmar plan semanal? Las OTs quedaran disponibles para los responsables.')) return
    confirmarPlan.mutate(planSemanalId, {
      onError: (e) => setErrorMsg(e instanceof Error ? e.message : 'Error al confirmar'),
    })
  }

  const semanaPrev = () => { const d = new Date(semanaIso); d.setDate(d.getDate() - 7); setSemanaIso(d.toISOString().slice(0, 10)) }
  const semanaSig  = () => { const d = new Date(semanaIso); d.setDate(d.getDate() + 7); setSemanaIso(d.toISOString().slice(0, 10)) }

  const planBloqueado = planSem?.estado === 'cerrado' || planSem?.estado === 'cancelado'
  const activeOT = activeOTId ? (otsById.get(activeOTId) ?? null) : null

  const lugarSelInfo = useMemo(() => {
    if (!lugarFisicoSel || !avancePorArea) return null
    return avancePorArea.find((a) => a.codigo_zona === lugarFisicoSel) ?? null
  }, [lugarFisicoSel, avancePorArea])

  const abrirComentario = (otId: string) => {
    const planOt = planOtsByOtId.get(otId)
    setComentarioTexto(planOt?.observaciones ?? '')
    setComentarioOpen(otId)
  }
  const guardarComentario = async () => {
    if (!comentarioOpen || !planSemanalId) return
    try {
      await updateComentario.mutateAsync({ planSemanalId, otId: comentarioOpen, observaciones: comentarioTexto })
      setComentarioOpen(null)
    } catch (e) {
      setErrorMsg(e instanceof Error ? e.message : 'Error al guardar comentario')
    }
  }

  const abrirAvance = (otId: string) => {
    const ot = otsById.get(otId)
    setAvanceValor(ot ? Number(ot.avance_pct ?? 0) : 0)
    setAvanceMotivo('ajuste_manual')
    setAvanceComentario('')
    setAvanceOpen(otId)
  }
  const guardarAvance = async () => {
    if (!avanceOpen) return
    if (avanceValor >= 100 && !avanceComentario.trim()) {
      setErrorMsg('Comentario obligatorio para marcar 100%')
      return
    }
    if (avanceValor >= 100) {
      if (!confirm('Esto marcara la OT como finalizada. ¿Confirmar?')) return
    }
    try {
      await updateAvance.mutateAsync({
        ot_id: avanceOpen,
        avance_nuevo: avanceValor,
        fuente: 'planificador',
        motivo: avanceMotivo,
        comentario: avanceComentario || undefined,
      })
      setAvanceOpen(null)
    } catch (e) {
      setErrorMsg(e instanceof Error ? e.message : 'Error al guardar avance')
    }
  }

  return (
    <div className="space-y-4">
      <Link href="/dashboard/operacion-calama" className="inline-flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700">
        <ArrowLeft className="h-4 w-4" /> Panel Calama
      </Link>

      <div className="rounded-2xl bg-gradient-to-r from-amber-700 to-orange-600 p-6 text-white shadow-lg">
        <h1 className="text-2xl font-bold flex items-center gap-2">
          <Calendar className="h-6 w-6" /> Plan Semanal Calama
        </h1>
        <p className="text-sm text-white/90 mt-1">
          Selecciona un lugar físico y arrastra sus tareas a los dias de la semana.
        </p>
      </div>

      {/* Controles globales */}
      <Card>
        <CardContent className="p-4 grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3 items-end">
          <Select
            label="Planificacion"
            value={planificacionId}
            onChange={(e) => setPlanificacionId(e.target.value)}
            options={(planificaciones ?? []).map((p) => ({ value: p.id, label: p.codigo }))}
          />
          <div>
            <label className="mb-1.5 block text-sm font-medium text-gray-700">Semana</label>
            <div className="flex items-center gap-1">
              <button onClick={semanaPrev} className="rounded border border-gray-300 p-2 hover:bg-gray-50">
                <ChevronLeft className="h-4 w-4" />
              </button>
              <input type="date" value={semanaIso} onChange={(e) => setSemanaIso(lunesDe(e.target.value))}
                className="min-h-[44px] flex-1 rounded-lg border border-gray-300 px-3 py-2 text-sm" />
              <button onClick={semanaSig} className="rounded border border-gray-300 p-2 hover:bg-gray-50">
                <ChevronRight className="h-4 w-4" />
              </button>
            </div>
            <p className="mt-1 text-xs text-gray-500">Lunes ({semanaIso})</p>
          </div>
          <div>
            <div className="text-xs uppercase text-gray-500">Estado plan</div>
            <div className="mt-1 inline-flex items-center gap-2">
              {planSem ? (
                <span className={`rounded-full px-3 py-0.5 text-xs font-semibold ${
                  planSem.estado === 'borrador' ? 'bg-slate-100 text-slate-700'
                  : planSem.estado === 'confirmado' ? 'bg-blue-100 text-blue-700'
                  : planSem.estado === 'en_ejecucion' ? 'bg-amber-100 text-amber-700'
                  : 'bg-gray-100 text-gray-500'
                }`}>{planSem.estado}</span>
              ) : <span className="text-gray-400 text-sm">Cargando…</span>}
              {planBloqueado && <Lock className="h-4 w-4 text-gray-400" />}
            </div>
          </div>
          <div className="flex gap-2 justify-end">
            {planSemanalId && planSem?.estado === 'borrador' && (
              <Button variant="primary" onClick={handleConfirmar} loading={confirmarPlan.isPending}
                disabled={(planOts?.length ?? 0) === 0}>
                <Save className="h-4 w-4" /> Confirmar
              </Button>
            )}
            {moverOT.isPending && <Spinner className="h-4 w-4" />}
          </div>
        </CardContent>
      </Card>

      {errorMsg && (
        <div className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700 flex items-start gap-2">
          <AlertTriangle className="h-4 w-4 mt-0.5 shrink-0" />
          <span>{errorMsg}</span>
          <button className="ml-auto text-red-700" onClick={() => setErrorMsg(null)}><X className="h-4 w-4" /></button>
        </div>
      )}

      {/* Tabs */}
      <div className="flex gap-1 border-b border-gray-200">
        {([
          ['planificacion', 'Planificacion semanal', <Calendar className="h-4 w-4" key="i1" />],
          ['general',       'Vista general',          <BarChart3 className="h-4 w-4" key="i2" />],
          ['por_area',      'Vista por area',         <Layers className="h-4 w-4" key="i3" />],
        ] as Array<[Tab, string, React.ReactNode]>).map(([k, label, icon]) => (
          <button
            key={k} onClick={() => setTab(k)}
            className={`flex items-center gap-2 px-3 py-2 text-sm font-medium border-b-2 -mb-px transition-colors ${
              tab === k ? 'border-amber-600 text-amber-700' : 'border-transparent text-gray-500 hover:text-gray-700'
            }`}
          >
            {icon}
            {label}
          </button>
        ))}
      </div>

      {tab === 'planificacion' && (
        <>
          {/* Selector de lugar físico */}
          <Card>
            <CardContent className="p-3 flex flex-wrap gap-3 items-end">
              <div className="flex-1 min-w-[260px]">
                <Select
                  label="Lugar físico (área / frente de trabajo)"
                  value={lugarFisicoSel}
                  onChange={(e) => setLugarFisicoSel(e.target.value)}
                  options={[
                    { value: '', label: 'Todos los lugares' },
                    ...((zonas ?? []).map((z) => ({
                      value: z.codigo_zona,
                      label: `${z.codigo_zona}  ${z.nombre}`,
                    }))),
                  ]}
                />
              </div>
              {lugarSelInfo && (
                <div className="flex flex-wrap gap-3 text-xs">
                  <Stat label="Tareas" value={lugarSelInfo.total_tareas} />
                  <Stat label="Finalizadas" value={lugarSelInfo.tareas_finalizadas} tone="green" />
                  <Stat label="Pendientes" value={lugarSelInfo.tareas_pendientes} tone="amber" />
                  <Stat label="Plan. semana" value={lugarSelInfo.tareas_planificadas_semana} />
                  <Stat label="Sin resp." value={lugarSelInfo.tareas_sin_responsable} tone={lugarSelInfo.tareas_sin_responsable > 0 ? 'red' : undefined} />
                  <Stat label="Avance" value={`${lugarSelInfo.avance_promedio_pct.toFixed(1)}%`} />
                </div>
              )}
            </CardContent>
          </Card>

          <DndContext sensors={sensors} onDragStart={handleDragStart} onDragEnd={handleDragEnd}>
            <div className="grid grid-cols-1 lg:grid-cols-[320px,1fr] gap-4">
              {/* Backlog */}
              <DroppableContainer id={BACKLOG_ID} className="bg-white rounded-xl border border-gray-200 p-3">
                <h3 className="text-sm font-bold uppercase text-gray-700 mb-2 flex items-center gap-2">
                  Backlog ({backlog.length})
                </h3>
                <p className="text-xs text-gray-400 mb-3">
                  {lugarFisicoSel
                    ? `Tareas de ${lugarFisicoSel} sin asignar.`
                    : 'Todas las tareas sin asignar (selecciona un lugar para filtrar).'}
                </p>
                <div className="space-y-2 max-h-[60vh] overflow-y-auto pr-1">
                  {backlog.length === 0 ? (
                    <p className="text-xs text-gray-400 italic text-center py-4">
                      {lugarFisicoSel ? 'No hay tareas pendientes en este lugar.' : 'No hay tareas en backlog.'}
                    </p>
                  ) : backlog.map((ot) => (
                    <DraggableOTCard key={ot.id} ot={ot} disabled={planBloqueado} />
                  ))}
                </div>
              </DroppableContainer>

              {/* Días semana */}
              <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-7 gap-2">
                {(dias ?? []).map((dia) => {
                  const otsDia = otsByDia.get(dia.id) ?? []
                  return (
                    <DroppableContainer
                      key={dia.id} id={dia.id}
                      className="bg-gray-50 rounded-xl border border-gray-200 p-2 min-h-[200px]"
                    >
                      <div className="mb-2 px-1">
                        <div className="text-xs font-bold uppercase text-gray-700">{dia.nombre_dia}</div>
                        <div className="text-[10px] text-gray-500">{dia.fecha}</div>
                        <div className="text-[10px] text-amber-700 font-mono">{otsDia.length} OTs</div>
                      </div>
                      <div className="space-y-1.5 max-h-[55vh] overflow-y-auto pr-1">
                        {otsDia.map((ot) => {
                          const planOt = planOtsByOtId.get(ot.id)
                          return (
                            <DraggableOTCard
                              key={ot.id} ot={ot} compact
                              responsableId={planOt?.responsable_id ?? null}
                              comentario={planOt?.observaciones ?? null}
                              usuarios={usuarios ?? []}
                              disabled={planBloqueado || planOt?.estado_plan === 'en_ejecucion' || planOt?.estado_plan === 'finalizada'}
                              onAsignar={(uid) => {
                                asignarResp.mutate({ planSemanalId, otId: ot.id, responsableId: uid }, {
                                  onError: (e) => setErrorMsg(e instanceof Error ? e.message : 'Error'),
                                })
                              }}
                              onQuitar={() => {
                                quitarOT.mutate({ planSemanalId, otId: ot.id }, {
                                  onError: (e) => setErrorMsg(e instanceof Error ? e.message : 'Error'),
                                })
                              }}
                              onComentar={() => abrirComentario(ot.id)}
                              onActualizarAvance={() => abrirAvance(ot.id)}
                            />
                          )
                        })}
                      </div>
                    </DroppableContainer>
                  )
                })}
              </div>
            </div>

            <DragOverlay>
              {activeOT ? <OTCardContent ot={activeOT} compact /> : null}
            </DragOverlay>
          </DndContext>
        </>
      )}

      {tab === 'general' && (
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-base flex items-center gap-2">
              <BarChart3 className="h-4 w-4" /> Vista general — {resumenGeneral?.planificacion_codigo ?? '—'}
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            {!resumenGeneral ? (
              <p className="text-sm text-gray-400">Cargando…</p>
            ) : (
              <>
                <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
                  <KPI title="Lugares físicos"  value={resumenGeneral.total_lugares_fisicos} icon={<Layers className="h-4 w-4" />} />
                  <KPI title="Total tareas"      value={resumenGeneral.total_tareas} />
                  <KPI title="Avance promedio"   value={`${resumenGeneral.avance_promedio_pct.toFixed(1)}%`} tone="indigo" />
                  <KPI title="Plan. esta semana" value={resumenGeneral.tareas_planificadas_semanas} />
                </div>
                <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
                  <KPI title="Finalizadas"       value={resumenGeneral.tareas_finalizadas} tone="green" />
                  <KPI title="En ejecución"      value={resumenGeneral.tareas_en_ejecucion} tone="amber" />
                  <KPI title="Pendientes"        value={resumenGeneral.tareas_pendientes} />
                  <KPI title="No ejecutadas"     value={resumenGeneral.tareas_no_ejecutadas} tone={resumenGeneral.tareas_no_ejecutadas > 0 ? 'red' : undefined} />
                </div>
                <div className="grid grid-cols-2 gap-3">
                  <KPI title="Sin responsable"   value={resumenGeneral.tareas_sin_responsable} tone={resumenGeneral.tareas_sin_responsable > 0 ? 'amber' : undefined} icon={<User className="h-4 w-4" />} />
                  <KPI title="Con comentarios"   value={resumenGeneral.tareas_con_comentario} icon={<MessageSquare className="h-4 w-4" />} />
                </div>
              </>
            )}
          </CardContent>
        </Card>
      )}

      {tab === 'por_area' && (
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-base flex items-center gap-2">
              <Layers className="h-4 w-4" /> Vista por lugar físico
            </CardTitle>
          </CardHeader>
          <CardContent className="overflow-x-auto">
            {!avancePorArea || avancePorArea.length === 0 ? (
              <p className="text-sm text-gray-400">Sin datos.</p>
            ) : (
              <table className="w-full text-xs">
                <thead>
                  <tr className="border-b bg-gray-50 text-left uppercase text-gray-500">
                    <th className="px-2 py-2">Cod.</th>
                    <th className="px-2 py-2">Lugar físico</th>
                    <th className="px-2 py-2 text-right">Total</th>
                    <th className="px-2 py-2 text-right">Final.</th>
                    <th className="px-2 py-2 text-right">Ejec.</th>
                    <th className="px-2 py-2 text-right">Pend.</th>
                    <th className="px-2 py-2 text-right">Plan sem.</th>
                    <th className="px-2 py-2 text-right">Sin resp.</th>
                    <th className="px-2 py-2 text-right">Coment.</th>
                    <th className="px-2 py-2 text-right">Avance</th>
                    <th className="px-2 py-2 text-center">Estado</th>
                  </tr>
                </thead>
                <tbody>
                  {avancePorArea.map((a) => {
                    const sem = a.tareas_no_ejecutadas > 0 || a.tareas_sin_responsable > 0
                      ? 'rojo'
                      : a.tareas_con_comentario > 0 || a.tareas_pendientes > a.tareas_finalizadas
                      ? 'amarillo'
                      : 'verde'
                    return (
                      <tr key={a.zona_proyecto_id}
                          className="border-b cursor-pointer hover:bg-amber-50"
                          onClick={() => { setLugarFisicoSel(a.codigo_zona); setTab('planificacion') }}
                      >
                        <td className="px-2 py-1.5 font-mono">{a.codigo_zona}</td>
                        <td className="px-2 py-1.5">{a.lugar_fisico_nombre}</td>
                        <td className="px-2 py-1.5 text-right">{a.total_tareas}</td>
                        <td className="px-2 py-1.5 text-right text-green-700">{a.tareas_finalizadas}</td>
                        <td className="px-2 py-1.5 text-right text-amber-700">{a.tareas_en_ejecucion}</td>
                        <td className="px-2 py-1.5 text-right">{a.tareas_pendientes}</td>
                        <td className="px-2 py-1.5 text-right">{a.tareas_planificadas_semana}</td>
                        <td className="px-2 py-1.5 text-right">{a.tareas_sin_responsable}</td>
                        <td className="px-2 py-1.5 text-right">{a.tareas_con_comentario}</td>
                        <td className="px-2 py-1.5 text-right font-medium">{a.avance_promedio_pct.toFixed(1)}%</td>
                        <td className="px-2 py-1.5 text-center">
                          <span className={`inline-block w-3 h-3 rounded-full ${
                            sem === 'verde' ? 'bg-green-500' : sem === 'amarillo' ? 'bg-amber-400' : 'bg-red-500'
                          }`} />
                        </td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            )}
          </CardContent>
          <CardContent className="pt-0 text-xs text-gray-400">
            Click en un lugar físico para filtrar el Kanban.
          </CardContent>
        </Card>
      )}

      {/* Modal comentario */}
      <Modal open={!!comentarioOpen} onClose={() => !updateComentario.isPending && setComentarioOpen(null)} title="Comentario de planificación">
        <div className="space-y-3 text-sm">
          <p className="text-gray-600">
            Ej: "Planificada, pero falta material X" / "Falta autorización del mandante" /
            "Esperando ingreso al área".
          </p>
          <textarea
            value={comentarioTexto}
            onChange={(e) => setComentarioTexto(e.target.value)}
            rows={4}
            className="w-full rounded border border-gray-300 px-3 py-2 text-sm"
            placeholder="Escribe el comentario…"
          />
        </div>
        <ModalFooter className="-mx-6 -mb-6 mt-4 px-6 pb-6 pt-4 border-t border-gray-100">
          <Button variant="secondary" onClick={() => setComentarioOpen(null)} disabled={updateComentario.isPending}>
            <X className="h-4 w-4" /> Cancelar
          </Button>
          <Button variant="primary" onClick={guardarComentario} loading={updateComentario.isPending}>
            <CheckCircle2 className="h-4 w-4" /> Guardar
          </Button>
        </ModalFooter>
      </Modal>

      {/* Modal actualizar avance manual */}
      <Modal
        open={!!avanceOpen}
        onClose={() => !updateAvance.isPending && setAvanceOpen(null)}
        title="Actualizar avance manual"
      >
        <div className="space-y-3 text-sm">
          {(() => {
            const ot = avanceOpen ? otsById.get(avanceOpen) : null
            const avanceExcel = ot ? Number((ot as { avance_excel_pct?: number }).avance_excel_pct ?? 0) : 0
            const avanceReal = ot ? Number(ot.avance_pct ?? 0) : 0
            return ot ? (
              <div className="rounded border bg-gray-50 p-2 text-xs">
                <div className="font-mono text-gray-500">{excelCodigoFromFolio(ot.folio)}</div>
                <div className="text-gray-900 mt-0.5">{ot.titulo}</div>
                <div className="mt-1 flex gap-3 text-gray-600">
                  <span>Excel: <strong>{avanceExcel.toFixed(0)}%</strong></span>
                  <span>Real actual: <strong>{avanceReal.toFixed(0)}%</strong></span>
                </div>
              </div>
            ) : null
          })()}

          <div>
            <label className="text-xs text-gray-500">Nuevo avance %</label>
            <input
              type="number" min={0} max={100}
              value={avanceValor}
              onChange={(e) => setAvanceValor(Math.min(100, Math.max(0, Number(e.target.value))))}
              className="mt-1 w-full rounded border border-gray-300 px-3 py-2 text-sm font-mono text-lg"
            />
            <input
              type="range" min={0} max={100} step={5}
              value={avanceValor}
              onChange={(e) => setAvanceValor(Number(e.target.value))}
              className="mt-1 w-full"
            />
          </div>

          <div>
            <label className="text-xs text-gray-500">Motivo</label>
            <Select
              value={avanceMotivo}
              onChange={(e) => setAvanceMotivo(e.target.value)}
              options={[
                { value: 'ajuste_manual',          label: 'Ajuste manual' },
                { value: 'validado_en_terreno',    label: 'Validado en terreno' },
                { value: 'actualizacion_mandante', label: 'Actualizacion por mandante' },
                { value: 'correccion_planificacion', label: 'Correccion de planificacion' },
                { value: 'otro',                   label: 'Otro' },
              ]}
            />
          </div>

          <div>
            <label className="text-xs text-gray-500">
              Comentario {avanceValor >= 100 && <span className="text-red-600">(obligatorio para 100%)</span>}
            </label>
            <textarea
              value={avanceComentario}
              onChange={(e) => setAvanceComentario(e.target.value)}
              rows={3}
              className="mt-1 w-full rounded border border-gray-300 px-3 py-2 text-sm"
              placeholder="Detalle del cambio…"
            />
          </div>

          {avanceValor >= 100 && (
            <div className="rounded border border-amber-300 bg-amber-50 p-2 text-xs text-amber-900">
              Esto marcará la OT como <strong>finalizada</strong>.
            </div>
          )}
        </div>
        <ModalFooter className="-mx-6 -mb-6 mt-4 px-6 pb-6 pt-4 border-t border-gray-100">
          <Button variant="secondary" onClick={() => setAvanceOpen(null)} disabled={updateAvance.isPending}>
            <X className="h-4 w-4" /> Cancelar
          </Button>
          <Button variant="primary" onClick={guardarAvance} loading={updateAvance.isPending}>
            <CheckCircle2 className="h-4 w-4" /> Guardar avance
          </Button>
        </ModalFooter>
      </Modal>
    </div>
  )
}

// ─── Subcomponentes ──────────────────────────────────────────────────────────

function DroppableContainer({
  id, children, className,
}: { id: string; children: React.ReactNode; className?: string }) {
  const { setNodeRef, isOver } = useDroppable({ id })
  return (
    <div ref={setNodeRef} className={`${className ?? ''} ${isOver ? 'ring-2 ring-amber-400' : ''}`}>
      {children}
    </div>
  )
}

function DraggableOTCard({
  ot, compact, responsableId, comentario, usuarios, disabled,
  onAsignar, onQuitar, onComentar, onActualizarAvance,
}: {
  ot: CalamaOTConRelaciones
  compact?: boolean
  responsableId?: string | null
  comentario?: string | null
  usuarios?: Array<{ id: string; nombre_completo: string | null; email?: string | null; cargo?: string | null }>
  disabled?: boolean
  onAsignar?: (uid: string) => void
  onQuitar?: () => void
  onComentar?: () => void
  onActualizarAvance?: () => void
}) {
  const { attributes, listeners, setNodeRef, isDragging } = useDraggable({ id: ot.id, disabled })
  return (
    <div ref={setNodeRef} {...attributes} {...listeners}
      className={`${isDragging ? 'opacity-30' : ''} ${disabled ? 'cursor-not-allowed' : 'cursor-grab active:cursor-grabbing'}`}
    >
      <OTCardContent
        ot={ot} compact={compact}
        responsableId={responsableId} comentario={comentario}
        usuarios={usuarios}
        onAsignar={onAsignar} onQuitar={onQuitar} onComentar={onComentar}
        onActualizarAvance={onActualizarAvance}
        disabled={disabled}
      />
    </div>
  )
}

function OTCardContent({
  ot, compact, responsableId, comentario, usuarios, onAsignar, onQuitar, onComentar, onActualizarAvance, disabled,
}: {
  ot: CalamaOTConRelaciones
  compact?: boolean
  responsableId?: string | null
  comentario?: string | null
  usuarios?: Array<{ id: string; nombre_completo: string | null; email?: string | null; cargo?: string | null }>
  onAsignar?: (uid: string) => void
  onQuitar?: () => void
  onComentar?: () => void
  onActualizarAvance?: () => void
  disabled?: boolean
}) {
  const codigo = excelCodigoFromFolio(ot.folio)
  const lugar = zonaCodeFromFolio(ot.folio)
  const avanceExcel = Number((ot as { avance_excel_pct?: number }).avance_excel_pct ?? 0)
  const avanceReal = Number(ot.avance_pct ?? 0)
  const desv = avanceReal - avanceExcel

  if (compact) {
    return (
      <div className="rounded border border-gray-200 bg-white p-2 text-xs shadow-sm">
        <div className="flex items-center justify-between gap-1 mb-1">
          <span className="font-mono text-[10px] text-gray-500">{codigo}</span>
          <EstadoBadge estado={ot.estado} />
        </div>
        <div className="text-gray-900 truncate" title={ot.titulo}>{ot.titulo}</div>
        <div className="mt-1 flex items-center gap-2 text-[10px] text-gray-500 flex-wrap">
          <span className="inline-flex items-center gap-0.5"><MapPin className="h-3 w-3" />{lugar ?? '—'}</span>
          {ot.horas_estimadas != null && (
            <span className="inline-flex items-center gap-0.5"><Clock className="h-3 w-3" />{ot.horas_estimadas}h</span>
          )}
          <span className="inline-flex items-center gap-0.5" title="Avance Excel / Real">
            E {avanceExcel.toFixed(0)}% · R <span className={avanceReal >= 100 ? 'text-green-700 font-medium' : 'text-gray-700 font-medium'}>{avanceReal.toFixed(0)}%</span>
          </span>
          {desv !== 0 && (
            <span className={`text-[10px] ${desv > 0 ? 'text-green-700' : 'text-red-700'}`}>
              {desv > 0 ? '+' : ''}{desv.toFixed(0)}pp
            </span>
          )}
          {comentario && (
            <span className="inline-flex items-center gap-0.5 text-amber-700" title={comentario}>
              <MessageSquare className="h-3 w-3" />
            </span>
          )}
        </div>
        {usuarios && onAsignar && (
          <div className="mt-1.5">
            <select
              value={responsableId ?? ''}
              onChange={(e) => e.target.value && onAsignar(e.target.value)}
              onPointerDown={(e) => e.stopPropagation()}
              onPointerUp={(e) => e.stopPropagation()}
              disabled={disabled}
              className="w-full rounded border border-gray-200 px-1.5 py-1 text-[10px] bg-white"
            >
              <option value="">Asignar responsable…</option>
              {usuarios.map((u) => (
                <option key={u.id} value={u.id}>
                  {u.nombre_completo || u.email || `(${u.id.slice(0, 6)})`}
                  {u.cargo ? ` — ${u.cargo}` : ''}
                </option>
              ))}
            </select>
          </div>
        )}
        <div className="mt-1.5 flex gap-1">
          {onComentar && (
            <button
              onClick={(e) => { e.stopPropagation(); onComentar() }}
              onPointerDown={(e) => e.stopPropagation()}
              disabled={disabled}
              className={`flex-1 inline-flex items-center justify-center gap-1 rounded border px-2 py-0.5 text-[10px] disabled:opacity-40 ${
                comentario
                  ? 'border-amber-300 bg-amber-50 text-amber-800 hover:bg-amber-100'
                  : 'border-gray-200 bg-white text-gray-700 hover:bg-gray-50'
              }`}
            >
              <MessageSquare className="h-3 w-3" />
              {comentario ? 'Editar' : 'Comentar'}
            </button>
          )}
          {onActualizarAvance && (
            <button
              onClick={(e) => { e.stopPropagation(); onActualizarAvance() }}
              onPointerDown={(e) => e.stopPropagation()}
              className="inline-flex items-center justify-center gap-1 rounded border border-indigo-200 bg-indigo-50 px-2 py-0.5 text-[10px] text-indigo-700 hover:bg-indigo-100"
              title="Actualizar avance manual"
            >
              %
            </button>
          )}
          {onQuitar && (
            <button
              onClick={(e) => { e.stopPropagation(); onQuitar() }}
              onPointerDown={(e) => e.stopPropagation()}
              disabled={disabled}
              className="inline-flex items-center justify-center gap-1 rounded border border-red-200 bg-red-50 px-2 py-0.5 text-[10px] text-red-700 hover:bg-red-100 disabled:opacity-40"
            >
              <Trash2 className="h-3 w-3" />
            </button>
          )}
        </div>
      </div>
    )
  }

  return (
    <div className="rounded-lg border border-gray-200 bg-white p-3 text-sm shadow-sm">
      <div className="flex items-center justify-between gap-2">
        <span className="font-mono text-xs text-gray-500">{codigo}</span>
        <EstadoBadge estado={ot.estado} />
      </div>
      <p className="mt-1 text-gray-900 line-clamp-2" title={ot.titulo}>{ot.titulo}</p>
      <div className="mt-2 flex flex-wrap gap-2 text-xs text-gray-500">
        <span className="inline-flex items-center gap-1"><MapPin className="h-3 w-3" />Lugar {lugar ?? '—'}</span>
        {ot.horas_estimadas != null && (
          <span className="inline-flex items-center gap-1"><Clock className="h-3 w-3" />{ot.horas_estimadas}h</span>
        )}
        <span className="font-medium">{(ot.avance_pct).toFixed(0)}%</span>
      </div>
    </div>
  )
}

function Stat({ label, value, tone }: { label: string; value: string | number; tone?: 'green' | 'red' | 'amber' }) {
  const tones: Record<string, string> = {
    green: 'text-green-700',
    red:   'text-red-700',
    amber: 'text-amber-700',
  }
  return (
    <div className="rounded border border-gray-200 bg-white px-2 py-1">
      <div className="text-[10px] uppercase text-gray-500">{label}</div>
      <div className={`text-sm font-semibold ${tone ? tones[tone] : 'text-gray-900'}`}>{value}</div>
    </div>
  )
}

function KPI({
  title, value, tone = 'gray', icon,
}: {
  title: string; value: string | number
  tone?: 'gray' | 'green' | 'red' | 'amber' | 'indigo'
  icon?: React.ReactNode
}) {
  const colors: Record<string, string> = {
    gray: 'border-gray-200 text-gray-900',
    green: 'border-green-200 text-green-700 bg-green-50',
    red: 'border-red-200 text-red-700 bg-red-50',
    amber: 'border-amber-200 text-amber-700 bg-amber-50',
    indigo: 'border-indigo-200 text-indigo-700 bg-indigo-50',
  }
  return (
    <div className={`rounded-xl border bg-white p-3 ${colors[tone]}`}>
      <div className="flex items-center gap-1.5 text-xs font-medium uppercase opacity-80">{icon}{title}</div>
      <div className="text-2xl font-bold mt-1">{value}</div>
    </div>
  )
}
