'use client'

import { useEffect, useMemo, useState } from 'react'
import {
  DndContext, DragEndEvent, DragOverlay, DragStartEvent,
  PointerSensor, useDraggable, useDroppable, useSensor, useSensors,
} from '@dnd-kit/core'
import {
  Calendar, Save, ArrowLeft, RefreshCw, ChevronLeft, ChevronRight,
  Lock, AlertTriangle, Trash2, User, Clock, MapPin,
} from 'lucide-react'
import Link from 'next/link'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { Select } from '@/components/ui/select'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useCalamaPlanificaciones, useCalamaOTs } from '@/hooks/use-calama'
import {
  useGetOrCreatePlanSemanal, usePlanSemanal, useDiasPlanSemanal, useOTsPlanSemanal,
  useMoverOTplanSemanal, useQuitarOTplanSemanal, useConfirmarPlanSemanal,
  useUsuariosAsignables, useAsignarResponsable,
} from '@/hooks/use-calama-plan-semanal'
import { lunesDe } from '@/lib/services/calama-plan-semanal'
import { zonaCodeFromFolio, excelCodigoFromFolio, type CalamaOTConRelaciones } from '@/lib/services/calama'
import { EstadoBadge } from '@/components/calama/gantt-table'

const BACKLOG_ID = 'backlog'

