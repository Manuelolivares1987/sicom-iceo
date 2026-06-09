'use client'

import { useMemo, useState, useEffect } from 'react'
import Link from 'next/link'
import {
  DndContext, DragEndEvent, PointerSensor, useDraggable, useDroppable, useSensor, useSensors,
} from '@dnd-kit/core'
import {
  Calendar, ArrowLeft, ChevronLeft, ChevronRight, Lock, AlertTriangle, Trash2, User,
  Play, Pause, CheckCircle2, BarChart3, ShieldAlert, RefreshCw, Wrench, Layers, FileSpreadsheet,
  Truck, Mail,
} from 'lucide-react'
import { exportarPlanSemanalExcel, descargarBlob } from '@/lib/export/plan-semanal-excel'
import { buildPlanSemanalTallerEmailHtml } from '@/lib/email/plan-semanal-taller-email'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { Modal, ModalFooter } from '@/components/ui/modal'
import { Input } from '@/components/ui/input'
import { useToast } from '@/contexts/toast-context'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import {
  useGetOrCreatePlanSemanalTaller, useDiasPlanSemanalTaller, useJornadasPlanSemanalTaller,
  useKpiSemanalTaller, useCumplimientoPmMesTaller,
  useCoberturaPm, useActivosSinPlan,
  useAgregarJornadaTaller, useMoverJornadaTaller, useQuitarJornadaTaller,
  useAsignarResponsableTaller, useConfirmarPlanSemanalTaller,
  useIniciarEjecucionTaller, usePausarEjecucionTaller, useFinalizarEjecucionTaller,
  useAdminSembrarPlanesFaltantes,
} from '@/hooks/use-taller-plan-semanal'
import { lunesDeIso, type TallerPlanOTFull } from '@/lib/services/taller-plan-semanal'
import { getFlotaDashboard, type FlotaDashboardActivo } from '@/lib/services/flota-dashboard'
import {
  getPlanesActivo, getPreventivasDue, programarOtTaller, getEquiposPadre, getRtPorVencer,
  subirDocumentoRt, renovarRevisionTecnica, getRecepcionesPorPlanificar, programarRecepcion,
  type PlanActivo, type PreventivaDue, type TipoOtTaller, type PrioridadTaller, type RtPorVencer,
  type RecepcionPorPlanificar,
} from '@/lib/services/taller-planificacion'

type Tab = 'kanban' | 'cobertura' | 'cumplimiento'

// Estados de flota: M/F (y T) primero en el panel de patentes.
const ESTADO_INFO: Record<string, { label: string; cls: string }> = {
  M: { label: 'Mantención',     cls: 'bg-amber-100 text-amber-800' },
  F: { label: 'Fuera servicio', cls: 'bg-red-100 text-red-800' },
  T: { label: 'Taller',         cls: 'bg-orange-100 text-orange-800' },
  A: { label: 'Arrendado',      cls: 'bg-green-100 text-green-700' },
  C: { label: 'En contrato',    cls: 'bg-green-100 text-green-700' },
  D: { label: 'Disponible',     cls: 'bg-blue-100 text-blue-700' },
  R: { label: 'Tránsito',       cls: 'bg-cyan-100 text-cyan-700' },
  U: { label: 'Uso interno',    cls: 'bg-sky-100 text-sky-700' },
  L: { label: 'Leasing',        cls: 'bg-indigo-100 text-indigo-700' },
  V: { label: 'En venta',       cls: 'bg-purple-100 text-purple-700' },
  H: { label: 'Sin clasificar', cls: 'bg-gray-100 text-gray-600' },
}
const ORDEN_ESTADO: Record<string, number> = { M: 0, F: 1, T: 2 }
function ordenEstado(cod: string | null): number {
  return cod && cod in ORDEN_ESTADO ? ORDEN_ESTADO[cod] : 9
}

// Mecánicos del taller (hasta 2 por jornada). Se guardan en el campo `cuadrilla`.
const MECANICOS = ['Yusedl', 'Joel', 'Sergio', 'Marco', 'Felipe L', 'Felipe'] as const
const MAX_MECANICOS = 2

// Objetivo de drop pendiente: patente/preventiva soltada en un día.
type DropTarget = {
  activoId: string
  label: string          // patente · código
  fecha: string
  planIdPre: string | null
  tipoPre: TipoOtTaller
}

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

