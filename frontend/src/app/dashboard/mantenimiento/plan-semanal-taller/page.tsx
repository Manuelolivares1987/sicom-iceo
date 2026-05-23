'use client'

import { useMemo, useState, useEffect } from 'react'
import Link from 'next/link'
import {
  DndContext, DragEndEvent, PointerSensor, useDraggable, useDroppable, useSensor, useSensors,
} from '@dnd-kit/core'
import {
  Calendar, ArrowLeft, ChevronLeft, ChevronRight, Lock, AlertTriangle, Trash2, User,
  Play, Pause, CheckCircle2, BarChart3, ShieldAlert, RefreshCw, Wrench, Layers,
} from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { Modal, ModalFooter } from '@/components/ui/modal'
import { Input } from '@/components/ui/input'
import { useToast } from '@/contexts/toast-context'
import { useRequireAuth } from '@/hooks/use-require-auth'
import {
  useGetOrCreatePlanSemanalTaller, useDiasPlanSemanalTaller, useJornadasPlanSemanalTaller,
  useBacklogTaller, useKpiSemanalTaller, useCumplimientoPmMesTaller,
  useUsuariosAsignablesTaller, useCoberturaPm, useActivosSinPlan,
  useAgregarJornadaTaller, useMoverJornadaTaller, useQuitarJornadaTaller,
  useAsignarResponsableTaller, useConfirmarPlanSemanalTaller,
  useIniciarEjecucionTaller, usePausarEjecucionTaller, useFinalizarEjecucionTaller,
  useAdminSembrarPlanesFaltantes,
} from '@/hooks/use-taller-plan-semanal'
import { lunesDeIso, type TallerPlanOTFull, type TallerOTBacklog } from '@/lib/services/taller-plan-semanal'

const BACKLOG_ID = 'backlog'
type Tab = 'kanban' | 'cobertura' | 'cumplimiento'

function fmtFecha(iso: string) {
  const d = new Date(iso + 'T12:00:00')
  return d.toLocaleDateString('es-CL', { day: '2-digit', month: 'short' })
}

function colorTipo(tipo: string): string {
  switch (tipo) {
    case 'preventivo':  return 'bg-blue-100 text-blue-800 border-blue-300'
    case 'correctivo':  return 'bg-red-100 text-red-800 border-red-300'
    case 'inspeccion':  return 'bg-amber-100 text-amber-800 border-amber-300'
    case 'lubricacion': return 'bg-purple-100 text-purple-800 border-purple-300'
    default:            return 'bg-gray-100 text-gray-800 border-gray-300'
  }
}

function colorPrioridad(p: string): string {
  if (p === 'emergencia') return 'bg-red-600 text-white'
  if (p === 'urgente')    return 'bg-orange-500 text-white'
  if (p === 'alta')       return 'bg-amber-500 text-white'
  if (p === 'normal')     return 'bg-gray-300 text-gray-800'
  return 'bg-gray-100 text-gray-600'
}