export default function PlanSemanalPage() {
  useRequireAuth()

  const { data: planificaciones } = useCalamaPlanificaciones()
  const [planificacionId, setPlanificacionId] = useState<string>('')
  const [semanaIso, setSemanaIso] = useState<string>(() => lunesDe(new Date()))
  const [planSemanalId, setPlanSemanalId] = useState<string>('')
  const [errorMsg, setErrorMsg] = useState<string | null>(null)

  const getOrCreate = useGetOrCreatePlanSemanal()
  const { data: planSem } = usePlanSemanal(planSemanalId || null)
  const { data: dias } = useDiasPlanSemanal(planSemanalId || null)
  const { data: planOts } = useOTsPlanSemanal(planSemanalId || null)
  const { data: ots } = useCalamaOTs(planificacionId ? { planificacionId } : undefined)
  const { data: usuarios } = useUsuariosAsignables()

  const moverOT = useMoverOTplanSemanal()
  const quitarOT = useQuitarOTplanSemanal()
  const confirmarPlan = useConfirmarPlanSemanal()
  const asignarResp = useAsignarResponsable()

  // Auto-seleccionar primera planificacion
  useEffect(() => {
    if (planificaciones && planificaciones.length > 0 && !planificacionId) {
      setPlanificacionId(planificaciones[0].id)
    }
  }, [planificaciones, planificacionId])

  // Auto-cargar plan semanal al elegir planificacion + semana
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

  // Backlog = OTs no en plan
  const backlog = useMemo(() => {
    if (!ots) return []
    return ots.filter((o) => !planOtsByOtId.has(o.id) && o.estado !== 'finalizada' && o.estado !== 'cancelada')
  }, [ots, planOtsByOtId])

  // OTs por dia
  const otsByDia = useMemo(() => {
    const m = new Map<string, CalamaOTConRelaciones[]>()
    for (const dia of dias ?? []) m.set(dia.id, [])
    for (const p of planOts ?? []) {
      const ot = otsById.get(p.ot_id)
      if (!ot) continue
      const arr = m.get(p.plan_dia_id)
      if (arr) arr.push(ot)
    }
    return m
  }, [dias, planOts, otsById])

  // Drag and drop state
  const [activeOTId, setActiveOTId] = useState<string | null>(null)
  const sensors = useSensors(useSensor(PointerSensor, { activationConstraint: { distance: 5 } }))

  const handleDragStart = (e: DragStartEvent) => setActiveOTId(String(e.active.id))

  const handleDragEnd = (e: DragEndEvent) => {
    setActiveOTId(null)
    const otId = String(e.active.id)
    const overId = e.over?.id ? String(e.over.id) : null
    if (!overId || !planSemanalId) return

    if (overId === BACKLOG_ID) {
      // Devolver al backlog (quitar del plan)
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

  const semanaPrev = () => {
    const d = new Date(semanaIso); d.setDate(d.getDate() - 7); setSemanaIso(d.toISOString().slice(0, 10))
  }
  const semanaSig = () => {
    const d = new Date(semanaIso); d.setDate(d.getDate() + 7); setSemanaIso(d.toISOString().slice(0, 10))
  }

  const planBloqueado = planSem?.estado === 'cerrado' || planSem?.estado === 'cancelado'
  const activeOT = activeOTId ? (otsById.get(activeOTId) ?? null) : null

  return (
    <div className="space-y-4">
      <Link
        href="/dashboard/operacion-calama"
        className="inline-flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700"
      >
        <ArrowLeft className="h-4 w-4" />
        Volver al panel Calama
      </Link>

      <div className="rounded-2xl bg-gradient-to-r from-amber-700 to-orange-600 p-6 text-white shadow-lg">
        <h1 className="text-2xl font-bold flex items-center gap-2">
          <Calendar className="h-6 w-6" />
          Plan Semanal Calama
        </h1>
        <p className="text-sm text-white/90 mt-1">
          Arrastra OTs desde el backlog (izquierda) hacia los dias de la semana.
        </p>
      </div>

      {/* Controles */}
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
              <input
                type="date"
                value={semanaIso}
                onChange={(e) => setSemanaIso(lunesDe(e.target.value))}
                className="min-h-[44px] flex-1 rounded-lg border border-gray-300 px-3 py-2 text-sm"
              />
              <button onClick={semanaSig} className="rounded border border-gray-300 p-2 hover:bg-gray-50">
                <ChevronRight className="h-4 w-4" />
              </button>
            </div>
            <p className="mt-1 text-xs text-gray-500">Lunes de la semana ({semanaIso})</p>
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
              <Button
                variant="primary"
                onClick={handleConfirmar}
                loading={confirmarPlan.isPending}
                disabled={(planOts?.length ?? 0) === 0}
              >
                <Save className="h-4 w-4" />
                Confirmar semana
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
        </div>
      )}

      <DndContext sensors={sensors} onDragStart={handleDragStart} onDragEnd={handleDragEnd}>
        <div className="grid grid-cols-1 lg:grid-cols-[320px,1fr] gap-4">
          {/* Backlog */}
          <DroppableContainer id={BACKLOG_ID} className="bg-white rounded-xl border border-gray-200 p-3">
            <h3 className="text-sm font-bold uppercase text-gray-700 mb-2 flex items-center gap-2">
              Backlog ({backlog.length})
            </h3>
            <p className="text-xs text-gray-400 mb-3">OTs sin asignar — arrastra a un dia.</p>
            <div className="space-y-2 max-h-[60vh] overflow-y-auto pr-1">
              {backlog.length === 0 ? (
                <p className="text-xs text-gray-400 italic text-center py-4">Todas las OTs estan en el plan.</p>
              ) : backlog.map((ot) => (
                <DraggableOTCard key={ot.id} ot={ot} disabled={planBloqueado} />
              ))}
            </div>
          </DroppableContainer>

          {/* Dias semana */}
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-7 gap-2">
            {(dias ?? []).map((dia) => {
              const otsDia = otsByDia.get(dia.id) ?? []
              return (
                <DroppableContainer
                  key={dia.id}
                  id={dia.id}
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
                          key={ot.id}
                          ot={ot}
                          compact
                          responsableId={planOt?.responsable_id ?? null}
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
    </div>
  )
}

// ─── Subcomponentes ──────────────────────────────────────────────────────────

function DroppableContainer({
  id, children, className,
}: {
  id: string; children: React.ReactNode; className?: string
}) {
  const { setNodeRef, isOver } = useDroppable({ id })
  return (
    <div ref={setNodeRef} className={`${className ?? ''} ${isOver ? 'ring-2 ring-amber-400' : ''}`}>
      {children}
    </div>
  )
}

function DraggableOTCard({
  ot, compact, responsableId, usuarios, disabled, onAsignar, onQuitar,
}: {
  ot: CalamaOTConRelaciones
  compact?: boolean
  responsableId?: string | null
  usuarios?: Array<{ id: string; nombre_completo: string | null }>
  disabled?: boolean
  onAsignar?: (uid: string) => void
  onQuitar?: () => void
}) {
  const { attributes, listeners, setNodeRef, isDragging } = useDraggable({ id: ot.id, disabled })
  return (
    <div
      ref={setNodeRef}
      {...attributes}
      {...listeners}
      className={`${isDragging ? 'opacity-30' : ''} ${disabled ? 'cursor-not-allowed' : 'cursor-grab active:cursor-grabbing'}`}
    >
      <OTCardContent
        ot={ot}
        compact={compact}
        responsableId={responsableId}
        usuarios={usuarios}
        onAsignar={onAsignar}
        onQuitar={onQuitar}
        disabled={disabled}
      />
    </div>
  )
}

function OTCardContent({
  ot, compact, responsableId, usuarios, onAsignar, onQuitar, disabled,
}: {
  ot: CalamaOTConRelaciones
  compact?: boolean
  responsableId?: string | null
  usuarios?: Array<{ id: string; nombre_completo: string | null }>
  onAsignar?: (uid: string) => void
  onQuitar?: () => void
  disabled?: boolean
}) {
  const codigo = excelCodigoFromFolio(ot.folio)
  const zona = zonaCodeFromFolio(ot.folio)

  if (compact) {
    return (
      <div className="rounded border border-gray-200 bg-white p-2 text-xs shadow-sm">
        <div className="flex items-center justify-between gap-1 mb-1">
          <span className="font-mono text-[10px] text-gray-500">{codigo}</span>
          <EstadoBadge estado={ot.estado} />
        </div>
        <div className="text-gray-900 truncate" title={ot.titulo}>{ot.titulo}</div>
        <div className="mt-1 flex items-center gap-2 text-[10px] text-gray-500">
          <span className="inline-flex items-center gap-0.5"><MapPin className="h-3 w-3" />{zona ?? '—'}</span>
          {ot.horas_estimadas != null && (
            <span className="inline-flex items-center gap-0.5"><Clock className="h-3 w-3" />{ot.horas_estimadas}h</span>
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
                <option key={u.id} value={u.id}>{u.nombre_completo ?? '(sin nombre)'}</option>
              ))}
            </select>
          </div>
        )}
        {onQuitar && (
          <button
            onClick={(e) => { e.stopPropagation(); onQuitar() }}
            onPointerDown={(e) => e.stopPropagation()}
            disabled={disabled}
            className="mt-1.5 w-full inline-flex items-center justify-center gap-1 rounded border border-red-200 bg-red-50 px-2 py-0.5 text-[10px] text-red-700 hover:bg-red-100 disabled:opacity-40"
          >
            <Trash2 className="h-3 w-3" />
            Quitar del dia
          </button>
        )}
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
        <span className="inline-flex items-center gap-1"><MapPin className="h-3 w-3" />Zona {zona ?? '—'}</span>
        {ot.horas_estimadas != null && (
          <span className="inline-flex items-center gap-1"><Clock className="h-3 w-3" />{ot.horas_estimadas}h</span>
        )}
        {ot.responsable_id && (
          <span className="inline-flex items-center gap-1"><User className="h-3 w-3" />Resp.</span>
        )}
      </div>
    </div>
  )
}
