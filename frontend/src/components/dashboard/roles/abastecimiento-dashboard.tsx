'use client'

import Link from 'next/link'
import { useMemo } from 'react'
import { Fuel, AlertTriangle, ArrowDownRight, Truck } from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Spinner } from '@/components/ui/spinner'
import { useEstanques, useMovimientosCombustible, useConsumoVehiculoMes } from '@/hooks/use-combustible'
import { formatDate } from '@/lib/utils'

/**
 * Dashboard operador_abastecimiento.
 * Foco: stock combustible, ingresos/salidas del dia, despachos pendientes.
 *
 * NOTA FASE 5.6: cuando se aplique mig 55+57, agregar:
 *   - "Valor stock combustible" (combustible_estanques.valor_total_stock)
 *   - "Despachos con sellos pendientes" (estado=programado/en_ruta)
 *   - "Diferencias varillaje > tolerancia"
 *   - "Kardex valorizado" (v_combustible_kardex_valorizado)
 */
export function AbastecimientoDashboard() {
  const { data: estanques, isLoading: loadingEst } = useEstanques()
  const { data: movimientos } = useMovimientosCombustible({ limit: 10 })

  const mesActualISO = useMemo(() => {
    const d = new Date()
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-01`
  }, [])
  const { data: consumo } = useConsumoVehiculoMes(mesActualISO)

  const totalStock = useMemo(
    () => (estanques ?? []).reduce((s: number, e: any) => s + Number(e.stock_teorico_lt ?? 0), 0),
    [estanques]
  )
  const totalCapacidad = useMemo(
    () => (estanques ?? []).reduce((s: number, e: any) => s + Number(e.capacidad_lt ?? 0), 0),
    [estanques]
  )
  const nAlertas = (estanques ?? []).filter((e: any) => e.bajo_minimo).length
  const consumoMes = (consumo ?? []).reduce(
    (s: number, c: any) => s + Number(c.litros_total ?? 0),
    0
  )

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Panel de Abastecimiento</h1>
        <p className="text-sm text-gray-500">Combustible, despachos, varillaje</p>
      </div>

      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <KPI
          label="Stock total"
          value={
            loadingEst ? null : `${totalStock.toLocaleString('es-CL')} lt`
          }
          icon={<Fuel className="h-5 w-5 text-blue-600" />}
          isText
        />
        <KPI
          label="Capacidad"
          value={
            loadingEst ? null : `${totalCapacidad.toLocaleString('es-CL')} lt`
          }
          icon={<Fuel className="h-5 w-5 text-gray-500" />}
          isText
        />
        <KPI
          label="Estanques bajo mínimo"
          value={loadingEst ? null : nAlertas}
          icon={<AlertTriangle className="h-5 w-5 text-red-600" />}
          accent={nAlertas > 0 ? 'red' : undefined}
        />
        <KPI
          label="Consumo mes (lt)"
          value={Math.round(consumoMes).toLocaleString('es-CL')}
          icon={<ArrowDownRight className="h-5 w-5 text-orange-600" />}
          isText
        />
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-base">
              <Fuel className="h-5 w-5 text-blue-600" />
              Estanques
            </CardTitle>
          </CardHeader>
          <CardContent>
            {loadingEst ? (
              <div className="flex justify-center py-4">
                <Spinner />
              </div>
            ) : (estanques ?? []).length === 0 ? (
              <p className="text-sm text-gray-400 py-4 text-center">Sin estanques registrados</p>
            ) : (
              <ul className="divide-y">
                {(estanques ?? []).slice(0, 4).map((e: any) => {
                  const pct = e.capacidad_lt > 0 ? (e.stock_teorico_lt / e.capacidad_lt) * 100 : 0
                  const lowStock = e.bajo_minimo
                  return (
                    <li key={e.id} className="py-2">
                      <div className="flex justify-between items-baseline">
                        <span className="text-sm font-medium text-gray-900">
                          {e.codigo} · {e.nombre}
                        </span>
                        <span className={`text-xs ${lowStock ? 'text-red-600 font-bold' : 'text-gray-500'}`}>
                          {Math.round(e.stock_teorico_lt)} / {Math.round(e.capacidad_lt)} lt
                        </span>
                      </div>
                      <div className="mt-1 h-1.5 bg-gray-100 rounded overflow-hidden">
                        <div
                          className={`h-full ${lowStock ? 'bg-red-400' : 'bg-blue-400'}`}
                          style={{ width: `${Math.min(pct, 100)}%` }}
                        />
                      </div>
                    </li>
                  )
                })}
              </ul>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-base">
              <Truck className="h-5 w-5 text-gray-600" />
              Movimientos recientes
            </CardTitle>
          </CardHeader>
          <CardContent>
            {(movimientos ?? []).length === 0 ? (
              <p className="text-sm text-gray-400 py-4 text-center">Sin movimientos recientes</p>
            ) : (
              <ul className="divide-y">
                {(movimientos ?? []).slice(0, 6).map((m: any) => (
                  <li key={m.id} className="flex items-center justify-between py-2 text-sm">
                    <span className="text-gray-700">
                      {m.tipo} · {Math.round(Number(m.litros))} lt
                    </span>
                    <span className="text-xs text-gray-500">
                      {m.fecha_hora ? formatDate(m.fecha_hora) : '—'}
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Acciones de hoy</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-2">
            <QuickLink href="/dashboard/inventario/combustible" label="Combustible" />
            <QuickLink href="/dashboard/inventario/combustible/movimiento" label="Registrar movimiento" />
            <QuickLink href="/dashboard/inventario/combustible/varillaje" label="Varillaje" />
            <QuickLink href="/dashboard/abastecimiento" label="Abastecimiento" />
          </div>
        </CardContent>
      </Card>
    </div>
  )
}

function KPI({
  label,
  value,
  icon,
  accent,
  isText,
}: {
  label: string
  value: number | string | null
  icon: React.ReactNode
  accent?: 'red'
  isText?: boolean
}) {
  const colorClass = accent === 'red' ? 'text-red-600' : 'text-gray-900'
  const sizeClass = isText ? 'text-xl' : 'text-3xl'
  return (
    <Card>
      <CardContent className="p-4">
        <div className="flex items-center justify-between">
          <p className="text-xs text-gray-500">{label}</p>
          {icon}
        </div>
        <p className={`mt-1 ${sizeClass} font-bold ${colorClass}`}>
          {value === null ? <Spinner size="sm" /> : value}
        </p>
      </CardContent>
    </Card>
  )
}

function QuickLink({ href, label }: { href: string; label: string }) {
  return (
    <Link
      href={href}
      className="rounded-md border border-gray-200 bg-white px-3 py-2 text-sm text-gray-700 text-center hover:bg-gray-50 hover:border-pillado-green-400"
    >
      {label}
    </Link>
  )
}
