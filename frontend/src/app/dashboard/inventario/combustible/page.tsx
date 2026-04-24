'use client'

import { useMemo } from 'react'
import Link from 'next/link'
import {
  ArrowLeft,
  Droplet,
  Fuel,
  AlertTriangle,
  Ruler,
  Plus,
  History,
  Truck,
  TrendingUp,
  Gauge,
} from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Spinner } from '@/components/ui/spinner'
import { cn, formatDate } from '@/lib/utils'
import {
  useEstanques,
  useMovimientosCombustible,
  useConsumoVehiculoMes,
} from '@/hooks/use-combustible'

function fmtLt(n: number | null | undefined) {
  if (n == null) return '—'
  return `${Number(n).toLocaleString('es-CL', { maximumFractionDigits: 1 })} lt`
}

export default function CombustiblePage() {
  const { data: estanques, isLoading: loadingEst } = useEstanques()
  const { data: movimientos } = useMovimientosCombustible({ limit: 10 })

  const mesActualISO = useMemo(() => {
    const d = new Date()
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-01`
  }, [])
  const { data: consumo } = useConsumoVehiculoMes(mesActualISO)

  const totalStock = useMemo(
    () => (estanques ?? []).reduce((s, e) => s + Number(e.stock_teorico_lt ?? 0), 0),
    [estanques]
  )
  const totalCapacidad = useMemo(
    () => (estanques ?? []).reduce((s, e) => s + Number(e.capacidad_lt ?? 0), 0),
    [estanques]
  )
  const nAlertas = (estanques ?? []).filter((e) => e.bajo_minimo).length
  const consumoMes = (consumo ?? []).reduce((s, c) => s + Number(c.litros_total ?? 0), 0)

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center gap-3">
        <Link href="/dashboard/inventario">
          <Button variant="outline" size="sm" className="gap-1">
            <ArrowLeft className="h-4 w-4" /> Inventario
          </Button>
        </Link>
        <h1 className="text-2xl font-bold text-gray-900">Combustible</h1>
      </div>

      {/* KPIs */}
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <Card>
          <CardContent className="flex items-center gap-3 p-4">
            <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-blue-50">
              <Fuel className="h-6 w-6 text-blue-600" />
            </div>
            <div>
              <p className="text-xs text-gray-500">Stock total</p>
              <p className="text-lg font-bold text-gray-900">{fmtLt(totalStock)}</p>
              <p className="text-[11px] text-gray-400">
                de {fmtLt(totalCapacidad)} capacidad
              </p>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="flex items-center gap-3 p-4">
            <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-amber-50">
              <AlertTriangle className="h-6 w-6 text-amber-600" />
            </div>
            <div>
              <p className="text-xs text-gray-500">Estanques bajo minimo</p>
              <p className="text-lg font-bold text-gray-900">{nAlertas}</p>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="flex items-center gap-3 p-4">
            <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-purple-50">
              <TrendingUp className="h-6 w-6 text-purple-600" />
            </div>
            <div>
              <p className="text-xs text-gray-500">Consumo del mes</p>
              <p className="text-lg font-bold text-gray-900">{fmtLt(consumoMes)}</p>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="flex items-center gap-3 p-4">
            <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-green-50">
              <Truck className="h-6 w-6 text-green-600" />
            </div>
            <div>
              <p className="text-xs text-gray-500">Vehiculos abastecidos (mes)</p>
              <p className="text-lg font-bold text-gray-900">{(consumo ?? []).length}</p>
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Acciones rapidas */}
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Link href="/dashboard/inventario/combustible/movimiento?tipo=ingreso">
          <Button className="w-full gap-2" variant="primary">
            <Plus className="h-4 w-4" /> Ingreso (compra)
          </Button>
        </Link>
        <Link href="/dashboard/inventario/combustible/movimiento?tipo=despacho">
          <Button className="w-full gap-2" variant="primary">
            <Droplet className="h-4 w-4" /> Despacho
          </Button>
        </Link>
        <Link href="/dashboard/inventario/combustible/varillaje">
          <Button className="w-full gap-2" variant="outline">
            <Ruler className="h-4 w-4" /> Varillaje diario
          </Button>
        </Link>
        <Link href="/dashboard/inventario/combustible/movimientos">
          <Button className="w-full gap-2" variant="outline">
            <History className="h-4 w-4" /> Historial
          </Button>
        </Link>
        <Link href="/dashboard/inventario/combustible/medidores">
          <Button className="w-full gap-2" variant="outline">
            <Gauge className="h-4 w-4" /> Medidores
          </Button>
        </Link>
      </div>

      {/* Estanques */}
      <div>
        <h2 className="mb-3 text-lg font-semibold text-gray-900">Estanques</h2>
        {loadingEst ? (
          <div className="flex justify-center py-8">
            <Spinner />
          </div>
        ) : (estanques ?? []).length === 0 ? (
          <Card>
            <CardContent className="py-8 text-center text-sm text-gray-500">
              No hay estanques configurados.
            </CardContent>
          </Card>
        ) : (
          <div className="grid grid-cols-1 gap-4 md:grid-cols-2 lg:grid-cols-3">
            {(estanques ?? []).map((e) => {
              const pct = Number(e.pct_llenado ?? 0)
              const barColor =
                pct >= 60 ? 'bg-green-500' : pct >= 25 ? 'bg-amber-500' : 'bg-red-500'
              return (
                <Card key={e.id} className={cn(e.bajo_minimo && 'border-red-300 bg-red-50/30')}>
                  <CardContent className="space-y-3 p-4">
                    <div className="flex items-start justify-between">
                      <div>
                        <div className="text-sm text-gray-500">{e.codigo}</div>
                        <div className="text-base font-semibold text-gray-900">
                          {e.nombre}
                        </div>
                        {e.faena_nombre && (
                          <div className="text-xs text-gray-400">{e.faena_nombre}</div>
                        )}
                      </div>
                      {e.bajo_minimo && (
                        <Badge className="bg-red-100 text-red-700 hover:bg-red-100">
                          Bajo minimo
                        </Badge>
                      )}
                    </div>

                    <div>
                      <div className="flex items-baseline justify-between text-sm">
                        <span className="font-bold text-gray-900">
                          {fmtLt(e.stock_teorico_lt)}
                        </span>
                        <span className="text-xs text-gray-500">
                          de {fmtLt(e.capacidad_lt)} ({pct.toFixed(0)}%)
                        </span>
                      </div>
                      <div className="mt-1 h-2 w-full overflow-hidden rounded-full bg-gray-200">
                        <div
                          className={cn('h-full transition-all', barColor)}
                          style={{ width: `${Math.min(100, pct)}%` }}
                        />
                      </div>
                      <div className="mt-1 text-[11px] text-gray-400">
                        Minimo alerta: {fmtLt(e.stock_minimo_alerta_lt)}
                      </div>
                    </div>

                    <div className="flex items-center justify-between text-xs text-gray-500">
                      <span>
                        {e.n_medidores} medidor{e.n_medidores === 1 ? '' : 'es'}
                      </span>
                      <span>
                        {e.ultima_varillaje_fecha
                          ? `Varillaje ${formatDate(e.ultima_varillaje_fecha)}`
                          : 'Sin varillaje'}
                      </span>
                    </div>

                    {e.ultima_varillaje_diferencia != null && (
                      <div
                        className={cn(
                          'rounded-md px-2 py-1 text-xs',
                          Math.abs(Number(e.ultima_varillaje_diferencia)) < 5
                            ? 'bg-green-50 text-green-700'
                            : 'bg-amber-50 text-amber-700'
                        )}
                      >
                        Ult. dif. varillaje:{' '}
                        {Number(e.ultima_varillaje_diferencia) > 0 ? '+' : ''}
                        {fmtLt(e.ultima_varillaje_diferencia)}
                      </div>
                    )}

                    <div className="flex gap-2 pt-1">
                      <Link
                        href={`/dashboard/inventario/combustible/movimiento?estanque=${e.id}&tipo=ingreso`}
                        className="flex-1"
                      >
                        <Button variant="outline" size="sm" className="w-full text-xs">
                          Ingreso
                        </Button>
                      </Link>
                      <Link
                        href={`/dashboard/inventario/combustible/movimiento?estanque=${e.id}&tipo=despacho`}
                        className="flex-1"
                      >
                        <Button variant="outline" size="sm" className="w-full text-xs">
                          Despacho
                        </Button>
                      </Link>
                      <Link
                        href={`/dashboard/inventario/combustible/varillaje?estanque=${e.id}`}
                        className="flex-1"
                      >
                        <Button variant="outline" size="sm" className="w-full text-xs">
                          Varillaje
                        </Button>
                      </Link>
                    </div>
                  </CardContent>
                </Card>
              )
            })}
          </div>
        )}
      </div>

      {/* Ultimos movimientos */}
      <div>
        <h2 className="mb-3 text-lg font-semibold text-gray-900">
          Ultimos movimientos
        </h2>
        <Card>
          <CardContent className="p-0">
            {(movimientos ?? []).length === 0 ? (
              <div className="py-6 text-center text-sm text-gray-500">
                Sin movimientos aun.
              </div>
            ) : (
              <ul className="divide-y">
                {(movimientos ?? []).slice(0, 8).map((m) => (
                  <li key={m.id} className="flex items-center gap-3 px-4 py-3">
                    <div
                      className={cn(
                        'flex h-9 w-9 items-center justify-center rounded-full',
                        m.tipo === 'ingreso' && 'bg-green-100 text-green-700',
                        m.tipo === 'despacho' && 'bg-blue-100 text-blue-700',
                        m.tipo === 'merma' && 'bg-red-100 text-red-700',
                        m.tipo === 'ajuste' && 'bg-amber-100 text-amber-700'
                      )}
                    >
                      {m.tipo === 'ingreso' ? (
                        <Plus className="h-4 w-4" />
                      ) : m.tipo === 'despacho' ? (
                        <Droplet className="h-4 w-4" />
                      ) : (
                        <AlertTriangle className="h-4 w-4" />
                      )}
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="text-sm font-medium text-gray-900">
                        {m.estanque_codigo} — {fmtLt(m.litros)}
                      </div>
                      <div className="truncate text-xs text-gray-500">
                        {m.tipo === 'despacho'
                          ? m.vehiculo_nombre ||
                            m.vehiculo_codigo ||
                            m.destino_descripcion ||
                            m.destino_tipo
                          : m.tipo === 'ingreso'
                            ? `${m.proveedor ?? 'Proveedor'} ${m.numero_factura ? `• ${m.numero_factura}` : ''}`
                            : (m.observaciones ?? m.tipo)}
                      </div>
                    </div>
                    <div className="text-xs text-gray-400">
                      {formatDate(m.fecha_hora)}
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  )
}
