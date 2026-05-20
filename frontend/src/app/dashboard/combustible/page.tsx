'use client'

import Link from 'next/link'
import {
  Fuel, ArrowUpRight, ArrowDownRight, AlertTriangle, Layers, DollarSign,
  RefreshCw, Scale, ShieldCheck, Gauge, Ban, Wrench,
} from 'lucide-react'
import { QuickActionsGrid } from '@/components/ui/quick-actions-grid'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Spinner } from '@/components/ui/spinner'
import {
  Table, TableHeader, TableBody, TableRow, TableHead, TableCell,
} from '@/components/ui/table'
import { formatCLP, formatDate, formatDateTime, cn } from '@/lib/utils'
import {
  useResumenCombustible, useControlEstanques, useMovimientosCombustible,
} from '@/hooks/use-combustible-cpp'
import type { EstadoControlCombustible } from '@/lib/services/combustible-cpp'
import { useQueryClient } from '@tanstack/react-query'

const ESTADO_COLOR: Record<EstadoControlCombustible, string> = {
  cuadrado:           'bg-green-100 text-green-700',
  sin_varillaje:      'bg-blue-100 text-blue-700',
  varillaje_atrasado: 'bg-amber-100 text-amber-700',
  desviacion_fisica:  'bg-red-100 text-red-700',
  stock_negativo:     'bg-red-200 text-red-900',
}