export default function PlanSemanalTallerPage() {
  useRequireAuth()
  const toast = useToast()

  const [semanaIso, setSemanaIso] = useState<string>(() => lunesDeIso(new Date()))
  const [planSemanalId, setPlanSemanalId] = useState<string>('')
  const [tab, setTab] = useState<Tab>('kanban')

  const getOrCreate = useGetOrCreatePlanSemanalTaller()
  const { data: dias } = useDiasPlanSemanalTaller(planSemanalId || null)
  const { data: jornadas, isLoading: loadJornadas } = useJornadasPlanSemanalTaller(planSemanalId || null)
  const { data: backlog } = useBacklogTaller()
  const { data: kpi } = useKpiSemanalTaller(planSemanalId || null)
  const { data: cobertura } = useCoberturaPm()

  const moverJornada = useMoverJornadaTaller(planSemanalId)
  const agregarJornada = useAgregarJornadaTaller(planSemanalId)
  const quitarJornada = useQuitarJornadaTaller(planSemanalId)
  const confirmarPlan = useConfirmarPlanSemanalTaller(planSemanalId)
  const iniciarEjec = useIniciarEjecucionTaller(planSemanalId)
  const pausarEjec  = usePausarEjecucionTaller(planSemanalId)
  const finalizarEjec = useFinalizarEjecucionTaller(planSemanalId)

  const [asignarOpen, setAsignarOpen] = useState<TallerPlanOTFull | null>(null)
  const [finalizarOpen, setFinalizarOpen] = useState<TallerPlanOTFull | null>(null)
  const [finAvance, setFinAvance] = useState<number>(100)
  const [finObs, setFinObs] = useState<string>('')

  // Resolver/crear plan al cambiar de semana
  useEffect(() => {
    if (!semanaIso) return
    getOrCreate.mutate({ fechaInicio: semanaIso }, {
      onSuccess: (d) => setPlanSemanalId(d.plan_semanal_id),
      onError: (e) => toast.error((e as Error).message),
    })
  /* eslint-disable-next-line react-hooks/exhaustive-deps */
  }, [semanaIso])

  const navSemana = (delta: number) => {
    const d = new Date(semanaIso + 'T12:00:00')
    d.setDate(d.getDate() + delta * 7)
    setSemanaIso(lunesDeIso(d))
  }

  // OTs ya asignadas al plan (para filtrar el backlog y no duplicar)
  const otsEnPlan = useMemo(() => new Set((jornadas ?? []).map((j) => j.ot_id)), [jornadas])
  const backlogFiltrado = useMemo(
    () => (backlog ?? []).filter((b) => !otsEnPlan.has(b.ot_id)),
    [backlog, otsEnPlan],
  )

  // Drag & drop
  const sensors = useSensors(useSensor(PointerSensor, { activationConstraint: { distance: 5 } }))

  const handleDragEnd = (e: DragEndEvent) => {
    const aOver = e.over?.id?.toString()
    const aActive = e.active?.id?.toString()
    if (!aOver || !aActive) return

    const isFromBacklog = aActive.startsWith('backlog:')
    const isFromJornada = aActive.startsWith('jornada:')
    if (!aOver.startsWith('dia:')) return

    const fechaDestino = aOver.replace('dia:', '')

    if (isFromBacklog) {
      const otId = aActive.replace('backlog:', '')
      agregarJornada.mutate({
        planSemanalId, otId, fecha: fechaDestino,
      }, {
        onSuccess: () => toast.success('OT agregada al plan'),
        onError: (err) => toast.error((err as Error).message),
      })
    } else if (isFromJornada) {
      const planOtId = aActive.replace('jornada:', '')
      moverJornada.mutate({ planOtId, fechaDestino }, {
        onSuccess: () => toast.success('Jornada movida'),
        onError: (err) => toast.error((err as Error).message),
      })
    }
  }

  return (
    <div className="space-y-4 p-4 sm:p-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-3">
          <Link href="/dashboard/mantenimiento">
            <Button variant="ghost" size="sm" className="gap-1"><ArrowLeft className="h-4 w-4" /> Mantenimiento</Button>
          </Link>
          <div>
            <h1 className="flex items-center gap-2 text-2xl font-bold">
              <Wrench className="h-6 w-6 text-blue-700" />
              Plan semanal del taller
            </h1>
            <p className="text-sm text-muted-foreground">
              Programa preventivas y correctivas. Drag &amp; drop entre días.
            </p>
          </div>
        </div>
        <div className="flex gap-2 flex-wrap">
          <Button variant="outline" size="sm" onClick={() => navSemana(-1)}>
            <ChevronLeft className="h-4 w-4" />
          </Button>
          <Button variant="outline" size="sm" onClick={() => setSemanaIso(lunesDeIso(new Date()))}>
            <Calendar className="h-4 w-4 mr-1" /> Hoy
          </Button>
          <Button variant="outline" size="sm" onClick={() => navSemana(1)}>
            <ChevronRight className="h-4 w-4" />
          </Button>
          <Button
            size="sm"
            disabled={!planSemanalId || confirmarPlan.isPending}
            onClick={() => confirmarPlan.mutate(planSemanalId, {
              onSuccess: (d) => toast.success(`Plan confirmado: ${d.ots_confirmadas} jornadas`),
              onError: (err) => toast.error((err as Error).message),
            })}
            className="bg-pillado-green-600 hover:bg-pillado-green-700"
          >
            <Lock className="h-4 w-4 mr-1" /> Confirmar plan
          </Button>
        </div>
      </div>

      {/* Banner cobertura PM */}
      {cobertura && cobertura.activos_sin_plan > 0 && (
        <Card className="border-amber-300 bg-amber-50">
          <CardContent className="flex items-center justify-between p-3 text-sm">
            <div className="flex items-center gap-2 text-amber-800">
              <ShieldAlert className="h-4 w-4" />
              <span>
                <strong>{cobertura.activos_sin_plan} activos sin plan preventivo</strong>
                {' '}— cobertura actual {cobertura.cobertura_pct}%.
              </span>
            </div>
            <Button size="sm" variant="outline" onClick={() => setTab('cobertura')}>Ver detalle</Button>
          </CardContent>
        </Card>
      )}

      {/* Tabs */}
      <div className="flex gap-2 border-b">
        <TabBtn active={tab === 'kanban'} onClick={() => setTab('kanban')} icon={<Layers className="h-4 w-4" />}>Kanban semanal</TabBtn>
        <TabBtn active={tab === 'cobertura'} onClick={() => setTab('cobertura')} icon={<ShieldAlert className="h-4 w-4" />}>
          Cobertura PM {cobertura && cobertura.activos_sin_plan > 0 ? `(${cobertura.activos_sin_plan})` : ''}
        </TabBtn>
        <TabBtn active={tab === 'cumplimiento'} onClick={() => setTab('cumplimiento')} icon={<BarChart3 className="h-4 w-4" />}>Cumplimiento PM</TabBtn>
      </div>

      {/* KPIs semana actual */}
      {kpi && tab === 'kanban' && (
        <div className="grid grid-cols-2 md:grid-cols-6 gap-2 text-xs">
          <KpiCard label="Planificadas" valor={kpi.jornadas_planificadas} />
          <KpiCard label="Finalizadas" valor={kpi.jornadas_finalizadas} color="text-green-700" />
          <KpiCard label="En ejecución" valor={kpi.jornadas_en_ejecucion} color="text-amber-700" />
          <KpiCard label="Atrasadas" valor={kpi.jornadas_atrasadas} color="text-red-700" />
          <KpiCard label="Cumplim. %" valor={`${kpi.cumplimiento_pct}%`} color="text-blue-700" />
          <KpiCard label="Hs plan / real" valor={`${Math.round(kpi.horas_planificadas)} / ${Math.round(kpi.horas_reales)}`} />
        </div>
      )}

      {tab === 'kanban' && (
        <DndContext sensors={sensors} onDragEnd={handleDragEnd}>
          <div className="grid grid-cols-1 lg:grid-cols-[260px_1fr] gap-3">
            {/* Backlog izq */}
            <BacklogPanel items={backlogFiltrado} />

            {/* 7 días */}
            <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-7 gap-2">
              {loadJornadas ? (
                <div className="col-span-7 flex justify-center py-10"><Spinner /></div>
              ) : (
                (dias ?? []).map((dia) => (
                  <DiaColumna
                    key={dia.id}
                    fecha={dia.fecha}
                    nombre={dia.nombre_dia}
                    jornadas={(jornadas ?? []).filter((j) => j.plan_dia_id === dia.id)}
                    onAsignar={(j) => setAsignarOpen(j)}
                    onQuitar={(j) => quitarJornada.mutate(j.plan_ot_id, {
                      onSuccess: () => toast.success('Jornada quitada'),
                      onError: (err) => toast.error((err as Error).message),
                    })}
                    onIniciar={(j) => iniciarEjec.mutate({ otId: j.ot_id }, {
                      onSuccess: () => toast.success('OT iniciada'),
                      onError: (err) => toast.error((err as Error).message),
                    })}
                    onPausar={(j) => j.ejecucion_activa_id && pausarEjec.mutate({ ejecucionId: j.ejecucion_activa_id }, {
                      onSuccess: () => toast.success('OT pausada'),
                      onError: (err) => toast.error((err as Error).message),
                    })}
                    onFinalizar={(j) => { setFinalizarOpen(j); setFinAvance(100); setFinObs('') }}
                  />
                ))
              )}
            </div>
          </div>
        </DndContext>
      )}

      {tab === 'cobertura' && <CoberturaTab />}
      {tab === 'cumplimiento' && <CumplimientoTab />}

      {/* Modal asignar responsable */}
      {asignarOpen && (
        <AsignarResponsableModal
          jornada={asignarOpen}
          onClose={() => setAsignarOpen(null)}
          planId={planSemanalId}
        />
      )}

      {/* Modal finalizar ejecución */}
      {finalizarOpen && finalizarOpen.ejecucion_activa_id && (
        <Modal open={true} onClose={() => setFinalizarOpen(null)} title={`Finalizar ${finalizarOpen.ot_folio}`}>
          <div className="space-y-3">
            <div>
              <label className="text-xs font-medium">Avance final (%)</label>
              <Input type="number" min="0" max="100" value={finAvance}
                     onChange={(e) => setFinAvance(Number(e.target.value))} />
            </div>
            <div>
              <label className="text-xs font-medium">Observación cierre</label>
              <Input value={finObs} onChange={(e) => setFinObs(e.target.value)} placeholder="opcional" />
            </div>
          </div>
          <ModalFooter>
            <Button variant="outline" onClick={() => setFinalizarOpen(null)}>Cancelar</Button>
            <Button onClick={() => {
              finalizarEjec.mutate({
                ejecucionId: finalizarOpen.ejecucion_activa_id!,
                avanceFinal: finAvance,
                observacion: finObs.trim() || null,
              }, {
                onSuccess: () => { toast.success('OT finalizada'); setFinalizarOpen(null) },
                onError: (err) => toast.error((err as Error).message),
              })
            }}>Finalizar</Button>
          </ModalFooter>
        </Modal>
      )}
    </div>
  )
}

