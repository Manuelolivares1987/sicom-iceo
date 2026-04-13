'use client'

import { useState, useMemo } from 'react'
import { useQuery } from '@tanstack/react-query'
import {
  FileText,
  MapPin,
  Calendar,
  DollarSign,
  Building2,
  ChevronDown,
  ChevronUp,
  Map,
} from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Spinner } from '@/components/ui/spinner'
import { EmptyState } from '@/components/ui/empty-state'
import { StatCard } from '@/components/ui/stat-card'
import { getContratos } from '@/lib/services/contratos'
import { getFaenas } from '@/lib/services/faenas'
import { formatCLP, formatDate } from '@/lib/utils'
import { cn } from '@/lib/utils'
import type { Contrato, Faena } from '@/types/database'

function useContratos() {
  return useQuery({
    queryKey: ['contratos'],
    queryFn: async () => {
      const { data, error } = await getContratos()
      if (error) throw error
      return data
    },
  })
}

function useAllFaenas() {
  return useQuery({
    queryKey: ['all-faenas'],
    queryFn: async () => {
      const { data, error } = await getFaenas()
      if (error) throw error
      return data
    },
  })
}

// ── Mapeo de regiones a zonas operacionales ──
function getZona(region?: string): string {
  if (!region) return 'Sin asignar'
  const r = region.toLowerCase()
  if (r.includes('coquimbo') || r.includes('atacama')) return 'Coquimbo'
  if (r.includes('antofagasta')) return 'Calama'
  return region
}

const ZONA_COLORS: Record<string, string> = {
  Coquimbo: 'bg-blue-100 text-blue-700 border-blue-200',
  Calama: 'bg-orange-100 text-orange-700 border-orange-200',
  'Sin asignar': 'bg-gray-100 text-gray-700 border-gray-200',
}

function getEstadoContratoVariant(estado: string) {
  switch (estado) {
    case 'activo': return 'operativo'
    case 'pausado': return 'pausada'
    default: return 'default'
  }
}

function getEstadoContratoLabel(estado: string) {
  switch (estado) {
    case 'activo': return 'Activo'
    case 'pausado': return 'Pausado'
    case 'finalizado': return 'Finalizado'
    default: return estado
  }
}

function ContractProgressBar({ fechaInicio, fechaFin }: { fechaInicio: string; fechaFin: string }) {
  const start = new Date(fechaInicio).getTime()
  const end = new Date(fechaFin).getTime()
  const now = Date.now()
  const total = end - start
  const elapsed = now - start
  const percent = total > 0 ? Math.min(100, Math.max(0, (elapsed / total) * 100)) : 0

  return (
    <div className="mt-2">
      <div className="flex items-center justify-between text-xs text-gray-500 mb-1">
        <span>{formatDate(fechaInicio)}</span>
        <span className="font-medium text-gray-700">{percent.toFixed(0)}%</span>
        <span>{formatDate(fechaFin)}</span>
      </div>
      <div className="w-full bg-gray-200 rounded-full h-2">
        <div
          className="bg-pillado-green-500 h-2 rounded-full transition-all"
          style={{ width: `${percent}%` }}
        />
      </div>
    </div>
  )
}

function ContratoExpandable({
  contrato,
  faenas,
  defaultOpen = false,
}: {
  contrato: Contrato
  faenas: Faena[]
  defaultOpen?: boolean
}) {
  const [open, setOpen] = useState(defaultOpen)

  return (
    <Card className="overflow-hidden">
      <button
        className="w-full text-left px-6 py-4 flex items-center justify-between hover:bg-gray-50 transition-colors"
        onClick={() => setOpen(!open)}
      >
        <div className="flex items-center gap-3">
          <FileText className="h-5 w-5 text-pillado-green-500 shrink-0" />
          <div>
            <h3 className="font-semibold text-gray-900">{contrato.nombre}</h3>
            <p className="text-xs text-gray-500">{contrato.codigo} · {contrato.cliente}</p>
          </div>
        </div>
        <div className="flex items-center gap-3">
          <Badge variant={getEstadoContratoVariant(contrato.estado) as 'operativo' | 'pausada' | 'default'}>
            {getEstadoContratoLabel(contrato.estado)}
          </Badge>
          <span className="text-xs text-gray-400">{faenas.length} faena{faenas.length !== 1 ? 's' : ''}</span>
          {open ? <ChevronUp className="h-4 w-4 text-gray-400" /> : <ChevronDown className="h-4 w-4 text-gray-400" />}
        </div>
      </button>

      {open && (
        <CardContent className="border-t border-gray-100">
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3 mb-4">
            <StatCard title="Cliente" value={contrato.cliente || '—'} icon={Building2} color="blue" />
            <StatCard title="Valor" value={contrato.valor_contrato ? formatCLP(contrato.valor_contrato) : '—'} subtitle={contrato.moneda} icon={DollarSign} color="green" />
            <StatCard title="Inicio" value={contrato.fecha_inicio ? formatDate(contrato.fecha_inicio) : '—'} icon={Calendar} color="blue" />
            <StatCard title="Fin" value={contrato.fecha_fin ? formatDate(contrato.fecha_fin) : '—'} icon={Calendar} color="orange" />
          </div>

          {contrato.fecha_inicio && contrato.fecha_fin && (
            <ContractProgressBar fechaInicio={contrato.fecha_inicio} fechaFin={contrato.fecha_fin} />
          )}

          {contrato.descripcion && (
            <p className="mt-3 text-sm text-gray-600 bg-gray-50 rounded-lg p-3">{contrato.descripcion}</p>
          )}

          {faenas.length > 0 && (
            <div className="mt-4">
              <h4 className="text-xs font-semibold text-gray-500 uppercase mb-2">Faenas asociadas</h4>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                {faenas.map((f) => (
                  <div key={f.id} className="rounded-lg border border-gray-200 p-3 hover:bg-gray-50 transition-colors">
                    <div className="flex items-center justify-between mb-1">
                      <span className="text-sm font-medium">{f.nombre}</span>
                      <Badge variant={f.estado === 'activa' ? 'operativo' : 'default'}>
                        {f.estado === 'activa' ? 'Activa' : f.estado}
                      </Badge>
                    </div>
                    {f.ubicacion && (
                      <div className="flex items-center gap-1 text-xs text-gray-500">
                        <MapPin className="h-3 w-3" />
                        {f.ubicacion}
                      </div>
                    )}
                    {(f.region || f.comuna) && (
                      <div className="text-xs text-gray-400 mt-0.5">
                        {[f.comuna, f.region].filter(Boolean).join(', ')}
                      </div>
                    )}
                  </div>
                ))}
              </div>
            </div>
          )}
        </CardContent>
      )}
    </Card>
  )
}

