'use client'

import Link from 'next/link'
import { ExternalLink, ShieldOff } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import type { FueraDeFlota } from '@/lib/services/panel-gerencia'
import { fmtFecha } from './comunes'

// ============================================================================
// Fuera de flota (MIG306)
// ----------------------------------------------------------------------------
// Equipos en estado 'S': robo, pérdida total, incautación. Sus días NO cuentan
// en la disponibilidad —se excluyen del denominador en vez de sumarse a los
// detenidos, porque no hay mantención que los recupere—.
//
// Pero tienen que quedar a la vista. Si un equipo simplemente saliera del
// cálculo y de la pantalla, el panel pasaría de mentir por exceso a mentir por
// omisión: en tres meses nadie se acordaría de que hay un seguro sin cerrar y
// un contrato con un equipo menos.
// ============================================================================

export function PanelFueraDeFlota({ equipos }: { equipos: FueraDeFlota[] }) {
  if (equipos.length === 0) return null

  return (
    <Card className="border-l-4 border-l-slate-500">
      <CardHeader className="pb-2">
        <CardTitle className="flex items-center gap-2 text-base">
          <ShieldOff className="h-4 w-4 text-slate-600" />
          Fuera de flota
          <span className="text-sm font-normal text-muted-foreground">
            ({equipos.length})
          </span>
        </CardTitle>
        <p className="text-xs text-muted-foreground">
          No cuentan en la disponibilidad: sus días se excluyen del cálculo, no
          se suman a los detenidos. Siguen acá porque el seguro y el contrato
          sí hay que cerrarlos.
        </p>
      </CardHeader>

      <CardContent className="space-y-2">
        {equipos.map((e) => (
          <div key={e.activo_id}
            className="flex items-start gap-3 rounded-lg border bg-slate-50/70 px-3 py-2">
            <div className="min-w-0 flex-1">
              <div className="flex flex-wrap items-center gap-x-2 gap-y-1">
                <span className="font-semibold">{e.codigo}</span>
                {e.patente && (
                  <span className="text-xs text-muted-foreground">{e.patente}</span>
                )}
                <span className="rounded bg-slate-200 px-1.5 py-0.5 text-[10px] font-semibold text-slate-700">
                  {e.operacion}
                </span>
                {e.contrato_activo && e.cliente_actual && (
                  <span className="rounded bg-amber-100 px-1.5 py-0.5 text-[10px] font-semibold text-amber-800">
                    sigue en contrato · {e.cliente_actual}
                  </span>
                )}
              </div>
              <div className="truncate text-xs text-muted-foreground">{e.nombre}</div>
              {e.motivo && (
                <p className="mt-1 text-xs leading-snug text-slate-700">{e.motivo}</p>
              )}
              <Link href={`/dashboard/activos/${e.activo_id}`}
                className="mt-1 inline-flex items-center gap-0.5 text-[11px] font-medium
                           text-blue-700 underline">
                Ver ficha del equipo <ExternalLink className="h-3 w-3" />
              </Link>
            </div>

            <div className="shrink-0 text-right">
              <div className="text-lg font-bold leading-none text-slate-700">
                {e.dias} d
              </div>
              <div className="text-[10px] text-muted-foreground">
                desde {fmtFecha(e.desde)}
              </div>
              {e.dias_en_periodo !== e.dias && (
                <div className="text-[10px] text-muted-foreground">
                  {e.dias_en_periodo} en el mes
                </div>
              )}
            </div>
          </div>
        ))}
      </CardContent>
    </Card>
  )
}