// ── Sub-componentes ─────────────────────────────────────────────────────────

function TabBtn({ active, onClick, children, icon }: {
  active: boolean; onClick: () => void; children: React.ReactNode; icon?: React.ReactNode
}) {
  return (
    <button onClick={onClick}
            className={`flex items-center gap-1 px-3 py-2 text-sm font-medium border-b-2 transition-colors ${
              active
                ? 'border-blue-600 text-blue-700'
                : 'border-transparent text-gray-500 hover:text-gray-700'
            }`}>
      {icon}{children}
    </button>
  )
}

function KpiCard({ label, valor, color }: { label: string; valor: string | number; color?: string }) {
  return (
    <div className="rounded-lg border bg-white p-2">
      <div className="text-[10px] uppercase tracking-wide text-gray-500">{label}</div>
      <div className={`text-lg font-bold tabular-nums ${color ?? 'text-gray-900'}`}>{valor}</div>
    </div>
  )
}

function BacklogPanel({ items }: { items: TallerOTBacklog[] }) {
  const { setNodeRef, isOver } = useDroppable({ id: BACKLOG_ID })
  return (
    <Card ref={setNodeRef} className={isOver ? 'ring-2 ring-blue-300' : ''}>
      <CardHeader className="pb-2">
        <CardTitle className="text-sm flex items-center gap-2">
          <Layers className="h-4 w-4" /> OTs pendientes ({items.length})
        </CardTitle>
      </CardHeader>
      <CardContent className="p-2 max-h-[70vh] overflow-y-auto space-y-1.5">
        {items.length === 0 ? (
          <div className="text-xs text-gray-400 p-4 text-center">Sin OTs pendientes</div>
        ) : (
          items.map((b) => <BacklogCard key={b.ot_id} item={b} />)
        )}
      </CardContent>
    </Card>
  )
}

