'use client'

// [MIG694] Stock en vivo de los estanques de la bodega de Coquimbo (es_bodega):
// el mismo dato que ve Comercial en el Consolidado, ahora también en el Panel
// Bodega — quien despacha y recibe tiene que ver cuánto queda.

import { useQuery } from '@tanstack/react-query'
import { Fuel } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { cargarStockEstanques } from '@/lib/services/combustible-comercial'

const fmtLt = (n: number) => `${n.toLocaleString('es-CL', { maximumFractionDigits: 0 })} L`

export function StockEstanquesCoquimbo() {
  const { data: estanques = [], isLoading } = useQuery({
    queryKey: ['comb-stock-estanques-bodega'], queryFn: cargarStockEstanques, refetchInterval: 5 * 60_000,
  })
  const total = estanques.reduce((s, e) => s + Number(e.stock_teorico_lt), 0)
  const capacidad = estanques.reduce((s, e) => s + Number(e.capacidad_lt), 0)

  return (
    <Card className="border-pillado-orange-300 bg-pillado-orange-50/40">
      <CardHeader className="pb-2">
        <CardTitle className="flex flex-wrap items-center justify-between gap-2 text-base text-pillado-orange-800">
          <span className="flex items-center gap-2"><Fuel className="h-4 w-4" /> Combustible Coquimbo · stock en vivo</span>
          {estanques.length > 0 && <span className="text-sm font-semibold">{fmtLt(total)} de {fmtLt(capacidad)}</span>}
        </CardTitle>
      </CardHeader>
      <CardContent>
        {isLoading ? <div className="text-sm text-muted-foreground">Cargando…</div>
          : estanques.length === 0 ? <div className="text-sm text-muted-foreground">Sin estanques registrados.</div>
          : (
            <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-4">
              {estanques.map((e) => {
                const colorBar = e.estado === 'critico' ? 'bg-red-500' : e.estado === 'bajo' ? 'bg-amber-500'
                  : e.estado === 'lleno' ? 'bg-pillado-orange-500' : 'bg-pillado-green-500'
                const colorTxt = e.estado === 'critico' ? 'text-red-700' : e.estado === 'bajo' ? 'text-amber-700' : 'text-pillado-green-700'
                return (
                  <div key={e.id} className="rounded-lg border bg-white p-3 shadow-sm">
                    <div className="flex items-start justify-between gap-2">
                      <div className="min-w-0 flex-1">
                        <div className="font-mono text-xs text-gray-500">{e.codigo}</div>
                        <div className="truncate text-sm font-semibold">{e.nombre}</div>
                      </div>
                      {(e.estado === 'critico' || e.estado === 'bajo') && (
                        <span className="rounded bg-red-100 px-1.5 py-0.5 text-[10px] font-bold text-red-700">
                          {e.estado === 'critico' ? 'CRÍTICO' : 'BAJO'}
                        </span>
                      )}
                    </div>
                    <div className="mt-2 flex items-baseline justify-between">
                      <span className={`text-xl font-bold ${colorTxt}`}>{fmtLt(Number(e.stock_teorico_lt))}</span>
                      <span className="text-[10px] text-gray-500">/ {fmtLt(Number(e.capacidad_lt))}</span>
                    </div>
                    <div className="mt-1 h-2 w-full overflow-hidden rounded-full bg-gray-100" role="img" aria-label={`${e.porcentaje.toFixed(0)} % lleno`}>
                      <div className={`h-full ${colorBar}`} style={{ width: `${e.porcentaje}%` }} />
                    </div>
                    <div className="mt-1 flex justify-between text-[10px] text-gray-500">
                      <span>{e.porcentaje.toFixed(0)} % lleno</span>
                      {e.stock_minimo_alerta_lt != null && <span>mín: {fmtLt(Number(e.stock_minimo_alerta_lt))}</span>}
                    </div>
                  </div>
                )
              })}
            </div>
          )}
      </CardContent>
    </Card>
  )
}
