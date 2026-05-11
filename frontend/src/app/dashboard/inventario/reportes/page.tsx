'use client'

import Link from 'next/link'
import { useMemo, useState } from 'react'
import {
  BarChart3, DollarSign, ArrowDownRight, AlertTriangle, Package,
  TrendingDown, Layers, Search, Download, RefreshCw, Scale,
} from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Input } from '@/components/ui/input'
import { Spinner } from '@/components/ui/spinner'
import {
  Table, TableHeader, TableBody, TableRow, TableHead, TableCell,
} from '@/components/ui/table'
import { formatCLP, formatDate, formatDateTime, cn } from '@/lib/utils'
import {
  useResumenFinanciero, useStockValorizado, useCostosPorOT,
  useCostosPorCECO, useKardexProducto, useMermasAjustes,
} from '@/hooks/use-bodega-reportes'
import { useProductos, useBodegas } from '@/hooks/use-inventario'
import { useQueryClient } from '@tanstack/react-query'

type Tab = 'stock' | 'ot' | 'ceco' | 'kardex' | 'mermas'

function exportCsv(filename: string, rows: Record<string, unknown>[]) {
  if (rows.length === 0) return
  const cols = Object.keys(rows[0])
  const escape = (v: unknown) => {
    if (v === null || v === undefined) return ''
    const s = typeof v === 'string' ? v : String(v)
    return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s
  }
  const lines = [cols.join(',')]
  for (const r of rows) lines.push(cols.map((c) => escape(r[c])).join(','))
  const blob = new Blob(['﻿' + lines.join('\n')], { type: 'text/csv;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  a.click()
  URL.revokeObjectURL(url)
}

export default function ReportesBodegaPage() {
  const [tab, setTab] = useState<Tab>('stock')
  const qc = useQueryClient()
  const resumen = useResumenFinanciero()

  const refresh = () => qc.invalidateQueries({ queryKey: ['bodega-reportes'] })

  return (
    <div className="space-y-6 p-6">
      <header className="flex items-start justify-between gap-4 flex-wrap">
        <div>
          <h1 className="text-2xl font-bold flex items-center gap-2">
            <BarChart3 className="h-6 w-6 text-amber-700" />
            Reportes financieros — Bodega
          </h1>
          <p className="text-sm text-gray-600 mt-1">
            Stock valorizado, costos por OT/CECO, kardex, mermas y reconciliación. Solo lectura.
            {resumen.data?.calculado_en && (
              <span className="ml-2 text-[11px] text-gray-500">
                Actualizado: {formatDateTime(resumen.data.calculado_en)}
              </span>
            )}
          </p>
        </div>
        <Button variant="outline" size="sm" onClick={refresh} disabled={resumen.isFetching}>
          <RefreshCw className={cn('h-4 w-4 mr-1', resumen.isFetching && 'animate-spin')} />
          Actualizar
        </Button>
      </header>

      {/* KPIs */}
      <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-3">
        <KpiCard
          icon={<DollarSign className="h-4 w-4" />}
          label="Valor stock FIFO"
          value={resumen.isLoading ? '—' : formatCLP(resumen.data?.valor_total_stock_fifo ?? 0)}
          hint={resumen.data?.valor_total_stock_legacy != null
            ? `Legacy: ${formatCLP(resumen.data.valor_total_stock_legacy)}`
            : undefined}
        />
        <KpiCard
          icon={<ArrowDownRight className="h-4 w-4" />}
          label="Salidas del mes"
          value={resumen.isLoading ? '—' : `${resumen.data?.total_salidas_mes ?? 0}`}
          hint={resumen.data?.costo_salidas_mes != null
            ? `Costo: ${formatCLP(resumen.data.costo_salidas_mes)}`
            : undefined}
        />
        <KpiCard
          icon={<TrendingDown className="h-4 w-4 text-red-600" />}
          label="Mermas / Ajustes mes"
          value={resumen.isLoading ? '—' : `${resumen.data?.total_mermas_mes ?? 0}`}
          hint={resumen.data?.costo_mermas_mes != null
            ? `Costo: ${formatCLP(resumen.data.costo_mermas_mes)}`
            : undefined}
          urgent={resumen.data ? resumen.data.total_mermas_mes > 0 : false}
        />
        <KpiCard
          icon={<AlertTriangle className="h-4 w-4 text-amber-600" />}
          label="Productos desviados"
          value={resumen.isLoading ? '—' : `${resumen.data?.productos_con_desviacion ?? 0}`}
          hint={resumen.data?.productos_con_desviacion ? 'Stock vs FIFO' : 'Reconciliación OK'}
          urgent={resumen.data ? resumen.data.productos_con_desviacion > 0 : false}
        />
        <KpiCard
          icon={<Package className="h-4 w-4 text-blue-600" />}
          label="Bajo mínimo"
          value={resumen.isLoading ? '—' : `${resumen.data?.productos_bajo_minimo ?? 0}`}
          hint={`${resumen.data?.productos_sin_stock ?? 0} sin stock`}
          urgent={resumen.data ? resumen.data.productos_bajo_minimo > 0 : false}
        />
        <Link href="/dashboard/inventario/reconciliacion" className="block">
          <Card className="hover:border-amber-300 transition border-gray-200">
            <CardContent className="p-4">
              <div className="flex items-center justify-between">
                <span className="text-xs font-semibold uppercase text-gray-600">Reconciliación</span>
                <Scale className="h-4 w-4 text-amber-700" />
              </div>
              <div className="mt-1 text-sm font-medium text-amber-800">
                Ver detalle →
              </div>
              <div className="text-[11px] text-gray-600 mt-1">
                stock vs FIFO, combustible, mov. excepcionales
              </div>
            </CardContent>
          </Card>
        </Link>
      </div>

      {/* Tabs */}
      <div className="flex gap-1 border-b border-gray-200 overflow-x-auto">
        <TabButton current={tab} value="stock"   label="Stock valorizado" icon={<Package className="h-4 w-4" />} onClick={() => setTab('stock')} />
        <TabButton current={tab} value="ot"      label="Costos por OT"    icon={<BarChart3 className="h-4 w-4" />} onClick={() => setTab('ot')} />
        <TabButton current={tab} value="ceco"    label="Costos por CECO"  icon={<DollarSign className="h-4 w-4" />} onClick={() => setTab('ceco')} />
        <TabButton current={tab} value="kardex"  label="Kardex producto"  icon={<Layers className="h-4 w-4" />} onClick={() => setTab('kardex')} />
        <TabButton current={tab} value="mermas"  label="Mermas / Ajustes" icon={<TrendingDown className="h-4 w-4" />} onClick={() => setTab('mermas')} />
      </div>

      {tab === 'stock'  && <TabStock />}
      {tab === 'ot'     && <TabCostosOT />}
      {tab === 'ceco'   && <TabCostosCECO />}
      {tab === 'kardex' && <TabKardex />}
      {tab === 'mermas' && <TabMermas />}
    </div>
  )
}

// ── KPI Card ──────────────────────────────────────────────────────────────

function KpiCard({
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

function TabButton({
  current, value, label, icon, onClick,
}: {
  current: Tab; value: Tab; label: string; icon: React.ReactNode; onClick: () => void
}) {
  const active = current === value
  return (
    <button
      onClick={onClick}
      className={cn(
        'inline-flex items-center gap-2 px-4 py-2 text-sm font-medium border-b-2 -mb-px transition whitespace-nowrap',
        active
          ? 'border-amber-600 text-amber-800'
          : 'border-transparent text-gray-600 hover:text-gray-900 hover:border-gray-300',
      )}
    >{icon}{label}</button>
  )
}

// ── Tab Stock valorizado ──────────────────────────────────────────────────

function TabStock() {
  const [categoria, setCategoria] = useState<string>('todos')
  const [search, setSearch] = useState('')
  const [soloConStock, setSoloConStock] = useState(true)
  const { data: rows, isLoading } = useStockValorizado({ categoria, search: search || undefined, solo_con_stock: soloConStock })

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between flex-wrap gap-3">
          <CardTitle>Stock valorizado</CardTitle>
          <Button
            variant="outline" size="sm"
            disabled={!rows || rows.length === 0}
            onClick={() => rows && exportCsv(`stock-valorizado-${new Date().toISOString().slice(0,10)}.csv`, rows as unknown as Record<string, unknown>[])}
          >
            <Download className="h-4 w-4 mr-1" /> Exportar CSV
          </Button>
        </div>
        <div className="flex items-center gap-2 flex-wrap mt-3">
          <select
            value={categoria}
            onChange={(e) => setCategoria(e.target.value)}
            className="rounded-md border border-gray-300 bg-white px-2 py-1.5 text-sm"
          >
            <option value="todos">Todas las categorías</option>
            <option value="combustible">Combustible</option>
            <option value="lubricante">Lubricante</option>
            <option value="filtro">Filtro</option>
            <option value="repuesto">Repuesto</option>
            <option value="consumible">Consumible</option>
            <option value="epp">EPP</option>
          </select>
          <div className="relative flex-1 min-w-[180px] max-w-md">
            <Search className="absolute left-2 top-1/2 -translate-y-1/2 h-4 w-4 text-gray-400" />
            <Input
              placeholder="Buscar producto..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="pl-8"
            />
          </div>
          <label className="flex items-center gap-1 text-xs">
            <input type="checkbox" checked={soloConStock} onChange={(e) => setSoloConStock(e.target.checked)} className="h-4 w-4" />
            Solo con stock
          </label>
        </div>
      </CardHeader>
      <CardContent className="px-0">
        {isLoading ? (
          <div className="flex justify-center py-10"><Spinner /></div>
        ) : (rows?.length ?? 0) === 0 ? (
          <div className="text-center text-sm text-gray-500 py-10">Sin filas</div>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Producto</TableHead>
                <TableHead>Bodega</TableHead>
                <TableHead className="text-right">Cant.</TableHead>
                <TableHead className="text-right">Valor FIFO</TableHead>
                <TableHead className="text-right">Valor legacy</TableHead>
                <TableHead>Estado</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {rows!.map((r) => (
                <TableRow key={`${r.producto_id}-${r.bodega_id}`}>
                  <TableCell>
                    <div className="font-medium text-sm">{r.producto_nombre}</div>
                    <div className="text-[11px] text-gray-500 font-mono">{r.producto_codigo} · {r.categoria}</div>
                  </TableCell>
                  <TableCell>
                    <div className="text-sm">{r.bodega_nombre}</div>
                    <div className="text-[11px] text-gray-500 font-mono">{r.bodega_codigo}</div>
                  </TableCell>
                  <TableCell className="text-right tabular-nums">{Number(r.cantidad_stock).toFixed(2)}</TableCell>
                  <TableCell className="text-right tabular-nums font-mono">{formatCLP(Number(r.valor_fifo))}</TableCell>
                  <TableCell className="text-right tabular-nums font-mono text-gray-600">{formatCLP(Number(r.valor_legacy))}</TableCell>
                  <TableCell>
                    <Badge className={r.estado_reconciliacion === 'cuadrado' ? 'bg-green-100 text-green-700' : 'bg-amber-100 text-amber-700'}>
                      {r.estado_reconciliacion}
                    </Badge>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </CardContent>
    </Card>
  )
}

// ── Tab Costos por OT ─────────────────────────────────────────────────────

function TabCostosOT() {
  const { data: rows, isLoading } = useCostosPorOT()
  const total = useMemo(() => (rows ?? []).reduce((s, r) => s + Number(r.costo_total_fifo), 0), [rows])

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between flex-wrap gap-3">
          <CardTitle>
            Costos por OT
            {rows && rows.length > 0 && (
              <span className="text-xs font-normal text-gray-600 ml-2">
                Total: <span className="font-mono font-semibold">{formatCLP(total)}</span>
              </span>
            )}
          </CardTitle>
          <Button variant="outline" size="sm" disabled={!rows || rows.length === 0}
            onClick={() => rows && exportCsv(`costos-ot-${new Date().toISOString().slice(0,10)}.csv`, rows as unknown as Record<string, unknown>[])}>
            <Download className="h-4 w-4 mr-1" /> Exportar CSV
          </Button>
        </div>
      </CardHeader>
      <CardContent className="px-0">
        {isLoading ? <div className="flex justify-center py-10"><Spinner /></div> :
         (rows?.length ?? 0) === 0 ? <div className="text-center text-sm text-gray-500 py-10">Sin salidas con OT registradas</div> :
        <Table>
          <TableHeader><TableRow>
            <TableHead>OT</TableHead>
            <TableHead>Faena</TableHead>
            <TableHead>CECO</TableHead>
            <TableHead className="text-right">Salidas</TableHead>
            <TableHead className="text-right">Items</TableHead>
            <TableHead className="text-right">Costo total FIFO</TableHead>
            <TableHead>Última salida</TableHead>
          </TableRow></TableHeader>
          <TableBody>
            {rows!.map((r) => (
              <TableRow key={r.ot_id}>
                <TableCell>
                  <div className="font-mono text-sm">{r.ot_folio}</div>
                  <div className="text-[11px] text-gray-500">{r.ot_estado}</div>
                </TableCell>
                <TableCell className="text-sm">{r.faena ?? '—'}</TableCell>
                <TableCell>
                  {r.ceco_codigo ? (
                    <div>
                      <div className="font-mono text-xs">{r.ceco_codigo}</div>
                      <div className="text-[11px] text-gray-500">{r.ceco_nombre}</div>
                    </div>
                  ) : '—'}
                </TableCell>
                <TableCell className="text-right tabular-nums">{r.cantidad_salidas}</TableCell>
                <TableCell className="text-right tabular-nums">{r.cantidad_items}</TableCell>
                <TableCell className="text-right tabular-nums font-mono font-semibold">{formatCLP(Number(r.costo_total_fifo))}</TableCell>
                <TableCell className="text-xs">{r.fecha_ultima_salida ? formatDate(r.fecha_ultima_salida) : '—'}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>}
      </CardContent>
    </Card>
  )
}

// ── Tab Costos por CECO ───────────────────────────────────────────────────

function TabCostosCECO() {
  const { data: rows, isLoading } = useCostosPorCECO()
  const rowsConSalidas = (rows ?? []).filter((r) => r.cantidad_salidas > 0)
  const total = rowsConSalidas.reduce((s, r) => s + Number(r.costo_total_fifo), 0)

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between flex-wrap gap-3">
          <CardTitle>
            Costos por CECO
            {rowsConSalidas.length > 0 && (
              <span className="text-xs font-normal text-gray-600 ml-2">
                Total: <span className="font-mono font-semibold">{formatCLP(total)}</span>
              </span>
            )}
          </CardTitle>
          <Button variant="outline" size="sm" disabled={rowsConSalidas.length === 0}
            onClick={() => exportCsv(`costos-ceco-${new Date().toISOString().slice(0,10)}.csv`, rowsConSalidas as unknown as Record<string, unknown>[])}>
            <Download className="h-4 w-4 mr-1" /> Exportar CSV
          </Button>
        </div>
      </CardHeader>
      <CardContent className="px-0">
        {isLoading ? <div className="flex justify-center py-10"><Spinner /></div> :
         rowsConSalidas.length === 0 ? <div className="text-center text-sm text-gray-500 py-10">Sin salidas con CECO registradas</div> :
        <Table>
          <TableHeader><TableRow>
            <TableHead>CECO</TableHead>
            <TableHead>Área</TableHead>
            <TableHead className="text-right">Salidas</TableHead>
            <TableHead className="text-right">Items</TableHead>
            <TableHead className="text-right">Costo total FIFO</TableHead>
            <TableHead>Última</TableHead>
          </TableRow></TableHeader>
          <TableBody>
            {rowsConSalidas.map((r) => (
              <TableRow key={r.ceco_id}>
                <TableCell>
                  <div className="font-mono text-sm">{r.ceco_codigo}</div>
                  <div className="text-[11px] text-gray-500">{r.ceco_nombre}</div>
                </TableCell>
                <TableCell className="text-sm">{r.ceco_area ?? '—'}</TableCell>
                <TableCell className="text-right tabular-nums">{r.cantidad_salidas}</TableCell>
                <TableCell className="text-right tabular-nums">{r.cantidad_items}</TableCell>
                <TableCell className="text-right tabular-nums font-mono font-semibold">{formatCLP(Number(r.costo_total_fifo))}</TableCell>
                <TableCell className="text-xs">{r.fecha_ultima ? formatDate(r.fecha_ultima) : '—'}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>}
      </CardContent>
    </Card>
  )
}

// ── Tab Kardex ────────────────────────────────────────────────────────────

function TabKardex() {
  const [productoId, setProductoId] = useState<string>('')
  const [bodegaId, setBodegaId] = useState<string>('')
  const { data: productosAll } = useProductos()
  const { data: bodegas } = useBodegas()
  const { data: rows, isLoading } = useKardexProducto(productoId || null, bodegaId || null)

  const productos = useMemo(() => productosAll ?? [], [productosAll])

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between flex-wrap gap-3">
          <CardTitle>Kardex valorizado por producto</CardTitle>
          <Button variant="outline" size="sm"
            disabled={!rows || rows.length === 0}
            onClick={() => rows && exportCsv(`kardex-${productoId}-${new Date().toISOString().slice(0,10)}.csv`, rows as unknown as Record<string, unknown>[])}>
            <Download className="h-4 w-4 mr-1" /> Exportar CSV
          </Button>
        </div>
        <div className="flex items-center gap-2 flex-wrap mt-3">
          <select
            value={productoId}
            onChange={(e) => setProductoId(e.target.value)}
            className="rounded-md border border-gray-300 bg-white px-2 py-1.5 text-sm flex-1 min-w-[200px] max-w-md"
          >
            <option value="">— Selecciona producto —</option>
            {productos.map((p) => (
              <option key={p.id} value={p.id}>{p.codigo} — {p.nombre}</option>
            ))}
          </select>
          <select
            value={bodegaId}
            onChange={(e) => setBodegaId(e.target.value)}
            className="rounded-md border border-gray-300 bg-white px-2 py-1.5 text-sm"
          >
            <option value="">Todas las bodegas</option>
            {(bodegas ?? []).map((b) => (
              <option key={b.id} value={b.id}>{b.codigo}</option>
            ))}
          </select>
        </div>
      </CardHeader>
      <CardContent className="px-0">
        {!productoId ? (
          <div className="text-center text-sm text-gray-500 py-10">Selecciona un producto para ver su kardex</div>
        ) : isLoading ? (
          <div className="flex justify-center py-10"><Spinner /></div>
        ) : (rows?.length ?? 0) === 0 ? (
          <div className="text-center text-sm text-gray-500 py-10">Sin movimientos para este producto</div>
        ) : (
          <Table>
            <TableHeader><TableRow>
              <TableHead>Fecha</TableHead>
              <TableHead>Tipo</TableHead>
              <TableHead>Referencia / OT</TableHead>
              <TableHead>Bodega</TableHead>
              <TableHead className="text-right">Entrada</TableHead>
              <TableHead className="text-right">Salida</TableHead>
              <TableHead className="text-right">Costo unit</TableHead>
              <TableHead>Motivo</TableHead>
            </TableRow></TableHeader>
            <TableBody>
              {rows!.map((r) => (
                <TableRow key={r.movimiento_id}>
                  <TableCell className="text-xs whitespace-nowrap">{formatDateTime(r.fecha_movimiento)}</TableCell>
                  <TableCell>
                    <Badge className={
                      r.tipo_movimiento.includes('entrada') || r.tipo_movimiento === 'ajuste_positivo' || r.tipo_movimiento === 'devolucion'
                        ? 'bg-green-100 text-green-700'
                        : r.tipo_movimiento === 'merma'
                        ? 'bg-red-100 text-red-700'
                        : 'bg-amber-100 text-amber-700'
                    }>{r.tipo_movimiento}</Badge>
                  </TableCell>
                  <TableCell className="font-mono text-xs">
                    {r.ot_folio ? <div>OT {r.ot_folio}</div> : null}
                    {r.referencia && <div className="text-gray-500">{r.referencia}</div>}
                  </TableCell>
                  <TableCell className="text-xs">{r.bodega_codigo}</TableCell>
                  <TableCell className="text-right tabular-nums">
                    {r.entrada_cantidad != null ? (
                      <>
                        <div>+{Number(r.entrada_cantidad).toFixed(2)}</div>
                        <div className="text-[11px] text-gray-500 font-mono">{formatCLP(Number(r.entrada_valor ?? 0))}</div>
                      </>
                    ) : '—'}
                  </TableCell>
                  <TableCell className="text-right tabular-nums">
                    {r.salida_cantidad != null ? (
                      <>
                        <div className="text-red-700">-{Number(r.salida_cantidad).toFixed(2)}</div>
                        <div className="text-[11px] text-gray-500 font-mono">{formatCLP(Number(r.salida_valor ?? 0))}</div>
                      </>
                    ) : '—'}
                  </TableCell>
                  <TableCell className="text-right tabular-nums font-mono text-xs">{formatCLP(Number(r.costo_unitario))}</TableCell>
                  <TableCell className="text-xs max-w-[200px] truncate" title={r.motivo ?? ''}>{r.motivo ?? '—'}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </CardContent>
    </Card>
  )
}

// ── Tab Mermas / Ajustes ──────────────────────────────────────────────────

function TabMermas() {
  const [tipo, setTipo] = useState<'todos' | 'merma' | 'ajuste_negativo' | 'ajuste_positivo'>('todos')
  const { data: rows, isLoading } = useMermasAjustes(tipo)
  const total = (rows ?? []).reduce((s, r) => s + Number(r.costo_total), 0)

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between flex-wrap gap-3">
          <CardTitle>
            Mermas y ajustes (últimos 60 días)
            {rows && rows.length > 0 && (
              <span className="text-xs font-normal text-gray-600 ml-2">
                Total: <span className="font-mono font-semibold">{formatCLP(total)}</span>
              </span>
            )}
          </CardTitle>
          <Button variant="outline" size="sm" disabled={!rows || rows.length === 0}
            onClick={() => rows && exportCsv(`mermas-ajustes-${new Date().toISOString().slice(0,10)}.csv`, rows as unknown as Record<string, unknown>[])}>
            <Download className="h-4 w-4 mr-1" /> Exportar CSV
          </Button>
        </div>
        <div className="flex items-center gap-1 flex-wrap mt-3">
          {(['todos', 'merma', 'ajuste_negativo', 'ajuste_positivo'] as const).map((t) => (
            <button key={t}
              onClick={() => setTipo(t)}
              className={cn(
                'px-2.5 py-1 text-xs rounded-full border transition',
                tipo === t ? 'bg-amber-700 text-white border-amber-700'
                  : 'bg-white text-gray-700 border-gray-300 hover:border-amber-400',
              )}
            >{t === 'todos' ? 'Todos' : t}</button>
          ))}
        </div>
      </CardHeader>
      <CardContent className="px-0">
        {isLoading ? <div className="flex justify-center py-10"><Spinner /></div> :
         (rows?.length ?? 0) === 0 ? <div className="text-center text-sm text-gray-500 py-10">Sin mermas/ajustes en el período</div> :
        <Table>
          <TableHeader><TableRow>
            <TableHead>Fecha</TableHead>
            <TableHead>Tipo</TableHead>
            <TableHead>Producto</TableHead>
            <TableHead>Bodega</TableHead>
            <TableHead className="text-right">Cantidad</TableHead>
            <TableHead className="text-right">Costo</TableHead>
            <TableHead>Motivo</TableHead>
            <TableHead>Usuario</TableHead>
            <TableHead>OT</TableHead>
          </TableRow></TableHeader>
          <TableBody>
            {rows!.map((r) => (
              <TableRow key={r.movimiento_id}>
                <TableCell className="text-xs whitespace-nowrap">{formatDateTime(r.fecha)}</TableCell>
                <TableCell>
                  <Badge className={
                    r.tipo === 'merma' ? 'bg-red-100 text-red-700'
                      : r.tipo === 'ajuste_negativo' ? 'bg-orange-100 text-orange-700'
                      : 'bg-green-100 text-green-700'
                  }>{r.tipo === 'ajuste_positivo' ? 'ajuste +' : r.tipo === 'ajuste_negativo' ? 'ajuste −' : 'merma'}</Badge>
                </TableCell>
                <TableCell>
                  <div className="text-sm font-medium">{r.producto_nombre}</div>
                  <div className="text-[11px] text-gray-500 font-mono">{r.producto_codigo}</div>
                </TableCell>
                <TableCell><div className="text-xs">{r.bodega_codigo}</div></TableCell>
                <TableCell className="text-right tabular-nums">{Number(r.cantidad).toFixed(2)}</TableCell>
                <TableCell className="text-right tabular-nums font-mono">{formatCLP(Number(r.costo_total))}</TableCell>
                <TableCell className="text-xs max-w-[200px]">
                  <div className="truncate" title={r.motivo ?? ''}>{r.motivo ?? '—'}</div>
                </TableCell>
                <TableCell className="text-xs">{r.usuario_nombre ?? '—'}</TableCell>
                <TableCell className="text-xs font-mono">{r.ot_folio ?? '—'}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>}
      </CardContent>
    </Card>
  )
}