function BacklogCard({ item }: { item: TallerOTBacklog }) {
  const { attributes, listeners, setNodeRef, transform, isDragging } = useDraggable({
    id: `backlog:${item.ot_id}`,
  })
  const style = transform
    ? { transform: `translate3d(${transform.x}px,${transform.y}px,0)`, opacity: isDragging ? 0.5 : 1 }
    : undefined

  return (
    <div ref={setNodeRef} style={style} {...listeners} {...attributes}
         className="rounded border bg-white p-2 cursor-grab active:cursor-grabbing hover:border-blue-400 shadow-sm">
      <div className="flex items-center gap-1.5">
        <span className={`text-[9px] px-1.5 py-0.5 rounded font-bold ${colorTipo(item.ot_tipo)}`}>
          {item.ot_tipo.toUpperCase().slice(0, 4)}
        </span>
        <span className={`text-[9px] px-1.5 py-0.5 rounded font-bold ${colorPrioridad(item.ot_prioridad)}`}>
          {item.ot_prioridad}
        </span>
      </div>
      <div className="text-[11px] font-mono font-bold mt-1">{item.ot_folio}</div>
      {item.activo_codigo && (
        <div className="text-[10px] text-gray-600">
          {item.activo_codigo} {item.activo_patente && `· ${item.activo_patente}`}
        </div>
      )}
      {item.pm_nombre && (
        <div className="text-[10px] text-blue-700 mt-0.5 line-clamp-2">{item.pm_nombre}</div>
      )}
      {item.proxima_ejecucion_fecha && (
        <div className="text-[9px] text-gray-400 mt-0.5">
          PM vence: {fmtFecha(item.proxima_ejecucion_fecha)}
        </div>
      )}
    </div>
  )
}

