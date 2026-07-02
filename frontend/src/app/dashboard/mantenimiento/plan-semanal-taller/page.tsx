'use client'

import { useMemo, useState, useEffect } from 'react'
import Link from 'next/link'
import {
  DndContext, DragEndEvent, PointerSensor, useDraggable, useDroppable, useSensor, useSensors,
} from '@dnd-kit/core'
import {
  Calendar, ArrowLeft, ChevronLeft, ChevronRight, Lock, AlertTriangle, Trash2, User,
  Play, Pause, CheckCircle2, BarChart3, ShieldAlert, RefreshCw, Wrench, Layers, FileSpreadsheet,
  Truck, Mail, Pencil, Plus, Clock, Camera, ExternalLink, ListChecks, Upload,
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
  useEditarJornadaTaller, useUsuariosAsignablesTaller,
  useChecklistV3Taller, useV3SetTiempoTaller, useV3SetExcluidoTaller,
  useV3AgregarItemTaller, useV3EliminarCustomTaller,
  useTallerTecnicos, useAgregarTareaLibreTaller,
  useCrearTecnico, useDesactivarTecnico,
} from '@/hooks/use-taller-plan-semanal'
import {
  lunesDeIso, getJornadaEventos,
  CATEGORIA_TAREA_LABEL, CATEGORIAS_TAREA_LIBRE,
  type TallerPlanOTFull, type ChecklistV3Item, type TallerJornadaEvento,
  type TallerTecnico, type CategoriaTareaTaller,
} from '@/lib/services/taller-plan-semanal'
import { getFlotaDashboard, type FlotaDashboardActivo } from '@/lib/services/flota-dashboard'
import {
  getPlanesActivo, getPreventivasDue, programarOtTaller, getEquiposPadre, getRtPorVencer,
  subirDocumentoRt, renovarRevisionTecnica, getRecepcionesPorPlanificar, programarRecepcion,
  getNcOtsPorAgendar,
  getDocumentosPorVencer, subirDocumentoCert, renovarCertificacion, TIPO_DOC_LABEL,
  type PlanActivo, type PreventivaDue, type TipoOtTaller, type PrioridadTaller, type RtPorVencer,
  type RecepcionPorPlanificar, type NcOtPorAgendar, type DocumentoPorVencer,
} from '@/lib/services/taller-planificacion'
import { MAX_MECANICOS } from '@/lib/taller-grupos'

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

// Mecánicos del taller (fuente única en lib/taller-grupos). Se guardan en `cuadrilla`.

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

function colorTipo(tipo: string | null): string {
  switch (tipo) {
    case 'preventivo':  return 'bg-blue-100 text-blue-800 border-blue-300'
    case 'correctivo':  return 'bg-red-100 text-red-800 border-red-300'
    case 'inspeccion':  return 'bg-amber-100 text-amber-800 border-amber-300'
    case 'lubricacion': return 'bg-purple-100 text-purple-800 border-purple-300'
    default:            return 'bg-gray-100 text-gray-800 border-gray-300'
  }
}

