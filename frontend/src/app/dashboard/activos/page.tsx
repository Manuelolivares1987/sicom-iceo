'use client'

import { useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import Link from 'next/link'
import {
  Search,
  LayoutGrid,
  List,
  ChevronDown,
  Gauge,
  Shield,
  Calendar,
  Wrench,
  Fuel,
} from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Input } from '@/components/ui/input'
import { Button } from '@/components/ui/button'
import {
  Table,
  TableHeader,
  TableBody,
  TableRow,
  TableHead,
  TableCell,
} from '@/components/ui/table'
import { Spinner } from '@/components/ui/spinner'
import { cn, getSemaforoColor, getCriticidadColor } from '@/lib/utils'
import { useActivos, useEstadosPlanificador } from '@/hooks/use-activos'
import { EstadoFlotaPill } from '@/components/flota/estado-flota-pill'
import { ESTADO_FLOTA_LABEL, ESTADO_FLOTA_OPCIONES, esFlotaDelPlanificador } from '@/lib/estado-flota'
import { getFaenas } from '@/lib/services/faenas'
import { usePermissions } from '@/hooks/use-permissions'
import type { Activo, TipoActivo, EstadoActivo, Criticidad } from '@/types/database'

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------
const tipoOptions: { value: string; label: string }[] = [
  { value: '', label: 'Todos' },
  { value: 'punto_fijo', label: 'Punto Fijo' },
  { value: 'punto_movil', label: 'Punto Móvil' },
  { value: 'surtidor', label: 'Surtidor' },
  { value: 'dispensador', label: 'Dispensador' },
  { value: 'estanque', label: 'Estanque' },
  { value: 'bomba', label: 'Bomba' },
  { value: 'manguera', label: 'Manguera' },
  { value: 'camion_cisterna', label: 'Camión Cisterna' },
  { value: 'lubrimovil', label: 'Lubrimóvil' },
  { value: 'equipo_bombeo', label: 'Equipo Bombeo' },
  { value: 'herramienta_critica', label: 'Herramienta Crítica' },
  { value: 'pistola_captura', label: 'Pistola Captura' },
  { value: 'camioneta', label: 'Camioneta' },
  { value: 'camion', label: 'Camión' },
  { value: 'equipo_menor', label: 'Equipo Menor' },
]

// El filtro de estado usa los códigos del planificador (A/C/D/...), no los
// estados internos de la ficha: es el mismo idioma de Sugerencias GPS, que es
// donde el estado se decide (MIG307).
const estadoOptions: { value: string; label: string }[] = [
  { value: '', label: 'Todos' },
  ...ESTADO_FLOTA_OPCIONES.map((c) => ({ value: c, label: `${c} · ${ESTADO_FLOTA_LABEL[c]}` })),
]

const criticidadOptions: { value: string; label: string }[] = [
  { value: '', label: 'Todas' },
  { value: 'critica', label: 'Crítica' },
  { value: 'alta', label: 'Alta' },
  { value: 'media', label: 'Media' },
  { value: 'baja', label: 'Baja' },
]

const estadoLabels: Record<string, string> = {
  operativo: 'Operativo',
  en_mantenimiento: 'En Mantenimiento',
  fuera_servicio: 'Fuera de Servicio',
  dado_baja: 'Dado de Baja',
  en_transito: 'En Tránsito',
}

const criticidadLabels: Record<string, string> = {
  critica: 'Crítica',
  alta: 'Alta',
  media: 'Media',
  baja: 'Baja',
}

const tipoLabels: Record<string, string> = {
  punto_fijo: 'Punto Fijo',
  punto_movil: 'Punto Móvil',
  surtidor: 'Surtidor',
  dispensador: 'Dispensador',
  estanque: 'Estanque',
  bomba: 'Bomba',
  manguera: 'Manguera',
  camion_cisterna: 'Camión Cisterna',
  lubrimovil: 'Lubrimóvil',
  equipo_bombeo: 'Equipo Bombeo',
  herramienta_critica: 'Herramienta Crítica',
  pistola_captura: 'Pistola Captura',
  camioneta: 'Camioneta',
  camion: 'Camión',
  equipo_menor: 'Equipo Menor',
}

type EstadoPlan = {
  activo_id: string
  estado_codigo: string | null
  fecha_estado: string | null
  confirmado_hoy: boolean | null
  dias_desde_confirmacion: number | null
}