export default function CombustiblePage() {
  const qc = useQueryClient()
  const resumen = useResumenCombustible()
  const control = useControlEstanques()
  const mov = useMovimientosCombustible(undefined)

  const refresh = () => qc.invalidateQueries({ queryKey: ['combustible'] })

  return (
    <div className="space-y-4 p-6">
      <header className="flex items-start justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-2xl font-bold flex items-center gap-2">
            <Fuel className="h-6 w-6 text-amber-700" />
            Panel Combustible — CPP móvil
          </h1>
          <p className="text-sm text-gray-600 mt-1">
            Stock valorizado, ingresos, salidas y control kardex vs varillaje.
            {resumen.data?.fecha_ultimo_movimiento && (
              <span className="ml-2 text-[11px] text-gray-500">
                Último mov: {formatDateTime(resumen.data.fecha_ultimo_movimiento)}
              </span>
            )}
          </p>
        </div>
        <Button variant="outline" size="sm" onClick={refresh} disabled={resumen.isFetching}>
          <RefreshCw className={cn('h-4 w-4 mr-1', resumen.isFetching && 'animate-spin')} />
          Actualizar
        </Button>
      </header>

      <QuickActionsGrid
        title="Acciones rápidas"
        cols={4}
        actions={[
          { label: 'Ingreso combustible', description: 'Ingreso valorizado con CPP móvil',         href: '/dashboard/combustible/ingreso',           icon: ArrowUpRight,   accent: 'green' },
          { label: 'Salida combustible',  description: 'Salida al CPP vigente con destino',        href: '/dashboard/combustible/salida',            icon: ArrowDownRight, accent: 'red' },
          { label: 'Despacho con sellos', description: 'Salida valorizada + sellos antifraude',    href: '/dashboard/combustible/despacho',          icon: ShieldCheck,    accent: 'amber' },
          { label: 'Control kardex',      description: 'Teórico vs físico vs último kardex',       href: '/dashboard/combustible/control',           icon: Gauge,          accent: 'blue' },
          { label: 'Corregir ingreso',    description: 'Anular ingreso mal cargado (admin)',       href: '/dashboard/combustible/corregir-ingreso',  icon: Ban,            accent: 'red',  badge: 'Admin' },
          { label: 'Ajustar stock',       description: 'Corregir litros físicos del estanque',     href: '/dashboard/combustible/ajuste',            icon: Wrench,         accent: 'purple', badge: 'Admin' },
          { label: 'Corregir patente',    description: 'Cambiar patente de un despacho ya hecho',  href: '/dashboard/combustible/corregir-despacho', icon: Wrench,         accent: 'amber',  badge: 'Admin' },
        ]}
      />

      {/* KPIs */}
      <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-3">
        <Kpi
          icon={<Fuel className="h-4 w-4 text-amber-700" />}
          label="Stock total"
          value={resumen.isLoading ? '—' : `${(resumen.data?.total_litros ?? 0).toLocaleString('es-CL')} lt`}
          hint={`${resumen.data?.estanques_activos ?? 0} estanques activos`}
        />
        <Kpi
          icon={<DollarSign className="h-4 w-4 text-amber-700" />}
          label="Valor total"
          value={resumen.isLoading ? '—' : formatCLP(resumen.data?.valor_total_clp ?? 0)}
        />
        <Kpi
          icon={<Layers className="h-4 w-4 text-blue-700" />}
          label="Con stock"
          value={resumen.isLoading ? '—' : `${resumen.data?.estanques_con_stock ?? 0}/${resumen.data?.estanques_activos ?? 0}`}
        />
        <Kpi
          icon={<AlertTriangle className="h-4 w-4 text-amber-600" />}
          label="Varillaje atrasado"
          value={resumen.isLoading ? '—' : `${resumen.data?.varillaje_atrasado ?? 0}`}
          urgent={!!resumen.data?.varillaje_atrasado}
        />
        <Kpi
          icon={<AlertTriangle className="h-4 w-4 text-red-600" />}
          label="Desviación física"
          value={resumen.isLoading ? '—' : `${resumen.data?.desviacion_fisica ?? 0}`}
          urgent={!!resumen.data?.desviacion_fisica}
        />
        <Kpi
          icon={<AlertTriangle className="h-4 w-4 text-red-700" />}
          label="Bajo mínimo"
          value={resumen.isLoading ? '—' : `${resumen.data?.estanques_bajo_minimo ?? 0}`}
          urgent={!!resumen.data?.estanques_bajo_minimo}
        />
      </div>

      {/* Tabla estanques */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base">Estanques</CardTitle>
        </CardHeader>
        <CardContent className="px-0">
          {control.isLoading ? (
            <div className="flex justify-center py-10"><Spinner /></div>
          ) : (control.data?.length ?? 0) === 0 ? (
            <div className="text-center text-sm text-gray-500 py-10">Sin estanques</div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Estanque</TableHead>
                  <TableHead className="text-right">Stock (lt)</TableHead>
                  <TableHead className="text-right">CPP</TableHead>
                  <TableHead className="text-right">Valor</TableHead>
                  <TableHead className="text-right">Último varillaje</TableHead>
                  <TableHead className="text-right">Δ físico</TableHead>
                  <TableHead>Estado</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {(control.data ?? []).map((e) => (
                  <TableRow key={e.estanque_id}>
                    <TableCell>
                      <div className="font-medium text-sm">{e.estanque_nombre}</div>
                      <div className="text-[11px] text-gray-500 font-mono">
                        {e.estanque_codigo} · cap {Number(e.capacidad_lt).toLocaleString('es-CL')} lt
                      </div>
                    </TableCell>
                    <TableCell className="text-right tabular-nums">
                      {Number(e.stock_teorico_lt).toFixed(2)}
                      {e.bajo_minimo && (
                        <div className="text-[10px] text-red-700">bajo min</div>
                      )}
                    </TableCell>
                    <TableCell className="text-right tabular-nums font-mono">{formatCLP(Number(e.cpp_actual))}</TableCell>
                    <TableCell className="text-right tabular-nums font-mono font-semibold">{formatCLP(Number(e.valor_teorico_clp))}</TableCell>
                    <TableCell className="text-right">
                      {e.ultimo_varillaje_lt != null ? (
                        <>
                          <div className="text-sm tabular-nums">{Number(e.ultimo_varillaje_lt).toFixed(0)} lt</div>
                          <div className="text-[10px] text-gray-500">
                            {e.fecha_ultimo_varillaje && formatDate(e.fecha_ultimo_varillaje)}
                            {e.dias_desde_varilla != null && ` (${e.dias_desde_varilla}d)`}
                          </div>
                        </>
                      ) : <span className="text-xs text-gray-400">—</span>}
                    </TableCell>
                    <TableCell className="text-right tabular-nums">
                      {e.delta_lt != null ? (
                        <span className={cn(Math.abs(e.delta_lt) > 50 ? 'text-red-700 font-semibold' : '')}>
                          {Number(e.delta_lt).toFixed(2)}
                        </span>
                      ) : '—'}
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

      {/* Últimos movimientos */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base">Últimos movimientos valorizados</CardTitle>
        </CardHeader>
        <CardContent className="px-0">
          {mov.isLoading ? (
            <div className="flex justify-center py-10"><Spinner /></div>
          ) : (mov.data?.length ?? 0) === 0 ? (
            <div className="text-center text-sm text-gray-500 py-10">Sin movimientos</div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Fecha</TableHead>
                  <TableHead>Tipo</TableHead>
                  <TableHead>Folio</TableHead>
                  <TableHead>Estanque</TableHead>
                  <TableHead className="text-right">Lt</TableHead>
                  <TableHead className="text-right">Costo unit</TableHead>
                  <TableHead className="text-right">Stock post</TableHead>
                  <TableHead className="text-right">CPP post</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {(mov.data ?? []).slice(0, 25).map((m) => {
                  const esIngreso = Number(m.litros_entrada) > 0
                  return (
                    <TableRow key={m.kardex_id}>
                      <TableCell className="text-xs whitespace-nowrap">{formatDateTime(m.fecha_movimiento)}</TableCell>
                      <TableCell>
                        <Badge className={
                          m.tipo_movimiento.startsWith('ingreso') ? 'bg-green-100 text-green-700'
                            : m.tipo_movimiento === 'stock_inicial' ? 'bg-blue-100 text-blue-700'
                            : 'bg-amber-100 text-amber-700'
                        }>{m.tipo_movimiento}</Badge>
                      </TableCell>
                      <TableCell className="text-xs font-mono">{m.folio_movimiento ?? '—'}</TableCell>
                      <TableCell className="text-xs">{m.estanque_codigo}</TableCell>
                      <TableCell className="text-right tabular-nums">
                        <span className={esIngreso ? 'text-green-700' : 'text-red-700'}>
                          {esIngreso ? '+' : '-'}{(esIngreso ? Number(m.litros_entrada) : Number(m.litros_salida)).toFixed(2)}
                        </span>
                      </TableCell>
                      <TableCell className="text-right tabular-nums font-mono">{formatCLP(Number(m.costo_unitario_movimiento))}</TableCell>
                      <TableCell className="text-right tabular-nums">{Number(m.stock_lt_despues).toFixed(2)}</TableCell>
                      <TableCell className="text-right tabular-nums font-mono">{formatCLP(Number(m.cpp_despues))}</TableCell>
                    </TableRow>
                  )
                })}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
    </div>
  )
}

function Kpi({
  icon, label, value, hint, urgent,
}: { icon: React.ReactNode; label: string; value: string; hint?: string; urgent?: boolean }) {
  return (
    <Card className={cn(urgent && 'border-amber-400 bg-amber-50')}>
      <CardContent className="p-4">
        <div className="flex items-center justify-between">
          <span className="text-xs font-semibold uppercase text-gray-600">{label}</span>
          {icon}
        </div>
        <div className="mt-1 text-xl font-bold tabular-nums">{value}</div>
        {hint && <div className="text-[11px] text-gray-600 mt-1">{hint}</div>}
      </CardContent>
    </Card>
  )
}