// Color/etiqueta corta por categoría de tarea (MIG182).
function colorCategoria(cat: CategoriaTareaTaller | null): string {
  switch (cat) {
    case 'soldadura':          return 'bg-orange-100 text-orange-800 border-orange-300'
    case 'equipo_externo':     return 'bg-teal-100 text-teal-800 border-teal-300'
    case 'asistencia_terreno': return 'bg-cyan-100 text-cyan-800 border-cyan-300'
    case 'calibracion':        return 'bg-indigo-100 text-indigo-800 border-indigo-300'
    case 'preventiva':         return 'bg-blue-100 text-blue-800 border-blue-300'
    default:                   return 'bg-gray-100 text-gray-700 border-gray-300'
  }
}
const CATEGORIA_CORTA: Record<string, string> = {
  preventiva: 'PREV', calibracion: 'CALIB', equipo_flota: 'FLOTA',
  asistencia_terreno: 'TERRENO', equipo_externo: 'EXTERNO', soldadura: 'SOLD.',
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
  const { data: docsDue } = useQuery({ queryKey: ['documentos-por-vencer', 30], queryFn: () => getDocumentosPorVencer(30), staleTime: 60_000 })
  const { data: recepciones } = useQuery({ queryKey: ['recepciones-por-planificar'], queryFn: getRecepcionesPorPlanificar, staleTime: 60_000 })
  const { data: ncOts } = useQuery({ queryKey: ['nc-ot-por-agendar'], queryFn: getNcOtsPorAgendar, staleTime: 60_000 })
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
  const [detalleOpen, setDetalleOpen] = useState<TallerPlanOTFull | null>(null)
  const [finalizarOpen, setFinalizarOpen] = useState<TallerPlanOTFull | null>(null)
  const [finAvance, setFinAvance] = useState<number>(100)
  const [finObs, setFinObs] = useState<string>('')
  const [dropTarget, setDropTarget] = useState<DropTarget | null>(null)
  const [renovarRt, setRenovarRt] = useState<RtPorVencer | null>(null)
  const [renovarDoc, setRenovarDoc] = useState<DocumentoPorVencer | null>(null)
  const [recepTarget, setRecepTarget] = useState<{ activoId: string; label: string; fecha: string } | null>(null)
  // Control de cambios: reprogramación de jornada en plan confirmado exige motivo.
  const [reprogTarget, setReprogTarget] = useState<{ planOtId: string; fechaDestino: string; label: string; diaActual: string } | null>(null)
  const [reprogMotivo, setReprogMotivo] = useState('')
  const qc = useQueryClient()
  const [filtroPatente, setFiltroPatente] = useState('')
  // Filtro por operación/zona (Coquimbo / Calama). '' = todas.
  const [filtroOperacion, setFiltroOperacion] = useState('')
  const [tareaLibreOpen, setTareaLibreOpen] = useState(false)
  const [gestionTecnicosOpen, setGestionTecnicosOpen] = useState(false)
  const { data: tecnicos } = useTallerTecnicos(filtroOperacion || null)
  const agregarTareaLibre = useAgregarTareaLibreTaller(planSemanalId)

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
      if (!prev || p.criticidad > prev.criticidad) m.set(p.activo_id, p)
    }
    return Array.from(m.values()).sort((a, b) => b.criticidad - a.criticidad)
  }, [preventivas, fleetIds])

  // Operaciones/zonas presentes (para el filtro Coquimbo/Calama).
  const operaciones = useMemo(() => {
    const set = new Set<string>(['Coquimbo', 'Calama'])
    for (const j of jornadas ?? []) if (j.operacion) set.add(j.operacion)
    return Array.from(set).sort()
  }, [jornadas])

  // Jornadas visibles según el filtro de operación.
  const jornadasVisibles = useMemo(
    () => (jornadas ?? []).filter((j) => !filtroOperacion || (j.operacion ?? '') === filtroOperacion),
    [jornadas, filtroOperacion],
  )

  // Estado real del plan (para no permitir re-confirmar uno ya confirmado).
  const planEstado = kpi?.plan_estado ?? jornadas?.[0]?.plan_estado ?? null
  const planConfirmado = planEstado != null && planEstado !== 'borrador'

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
    } else if (aActive.startsWith('ncot:')) {
      // ncot:<otId> -> agendar la OT correctiva (NC ya planificada) directo, con su grupo
      const otId = aActive.replace('ncot:', '')
      const n = (ncOts ?? []).find((x) => x.ot_id === otId)
      agregarJornada.mutate(
        { planSemanalId, otId, fecha: fechaDestino, cuadrilla: n?.grupo_trabajo ?? null },
        {
          onSuccess: () => { toast.success('Correctivo de recepción agendado'); qc.invalidateQueries({ queryKey: ['nc-ot-por-agendar'] }) },
          onError: (err) => toast.error((err as Error).message),
        },
      )
    } else if (aActive.startsWith('recepcion:')) {
      // recepcion:<activoId> -> al soltar en un día se crea la OT de inspección de recepción
      const activoId = aActive.replace('recepcion:', '')
      const r = (recepciones ?? []).find((x) => x.activo_id === activoId)
      setRecepTarget({ activoId, label: r ? `${r.patente ?? r.codigo}` : activoId, fecha: fechaDestino })
    } else if (aActive.startsWith('jornada:')) {
      const planOtId = aActive.replace('jornada:', '')
      const j = (jornadas ?? []).find((x) => x.plan_ot_id === planOtId)
      if (!j || j.dia_fecha === fechaDestino) return // mismo día: nada que mover
      // Plan confirmado → exigir motivo del cambio (control de cambios).
      if (j.plan_estado !== 'borrador') {
        setReprogMotivo('')
        setReprogTarget({
          planOtId,
          fechaDestino,
          label: `${j.activo_patente ?? j.activo_codigo ?? ''} · OT ${j.ot_folio}`,
          diaActual: j.dia_fecha,
        })
        return
      }
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
                    folio: j.ot_folio ?? j.titulo ?? '(tarea)',
                    tipo: j.ot_tipo ?? (j.categoria ?? ''),
                    prioridad: j.ot_prioridad ?? '',
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
          <select
            value={filtroOperacion}
            onChange={(e) => setFiltroOperacion(e.target.value)}
            className="h-8 rounded border border-gray-300 px-2 text-xs focus:border-blue-500 focus:outline-none"
            title="Filtrar por operación / zona"
          >
            <option value="">Todas las operaciones</option>
            {operaciones.map((op) => <option key={op} value={op}>{op}</option>)}
          </select>
          <Button
            variant="outline"
            size="sm"
            disabled={!planSemanalId}
            onClick={() => setTareaLibreOpen(true)}
            title="Programar una tarea (asistencia en terreno, equipo externo, soldadura, etc.)"
          >
            <Plus className="h-4 w-4 mr-1" /> Programar tarea
          </Button>
          <Button
            variant="outline"
            size="sm"
            onClick={() => setGestionTecnicosOpen(true)}
            title="Agregar o quitar técnicos del taller"
          >
            <User className="h-4 w-4 mr-1" /> Técnicos
          </Button>
          <Button
            size="sm"
            disabled={!planSemanalId || confirmarPlan.isPending || planConfirmado}
            onClick={() => confirmarPlan.mutate(planSemanalId, {
              onSuccess: (d) => toast.success(`Plan confirmado: ${d.ots_confirmadas} jornadas`),
              onError: (err) => toast.error((err as Error).message),
            })}
            className="bg-pillado-green-600 hover:bg-pillado-green-700 disabled:opacity-100"
            title={planConfirmado ? 'El plan de esta semana ya está confirmado' : undefined}
          >
            <Lock className="h-4 w-4 mr-1" />
            {planConfirmado ? 'Plan confirmado ✓' : 'Confirmar plan'}
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
                      jornadas={jornadasVisibles.filter((j) => j.plan_dia_id === dia.id)}
                      onAsignar={(j) => setAsignarOpen(j)}
                      onDetalle={(j) => setDetalleOpen(j)}
                      onQuitar={(j) => quitarJornada.mutate(j.plan_ot_id, {
                        onSuccess: () => toast.success('Jornada quitada'),
                        onError: (err) => toast.error((err as Error).message),
                      })}
                      onIniciar={(j) => j.ot_id && iniciarEjec.mutate({ otId: j.ot_id }, {
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

              {/* Correctivos de recepción por agendar (NC ya planificadas) */}
              <NcOtPorAgendarCard items={ncOts ?? []} />

              {/* Preventivas sugeridas (arrástralas a un día) */}
              <PreventivasSugeridas items={preventivasPatentes} />

              {/* Revisión Técnica por vencer (arrástralas a un día → inspección) */}
              <RtPorVencerCard items={rtDue ?? []} onRenovar={setRenovarRt} />

              {/* Patentes con problemas de documentos (solo flota rodante) */}
              <DocumentosPorVencerCard
                items={(docsDue ?? []).filter((d) =>
                  fleetIds.has(d.activo_id) &&
                  (!filtroOperacion || (d.operacion ?? '') === filtroOperacion),
                )}
                onRenovar={setRenovarDoc}
              />
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

      {/* Modal detalle / edición de la OT (jefe de taller) */}
      {detalleOpen && (
        <JornadaDetalleModal
          jornada={detalleOpen}
          onClose={() => setDetalleOpen(null)}
          planId={planSemanalId}
        />
      )}

      {/* Modal gestionar técnicos (agregar / quitar) */}
      {gestionTecnicosOpen && (
        <GestionarTecnicosDialog
          operacionInicial={filtroOperacion || null}
          onClose={() => setGestionTecnicosOpen(false)}
        />
      )}

      {/* Modal programar tarea libre (sin equipo de flota) */}
      {tareaLibreOpen && planSemanalId && (
        <TareaLibreDialog
          dias={dias ?? []}
          tecnicos={tecnicos ?? []}
          operacionInicial={filtroOperacion || null}
          enviando={agregarTareaLibre.isPending}
          onClose={() => setTareaLibreOpen(false)}
          onSubmit={(payload) => agregarTareaLibre.mutate(
            { planSemanalId, ...payload },
            {
              onSuccess: () => { toast.success('Tarea programada'); setTareaLibreOpen(false) },
              onError: (err) => toast.error((err as Error).message),
            },
          )}
        />
      )}

      {/* Modal finalizar ejecución */}
      {finalizarOpen && finalizarOpen.ejecucion_activa_id && (
        <Modal open={true} onClose={() => setFinalizarOpen(null)} title={`Finalizar ${finalizarOpen.ot_folio ?? finalizarOpen.titulo ?? ''}`}>
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

      {/* Control de cambios: motivo al reprogramar una jornada de un plan confirmado */}
      {reprogTarget && (
        <Modal open={true} onClose={() => setReprogTarget(null)}
               title="Reprogramar jornada (plan confirmado)">
          <div className="space-y-3">
            <div className="text-xs text-gray-600">
              <p className="font-medium text-gray-800">{reprogTarget.label}</p>
              <p>Mueves de <b>{fmtFecha(reprogTarget.diaActual)}</b> a <b>{fmtFecha(reprogTarget.fechaDestino)}</b>.</p>
            </div>
            <div className="flex items-start gap-2 rounded bg-amber-50 border border-amber-200 px-2 py-1.5 text-[11px] text-amber-800">
              <AlertTriangle className="h-3.5 w-3.5 mt-0.5 shrink-0" />
              <span>El plan ya está confirmado. Indica el motivo del cambio: quedará registrado en el control de cambios.</span>
            </div>
            <div>
              <label className="text-xs font-medium">Motivo de la reprogramación <span className="text-red-500">*</span></label>
              <textarea value={reprogMotivo} onChange={(e) => setReprogMotivo(e.target.value)}
                        rows={3} autoFocus
                        className="w-full border rounded px-2 py-1.5 text-sm"
                        placeholder="Ej: falta de repuesto, equipo no llegó a taller, prioridad de cliente…" />
            </div>
          </div>
          <ModalFooter>
            <Button variant="outline" onClick={() => setReprogTarget(null)}>Cancelar</Button>
            <Button disabled={moverJornada.isPending || !reprogMotivo.trim()}
                    onClick={() => {
                      moverJornada.mutate(
                        { planOtId: reprogTarget.planOtId, fechaDestino: reprogTarget.fechaDestino, motivo: reprogMotivo.trim() },
                        {
                          onSuccess: () => { toast.success('Jornada reprogramada'); setReprogTarget(null) },
                          onError: (err) => toast.error((err as Error).message),
                        },
                      )
                    }}>
              {moverJornada.isPending ? <Spinner className="h-4 w-4 mr-1" /> : null}
              Reprogramar
            </Button>
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
      {renovarDoc && (
        <RenovarDocumentoDialog
          doc={renovarDoc}
          onClose={() => setRenovarDoc(null)}
          onDone={() => {
            setRenovarDoc(null)
            qc.invalidateQueries({ queryKey: ['documentos-por-vencer'] })
            qc.invalidateQueries({ queryKey: ['rt-por-vencer'] })
          }}
        />
      )}

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
  const vencida = p.vencida
  const ejeIcon = p.eje_critico === 'km' ? '🛣' : p.eje_critico === 'horas' ? '⏱' : '📅'

  return (
    <div ref={setNodeRef} style={style} {...listeners} {...attributes}
         title={`${p.detalle}${p.pauta_nombre ? ` · ${p.pauta_nombre}` : ''}${!p.baseline_confiable ? ' · ⚠ revisar lectura km/h del plan' : ''}`}
         className={`rounded border px-2.5 py-1.5 cursor-grab active:cursor-grabbing shadow-sm min-w-[120px] ${
           vencida ? 'border-red-300 bg-red-50 text-red-800' : 'border-amber-200 bg-amber-50 text-amber-800'
         }`}>
      <div className="font-mono text-[12px] font-bold flex items-center gap-1">
        {p.patente}
        {!p.baseline_confiable && <AlertTriangle className="h-3 w-3 text-orange-500" />}
      </div>
      <div className="text-[10px] font-normal opacity-80">{ejeIcon} {p.detalle}</div>
    </div>
  )
}

function NcOtPorAgendarCard({ items }: { items: NcOtPorAgendar[] }) {
  return (
    <Card className="border-orange-200">
      <CardHeader className="pb-2">
        <CardTitle className="text-sm flex items-center gap-2 text-orange-800">
          <AlertTriangle className="h-4 w-4" /> Correctivos de recepción por agendar ({items.length})
          <span className="text-[10px] font-normal text-gray-400">— No Conformidades ya planificadas (con recursos). Arrástralas a un día.</span>
        </CardTitle>
      </CardHeader>
      <CardContent className="p-2">
        {items.length === 0 ? (
          <div className="text-xs text-gray-400 p-3 text-center">Sin correctivos de recepción pendientes de agendar.</div>
        ) : (
          <div className="flex gap-2 overflow-x-auto pb-1">
            {items.map((n) => <NcOtCard key={n.ot_id} n={n} />)}
          </div>
        )}
      </CardContent>
    </Card>
  )
}

function NcOtCard({ n }: { n: NcOtPorAgendar }) {
  const { attributes, listeners, setNodeRef, transform, isDragging } = useDraggable({ id: `ncot:${n.ot_id}` })
  const style = transform
    ? { transform: `translate3d(${transform.x}px,${transform.y}px,0)`, opacity: isDragging ? 0.5 : 1 }
    : undefined
  return (
    <div ref={setNodeRef} style={style} {...listeners} {...attributes}
         title={`${n.descripcion}${n.grupo_trabajo ? ' · ' + n.grupo_trabajo : ''}${n.horas_estimadas ? ' · ' + n.horas_estimadas + 'h' : ''}`}
         className="shrink-0 w-[140px] rounded border border-orange-300 bg-orange-50 text-orange-900 px-2.5 py-1.5 cursor-grab active:cursor-grabbing shadow-sm text-[12px] text-center">
      <div className="font-mono font-bold">{n.patente ?? n.codigo}</div>
      <div className="text-[10px] truncate">{n.descripcion}</div>
      {(n.grupo_trabajo || n.horas_estimadas) && (
        <div className="text-[9px] text-orange-700">{n.grupo_trabajo ?? ''}{n.horas_estimadas ? ` · ${n.horas_estimadas}h` : ''}</div>
      )}
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
  const { data: tecnicos } = useTallerTecnicos()
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
          <MecanicosPicker value={mecanicos} onChange={setMecanicos} opciones={tecnicos ?? []} />
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

// ── Patentes con problemas de documentos (RT, SOAP, permiso, hermeticidad, …) ──
// Agrupado por equipo: cada patente muestra juntos sus documentos con problema.
function DocumentosPorVencerCard({ items, onRenovar }: {
  items: DocumentoPorVencer[]
  onRenovar: (d: DocumentoPorVencer) => void
}) {
  const vencidos = items.filter((d) => d.dias_restantes < 0).length
  const grupos = useMemo(() => {
    const m = new Map<string, DocumentoPorVencer[]>()
    for (const d of items) {
      const arr = m.get(d.activo_id) ?? []
      arr.push(d)
      m.set(d.activo_id, arr)
    }
    return Array.from(m.values())
      .map((docs) => docs.slice().sort((a, b) => a.dias_restantes - b.dias_restantes))
      .sort((a, b) => a[0].dias_restantes - b[0].dias_restantes) // peor equipo primero
  }, [items])

  return (
    <Card className="border-amber-300">
      <CardHeader className="pb-2">
        <CardTitle className="text-sm flex flex-wrap items-center gap-2 text-amber-800">
          <ShieldAlert className="h-4 w-4" /> Documentos con problemas · {grupos.length} equipos ({items.length} docs)
          {vencidos > 0 && (
            <span className="text-[10px] font-bold px-1.5 py-0.5 rounded bg-red-100 text-red-700">{vencidos} vencidos</span>
          )}
          <span className="text-[10px] font-normal text-gray-400">— RT, SOAP, permiso de circulación, hermeticidad, etc. Pulsa «Renovar» para subir el archivo y el nuevo vencimiento.</span>
        </CardTitle>
      </CardHeader>
      <CardContent className="p-2">
        {grupos.length === 0 ? (
          <div className="text-xs text-gray-400 p-3 text-center">Sin documentos vencidos ni próximos a vencer.</div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 gap-2">
            {grupos.map((docs) => {
              const g = docs[0]
              const gVencidos = docs.filter((d) => d.dias_restantes < 0).length
              return (
                <div key={g.activo_id} className="rounded-lg border border-gray-200 overflow-hidden">
                  <div className="flex items-center gap-2 bg-gray-50 px-2.5 py-1.5 border-b">
                    <span className="font-mono font-bold text-sm text-gray-800">{g.patente ?? g.codigo ?? '—'}</span>
                    {g.patente && g.codigo && <span className="text-[10px] text-gray-400">{g.codigo}</span>}
                    {g.operacion && <span className="text-[10px] text-gray-400">· {g.operacion}</span>}
                    <span className="ml-auto text-[10px] text-gray-500">{docs.length} doc{docs.length > 1 ? 's' : ''}</span>
                    {gVencidos > 0 && (
                      <span className="text-[9px] font-bold px-1 rounded bg-red-100 text-red-700">{gVencidos} venc.</span>
                    )}
                  </div>
                  <div className="divide-y">
                    {docs.map((d) => {
                      const vencido = d.dias_restantes < 0
                      return (
                        <div key={d.tipo} className="flex items-center gap-2 px-2.5 py-1.5 text-xs hover:bg-amber-50/40">
                          <div className="min-w-0">
                            <div className="truncate font-medium text-gray-700">
                              {TIPO_DOC_LABEL[d.tipo] ?? d.tipo}
                              {d.bloqueante && <span className="ml-1 text-[9px] px-1 rounded bg-red-100 text-red-700">bloqueante</span>}
                            </div>
                            <div className="text-[10px] text-gray-400">vence {d.fecha_vencimiento}</div>
                          </div>
                          <span className={`ml-auto shrink-0 text-[10px] font-semibold px-1.5 py-0.5 rounded ${
                            vencido ? 'bg-red-100 text-red-700' : 'bg-amber-100 text-amber-800'
                          }`}>
                            {vencido ? `vencido ${Math.abs(d.dias_restantes)}d` : `en ${d.dias_restantes}d`}
                          </span>
                          <button type="button" onClick={() => onRenovar(d)}
                            title="Subir el documento y registrar el nuevo vencimiento"
                            className="shrink-0 inline-flex items-center gap-1 text-[11px] text-white bg-amber-600 hover:bg-amber-700 rounded px-2.5 py-1 font-semibold shadow-sm">
                            <Upload className="h-3.5 w-3.5" /> Subir documento
                          </button>
                        </div>
                      )
                    })}
                  </div>
                </div>
              )
            })}
          </div>
        )}
      </CardContent>
    </Card>
  )
}

function RenovarDocumentoDialog({ doc, onClose, onDone }: {
  doc: DocumentoPorVencer; onClose: () => void; onDone: () => void
}) {
  const toast = useToast()
  const [file, setFile] = useState<File | null>(null)
  const [emision, setEmision] = useState<string>(() => new Date().toISOString().slice(0, 10))
  const [venc, setVenc] = useState<string>('')
  const [numero, setNumero] = useState('')
  const [saving, setSaving] = useState(false)
  const label = TIPO_DOC_LABEL[doc.tipo] ?? doc.tipo

  const submit = async () => {
    if (!venc) { toast.error('Indica el nuevo vencimiento'); return }
    if (venc < emision) { toast.error('El vencimiento no puede ser anterior a la emisión'); return }
    setSaving(true)
    try {
      let url: string | null = null
      if (file) url = await subirDocumentoCert(doc.activo_id, doc.tipo, file)
      await renovarCertificacion({
        activoId: doc.activo_id, tipo: doc.tipo, fechaEmision: emision, fechaVencimiento: venc,
        archivoUrl: url, numero: numero || null,
      })
      toast.success(`${label} renovado: ${doc.patente ?? doc.codigo} vence ${venc}`)
      onDone()
    } catch (e) {
      toast.error(e instanceof Error ? e.message : 'Error al renovar el documento')
    } finally { setSaving(false) }
  }

  return (
    <Modal open onClose={onClose} title={`Renovar ${label} · ${doc.patente ?? doc.codigo}`}>
      <div className="space-y-3">
        <p className="text-xs text-gray-500">
          {label} {doc.dias_restantes < 0 ? `vencido hace ${Math.abs(doc.dias_restantes)} días` : `vence en ${doc.dias_restantes} días`} ({doc.fecha_vencimiento}).
        </p>
        <div>
          <label className="text-xs font-medium block mb-1">Archivo del documento (PDF o foto)</label>
          <label className="flex cursor-pointer flex-col items-center justify-center gap-1 rounded-lg border-2 border-dashed border-amber-300 bg-amber-50 px-3 py-5 text-center hover:bg-amber-100">
            <Upload className="h-6 w-6 text-amber-600" />
            <span className="text-sm font-semibold text-amber-800">
              {file ? file.name : 'Haz clic para subir el archivo'}
            </span>
            <span className="text-[11px] text-amber-600">PDF o foto de la {label.toLowerCase()}</span>
            <input type="file" accept="application/pdf,image/*" className="hidden"
              onChange={(e) => setFile(e.target.files?.[0] ?? null)} />
          </label>
          {file && <p className="text-[11px] text-green-600 mt-1">✓ {file.name} seleccionado</p>}
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
        <label className="text-xs font-medium block">N° / folio (opcional)
          <input value={numero} onChange={(e) => setNumero(e.target.value)}
            className="mt-0.5 w-full rounded border px-2 py-1.5 text-sm" />
        </label>
      </div>
      <ModalFooter>
        <Button variant="outline" onClick={onClose} disabled={saving}>Cancelar</Button>
        <Button onClick={submit} disabled={saving}>{saving ? 'Guardando…' : 'Registrar documento renovado'}</Button>
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
  const { data: tecnicos } = useTallerTecnicos()
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
          <label className="text-xs font-medium">Técnicos a cargo (hasta {MAX_MECANICOS})</label>
          <MecanicosPicker value={mecanicos} onChange={setMecanicos} opciones={tecnicos ?? []} />
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

// Selector de técnicos (hasta 2). Devuelve nombres; se guardan en `cuadrilla`.
function MecanicosPicker({ value, onChange, opciones }: {
  value: string[]
  onChange: (v: string[]) => void
  opciones: TallerTecnico[]
}) {
  const toggle = (m: string) => {
    if (value.includes(m)) onChange(value.filter((x) => x !== m))
    else if (value.length < MAX_MECANICOS) onChange([...value, m])
  }
  if (opciones.length === 0) {
    return <p className="mt-1 text-xs text-gray-400">No hay técnicos registrados para esta operación.</p>
  }
  return (
    <div className="mt-1 flex flex-wrap gap-1">
      {opciones.map((t) => {
        const on = value.includes(t.nombre)
        const bloqueado = !on && value.length >= MAX_MECANICOS
        return (
          <button key={t.id} type="button" onClick={() => toggle(t.nombre)} disabled={bloqueado}
                  title={t.especialidad}
                  className={`rounded-full border px-2.5 py-1 text-xs transition-colors ${
                    on ? 'border-blue-500 bg-blue-500 text-white'
                       : bloqueado ? 'border-gray-100 bg-gray-50 text-gray-300 cursor-not-allowed'
                       : 'border-gray-200 bg-white text-gray-700 hover:bg-blue-50'
                  }`}>
            {t.nombre}
            <span className={`ml-1 text-[9px] ${on ? 'text-blue-100' : 'text-gray-400'}`}>{t.especialidad}</span>
          </button>
        )
      })}
    </div>
  )
}

const ESPECIALIDADES = ['MECANICO', 'SOLDADURA', 'TRASLADOS', 'ELECTRICO', 'HIDRAULICA', 'OTRO'] as const

// Diálogo: gestionar técnicos del taller (agregar / quitar).
function GestionarTecnicosDialog({ operacionInicial, onClose }: {
  operacionInicial: string | null
  onClose: () => void
}) {
  const toast = useToast()
  const [verOperacion, setVerOperacion] = useState(operacionInicial ?? '')
  const { data: tecnicos, isLoading } = useTallerTecnicos(verOperacion || null)
  const crear = useCrearTecnico()
  const desactivar = useDesactivarTecnico()

  const [nombre, setNombre] = useState('')
  const [especialidad, setEspecialidad] = useState<string>('MECANICO')
  const [operacion, setOperacion] = useState(operacionInicial ?? 'Coquimbo')

  const agregar = () => {
    if (!nombre.trim()) { toast.error('Indica el nombre del técnico'); return }
    crear.mutate({ nombre, especialidad, operacion: operacion || null }, {
      onSuccess: () => { toast.success('Técnico agregado'); setNombre('') },
      onError: (e) => toast.error((e as Error).message),
    })
  }

  return (
    <Modal open onClose={onClose} title="Técnicos del taller" className="sm:max-w-lg">
      <div className="space-y-4">
        {/* Agregar */}
        <div className="rounded-lg border border-blue-200 bg-blue-50/40 p-3 space-y-2">
          <div className="text-xs font-semibold text-gray-700">Agregar técnico</div>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
            <Input value={nombre} onChange={(e) => setNombre(e.target.value)}
                   placeholder="Nombre y apellido"
                   onKeyDown={(e) => { if (e.key === 'Enter') agregar() }} />
            <select value={especialidad} onChange={(e) => setEspecialidad(e.target.value)}
                    className="rounded border border-gray-300 px-2 py-1.5 text-sm">
              {ESPECIALIDADES.map((e) => <option key={e} value={e}>{e}</option>)}
            </select>
            <select value={operacion} onChange={(e) => setOperacion(e.target.value)}
                    className="rounded border border-gray-300 px-2 py-1.5 text-sm">
              <option value="Coquimbo">Coquimbo</option>
              <option value="Calama">Calama</option>
              <option value="">Sin operación</option>
            </select>
            <Button size="sm" onClick={agregar} disabled={crear.isPending || !nombre.trim()}>
              <Plus className="h-4 w-4 mr-1" /> Agregar
            </Button>
          </div>
        </div>

        {/* Filtro de lista */}
        <div className="flex items-center justify-between">
          <span className="text-xs font-semibold text-gray-700">Técnicos registrados</span>
          <select value={verOperacion} onChange={(e) => setVerOperacion(e.target.value)}
                  className="h-7 rounded border border-gray-300 px-2 text-xs">
            <option value="">Todas las operaciones</option>
            <option value="Coquimbo">Coquimbo</option>
            <option value="Calama">Calama</option>
          </select>
        </div>

        {/* Lista */}
        <div className="max-h-72 overflow-auto rounded-lg border border-gray-200 divide-y">
          {isLoading ? (
            <div className="flex justify-center py-6"><Spinner className="h-5 w-5" /></div>
          ) : (tecnicos ?? []).length === 0 ? (
            <p className="py-6 text-center text-xs text-gray-400">Sin técnicos para esta operación.</p>
          ) : (
            (tecnicos ?? []).map((t) => (
              <div key={t.id} className="flex items-center gap-2 px-3 py-2 text-sm">
                <span className="font-medium text-gray-800">{t.nombre}</span>
                <span className="text-[10px] px-1.5 py-0.5 rounded bg-gray-100 text-gray-600">{t.especialidad}</span>
                {t.operacion && <span className="text-[10px] text-gray-400">{t.operacion}</span>}
                <button
                  onClick={() => desactivar.mutate(t.id, {
                    onSuccess: () => toast.success('Técnico quitado'),
                    onError: (e) => toast.error((e as Error).message),
                  })}
                  disabled={desactivar.isPending}
                  className="ml-auto text-[11px] inline-flex items-center gap-1 rounded border border-red-200 bg-white px-2 py-1 text-red-600 hover:bg-red-50 disabled:opacity-50"
                  title="Quitar técnico">
                  <Trash2 className="h-3.5 w-3.5" /> Quitar
                </button>
              </div>
            ))
          )}
        </div>
      </div>
      <ModalFooter>
        <Button variant="outline" onClick={onClose}>Cerrar</Button>
      </ModalFooter>
    </Modal>
  )
}

// Diálogo: programar una tarea sin equipo de flota (terreno / externo / soldadura).
function TareaLibreDialog({ dias, tecnicos, operacionInicial, enviando, onClose, onSubmit }: {
  dias: { fecha: string; nombre_dia: string }[]
  tecnicos: TallerTecnico[]
  operacionInicial: string | null
  enviando: boolean
  onClose: () => void
  onSubmit: (payload: {
    fecha: string
    categoria: CategoriaTareaTaller
    titulo: string
    descripcion?: string | null
    equipoExterno?: string | null
    operacion?: string | null
    tecnicoId?: string | null
    cuadrilla?: string | null
    horas?: number | null
  }) => void
}) {
  const [categoria, setCategoria] = useState<CategoriaTareaTaller>(CATEGORIAS_TAREA_LIBRE[0])
  const [titulo, setTitulo] = useState('')
  const [equipoExterno, setEquipoExterno] = useState('')
  const [descripcion, setDescripcion] = useState('')
  const [operacion, setOperacion] = useState(operacionInicial ?? '')
  const [fecha, setFecha] = useState(dias[0]?.fecha ?? '')
  const [tecnicoId, setTecnicoId] = useState('')
  const [horas, setHoras] = useState('')

  const tecnico = tecnicos.find((t) => t.id === tecnicoId)

  return (
    <Modal open onClose={onClose} title="Programar tarea">
      <div className="space-y-3">
        <div>
          <label className="text-xs font-medium">Tipo de trabajo</label>
          <select value={categoria} onChange={(e) => setCategoria(e.target.value as CategoriaTareaTaller)}
                  className="mt-0.5 w-full rounded border border-gray-300 px-2 py-1.5 text-sm">
            {CATEGORIAS_TAREA_LIBRE.map((c) => (
              <option key={c} value={c}>{CATEGORIA_TAREA_LABEL[c]}</option>
            ))}
          </select>
        </div>
        <div>
          <label className="text-xs font-medium">Título <span className="text-red-500">*</span></label>
          <Input value={titulo} onChange={(e) => setTitulo(e.target.value)}
                 placeholder="Ej. Soldadura de estanque, asistencia generador faena X" />
        </div>
        <div>
          <label className="text-xs font-medium">Equipo / cliente / lugar</label>
          <Input value={equipoExterno} onChange={(e) => setEquipoExterno(e.target.value)}
                 placeholder="Ej. Generador Cliente ACME — Faena La Negra" />
        </div>
        <div>
          <label className="text-xs font-medium">Descripción</label>
          <textarea value={descripcion} onChange={(e) => setDescripcion(e.target.value)}
                    className="mt-0.5 w-full rounded border border-gray-300 px-2 py-1.5 text-sm min-h-[60px]"
                    placeholder="Detalle del trabajo" maxLength={800} />
        </div>
        <div className="grid grid-cols-2 gap-2">
          <div>
            <label className="text-xs font-medium">Día</label>
            <select value={fecha} onChange={(e) => setFecha(e.target.value)}
                    className="mt-0.5 w-full rounded border border-gray-300 px-2 py-1.5 text-sm">
              {dias.map((d) => (
                <option key={d.fecha} value={d.fecha}>{d.nombre_dia} · {fmtFecha(d.fecha)}</option>
              ))}
            </select>
          </div>
          <div>
            <label className="text-xs font-medium">Operación / zona</label>
            <select value={operacion} onChange={(e) => setOperacion(e.target.value)}
                    className="mt-0.5 w-full rounded border border-gray-300 px-2 py-1.5 text-sm">
              <option value="">— Sin asignar —</option>
              <option value="Coquimbo">Coquimbo</option>
              <option value="Calama">Calama</option>
              {operacion && !['', 'Coquimbo', 'Calama'].includes(operacion) && (
                <option value={operacion}>{operacion}</option>
              )}
            </select>
          </div>
        </div>
        <div className="grid grid-cols-2 gap-2">
          <div>
            <label className="text-xs font-medium">Técnico a cargo</label>
            <select value={tecnicoId} onChange={(e) => setTecnicoId(e.target.value)}
                    className="mt-0.5 w-full rounded border border-gray-300 px-2 py-1.5 text-sm">
              <option value="">— Sin asignar —</option>
              {tecnicos.map((t) => (
                <option key={t.id} value={t.id}>{t.nombre} · {t.especialidad}</option>
              ))}
            </select>
          </div>
          <div>
            <label className="text-xs font-medium">Horas estimadas</label>
            <Input type="number" min="0" value={horas} onChange={(e) => setHoras(e.target.value)} placeholder="opcional" />
          </div>
        </div>
      </div>
      <ModalFooter>
        <Button variant="outline" onClick={onClose}>Cancelar</Button>
        <Button disabled={enviando || !titulo.trim() || !fecha}
                onClick={() => onSubmit({
                  fecha,
                  categoria,
                  titulo: titulo.trim(),
                  descripcion: descripcion.trim() || null,
                  equipoExterno: equipoExterno.trim() || null,
                  operacion: operacion || null,
                  tecnicoId: tecnicoId || null,
                  cuadrilla: tecnico?.nombre ?? null,
                  horas: horas ? Number(horas) : null,
                })}>
          {enviando ? <Spinner className="h-4 w-4 mr-1" /> : null}
          Programar
        </Button>
      </ModalFooter>
    </Modal>
  )
}

function DiaColumna({ fecha, nombre, jornadas, onAsignar, onDetalle, onQuitar, onIniciar, onPausar, onFinalizar }: {
  fecha: string
  nombre: string
  jornadas: TallerPlanOTFull[]
  onAsignar: (j: TallerPlanOTFull) => void
  onDetalle: (j: TallerPlanOTFull) => void
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
                         onAsignar={onAsignar} onDetalle={onDetalle} onQuitar={onQuitar}
                         onIniciar={onIniciar} onPausar={onPausar} onFinalizar={onFinalizar} />
          ))
        )}
      </CardContent>
    </Card>
  )
}

function JornadaCard({ jornada, onAsignar, onDetalle, onQuitar, onIniciar, onPausar, onFinalizar }: {
  jornada: TallerPlanOTFull
  onAsignar: (j: TallerPlanOTFull) => void
  onDetalle: (j: TallerPlanOTFull) => void
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
  const libre = jornada.es_tarea_libre

  return (
    <div ref={setNodeRef} style={style}
         className={`rounded border p-2 shadow-sm bg-white text-[11px] ${
           finalizada ? 'opacity-60 border-green-200' :
           enEjec ? 'border-amber-400 ring-1 ring-amber-200' :
           'hover:border-blue-300'
         }`}>
      <div {...listeners} {...attributes} className="cursor-grab active:cursor-grabbing">
        <div className="flex items-center gap-1">
          {libre ? (
            <span className={`text-[9px] px-1.5 py-0.5 rounded font-bold border ${colorCategoria(jornada.categoria)}`}>
              {jornada.categoria ? (CATEGORIA_CORTA[jornada.categoria] ?? 'TAREA') : 'TAREA'}
            </span>
          ) : (
            <span className={`text-[9px] px-1.5 py-0.5 rounded font-bold ${colorTipo(jornada.ot_tipo)}`}>
              {(jornada.ot_tipo ?? 'OT').toUpperCase().slice(0, 4)}
            </span>
          )}
          {jornada.secuencia_jornada > 1 && (
            <span className="text-[9px] px-1 py-0.5 rounded bg-purple-100 text-purple-700 font-bold">
              J{jornada.secuencia_jornada}
            </span>
          )}
          {jornada.horas_planificadas && (
            <span className="text-[9px] text-gray-500 ml-auto">{jornada.horas_planificadas}h</span>
          )}
        </div>
        {libre ? (
          <>
            <div className="font-semibold mt-0.5 line-clamp-2">{jornada.titulo}</div>
            {jornada.equipo_externo && (
              <div className="text-[10px] text-teal-700 mt-0.5 line-clamp-1">🔧 {jornada.equipo_externo}</div>
            )}
            {jornada.tarea_descripcion && (
              <div className="text-[10px] text-gray-500 mt-0.5 line-clamp-2">{jornada.tarea_descripcion}</div>
            )}
          </>
        ) : (
          <>
            <div className="font-mono font-bold mt-0.5">{jornada.ot_folio}</div>
            {jornada.activo_codigo && (
              <div className="text-[10px] text-gray-600">
                {jornada.activo_codigo} {jornada.activo_patente && `· ${jornada.activo_patente}`}
              </div>
            )}
            {jornada.pm_nombre && (
              <div className="text-[10px] text-blue-700 mt-0.5 line-clamp-1">{jornada.pm_nombre}</div>
            )}
          </>
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
        {(jornada.checklist_total ?? 0) > 0 && (
          <div className="flex items-center gap-1 mt-0.5 text-[9px] text-gray-500">
            <ListChecks className="h-3 w-3" />
            {jornada.checklist_completados ?? 0}/{jornada.checklist_total} tareas
            {(jornada.tiempo_estimado_total_min ?? 0) > 0 && (
              <span className="ml-1">· {Math.round((jornada.tiempo_estimado_total_min ?? 0))}min</span>
            )}
          </div>
        )}
      </div>

      {/* Acciones */}
      <div className="flex gap-1 mt-1.5">
        {libre ? (
          /* Tarea libre: asignar técnicos + quitar (sin ejecución de OT) */
          <>
            <button onClick={() => onAsignar(jornada)} title="Técnicos a cargo"
                    className="text-[9px] px-1.5 py-0.5 rounded bg-gray-100 hover:bg-gray-200 flex items-center gap-1">
              <User className="h-3 w-3" />
            </button>
            <button onClick={() => onQuitar(jornada)} title="Quitar del plan"
                    className="text-[9px] px-1.5 py-0.5 rounded bg-red-50 hover:bg-red-100 text-red-600 ml-auto">
              <Trash2 className="h-3 w-3" />
            </button>
          </>
        ) : (
        <>
        <button onClick={() => onDetalle(jornada)} title="Ver / editar OT"
                className="text-[9px] px-1.5 py-0.5 rounded bg-blue-100 hover:bg-blue-200 text-blue-700 flex items-center gap-1">
          <Pencil className="h-3 w-3" />
        </button>
        {!finalizada && (
          <>
            <button onClick={() => onAsignar(jornada)} title="Mecánicos"
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
        </>
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
  const { data: tecnicos } = useTallerTecnicos(jornada.operacion)
  // Mecánicos iniciales a partir de la cuadrilla guardada.
  const inicial = (jornada.cuadrilla ?? '')
    .split(',').map((s) => s.trim())
    .filter(Boolean)
    .slice(0, MAX_MECANICOS)
  const [mecanicos, setMecanicos] = useState<string[]>(inicial)
  const [motivo, setMotivo] = useState('')

  const confirmado = jornada.plan_estado !== 'borrador'
  const cuadrillaCambia = mecanicos.join(', ') !== (jornada.cuadrilla ?? '')
  const requiereMotivo = confirmado && cuadrillaCambia

  return (
    <Modal open={true} onClose={onClose} title={`Técnicos a cargo · ${jornada.titulo ?? jornada.ot_folio ?? 'Tarea'}`}>
      <div className="space-y-3">
        <div>
          <label className="text-xs font-medium">Técnicos a cargo (hasta {MAX_MECANICOS})</label>
          <MecanicosPicker value={mecanicos} onChange={setMecanicos} opciones={tecnicos ?? []} />
        </div>
        {requiereMotivo && (
          <div>
            <label className="text-xs font-medium text-amber-800">
              Motivo del cambio <span className="text-red-500">*</span>
            </label>
            <Input value={motivo} onChange={(e) => setMotivo(e.target.value)}
                   placeholder="El plan está confirmado: por qué cambian los mecánicos" />
          </div>
        )}
      </div>
      <ModalFooter>
        <Button variant="outline" onClick={onClose}>Cancelar</Button>
        <Button disabled={asignar.isPending || (requiereMotivo && !motivo.trim())}
                onClick={() => asignar.mutate({
                  planOtId: jornada.plan_ot_id, responsableId: jornada.responsable_id ?? null,
                  cuadrilla: mecanicos.join(', '), motivo: motivo.trim() || null,
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

// ── Detalle / edición de la OT (jefe de taller) ─────────────────────────────
function prettyBloque(b: string): string {
  const sinPrefijo = b.replace(/^b[0-9]*_?/i, '').replace(/_/g, ' ').trim()
  const txt = sinPrefijo || b
  return txt.charAt(0).toUpperCase() + txt.slice(1)
}

function JornadaDetalleModal({ jornada, planId, onClose }: {
  jornada: TallerPlanOTFull
  planId: string
  onClose: () => void
}) {
  const toast = useToast()
  const { data: usuarios } = useUsuariosAsignablesTaller()
  const { data: tecnicos } = useTallerTecnicos(jornada.operacion)
  const editar = useEditarJornadaTaller(planId)
  const { data: checklist, isLoading: loadCl } = useChecklistV3Taller(jornada.ot_id)
  const agregar = useV3AgregarItemTaller(planId, jornada.ot_id)

  const mecIniciales = (jornada.cuadrilla ?? '').split(',').map((s) => s.trim())
    .filter(Boolean).slice(0, MAX_MECANICOS)
  const [mecanicos, setMecanicos] = useState<string[]>(mecIniciales)
  const [responsableId, setResponsableId] = useState<string>(jornada.responsable_id ?? '')
  const [horas, setHoras] = useState<string>(jornada.horas_planificadas != null ? String(jornada.horas_planificadas) : '')
  const [meta, setMeta] = useState<string>(jornada.avance_objetivo_pct != null ? String(jornada.avance_objetivo_pct) : '')
  const [obs, setObs] = useState<string>(jornada.observaciones ?? '')
  const [nuevaTarea, setNuevaTarea] = useState('')
  const [nuevoTiempo, setNuevoTiempo] = useState('')
  const [motivo, setMotivo] = useState('')

  // Control de cambios: si el plan está confirmado y cambia el personal, exigir motivo.
  const confirmado = jornada.plan_estado !== 'borrador'
  const personalCambia =
    (responsableId !== (jornada.responsable_id ?? '')) ||
    (mecanicos.join(', ') !== (jornada.cuadrilla ?? ''))
  const requiereMotivo = confirmado && personalCambia

  function guardarCabecera() {
    if (requiereMotivo && !motivo.trim()) {
      toast.error('El plan está confirmado: indica el motivo del cambio de personal.')
      return
    }
    editar.mutate({
      planOtId: jornada.plan_ot_id,
      responsableId: responsableId || null,
      cuadrilla: mecanicos.join(', '),
      horasPlanificadas: horas ? Number(horas) : null,
      avanceObjetivo: meta ? Number(meta) : null,
      observaciones: obs.trim() || null,
      motivo: motivo.trim() || null,
    }, {
      onSuccess: () => { toast.success('Jornada actualizada'); onClose() },
      onError: (err) => toast.error((err as Error).message),
    })
  }

  function agregarTarea() {
    if (!nuevaTarea.trim()) return
    agregar.mutate({
      otId: jornada.ot_id ?? '', descripcion: nuevaTarea.trim(),
      tiempoMin: nuevoTiempo ? Number(nuevoTiempo) : null,
    }, {
      onSuccess: () => { setNuevaTarea(''); setNuevoTiempo('') },
      onError: (err) => toast.error((err as Error).message),
    })
  }

  const items = checklist ?? []
  const activos = items.filter((i) => !i.excluido)
  const tiempoTotal = activos.reduce((s, i) => s + (i.tiempo_min ?? 0), 0)
  // Agrupar por bloque preservando el orden (ya viene ordenado por bloque_orden, orden)
  const grupos: { bloque: string; items: ChecklistV3Item[] }[] = []
  for (const it of items) {
    let g = grupos.find((x) => x.bloque === it.bloque)
    if (!g) { g = { bloque: it.bloque, items: [] }; grupos.push(g) }
    g.items.push(it)
  }

  return (
    <Modal open onClose={onClose} title={`OT ${jornada.ot_folio} · ${jornada.activo_codigo ?? ''}`}>
      <div className="space-y-4 max-h-[72vh] overflow-y-auto pr-1">
        {/* Cabecera de la OT */}
        <div className="flex flex-wrap items-center gap-2 text-[11px]">
          <span className={`px-1.5 py-0.5 rounded font-bold ${colorTipo(jornada.ot_tipo)}`}>
            {(jornada.ot_tipo ?? 'OT').toUpperCase()}
          </span>
          <span className="px-1.5 py-0.5 rounded bg-gray-100 text-gray-700">{jornada.ot_estado}</span>
          <span className="text-gray-600">{jornada.activo_nombre} {jornada.activo_patente && `· ${jornada.activo_patente}`}</span>
          {jornada.pm_nombre && <span className="text-blue-700">· {jornada.pm_nombre}</span>}
          <Link href={`/dashboard/ordenes-trabajo/${jornada.ot_id}`}
                className="ml-auto text-blue-600 hover:underline flex items-center gap-1">
            <ExternalLink className="h-3 w-3" /> Ficha completa
          </Link>
        </div>

        {/* Campos editables de la actividad */}
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <div>
            <label className="text-xs font-medium">Responsable</label>
            <select value={responsableId} onChange={(e) => setResponsableId(e.target.value)}
                    className="w-full border rounded px-2 py-1.5 text-sm">
              <option value="">Sin asignar</option>
              {(usuarios ?? []).map((u) => (
                <option key={u.id} value={u.id}>{u.nombre_completo ?? u.id} {u.rol ? `(${u.rol})` : ''}</option>
              ))}
            </select>
          </div>
          <div>
            <label className="text-xs font-medium">Horas planificadas</label>
            <Input type="number" min="0" step="0.5" value={horas} onChange={(e) => setHoras(e.target.value)} />
          </div>
          <div className="sm:col-span-2">
            <label className="text-xs font-medium">Mecánicos a cargo (hasta {MAX_MECANICOS})</label>
            <MecanicosPicker value={mecanicos} onChange={setMecanicos} opciones={tecnicos ?? []} />
          </div>
          <div>
            <label className="text-xs font-medium">Meta de avance (%)</label>
            <Input type="number" min="0" max="100" value={meta} onChange={(e) => setMeta(e.target.value)} />
          </div>
          <div>
            <label className="text-xs font-medium">Observaciones</label>
            <Input value={obs} onChange={(e) => setObs(e.target.value)} placeholder="opcional" />
          </div>
          {requiereMotivo && (
            <div className="sm:col-span-2">
              <label className="text-xs font-medium text-amber-800">
                Motivo del cambio de personal <span className="text-red-500">*</span>
              </label>
              <Input value={motivo} onChange={(e) => setMotivo(e.target.value)}
                     placeholder="El plan está confirmado: por qué cambia el personal" />
            </div>
          )}
        </div>

        {/* Checklist V03 de la OT */}
        <div className="border-t pt-3">
          <div className="flex items-center justify-between mb-2">
            <h3 className="text-sm font-semibold flex items-center gap-1">
              <ListChecks className="h-4 w-4 text-blue-600" /> Checklist de la actividad
            </h3>
            <span className="text-[11px] text-gray-500 flex items-center gap-3">
              <span>{activos.length} tareas</span>
              <span className="flex items-center gap-1"><Clock className="h-3 w-3" /> {tiempoTotal} min ({(tiempoTotal / 60).toFixed(1)} h)</span>
            </span>
          </div>

          {loadCl ? (
            <div className="flex justify-center py-4"><Spinner /></div>
          ) : items.length === 0 ? (
            <div className="text-xs text-gray-400 py-2">Esta OT aún no tiene checklist. Agrega tareas abajo.</div>
          ) : (
            <div className="space-y-3">
              {grupos.map((g) => {
                const tBloque = g.items.filter((i) => !i.excluido).reduce((s, i) => s + (i.tiempo_min ?? 0), 0)
                const nBloque = g.items.filter((i) => !i.excluido).length
                return (
                  <div key={g.bloque}>
                    <div className="flex items-center justify-between bg-gray-100 rounded px-2 py-1 mb-1">
                      <span className="text-[11px] font-semibold text-gray-700">{prettyBloque(g.bloque)}</span>
                      <span className="text-[10px] text-gray-500">{nBloque} · {tBloque} min</span>
                    </div>
                    <div className="space-y-1">
                      {g.items.map((it) => (
                        <ChecklistV3Row key={it.instance_item_id} item={it} otId={jornada.ot_id ?? ''} planId={planId} />
                      ))}
                    </div>
                  </div>
                )
              })}
            </div>
          )}

          {/* Agregar tarea a medida */}
          <div className="flex items-end gap-2 mt-3">
            <div className="flex-1">
              <label className="text-[11px] font-medium text-gray-600">Agregar tarea a esta OT</label>
              <Input value={nuevaTarea} onChange={(e) => setNuevaTarea(e.target.value)}
                     placeholder="Descripción de la tarea"
                     onKeyDown={(e) => { if (e.key === 'Enter') agregarTarea() }} />
            </div>
            <div className="w-20">
              <label className="text-[11px] font-medium text-gray-600">Min</label>
              <Input type="number" min="0" value={nuevoTiempo} onChange={(e) => setNuevoTiempo(e.target.value)} />
            </div>
            <Button variant="outline" disabled={!nuevaTarea.trim() || agregar.isPending} onClick={agregarTarea}>
              <Plus className="h-4 w-4 mr-1" /> Agregar
            </Button>
          </div>
        </div>

        {/* Control de cambios: bitácora de reprogramaciones y cambios de personal */}
        <JornadaEventosTimeline planOtId={jornada.plan_ot_id} />
      </div>

      <ModalFooter>
        <Button variant="outline" onClick={onClose}>Cerrar</Button>
        <Button disabled={editar.isPending} onClick={guardarCabecera}>
          {editar.isPending ? <Spinner className="h-4 w-4 mr-1" /> : null}
          Guardar cambios
        </Button>
      </ModalFooter>
    </Modal>
  )
}

// ── Control de cambios: línea de tiempo de eventos de la jornada ────────────
const TIPO_EVENTO_LABEL: Record<TallerJornadaEvento['tipo'], string> = {
  reprogramacion: 'Reprogramación',
  cambio_responsable: 'Cambio de responsable',
  cambio_cuadrilla: 'Cambio de mecánicos',
  cambio_horas: 'Cambio de horas',
  cambio_avance: 'Cambio de meta',
  creacion: 'Creación',
  eliminacion: 'Eliminación',
  otro: 'Cambio',
}

function JornadaEventosTimeline({ planOtId }: { planOtId: string }) {
  const { data: eventos, isLoading } = useQuery({
    queryKey: ['taller', 'jornada-eventos', planOtId],
    queryFn: () => getJornadaEventos(planOtId),
    staleTime: 10_000,
  })

  function detalle(e: TallerJornadaEvento): string {
    if (e.tipo === 'reprogramacion' && e.dia_anterior && e.dia_nuevo)
      return `${fmtFecha(e.dia_anterior)} → ${fmtFecha(e.dia_nuevo)}`
    if (e.tipo === 'cambio_responsable')
      return `${e.responsable_anterior_nombre ?? 'Sin asignar'} → ${e.responsable_nuevo_nombre ?? 'Sin asignar'}`
    if (e.tipo === 'cambio_cuadrilla')
      return `${e.cuadrilla_anterior ?? '—'} → ${e.cuadrilla_nueva ?? '—'}`
    if (e.valor_anterior != null || e.valor_nuevo != null)
      return `${e.valor_anterior ?? '—'} → ${e.valor_nuevo ?? '—'}`
    return ''
  }

  return (
    <div className="border-t pt-3">
      <h3 className="text-sm font-semibold flex items-center gap-1 mb-2">
        <RefreshCw className="h-4 w-4 text-gray-500" /> Control de cambios
      </h3>
      {isLoading ? (
        <div className="flex justify-center py-3"><Spinner className="h-4 w-4" /></div>
      ) : !eventos || eventos.length === 0 ? (
        <p className="text-[11px] text-gray-400 py-1">Sin cambios registrados en esta jornada.</p>
      ) : (
        <ul className="space-y-2">
          {eventos.map((e) => (
            <li key={e.id} className="flex gap-2 text-[11px]">
              <div className="mt-1 h-1.5 w-1.5 rounded-full bg-gray-400 shrink-0" />
              <div className="flex-1">
                <div className="flex flex-wrap items-center gap-1.5">
                  <span className="font-semibold text-gray-800">{TIPO_EVENTO_LABEL[e.tipo]}</span>
                  <span className="text-gray-600">{detalle(e)}</span>
                  {e.plan_confirmado && (
                    <span className="text-[9px] px-1 rounded bg-amber-100 text-amber-700">plan confirmado</span>
                  )}
                </div>
                {e.motivo && <p className="text-gray-600 italic">«{e.motivo}»</p>}
                <p className="text-gray-400">
                  {e.autor_nombre ?? '—'} · {new Date(e.created_at).toLocaleString('es-CL', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' })}
                </p>
              </div>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}

function ChecklistV3Row({ item, otId, planId }: {
  item: ChecklistV3Item
  otId: string
  planId: string
}) {
  const toast = useToast()
  const setTiempo = useV3SetTiempoTaller(planId, otId)
  const setExcluido = useV3SetExcluidoTaller(planId, otId)
  const eliminarCustom = useV3EliminarCustomTaller(planId, otId)
  const [tiempo, setTiempoStr] = useState(item.tiempo_min != null ? String(item.tiempo_min) : '')
  const ejecutado = !!item.resultado && item.resultado !== 'pendiente'

  function guardarTiempo() {
    const nuevo = tiempo ? Number(tiempo) : null
    if (nuevo === (item.tiempo_min ?? null)) return
    setTiempo.mutate({ itemId: item.instance_item_id, tiempoMin: nuevo }, {
      onError: (err) => toast.error((err as Error).message),
    })
  }

  return (
    <div className={`border rounded px-2 py-1.5 ${item.excluido ? 'bg-gray-100 opacity-60' : 'bg-white'}`}>
      <div className="flex items-center gap-2">
        {item.codigo && <span className="text-[9px] text-gray-400 font-mono shrink-0">{item.codigo}</span>}
        <span className={`flex-1 text-[12px] ${item.excluido ? 'line-through text-gray-400' : 'text-gray-800'}`}>
          {item.descripcion}
          {item.es_custom && <span className="ml-1 text-[9px] px-1 rounded bg-purple-100 text-purple-700">añadida</span>}
          {item.critico && <span className="ml-1 text-[9px] px-1 rounded bg-red-100 text-red-700">crítica</span>}
        </span>
        {item.requiere_foto && <Camera className="h-3 w-3 text-gray-400 shrink-0" />}
        <div className="w-16 shrink-0">
          <Input type="number" min="0" value={tiempo} disabled={item.excluido}
                 onChange={(e) => setTiempoStr(e.target.value)} onBlur={guardarTiempo}
                 className="h-7 text-xs" placeholder="min" />
        </div>
        {ejecutado && (
          <span className={`text-[9px] px-1 rounded font-medium shrink-0 ${
            item.resultado === 'ok' ? 'bg-green-100 text-green-700' : 'bg-red-100 text-red-700'
          }`}>{item.resultado}</span>
        )}
        <div className="flex items-center gap-1 shrink-0">
          {item.es_custom ? (
            <button onClick={() => eliminarCustom.mutate(item.instance_item_id, {
                      onError: (err) => toast.error((err as Error).message),
                    })} disabled={eliminarCustom.isPending} title="Eliminar tarea añadida"
                    className="px-1 py-0.5 rounded bg-red-50 hover:bg-red-100 text-red-600">
              <Trash2 className="h-3.5 w-3.5" />
            </button>
          ) : (
            <button onClick={() => setExcluido.mutate({ itemId: item.instance_item_id, excluido: !item.excluido }, {
                      onError: (err) => toast.error((err as Error).message),
                    })} disabled={setExcluido.isPending || ejecutado}
                    title={item.excluido ? 'Incluir en esta OT' : 'No aplica a esta OT'}
                    className={`px-1.5 py-0.5 rounded text-[10px] ${
                      item.excluido ? 'bg-green-100 hover:bg-green-200 text-green-700'
                                    : 'bg-gray-100 hover:bg-gray-200 text-gray-600'}`}>
              {item.excluido ? 'Incluir' : 'No aplica'}
            </button>
          )}
        </div>
      </div>
    </div>
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
