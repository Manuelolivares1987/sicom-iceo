'use client'

import { Badge } from '@/components/ui/badge'
import { Card, CardContent } from '@/components/ui/card'
import { formatDate, formatDateTime, getEstadoOTColor, getEstadoOTLabel } from '@/lib/utils'

// ---------------------------------------------------------------------------
// Tipo label helper
// ---------------------------------------------------------------------------
const tipoLabels: Record<string, string> = {
  inspeccion: 'Inspección',
  preventivo: 'Preventivo',
  correctivo: 'Correctivo',
  abastecimiento: 'Abastecimiento',
  lubricacion: 'Lubricación',
  inventario: 'Inventario',
  regularizacion: 'Regularización',
}

// ---------------------------------------------------------------------------
// Props
// ---------------------------------------------------------------------------
export interface OTInfoHeaderProps {
  ot: {
    folio: string
    tipo: string
    estado: string
    prioridad: string
    cuadrilla?: string | null
    fecha_programada?: string | null
    fecha_inicio?: string | null
    fecha_termino?: string | null
    activo?: { id: string; codigo: string; nombre: string | null } | null
    faena?: { id: string; nombre: string } | null
    responsable?: { id: string; nombre_completo: string; cargo: string | null } | null
  }
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------
export function OTInfoHeader({ ot }: OTInfoHeaderProps) {
  const activoLabel = ot.activo ? (ot.activo.nombre || ot.activo.codigo) : '—'
  const faenaLabel = ot.faena?.nombre || '—'
  const responsableLabel = ot.responsable?.nombre_completo || '—'
  const tipoLabel = tipoLabels[ot.tipo] || ot.tipo
  const prioridadLabel =
    (ot.prioridad as string).charAt(0).toUpperCase() + (ot.prioridad as string).slice(1)

  return (
    <>
      {/* Header row */}
      <div className="mb-6 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">{ot.folio}</h1>
          <p className="text-sm text-gray-500">
            {activoLabel} — {faenaLabel}
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          <Badge className={getEstadoOTColor(ot.estado)}>
            {getEstadoOTLabel(ot.estado)}
          </Badge>
          <Badge variant={(ot.prioridad || 'default') as any}>{prioridadLabel}</Badge>
          <span className="inline-flex items-center rounded-full bg-blue-100 px-2.5 py-0.5 text-xs font-semibold text-blue-700">
            {tipoLabel}
          </span>
        </div>
      </div>

      {/* Info grid */}
      <Card className="mb-6">
        <CardContent className="grid grid-cols-2 gap-4 p-4 sm:grid-cols-3 lg:grid-cols-4">
          {[
            { label: 'Activo', value: activoLabel },
            { label: 'Faena', value: faenaLabel },
            { label: 'Responsable', value: responsableLabel },
            { label: 'Cuadrilla', value: ot.cuadrilla || '—' },
            {
              label: 'Fecha Programada',
              value: ot.fecha_programada ? formatDate(ot.fecha_programada) : '—',
            },
            {
              label: 'Fecha Inicio',
              value: ot.fecha_inicio ? formatDateTime(ot.fecha_inicio) : '—',
            },
            {
              label: 'Fecha Término',
              value: ot.fecha_termino ? formatDateTime(ot.fecha_termino) : 'En curso',
            },
          ].map((item) => (
            <div key={item.label}>
              <p className="text-xs font-medium text-gray-400">{item.label}</p>
              <p className="text-sm font-semibold text-gray-900">{item.value}</p>
            </div>
          ))}
        </CardContent>
      </Card>
    </>
  )
}
