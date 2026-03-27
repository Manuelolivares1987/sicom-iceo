'use client'

import { useState, useMemo } from 'react'
import Link from 'next/link'
import {
  Search,
  DollarSign,
  Package,
  AlertTriangle,
  FileWarning,
  ChevronDown,
  ArrowUpRight,
  ArrowDownRight,
  ArrowLeftRight,
  Download,
  CheckCircle2,
} from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Input } from '@/components/ui/input'
import { Spinner } from '@/components/ui/spinner'
import {
  Table,
  TableHeader,
  TableBody,
  TableRow,
  TableHead,
  TableCell,
} from '@/components/ui/table'
import { formatCLP, formatDate, cn } from '@/lib/utils'
import {
  useStockBodega,
  useValorizacionTotal,
  useMovimientos,
  useBodegas,
} from '@/hooks/use-inventario'

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
const categorias = ['Todas', 'Combustible', 'Lubricante', 'Filtro', 'Repuesto']

function getMovimientoIcon(tipo: string) {
  switch (tipo) {
    case 'entrada':
      return <ArrowDownRight className="h-4 w-4 text-green-600" />
    case 'salida':
      return <ArrowUpRight className="h-4 w-4 text-red-600" />
    case 'transferencia_entrada':
    case 'transferencia_salida':
      return <ArrowLeftRight className="h-4 w-4 text-blue-600" />
    default:
      return <FileWarning className="h-4 w-4 text-yellow-600" />
  }
}

function getMovimientoBadge(tipo: string) {
  const map: Record<string, string> = {
    entrada: 'bg-green-100 text-green-700',
    salida: 'bg-red-100 text-red-700',
    transferencia_entrada: 'bg-blue-100 text-blue-700',
    transferencia_salida: 'bg-blue-100 text-blue-700',
    ajuste_positivo: 'bg-yellow-100 text-yellow-700',
    ajuste_negativo: 'bg-yellow-100 text-yellow-700',
    merma: 'bg-orange-100 text-orange-700',
    devolucion: 'bg-purple-100 text-purple-700',
  }
  const labels: Record<string, string> = {
    entrada: 'Entrada',
    salida: 'Salida',
    transferencia_entrada: 'Transf. Entrada',
    transferencia_salida: 'Transf. Salida',
    ajuste_positivo: 'Ajuste (+)',
    ajuste_negativo: 'Ajuste (-)',
    merma: 'Merma',
    devolucion: 'Devolucion',
  }
  return (
    <span className={`inline-flex items-center gap-1 rounded-full px-2.5 py-0.5 text-xs font-semibold ${map[tipo] || 'bg-gray-100 text-gray-700'}`}>
      {getMovimientoIcon(tipo)}
      {labels[tipo] || tipo}
    </span>
  )
}