function DiaColumna({ fecha, nombre, jornadas, onAsignar, onQuitar, onIniciar, onPausar, onFinalizar }: {
  fecha: string
  nombre: string
  jornadas: TallerPlanOTFull[]
  onAsignar: (j: TallerPlanOTFull) => void
  onQuitar: (j: TallerPlanOTFull) => void
  onIniciar: (j: TallerPlanOTFull) => void
  onPausar: (j: TallerPlanOTFull) => void
  onFinalizar: (j: TallerPlanOTFull) => void
}) {
  const { setNodeRef, isOver } = useDroppable({ id: `dia:${fecha}` })
  const esHoy = fecha === new Date().toISOString().slice(0, 10)

  return (
    <Card ref={setNodeRef} className={`${isOver ? 'ring-2 ring-blue-400' : ''} ${esHoy ? 'border-blue-400' : ''}`}>
      <CardHeader className={`pb-2 ${esHoy ? 'bg-blue-50' : ''}`}>
        <CardTitle className="text-xs flex items-center justify-between">
          <span className="capitalize">{nombre}</span>
          <span className="text-[10px] text-gray-500 font-normal">{fmtFecha(fecha)}</span>
        </CardTitle>
      </CardHeader>
      <CardContent className="p-2 min-h-[60vh] space-y-1.5">
        {jornadas.length === 0 ? (
          <div className="text-[10px] text-gray-400 p-2 text-center">Sin OTs</div>
        ) : (
          jornadas.map((j) => (
            <JornadaCard key={j.plan_ot_id} jornada={j}
                         onAsignar={onAsignar} onQuitar={onQuitar}
                         onIniciar={onIniciar} onPausar={onPausar} onFinalizar={onFinalizar} />
          ))
        )}
      </CardContent>
    </Card>
  )
}