export default function PlanSemanalTallerPage() {
  useRequireAuth()
  const toast = useToast()

  const [semanaIso, setSemanaIso] = useState<string>(() => lunesDeIso(new Date()))
  const [planSemanalId, setPlanSemanalId] = useState<string>('')
  const [tab, setTab] = useState<Tab>('kanban')

  const getOrCreate = useGetOrCreatePlanSemanalTaller()
  const { data: dias } = useDiasPlanSemanalTaller(planSemanalId || null)
  const { data: jornadas, isLoading: loadJornadas } = useJornadasPlanSemanalTaller(planSemanalId || null)
  const { data: flota } = useQuery({ queryKey: ['flota-dashboard'], queryFn: getFlotaDashboard, staleTime: 60_000 })
  // Solo la flota real (55): tipo móvil, sin activo_padre_id, no dada de baja. Excluye auxiliares.
  const { data: fleet } = useQuery({ queryKey: ['equipos-padre'], queryFn: getEquiposPadre, staleTime: 60_000 })
  const { data: preventivas } = useQuery({ queryKey: ['preventivas-due', 15], queryFn: () => getPreventivasDue(15), staleTime: 60_000 })
  const { data: rtDue } = useQuery({ queryKey: ['rt-por-vencer', 30], queryFn: () => getRtPorVencer(30), staleTime: 60_000 })
  const { data: recepciones } = useQuery({ queryKey: ['recepciones-por-planificar'], queryFn: getRecepcionesPorPlanificar, staleTime: 60_000 })
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
  const [dropTarget, setDropTarget] = useState<DropTarget | null>(null)
  const [renovarRt, setRenovarRt] = useState<RtPorVencer | null>(null)
  const [recepTarget, setRecepTarget] = useState<{ activoId: string; label: string; fecha: string } | null>(null)
  const qc = useQueryClient()
  const [filtroPatente, setFiltroPatente] = useState('')

  // Solo las 55 patentes de la flota (excluye auxiliares y otros activos de la vista).
  const fleetIds = useMemo(() => new Set((fleet ?? []).map((e) => e.id)), [fleet])

  // Patentes ordenadas: Mantención y Fuera de servicio primero (luego Taller, luego resto).
  const patentesOrdenadas = useMemo(() => {
    const q = filtroPatente.trim().toLowerCase()
    return (flota ?? [])
      .filter((a) => fleetIds.has(a.activo_id))
      .filter((a) => !q || (a.patente ?? '').toLowerCase().includes(q) || a.activo_codigo.toLowerCase().includes(q) || a.activo_nombre.toLowerCase().includes(q))
      .slice()
      .sort((a, b) => {
        const da = ordenEstado(a.estado_codigo_hoy), db = ordenEstado(b.estado_codigo_hoy)
        if (da !== db) return da - db
        return (a.patente ?? a.activo_codigo).localeCompare(b.patente ?? b.activo_codigo)
      })
  }, [flota, fleetIds, filtroPatente])

  // Preventivas sugeridas: una por patente (la más vencida), solo flota real.
  const preventivasPatentes = useMemo(() => {
    const m = new Map<string, PreventivaDue>()
    for (const p of preventivas ?? []) {
      if (fleetIds.size > 0 && !fleetIds.has(p.activo_id)) continue
      const prev = m.get(p.activo_id)
      if (!prev || p.dias_vencido > prev.dias_vencido) m.set(p.activo_id, p)
    }
    return Array.from(m.values()).sort((a, b) => b.dias_vencido - a.dias_vencido)
  }, [preventivas, fleetIds])

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

  // Drag & drop
  const sensors = useSensors(useSensor(PointerSensor, { activationConstraint: { distance: 5 } }))

  const handleDragEnd = (e: DragEndEvent) => {
    const aOver = e.over?.id?.toString()
    const aActive = e.active?.id?.toString()
    if (!aOver || !aActive || !aOver.startsWith('dia:')) return
    const fechaDestino = aOver.replace('dia:', '')

    if (aActive.startsWith('patente:')) {
      // patente:<activoId> -> abrir diálogo para elegir tipo + pauta (actividades)
      const activoId = aActive.replace('patente:', '')
      const a = (flota ?? []).find((x) => x.activo_id === activoId)
      if (!a) return
      setDropTarget({
        activoId,
        label: a.patente ? `${a.patente} · ${a.activo_codigo}` : a.activo_codigo,
        fecha: fechaDestino,
        planIdPre: null,
        tipoPre: 'preventivo',
      })
    } else if (aActive.startsWith('preventiva:')) {
      // preventiva:<activoId>:<planId> -> diálogo con la pauta vencida preseleccionada
      const [, activoId, planId] = aActive.split(':')
      const p = (preventivas ?? []).find((x) => x.activo_id === activoId && x.plan_id === planId)
      setDropTarget({
        activoId,
        label: p ? `${p.patente} · ${p.pauta_nombre ?? 'PM'}` : activoId,
        fecha: fechaDestino,
        planIdPre: planId,
        tipoPre: 'preventivo',
      })
    } else if (aActive.startsWith('recepcion:')) {
      // recepcion:<activoId> -> al soltar en un día se crea la OT de inspección de recepción
      const activoId = aActive.replace('recepcion:', '')
      const r = (recepciones ?? []).find((x) => x.activo_id === activoId)
      setRecepTarget({ activoId, label: r ? `${r.patente ?? r.codigo}` : activoId, fecha: fechaDestino })
    } else if (aActive.startsWith('jornada:')) {
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
              Arrastra una patente a un día y elige las actividades (pauta). Drag &amp; drop entre días.
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
            variant="outline"
            size="sm"
            disabled={!jornadas || jornadas.length === 0}
            onClick={async () => {
              try {
                const blob = await exportarPlanSemanalExcel({
                  titulo: 'Plan semanal del taller',
                  fechaInicio: semanaIso,
                  fechaFin: dias?.[6]?.fecha ?? semanaIso,
                  jornadas: (jornadas ?? []).map((j) => ({
                    fecha: j.dia_fecha,
                    dia_nombre: j.dia_nombre,
                    folio: j.ot_folio,
                    tipo: j.ot_tipo,
                    prioridad: j.ot_prioridad,
                    activo: j.activo_codigo ? `${j.activo_codigo}${j.activo_patente ? ' · ' + j.activo_patente : ''}` : null,
                    pm_nombre: j.pm_nombre,
                    responsable: j.responsable,
                    cuadrilla: j.cuadrilla,
                    horas_planificadas: j.horas_planificadas,
                    avance_objetivo: j.avance_objetivo_pct,
                    secuencia_jornada: j.secuencia_jornada,
                    estado_jornada: j.jornada_estado,
                    estado_ot: j.ot_estado,
                    avance_final: j.ultima_ejecucion_avance,
                    faena: j.faena_nombre,
                    cliente: j.contrato_cliente,
                    observaciones: j.observaciones,
                  })),
                  resumen: kpi ? {
                    jornadas_planificadas: kpi.jornadas_planificadas,
                    jornadas_finalizadas: kpi.jornadas_finalizadas,
                    jornadas_en_ejecucion: kpi.jornadas_en_ejecucion,
                    jornadas_pendientes: kpi.jornadas_pendientes,
                    jornadas_atrasadas: kpi.jornadas_atrasadas,
                    cumplimiento_pct: kpi.cumplimiento_pct,
                    horas_planificadas: kpi.horas_planificadas,
                    horas_reales: kpi.horas_reales,
                  } : null,
                  scopeNombre: 'Taller (global)',
                })
                descargarBlob(blob, `plan_taller_${semanaIso}.xlsx`)
                toast.success('Plan exportado')
              } catch (err) {
                toast.error((err as Error).message)
              }
            }}
          >
            <FileSpreadsheet className="h-4 w-4 mr-1" /> Excel
          </Button>
          <Button
            variant="outline"
            size="sm"
            disabled={!jornadas || jornadas.length === 0}
            onClick={async () => {
              const html = buildPlanSemanalTallerEmailHtml({
                dias: dias ?? [],
                jornadas: jornadas ?? [],
                kpi: kpi ?? null,
                semanaInicio: semanaIso,
                semanaFin: dias?.[6]?.fecha ?? semanaIso,
                faena: jornadas?.[0]?.faena_nombre ?? null,
                link: `${window.location.origin}/dashboard/mantenimiento/plan-semanal-taller`,
              })
              try {
                await navigator.clipboard.write([new ClipboardItem({
                  'text/html': new Blob([html], { type: 'text/html' }),
                  'text/plain': new Blob([`Plan Semanal de Taller — ${semanaIso}`], { type: 'text/plain' }),
                })])
                toast.success('Copiado ✓ — pega en Outlook/Gmail (Ctrl+V)')
              } catch {
                const w = window.open('', '_blank')
                if (w) { w.document.write(html); w.document.close() }
                toast.success('Se abrió en otra pestaña: Ctrl+A → Ctrl+C → pega en el correo')
              }
            }}
          >
            <Mail className="h-4 w-4 mr-1" /> Copiar para correo
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
            {/* Patentes izq */}
            <PatentesPanel
              items={patentesOrdenadas}
              total={fleet?.length ?? 0}
              filtro={filtroPatente}
              onFiltro={setFiltroPatente}
            />

            {/* Días + preventivas sugeridas */}
            <div className="space-y-3">
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

              {/* Recepción por planificar (marcadas 'R' en Sugerencias de estado) */}
              <RecepcionPorPlanificarCard items={recepciones ?? []} />

              {/* Preventivas sugeridas (arrástralas a un día) */}
              <PreventivasSugeridas items={preventivasPatentes} />

              {/* Revisión Técnica por vencer (arrástralas a un día → inspección) */}
              <RtPorVencerCard items={rtDue ?? []} onRenovar={setRenovarRt} />
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

      {/* Diálogo: programar patente en el día (elige tipo + pauta) */}
      {dropTarget && (
        <ProgramarOtDialog
          target={dropTarget}
          planSemanalId={planSemanalId}
          dias={(dias ?? []).map((d) => ({ fecha: d.fecha, nombre: d.nombre_dia }))}
          onClose={() => setDropTarget(null)}
          onDone={() => { setDropTarget(null) }}
          agregarJornada={agregarJornada}
        />
      )}

      {/* Diálogo: renovar Revisión Técnica (subir doc + nuevo vencimiento) */}
      {renovarRt && (
        <RenovarRtDialog
          rt={renovarRt}
          onClose={() => setRenovarRt(null)}
          onDone={() => { setRenovarRt(null); qc.invalidateQueries({ queryKey: ['rt-por-vencer'] }) }}
        />
      )}

      {/* Diálogo: planificar inspección de recepción (asigna grupo + día) */}
      {recepTarget && (
        <RecepcionDialog
          target={recepTarget}
          planSemanalId={planSemanalId}
          dias={(dias ?? []).map((d) => ({ fecha: d.fecha, nombre: d.nombre_dia }))}
          agregarJornada={agregarJornada}
          onClose={() => setRecepTarget(null)}
          onDone={() => {
            setRecepTarget(null)
            qc.invalidateQueries({ queryKey: ['recepciones-por-planificar'] })
          }}
        />
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

function PatentesPanel({ items, total, filtro, onFiltro }: {
  items: FlotaDashboardActivo[]
  total: number
  filtro: string
  onFiltro: (v: string) => void
}) {
  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-sm flex items-center gap-2">
          <Truck className="h-4 w-4" /> Patentes ({items.length}/{total})
        </CardTitle>
      </CardHeader>
      <CardContent className="p-2 space-y-2">
        <Input value={filtro} onChange={(e) => onFiltro(e.target.value)}
               placeholder="Buscar patente / código…" className="h-8 text-xs" />
        <div className="text-[10px] text-gray-400">Mantención y fuera de servicio primero. Arrastra a un día →</div>
        <div className="max-h-[64vh] overflow-y-auto space-y-1.5">
          {items.length === 0 ? (
            <div className="text-xs text-gray-400 p-4 text-center">Sin patentes</div>
          ) : (
            items.map((a) => <PatenteCard key={a.activo_id} a={a} />)
          )}
        </div>
      </CardContent>
    </Card>
  )
}

function PatenteCard({ a }: { a: FlotaDashboardActivo }) {
  const { attributes, listeners, setNodeRef, transform, isDragging } = useDraggable({ id: `patente:${a.activo_id}` })
  const style = transform
    ? { transform: `translate3d(${transform.x}px,${transform.y}px,0)`, opacity: isDragging ? 0.5 : 1 }
    : undefined
  const est = a.estado_codigo_hoy ? ESTADO_INFO[a.estado_codigo_hoy] : undefined

  return (
    <div ref={setNodeRef} style={style} {...listeners} {...attributes}
         className="rounded border bg-white p-2 cursor-grab active:cursor-grabbing hover:border-blue-400 shadow-sm">
      <div className="flex items-center justify-between gap-1">
        <span className="text-[11px] font-mono font-bold">{a.patente ?? a.activo_codigo}</span>
        {est && <span className={`text-[8px] px-1 py-0.5 rounded font-bold ${est.cls}`}>{est.label}</span>}
      </div>
      <div className="text-[10px] text-gray-500 truncate">{a.activo_codigo} · {a.activo_nombre}</div>
      {a.pm_status === 'vencido' && (
        <div className="text-[9px] text-red-600 mt-0.5 font-semibold">PM vencido</div>
      )}
    </div>
  )
}

function PreventivasSugeridas({ items }: { items: PreventivaDue[] }) {
  return (
    <Card className="border-amber-200">
      <CardHeader className="pb-2">
        <CardTitle className="text-sm flex items-center gap-2 text-amber-800">
          <ShieldAlert className="h-4 w-4" /> Preventivas sugeridas ({items.length})
          <span className="text-[10px] font-normal text-gray-400">— vencidas o próximas (15 días). Arrástralas a un día.</span>
        </CardTitle>
      </CardHeader>
      <CardContent className="p-2">
        {items.length === 0 ? (
          <div className="text-xs text-gray-400 p-3 text-center">Sin preventivas vencidas ni próximas.</div>
        ) : (
          <div className="flex gap-2 overflow-x-auto pb-1">
            {items.map((p) => <PreventivaCard key={`${p.activo_id}:${p.plan_id}`} p={p} />)}
          </div>
        )}
      </CardContent>
    </Card>
  )
}

function PreventivaCard({ p }: { p: PreventivaDue }) {
  const { attributes, listeners, setNodeRef, transform, isDragging } = useDraggable({
    id: `preventiva:${p.activo_id}:${p.plan_id}`,
  })
  const style = transform
    ? { transform: `translate3d(${transform.x}px,${transform.y}px,0)`, opacity: isDragging ? 0.5 : 1 }
    : undefined
  const vencida = p.dias_vencido > 0

  return (
    <div ref={setNodeRef} style={style} {...listeners} {...attributes}
         title={vencida ? `Vencida ${p.dias_vencido}d` : `Vence en ${Math.abs(p.dias_vencido)}d`}
         className={`rounded border px-2.5 py-1.5 cursor-grab active:cursor-grabbing shadow-sm font-mono text-[12px] font-bold ${
           vencida ? 'border-red-300 bg-red-50 text-red-800' : 'border-amber-200 bg-amber-50 text-amber-800'
         }`}>
      {p.patente}
    </div>
  )
}

function RecepcionPorPlanificarCard({ items }: { items: RecepcionPorPlanificar[] }) {
  return (
    <Card className="border-cyan-200">
      <CardHeader className="pb-2">
        <CardTitle className="text-sm flex items-center gap-2 text-cyan-800">
          <Truck className="h-4 w-4" /> Recepción por planificar ({items.length})
          <span className="text-[10px] font-normal text-gray-400">— marcadas «R» en Sugerencias. Arrástrala a un día → crea la inspección de recepción.</span>
        </CardTitle>
      </CardHeader>
      <CardContent className="p-2">
        {items.length === 0 ? (
          <div className="text-xs text-gray-400 p-3 text-center">Sin recepciones marcadas.</div>
        ) : (
          <div className="flex gap-2 overflow-x-auto pb-1">
            {items.map((r) => <RecepcionCard key={r.activo_id} r={r} />)}
          </div>
        )}
      </CardContent>
    </Card>
  )
}

function RecepcionCard({ r }: { r: RecepcionPorPlanificar }) {
  const { attributes, listeners, setNodeRef, transform, isDragging } = useDraggable({ id: `recepcion:${r.activo_id}` })
  const style = transform
    ? { transform: `translate3d(${transform.x}px,${transform.y}px,0)`, opacity: isDragging ? 0.5 : 1 }
    : undefined
  return (
    <div ref={setNodeRef} style={style} {...listeners} {...attributes}
         title={`Recepción marcada ${r.fecha_recepcion ?? ''}`}
         className="shrink-0 rounded border border-cyan-300 bg-cyan-50 text-cyan-800 px-2.5 py-1.5 cursor-grab active:cursor-grabbing shadow-sm text-[12px] font-bold text-center font-mono">
      {r.patente ?? r.codigo}
    </div>
  )
}

function RecepcionDialog({ target, planSemanalId, dias, agregarJornada, onClose, onDone }: {
  target: { activoId: string; label: string; fecha: string }
  planSemanalId: string
  dias: { fecha: string; nombre: string }[]
  agregarJornada: ReturnType<typeof useAgregarJornadaTaller>
  onClose: () => void
  onDone: () => void
}) {
  const toast = useToast()
  const [mecanicos, setMecanicos] = useState<string[]>([])
  const [fechasSel, setFechasSel] = useState<Set<string>>(new Set([target.fecha]))
  const [enviando, setEnviando] = useState(false)
  const toggleDia = (f: string) => setFechasSel((prev) => { const n = new Set(prev); n.has(f) ? n.delete(f) : n.add(f); return n })

  const submit = async () => {
    if (fechasSel.size === 0) return
    setEnviando(true)
    try {
      const fechas = Array.from(fechasSel).sort()
      const cuadrilla = mecanicos.length ? mecanicos.join(', ') : null
      const { ot_id } = await programarRecepcion(target.activoId)
      for (const f of fechas) await agregarJornada.mutateAsync({ planSemanalId, otId: ot_id, fecha: f, cuadrilla })
      toast.success(`Recepción de ${target.label} planificada (${fechas.length} día${fechas.length > 1 ? 's' : ''})`)
      onDone()
    } catch (e) {
      toast.error(e instanceof Error ? e.message : 'Error al planificar recepción')
    } finally { setEnviando(false) }
  }

  return (
    <Modal open onClose={onClose} title={`Planificar recepción · ${target.label}`}>
      <div className="space-y-3">
        <p className="text-xs text-gray-500">Se crea la OT de inspección de recepción (checklist profundo) y se asigna al grupo en el/los día(s) elegidos.</p>
        <div>
          <label className="text-xs font-medium">Días (puede ser más de uno)</label>
          <div className="mt-1 grid grid-cols-4 gap-1">
            {dias.map((d) => {
              const on = fechasSel.has(d.fecha)
              return (
                <button key={d.fecha} type="button" onClick={() => toggleDia(d.fecha)}
                        className={`rounded border px-1.5 py-1 text-[11px] capitalize ${on ? 'border-cyan-500 bg-cyan-500 text-white' : 'border-gray-200 bg-white text-gray-600 hover:bg-cyan-50'}`}>
                  {d.nombre.slice(0, 3)} {fmtFecha(d.fecha)}
                </button>
              )
            })}
          </div>
        </div>
        <div>
          <label className="text-xs font-medium">Grupo de trabajo (hasta {MAX_MECANICOS})</label>
          <div className="mt-1 flex flex-wrap gap-1">
            {MECANICOS.map((m) => {
              const on = mecanicos.includes(m)
              return (
                <button key={m} type="button"
                        onClick={() => setMecanicos((prev) => on ? prev.filter((x) => x !== m) : prev.length < MAX_MECANICOS ? [...prev, m] : prev)}
                        className={`rounded border px-2 py-1 text-[11px] ${on ? 'border-blue-500 bg-blue-500 text-white' : 'border-gray-200 bg-white text-gray-600'}`}>
                  {m}
                </button>
              )
            })}
          </div>
        </div>
      </div>
      <ModalFooter>
        <Button variant="outline" onClick={onClose} disabled={enviando}>Cancelar</Button>
        <Button onClick={submit} disabled={enviando}>{enviando ? 'Creando…' : 'Planificar recepción'}</Button>
      </ModalFooter>
    </Modal>
  )
}

function RtPorVencerCard({ items, onRenovar }: { items: RtPorVencer[]; onRenovar: (r: RtPorVencer) => void }) {
  return (
    <Card className="border-purple-200">
      <CardHeader className="pb-2">
        <CardTitle className="text-sm flex items-center gap-2 text-purple-800">
          <ShieldAlert className="h-4 w-4" /> Revisión Técnica por vencer ({items.length})
          <span className="text-[10px] font-normal text-gray-400">— pulsa «Renovar RT» para subir el documento nuevo y el nuevo vencimiento.</span>
        </CardTitle>
      </CardHeader>
      <CardContent className="p-2">
        {items.length === 0 ? (
          <div className="text-xs text-gray-400 p-3 text-center">Sin RT vencidas ni próximas.</div>
        ) : (
          <div className="flex gap-2 overflow-x-auto pb-1">
            {items.map((r) => <RtCard key={r.activo_id} r={r} onRenovar={onRenovar} />)}
          </div>
        )}
      </CardContent>
    </Card>
  )
}

function RtCard({ r, onRenovar }: { r: RtPorVencer; onRenovar: (r: RtPorVencer) => void }) {
  const vencida = r.dias_restantes < 0
  return (
    <div className="shrink-0 flex flex-col gap-1 items-stretch w-[120px]">
      <div title={vencida ? `RT vencida hace ${Math.abs(r.dias_restantes)}d (venció ${r.fecha_vencimiento})` : `RT vence en ${r.dias_restantes}d (${r.fecha_vencimiento})`}
           className={`rounded border px-2.5 py-1.5 shadow-sm text-[12px] font-bold text-center ${
             vencida ? 'border-red-300 bg-red-50 text-red-800' : 'border-purple-200 bg-purple-50 text-purple-800'
           }`}>
        <div className="font-mono">{r.patente ?? r.codigo}</div>
        <div className="text-[10px] font-normal">{vencida ? `vencida ${Math.abs(r.dias_restantes)}d` : `en ${r.dias_restantes}d`}</div>
      </div>
      <button type="button" onClick={() => onRenovar(r)}
        className="text-[11px] text-white bg-purple-600 hover:bg-purple-700 rounded px-2 py-1 font-medium">📄 Renovar RT</button>
    </div>
  )
}

function RenovarRtDialog({ rt, onClose, onDone }: { rt: RtPorVencer; onClose: () => void; onDone: () => void }) {
  const toast = useToast()
  const [file, setFile] = useState<File | null>(null)
  const [emision, setEmision] = useState<string>(() => new Date().toISOString().slice(0, 10))
  const [venc, setVenc] = useState<string>('')
  const [numero, setNumero] = useState('')
  const [saving, setSaving] = useState(false)

  const submit = async () => {
    if (!venc) { toast.error('Indica el nuevo vencimiento de la RT'); return }
    if (venc < emision) { toast.error('El vencimiento no puede ser anterior a la emisión'); return }
    setSaving(true)
    try {
      let url: string | null = null
      if (file) url = await subirDocumentoRt(rt.activo_id, file)
      await renovarRevisionTecnica({
        activoId: rt.activo_id, fechaEmision: emision, fechaVencimiento: venc,
        archivoUrl: url, numero: numero || null,
      })
      toast.success(`RT renovada: ${rt.patente ?? rt.codigo} vence ${venc}`)
      onDone()
    } catch (e) {
      toast.error(e instanceof Error ? e.message : 'Error al renovar la RT')
    } finally { setSaving(false) }
  }

  return (
    <Modal open onClose={onClose} title={`Renovar Revisión Técnica · ${rt.patente ?? rt.codigo}`}>
      <div className="space-y-3">
        <p className="text-xs text-gray-500">
          RT actual {rt.dias_restantes < 0 ? `vencida hace ${Math.abs(rt.dias_restantes)} días` : `vence en ${rt.dias_restantes} días`} ({rt.fecha_vencimiento}).
        </p>
        <div>
          <label className="text-xs font-medium">Documento de la nueva RT (PDF/imagen)</label>
          <input type="file" accept="application/pdf,image/*"
            onChange={(e) => setFile(e.target.files?.[0] ?? null)}
            className="w-full rounded border px-2 py-1.5 text-sm" />
          {file && <p className="text-[10px] text-green-600 mt-0.5">✓ {file.name}</p>}
        </div>
        <div className="grid grid-cols-2 gap-2">
          <label className="text-xs font-medium">Fecha de emisión
            <input type="date" value={emision} onChange={(e) => setEmision(e.target.value)}
              className="mt-0.5 w-full rounded border px-2 py-1.5 text-sm" />
          </label>
          <label className="text-xs font-medium">Nuevo vencimiento*
            <input type="date" value={venc} onChange={(e) => setVenc(e.target.value)}
              className="mt-0.5 w-full rounded border px-2 py-1.5 text-sm" />
          </label>
        </div>
        <label className="text-xs font-medium block">N° certificado (opcional)
          <input value={numero} onChange={(e) => setNumero(e.target.value)}
            className="mt-0.5 w-full rounded border px-2 py-1.5 text-sm" />
        </label>
      </div>
      <ModalFooter>
        <Button variant="outline" onClick={onClose} disabled={saving}>Cancelar</Button>
        <Button onClick={submit} disabled={saving}>{saving ? 'Guardando…' : 'Registrar RT renovada'}</Button>
      </ModalFooter>
    </Modal>
  )
}

function ProgramarOtDialog({ target, planSemanalId, dias, onClose, onDone, agregarJornada }: {
  target: DropTarget
  planSemanalId: string
  dias: { fecha: string; nombre: string }[]
  onClose: () => void
  onDone: () => void
  agregarJornada: ReturnType<typeof useAgregarJornadaTaller>
}) {
  const toast = useToast()
  const { data: planes } = useQuery({
    queryKey: ['planes-activo', target.activoId],
    queryFn: () => getPlanesActivo(target.activoId),
  })
  const [tipo, setTipo] = useState<TipoOtTaller>(target.tipoPre)
  const [planId, setPlanId] = useState<string>(target.planIdPre ?? '')
  const [prioridad, setPrioridad] = useState<PrioridadTaller>('normal')
  const [mecanicos, setMecanicos] = useState<string[]>([])
  // Un equipo se puede programar para VARIOS días (multidía): el día soltado viene marcado.
  const [fechasSel, setFechasSel] = useState<Set<string>>(new Set([target.fecha]))
  const [enviando, setEnviando] = useState(false)

  // Preseleccionar la primera pauta cuando cargan los planes (si no vino preset).
  useEffect(() => {
    if (!target.planIdPre && tipo === 'preventivo' && !planId && planes && planes.length > 0) {
      setPlanId(planes[0].id)
    }
  /* eslint-disable-next-line react-hooks/exhaustive-deps */
  }, [planes])

  const toggleDia = (f: string) => setFechasSel((prev) => {
    const next = new Set(prev)
    if (next.has(f)) next.delete(f); else next.add(f)
    return next
  })

  const submit = async () => {
    if (fechasSel.size === 0) return
    setEnviando(true)
    try {
      const fechas = Array.from(fechasSel).sort()
      const cuadrilla = mecanicos.length ? mecanicos.join(', ') : null
      // Una sola OT (con su checklist desde la pauta); se agrega como jornada en cada día.
      const r = await programarOtTaller({
        activoId: target.activoId, tipo, prioridad, fecha: fechas[0],
        responsableId: null,
        planId: tipo === 'preventivo' ? (planId || null) : null,
      })
      for (const f of fechas) {
        await agregarJornada.mutateAsync({ planSemanalId, otId: r.id, fecha: f, cuadrilla })
      }
      toast.success(`OT ${r.folio} programada (${fechas.length} día${fechas.length > 1 ? 's' : ''})`)
      onDone()
    } catch (e) {
      toast.error((e as Error).message)
    } finally {
      setEnviando(false)
    }
  }

  return (
    <Modal open onClose={onClose} title={`Programar · ${target.label}`}>
      <div className="space-y-3">
        <div>
          <label className="text-xs font-medium">Tipo de trabajo</label>
          <select value={tipo} onChange={(e) => setTipo(e.target.value as TipoOtTaller)}
                  className="w-full rounded border px-2 py-1.5 text-sm">
            <option value="preventivo">Preventivo (actividades desde pauta)</option>
            <option value="correctivo">Correctivo</option>
            <option value="inspeccion">Inspección</option>
          </select>
        </div>

        {tipo === 'preventivo' && (
          <div>
            <label className="text-xs font-medium">Pauta / actividades</label>
            <select value={planId} onChange={(e) => setPlanId(e.target.value)}
                    className="w-full rounded border px-2 py-1.5 text-sm">
              <option value="">— Sin pauta (checklist genérico) —</option>
              {(planes ?? []).map((pl: PlanActivo) => (
                <option key={pl.id} value={pl.id}>
                  {pl.pauta_nombre ?? pl.nombre ?? 'Pauta'}{pl.duracion_estimada_hrs ? ` (${pl.duracion_estimada_hrs}h)` : ''}
                </option>
              ))}
            </select>
            {planes && planes.length === 0 && (
              <p className="text-[10px] text-amber-600 mt-1">Este equipo no tiene pautas cargadas; se usará el checklist genérico del tipo de OT.</p>
            )}
          </div>
        )}

        {/* Días (multidía) */}
        <div>
          <label className="text-xs font-medium">Días (puede ser más de uno)</label>
          <div className="mt-1 grid grid-cols-4 gap-1">
            {dias.map((d) => {
              const on = fechasSel.has(d.fecha)
              return (
                <button key={d.fecha} type="button" onClick={() => toggleDia(d.fecha)}
                        className={`rounded border px-1.5 py-1 text-[11px] capitalize transition-colors ${
                          on ? 'border-blue-500 bg-blue-500 text-white' : 'border-gray-200 bg-white text-gray-600 hover:bg-blue-50'
                        }`}>
                  {d.nombre.slice(0, 3)} {fmtFecha(d.fecha)}
                </button>
              )
            })}
          </div>
        </div>

        {/* Mecánicos a cargo (hasta 2) */}
        <div>
          <label className="text-xs font-medium">Mecánicos a cargo (hasta {MAX_MECANICOS})</label>
          <MecanicosPicker value={mecanicos} onChange={setMecanicos} />
        </div>

        <div>
          <label className="text-xs font-medium">Prioridad</label>
          <select value={prioridad} onChange={(e) => setPrioridad(e.target.value as PrioridadTaller)}
                  className="w-full rounded border px-2 py-1.5 text-sm">
            <option value="emergencia">Emergencia</option>
            <option value="alta">Alta</option>
            <option value="normal">Normal</option>
            <option value="baja">Baja</option>
          </select>
        </div>
      </div>
      <ModalFooter>
        <Button variant="outline" onClick={onClose}>Cancelar</Button>
        <Button disabled={enviando || fechasSel.size === 0} onClick={submit}>
          {enviando ? <Spinner className="h-4 w-4 mr-1" /> : null}
          Programar
        </Button>
      </ModalFooter>
    </Modal>
  )
}

// Selector de mecánicos (hasta 2). Devuelve nombres; se guardan en `cuadrilla`.
function MecanicosPicker({ value, onChange }: { value: string[]; onChange: (v: string[]) => void }) {
  const toggle = (m: string) => {
    if (value.includes(m)) onChange(value.filter((x) => x !== m))
    else if (value.length < MAX_MECANICOS) onChange([...value, m])
  }
  return (
    <div className="mt-1 flex flex-wrap gap-1">
      {MECANICOS.map((m) => {
        const on = value.includes(m)
        const bloqueado = !on && value.length >= MAX_MECANICOS
        return (
          <button key={m} type="button" onClick={() => toggle(m)} disabled={bloqueado}
                  className={`rounded-full border px-2.5 py-1 text-xs transition-colors ${
                    on ? 'border-blue-500 bg-blue-500 text-white'
                       : bloqueado ? 'border-gray-100 bg-gray-50 text-gray-300 cursor-not-allowed'
                       : 'border-gray-200 bg-white text-gray-700 hover:bg-blue-50'
                  }`}>
            {m}
          </button>
        )
      })}
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
          <span className="text-[10px] text-gray-600 truncate">
            {jornada.cuadrilla ?? jornada.responsable ?? 'Sin asignar'}
          </span>
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
  const asignar = useAsignarResponsableTaller(planId)
  // Mecánicos iniciales a partir de la cuadrilla guardada.
  const inicial = (jornada.cuadrilla ?? '')
    .split(',').map((s) => s.trim())
    .filter((s) => (MECANICOS as readonly string[]).includes(s))
    .slice(0, MAX_MECANICOS)
  const [mecanicos, setMecanicos] = useState<string[]>(inicial)

  return (
    <Modal open={true} onClose={onClose} title={`Mecánicos a cargo · ${jornada.ot_folio}`}>
      <div className="space-y-3">
        <div>
          <label className="text-xs font-medium">Mecánicos a cargo (hasta {MAX_MECANICOS})</label>
          <MecanicosPicker value={mecanicos} onChange={setMecanicos} />
        </div>
      </div>
      <ModalFooter>
        <Button variant="outline" onClick={onClose}>Cancelar</Button>
        <Button disabled={asignar.isPending}
                onClick={() => asignar.mutate({
                  planOtId: jornada.plan_ot_id, responsableId: null, cuadrilla: mecanicos.join(', '),
                }, {
                  onSuccess: () => { toast.success('Mecánicos asignados'); onClose() },
                  onError: (err) => toast.error((err as Error).message),
                })}>
          {asignar.isPending ? <Spinner className="h-4 w-4 mr-1" /> : null}
          Guardar
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