// ---------------------------------------------------------------------------
// Card sub-component
// ---------------------------------------------------------------------------
function ActivoCard({ activo, estadoPlan }: { activo: Activo; estadoPlan?: EstadoPlan }) {
  const marcaNombre = activo.modelo?.marca?.nombre ?? ''
  const modeloNombre = activo.modelo?.nombre ?? ''
  const faenaNombre = activo.faena?.nombre ?? '—'

  return (
    <Link href={`/dashboard/activos/${activo.id}`} className="block">
    <Card className="transition-shadow hover:shadow-md">
      <CardContent className="p-4">
        {/* Header */}
        <div className="flex items-start justify-between">
          <div className="flex items-center gap-3">
            <span className={cn('h-3 w-3 rounded-full', getSemaforoColor(activo.estado))} />
            <div>
              <p className="text-sm font-bold text-gray-900">{activo.codigo}</p>
              <p className="text-xs text-gray-500">{activo.nombre ?? activo.codigo}</p>
            </div>
          </div>
          {esFlotaDelPlanificador(activo.tipo) && estadoPlan?.estado_codigo ? (
            <EstadoFlotaPill
              codigo={estadoPlan.estado_codigo}
              title={
                estadoPlan.confirmado_hoy
                  ? 'Confirmado hoy por el planificador'
                  : `Último día cerrado por el planificador: ${estadoPlan.fecha_estado?.slice(0, 10) ?? '—'}`
              }
            />
          ) : (
            <Badge variant={(activo.estado) as any}>
              {estadoLabels[activo.estado] || activo.estado}
            </Badge>
          )}
        </div>

        {/* Type & criticidad */}
        <div className="mt-3 flex flex-wrap gap-2">
          <span className="inline-flex items-center rounded-full bg-gray-100 px-2.5 py-0.5 text-xs font-semibold text-gray-600">
            {tipoLabels[activo.tipo] || activo.tipo}
          </span>
          <Badge
            className={getCriticidadColor(activo.criticidad)}
            title="Criticidad del equipo: cuánto duele que se detenga. No es una alarma ni el estado de hoy."
          >
            Criticidad {criticidadLabels[activo.criticidad]?.toLowerCase()}
          </Badge>
        </div>

        {/* Details */}
        <div className="mt-3 space-y-1 text-xs text-gray-500">
          <p className="font-medium text-gray-700">
            {marcaNombre}{marcaNombre && modeloNombre ? ' — ' : ''}{modeloNombre}
          </p>
          <p>{faenaNombre}</p>
        </div>

        {/* Counters */}
        <div className="mt-3 flex gap-4 text-xs text-gray-500">
          {activo.kilometraje_actual > 0 && (
            <div className="flex items-center gap-1">
              <Gauge className="h-3.5 w-3.5" />
              <span>{activo.kilometraje_actual.toLocaleString('es-CL')} km</span>
            </div>
          )}
          {activo.horas_uso_actual > 0 && (
            <div className="flex items-center gap-1">
              <Gauge className="h-3.5 w-3.5" />
              <span>{activo.horas_uso_actual.toLocaleString('es-CL')} hrs</span>
            </div>
          )}
        </div>
      </CardContent>
    </Card>
    </Link>
  )
}