function JornadaCard({ jornada, onAsignar, onQuitar, onIniciar, onPausar, onFinalizar }: {
  jornada: TallerPlanOTFull
  onAsignar: (j: TallerPlanOTFull) => void
  onQuitar: (j: TallerPlanOTFull) => void
  onIniciar: (j: TallerPlanOTFull) => void
  onPausar: (j: TallerPlanOTFull) => void
  onFinalizar: (j: TallerPlanOTFull) => void
}) {
  const { attributes, listeners, setNodeRef, transform, isDragging } = useDraggable({
    id: `jornada:${jornada.plan_ot_id}`,
    disabled: jornada.jornada_estado === 'en_ejecucion' || jornada.jornada_estado === 'finalizada',
  })
  const style = transform
    ? { transform: `translate3d(${transform.x}px,${transform.y}px,0)`, opacity: isDragging ? 0.5 : 1 }
    : undefined

  const enEjec = jornada.ejecucion_activa_estado === 'en_ejecucion'
  const pausada = jornada.ejecucion_activa_estado === 'pausada'
  const finalizada = jornada.jornada_estado === 'finalizada'

  return (
    <div ref={setNodeRef} style={style}
         className={`rounded border p-2 shadow-sm bg-white text-[11px] ${
           finalizada ? 'opacity-60 border-green-200' :
           enEjec ? 'border-amber-400 ring-1 ring-amber-200' :
           'hover:border-blue-300'
         }`}>
      <div {...listeners} {...attributes} className="cursor-grab active:cursor-grabbing">
        <div className="flex items-center gap-1">
          <span className={`text-[9px] px-1.5 py-0.5 rounded font-bold ${colorTipo(jornada.ot_tipo)}`}>
            {jornada.ot_tipo.toUpperCase().slice(0, 4)}
          </span>
          {jornada.secuencia_jornada > 1 && (
            <span className="text-[9px] px-1 py-0.5 rounded bg-purple-100 text-purple-700 font-bold">
              J{jornada.secuencia_jornada}
            </span>
          )}
          {jornada.horas_planificadas && (
            <span className="text-[9px] text-gray-500 ml-auto">{jornada.horas_planificadas}h</span>
          )}
        </div>
        <div className="font-mono font-bold mt-0.5">{jornada.ot_folio}</div>
        {jornada.activo_codigo && (
          <div className="text-[10px] text-gray-600">
            {jornada.activo_codigo} {jornada.activo_patente && `· ${jornada.activo_patente}`}
          </div>
        )}
        {jornada.pm_nombre && (
          <div className="text-[10px] text-blue-700 mt-0.5 line-clamp-1">{jornada.pm_nombre}</div>
        )}
        <div className="flex items-center gap-1 mt-1">
          <User className="h-3 w-3 text-gray-400" />
          <span className="text-[10px] text-gray-600 truncate">{jornada.responsable ?? 'Sin asignar'}</span>
        </div>
        {jornada.avance_objetivo_pct && (
          <div className="text-[9px] text-gray-500 mt-0.5">Meta {jornada.avance_objetivo_pct}%</div>
        )}
      </div>

      {/* Acciones */}
      <div className="flex gap-1 mt-1.5">
        {!finalizada && (
          <>
            <button onClick={() => onAsignar(jornada)}
                    className="text-[9px] px-1.5 py-0.5 rounded bg-gray-100 hover:bg-gray-200 flex items-center gap-1">
              <User className="h-3 w-3" />
            </button>
            {!enEjec && !pausada && (
              <button onClick={() => onIniciar(jornada)} title="Iniciar"
                      className="text-[9px] px-1.5 py-0.5 rounded bg-green-100 hover:bg-green-200 text-green-700">
                <Play className="h-3 w-3" />
              </button>
            )}
            {enEjec && (
              <>
                <button onClick={() => onPausar(jornada)} title="Pausar"
                        className="text-[9px] px-1.5 py-0.5 rounded bg-amber-100 hover:bg-amber-200 text-amber-700">
                  <Pause className="h-3 w-3" />
                </button>
                <button onClick={() => onFinalizar(jornada)} title="Finalizar"
                        className="text-[9px] px-1.5 py-0.5 rounded bg-green-100 hover:bg-green-200 text-green-700">
                  <CheckCircle2 className="h-3 w-3" />
                </button>
              </>
            )}
            {pausada && (
              <button onClick={() => onFinalizar(jornada)} title="Finalizar"
                      className="text-[9px] px-1.5 py-0.5 rounded bg-green-100 hover:bg-green-200 text-green-700">
                <CheckCircle2 className="h-3 w-3" />
              </button>
            )}
            <button onClick={() => onQuitar(jornada)} title="Quitar del plan"
                    className="text-[9px] px-1.5 py-0.5 rounded bg-red-50 hover:bg-red-100 text-red-600 ml-auto">
              <Trash2 className="h-3 w-3" />
            </button>
          </>
        )}
        {finalizada && (
          <div className="text-[9px] text-green-700 flex items-center gap-1">
            <CheckCircle2 className="h-3 w-3" /> {jornada.ultima_ejecucion_avance ?? 100}% completada
          </div>
        )}
      </div>
    </div>
  )
}

