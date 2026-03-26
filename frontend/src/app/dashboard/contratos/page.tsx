'use client'

import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { FileText, MapPin, Calendar, DollarSign, Building2, ChevronDown, ChevronUp } from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Spinner } from '@/components/ui/spinner'
import { EmptyState } from '@/components/ui/empty-state'
import { StatCard } from '@/components/ui/stat-card'
import { getContratos } from '@/lib/services/contratos'
import { getFaenas } from '@/lib/services/faenas'
import { formatCLP, formatDate } from '@/lib/utils'
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

function useFaenas(contratoId?: string) {
  return useQuery({
    queryKey: ['faenas', contratoId],
    queryFn: async () => {
      const { data, error } = await getFaenas(contratoId)
      if (error) throw error
      return data
    },
    enabled: !!contratoId,
  })
}

function getEstadoContratoVariant(estado: string) {
  switch (estado) {
    case 'activo':
      return 'operativo'
    case 'pausado':
      return 'pausada'
    case 'finalizado':
      return 'default'
    default:
      return 'default'
  }
}

function getEstadoContratoLabel(estado: string) {
  switch (estado) {
    case 'activo':
      return 'Activo'
    case 'pausado':
      return 'Pausado'
    case 'finalizado':
      return 'Finalizado'
    default:
      return estado
  }
}

