'use client'

import { useState, useMemo, useEffect, useCallback } from 'react'
import { useQuery } from '@tanstack/react-query'
import { useRouter } from 'next/navigation'
import {
  Wrench,
  Calendar,
  CalendarDays,
  AlertTriangle,
  Clock,
  CheckCircle2,
  ChevronDown,
  ChevronUp,
  ChevronLeft,
  ChevronRight,
  Play,
  Package,
  Plus,
  X,
} from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { StatCard } from '@/components/ui/stat-card'
import { Spinner } from '@/components/ui/spinner'
import { EmptyState } from '@/components/ui/empty-state'
import { Select } from '@/components/ui/select'
import {
  Table,
  TableHeader,
  TableBody,
  TableRow,
  TableHead,
  TableCell,
} from '@/components/ui/table'
import { formatDate } from '@/lib/utils'
import { getFaenas } from '@/lib/services/faenas'
import { getContratoParaFaena } from '@/lib/services/mantenimiento'
import {
  usePlanes,
  useMantenimientosVencidos,
  usePautasFabricante,
  useProximasMantenimientos,
  useGenerarOTDesdePlan,
} from '@/hooks/use-mantenimiento'
import { useOrdenesTrabajo } from '@/hooks/use-ordenes-trabajo'
import { CrearOTModal } from '@/components/ot/crear-ot-modal'

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function diasHasta(fecha: string): number {
  const hoy = new Date()
  hoy.setHours(0, 0, 0, 0)
  const target = new Date(fecha)
  target.setHours(0, 0, 0, 0)
  return Math.ceil((target.getTime() - hoy.getTime()) / (1000 * 60 * 60 * 24))
}

function semaforoColor(fecha: string): 'green' | 'yellow' | 'red' {
  const d = diasHasta(fecha)
  if (d < 0) return 'red'
  if (d <= 7) return 'yellow'
  return 'green'
}

const semaforoDot: Record<string, string> = {
  green: 'bg-green-500',
  yellow: 'bg-yellow-500',
  red: 'bg-red-500',
}

const semaforoTextColor: Record<string, string> = {
  green: 'text-green-700',
  yellow: 'text-yellow-700',
  red: 'text-red-700 font-bold',
}

function tipoPlanLabel(tipo: string): string {
  const map: Record<string, string> = {
    por_tiempo: 'Por tiempo',
    por_km: 'Por km',
    por_horas: 'Por horas',
    por_ciclos: 'Por ciclos',
  }
  return map[tipo] || tipo
}

function frecuenciaLabel(pauta: any): string {
  if (!pauta) return '-'
  if (pauta.frecuencia_dias) return `Cada ${pauta.frecuencia_dias} dias`
  if (pauta.frecuencia_km) return `Cada ${pauta.frecuencia_km.toLocaleString('es-CL')} km`
  if (pauta.frecuencia_horas) return `Cada ${pauta.frecuencia_horas} hrs`
  if (pauta.frecuencia_ciclos) return `Cada ${pauta.frecuencia_ciclos} ciclos`
  return '-'
}

const DIAS_SEMANA = ['Domingo', 'Lunes', 'Martes', 'Miercoles', 'Jueves', 'Viernes', 'Sabado']
const DIAS_CORTO = ['Dom', 'Lun', 'Mar', 'Mie', 'Jue', 'Vie', 'Sab']

function getNext7Days(): { date: string; dayName: string; dayShort: string; dateObj: Date }[] {
  const days = []
  const hoy = new Date()
  hoy.setHours(0, 0, 0, 0)
  for (let i = 0; i < 7; i++) {
    const d = new Date(hoy.getTime() + i * 24 * 60 * 60 * 1000)
    const iso = d.toISOString().slice(0, 10)
    days.push({
      date: iso,
      dayName: DIAS_SEMANA[d.getDay()],
      dayShort: DIAS_CORTO[d.getDay()],
      dateObj: d,
    })
  }
  return days
}

// Week range helper for the new PlanSemanalTab
function getWeekRange(offset: number) {
  const now = new Date()
  const dayOfWeek = now.getDay() // 0=Sunday
  const monday = new Date(now)
  // getDay() returns 0 for Sunday, so adjust: if Sunday (0), go back 6 days
  monday.setDate(now.getDate() - (dayOfWeek === 0 ? 6 : dayOfWeek - 1) + offset * 7)
  monday.setHours(0, 0, 0, 0)
  const sunday = new Date(monday)
  sunday.setDate(monday.getDate() + 6)
  sunday.setHours(23, 59, 59, 999)

  const days: Date[] = []
  for (let i = 0; i < 7; i++) {
    const d = new Date(monday)
    d.setDate(monday.getDate() + i)
    days.push(d)
  }
  return { monday, sunday, days }
}

const dayNames = ['Lunes', 'Martes', 'Miercoles', 'Jueves', 'Viernes', 'Sabado', 'Domingo']

const tipoBadgeColor: Record<string, string> = {
  preventivo: 'bg-green-100 text-green-700',
  correctivo: 'bg-red-100 text-red-700',
  inspeccion: 'bg-blue-100 text-blue-700',
  abastecimiento: 'bg-amber-100 text-amber-700',
  lubricacion: 'bg-purple-100 text-purple-700',
  inventario: 'bg-cyan-100 text-cyan-700',
  regularizacion: 'bg-gray-100 text-gray-700',
}