function AsignarResponsableModal({ jornada, planId, onClose }: {
  jornada: TallerPlanOTFull
  planId: string
  onClose: () => void
}) {
  const toast = useToast()
  const { data: usuarios } = useUsuariosAsignablesTaller()
  const asignar = useAsignarResponsableTaller(planId)
  const [respId, setRespId] = useState(jornada.responsable_id ?? '')
  const [cuadrilla, setCuadrilla] = useState(jornada.cuadrilla ?? '')

  return (
    <Modal open={true} onClose={onClose} title={`Asignar responsable · ${jornada.ot_folio}`}>
      <div className="space-y-3">
        <div>
          <label className="text-xs font-medium">Responsable</label>
          <select value={respId} onChange={(e) => setRespId(e.target.value)}
                  className="w-full rounded border px-2 py-1.5 text-sm">
            <option value="">— Seleccionar —</option>
            {(usuarios ?? []).map((u) => (
              <option key={u.id} value={u.id}>{u.nombre_completo} {u.rol && `(${u.rol})`}</option>
            ))}
          </select>
        </div>
        <div>
          <label className="text-xs font-medium">Cuadrilla (opcional)</label>
          <Input value={cuadrilla} onChange={(e) => setCuadrilla(e.target.value)} placeholder="ej: Equipo A" />
        </div>
      </div>
      <ModalFooter>
        <Button variant="outline" onClick={onClose}>Cancelar</Button>
        <Button disabled={!respId || asignar.isPending}
                onClick={() => asignar.mutate({
                  planOtId: jornada.plan_ot_id, responsableId: respId, cuadrilla: cuadrilla.trim() || null,
                }, {
                  onSuccess: () => { toast.success('Responsable asignado'); onClose() },
                  onError: (err) => toast.error((err as Error).message),
                })}>
          {asignar.isPending ? <Spinner className="h-4 w-4 mr-1" /> : null}
          Asignar
        </Button>
      </ModalFooter>
    </Modal>
  )
}

