'use client'

import Link from 'next/link'
import { ArrowLeft, Scale, RefreshCw } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Spinner } from '@/components/ui/spinner'
import {
  Table, TableHeader, TableBody, TableRow, TableHead, TableCell,
} from '@/components/ui/table'
import { formatCLP, formatDate, cn } from '@/lib/utils'
import { useControlEstanques } from '@/hooks/use-combustible-cpp'
import type { EstadoControlCombustible } from '@/lib/services/combustible-cpp'
import { useQueryClient } from '@tanstack/react-query'

const ESTADO_COLOR: Record<EstadoControlCombustible, string> = {
  cuadrado:           'bg-green-100 text-green-700',
  sin_varillaje:      'bg-blue-100 text-blue-700',
  varillaje_atrasado: 'bg-amber-100 text-amber-700',
  desviacion_fisica:  'bg-red-100 text-red-700',
  stock_negativo:     'bg-red-200 text-red-900',
}

export default function CombustibleControlPage() {
  const qc = useQueryClient()
  const { data, isLoading, isFetching } = useControlEstanques()

  return (
    <div className="space-y-4 p-6">
      <div className="flex items-center gap-2 flex-wrap">
        <Link href="/dashboard/combustible">
          <Button variant="outline" size="sm">
            <ArrowLeft className="h-4 w-4 mr-1" /> Volver
          </Button>
        </Link>
        <h1 className="text-xl font-bold flex items-center gap-2">
          <Scale className="h-5 w-5 text-amber-700" />
          Control kardex vs varillaje
        </h1>
        <div className="flex-1" />
        <Button variant="outline" size="sm"
          onClick={() => qc.invalidateQueries({ queryKey: ['combustible'] })}
          disabled={isFetching}>
          <RefreshCw className={cn('h-4 w-4 mr-1', isFetching && 'animate-spin')} />
          Actualizar
        </Button>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Estado consolidado por estanque</CardTitle>
          <p className="text-xs text-gray-600">
            Compara stock teórico, último varillaje físico y kardex valorizado.
            Estados: cuadrado / sin_varillaje / varillaje_atrasado (&gt;7d) /
            desviacion_fisica (&gt;50 lt) / stock_negativo.
          </p>
        </CardHeader>
        <CardContent className="px-0">
          {isLoading ? (
            <div className="flex justify-center py-10"><Spinner /></div>
          ) : (data?.length ?? 0) === 0 ? (
            <div className="text-center text-sm text-gray-500 py-10">Sin estanques</div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Estanque</TableHead>
                  <TableHead className="text-right">Capacidad</TableHead>
                  <TableHead className="text-right">Stock teórico</TableHead>
                  <TableHead className="text-right">Varilla físico</TableHead>
                  <TableHead className="text-right">Δ lt</TableHead>
                  <TableHead className="text-right">Δ %</TableHead>
                  <TableHead className="text-right">CPP</TableHead>
                  <TableHead className="text-right">Valor</TableHead>
                  <TableHead>Última varilla</TableHead>
                  <TableHead>Último mov</TableHead>
                  <TableHead>Estado</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {(data ?? []).map((e) => (
                  <TableRow key={e.estanque_id}>
                    <TableCell>
                      <div className="font-medium text-sm">{e.estanque_nombre}</div>
                      <div className="text-[11px] text-gray-500 font-mono">{e.estanque_codigo}</div>
                      {e.bajo_minimo && (
                        <Badge className="bg-red-100 text-red-700 mt-1">bajo mínimo</Badge>
                      )}
                    </TableCell>
                    <TableCell className="text-right tabular-nums">{Number(e.capacidad_lt).toLocaleString('es-CL')}</TableCell>
                    <TableCell className="text-right tabular-nums">{Number(e.stock_teorico_lt).toFixed(2)}</TableCell>
                    <TableCell className="text-right tabular-nums">
                      {e.ultimo_varillaje_lt != null ? Number(e.ultimo_varillaje_lt).toFixed(2) : '—'}
                    </TableCell>
                    <TableCell className="text-right tabular-nums">
                      {e.delta_lt != null ? (
                        <span className={cn(Math.abs(e.delta_lt) > 50 ? 'text-red-700 font-semibold' : '')}>
                          {Number(e.delta_lt).toFixed(2)}
                        </span>
                      ) : '—'}
                    </TableCell>
                    <TableCell className="text-right tabular-nums">
                      {e.delta_pct != null ? `${Number(e.delta_pct).toFixed(2)}%` : '—'}
                    </TableCell>
                    <TableCell className="text-right tabular-nums font-mono">{formatCLP(Number(e.cpp_actual))}</TableCell>
                    <TableCell className="text-right tabular-nums font-mono font-semibold">{formatCLP(Number(e.valor_teorico_clp))}</TableCell>
                    <TableCell className="text-xs">
                      {e.fecha_ultimo_varillaje ? (
                        <>
                          {formatDate(e.fecha_ultimo_varillaje)}
                          {e.dias_desde_varilla != null && (
                            <div className={cn(
                              'text-[10px]',
                              e.dias_desde_varilla > 7 ? 'text-amber-700 font-semibold' : 'text-gray-500',
                            )}>
                              hace {e.dias_desde_varilla}d
                            </div>
                          )}
                        </>
                      ) : <span className="text-gray-400">sin reg.</span>}
                    </TableCell>
                    <TableCell className="text-xs">
                      {e.fecha_ultimo_movimiento ? (
                        <>
                          <div>{formatDate(e.fecha_ultimo_movimiento)}</div>
                          {e.tipo_ultimo_movimiento && (
                            <div className="text-[10px] text-gray-500 font-mono">{e.tipo_ultimo_movimiento}</div>
                          )}
                        </>
                      ) : <span className="text-gray-400">—</span>}
                    </TableCell>
                    <TableCell>
                      <Badge className={ESTADO_COLOR[e.estado]}>{e.estado}</Badge>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
