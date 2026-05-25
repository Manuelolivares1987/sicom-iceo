'use client'

import { useEffect, useMemo, useState } from 'react'
import {
  DndContext, DragEndEvent, DragOverlay, DragStartEvent,
  PointerSensor, useDraggable, useDroppable, useSensor, useSensors,
} from '@dnd-kit/core'
import {
  Calendar, Save, ArrowLeft, ChevronLeft, ChevronRight, Lock, AlertTriangle, FileSpreadsheet,
  Trash2, User, Clock, MapPin, MessageSquare, BarChart3, Layers, X,
  CheckCircle2, CalendarPlus, Repeat, Ban, Eraser, ShieldAlert,
} from 'lucide-react'
import Link from 'next/link'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { Select } from '@/components/ui/select'
import { Modal, ModalFooter } from '@/components/ui/modal'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useToast } from '@/contexts/toast-context'
import { useCalamaPlanificaciones, useCalamaOTs, useCalamaZonas } from '@/hooks/use-calama'
import {
  useGetOrCreatePlanSemanal, usePlanSemanal, useDiasPlanSemanal, useOTsPlanSemanal,
  useMoverOTplanSemanal, useMoverJornada, useQuitarOTplanSemanal, useQuitarJornada,
  useConfirmarPlanSemanal,
  useUsuariosAsignables, useAsignarResponsable,
  useActualizarComentarioPlanOT, useAvancePorArea, useResumenGeneral,
} from '@/hooks/use-calama-plan-semanal'
import { useActualizarAvanceManual } from '@/hooks/use-calama-avance'
import {
  useAgregarJornadaOT, useReprogramarSaldoOT,
  useDesprogramarJornada, useCancelarJornada,
  useResetearJornadaPrueba, useEliminarJornadaPrueba,
} from '@/hooks/use-calama-jornada'
import { usePermissions } from '@/hooks/use-permissions'
import { lunesDe, jornadaActiva } from '@/lib/services/calama-plan-semanal'
import { exportarPlanSemanalExcel, descargarBlob } from '@/lib/export/plan-semanal-excel'
import { zonaCodeFromFolio, excelCodigoFromFolio, type CalamaOTConRelaciones } from '@/lib/services/calama'
import { EstadoBadge } from '@/components/calama/gantt-table'

const BACKLOG_ID = 'backlog'
type Tab = 'planificacion' | 'general' | 'por_area'