export default function ContratosPage() {
  const { data: contratos, isLoading: loadingContratos, error: errorContratos } = useContratos()
  const { data: allFaenas, isLoading: loadingFaenas } = useAllFaenas()
  const [zonaFilter, setZonaFilter] = useState<string | null>(null)

  // ── Agrupar contratos por zona ──
  const contratosPorZona = useMemo(() => {
    if (!contratos || !allFaenas) return {}

    // Map contrato_id → faenas
    const faenasByContrato: Record<string, Faena[]> = {}
    allFaenas.forEach((f) => {
      if (!faenasByContrato[f.contrato_id]) faenasByContrato[f.contrato_id] = []
      faenasByContrato[f.contrato_id].push(f)
    })

    // Determine zona from first faena region
    const result: Record<string, Array<{ contrato: Contrato; faenas: Faena[] }>> = {}
    contratos.forEach((c) => {
      const cFaenas = faenasByContrato[c.id] || []
      const zona = cFaenas.length > 0 ? getZona(cFaenas[0].region ?? undefined) : 'Sin asignar'
      if (!result[zona]) result[zona] = []
      result[zona].push({ contrato: c, faenas: cFaenas })
    })

    return result
  }, [contratos, allFaenas])

  const zonas = useMemo(() => Object.keys(contratosPorZona).sort(), [contratosPorZona])
  const zonasToShow = zonaFilter ? [zonaFilter] : zonas
  const totalContratos = contratos?.length ?? 0
  const totalActivos = contratos?.filter((c) => c.estado === 'activo').length ?? 0

  if (loadingContratos || loadingFaenas) {
    return (
      <div className="flex items-center justify-center min-h-[60vh]">
        <Spinner size="lg" />
      </div>
    )
  }

  if (errorContratos || !contratos || contratos.length === 0) {
    return (
      <div className="flex items-center justify-center min-h-[60vh]">
        <EmptyState
          icon={FileText}
          title={errorContratos ? 'Error al cargar contratos' : 'Sin contratos'}
          description={errorContratos ? 'Intente recargar.' : 'No hay contratos registrados.'}
        />
      </div>
    )
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-gray-900 flex items-center gap-2">
            <FileText className="h-7 w-7 text-pillado-green-500" />
            Contratos
          </h1>
          <p className="text-sm text-gray-500 mt-1">
            {totalContratos} contratos · {totalActivos} activos · {allFaenas?.length ?? 0} faenas
          </p>
        </div>
      </div>

      {/* ── Filtros por zona ── */}
      <div className="flex flex-wrap gap-2">
        <button
          onClick={() => setZonaFilter(null)}
          className={cn(
            'rounded-lg border px-4 py-2 text-sm font-medium transition-colors',
            !zonaFilter ? 'bg-gray-900 text-white border-gray-900' : 'bg-white text-gray-700 border-gray-300 hover:bg-gray-50'
          )}
        >
          <Map className="h-4 w-4 inline mr-1" />
          Todas ({totalContratos})
        </button>
        {zonas.map((zona) => (
          <button
            key={zona}
            onClick={() => setZonaFilter(zonaFilter === zona ? null : zona)}
            className={cn(
              'rounded-lg border px-4 py-2 text-sm font-medium transition-colors',
              zonaFilter === zona
                ? ZONA_COLORS[zona] || 'bg-gray-900 text-white border-gray-900'
                : 'bg-white text-gray-700 border-gray-300 hover:bg-gray-50'
            )}
          >
            {zona} ({contratosPorZona[zona]?.length ?? 0})
          </button>
        ))}
      </div>

      {/* ── Contratos agrupados por zona ── */}
      {zonasToShow.map((zona) => {
        const items = contratosPorZona[zona] || []
        return (
          <div key={zona}>
            <h2 className="text-lg font-bold text-gray-800 mb-3 flex items-center gap-2">
              <span className={cn('inline-block rounded px-2 py-0.5 text-xs font-semibold', ZONA_COLORS[zona] || 'bg-gray-100 text-gray-700')}>
                {zona}
              </span>
              <span className="text-sm font-normal text-gray-500">
                {items.length} contrato{items.length !== 1 ? 's' : ''}
              </span>
            </h2>
            <div className="space-y-3">
              {items.map(({ contrato, faenas }, i) => (
                <ContratoExpandable
                  key={contrato.id}
                  contrato={contrato}
                  faenas={faenas}
                  defaultOpen={i === 0 && items.length === 1}
                />
              ))}
            </div>
          </div>
        )
      })}
    </div>
  )
}