// ---------------------------------------------------------------------------
// CSV export helper
// ---------------------------------------------------------------------------
function exportAlertasCSV(data: any[]) {
  const headers = ['Codigo', 'Producto', 'Stock Actual', 'Stock Min', 'Stock Max', 'Cantidad a Comprar', 'Costo Unit.', 'Costo Total Estimado'].join(',')
  const rows = data.map((item) => {
    const prod = item.producto
    const cantidadComprar = Math.max(0, (prod?.stock_maximo ?? 0) - item.cantidad)
    const costoUnit = item.costo_promedio ?? 0
    const costoTotal = cantidadComprar * costoUnit
    return [
      prod?.codigo ?? '',
      `"${(prod?.nombre ?? '').replace(/"/g, '""')}"`,
      item.cantidad ?? 0,
      prod?.stock_minimo ?? 0,
      prod?.stock_maximo ?? 0,
      cantidadComprar,
      costoUnit,
      costoTotal,
    ].join(',')
  }).join('\n')

  const bom = '\uFEFF'
  const blob = new Blob([bom + headers + '\n' + rows], { type: 'text/csv;charset=utf-8;' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = 'lista-compra.csv'
  a.click()
  URL.revokeObjectURL(url)
}

// ---------------------------------------------------------------------------
// Main tabs
// ---------------------------------------------------------------------------
const mainTabs = [
  { id: 'stock', label: 'Stock' },
  { id: 'movimientos', label: 'Movimientos' },
  { id: 'alertas', label: 'Alertas', icon: AlertTriangle },
  { id: 'conteos', label: 'Conteos' },
  { id: 'kardex', label: 'Kardex' },
]

// ---------------------------------------------------------------------------
// Main page
// ---------------------------------------------------------------------------
export default function InventarioPage() {
  const [activeTab, setActiveTab] = useState('stock')
  const [search, setSearch] = useState('')
  const [categoriaFilter, setCategoriaFilter] = useState('Todas')
  const [bodegaFilter, setBodegaFilter] = useState('')
  const [movTipoFilter, setMovTipoFilter] = useState('')

  // Hooks
  const stockFilters: Record<string, unknown> = {}
  if (bodegaFilter) stockFilters.bodega_id = bodegaFilter
  if (categoriaFilter !== 'Todas') stockFilters.categoria = categoriaFilter

  const { data: stockData, isLoading: loadingStock } = useStockBodega(stockFilters)
  const { data: valorizacion, isLoading: loadingValorizacion } = useValorizacionTotal()
  const { data: bodegas } = useBodegas()

  // Alertas: products below minimum stock
  const { data: alertasData, isLoading: loadingAlertas } = useStockBodega({ below_minimum: true })

  const movFilters: Record<string, unknown> = {}
  if (bodegaFilter) movFilters.bodega_id = bodegaFilter
  if (movTipoFilter) movFilters.tipo = movTipoFilter

  const { data: movimientosData, isLoading: loadingMovimientos } = useMovimientos(movFilters)

  // Client-side search filter on stock
  const filteredStock = useMemo(() => {
    if (!stockData) return []
    return (stockData as any[]).filter((s) => {
      if (!search) return true
      const term = search.toLowerCase()
      const prod = s.producto
      return (
        (prod?.codigo ?? '').toLowerCase().includes(term) ||
        (prod?.nombre ?? '').toLowerCase().includes(term)
      )
    })
  }, [stockData, search])

  // Stats
  const totalProductos = filteredStock.length
  const alertasBajo = useMemo(() => {
    if (!stockData) return 0
    return (stockData as any[]).filter(
      (s) => s.cantidad < (s.producto?.stock_minimo ?? 0)
    ).length
  }, [stockData])

  // Alertas computed values
  const alertasList = useMemo(() => (alertasData ?? []) as any[], [alertasData])
  const inversionEstimada = useMemo(() => {
    return alertasList.reduce((sum, item) => {
      const cantidadComprar = Math.max(0, (item.producto?.stock_maximo ?? 0) - item.cantidad)
      return sum + cantidadComprar * (item.costo_promedio ?? 0)
    }, 0)
  }, [alertasList])

  const bodegaOptions = [
    { value: '', label: 'Todas' },
    ...(bodegas ?? []).map((b: any) => ({ value: b.id, label: b.nombre })),
  ]

  // Stats cards
  const stats = [
    {
      label: 'Valorizacion Total',
      value: loadingValorizacion ? '...' : formatCLP(valorizacion ?? 0),
      icon: DollarSign,
      color: 'text-pillado-green-600',
      bg: 'bg-pillado-green-50',
    },
    {
      label: 'Items en Stock',
      value: loadingStock ? '...' : String(totalProductos),
      icon: Package,
      color: 'text-blue-600',
      bg: 'bg-blue-50',
    },
    {
      label: 'Alertas Stock Bajo',
      value: loadingStock ? '...' : String(alertasBajo),
      icon: AlertTriangle,
      color: 'text-amber-600',
      bg: 'bg-amber-50',
    },
  ]

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold text-gray-900">Inventario</h1>

      {/* Stats */}
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-3">
        {stats.map((s) => {
          const Icon = s.icon
          return (
            <Card key={s.label}>
              <CardContent className="flex items-center gap-4 p-4">
                <div className={cn('flex h-12 w-12 items-center justify-center rounded-xl', s.bg)}>
                  <Icon className={cn('h-6 w-6', s.color)} />
                </div>
                <div>
                  <p className="text-xs text-gray-500">{s.label}</p>
                  <p className="text-lg font-bold text-gray-900">{s.value}</p>
                </div>
              </CardContent>
            </Card>
          )
        })}
      </div>

      {/* Tabs */}
      <div className="flex gap-1 overflow-x-auto rounded-xl bg-gray-100 p-1">
        {mainTabs.map((tab) => {
          const TabIcon = tab.icon
          return (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`flex flex-1 items-center justify-center gap-1.5 whitespace-nowrap rounded-lg px-4 py-2 text-sm font-medium transition-colors ${
                activeTab === tab.id
                  ? 'bg-white text-pillado-green-600 shadow-sm'
                  : 'text-gray-500 hover:text-gray-700'
              }`}
            >
              {TabIcon && <TabIcon className="h-4 w-4" />}
              {tab.label}
            </button>
          )
        })}
      </div>

      {/* Stock Tab */}
      {activeTab === 'stock' && (
        <>
          {/* Filters */}
          <Card>
            <CardContent className="flex flex-col gap-3 p-4 sm:flex-row sm:items-end">
              <div className="flex-1 sm:max-w-xs">
                <Input
                  placeholder="Buscar codigo o producto..."
                  value={search}
                  onChange={(e) => setSearch(e.target.value)}
                />
              </div>
              <div className="w-full sm:w-44">
                <label className="mb-1 block text-xs font-medium text-gray-500">Categoria</label>
                <div className="relative">
                  <select
                    value={categoriaFilter}
                    onChange={(e) => setCategoriaFilter(e.target.value)}
                    className="h-10 w-full appearance-none rounded-lg border border-gray-300 bg-white px-3 pr-8 text-sm focus:border-pillado-green-500 focus:outline-none focus:ring-2 focus:ring-pillado-green-500/20"
                  >
                    {categorias.map((c) => (
                      <option key={c} value={c}>{c}</option>
                    ))}
                  </select>
                  <ChevronDown className="pointer-events-none absolute right-2 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400" />
                </div>
              </div>
              <div className="w-full sm:w-44">
                <label className="mb-1 block text-xs font-medium text-gray-500">Bodega</label>
                <div className="relative">
                  <select
                    value={bodegaFilter}
                    onChange={(e) => setBodegaFilter(e.target.value)}
                    className="h-10 w-full appearance-none rounded-lg border border-gray-300 bg-white px-3 pr-8 text-sm focus:border-pillado-green-500 focus:outline-none focus:ring-2 focus:ring-pillado-green-500/20"
                  >
                    {bodegaOptions.map((b) => (
                      <option key={b.value} value={b.value}>{b.label}</option>
                    ))}
                  </select>
                  <ChevronDown className="pointer-events-none absolute right-2 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400" />
                </div>
              </div>
            </CardContent>
          </Card>

          {/* Loading */}
          {loadingStock && (
            <div className="flex justify-center py-16">
              <Spinner size="lg" className="text-pillado-green-600" />
            </div>
          )}

          {/* Stock table */}
          {!loadingStock && (
            <Card>
              <div className="hidden md:block">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Codigo</TableHead>
                      <TableHead>Producto</TableHead>
                      <TableHead>Categoria</TableHead>
                      <TableHead>Bodega</TableHead>
                      <TableHead className="text-right">Stock</TableHead>
                      <TableHead>Unidad</TableHead>
                      <TableHead className="text-right">Costo Prom.</TableHead>
                      <TableHead className="text-right">Valor Total</TableHead>
                      <TableHead className="text-center">Estado</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {filteredStock.map((s: any) => {
                      const prod = s.producto
                      const bod = s.bodega
                      const bajo = s.cantidad < (prod?.stock_minimo ?? 0)
                      return (
                        <TableRow key={s.id}>
                          <TableCell className="font-mono text-xs font-semibold">{prod?.codigo ?? '--'}</TableCell>
                          <TableCell className="font-medium">{prod?.nombre ?? '--'}</TableCell>
                          <TableCell className="text-xs text-gray-500">{prod?.categoria ?? '--'}</TableCell>
                          <TableCell className="text-xs text-gray-500">{bod?.nombre ?? '--'}</TableCell>
                          <TableCell className={cn('text-right font-semibold', bajo && 'text-red-600')}>
                            {s.cantidad?.toLocaleString('es-CL') ?? 0}
                          </TableCell>
                          <TableCell className="text-xs text-gray-500">{prod?.unidad_medida ?? '--'}</TableCell>
                          <TableCell className="text-right">{formatCLP(s.costo_promedio ?? 0)}</TableCell>
                          <TableCell className="text-right font-medium">
                            {formatCLP(s.valor_total ?? 0)}
                          </TableCell>
                          <TableCell className="text-center">
                            {bajo ? (
                              <span className="inline-flex h-3 w-3 rounded-full bg-red-500" title="Stock bajo" />
                            ) : (
                              <span className="inline-flex h-3 w-3 rounded-full bg-green-500" title="OK" />
                            )}
                          </TableCell>
                        </TableRow>
                      )
                    })}
                    {filteredStock.length === 0 && (
                      <TableRow>
                        <TableCell colSpan={9} className="py-8 text-center text-sm text-gray-400">
                          No hay productos en stock
                        </TableCell>
                      </TableRow>
                    )}
                  </TableBody>
                </Table>
              </div>

              {/* Mobile stock */}
              <div className="space-y-2 p-4 md:hidden">
                {filteredStock.map((s: any) => {
                  const prod = s.producto
                  const bajo = s.cantidad < (prod?.stock_minimo ?? 0)
                  return (
                    <div key={s.id} className="rounded-lg border border-gray-100 p-3">
                      <div className="flex items-start justify-between">
                        <div>
                          <p className="text-sm font-semibold text-gray-900">{prod?.nombre ?? '--'}</p>
                          <p className="font-mono text-xs text-gray-400">{prod?.codigo ?? '--'}</p>
                        </div>
                        {bajo ? (
                          <span className="inline-flex h-3 w-3 rounded-full bg-red-500" />
                        ) : (
                          <span className="inline-flex h-3 w-3 rounded-full bg-green-500" />
                        )}
                      </div>
                      <div className="mt-2 flex justify-between text-xs text-gray-500">
                        <span>{s.bodega?.nombre ?? '--'}</span>
                        <span className={cn('font-semibold', bajo ? 'text-red-600' : 'text-gray-900')}>
                          {s.cantidad?.toLocaleString('es-CL') ?? 0} {prod?.unidad_medida ?? ''}
                        </span>
                      </div>
                      <div className="mt-1 flex justify-between text-xs text-gray-400">
                        <span>{prod?.categoria ?? '--'}</span>
                        <span>{formatCLP(s.valor_total ?? 0)}</span>
                      </div>
                    </div>
                  )
                })}
                {filteredStock.length === 0 && (
                  <div className="py-8 text-center text-sm text-gray-400">
                    No hay productos en stock
                  </div>
                )}
              </div>
            </Card>
          )}
        </>
      )}

      {/* Movimientos Tab */}
      {activeTab === 'movimientos' && (
        <>
          {/* Movimiento filters */}
          <Card>
            <CardContent className="flex flex-col gap-3 p-4 sm:flex-row sm:items-end">
              <div className="w-full sm:w-44">
                <label className="mb-1 block text-xs font-medium text-gray-500">Bodega</label>
                <div className="relative">
                  <select
                    value={bodegaFilter}
                    onChange={(e) => setBodegaFilter(e.target.value)}
                    className="h-10 w-full appearance-none rounded-lg border border-gray-300 bg-white px-3 pr-8 text-sm focus:border-pillado-green-500 focus:outline-none focus:ring-2 focus:ring-pillado-green-500/20"
                  >
                    {bodegaOptions.map((b) => (
                      <option key={b.value} value={b.value}>{b.label}</option>
                    ))}
                  </select>
                  <ChevronDown className="pointer-events-none absolute right-2 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400" />
                </div>
              </div>
              <div className="w-full sm:w-44">
                <label className="mb-1 block text-xs font-medium text-gray-500">Tipo</label>
                <div className="relative">
                  <select
                    value={movTipoFilter}
                    onChange={(e) => setMovTipoFilter(e.target.value)}
                    className="h-10 w-full appearance-none rounded-lg border border-gray-300 bg-white px-3 pr-8 text-sm focus:border-pillado-green-500 focus:outline-none focus:ring-2 focus:ring-pillado-green-500/20"
                  >
                    <option value="">Todos</option>
                    <option value="entrada">Entrada</option>
                    <option value="salida">Salida</option>
                    <option value="ajuste_positivo">Ajuste (+)</option>
                    <option value="ajuste_negativo">Ajuste (-)</option>
                    <option value="transferencia_entrada">Transf. Entrada</option>
                    <option value="transferencia_salida">Transf. Salida</option>
                    <option value="merma">Merma</option>
                    <option value="devolucion">Devolucion</option>
                  </select>
                  <ChevronDown className="pointer-events-none absolute right-2 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400" />
                </div>
              </div>
            </CardContent>
          </Card>

          {loadingMovimientos && (
            <div className="flex justify-center py-16">
              <Spinner size="lg" className="text-pillado-green-600" />
            </div>
          )}

          {!loadingMovimientos && (
            <Card>
              <div className="hidden md:block">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Fecha</TableHead>
                      <TableHead>Tipo</TableHead>
                      <TableHead>Producto</TableHead>
                      <TableHead className="text-right">Cantidad</TableHead>
                      <TableHead className="text-right">Costo</TableHead>
                      <TableHead>OT</TableHead>
                      <TableHead>Bodega</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {(movimientosData ?? []).map((m: any) => (
                      <TableRow key={m.id}>
                        <TableCell className="whitespace-nowrap text-xs">{formatDate(m.created_at)}</TableCell>
                        <TableCell>{getMovimientoBadge(m.tipo)}</TableCell>
                        <TableCell className="font-medium">{m.producto?.nombre ?? '--'}</TableCell>
                        <TableCell className="text-right">
                          {m.cantidad > 0 ? '+' : ''}{m.cantidad?.toLocaleString('es-CL') ?? 0} {m.producto?.unidad_medida ?? ''}
                        </TableCell>
                        <TableCell className="text-right">{formatCLP(Math.abs(m.costo_total ?? 0))}</TableCell>
                        <TableCell>
                          {m.ot?.folio ? (
                            <Link
                              href={`/dashboard/ordenes-trabajo/${m.ot.id}`}
                              className="text-xs font-semibold text-pillado-green-600 hover:underline"
                            >
                              {m.ot.folio}
                            </Link>
                          ) : (
                            <span className="text-xs text-gray-400">--</span>
                          )}
                        </TableCell>
                        <TableCell className="text-xs text-gray-500">{m.bodega?.nombre ?? '--'}</TableCell>
                      </TableRow>
                    ))}
                    {(movimientosData ?? []).length === 0 && (
                      <TableRow>
                        <TableCell colSpan={7} className="py-8 text-center text-sm text-gray-400">
                          No hay movimientos registrados
                        </TableCell>
                      </TableRow>
                    )}
                  </TableBody>
                </Table>
              </div>

              {/* Mobile movimientos */}
              <div className="space-y-2 p-4 md:hidden">
                {(movimientosData ?? []).map((m: any) => (
                  <div key={m.id} className="rounded-lg border border-gray-100 p-3">
                    <div className="flex items-start justify-between">
                      <div className="flex items-center gap-2">
                        {getMovimientoBadge(m.tipo)}
                      </div>
                      <span className="text-xs text-gray-400">{formatDate(m.created_at)}</span>
                    </div>
                    <p className="mt-2 text-sm font-medium">{m.producto?.nombre ?? '--'}</p>
                    <div className="mt-1 flex justify-between text-xs text-gray-500">
                      <span>{m.cantidad > 0 ? '+' : ''}{m.cantidad ?? 0} {m.producto?.unidad_medida ?? ''}</span>
                      <span className="font-semibold text-gray-900">{formatCLP(Math.abs(m.costo_total ?? 0))}</span>
                    </div>
                    {m.ot?.folio && (
                      <p className="mt-1 text-xs text-pillado-green-600">{m.ot.folio}</p>
                    )}
                  </div>
                ))}
                {(movimientosData ?? []).length === 0 && (
                  <div className="py-8 text-center text-sm text-gray-400">
                    No hay movimientos registrados
                  </div>
                )}
              </div>
            </Card>
          )}
        </>
      )}

      {/* Alertas Tab */}
      {activeTab === 'alertas' && (
        <>
          {/* Summary card */}
          <Card>
            <CardContent className="flex flex-col gap-4 p-4 sm:flex-row sm:items-center sm:justify-between">
              <div className="flex items-center gap-4">
                <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-red-50">
                  <AlertTriangle className="h-6 w-6 text-red-600" />
                </div>
                <div>
                  <p className="text-sm font-medium text-gray-500">
                    {alertasList.length} producto{alertasList.length !== 1 ? 's' : ''} bajo minimo
                  </p>
                  <p className="text-lg font-bold text-gray-900">
                    Inversion estimada: {formatCLP(inversionEstimada)}
                  </p>
                </div>
              </div>
              {alertasList.length > 0 && (
                <Button
                  variant="outline"
                  onClick={() => exportAlertasCSV(alertasList)}
                >
                  <Download className="mr-2 h-4 w-4" />
                  Exportar Lista de Compra
                </Button>
              )}
            </CardContent>
          </Card>

          {loadingAlertas && (
            <div className="flex justify-center py-16">
              <Spinner size="lg" className="text-pillado-green-600" />
            </div>
          )}

          {!loadingAlertas && alertasList.length === 0 && (
            <Card>
              <CardContent className="flex flex-col items-center justify-center py-16 text-center">
                <CheckCircle2 className="mb-4 h-12 w-12 text-green-300" />
                <p className="text-lg font-medium text-gray-500">Todo en orden</p>
                <p className="mt-1 text-sm text-gray-400">No hay productos bajo el stock minimo</p>
              </CardContent>
            </Card>
          )}

          {!loadingAlertas && alertasList.length > 0 && (
            <Card>
              {/* Desktop table */}
              <div className="hidden md:block">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Codigo</TableHead>
                      <TableHead>Producto</TableHead>
                      <TableHead className="text-right">Stock Actual</TableHead>
                      <TableHead className="text-right">Stock Min</TableHead>
                      <TableHead className="text-right">Stock Max</TableHead>
                      <TableHead className="text-right">Cant. a Comprar</TableHead>
                      <TableHead className="text-right">Costo Unit.</TableHead>
                      <TableHead className="text-right">Costo Total Est.</TableHead>
                      <TableHead>Nivel</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {alertasList.map((item: any) => {
                      const prod = item.producto
                      const stockMin = prod?.stock_minimo ?? 0
                      const stockMax = prod?.stock_maximo ?? 0
                      const cantidadComprar = Math.max(0, stockMax - item.cantidad)
                      const costoUnit = item.costo_promedio ?? 0
                      const costoTotal = cantidadComprar * costoUnit
                      // How far below minimum: 0 = at minimum, 1 = at zero
                      const deficit = stockMin > 0 ? Math.min(1, Math.max(0, (stockMin - item.cantidad) / stockMin)) : 0

                      return (
                        <TableRow key={item.id}>
                          <TableCell className="font-mono text-xs font-semibold">
                            {prod?.codigo ?? '--'}
                          </TableCell>
                          <TableCell className="font-medium">{prod?.nombre ?? '--'}</TableCell>
                          <TableCell className="text-right font-semibold text-red-600">
                            {item.cantidad?.toLocaleString('es-CL') ?? 0}
                          </TableCell>
                          <TableCell className="text-right text-gray-500">
                            {stockMin.toLocaleString('es-CL')}
                          </TableCell>
                          <TableCell className="text-right text-gray-500">
                            {stockMax.toLocaleString('es-CL')}
                          </TableCell>
                          <TableCell className="text-right font-semibold text-amber-600">
                            {cantidadComprar.toLocaleString('es-CL')}
                          </TableCell>
                          <TableCell className="text-right">{formatCLP(costoUnit)}</TableCell>
                          <TableCell className="text-right font-medium">{formatCLP(costoTotal)}</TableCell>
                          <TableCell>
                            <div className="flex items-center gap-2">
                              <div className="h-2 w-16 overflow-hidden rounded-full bg-gray-200">
                                <div
                                  className={cn(
                                    'h-full rounded-full transition-all',
                                    deficit > 0.7 ? 'bg-red-500' : deficit > 0.4 ? 'bg-orange-400' : 'bg-yellow-400'
                                  )}
                                  style={{ width: `${deficit * 100}%` }}
                                />
                              </div>
                              <span className="text-xs text-gray-400">
                                {Math.round(deficit * 100)}%
                              </span>
                            </div>
                          </TableCell>
                        </TableRow>
                      )
                    })}
                  </TableBody>
                </Table>
              </div>

              {/* Mobile alertas */}
              <div className="space-y-2 p-4 md:hidden">
                {alertasList.map((item: any) => {
                  const prod = item.producto
                  const stockMin = prod?.stock_minimo ?? 0
                  const stockMax = prod?.stock_maximo ?? 0
                  const cantidadComprar = Math.max(0, stockMax - item.cantidad)
                  const costoUnit = item.costo_promedio ?? 0
                  const costoTotal = cantidadComprar * costoUnit
                  const deficit = stockMin > 0 ? Math.min(1, Math.max(0, (stockMin - item.cantidad) / stockMin)) : 0

                  return (
                    <div key={item.id} className="rounded-lg border border-red-100 bg-red-50/30 p-3">
                      <div className="flex items-start justify-between">
                        <div>
                          <p className="text-sm font-semibold text-gray-900">{prod?.nombre ?? '--'}</p>
                          <p className="font-mono text-xs text-gray-400">{prod?.codigo ?? '--'}</p>
                        </div>
                        <span className="rounded-full bg-red-100 px-2 py-0.5 text-xs font-semibold text-red-700">
                          {item.cantidad?.toLocaleString('es-CL') ?? 0} / {stockMin.toLocaleString('es-CL')}
                        </span>
                      </div>
                      {/* Progress bar */}
                      <div className="mt-2">
                        <div className="h-2 w-full overflow-hidden rounded-full bg-gray-200">
                          <div
                            className={cn(
                              'h-full rounded-full',
                              deficit > 0.7 ? 'bg-red-500' : deficit > 0.4 ? 'bg-orange-400' : 'bg-yellow-400'
                            )}
                            style={{ width: `${deficit * 100}%` }}
                          />
                        </div>
                      </div>
                      <div className="mt-2 flex justify-between text-xs text-gray-500">
                        <span>Comprar: <span className="font-semibold text-amber-600">{cantidadComprar.toLocaleString('es-CL')}</span></span>
                        <span className="font-semibold text-gray-900">{formatCLP(costoTotal)}</span>
                      </div>
                    </div>
                  )
                })}
              </div>
            </Card>
          )}
        </>
      )}

      {/* Conteos Tab */}
      {activeTab === 'conteos' && (
        <Card>
          <CardContent className="flex flex-col items-center justify-center py-16 text-center">
            <Package className="mb-4 h-12 w-12 text-gray-300" />
            <p className="text-lg font-medium text-gray-500">Conteos de Inventario</p>
            <p className="mt-1 text-sm text-gray-400">Gestione conteos fisicos con scanner de codigo de barras</p>
            <Link href="/dashboard/inventario/conteo">
              <Button variant="primary" className="mt-4">
                Ir a Conteos
              </Button>
            </Link>
          </CardContent>
        </Card>
      )}

      {/* Kardex Tab */}
      {activeTab === 'kardex' && (
        <Card>
          <CardContent className="flex flex-col items-center justify-center py-16 text-center">
            <FileWarning className="mb-4 h-12 w-12 text-gray-300" />
            <p className="text-lg font-medium text-gray-500">Kardex</p>
            <p className="mt-1 text-sm text-gray-400">Seleccione un producto para ver su kardex detallado</p>
          </CardContent>
        </Card>
      )}
    </div>
  )
}