const estadoBadgeColor: Record<string, string> = {
  creada: 'bg-violet-100 text-violet-700',
  asignada: 'bg-blue-100 text-blue-700',
  en_ejecucion: 'bg-amber-100 text-amber-700',
  pausada: 'bg-orange-100 text-orange-700',
  ejecutada_ok: 'bg-green-100 text-green-700',
  ejecutada_con_observaciones: 'bg-emerald-100 text-emerald-700',
  no_ejecutada: 'bg-red-100 text-red-700',
  cancelada: 'bg-gray-100 text-gray-700',
}

const prioridadBadgeColor: Record<string, string> = {
  emergencia: 'bg-red-100 text-red-700',
  urgente: 'bg-orange-100 text-orange-700',
  alta: 'bg-amber-100 text-amber-700',
  normal: 'bg-blue-100 text-blue-700',
  baja: 'bg-gray-100 text-gray-600',
}

function formatDateShort(d: Date): string {
  return d.toLocaleDateString('es-CL', { day: '2-digit', month: 'short' })
}

function toISODate(d: Date): string {
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, '0')
  const day = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${day}`
}

// ---------------------------------------------------------------------------
// Tabs definition
// ---------------------------------------------------------------------------
const tabs = [
  { id: 'semanal', label: 'Plan Semanal', icon: CalendarDays },
  { id: 'calendario', label: 'Calendario PM', icon: Calendar },
  { id: 'vencidos', label: 'Vencidos', icon: AlertTriangle },
  { id: 'pautas', label: 'Pautas del Fabricante', icon: Wrench },
]

// ---------------------------------------------------------------------------
// PlanCard - reusable card for a maintenance plan
// ---------------------------------------------------------------------------
function PlanCard({ plan }: { plan: any }) {
  const activo = plan.activo
  const pauta = plan.pauta
  const color = plan.proxima_ejecucion_fecha
    ? semaforoColor(plan.proxima_ejecucion_fecha)
    : 'green'

  const marcaModelo = activo?.modelo
    ? `${activo.modelo.marca?.nombre ?? ''} - ${activo.modelo.nombre}`
    : '-'

  return (
    <Card className="overflow-hidden">
      <CardContent className="p-4">
        <div className="flex gap-3">
          {/* Semaforo dot */}
          <div className="flex flex-col items-center pt-1">
            <span className={`inline-block h-3 w-3 rounded-full ${semaforoDot[color]}`} />
          </div>

          {/* Content */}
          <div className="flex-1 min-w-0">
            {/* Row 1: Activo */}
            <div className="flex flex-wrap items-center gap-2">
              <span className="font-semibold text-gray-900">
                {activo?.codigo ?? '-'}
              </span>
              <span className="text-gray-600 truncate">
                {activo?.nombre ?? ''}
              </span>
              {activo?.tipo && (
                <Badge variant="default" className="text-[10px]">
                  {activo.tipo.replace(/_/g, ' ')}
                </Badge>
              )}
            </div>

            {/* Row 2: Marca - Modelo */}
            <p className="text-sm text-gray-500 mt-0.5">{marcaModelo}</p>

            {/* Row 3: Pauta */}
            <div className="flex flex-wrap items-center gap-2 mt-1.5">
              <span className="text-sm font-medium text-gray-700">
                {pauta?.nombre ?? '-'}
              </span>
              {pauta?.tipo_plan && (
                <Badge variant="secondary" className="text-[10px]">
                  {tipoPlanLabel(pauta.tipo_plan)}
                </Badge>
              )}
            </div>

            {/* Row 4: Frecuencia */}
            <p className="text-xs text-gray-500 mt-1">
              <Clock className="inline h-3 w-3 mr-1 -mt-0.5" />
              Frecuencia: {frecuenciaLabel(pauta)}
            </p>

            {/* Row 5: Dates */}
            <div className="flex flex-wrap gap-x-6 gap-y-1 mt-2 text-sm">
              <div>
                <span className="text-gray-400">Ultima ejecucion: </span>
                <span className="text-gray-700">
                  {plan.ultima_ejecucion_fecha
                    ? formatDate(plan.ultima_ejecucion_fecha)
                    : 'Sin registro'}
                </span>
              </div>
              <div>
                <span className="text-gray-400">Proxima: </span>
                <span className={semaforoTextColor[color]}>
                  {plan.proxima_ejecucion_fecha
                    ? formatDate(plan.proxima_ejecucion_fecha)
                    : '-'}
                </span>
                {plan.proxima_ejecucion_fecha && (
                  <span className={`ml-1 text-xs ${semaforoTextColor[color]}`}>
                    ({diasHasta(plan.proxima_ejecucion_fecha) < 0
                      ? `${Math.abs(diasHasta(plan.proxima_ejecucion_fecha))}d vencido`
                      : `en ${diasHasta(plan.proxima_ejecucion_fecha)}d`})
                  </span>
                )}
              </div>
            </div>

            {/* Row 6: Faena */}
            {activo?.faena?.nombre && (
              <p className="text-xs text-gray-400 mt-1.5">
                Faena: {activo.faena.nombre}
              </p>
            )}
          </div>
        </div>
      </CardContent>
    </Card>
  )
}

// ---------------------------------------------------------------------------
// PautaRow - expandable row for pautas table
// ---------------------------------------------------------------------------
function PautaRow({ pauta }: { pauta: any }) {
  const [expanded, setExpanded] = useState(false)

  const marcaModelo = pauta.modelo
    ? `${pauta.modelo.marca?.nombre ?? ''} - ${pauta.modelo.nombre}`
    : '-'

  const checklistCount = pauta.checklist_items
    ? (Array.isArray(pauta.checklist_items)
        ? pauta.checklist_items.length
        : 0)
    : 0

  return (
    <>
      <TableRow
        className="cursor-pointer"
        onClick={() => setExpanded(!expanded)}
      >
        <TableCell className="font-medium">{marcaModelo}</TableCell>
        <TableCell>{pauta.nombre}</TableCell>
        <TableCell>
          {pauta.tipo_plan && (
            <Badge variant="secondary" className="text-[10px]">
              {tipoPlanLabel(pauta.tipo_plan)}
            </Badge>
          )}
        </TableCell>
        <TableCell className="whitespace-nowrap">{frecuenciaLabel(pauta)}</TableCell>
        <TableCell className="text-center">
          {pauta.duracion_estimada_hrs ? `${pauta.duracion_estimada_hrs} hrs` : '-'}
        </TableCell>
        <TableCell className="text-center">{checklistCount}</TableCell>
        <TableCell className="text-center">
          {expanded ? (
            <ChevronUp className="inline h-4 w-4 text-gray-400" />
          ) : (
            <ChevronDown className="inline h-4 w-4 text-gray-400" />
          )}
        </TableCell>
      </TableRow>
      {expanded && (
        <TableRow>
          <TableCell colSpan={7} className="bg-gray-50 px-8 py-4">
            {checklistCount > 0 ? (
              <div>
                <p className="text-xs font-semibold text-gray-500 uppercase mb-2">
                  Items del checklist
                </p>
                <ul className="space-y-1">
                  {(pauta.checklist_items as any[]).map((item: any, i: number) => (
                    <li key={i} className="flex items-center gap-2 text-sm text-gray-700">
                      <CheckCircle2 className="h-3.5 w-3.5 text-pillado-green-500 shrink-0" />
                      {typeof item === 'string' ? item : item.descripcion ?? item.nombre ?? JSON.stringify(item)}
                    </li>
                  ))}
                </ul>
              </div>
            ) : (
              <p className="text-sm text-gray-400 italic">
                No hay items de checklist definidos para esta pauta.
              </p>
            )}
            {pauta.materiales_estimados && Array.isArray(pauta.materiales_estimados) && pauta.materiales_estimados.length > 0 && (
              <div className="mt-3">
                <p className="text-xs font-semibold text-gray-500 uppercase mb-2">
                  Materiales estimados
                </p>
                <ul className="space-y-1">
                  {(pauta.materiales_estimados as any[]).map((mat: any, i: number) => (
                    <li key={i} className="text-sm text-gray-700">
                      {typeof mat === 'string' ? mat : mat.nombre ?? JSON.stringify(mat)}
                      {mat.cantidad ? ` (x${mat.cantidad})` : ''}
                    </li>
                  ))}
                </ul>
              </div>
            )}
          </TableCell>
        </TableRow>
      )}
    </>
  )
}

// ---------------------------------------------------------------------------
// Main Page
// ---------------------------------------------------------------------------
export default function MantenimientoPage() {
  const [activeTab, setActiveTab] = useState('semanal')
  const [faenaFilter, setFaenaFilter] = useState('')

  // Data
  const planesFilters = useMemo(
    () => (faenaFilter ? { faena_id: faenaFilter } : undefined),
    [faenaFilter]
  )
  const { data: planes, isLoading: loadingPlanes } = usePlanes(planesFilters)
  const { data: vencidos, isLoading: loadingVencidos } = useMantenimientosVencidos()
  const { data: pautas, isLoading: loadingPautas } = usePautasFabricante()

  // Faenas for filter
  const { data: faenas } = useQuery({
    queryKey: ['faenas'],
    queryFn: async () => {
      const { data, error } = await getFaenas()
      if (error) throw error
      return data
    },
  })

  // Stats
  const totalPlanes = planes?.length ?? 0

  const proximas7d = useMemo(() => {
    if (!planes) return 0
    const hoy = new Date()
    hoy.setHours(0, 0, 0, 0)
    const en7 = new Date(hoy.getTime() + 7 * 24 * 60 * 60 * 1000)
    return planes.filter((p: any) => {
      if (!p.proxima_ejecucion_fecha) return false
      const d = new Date(p.proxima_ejecucion_fecha)
      return d >= hoy && d <= en7
    }).length
  }, [planes])

  const totalVencidos = vencidos?.length ?? 0

  const cumplimientoPM = useMemo(() => {
    // Calculated from planes data - percentage of plans that have been executed at least once
    if (!planes || planes.length === 0) return '-'
    const ejecutados = planes.filter(
      (p: any) => p.ultima_ejecucion_fecha != null
    ).length
    return `${Math.round((ejecutados / planes.length) * 100)}%`
  }, [planes])

  const vencidosCount = totalVencidos

  return (
    <div className="space-y-6">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold text-gray-900">
          Mantenimiento Preventivo
        </h1>
        <p className="mt-1 text-sm text-gray-500">
          Planes de mantenimiento, calendario y pautas del fabricante.
        </p>
      </div>

      {/* Stats */}
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <StatCard
          title="Planes activos"
          value={loadingPlanes ? '...' : totalPlanes}
          icon={Wrench}
          color="green"
        />
        <StatCard
          title="Proximas 7 dias"
          value={loadingPlanes ? '...' : proximas7d}
          icon={Calendar}
          color="orange"
        />
        <StatCard
          title="Vencidos"
          value={loadingVencidos ? '...' : totalVencidos}
          icon={AlertTriangle}
          color="red"
        />
        <StatCard
          title="Cumplimiento PM"
          value={loadingPlanes ? '...' : cumplimientoPM}
          icon={CheckCircle2}
          color="blue"
        />
      </div>

      {/* Tabs */}
      <div className="mb-4 flex gap-1 overflow-x-auto rounded-xl bg-gray-100 p-1">
        {tabs.map((tab) => {
          const Icon = tab.icon
          return (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`flex flex-1 items-center justify-center gap-1.5 whitespace-nowrap rounded-lg px-3 py-2 text-sm font-medium transition-colors ${
                activeTab === tab.id
                  ? 'bg-white text-pillado-green-600 shadow-sm'
                  : 'text-gray-500 hover:text-gray-700'
              }`}
            >
              <Icon className="h-4 w-4" />
              {tab.label}
              {tab.id === 'vencidos' && vencidosCount > 0 && (
                <span className="ml-1 inline-flex h-5 min-w-[20px] items-center justify-center rounded-full bg-red-500 px-1.5 text-[10px] font-bold text-white">
                  {vencidosCount}
                </span>
              )}
            </button>
          )
        })}
      </div>

      {/* Tab content */}
      {activeTab === 'semanal' && <PlanSemanalTab />}
      {activeTab === 'calendario' && (
        <CalendarioTab
          planes={planes}
          isLoading={loadingPlanes}
          faenas={faenas}
          faenaFilter={faenaFilter}
          setFaenaFilter={setFaenaFilter}
        />
      )}
      {activeTab === 'vencidos' && (
        <VencidosTab vencidos={vencidos} isLoading={loadingVencidos} />
      )}
      {activeTab === 'pautas' && (
        <PautasTab pautas={pautas} isLoading={loadingPautas} />
      )}
    </div>
  )
}

// ---------------------------------------------------------------------------
// Tab: Plan Semanal (Full Weekly Planner)
// ---------------------------------------------------------------------------
function PlanSemanalTab() {
  const router = useRouter()
  const [weekOffset, setWeekOffset] = useState(0)

  // Week range
  const { monday, sunday, days } = useMemo(() => getWeekRange(weekOffset), [weekOffset])
  const mondayISO = toISODate(monday)
  const sundayISO = toISODate(sunday)

  // Discarded PM suggestions (local state, not persisted)
  const [discarded, setDiscarded] = useState<Set<string>>(new Set())

  // Modal state for creating OT
  const [crearOTModalOpen, setCrearOTModalOpen] = useState(false)
  const [crearOTFechaPre, setCrearOTFechaPre] = useState<string>('')

  // Cache contract id
  const [contratoId, setContratoId] = useState<string | null>(null)
  const [contratoError, setContratoError] = useState(false)

  useEffect(() => {
    getContratoParaFaena('').then(({ data }) => {
      if (data?.id) {
        setContratoId(data.id)
      } else {
        setContratoError(true)
      }
    })
  }, [])

  // PM suggestions: fetch proximas mantenimientos covering the week range
  // Use a generous dias window to cover future weeks
  const diasParaFetch = useMemo(() => {
    const hoy = new Date()
    hoy.setHours(0, 0, 0, 0)
    const diffMs = sunday.getTime() - hoy.getTime()
    const diffDays = Math.ceil(diffMs / (1000 * 60 * 60 * 24))
    return Math.max(diffDays + 1, 7)
  }, [sunday])

  const { data: proximos, isLoading: loadingPM } = useProximasMantenimientos(
    diasParaFetch > 0 ? diasParaFetch : 7
  )

  // OTs for the week
  const otFilters = useMemo(
    () => ({ fecha_desde: mondayISO, fecha_hasta: sundayISO }),
    [mondayISO, sundayISO]
  )
  const { data: weekOTs, isLoading: loadingOTs } = useOrdenesTrabajo(otFilters)

  // Generar OT mutation
  const generarOT = useGenerarOTDesdePlan()
  const [generandoId, setGenerandoId] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [successMsg, setSuccessMsg] = useState<string | null>(null)

  // Filter PM suggestions to the selected week
  const weekPM = useMemo(() => {
    if (!proximos) return []
    return proximos.filter((plan: any) => {
      const fecha = plan.proxima_ejecucion_fecha?.slice(0, 10)
      if (!fecha) return false
      return fecha >= mondayISO && fecha <= sundayISO
    })
  }, [proximos, mondayISO, sundayISO])

  // Set of plan_mantenimiento_ids that already have OTs (accepted suggestions)
  const acceptedPlanIds = useMemo(() => {
    const ids = new Set<string>()
    if (weekOTs) {
      for (const ot of weekOTs) {
        if ((ot as any).plan_mantenimiento_id) {
          ids.add((ot as any).plan_mantenimiento_id)
        }
      }
    }
    return ids
  }, [weekOTs])

  // Group PM suggestions by date
  const pmByDate = useMemo(() => {
    const map: Record<string, any[]> = {}
    for (const day of days) {
      map[toISODate(day)] = []
    }
    for (const plan of weekPM) {
      const fecha = plan.proxima_ejecucion_fecha?.slice(0, 10)
      if (fecha && map[fecha]) {
        map[fecha].push(plan)
      }
    }
    return map
  }, [weekPM, days])

  // Group OTs by date
  const otsByDate = useMemo(() => {
    const map: Record<string, any[]> = {}
    for (const day of days) {
      map[toISODate(day)] = []
    }
    if (weekOTs) {
      for (const ot of weekOTs) {
        const fecha = (ot as any).fecha_programada?.slice(0, 10)
        if (fecha && map[fecha]) {
          map[fecha].push(ot)
        }
      }
    }
    return map
  }, [weekOTs, days])

  // Accept PM suggestion -> create OT
  const handleAceptar = useCallback(
    async (plan: any) => {
      if (!contratoId) {
        setError('No se encontro un contrato activo. No se puede generar la OT.')
        return
      }
      setError(null)
      setSuccessMsg(null)
      setGenerandoId(plan.id)

      try {
        await generarOT.mutateAsync({
          tipo: 'preventivo',
          contrato_id: contratoId,
          faena_id: plan.activo?.faena_id ?? plan.activo?.faena?.id ?? '',
          activo_id: plan.activo?.id ?? '',
          plan_mantenimiento_id: plan.id,
          fecha_programada: plan.proxima_ejecucion_fecha,
          prioridad: 'normal',
        })
        setSuccessMsg(`OT generada para ${plan.activo?.codigo ?? 'activo'} - ${plan.pauta?.nombre ?? 'plan'}`)
      } catch (err: any) {
        setError(err?.message ?? 'Error al generar la OT')
      } finally {
        setGenerandoId(null)
      }
    },
    [contratoId, generarOT]
  )

  // Discard PM suggestion
  const handleDescartar = useCallback((planId: string) => {
    setDiscarded((prev) => {
      const next = new Set(prev)
      next.add(planId)
      return next
    })
  }, [])

  // Open CrearOTModal with a pre-set date
  const handleAgregarOT = useCallback((fecha: string) => {
    setCrearOTFechaPre(fecha)
    setCrearOTModalOpen(true)
  }, [])

  // Today ISO
  const todayISO = useMemo(() => toISODate(new Date()), [])

  // Consolidated materials from PM pautas for the week
  const materialesConsolidados = useMemo(() => {
    const agg: Record<string, { nombre: string; cantidad: number; unidad?: string }> = {}
    for (const plan of weekPM) {
      if (discarded.has(plan.id) || acceptedPlanIds.has(plan.id)) continue
      const materiales = plan.pauta?.materiales_estimados
      if (Array.isArray(materiales)) {
        for (const mat of materiales) {
          const nombre = typeof mat === 'string' ? mat : (mat.nombre ?? JSON.stringify(mat))
          const cantidad = typeof mat === 'object' ? (mat.cantidad ?? 1) : 1
          const unidad = typeof mat === 'object' ? mat.unidad : undefined
          if (agg[nombre]) {
            agg[nombre].cantidad += cantidad
          } else {
            agg[nombre] = { nombre, cantidad, unidad }
          }
        }
      }
    }
    return Object.values(agg).sort((a, b) => a.nombre.localeCompare(b.nombre))
  }, [weekPM, discarded, acceptedPlanIds])

  // Week summary counts
  const weekSummary = useMemo(() => {
    const byTipo: Record<string, number> = {}
    let total = 0
    let completed = 0
    if (weekOTs) {
      for (const ot of weekOTs) {
        const tipo = (ot as any).tipo || 'otro'
        byTipo[tipo] = (byTipo[tipo] || 0) + 1
        total++
        const estado = (ot as any).estado
        if (estado === 'ejecutada_ok' || estado === 'ejecutada_con_observaciones') {
          completed++
        }
      }
    }
    return { byTipo, total, completed }
  }, [weekOTs])

  const isLoading = loadingPM || loadingOTs

  return (
    <div className="space-y-6">
      {/* Week Selector */}
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h2 className="text-lg font-semibold text-gray-900">
            Planificador Semanal
          </h2>
          <p className="text-sm text-gray-500">
            Semana del {formatDateShort(monday)} al {formatDateShort(sunday)}
          </p>
        </div>
        <div className="flex items-center gap-2">
          <Button
            variant="outline"
            size="sm"
            onClick={() => setWeekOffset((o) => o - 1)}
          >
            <ChevronLeft className="h-4 w-4" />
            Anterior
          </Button>
          <Button
            variant={weekOffset === 0 ? 'primary' : 'outline'}
            size="sm"
            onClick={() => setWeekOffset(0)}
          >
            Hoy
          </Button>
          <Button
            variant="outline"
            size="sm"
            onClick={() => setWeekOffset((o) => o + 1)}
          >
            Siguiente
            <ChevronRight className="h-4 w-4" />
          </Button>
        </div>
      </div>

      {/* Messages */}
      {contratoError && (
        <div className="rounded-lg border border-red-200 bg-red-50 px-4 py-3">
          <p className="text-sm text-red-700">
            No se encontro un contrato activo. La generacion de OTs no esta disponible.
          </p>
        </div>
      )}
      {error && (
        <div className="rounded-lg border border-red-200 bg-red-50 px-4 py-3">
          <p className="text-sm text-red-700">{error}</p>
        </div>
      )}
      {successMsg && (
        <div className="rounded-lg border border-green-200 bg-green-50 px-4 py-3">
          <p className="text-sm text-green-700">{successMsg}</p>
        </div>
      )}

      {isLoading ? (
        <div className="flex items-center justify-center py-16">
          <Spinner size="lg" />
        </div>
      ) : (
        <>
          {/* Days of the week */}
          <div className="space-y-4">
            {days.map((dayDate, dayIdx) => {
              const dateISO = toISODate(dayDate)
              const isToday = dateISO === todayISO
              const dayPM = (pmByDate[dateISO] ?? []).filter(
                (p: any) => !discarded.has(p.id)
              )
              const dayOTs = otsByDate[dateISO] ?? []
              const hasPM = dayPM.length > 0
              const hasOTs = dayOTs.length > 0

              return (
                <Card key={dateISO} className={isToday ? 'ring-2 ring-pillado-green-500/50' : ''}>
                  <CardContent className="p-4">
                    {/* Day header */}
                    <div className="flex items-center justify-between mb-3">
                      <div className={`flex items-center gap-2 ${isToday ? 'text-pillado-green-600' : 'text-gray-700'}`}>
                        <CalendarDays className="h-4 w-4" />
                        <span className="font-semibold text-base">
                          {dayNames[dayIdx]}
                        </span>
                        <span className="text-sm text-gray-400">
                          {formatDateShort(dayDate)}
                        </span>
                        {isToday && (
                          <Badge variant="default" className="text-[10px]">
                            Hoy
                          </Badge>
                        )}
                      </div>
                      <div className="flex items-center gap-2 text-xs text-gray-400">
                        {hasPM && (
                          <span>{dayPM.length} sugerencia{dayPM.length !== 1 ? 's' : ''} PM</span>
                        )}
                        {hasOTs && (
                          <span>{dayOTs.length} OT{dayOTs.length !== 1 ? 's' : ''}</span>
                        )}
                      </div>
                    </div>

                    {/* Section A: PM Suggestions */}
                    {hasPM && (
                      <div className="mb-3">
                        <p className="text-xs font-semibold text-gray-500 uppercase mb-2">
                          Sugerencias de Mantenimiento Preventivo
                        </p>
                        <div className="space-y-2">
                          {dayPM.map((plan: any) => {
                            const activo = plan.activo
                            const pauta = plan.pauta
                            const isAccepted = acceptedPlanIds.has(plan.id)
                            const isGenerating = generandoId === plan.id

                            return (
                              <div
                                key={plan.id}
                                className={`flex items-start justify-between gap-3 rounded-lg border p-3 ${
                                  isAccepted
                                    ? 'border-green-300 bg-green-50/50'
                                    : 'border-amber-200 bg-amber-50/30'
                                }`}
                              >
                                <div className="flex-1 min-w-0">
                                  <div className="flex flex-wrap items-center gap-2">
                                    <span className="font-medium text-sm text-gray-900">
                                      {activo?.codigo ?? '-'}
                                    </span>
                                    <span className="text-sm text-gray-600 truncate">
                                      {activo?.nombre ?? ''}
                                    </span>
                                  </div>
                                  <div className="flex flex-wrap items-center gap-2 mt-1">
                                    <Wrench className="h-3 w-3 text-gray-400" />
                                    <span className="text-xs text-gray-700">
                                      {pauta?.nombre ?? '-'}
                                    </span>
                                    {pauta?.tipo_plan && (
                                      <span className="inline-flex items-center rounded px-1.5 py-0.5 text-[10px] font-medium bg-amber-100 text-amber-700">
                                        {tipoPlanLabel(pauta.tipo_plan)}
                                      </span>
                                    )}
                                  </div>
                                  {/* Materials */}
                                  {pauta?.materiales_estimados && Array.isArray(pauta.materiales_estimados) && pauta.materiales_estimados.length > 0 && (
                                    <div className="flex flex-wrap items-center gap-1 mt-1.5">
                                      <Package className="h-3 w-3 text-gray-400" />
                                      {(pauta.materiales_estimados as any[]).slice(0, 3).map((mat: any, i: number) => (
                                        <span key={i} className="text-[10px] text-gray-500 bg-gray-100 px-1.5 py-0.5 rounded">
                                          {typeof mat === 'string' ? mat : mat.nombre ?? '?'}
                                          {mat.cantidad ? ` x${mat.cantidad}` : ''}
                                        </span>
                                      ))}
                                      {pauta.materiales_estimados.length > 3 && (
                                        <span className="text-[10px] text-gray-400">
                                          +{pauta.materiales_estimados.length - 3} mas
                                        </span>
                                      )}
                                    </div>
                                  )}
                                </div>
                                <div className="shrink-0 flex items-center gap-1.5">
                                  {isAccepted ? (
                                    <div className="flex items-center gap-1 text-green-600 text-xs font-medium">
                                      <CheckCircle2 className="h-4 w-4" />
                                      Aceptada
                                    </div>
                                  ) : (
                                    <>
                                      <Button
                                        variant="primary"
                                        size="sm"
                                        onClick={() => handleAceptar(plan)}
                                        loading={isGenerating}
                                        disabled={contratoError}
                                      >
                                        <CheckCircle2 className="h-3.5 w-3.5" />
                                        Aceptar
                                      </Button>
                                      <Button
                                        variant="outline"
                                        size="sm"
                                        onClick={() => handleDescartar(plan.id)}
                                      >
                                        <X className="h-3.5 w-3.5" />
                                      </Button>
                                    </>
                                  )}
                                </div>
                              </div>
                            )
                          })}
                        </div>
                      </div>
                    )}

                    {/* Section B: Planned OTs */}
                    {hasOTs && (
                      <div className="mb-3">
                        <p className="text-xs font-semibold text-gray-500 uppercase mb-2">
                          Ordenes de Trabajo Planificadas
                        </p>
                        <div className="space-y-1.5">
                          {dayOTs.map((ot: any) => (
                            <div
                              key={ot.id}
                              onClick={() => router.push(`/dashboard/ordenes-trabajo/${ot.id}`)}
                              className="flex items-center gap-3 rounded-lg border border-gray-200 bg-white p-3 cursor-pointer hover:bg-gray-50 transition-colors"
                            >
                              <div className="flex-1 min-w-0 flex flex-wrap items-center gap-2">
                                <span className="font-mono text-xs text-gray-500">
                                  {ot.folio ?? '-'}
                                </span>
                                <span className={`inline-flex items-center rounded px-1.5 py-0.5 text-[10px] font-medium ${tipoBadgeColor[ot.tipo] ?? 'bg-gray-100 text-gray-700'}`}>
                                  {ot.tipo?.replace(/_/g, ' ') ?? '-'}
                                </span>
                                <span className="text-sm text-gray-900 truncate">
                                  {ot.activo?.nombre ?? ot.activo?.codigo ?? '-'}
                                </span>
                                <span className={`inline-flex items-center rounded px-1.5 py-0.5 text-[10px] font-medium ${prioridadBadgeColor[ot.prioridad] ?? 'bg-gray-100 text-gray-600'}`}>
                                  {ot.prioridad ?? '-'}
                                </span>
                              </div>
                              <div className="shrink-0 flex items-center gap-2">
                                {ot.responsable?.nombre_completo && (
                                  <span className="text-xs text-gray-500 hidden sm:inline">
                                    {ot.responsable.nombre_completo}
                                  </span>
                                )}
                                <span className={`inline-flex items-center rounded px-1.5 py-0.5 text-[10px] font-medium ${estadoBadgeColor[ot.estado] ?? 'bg-gray-100 text-gray-600'}`}>
                                  {ot.estado?.replace(/_/g, ' ') ?? '-'}
                                </span>
                              </div>
                            </div>
                          ))}
                        </div>
                      </div>
                    )}

                    {/* Empty state for the day */}
                    {!hasPM && !hasOTs && (
                      <p className="text-sm text-gray-400 italic mb-3">
                        Sin actividades programadas para este dia.
                      </p>
                    )}

                    {/* Section C: Add OT button */}
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => handleAgregarOT(dateISO)}
                      disabled={contratoError}
                      className="w-full border-dashed"
                    >
                      <Plus className="h-3.5 w-3.5" />
                      Agregar OT
                    </Button>
                  </CardContent>
                </Card>
              )
            })}
          </div>

          {/* Week Summary */}
          <Card>
            <CardContent className="p-5">
              <h3 className="text-base font-semibold text-gray-900 mb-4">
                Resumen de la Semana
              </h3>
              <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
                {/* Count by tipo */}
                {Object.entries(weekSummary.byTipo).map(([tipo, count]) => (
                  <div key={tipo} className="text-center">
                    <span className={`inline-flex items-center rounded px-2 py-1 text-xs font-medium ${tipoBadgeColor[tipo] ?? 'bg-gray-100 text-gray-700'}`}>
                      {tipo.replace(/_/g, ' ')}
                    </span>
                    <p className="mt-1 text-2xl font-bold text-gray-900">{count}</p>
                  </div>
                ))}
                {/* Total */}
                <div className="text-center">
                  <span className="inline-flex items-center rounded px-2 py-1 text-xs font-medium bg-gray-100 text-gray-700">
                    Total OTs
                  </span>
                  <p className="mt-1 text-2xl font-bold text-gray-900">{weekSummary.total}</p>
                </div>
                {/* Completed */}
                <div className="text-center">
                  <span className="inline-flex items-center rounded px-2 py-1 text-xs font-medium bg-green-100 text-green-700">
                    Completadas
                  </span>
                  <p className="mt-1 text-2xl font-bold text-green-700">{weekSummary.completed}</p>
                </div>
              </div>
            </CardContent>
          </Card>

          {/* Consolidated Materials */}
          {materialesConsolidados.length > 0 && (
            <Card>
              <CardContent className="p-5">
                <div className="flex items-center gap-2 mb-4">
                  <Package className="h-5 w-5 text-pillado-green-600" />
                  <h3 className="text-base font-semibold text-gray-900">
                    Materiales Necesarios (Semana)
                  </h3>
                </div>
                <div className="overflow-x-auto">
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>Material / Repuesto</TableHead>
                        <TableHead className="text-center w-32">Cantidad Total</TableHead>
                        <TableHead className="w-32">Unidad</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {materialesConsolidados.map((mat, i) => (
                        <TableRow key={i}>
                          <TableCell className="font-medium">{mat.nombre}</TableCell>
                          <TableCell className="text-center">{mat.cantidad}</TableCell>
                          <TableCell className="text-gray-500">{mat.unidad ?? '-'}</TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </div>
              </CardContent>
            </Card>
          )}
        </>
      )}

      {/* CrearOTModal */}
      {contratoId && (
        <CrearOTModal
          open={crearOTModalOpen}
          onClose={() => setCrearOTModalOpen(false)}
          onCreated={() => {
            setCrearOTModalOpen(false)
            setSuccessMsg('Orden de trabajo creada exitosamente.')
          }}
          contratoId={contratoId}
          defaultFechaProgramada={crearOTFechaPre}
        />
      )}
    </div>
  )
}

// ---------------------------------------------------------------------------
// Tab: Calendario PM
// ---------------------------------------------------------------------------
function CalendarioTab({
  planes,
  isLoading,
  faenas,
  faenaFilter,
  setFaenaFilter,
}: {
  planes: any[] | null | undefined
  isLoading: boolean
  faenas: any[] | null | undefined
  faenaFilter: string
  setFaenaFilter: (v: string) => void
}) {
  return (
    <div className="space-y-4">
      {/* Filter */}
      <div className="max-w-xs">
        <Select
          placeholder="Todas las faenas"
          value={faenaFilter}
          onChange={(e) => setFaenaFilter(e.target.value)}
          options={[
            { value: '', label: 'Todas las faenas' },
            ...(faenas?.map((f: any) => ({ value: f.id, label: f.nombre })) ?? []),
          ]}
        />
      </div>

      {isLoading ? (
        <div className="flex items-center justify-center py-16">
          <Spinner size="lg" />
        </div>
      ) : !planes || planes.length === 0 ? (
        <EmptyState
          icon={Calendar}
          title="Sin planes de mantenimiento"
          description="No hay planes de mantenimiento activos para los filtros seleccionados."
        />
      ) : (
        <div className="space-y-3">
          {planes.map((plan: any) => (
            <PlanCard key={plan.id} plan={plan} />
          ))}
        </div>
      )}
    </div>
  )
}

// ---------------------------------------------------------------------------
// Tab: Vencidos
// ---------------------------------------------------------------------------
function VencidosTab({
  vencidos,
  isLoading,
}: {
  vencidos: any[] | null | undefined
  isLoading: boolean
}) {
  return (
    <div className="space-y-4">
      {/* Red accent header */}
      {!isLoading && vencidos && vencidos.length > 0 && (
        <div className="flex items-center gap-2 rounded-lg border border-red-200 bg-red-50 px-4 py-3">
          <AlertTriangle className="h-5 w-5 text-red-500 shrink-0" />
          <p className="text-sm text-red-700">
            Hay <strong>{vencidos.length}</strong> plan{vencidos.length !== 1 ? 'es' : ''} de
            mantenimiento con fecha vencida. Se requiere atencion inmediata.
          </p>
        </div>
      )}

      {isLoading ? (
        <div className="flex items-center justify-center py-16">
          <Spinner size="lg" />
        </div>
      ) : !vencidos || vencidos.length === 0 ? (
        <EmptyState
          icon={CheckCircle2}
          title="Sin mantenimientos vencidos"
          description="Todos los planes de mantenimiento estan al dia."
        />
      ) : (
        <div className="space-y-3">
          {vencidos.map((plan: any) => (
            <PlanCard key={plan.id} plan={plan} />
          ))}
        </div>
      )}
    </div>
  )
}

// ---------------------------------------------------------------------------
// Tab: Pautas del Fabricante
// ---------------------------------------------------------------------------
function PautasTab({
  pautas,
  isLoading,
}: {
  pautas: any[] | null | undefined
  isLoading: boolean
}) {
  return (
    <div>
      {isLoading ? (
        <div className="flex items-center justify-center py-16">
          <Spinner size="lg" />
        </div>
      ) : !pautas || pautas.length === 0 ? (
        <EmptyState
          icon={Wrench}
          title="Sin pautas del fabricante"
          description="No hay pautas de mantenimiento registradas."
        />
      ) : (
        <Card>
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Modelo</TableHead>
                  <TableHead>Nombre pauta</TableHead>
                  <TableHead>Tipo plan</TableHead>
                  <TableHead>Frecuencia</TableHead>
                  <TableHead className="text-center">Duracion est.</TableHead>
                  <TableHead className="text-center">Items</TableHead>
                  <TableHead className="text-center w-10" />
                </TableRow>
              </TableHeader>
              <TableBody>
                {pautas.map((pauta: any) => (
                  <PautaRow key={pauta.id} pauta={pauta} />
                ))}
              </TableBody>
            </Table>
          </div>
        </Card>
      )}
    </div>
  )
}
