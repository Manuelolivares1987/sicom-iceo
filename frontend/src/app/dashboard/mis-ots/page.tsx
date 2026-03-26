'use client'

import { useMemo } from 'react'
import { useRouter } from 'next/navigation'
import { ClipboardList, Calendar, User } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Spinner } from '@/components/ui/spinner'
import { EmptyState } from '@/components/ui/empty-state'
import { useAuth } from '@/contexts/auth-context'
import { useOrdenesTrabajo } from '@/hooks/use-ordenes-trabajo'
import { formatDate, getEstadoOTColor, getEstadoOTLabel } from '@/lib/utils'

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const tipoLabels: Record<string, string> = {
  inspeccion: 'Inspeccion',
  preventivo: 'Preventivo',
  correctivo: 'Correctivo',
  abastecimiento: 'Abastecimiento',
  lubricacion: 'Lubricacion',
  inventario: 'Inventario',
  regularizacion: 'Regularizacion',
}

function getPrioridadColor(p: string) {
  const m: Record<string, string> = {
    emergencia: 'bg-red-100 text-red-700',
    urgente: 'bg-red-100 text-red-700',
    alta: 'bg-orange-100 text-orange-700',
    normal: 'bg-blue-100 text-blue-700',
    media: 'bg-yellow-100 text-yellow-700',
    baja: 'bg-green-100 text-green-700',
  }
  return m[p] || 'bg-gray-100 text-gray-700'
}

function getPrioridadLabel(p: string) {
  const m: Record<string, string> = {
    emergencia: 'Emergencia',
    urgente: 'Urgente',
    alta: 'Alta',
    normal: 'Normal',
    media: 'Media',
    baja: 'Baja',
  }
  return m[p] || p
}

// Grouping order
const estadoGroupOrder = [
  'en_ejecucion',
  'asignada',
  'pausada',
  'creada',
  'ejecutada_ok',
  'ejecutada_con_observaciones',
  'no_ejecutada',
  'cancelada',
]

const estadoGroupLabels: Record<string, string> = {
  en_ejecucion: 'En Ejecucion',
  asignada: 'Asignadas',
  pausada: 'Pausadas',
  creada: 'Creadas',
  ejecutada_ok: 'Ejecutadas OK',
  ejecutada_con_observaciones: 'Con Observaciones',
  no_ejecutada: 'No Ejecutadas',
  cancelada: 'Canceladas',
}

// ---------------------------------------------------------------------------
// Main page
// ---------------------------------------------------------------------------
export default function MisOTsPage() {
  const { user } = useAuth()
  const router = useRouter()

  const { data: ots, isLoading } = useOrdenesTrabajo(
    user?.id ? { responsable_id: user.id } : undefined
  )

  // Group OTs by estado
  const grouped = useMemo(() => {
    if (!ots || ots.length === 0) return []

    const groups: Record<string, any[]> = {}
    for (const ot of ots as any[]) {
      const estado = ot.estado || 'creada'
      if (!groups[estado]) groups[estado] = []
      groups[estado].push(ot)
    }

    return estadoGroupOrder
      .filter((estado) => groups[estado] && groups[estado].length > 0)
      .map((estado) => ({
        estado,
        label: estadoGroupLabels[estado] || estado,
        items: groups[estado],
      }))
  }, [ots])

  if (isLoading) {
    return (
      <div className="flex justify-center py-24">
        <Spinner size="lg" className="text-pillado-green-600" />
      </div>
    )
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Mis Ordenes de Trabajo</h1>
        <p className="mt-1 text-sm text-gray-500">
          OTs asignadas a ti. Toca una tarjeta para ver el detalle.
        </p>
      </div>

      {/* Empty state */}
      {(!ots || ots.length === 0) && (
        <EmptyState
          icon={ClipboardList}
          title="No tienes OTs asignadas"
          description="Cuando te asignen ordenes de trabajo, aparecerán aquí."
        />
      )}

      {/* Grouped cards */}
      {grouped.map((group) => (
        <div key={group.estado} className="space-y-3">
          <div className="flex items-center gap-2">
            <h2 className="text-sm font-semibold text-gray-700">{group.label}</h2>
            <Badge variant="default" className="text-xs">
              {group.items.length}
            </Badge>
          </div>

          {group.items.map((ot: any) => (
            <Card
              key={ot.id}
              className="cursor-pointer transition-shadow hover:shadow-md"
              onClick={() => router.push(`/dashboard/ordenes-trabajo/${ot.id}`)}
            >
              <CardContent className="p-4 space-y-2">
                <div className="flex items-center justify-between">
                  <span className="font-mono text-sm font-bold text-pillado-green-600">
                    {ot.folio}
                  </span>
                  <Badge className={getEstadoOTColor(ot.estado)}>
                    {getEstadoOTLabel(ot.estado)}
                  </Badge>
                </div>

                <div className="flex flex-wrap gap-2">
                  <Badge variant="default">
                    {tipoLabels[ot.tipo] || ot.tipo}
                  </Badge>
                  <Badge className={getPrioridadColor(ot.prioridad)}>
                    {getPrioridadLabel(ot.prioridad)}
                  </Badge>
                </div>

                <div className="flex items-center justify-between text-xs text-gray-500">
                  <span className="flex items-center gap-1">
                    <Calendar className="h-3.5 w-3.5" />
                    {ot.fecha_programada ? formatDate(ot.fecha_programada) : 'Sin fecha'}
                  </span>
                  {ot.activo && (
                    <span className="font-medium text-gray-700">
                      {ot.activo.codigo || ot.activo.nombre}
                    </span>
                  )}
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      ))}
    </div>
  )
}