// ── Tab Cobertura PM ────────────────────────────────────────────────────────
function CoberturaTab() {
  const toast = useToast()
  const { data: cobertura } = useCoberturaPm()
  const { data: sinPlan } = useActivosSinPlan()
  const sembrar = useAdminSembrarPlanesFaltantes()

  return (
    <div className="space-y-3">
      {cobertura && (
        <div className="grid grid-cols-2 md:grid-cols-4 gap-2">
          <KpiCard label="Activos totales" valor={cobertura.activos_totales} />
          <KpiCard label="Con plan PM" valor={cobertura.activos_con_plan} color="text-green-700" />
          <KpiCard label="SIN plan PM" valor={cobertura.activos_sin_plan}
                   color={cobertura.activos_sin_plan > 0 ? 'text-red-700' : 'text-green-700'} />
          <KpiCard label="Cobertura" valor={`${cobertura.cobertura_pct}%`} color="text-blue-700" />
        </div>
      )}

      <div className="flex items-center justify-between">
        <h3 className="text-base font-semibold">Activos descubiertos ({sinPlan?.length ?? 0})</h3>
        <Button size="sm" disabled={sembrar.isPending}
                onClick={() => sembrar.mutate(undefined, {
                  onSuccess: (d) => toast.success(`Sembrados ${d.planes_creados} planes en ${d.activos_revisados} activos`),
                  onError: (err) => toast.error((err as Error).message),
                })}>
          {sembrar.isPending ? <Spinner className="h-4 w-4 mr-1" /> : <RefreshCw className="h-4 w-4 mr-1" />}
          Sembrar planes faltantes
        </Button>
      </div>

      <Card>
        <CardContent className="p-0 overflow-x-auto">
          {!sinPlan || sinPlan.length === 0 ? (
            <div className="p-8 text-center text-sm text-green-700">
              <CheckCircle2 className="h-8 w-8 mx-auto mb-2" />
              ¡Excelente! Todos los activos vivos con modelo tienen sus planes preventivos.
            </div>
          ) : (
            <table className="w-full text-xs">
              <thead className="bg-gray-50">
                <tr>
                  <th className="px-2 py-2 text-left">Activo</th>
                  <th className="px-2 py-2 text-left">Modelo</th>
                  <th className="px-2 py-2 text-left">Faena</th>
                  <th className="px-2 py-2 text-left">Cliente</th>
                  <th className="px-2 py-2 text-right">Pautas dispon.</th>
                  <th className="px-2 py-2 text-right">Planes asign.</th>
                  <th className="px-2 py-2 text-right">Sin cubrir</th>
                </tr>
              </thead>
              <tbody>
                {sinPlan.map((a) => (
                  <tr key={a.activo_id} className="border-t hover:bg-amber-50">
                    <td className="px-2 py-1.5 font-mono">
                      {a.activo_codigo} {a.patente && `· ${a.patente}`}
                      <div className="text-[10px] text-gray-500 font-sans">{a.activo_nombre}</div>
                    </td>
                    <td className="px-2 py-1.5">{a.modelo_marca} {a.modelo_nombre}</td>
                    <td className="px-2 py-1.5">{a.faena_nombre ?? '—'}</td>
                    <td className="px-2 py-1.5">{a.contrato_cliente ?? '—'}</td>
                    <td className="px-2 py-1.5 text-right">{a.pautas_disponibles}</td>
                    <td className="px-2 py-1.5 text-right">{a.planes_asignados}</td>
                    <td className="px-2 py-1.5 text-right font-bold text-red-700">{a.pautas_sin_cubrir}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </CardContent>
      </Card>
    </div>
  )
}

// ── Tab Cumplimiento PM ─────────────────────────────────────────────────────
function CumplimientoTab() {
  const { data: cumpl } = useCumplimientoPmMesTaller()
  if (!cumpl) return <div className="flex justify-center py-10"><Spinner /></div>
  if (cumpl.length === 0) {
    return <div className="text-center text-sm text-gray-500 py-10">Sin datos de cumplimiento en los últimos 12 meses.</div>
  }
  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Cumplimiento PM mensual (últimos 12 meses)</CardTitle>
      </CardHeader>
      <CardContent className="p-0 overflow-x-auto">
        <table className="w-full text-sm">
          <thead className="bg-gray-50">
            <tr>
              <th className="px-3 py-2 text-left">Mes</th>
              <th className="px-3 py-2 text-right">PM Total</th>
              <th className="px-3 py-2 text-right">PM Completados</th>
              <th className="px-3 py-2 text-right">PM No ejecutados</th>
              <th className="px-3 py-2 text-right">Correctivos</th>
              <th className="px-3 py-2 text-right">Cumpl. %</th>
            </tr>
          </thead>
          <tbody>
            {cumpl.map((m) => (
              <tr key={m.mes} className="border-t">
                <td className="px-3 py-2 capitalize">
                  {new Date(m.mes + 'T12:00:00').toLocaleDateString('es-CL', { month: 'long', year: 'numeric' })}
                </td>
                <td className="px-3 py-2 text-right">{m.pm_total}</td>
                <td className="px-3 py-2 text-right text-green-700">{m.pm_completados}</td>
                <td className="px-3 py-2 text-right text-red-700">{m.pm_no_ejecutados}</td>
                <td className="px-3 py-2 text-right">{m.correctivos_total}</td>
                <td className="px-3 py-2 text-right font-bold">
                  <span className={m.cumplimiento_pm_pct >= 80 ? 'text-green-700' : m.cumplimiento_pm_pct >= 60 ? 'text-amber-700' : 'text-red-700'}>
                    {m.cumplimiento_pm_pct}%
                  </span>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </CardContent>
    </Card>
  )
}
