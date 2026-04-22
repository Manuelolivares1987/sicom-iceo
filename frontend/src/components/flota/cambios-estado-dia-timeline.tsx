'use client'

import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Spinner } from '@/components/ui/spinner'
import { Activity, FileText } from 'lucide-react'
import { cn, todayISO } from '@/lib/utils'
import { ESTADO_DIARIO_LABELS, ESTADO_DIARIO_COLORS } from '@/lib/services/flota'
import type { CambioEstadoDia } from '@/lib/services/reporte-diario'

interface Props {
  data: CambioEstadoDia[]
  isLoading?: boolean
  fecha?: string
}

function formatHora(iso: string) {
  const d = new Date(iso)
  return d.toLocaleTimeString('es-CL', { hour: '2-digit', minute: '2-digit' })
}

export function CambiosEstadoDiaTimeline({ data, isLoading, fecha }: Props) {
  const fechaLabel = fecha ?? todayISO()

  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-base flex items-center gap-2">
          <Activity className="h-5 w-5 text-blue-600" />
          Cambios manuales de estado · {fechaLabel}
          {data.length > 0 && (
            <span className="ml-2 rounded-full bg-blue-100 px-2 py-0.5 text-xs font-semibold text-blue-700">
              {data.length}
            </span>
          )}
        </CardTitle>
      </CardHeader>
      <CardContent>
        {isLoading ? (
          <div className="flex h-32 items-center justify-center">
            <Spinner className="h-6 w-6" />
          </div>
        ) : data.length === 0 ? (
          <div className="py-6 text-center text-sm text-gray-400">
            Sin cambios manuales registrados en la fecha seleccionada.
          </div>
        ) : (
          <div className="space-y-3">
            {data.map((c, idx) => (
              <div
                key={`${c.activo_id}-${idx}`}
                className="flex gap-3 border-l-2 border-blue-200 pl-3"
              >
                <div className="flex-shrink-0 text-xs font-mono text-gray-500 pt-0.5">
                  {formatHora(c.fecha_hora)}
                </div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 flex-wrap">
                    <span className="font-semibold text-gray-900">{c.patente}</span>
                    <span className="text-xs text-gray-500">{c.equipo}</span>
                    <span
                      className={cn(
                        'inline-block rounded px-1.5 py-0.5 text-xs font-bold',
                        ESTADO_DIARIO_COLORS[c.estado_codigo] || 'bg-gray-200 text-gray-700',
                      )}
                    >
                      {c.estado_codigo} · {ESTADO_DIARIO_LABELS[c.estado_codigo] || ''}
                    </span>
                  </div>
                  {c.motivo && (
                    <p className="text-sm text-gray-700 mt-1 italic">"{c.motivo}"</p>
                  )}
                  <div className="flex items-center gap-3 mt-1 text-xs text-gray-500">
                    <span>
                      Por <strong>{c.usuario_nombre}</strong>
                      {c.usuario_rol !== '—' && <span className="text-gray-400"> · {c.usuario_rol}</span>}
                    </span>
                    {c.ot_folio && (
                      <span className="flex items-center gap-1 text-amber-700">
                        <FileText className="h-3 w-3" />
                        OT {c.ot_folio}
                      </span>
                    )}
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}
      </CardContent>
    </Card>
  )
}