// ---------------------------------------------------------------------------
// Main page
// ---------------------------------------------------------------------------
export default function ActivosPage() {
  const [viewMode, setViewMode] = useState<'grid' | 'list'>('grid')
  const [search, setSearch] = useState('')
  const [tipoFilter, setTipoFilter] = useState('')
  // [MIG385] Quien está acotado a una faena entra con su faena puesta y no la
  // puede cambiar: el filtro deja de ser una preferencia y pasa a ser el
  // alcance de la persona.
  const { faenaExclusiva } = usePermissions()
  const faenaSolo = faenaExclusiva()
  const [faenaFilter, setFaenaFilter] = useState(faenaSolo?.id ?? '')
  const [estadoFilter, setEstadoFilter] = useState('')
  const [criticidadFilter, setCriticidadFilter] = useState('')

  // Fetch faenas for dropdown
  const { data: faenas } = useQuery({
    queryKey: ['faenas'],
    queryFn: async () => {
      const { data, error } = await getFaenas()
      if (error) throw error
      return data
    },
  })

  // Build filters for the hook. El estado NO va al servidor: se filtra por el
  // código del planificador, que vive en otra tabla (estado_diario_flota).
  const filters: Record<string, unknown> = {}
  if (tipoFilter) filters.tipo = tipoFilter
  if (faenaSolo) filters.faena_id = faenaSolo.id
  else if (faenaFilter) filters.faena_id = faenaFilter
  if (criticidadFilter) filters.criticidad = criticidadFilter

  const { data: activos, isLoading, error } = useActivos(filters)
  const { data: estadosPlan } = useEstadosPlanificador()

  const estadoPorActivo = useMemo(() => {
    const m: Record<string, EstadoPlan> = {}
    for (const e of estadosPlan ?? []) m[e.activo_id] = e as EstadoPlan
    return m
  }, [estadosPlan])

  // Client-side text search + estado del planificador
  const filtered = (activos ?? []).filter((a) => {
    if (estadoFilter) {
      if (!esFlotaDelPlanificador(a.tipo)) return false
      if (estadoPorActivo[a.id]?.estado_codigo !== estadoFilter) return false
    }
    if (!search) return true
    const s = search.toLowerCase()
    return (
      a.codigo.toLowerCase().includes(s) ||
      (a.nombre ?? '').toLowerCase().includes(s) ||
      (a.patente ?? '').toLowerCase().includes(s)
    )
  })

  // Hace cuánto se cerró el día por última vez. No se avisa "faltan N por
  // cerrar hoy": a las 9 de la mañana eso es cierto para toda la flota y no
  // significa nada malo — el equipo arrastra el estado de ayer, que es lo
  // correcto. Lo que sí importa es un día SALTADO, y eso se ve en la brecha.
  const diasDesdeCierre = useMemo(() => {
    const dias = (activos ?? [])
      .filter((a) => esFlotaDelPlanificador(a.tipo))
      .map((a) => estadoPorActivo[a.id]?.dias_desde_confirmacion)
      .filter((d): d is number => d != null)
    return dias.length ? Math.min(...dias) : null
  }, [activos, estadoPorActivo])

  const faenaOptions: { value: string; label: string }[] = [
    { value: '', label: 'Todas' },
    ...(faenas ?? []).map((f) => ({ value: f.id, label: f.nombre })),
  ]

  function FilterSelect({
    label,
    value,
    onChange,
    options,
  }: {
    label: string
    value: string
    onChange: (v: string) => void
    options: { value: string; label: string }[]
  }) {
    return (
      <div className="w-full sm:w-auto">
        <label className="mb-1 block text-xs font-medium text-gray-500">{label}</label>
        <div className="relative">
          <select
            value={value}
            onChange={(e) => onChange(e.target.value)}
            className="h-10 w-full appearance-none rounded-lg border border-gray-300 bg-white px-3 pr-8 text-sm focus:border-pillado-green-500 focus:outline-none focus:ring-2 focus:ring-pillado-green-500/20 sm:w-40"
          >
            {options.map((o) => (
              <option key={o.value} value={o.value}>{o.label}</option>
            ))}
          </select>
          <ChevronDown className="pointer-events-none absolute right-2 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400" />
        </div>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Activos</h1>
          <p className="mt-1 text-sm text-gray-500">
            El estado que se muestra es el que confirma el planificador en{' '}
            <Link href="/dashboard/flota/sugerencias" className="font-medium text-pillado-green-600 hover:underline">
              Sugerencias de estado (GPS)
            </Link>
            . La ficha no tiene un estado propio. Los equipos fijos (surtidores, estanques,
            bombas) no se cierran a diario: muestran su estado de mantención.
            {diasDesdeCierre != null && diasDesdeCierre >= 2 && (
              <span className="ml-1 font-medium text-amber-600">
                El último cierre de flota fue hace {diasDesdeCierre} días.
              </span>
            )}
          </p>
        </div>
        <div className="flex gap-1 rounded-lg bg-gray-100 p-1">
          <button
            onClick={() => setViewMode('grid')}
            className={cn(
              'flex items-center gap-1 rounded-md px-3 py-1.5 text-sm font-medium transition-colors',
              viewMode === 'grid' ? 'bg-white text-pillado-green-600 shadow-sm' : 'text-gray-500'
            )}
          >
            <LayoutGrid className="h-4 w-4" />
            Grid
          </button>
          <button
            onClick={() => setViewMode('list')}
            className={cn(
              'flex items-center gap-1 rounded-md px-3 py-1.5 text-sm font-medium transition-colors',
              viewMode === 'list' ? 'bg-white text-pillado-green-600 shadow-sm' : 'text-gray-500'
            )}
          >
            <List className="h-4 w-4" />
            Lista
          </button>
        </div>
      </div>

      {/* Filters */}
      <Card>
        <CardContent className="flex flex-col gap-3 p-4 sm:flex-row sm:flex-wrap sm:items-end">
          <div className="flex-1 sm:max-w-xs">
            <Input
              placeholder="Buscar código o nombre..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
            />
          </div>
          <FilterSelect
            label="Tipo"
            value={tipoFilter}
            onChange={setTipoFilter}
            options={tipoOptions}
          />
          {faenaSolo ? (
            <div className="min-w-[150px]">
              <label className="mb-1 block text-xs font-medium text-gray-500">Faena</label>
              <p className="rounded-lg border border-gray-200 bg-gray-50 px-3 py-2 text-sm font-semibold text-gray-700">
                {faenaSolo.nombre}
              </p>
            </div>
          ) : (
            <FilterSelect
              label="Faena"
              value={faenaFilter}
              onChange={setFaenaFilter}
              options={faenaOptions}
            />
          )}
          <FilterSelect
            label="Estado"
            value={estadoFilter}
            onChange={setEstadoFilter}
            options={estadoOptions}
          />
          <FilterSelect
            label="Criticidad"
            value={criticidadFilter}
            onChange={setCriticidadFilter}
            options={criticidadOptions}
          />
        </CardContent>
      </Card>

      {/* Loading */}
      {isLoading && (
        <div className="flex justify-center py-16">
          <Spinner size="lg" className="text-pillado-green-600" />
        </div>
      )}

      {/* Error */}
      {error && (
        <div className="py-16 text-center">
          <p className="text-lg font-medium text-red-500">Error al cargar activos</p>
          <p className="mt-1 text-sm text-gray-400">{(error as Error).message}</p>
        </div>
      )}

      {/* Grid view */}
      {!isLoading && !error && viewMode === 'grid' && (
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
          {filtered.map((activo) => (
            <ActivoCard key={activo.id} activo={activo} estadoPlan={estadoPorActivo[activo.id]} />
          ))}
        </div>
      )}

      {/* List view */}
      {!isLoading && !error && viewMode === 'list' && (
        <Card>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead></TableHead>
                <TableHead>Estado (planificador)</TableHead>
                <TableHead>Código</TableHead>
                <TableHead>Patente</TableHead>
                <TableHead>Nombre</TableHead>
                <TableHead>Tipo</TableHead>
                <TableHead>Marca / Modelo</TableHead>
                <TableHead>Faena</TableHead>
                <TableHead>Criticidad (clasificación)</TableHead>
                <TableHead className="text-right">Km / Hrs</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {filtered.map((a) => (
                <TableRow key={a.id}>
                  <TableCell>
                    <span className={cn('inline-flex h-3 w-3 rounded-full', getSemaforoColor(a.estado))} />
                  </TableCell>
                  <TableCell>
                    {esFlotaDelPlanificador(a.tipo) && estadoPorActivo[a.id]?.estado_codigo ? (
                      <EstadoFlotaPill
                        codigo={estadoPorActivo[a.id].estado_codigo}
                        title={
                          estadoPorActivo[a.id].confirmado_hoy
                            ? 'Confirmado hoy por el planificador'
                            : `Último día cerrado: ${estadoPorActivo[a.id].fecha_estado?.slice(0, 10) ?? '—'}`
                        }
                      />
                    ) : (
                      <span className="text-xs text-gray-400">{estadoLabels[a.estado] || a.estado}</span>
                    )}
                  </TableCell>
                  <TableCell className="font-mono text-xs font-semibold">
                    <Link href={`/dashboard/activos/${a.id}`} className="text-pillado-green-600 hover:underline">{a.codigo}</Link>
                  </TableCell>
                  <TableCell className="font-mono text-xs text-gray-600">{a.patente ?? '—'}</TableCell>
                  <TableCell className="font-medium">
                    <Link href={`/dashboard/activos/${a.id}`} className="hover:text-pillado-green-600 hover:underline">{a.nombre ?? a.codigo}</Link>
                  </TableCell>
                  <TableCell className="text-xs text-gray-500">{tipoLabels[a.tipo] || a.tipo}</TableCell>
                  <TableCell className="text-xs text-gray-500">
                    {a.modelo?.marca?.nombre ?? ''}{a.modelo?.marca?.nombre && a.modelo?.nombre ? ' — ' : ''}{a.modelo?.nombre ?? ''}
                  </TableCell>
                  <TableCell className="text-xs text-gray-500">{a.faena?.nombre ?? '—'}</TableCell>
                  <TableCell>
                    <Badge
                      className={getCriticidadColor(a.criticidad)}
                      title="Criticidad del equipo: cuánto duele que se detenga. No es una alarma ni el estado de hoy."
                    >
                      {criticidadLabels[a.criticidad]}
                    </Badge>
                  </TableCell>
                  <TableCell className="text-right text-xs text-gray-500">
                    {a.kilometraje_actual > 0 && `${a.kilometraje_actual.toLocaleString('es-CL')} km`}
                    {a.kilometraje_actual > 0 && a.horas_uso_actual > 0 && ' / '}
                    {a.horas_uso_actual > 0 && `${a.horas_uso_actual.toLocaleString('es-CL')} hrs`}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </Card>
      )}

      {!isLoading && !error && filtered.length === 0 && (
        <div className="py-16 text-center">
          <Fuel className="mx-auto mb-4 h-12 w-12 text-gray-300" />
          <p className="text-lg font-medium text-gray-500">No hay activos registrados</p>
        </div>
      )}
    </div>
  )
}
