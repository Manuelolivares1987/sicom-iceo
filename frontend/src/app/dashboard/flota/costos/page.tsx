'use client'

import { useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Gauge } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { getPanelCostos } from '@/lib/services/costos-operacion'
import { fmtClp, fmtNum, rangoPreset, type RangoPreset } from '@/lib/costos-operacion'
import {
  PRESETS, TablaEquiposCosto,
} from '@/components/costos/comunes'
import { ParetoModal, type PasoPareto } from '@/components/costos/pareto-modal'
import { ConciliacionUbicacion } from '@/components/costos/conciliacion-ubicacion'
import { PanelFaenas } from '@/components/costos/panel-faenas'

// ============================================================================
// Flota · Costo por faena y por equipo (MIG598-600)
// ----------------------------------------------------------------------------
// La misma información del panel de Costos de Operación, mirada desde la flota:
// cuánto cuesta cada faena y cada equipo por hora operada. Sin petróleo (se
// revende). Mismo permiso que el panel de gerencia (fn_costos_operacion_puede_ver).
// ============================================================================

export default function FlotaCostosPage() {
  useRequireAuth()
  const [preset, setPreset] = useState<RangoPreset>('12m')
  const [pareto, setPareto] = useState<PasoPareto | null>(null)
  const rango = useMemo(() => rangoPreset(preset, new Date()), [preset])

  const { data, isLoading, error } = useQuery({
    queryKey: ['costos-operacion', rango.desde, rango.hasta, false],
    queryFn: () => getPanelCostos(rango.desde, rango.hasta, null),
    staleTime: 5 * 60_000,
    retry: (n, err) => err?.name !== 'CostosNoAutorizadoError' && n < 2,
  })

  return (
    <div className="space-y-5 p-4 md:p-6">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="flex items-center gap-2 text-2xl font-bold text-gray-900">
            <Gauge className="h-6 w-6 text-pillado-green-600" /> Costo por faena y por equipo
          </h1>
          <p className="text-sm text-gray-500">
            Gasto de bodega Softland (repuestos, neumáticos, lubricantes, insumos y EPP). Sin petróleo, que se revende.
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          {PRESETS.map((p) => (
            <Button key={p.id} size="sm" variant={preset === p.id ? 'primary' : 'outline'}
                    onClick={() => setPreset(p.id)}>
              {p.label}
            </Button>
          ))}
        </div>
      </div>

      {error && <Card><CardContent className="p-6 text-sm text-red-700">{(error as Error).message}</CardContent></Card>}
      {!error && <PanelFaenas desde={rango.desde} hasta={rango.hasta} onPareto={setPareto} />}

      {isLoading && <div className="flex justify-center py-10"><Spinner /></div>}
      {data && (
        <>
          <Card>
            <CardContent className="flex flex-wrap gap-x-8 gap-y-2 p-4 text-sm">
              <span>
                Costo por hora de la flota:{' '}
                <b>{data.kpi.flota_costo_hora != null ? `${fmtClp(data.kpi.flota_costo_hora)}/h` : '—'}</b>
              </span>
              <span className="text-gray-500">
                {fmtNum(data.kpi.equipos_medidos)} equipos medidos · {fmtNum(data.kpi.flota_horas)} h ·
                ventana típica {fmtNum(data.kpi.dias_medidos_mediana)} días
              </span>
            </CardContent>
          </Card>
          <TablaEquiposCosto equipos={data.por_equipo} onPareto={setPareto} />
        </>
      )}

      <ConciliacionUbicacion />

      {pareto && (
        <ParetoModal inicio={pareto} desde={rango.desde} hasta={rango.hasta}
                     onClose={() => setPareto(null)} />
      )}
    </div>
  )
}
