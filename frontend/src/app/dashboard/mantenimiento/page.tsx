'use client'

import { useState, useMemo, useEffect } from 'react'
import { useQuery } from '@tanstack/react-query'
import {
  Wrench,
  Calendar,
  AlertTriangle,
  Clock,
  CheckCircle2,
  ChevronDown,
  ChevronUp,
} from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
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
import {
  usePlanes,
  useMantenimientosVencidos,
  usePautasFabricante,
} from '@/hooks/use-mantenimiento'

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

// ---------------------------------------------------------------------------
// Tabs definition
// ---------------------------------------------------------------------------
const tabs = [
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
  const [activeTab, setActiveTab] = useState('calendario')
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
