'use client'

import { useMemo, useState } from 'react'
import Link from 'next/link'
import { useSearchParams } from 'next/navigation'
import { ClipboardList, Filter, Search } from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Spinner } from '@/components/ui/spinner'
import { Select } from '@/components/ui/select'
import { Input } from '@/components/ui/input'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useCalamaOTs, useCalamaPlanificaciones, useCalamaFaenas } from '@/hooks/use-calama'
import { GanttTable } from '@/components/calama/gantt-table'
import { zonaCodeFromFolio } from '@/lib/services/calama'
import type { CalamaOTEstado } from '@/lib/services/calama'

const ESTADOS: Array<{ value: CalamaOTEstado | ''; label: string }> = [
  { value: '',              label: 'Todos los estados' },
  { value: 'planificada',   label: 'Planificada' },
  { value: 'liberada',      label: 'Liberada' },
  { value: 'en_ejecucion',  label: 'En ejecucion' },
  { value: 'en_pausa',      label: 'En pausa' },
  { value: 'finalizada',    label: 'Finalizada' },
  { value: 'no_ejecutada',  label: 'No ejecutada' },
  { value: 'cancelada',     label: 'Cancelada' },
]

export default function OTsListadoPage() {
  useRequireAuth()
  const searchParams = useSearchParams()
  const initialEstado = (searchParams.get('estado') as CalamaOTEstado | null) ?? ''
  const initialPlan = searchParams.get('planificacionId') ?? ''

  const [estado, setEstado] = useState<CalamaOTEstado | ''>(initialEstado)
  const [planificacionId, setPlanificacionId] = useState<string>(initialPlan)
  const [faenaId, setFaenaId] = useState<string>('')
  const [zonaCodigo, setZonaCodigo] = useState<string>('')
  const [busqueda, setBusqueda] = useState<string>('')
  const [fechaDesde, setFechaDesde] = useState<string>('')
  const [fechaHasta, setFechaHasta] = useState<string>('')

  const { data: planificaciones } = useCalamaPlanificaciones()
  const { data: faenas } = useCalamaFaenas()

  const filters = useMemo(() => ({
    estado: estado || undefined,
    planificacionId: planificacionId || undefined,
    faenaId: faenaId || undefined,
    fechaDesde: fechaDesde || undefined,
    fechaHasta: fechaHasta || undefined,
    busqueda: busqueda || undefined,
  }), [estado, planificacionId, faenaId, fechaDesde, fechaHasta, busqueda])

  const { data: ots, isLoading, error } = useCalamaOTs(filters)

  const otsFiltradas = useMemo(() => {
    if (!ots) return []
    if (!zonaCodigo) return ots
    return ots.filter((o) => zonaCodeFromFolio(o.folio) === zonaCodigo)
  }, [ots, zonaCodigo])

  const zonasDisponibles = useMemo(() => {
    if (!ots) return [] as string[]
    const set = new Set<string>()
    for (const o of ots) {
      const z = zonaCodeFromFolio(o.folio)
      if (z) set.add(z)
    }
    return Array.from(set).sort()
  }, [ots])

  return (
    <div className="space-y-4">
      <div className="rounded-2xl bg-gradient-to-r from-amber-700 to-orange-600 p-6 text-white shadow-lg">
        <h1 className="text-2xl font-bold flex items-center gap-2">
          <ClipboardList className="h-6 w-6" />
          OTs Operacion Calama
        </h1>
        <p className="text-sm text-white/90 mt-1">
          {otsFiltradas.length} OTs visibles
          {ots && ots.length !== otsFiltradas.length ? ` (de ${ots.length} totales)` : ''}.
        </p>
      </div>

      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-base flex items-center gap-2">
            <Filter className="h-4 w-4" />
            Filtros
          </CardTitle>
        </CardHeader>
        <CardContent className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">
          <Select
            label="Estado"
            value={estado}
            onChange={(e) => setEstado(e.target.value as CalamaOTEstado | '')}
            options={ESTADOS}
          />
          <Select
            label="Planificacion"
            value={planificacionId}
            onChange={(e) => setPlanificacionId(e.target.value)}
            options={[
              { value: '', label: 'Todas' },
              ...((planificaciones ?? []).map((p) => ({ value: p.id, label: p.codigo }))),
            ]}
          />
          <Select
            label="Faena"
            value={faenaId}
            onChange={(e) => setFaenaId(e.target.value)}
            options={[
              { value: '', label: 'Todas' },
              ...((faenas ?? []).map((f) => ({ value: f.id, label: f.codigo }))),
            ]}
          />
          <Select
            label="Zona"
            value={zonaCodigo}
            onChange={(e) => setZonaCodigo(e.target.value)}
            options={[
              { value: '', label: 'Todas' },
              ...zonasDisponibles.map((z) => ({ value: z, label: z })),
            ]}
          />
          <Input
            label="Fecha desde"
            type="date"
            value={fechaDesde}
            onChange={(e) => setFechaDesde(e.target.value)}
          />
          <Input
            label="Fecha hasta"
            type="date"
            value={fechaHasta}
            onChange={(e) => setFechaHasta(e.target.value)}
          />
          <div className="sm:col-span-2 lg:col-span-2">
            <label className="mb-1.5 block text-sm font-medium text-gray-700">Buscar</label>
            <div className="relative">
              <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 h-4 w-4 text-gray-400" />
              <input
                type="text"
                value={busqueda}
                onChange={(e) => setBusqueda(e.target.value)}
                placeholder="Folio o titulo..."
                className="min-h-[44px] w-full rounded-lg border border-gray-300 bg-white pl-9 pr-3 py-2 text-sm focus:border-amber-500 focus:outline-none focus:ring-2 focus:ring-amber-500/20"
              />
            </div>
          </div>
        </CardContent>
      </Card>

      {isLoading && (
        <div className="flex items-center gap-2 text-sm text-gray-500">
          <Spinner className="h-4 w-4" />
          Cargando OTs…
        </div>
      )}
      {error && (
        <div className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">
          Error: {error instanceof Error ? error.message : 'desconocido'}
        </div>
      )}

      {ots && (
        <Card>
          <CardContent className="p-0">
            <GanttTable ots={otsFiltradas} />
          </CardContent>
        </Card>
      )}

      <p className="text-xs text-gray-400">
        <Link href="/dashboard/operacion-calama" className="hover:text-gray-600">← Volver al dashboard</Link>
      </p>
    </div>
  )
}