export default function PlanSemanalPage() {
  useRequireAuth()
  const toast = useToast()
  const { isAdminGlobal } = usePermissions()
  const esAdmin = isAdminGlobal()

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
  const moverJornada = useMoverJornada()
  const quitarOT = useQuitarOTplanSemanal()
  const quitarJornada = useQuitarJornada()
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

  // Modal planificar varios dias (multidia)
  const agregarJornada = useAgregarJornadaOT()
  const [multidiaOpen, setMultidiaOpen] = useState<string | null>(null) // ot_id
  const [multidiaFechas, setMultidiaFechas] = useState<string[]>([])
  const [multidiaResp, setMultidiaResp] = useState<string>('')
  const [multidiaHoras, setMultidiaHoras] = useState<string>('')
  const [multidiaAvance, setMultidiaAvance] = useState<string>('')
  const [multidiaComentario, setMultidiaComentario] = useState<string>('')

  // Modal reprogramar saldo
  const reprogramarSaldo = useReprogramarSaldoOT()
  const [reprogramarOpen, setReprogramarOpen] = useState<string | null>(null) // plan_ot_id origen
  const [reprogramarFecha, setReprogramarFecha] = useState<string>('')
  const [reprogramarResp, setReprogramarResp] = useState<string>('')
  const [reprogramarMotivo, setReprogramarMotivo] = useState<string>('')
  const [reprogramarHoras, setReprogramarHoras] = useState<string>('')
  const [reprogramarAvance, setReprogramarAvance] = useState<string>('')

  // MIG32: acciones administrativas
  const desprogramar = useDesprogramarJornada()
  const cancelar = useCancelarJornada()
  const resetearPrueba = useResetearJornadaPrueba()
  const eliminarPrueba = useEliminarJornadaPrueba()
  // Modal "Sacar del programa" (desprogramar)
  const [sacarOpen, setSacarOpen] = useState<string | null>(null) // plan_ot_id
  const [sacarMotivo, setSacarMotivo] = useState('')
  const [sacarObs, setSacarObs] = useState('')
  const [sacarDestino, setSacarDestino] = useState<'backlog'|'requiere_reprogramacion'|'desprogramada'>('desprogramada')
  // Modal Cancelar
  const [cancelarOpen, setCancelarOpen] = useState<string | null>(null) // plan_ot_id
  const [cancelarMotivo, setCancelarMotivo] = useState('')
  const [cancelarObs, setCancelarObs] = useState('')
  const [cancelarTipo, setCancelarTipo] = useState<'operacional'|'prueba'|'mandante'|'clima'|'otro'>('operacional')
  // Modal Resetear prueba (admin)
  const [resetearOpen, setResetearOpen] = useState<string | null>(null) // plan_ot_id
  const [resetearMotivo, setResetearMotivo] = useState('')
  const [resetearModo, setResetearModo] = useState<'mantener_programada'|'devolver_backlog'|'desprogramar'|'eliminar_logico'>('mantener_programada')
  const [resetearConfirm, setResetearConfirm] = useState('')
  // Modal Eliminar prueba (admin)
  const [eliminarOpen, setEliminarOpen] = useState<string | null>(null) // plan_ot_id
  const [eliminarMotivo, setEliminarMotivo] = useState('')
  const [eliminarConfirm, setEliminarConfirm] = useState('')

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

  // Solo cuenta como "ya en plan" si la jornada esta ACTIVA. Una OT cuyas
  // unicas jornadas estan desprogramadas/anuladas debe volver al backlog.
  const planOtsActivasByOtId = useMemo(
    () => new Map((planOts ?? []).filter(jornadaActiva).map((p) => [p.ot_id, p])),
    [planOts],
  )
  const planOtsByOtId = planOtsActivasByOtId
  const otsById = useMemo(() => new Map((ots ?? []).map((o) => [o.id, o])), [ots])

  const otsLugar = useMemo(() => {
    if (!ots) return []
    if (!lugarFisicoSel) return ots
    return ots.filter((o) => zonaCodeFromFolio(o.folio) === lugarFisicoSel)
  }, [ots, lugarFisicoSel])

  // Backlog = OTs del lugar (o todas) que NO tengan jornada ACTIVA en el plan.
  const backlog = useMemo(() => {
    return otsLugar.filter((o) => !planOtsActivasByOtId.has(o.id) && o.estado !== 'finalizada' && o.estado !== 'cancelada')
  }, [otsLugar, planOtsActivasByOtId])

  const otsByDia = useMemo(() => {
    const m = new Map<string, CalamaOTConRelaciones[]>()
    for (const dia of dias ?? []) m.set(dia.id, [])
    for (const p of planOts ?? []) {
      // MIG32: defensa profunda - oculta desprogramadas / anuladas / canceladas /
      // no_ejecutada / reprogramada / visible_en_kanban=false / desprogramada_at|anulada_at!=null.
      if (!jornadaActiva(p)) continue
      const ot = otsById.get(p.ot_id)
      if (!ot) continue
      if (lugarFisicoSel && zonaCodeFromFolio(ot.folio) !== lugarFisicoSel) continue
      const arr = m.get(p.plan_dia_id)
      if (arr) arr.push(ot)
    }
    return m
  }, [dias, planOts, otsById, lugarFisicoSel])

  const [activeOTId, setActiveOTId] = useState<string | null>(null)
  const sensors = useSensors(useSensor(PointerSensor, { activationConstraint: { distance: 5 } }))

  // Identifier helpers: backlog = "bl:<ot_id>", jornada existente = "j:<plan_ot_id>".
  const parseDragId = (raw: string): { kind: 'bl' | 'j' | 'unknown'; id: string } => {
    if (raw.startsWith('bl:')) return { kind: 'bl', id: raw.slice(3) }
    if (raw.startsWith('j:'))  return { kind: 'j',  id: raw.slice(2) }
    return { kind: 'unknown', id: raw }
  }

  const handleDragStart = (e: DragStartEvent) => {
    const parsed = parseDragId(String(e.active.id))
    if (parsed.kind === 'bl') setActiveOTId(parsed.id)
    else if (parsed.kind === 'j') {
      const planOt = (planOts ?? []).find((p) => p.id === parsed.id)
      setActiveOTId(planOt?.ot_id ?? null)
    } else setActiveOTId(null)
  }

  const handleDragEnd = (e: DragEndEvent) => {
    setActiveOTId(null)
    if (!planSemanalId) return
    const parsed = parseDragId(String(e.active.id))
    const overId = e.over?.id ? String(e.over.id) : null
    if (!overId) return

    // Drop al BACKLOG: solo aplica si venia de una jornada existente.
    if (overId === BACKLOG_ID) {
      if (parsed.kind !== 'j') return
      if (!confirm('¿Quieres quitar esta jornada del plan? La OT volverá a quedar disponible para reprogramar.')) return
      quitarJornada.mutate({ planSemanalId, planOtId: parsed.id }, {
        onSuccess: () => toast.success('Jornada quitada del plan'),
        onError: (err) => {
          const msg = err instanceof Error ? err.message : 'Error al quitar jornada'
          setErrorMsg(msg); toast.error(msg)
        },
      })
      return
    }

    const dia = dias?.find((d) => d.id === overId)
    if (!dia) return

    if (parsed.kind === 'bl') {
      // Desde backlog: insertar nueva jornada via RPC viejo (multidia-safe porque
      // hace UPSERT por (plan_semanal_id, ot_id) y MIG28 ya admite multidia con
      // este patron — nueva fila si no existe en ese dia).
      moverOT.mutate(
        { planSemanalId, otId: parsed.id, fechaDestino: dia.fecha },
        {
          onSuccess: () => toast.success(`OT planificada para ${dia.nombre_dia} ${dia.fecha}`),
          onError: (err) => {
            const msg = err instanceof Error ? err.message : 'Error al planificar OT'
            setErrorMsg(msg); toast.error(msg)
          },
        },
      )
    } else if (parsed.kind === 'j') {
      // Mover jornada concreta (multidia-safe).
      moverJornada.mutate(
        { planSemanalId, planOtId: parsed.id, fechaDestino: dia.fecha },
        {
          onSuccess: () => toast.success(`Jornada movida a ${dia.nombre_dia} ${dia.fecha}`),
          onError: (err) => {
            const msg = err instanceof Error ? err.message : 'Error al mover jornada'
            setErrorMsg(msg); toast.error(msg)
          },
        },
      )
    }
  }

  const handleConfirmar = () => {
    if (!planSemanalId) return
    if (!confirm('¿Confirmar plan semanal? Las OTs quedaran disponibles para los responsables.')) return
    confirmarPlan.mutate(planSemanalId, {
      onSuccess: () => toast.success('Plan semanal confirmado'),
      onError: (e) => {
        const msg = e instanceof Error ? e.message : 'Error al confirmar'
        setErrorMsg(msg); toast.error(msg)
      },
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
      toast.success('Comentario guardado')
      setComentarioOpen(null)
    } catch (e) {
      const msg = e instanceof Error ? e.message : 'Error al guardar comentario'
      setErrorMsg(msg); toast.error(msg)
    }
  }

  const abrirAvance = (otId: string) => {
    const ot = otsById.get(otId)
    setAvanceValor(ot ? Number(ot.avance_pct ?? 0) : 0)
    setAvanceMotivo('ajuste_manual')
    setAvanceComentario('')
    setAvanceOpen(otId)
  }
  const abrirMultidia = (otId: string) => {
    setMultidiaFechas([])
    setMultidiaResp('')
    setMultidiaHoras('')
    setMultidiaAvance('')
    setMultidiaComentario('')
    setMultidiaOpen(otId)
  }
  const guardarMultidia = async () => {
    if (!multidiaOpen || !planSemanalId) return
    if (multidiaFechas.length === 0) { toast.error('Selecciona al menos una fecha'); return }
    let okCount = 0
    let errCount = 0
    for (const fecha of multidiaFechas) {
      try {
        await agregarJornada.mutateAsync({
          plan_semanal_id: planSemanalId,
          ot_id: multidiaOpen,
          fecha,
          responsable_id: multidiaResp || undefined,
          horas_planificadas: multidiaHoras ? Number(multidiaHoras) : undefined,
          avance_objetivo_pct: multidiaAvance ? Number(multidiaAvance) : undefined,
          comentario: multidiaComentario || undefined,
        })
        okCount++
      } catch {
        errCount++
      }
    }
    if (okCount > 0) toast.success(`${okCount} jornada(s) creada(s)`)
    if (errCount > 0) toast.error(`${errCount} fecha(s) fallaron (¿ya existen?)`)
    setMultidiaOpen(null)
  }

  const abrirReprogramar = (planOtId: string) => {
    setReprogramarFecha('')
    setReprogramarResp('')
    setReprogramarMotivo('')
    setReprogramarHoras('')
    setReprogramarAvance('')
    setReprogramarOpen(planOtId)
  }
  const guardarReprogramar = async () => {
    if (!reprogramarOpen || !planSemanalId) return
    if (!reprogramarFecha) { toast.error('Fecha destino obligatoria'); return }
    if (!reprogramarMotivo.trim()) { toast.error('Motivo obligatorio'); return }
    const planOt = (planOts ?? []).find((p) => p.id === reprogramarOpen)
    if (!planOt) { toast.error('Jornada origen no encontrada'); return }
    try {
      await reprogramarSaldo.mutateAsync({
        plan_semanal_ot_origen_id: reprogramarOpen,
        plan_semanal_id: planSemanalId,
        fecha_destino: reprogramarFecha,
        responsable_id: reprogramarResp || undefined,
        avance_objetivo_pct: reprogramarAvance ? Number(reprogramarAvance) : undefined,
        horas_planificadas: reprogramarHoras ? Number(reprogramarHoras) : undefined,
        motivo: reprogramarMotivo,
        ot_id: planOt.ot_id,
      })
      toast.success('Saldo reprogramado')
      setReprogramarOpen(null)
    } catch (e) {
      toast.error(e instanceof Error ? e.message : 'Error al reprogramar')
    }
  }

  // ── Acciones admin ─────────────────────────────────────────────────────────
  const abrirSacar = (planOtId: string) => {
    setSacarMotivo(''); setSacarObs(''); setSacarDestino('desprogramada')
    setSacarOpen(planOtId)
  }
  const guardarSacar = async () => {
    if (!sacarOpen) return
    const planOt = (planOts ?? []).find((p) => p.id === sacarOpen)
    if (!planOt) return
    if (!sacarMotivo.trim()) { toast.error('Motivo obligatorio'); return }
    try {
      await desprogramar.mutateAsync({
        plan_semanal_ot_id: sacarOpen,
        ot_id: planOt.ot_id,
        plan_semanal_id: planSemanalId,
        motivo: sacarMotivo, observacion: sacarObs || undefined,
        destino: sacarDestino,
      })
      toast.success(sacarDestino === 'backlog' ? 'OT devuelta al backlog' : 'Jornada desprogramada')
      setSacarOpen(null)
    } catch (e) { toast.error(e instanceof Error ? e.message : 'Error al desprogramar') }
  }

  const abrirCancelar = (planOtId: string) => {
    setCancelarMotivo(''); setCancelarObs(''); setCancelarTipo('operacional')
    setCancelarOpen(planOtId)
  }
  const guardarCancelar = async () => {
    if (!cancelarOpen) return
    const planOt = (planOts ?? []).find((p) => p.id === cancelarOpen)
    if (!planOt) return
    if (!cancelarMotivo.trim()) { toast.error('Motivo obligatorio'); return }
    try {
      await cancelar.mutateAsync({
        plan_semanal_ot_id: cancelarOpen,
        ot_id: planOt.ot_id,
        plan_semanal_id: planSemanalId,
        motivo: cancelarMotivo, observacion: cancelarObs || undefined,
        tipo_cancelacion: cancelarTipo,
      })
      toast.success('Jornada cancelada')
      setCancelarOpen(null)
    } catch (e) { toast.error(e instanceof Error ? e.message : 'Error al cancelar') }
  }

  const abrirResetear = (planOtId: string) => {
    setResetearMotivo(''); setResetearModo('mantener_programada'); setResetearConfirm('')
    setResetearOpen(planOtId)
  }
  const guardarResetear = async () => {
    if (!resetearOpen) return
    const planOt = (planOts ?? []).find((p) => p.id === resetearOpen)
    if (!planOt) return
    if (!resetearMotivo.trim()) { toast.error('Motivo obligatorio'); return }
    if (resetearConfirm !== 'RESET') { toast.error('Debes escribir RESET para confirmar'); return }
    try {
      await resetearPrueba.mutateAsync({
        plan_semanal_ot_id: resetearOpen,
        ot_id: planOt.ot_id,
        plan_semanal_id: planSemanalId,
        motivo: resetearMotivo, modo: resetearModo,
        confirmacion_texto: resetearConfirm,
      })
      toast.success(`Reset de prueba: ${resetearModo}`)
      setResetearOpen(null)
    } catch (e) { toast.error(e instanceof Error ? e.message : 'Error al resetear') }
  }

  const abrirEliminar = (planOtId: string) => {
    setEliminarMotivo(''); setEliminarConfirm('')
    setEliminarOpen(planOtId)
  }
  const guardarEliminar = async () => {
    if (!eliminarOpen) return
    const planOt = (planOts ?? []).find((p) => p.id === eliminarOpen)
    if (!planOt) return
    if (!eliminarMotivo.trim()) { toast.error('Motivo obligatorio'); return }
    if (eliminarConfirm !== 'ELIMINAR') { toast.error('Debes escribir ELIMINAR para confirmar'); return }
    try {
      await eliminarPrueba.mutateAsync({
        plan_semanal_ot_id: eliminarOpen,
        ot_id: planOt.ot_id,
        plan_semanal_id: planSemanalId,
        motivo: eliminarMotivo,
        confirmacion_texto: eliminarConfirm,
      })
      toast.success('Jornada eliminada')
      setEliminarOpen(null)
    } catch (e) { toast.error(e instanceof Error ? e.message : 'Error al eliminar') }
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
      toast.success(`Avance actualizado a ${avanceValor}%`)
      setAvanceOpen(null)
    } catch (e) {
      const msg = e instanceof Error ? e.message : 'Error al guardar avance'
      setErrorMsg(msg); toast.error(msg)
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
            <Button
              variant="outline"
              disabled={!planSemanalId || (planOts?.length ?? 0) === 0}
              onClick={async () => {
                try {
                  const otById = new Map((ots ?? []).map((o) => [o.id, o]))
                  const diaById = new Map((dias ?? []).map((d) => [d.id, d]))
                  // Map codigo_zona -> nombre (oficina, truckshop, etc.)
                  // Las macro zonas suelen tener codigo terminado en .0.0 (1.0.0, 2.0.0)
                  // pero el catalogo puede tener tambien sub-zonas — buscamos primero
                  // por coincidencia exacta y caemos al codigo si no hay nombre.
                  const zonaNombrePorCodigo = new Map(
                    (zonas ?? []).map((z) => [z.codigo_zona, z.nombre] as const),
                  )
                  const planificacion = (planificaciones ?? []).find((p) => p.id === planificacionId)
                  const blob = await exportarPlanSemanalExcel({
                    titulo: `Plan semanal Calama${planificacion ? ' — ' + planificacion.nombre : ''}`,
                    fechaInicio: semanaIso,
                    fechaFin: (dias && dias.length > 0) ? dias[dias.length - 1].fecha : semanaIso,
                    jornadas: (planOts ?? []).filter((p) => jornadaActiva(p)).map((j) => {
                      const ot = otById.get(j.ot_id)
                      const dia = diaById.get(j.plan_dia_id)
                      const folio = ot?.folio ?? j.ot_id.slice(0, 8)
                      const macroZona = ot?.folio ? zonaCodeFromFolio(ot.folio) : null
                      return {
                        fecha: dia?.fecha ?? '',
                        dia_nombre: dia?.nombre_dia ?? '',
                        folio,
                        macro_zona: macroZona,
                        macro_zona_nombre: macroZona ? (zonaNombrePorCodigo.get(macroZona) ?? null) : null,
                        codigo_excel: ot?.folio ? excelCodigoFromFolio(ot.folio) : null,
                        tipo: 'OT calama',
                        prioridad: ot?.prioridad ?? null,
                        activo: ot?.tarea_maestro?.codigo
                          ? `${ot.tarea_maestro.codigo} · ${ot.tarea_maestro.nombre ?? ''}`
                          : null,
                        pm_nombre: ot?.titulo ?? null,
                        responsable: null,
                        cuadrilla: null,
                        horas_planificadas: j.horas_planificadas,
                        avance_objetivo: j.avance_objetivo_pct,
                        secuencia_jornada: j.secuencia_jornada,
                        estado_jornada: j.estado_plan,
                        estado_ot: ot?.estado ?? null,
                        avance_final: ot?.avance_pct ?? null,
                        faena: ot?.faena?.nombre ?? null,
                        cliente: ot?.planificacion?.nombre ?? null,
                        observaciones: j.observaciones,
                      }
                    }),
                    mostrarMacroZona: true,
                    scopeNombre: planificacion?.nombre ?? null,
                  })
                  descargarBlob(blob, `plan_calama_${semanaIso}.xlsx`)
                  toast.success('Plan exportado')
                } catch (err) {
                  toast.error((err as Error).message)
                }
              }}
            >
              <FileSpreadsheet className="h-4 w-4 mr-1" /> Excel
            </Button>
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

      {/* Banner de estado de guardado / plan confirmado */}
      {planSem && (
        <div className={`rounded-lg border p-2 text-xs flex items-center justify-between gap-2 ${
          planSem.estado === 'borrador'
            ? 'border-blue-200 bg-blue-50 text-blue-800'
            : planSem.estado === 'confirmado'
            ? 'border-amber-200 bg-amber-50 text-amber-800'
            : planSem.estado === 'en_ejecucion'
            ? 'border-amber-200 bg-amber-50 text-amber-800'
            : 'border-gray-200 bg-gray-50 text-gray-700'
        }`}>
          <span className="flex items-center gap-2">
            {(asignarResp.isPending || moverOT.isPending || moverJornada.isPending
              || quitarOT.isPending || quitarJornada.isPending
              || updateComentario.isPending || agregarJornada.isPending
              || reprogramarSaldo.isPending) ? (
              <>
                <Spinner className="h-3 w-3" />
                <span>Guardando…</span>
              </>
            ) : planSem.estado === 'confirmado' || planSem.estado === 'en_ejecucion' ? (
              <>
                <AlertTriangle className="h-3.5 w-3.5" />
                <span>
                  Plan <strong>{planSem.estado}</strong>. Puedes modificarlo: los cambios quedaran registrados.
                  Las jornadas en ejecucion / aceptadas / cerradas no se mueven directamente; usa "Reprogramar saldo".
                </span>
              </>
            ) : (
              <>
                <CheckCircle2 className="h-3.5 w-3.5" />
                <span>
                  Plan {planSem.estado}. Los cambios (responsable, comentario, mover OT) se guardan automaticamente.
                </span>
              </>
            )}
          </span>
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
                    <DraggableOTCard
                      key={ot.id} ot={ot} dragId={`bl:${ot.id}`} disabled={planBloqueado}
                      onPlanificarVariosDias={() => abrirMultidia(ot.id)}
                    />
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
                          // Estados de jornada que NO admiten mover/quitar libremente.
                          const estadosBloqueoJornada: string[] = [
                            'en_ejecucion','pausada','finalizada','finalizada_operador',
                            'pendiente_aprobacion','aceptada','cerrada',
                          ]
                          const jornadaBloqueada = !!planOt && estadosBloqueoJornada.includes(planOt.estado_plan)
                          return (
                            <DraggableOTCard
                              key={planOt?.id ?? ot.id} ot={ot} compact
                              dragId={planOt ? `j:${planOt.id}` : `bl:${ot.id}`}
                              responsableId={planOt?.responsable_id ?? null}
                              comentario={planOt?.observaciones ?? null}
                              usuarios={usuarios ?? []}
                              disabled={planBloqueado || jornadaBloqueada}
                              onAsignar={(uid) => {
                                const u = (usuarios ?? []).find((x) => x.id === uid)
                                const nombre = u?.nombre_completo || u?.email || 'usuario'
                                asignarResp.mutate(
                                  { planSemanalId, otId: ot.id, responsableId: uid },
                                  {
                                    onSuccess: () => {
                                      toast.success(`Responsable actualizado: ${nombre}`)
                                    },
                                    onError: (e) => {
                                      const msg = e instanceof Error ? e.message : 'Error al asignar responsable'
                                      setErrorMsg(msg)
                                      toast.error(msg)
                                    },
                                  },
                                )
                              }}
                              onQuitar={() => {
                                if (!planOt) return
                                if (!confirm('¿Quieres quitar esta jornada del plan? La OT volverá a quedar disponible para reprogramar.')) return
                                quitarJornada.mutate({ planSemanalId, planOtId: planOt.id }, {
                                  onSuccess: () => toast.success('Jornada quitada del plan'),
                                  onError: (e) => {
                                    const msg = e instanceof Error ? e.message : 'Error al quitar jornada'
                                    setErrorMsg(msg)
                                    toast.error(msg)
                                  },
                                })
                              }}
                              onComentar={() => abrirComentario(ot.id)}
                              onActualizarAvance={() => abrirAvance(ot.id)}
                              onPlanificarVariosDias={() => abrirMultidia(ot.id)}
                              estadoPlan={planOt?.estado_plan ?? null}
                              requiereDecision={(planOt as { requiere_decision_programador?: boolean } | undefined)?.requiere_decision_programador ?? false}
                              onSacar={planOt ? () => abrirSacar(planOt.id) : undefined}
                              onCancelar={planOt ? () => abrirCancelar(planOt.id) : undefined}
                              onResetearPrueba={esAdmin && planOt ? () => abrirResetear(planOt.id) : undefined}
                              onEliminarPrueba={esAdmin && planOt ? () => abrirEliminar(planOt.id) : undefined}
                              onReprogramarSaldo={
                                planOt && Number(ot.avance_pct ?? 0) < 100
                                  ? () => abrirReprogramar(planOt.id)
                                  : undefined
                              }
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
                <div className="grid grid-cols-2 sm:grid-cols-5 gap-3">
                  <KPI title="Lugares físicos"  value={resumenGeneral.total_lugares_fisicos} icon={<Layers className="h-4 w-4" />} />
                  <KPI title="Total tareas"      value={resumenGeneral.total_tareas} />
                  <KPI title="Avance terminado"
                    value={`${(resumenGeneral.avance_completitud_pct ?? 0).toFixed(1)}%`}
                    tone="green"
                  />
                  <KPI title="Avance real"
                    value={`${(resumenGeneral.avance_real_pct ?? 0).toFixed(1)}%`}
                    tone="indigo"
                  />
                  <KPI title="Avance proyectado"
                    value={`${(resumenGeneral.avance_proyectado_pct ?? 0).toFixed(1)}%`}
                    tone="amber"
                  />
                </div>
                <div className="text-[11px] text-gray-500 -mt-1 leading-relaxed">
                  <strong>Avance terminado</strong> = Finalizadas / Total ({resumenGeneral.tareas_finalizadas}/{resumenGeneral.total_tareas}).
                  {' '}<strong>Avance real</strong> = (Finalizadas + En ejecución) / Total ({resumenGeneral.tareas_finalizadas + resumenGeneral.tareas_en_ejecucion}/{resumenGeneral.total_tareas}).
                  {' '}<strong>Avance proyectado</strong> = (Finalizadas + En ejecución + Planificadas semana) / Total.
                </div>
                <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
                  <KPI title="Finalizadas"       value={resumenGeneral.tareas_finalizadas} tone="green" />
                  <KPI title="En ejecución"      value={resumenGeneral.tareas_en_ejecucion} tone="amber" />
                  <KPI title="Pendientes"        value={resumenGeneral.tareas_pendientes} />
                  <KPI title="No ejecutadas"     value={resumenGeneral.tareas_no_ejecutadas} tone={resumenGeneral.tareas_no_ejecutadas > 0 ? 'red' : undefined} />
                </div>
                <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
                  <KPI title="Por aprobar"
                    value={resumenGeneral.tareas_pendiente_aprobacion ?? 0}
                    tone={(resumenGeneral.tareas_pendiente_aprobacion ?? 0) > 0 ? 'amber' : undefined}
                  />
                  <KPI title="Parciales"
                    value={resumenGeneral.tareas_parciales ?? 0}
                    tone={(resumenGeneral.tareas_parciales ?? 0) > 0 ? 'amber' : undefined}
                  />
                  <KPI title="Requiere corrección"
                    value={resumenGeneral.tareas_requiere_correccion ?? 0}
                    tone={(resumenGeneral.tareas_requiere_correccion ?? 0) > 0 ? 'red' : undefined}
                  />
                  <KPI title="Plan. esta semana" value={resumenGeneral.tareas_planificadas_semanas} />
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

      {/* Modal: planificar varios dias (multidia) */}
      <Modal
        open={!!multidiaOpen}
        onClose={() => !agregarJornada.isPending && setMultidiaOpen(null)}
        title="Planificar OT en varios dias"
      >
        <div className="space-y-3 text-sm">
          {(() => {
            const ot = multidiaOpen ? otsById.get(multidiaOpen) : null
            return ot ? (
              <div className="rounded border bg-gray-50 p-2 text-xs">
                <div className="font-mono text-gray-500">{excelCodigoFromFolio(ot.folio)}</div>
                <div className="text-gray-900 mt-0.5">{ot.titulo}</div>
              </div>
            ) : null
          })()}

          <div>
            <label className="text-xs text-gray-600 mb-1 block">Selecciona los dias de la semana</label>
            <div className="grid grid-cols-2 gap-1">
              {(dias ?? []).map((d) => {
                const checked = multidiaFechas.includes(d.fecha)
                return (
                  <label key={d.id}
                    className={`flex items-center gap-2 rounded border px-2 py-1.5 cursor-pointer ${
                      checked ? 'border-amber-400 bg-amber-50' : 'border-gray-200 bg-white'
                    }`}>
                    <input type="checkbox" checked={checked}
                      onChange={(e) => {
                        if (e.target.checked) setMultidiaFechas((prev) => [...prev, d.fecha])
                        else setMultidiaFechas((prev) => prev.filter((f) => f !== d.fecha))
                      }}
                    />
                    <span className="text-xs">
                      <strong>{d.nombre_dia}</strong> <span className="text-gray-500 font-mono">{d.fecha}</span>
                    </span>
                  </label>
                )
              })}
            </div>
          </div>

          <div className="grid grid-cols-2 gap-2">
            <div>
              <label className="text-xs text-gray-600">Horas/jornada</label>
              <input type="number" min={0} step={0.5} value={multidiaHoras}
                onChange={(e) => setMultidiaHoras(e.target.value)}
                className="mt-1 w-full rounded border border-gray-300 px-3 py-2 text-sm" />
            </div>
            <div>
              <label className="text-xs text-gray-600">Avance objetivo %</label>
              <input type="number" min={0} max={100} value={multidiaAvance}
                onChange={(e) => setMultidiaAvance(e.target.value)}
                className="mt-1 w-full rounded border border-gray-300 px-3 py-2 text-sm" />
            </div>
          </div>

          <div>
            <label className="text-xs text-gray-600">Responsable</label>
            <select value={multidiaResp} onChange={(e) => setMultidiaResp(e.target.value)}
              className="mt-1 w-full rounded border border-gray-300 px-3 py-2 text-sm">
              <option value="">Sin asignar</option>
              {(usuarios ?? []).map((u) => (
                <option key={u.id} value={u.id}>{u.nombre_completo || u.email}</option>
              ))}
            </select>
          </div>

          <div>
            <label className="text-xs text-gray-600">Comentario</label>
            <textarea rows={2} value={multidiaComentario}
              onChange={(e) => setMultidiaComentario(e.target.value)}
              className="mt-1 w-full rounded border border-gray-300 px-3 py-2 text-sm"
              placeholder="Ej: tarea continua, jornada matinal..." />
          </div>

          <p className="text-[11px] text-gray-500">
            Se creara una jornada por cada dia seleccionado ({multidiaFechas.length} jornada{multidiaFechas.length === 1 ? '' : 's'}).
          </p>
        </div>
        <ModalFooter className="-mx-6 -mb-6 mt-4 px-6 pb-6 pt-4 border-t border-gray-100">
          <Button variant="secondary" onClick={() => setMultidiaOpen(null)} disabled={agregarJornada.isPending}>
            <X className="h-4 w-4" /> Cancelar
          </Button>
          <Button variant="primary" onClick={guardarMultidia} loading={agregarJornada.isPending}
            disabled={multidiaFechas.length === 0}>
            <CalendarPlus className="h-4 w-4" /> Crear jornadas
          </Button>
        </ModalFooter>
      </Modal>

      {/* Modal: reprogramar saldo */}
      <Modal
        open={!!reprogramarOpen}
        onClose={() => !reprogramarSaldo.isPending && setReprogramarOpen(null)}
        title="Reprogramar saldo de OT"
      >
        <div className="space-y-3 text-sm">
          {(() => {
            const planOt = reprogramarOpen ? (planOts ?? []).find((p) => p.id === reprogramarOpen) : null
            const ot = planOt ? otsById.get(planOt.ot_id) : null
            const avanceReal = ot ? Number(ot.avance_pct ?? 0) : 0
            return ot ? (
              <div className="rounded border bg-gray-50 p-2 text-xs">
                <div className="font-mono text-gray-500">{excelCodigoFromFolio(ot.folio)}</div>
                <div className="text-gray-900 mt-0.5">{ot.titulo}</div>
                <div className="mt-1 text-gray-600">
                  Avance actual: <strong>{avanceReal.toFixed(0)}%</strong> · Saldo: <strong>{(100 - avanceReal).toFixed(0)}%</strong>
                </div>
              </div>
            ) : null
          })()}

          <div>
            <label className="text-xs text-gray-600">Fecha destino</label>
            <select value={reprogramarFecha} onChange={(e) => setReprogramarFecha(e.target.value)}
              className="mt-1 w-full rounded border border-gray-300 px-3 py-2 text-sm">
              <option value="">— Selecciona dia —</option>
              {(dias ?? []).map((d) => (
                <option key={d.id} value={d.fecha}>{d.nombre_dia} {d.fecha}</option>
              ))}
            </select>
          </div>

          <div>
            <label className="text-xs text-gray-600">Responsable</label>
            <select value={reprogramarResp} onChange={(e) => setReprogramarResp(e.target.value)}
              className="mt-1 w-full rounded border border-gray-300 px-3 py-2 text-sm">
              <option value="">Sin asignar</option>
              {(usuarios ?? []).map((u) => (
                <option key={u.id} value={u.id}>{u.nombre_completo || u.email}</option>
              ))}
            </select>
          </div>

          <div className="grid grid-cols-2 gap-2">
            <div>
              <label className="text-xs text-gray-600">Horas planificadas</label>
              <input type="number" min={0} step={0.5} value={reprogramarHoras}
                onChange={(e) => setReprogramarHoras(e.target.value)}
                className="mt-1 w-full rounded border border-gray-300 px-3 py-2 text-sm" />
            </div>
            <div>
              <label className="text-xs text-gray-600">Avance objetivo %</label>
              <input type="number" min={0} max={100} value={reprogramarAvance}
                onChange={(e) => setReprogramarAvance(e.target.value)}
                className="mt-1 w-full rounded border border-gray-300 px-3 py-2 text-sm" />
            </div>
          </div>

          <div>
            <label className="text-xs text-gray-600">Motivo (obligatorio)</label>
            <textarea rows={2} value={reprogramarMotivo}
              onChange={(e) => setReprogramarMotivo(e.target.value)}
              className="mt-1 w-full rounded border border-purple-300 px-3 py-2 text-sm"
              placeholder="Ej: avance parcial por falta de material, condicion climatica..." />
          </div>
        </div>
        <ModalFooter className="-mx-6 -mb-6 mt-4 px-6 pb-6 pt-4 border-t border-gray-100">
          <Button variant="secondary" onClick={() => setReprogramarOpen(null)} disabled={reprogramarSaldo.isPending}>
            <X className="h-4 w-4" /> Cancelar
          </Button>
          <Button variant="primary" onClick={guardarReprogramar} loading={reprogramarSaldo.isPending}
            disabled={!reprogramarFecha || !reprogramarMotivo.trim()}>
            <Repeat className="h-4 w-4" /> Reprogramar
          </Button>
        </ModalFooter>
      </Modal>

      {/* Modal: Sacar del programa (desprogramar) */}
      <Modal open={!!sacarOpen} onClose={() => !desprogramar.isPending && setSacarOpen(null)} title="Sacar jornada del programa">
        <div className="space-y-3 text-sm">
          <p className="text-xs text-gray-600">
            Saca la jornada del Kanban activo. Elige si vuelve al backlog (eliminada del plan), si queda
            en cola de reprogramación o simplemente desprogramada.
          </p>
          <div>
            <label className="text-xs text-gray-600">Destino</label>
            <select value={sacarDestino} onChange={(e) => setSacarDestino(e.target.value as typeof sacarDestino)}
              className="mt-1 w-full rounded border border-gray-300 px-3 py-2 text-sm">
              <option value="desprogramada">Desprogramada (oculta del Kanban)</option>
              <option value="requiere_reprogramacion">Requiere reprogramación (visible con badge)</option>
              <option value="backlog">Volver al backlog (elimina jornada)</option>
            </select>
          </div>
          <div>
            <label className="text-xs text-gray-600">Motivo *</label>
            <input value={sacarMotivo} onChange={(e) => setSacarMotivo(e.target.value)}
              placeholder="Ej: cambio de prioridad, falta de material..."
              className="mt-1 w-full rounded border border-orange-300 px-3 py-2 text-sm" />
          </div>
          <div>
            <label className="text-xs text-gray-600">Observación</label>
            <textarea rows={2} value={sacarObs} onChange={(e) => setSacarObs(e.target.value)}
              className="mt-1 w-full rounded border border-gray-300 px-3 py-2 text-sm" />
          </div>
        </div>
        <ModalFooter className="-mx-6 -mb-6 mt-4 px-6 pb-6 pt-4 border-t border-gray-100">
          <Button variant="secondary" onClick={() => setSacarOpen(null)} disabled={desprogramar.isPending}>
            <X className="h-4 w-4" /> Cancelar
          </Button>
          <Button variant="primary" onClick={guardarSacar} loading={desprogramar.isPending} disabled={!sacarMotivo.trim()}>
            <Eraser className="h-4 w-4" /> Sacar del programa
          </Button>
        </ModalFooter>
      </Modal>

      {/* Modal: Cancelar jornada */}
      <Modal open={!!cancelarOpen} onClose={() => !cancelar.isPending && setCancelarOpen(null)} title="Cancelar jornada">
        <div className="space-y-3 text-sm">
          <p className="text-xs text-gray-600">
            Marca la jornada como cancelada. La OT no se elimina; queda registro auditable y la
            ejecución activa se cierra.
          </p>
          <div>
            <label className="text-xs text-gray-600">Tipo</label>
            <select value={cancelarTipo} onChange={(e) => setCancelarTipo(e.target.value as typeof cancelarTipo)}
              className="mt-1 w-full rounded border border-gray-300 px-3 py-2 text-sm">
              <option value="operacional">Operacional</option>
              <option value="prueba">Prueba</option>
              <option value="mandante">Mandante</option>
              <option value="clima">Clima</option>
              <option value="otro">Otro</option>
            </select>
          </div>
          <div>
            <label className="text-xs text-gray-600">Motivo *</label>
            <input value={cancelarMotivo} onChange={(e) => setCancelarMotivo(e.target.value)}
              className="mt-1 w-full rounded border border-orange-300 px-3 py-2 text-sm" />
          </div>
          <div>
            <label className="text-xs text-gray-600">Observación</label>
            <textarea rows={2} value={cancelarObs} onChange={(e) => setCancelarObs(e.target.value)}
              className="mt-1 w-full rounded border border-gray-300 px-3 py-2 text-sm" />
          </div>
        </div>
        <ModalFooter className="-mx-6 -mb-6 mt-4 px-6 pb-6 pt-4 border-t border-gray-100">
          <Button variant="secondary" onClick={() => setCancelarOpen(null)} disabled={cancelar.isPending}>
            <X className="h-4 w-4" /> Cancelar
          </Button>
          <Button variant="primary" onClick={guardarCancelar} loading={cancelar.isPending} disabled={!cancelarMotivo.trim()}>
            <Ban className="h-4 w-4" /> Cancelar jornada
          </Button>
        </ModalFooter>
      </Modal>

      {/* Modal: Resetear prueba (admin) */}
      <Modal open={!!resetearOpen} onClose={() => !resetearPrueba.isPending && setResetearOpen(null)} title="Resetear jornada de prueba">
        <div className="space-y-3 text-sm">
          <div className="rounded border border-yellow-300 bg-yellow-50 p-2 text-xs text-yellow-900">
            <strong>⚠ Solo para datos de prueba.</strong> Esta acción detiene cualquier ejecución activa,
            limpia llegada/foto antes y marca la jornada como prueba. NO afecta firmas reales del mandante.
          </div>
          <div>
            <label className="text-xs text-gray-600">Modo</label>
            <select value={resetearModo} onChange={(e) => setResetearModo(e.target.value as typeof resetearModo)}
              className="mt-1 w-full rounded border border-gray-300 px-3 py-2 text-sm">
              <option value="mantener_programada">Resetear y mantener programada</option>
              <option value="devolver_backlog">Resetear y devolver al backlog</option>
              <option value="desprogramar">Resetear y desprogramar (oculta)</option>
              <option value="eliminar_logico">Eliminar lógicamente (anulada_prueba)</option>
            </select>
          </div>
          <div>
            <label className="text-xs text-gray-600">Motivo *</label>
            <input value={resetearMotivo} onChange={(e) => setResetearMotivo(e.target.value)}
              placeholder="Ej: prueba terreno admin, datos de demo..."
              className="mt-1 w-full rounded border border-yellow-300 px-3 py-2 text-sm" />
          </div>
          <div>
            <label className="text-xs text-gray-600">Confirmación: escribe <strong>RESET</strong></label>
            <input value={resetearConfirm} onChange={(e) => setResetearConfirm(e.target.value)}
              className="mt-1 w-full rounded border border-yellow-400 px-3 py-2 text-sm font-mono" />
          </div>
        </div>
        <ModalFooter className="-mx-6 -mb-6 mt-4 px-6 pb-6 pt-4 border-t border-gray-100">
          <Button variant="secondary" onClick={() => setResetearOpen(null)} disabled={resetearPrueba.isPending}>
            <X className="h-4 w-4" /> Cancelar
          </Button>
          <Button variant="primary" onClick={guardarResetear} loading={resetearPrueba.isPending}
            disabled={!resetearMotivo.trim() || resetearConfirm !== 'RESET'}>
            Resetear
          </Button>
        </ModalFooter>
      </Modal>

      {/* Modal: Eliminar prueba (admin, fuerte) */}
      <Modal open={!!eliminarOpen} onClose={() => !eliminarPrueba.isPending && setEliminarOpen(null)} title="Eliminar jornada (irreversible)">
        <div className="space-y-3 text-sm">
          <div className="rounded border border-red-300 bg-red-50 p-2 text-xs text-red-900">
            <strong>⚠ Acción irreversible.</strong> La jornada se borra fisicamente. Solo permitido si NO
            tiene firma de mandante real. Usa Reset prueba si solo quieres limpiar datos.
          </div>
          <div>
            <label className="text-xs text-gray-600">Motivo *</label>
            <input value={eliminarMotivo} onChange={(e) => setEliminarMotivo(e.target.value)}
              className="mt-1 w-full rounded border border-red-300 px-3 py-2 text-sm" />
          </div>
          <div>
            <label className="text-xs text-gray-600">Confirmación: escribe <strong>ELIMINAR</strong></label>
            <input value={eliminarConfirm} onChange={(e) => setEliminarConfirm(e.target.value)}
              className="mt-1 w-full rounded border border-red-400 px-3 py-2 text-sm font-mono" />
          </div>
        </div>
        <ModalFooter className="-mx-6 -mb-6 mt-4 px-6 pb-6 pt-4 border-t border-gray-100">
          <Button variant="secondary" onClick={() => setEliminarOpen(null)} disabled={eliminarPrueba.isPending}>
            <X className="h-4 w-4" /> Cancelar
          </Button>
          <Button variant="primary" onClick={guardarEliminar} loading={eliminarPrueba.isPending}
            disabled={!eliminarMotivo.trim() || eliminarConfirm !== 'ELIMINAR'}>
            <Trash2 className="h-4 w-4" /> Eliminar definitivamente
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
  ot, dragId, compact, responsableId, comentario, usuarios, disabled,
  estadoPlan, requiereDecision,
  onAsignar, onQuitar, onComentar, onActualizarAvance,
  onPlanificarVariosDias, onReprogramarSaldo,
  onSacar, onCancelar, onResetearPrueba, onEliminarPrueba,
}: {
  ot: CalamaOTConRelaciones
  dragId: string
  compact?: boolean
  responsableId?: string | null
  comentario?: string | null
  usuarios?: Array<{ id: string; nombre_completo: string | null; email?: string | null; cargo?: string | null }>
  disabled?: boolean
  estadoPlan?: string | null
  requiereDecision?: boolean
  onAsignar?: (uid: string) => void
  onQuitar?: () => void
  onComentar?: () => void
  onActualizarAvance?: () => void
  onPlanificarVariosDias?: () => void
  onReprogramarSaldo?: () => void
  onSacar?: () => void
  onCancelar?: () => void
  onResetearPrueba?: () => void
  onEliminarPrueba?: () => void
}) {
  const { attributes, listeners, setNodeRef, isDragging } = useDraggable({ id: dragId, disabled })
  return (
    <div ref={setNodeRef} {...attributes} {...listeners}
      className={`${isDragging ? 'opacity-30' : ''} ${disabled ? 'cursor-not-allowed' : 'cursor-grab active:cursor-grabbing'}`}
    >
      <OTCardContent
        ot={ot} compact={compact}
        responsableId={responsableId} comentario={comentario}
        usuarios={usuarios}
        estadoPlan={estadoPlan} requiereDecision={requiereDecision}
        onAsignar={onAsignar} onQuitar={onQuitar} onComentar={onComentar}
        onActualizarAvance={onActualizarAvance}
        onPlanificarVariosDias={onPlanificarVariosDias}
        onReprogramarSaldo={onReprogramarSaldo}
        onSacar={onSacar} onCancelar={onCancelar}
        onResetearPrueba={onResetearPrueba} onEliminarPrueba={onEliminarPrueba}
        disabled={disabled}
      />
    </div>
  )
}

function OTCardContent({
  ot, compact, responsableId, comentario, usuarios,
  estadoPlan, requiereDecision,
  onAsignar, onQuitar, onComentar, onActualizarAvance,
  onPlanificarVariosDias, onReprogramarSaldo,
  onSacar, onCancelar, onResetearPrueba, onEliminarPrueba,
  disabled,
}: {
  ot: CalamaOTConRelaciones
  compact?: boolean
  responsableId?: string | null
  comentario?: string | null
  usuarios?: Array<{ id: string; nombre_completo: string | null; email?: string | null; cargo?: string | null }>
  estadoPlan?: string | null
  requiereDecision?: boolean
  onAsignar?: (uid: string) => void
  onQuitar?: () => void
  onComentar?: () => void
  onActualizarAvance?: () => void
  onPlanificarVariosDias?: () => void
  onReprogramarSaldo?: () => void
  onSacar?: () => void
  onCancelar?: () => void
  onResetearPrueba?: () => void
  onEliminarPrueba?: () => void
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
          <div className="mt-1.5 flex items-center gap-1">
            <select
              value={responsableId ?? ''}
              onChange={(e) => e.target.value && onAsignar(e.target.value)}
              onPointerDown={(e) => e.stopPropagation()}
              onPointerUp={(e) => e.stopPropagation()}
              disabled={disabled}
              className={`flex-1 rounded border px-1.5 py-1 text-[10px] bg-white ${
                responsableId ? 'border-green-300 ring-1 ring-green-100' : 'border-gray-200'
              }`}
              title={responsableId ? 'Responsable asignado (auto-guardado)' : 'Selecciona un responsable'}
            >
              <option value="">Asignar responsable…</option>
              {usuarios.map((u) => (
                <option key={u.id} value={u.id}>
                  {u.nombre_completo || u.email || `(${u.id.slice(0, 6)})`}
                  {u.cargo ? ` — ${u.cargo}` : ''}
                </option>
              ))}
            </select>
            {responsableId && (
              <CheckCircle2 className="h-3 w-3 text-green-600 shrink-0" aria-label="guardado" />
            )}
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
          {onPlanificarVariosDias && (
            <button
              onClick={(e) => { e.stopPropagation(); onPlanificarVariosDias() }}
              onPointerDown={(e) => e.stopPropagation()}
              disabled={disabled}
              className="inline-flex items-center justify-center gap-1 rounded border border-blue-200 bg-blue-50 px-2 py-0.5 text-[10px] text-blue-700 hover:bg-blue-100 disabled:opacity-40"
              title="Planificar varios dias"
            >
              <CalendarPlus className="h-3 w-3" /> Dias
            </button>
          )}
          {onReprogramarSaldo && (
            <button
              onClick={(e) => { e.stopPropagation(); onReprogramarSaldo() }}
              onPointerDown={(e) => e.stopPropagation()}
              disabled={disabled}
              className="inline-flex items-center justify-center gap-1 rounded border border-purple-200 bg-purple-50 px-2 py-0.5 text-[10px] text-purple-700 hover:bg-purple-100 disabled:opacity-40"
              title="Reprogramar saldo"
            >
              <Repeat className="h-3 w-3" />
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

        {/* Badge "requiere decisión" cuando aplica */}
        {(requiereDecision || estadoPlan === 'pausada' || estadoPlan === 'rechazada') && (
          <div className="mt-1.5 rounded border border-orange-200 bg-orange-50 px-1.5 py-1 text-[10px] text-orange-800 inline-flex items-center gap-1">
            <ShieldAlert className="h-3 w-3" />
            Requiere decisión del programador
          </div>
        )}

        {/* Acciones admin (sacar / cancelar / resetear / eliminar) */}
        {(onSacar || onCancelar || onResetearPrueba || onEliminarPrueba) && (
          <details className="mt-1.5">
            <summary className="cursor-pointer text-[10px] font-medium text-gray-600 hover:text-gray-800">
              Acciones
            </summary>
            <div className="mt-1 grid grid-cols-2 gap-1">
              {onSacar && (
                <button
                  onClick={(e) => { e.stopPropagation(); onSacar() }}
                  onPointerDown={(e) => e.stopPropagation()}
                  className="rounded border border-orange-200 bg-orange-50 px-2 py-1 text-[10px] text-orange-800 hover:bg-orange-100 inline-flex items-center justify-center gap-1"
                >
                  <Eraser className="h-3 w-3" /> Sacar
                </button>
              )}
              {onCancelar && (
                <button
                  onClick={(e) => { e.stopPropagation(); onCancelar() }}
                  onPointerDown={(e) => e.stopPropagation()}
                  className="rounded border border-gray-200 bg-gray-50 px-2 py-1 text-[10px] text-gray-800 hover:bg-gray-100 inline-flex items-center justify-center gap-1"
                >
                  <Ban className="h-3 w-3" /> Cancelar
                </button>
              )}
              {onResetearPrueba && (
                <button
                  onClick={(e) => { e.stopPropagation(); onResetearPrueba() }}
                  onPointerDown={(e) => e.stopPropagation()}
                  className="rounded border border-yellow-300 bg-yellow-50 px-2 py-1 text-[10px] text-yellow-900 hover:bg-yellow-100 inline-flex items-center justify-center gap-1"
                  title="Solo admin global"
                >
                  Reset prueba
                </button>
              )}
              {onEliminarPrueba && (
                <button
                  onClick={(e) => { e.stopPropagation(); onEliminarPrueba() }}
                  onPointerDown={(e) => e.stopPropagation()}
                  className="rounded border border-red-300 bg-red-50 px-2 py-1 text-[10px] text-red-800 hover:bg-red-100 inline-flex items-center justify-center gap-1"
                  title="Solo admin global - sin firma mandante"
                >
                  Eliminar
                </button>
              )}
            </div>
          </details>
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