function getEstadoFaenaVariant(estado: string) {
  switch (estado) {
    case 'activa':
      return 'operativo'
    case 'inactiva':
      return 'default'
    default:
      return 'default'
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
        <span className="font-medium text-gray-700">{percent.toFixed(1)}% transcurrido</span>
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

function ContratoCard({ contrato }: { contrato: Contrato }) {
  const [descOpen, setDescOpen] = useState(false)

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-pillado-green-50">
              <FileText className="h-5 w-5 text-pillado-green-500" />
            </div>
            <div>
              <CardTitle>{contrato.nombre}</CardTitle>
              <p className="text-sm text-gray-500 mt-0.5">{contrato.codigo}</p>
            </div>
          </div>
          <Badge variant={getEstadoContratoVariant(contrato.estado) as 'operativo' | 'pausada' | 'default'}>
            {getEstadoContratoLabel(contrato.estado)}
          </Badge>
        </div>
      </CardHeader>
      <CardContent>
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mb-4">
          <StatCard
            title="Cliente"
            value={contrato.cliente || 'No especificado'}
            icon={Building2}
            color="blue"
          />
          <StatCard
            title="Valor Contrato"
            value={contrato.valor_contrato ? formatCLP(contrato.valor_contrato) : 'No definido'}
            subtitle={contrato.moneda}
            icon={DollarSign}
            color="green"
          />
          <StatCard
            title="Fecha Inicio"
            value={contrato.fecha_inicio ? formatDate(contrato.fecha_inicio) : '-'}
            icon={Calendar}
            color="blue"
          />
          <StatCard
            title="Fecha Fin"
            value={contrato.fecha_fin ? formatDate(contrato.fecha_fin) : '-'}
            icon={Calendar}
            color="orange"
          />
        </div>

        {contrato.fecha_inicio && contrato.fecha_fin && (
          <ContractProgressBar
            fechaInicio={contrato.fecha_inicio}
            fechaFin={contrato.fecha_fin}
          />
        )}

        {contrato.descripcion && (
          <div className="mt-4">
            <button
              onClick={() => setDescOpen(!descOpen)}
              className="flex items-center gap-1 text-sm font-medium text-gray-600 hover:text-gray-900 transition-colors"
            >
              {descOpen ? (
                <ChevronUp className="h-4 w-4" />
              ) : (
                <ChevronDown className="h-4 w-4" />
              )}
              Descripcion
            </button>
            {descOpen && (
              <p className="mt-2 text-sm text-gray-600 bg-gray-50 rounded-lg p-3">
                {contrato.descripcion}
              </p>
            )}
          </div>
        )}
      </CardContent>
    </Card>
  )
}

function FaenaCard({ faena }: { faena: Faena }) {
  return (
    <Card className="hover:shadow-md transition-shadow">
      <CardContent className="p-5">
        <div className="flex items-start justify-between mb-3">
          <div>
            <p className="text-xs font-medium text-gray-400">{faena.codigo}</p>
            <h4 className="text-base font-semibold text-gray-900 mt-0.5">{faena.nombre}</h4>
          </div>
          <Badge variant={getEstadoFaenaVariant(faena.estado) as 'operativo' | 'default'}>
            {faena.estado === 'activa' ? 'Activa' : faena.estado}
          </Badge>
        </div>

        {faena.ubicacion && (
          <div className="flex items-center gap-1.5 text-sm text-gray-600 mb-1.5">
            <MapPin className="h-3.5 w-3.5 text-gray-400 shrink-0" />
            <span>{faena.ubicacion}</span>
          </div>
        )}

        {(faena.region || faena.comuna) && (
          <div className="flex items-center gap-1.5 text-sm text-gray-500 mb-1.5">
            <Building2 className="h-3.5 w-3.5 text-gray-400 shrink-0" />
            <span>
              {[faena.comuna, faena.region].filter(Boolean).join(', ')}
            </span>
          </div>
        )}

        {faena.coordenadas_lat && faena.coordenadas_lng && (
          <p className="text-xs text-gray-400 mt-2">
            Coordenadas: {faena.coordenadas_lat.toFixed(4)}, {faena.coordenadas_lng.toFixed(4)}
          </p>
        )}
      </CardContent>
    </Card>
  )
}

export default function ContratosPage() {
  const { data: contratos, isLoading: loadingContratos, error: errorContratos } = useContratos()
  const activeContrato = contratos?.find((c) => c.estado === 'activo') || contratos?.[0]
  const { data: faenas, isLoading: loadingFaenas } = useFaenas(activeContrato?.id)

  if (loadingContratos) {
    return (
      <div className="flex items-center justify-center min-h-[60vh]">
        <Spinner size="lg" />
      </div>
    )
  }

  if (errorContratos) {
    return (
      <div className="flex items-center justify-center min-h-[60vh]">
        <EmptyState
          icon={FileText}
          title="Error al cargar contratos"
          description="No se pudieron cargar los contratos. Intente recargar la pagina."
        />
      </div>
    )
  }

  if (!contratos || contratos.length === 0) {
    return (
      <div className="flex items-center justify-center min-h-[60vh]">
        <EmptyState
          icon={FileText}
          title="Sin contratos"
          description="No hay contratos registrados en el sistema."
        />
      </div>
    )
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Contratos</h1>
        <p className="text-sm text-gray-500 mt-1">
          Gestion de contratos de servicio y faenas asociadas
        </p>
      </div>

      {/* Main contract card */}
      {activeContrato && <ContratoCard contrato={activeContrato} />}

      {/* Additional contracts if any */}
      {contratos.length > 1 && (
        <div className="space-y-4">
          <h2 className="text-lg font-semibold text-gray-900">Otros Contratos</h2>
          {contratos
            .filter((c) => c.id !== activeContrato?.id)
            .map((contrato) => (
              <ContratoCard key={contrato.id} contrato={contrato} />
            ))}
        </div>
      )}

      {/* Faenas section */}
      <div>
        <div className="flex items-center justify-between mb-4">
          <div>
            <h2 className="text-lg font-semibold text-gray-900">Faenas</h2>
            <p className="text-sm text-gray-500">
              {faenas?.length ?? 0} faena{(faenas?.length ?? 0) !== 1 ? 's' : ''} asociada{(faenas?.length ?? 0) !== 1 ? 's' : ''} al contrato
            </p>
          </div>
        </div>

        {loadingFaenas ? (
          <div className="flex items-center justify-center py-12">
            <Spinner size="md" />
          </div>
        ) : !faenas || faenas.length === 0 ? (
          <EmptyState
            icon={MapPin}
            title="Sin faenas"
            description="No hay faenas asociadas a este contrato."
          />
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {faenas.map((faena) => (
              <FaenaCard key={faena.id} faena={faena} />
            ))}
          </div>
        )}
      </div>
    </div>
  )
}
