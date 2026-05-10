'use client'

import Link from 'next/link'
import { Package, ArrowDownRight, ArrowUpRight, AlertTriangle, FileSpreadsheet } from 'lucide-react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Spinner } from '@/components/ui/spinner'
import { useStockBodega, useValorizacionTotal, useMovimientos } from '@/hooks/use-inventario'
import { formatCLP, formatDate } from '@/lib/utils'

/**
 * Dashboard bodeguero.
 * Foco: stock bajo, salidas/recepciones recientes, accesos a inventario.
 *
 * NOTA FASE 5.6: cuando se aplique mig 55-56, agregar:
 *   - "Recepciones pendientes contra OC" (tabla recepciones_bodega)
 *   - "OC parciales" (ordenes_compra estado=parcial)
 *   - "Productos sin capa FIFO" (alerta legacy)
 *   - "Stock valorizado FIFO" (vista v_stock_valorizado_fifo)
 */
export function BodegueroDashboard() {
  const { data: stock, isLoading: loadingStock } = useStockBodega()
  const { data: valorizacion, isLoading: loadingValor } = useValorizacionTotal()
  const { data: movimientos } = useMovimientos({})

  const stockBajo = (stock ?? []).filter(
    (s: any) => s.cantidad < (s.producto?.stock_minimo ?? 0)
  )
  const movsRecientes = (movimientos ?? []).slice(0, 6)

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Panel de Bodega</h1>
        <p className="text-sm text-gray-500">Stock, recepciones, salidas, valorización</p>
      </div>

      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <KPI
          label="Productos en stock"
          value={loadingStock ? null : (stock?.length ?? 0)}
          icon={<Package className="h-5 w-5 text-blue-600" />}
        />
        <KPI
          label="Inventario valorizado"
          value={
            loadingValor
              ? null
              : valorizacion != null
              ? formatCLP(valorizacion as number)
              : '—'
          }
          icon={<FileSpreadsheet className="h-5 w-5 text-emerald-600" />}
          isCurrency
        />
        <KPI
          label="Stock bajo mínimo"
          value={loadingStock ? null : stockBajo.length}
          icon={<AlertTriangle className="h-5 w-5 text-red-600" />}
          accent={stockBajo.length > 0 ? 'red' : undefined}
        />
        <KPI
          label="Movimientos recientes"
          value={movsRecientes.length}
          icon={<ArrowDownRight className="h-5 w-5 text-gray-600" />}
        />
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-base">
              <AlertTriangle className="h-5 w-5 text-red-500" />
              Productos bajo mínimo
            </CardTitle>
          </CardHeader>
          <CardContent>
            {loadingStock ? (
              <div className="flex justify-center py-4">
                <Spinner />
              </div>
            ) : stockBajo.length === 0 ? (
              <p className="text-sm text-gray-400 py-4 text-center">Todos los productos sobre mínimo</p>
            ) : (
              <ul className="divide-y">
                {stockBajo.slice(0, 5).map((s: any) => (
                  <li key={s.id} className="flex items-center justify-between py-2">
                    <div>
                      <p className="font-medium text-sm text-gray-900">{s.producto?.nombre}</p>
                      <p className="text-xs text-gray-500">{s.producto?.codigo}</p>
                    </div>
                    <div className="text-right">
                      <p className="text-sm font-semibold text-red-600">
                        {s.cantidad} {s.producto?.unidad_medida}
                      </p>
                      <p className="text-xs text-gray-400">mín: {s.producto?.stock_minimo}</p>
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-base">
              <ArrowUpRight className="h-5 w-5 text-blue-600" />
              Movimientos recientes
            </CardTitle>
          </CardHeader>
          <CardContent>
            {movsRecientes.length === 0 ? (
              <p className="text-sm text-gray-400 py-4 text-center">Sin movimientos recientes</p>
            ) : (
              <ul className="divide-y">
                {movsRecientes.map((m: any) => (
                  <li key={m.id} className="flex items-center justify-between py-2 text-sm">
                    <span className="text-gray-700">{m.tipo}</span>
                    <span className="text-xs text-gray-500">
                      {m.created_at ? formatDate(m.created_at) : '—'}
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
            <QuickLink href="/dashboard/inventario" label="Stock General" />
            <QuickLink href="/dashboard/inventario/salida" label="Registrar Salida" />
            <QuickLink href="/dashboard/inventario/conteo" label="Conteo" />
            <QuickLink href="/dashboard/inventario/scanner" label="Scanner" />
            <QuickLink href="/dashboard/inventario/reconciliacion" label="Reconciliación" />
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
  isCurrency,
}: {
  label: string
  value: number | string | null
  icon: React.ReactNode
  accent?: 'red'
  isCurrency?: boolean
}) {
  const colorClass = accent === 'red' ? 'text-red-600' : 'text-gray-900'
  const sizeClass = isCurrency ? 'text-xl' : 'text-3xl'
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
