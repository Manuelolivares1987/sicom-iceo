'use client'

import { useMemo, useState } from 'react'
import {
  Scale, Fuel, FileWarning, Search, RefreshCw,
  CheckCircle2, Download,
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
  useReconciliacionResumen,
  useReconciliacionStockFifo,
  useReconciliacionCombustible,
  useMovimientosExcepcionales,
} from '@/hooks/use-bodega-reconciliacion'
import type {
  EstadoReconciliacionStock,
  EstadoReconciliacionCombustible,
  ReconciliacionStockFifoRow,
  ReconciliacionCombustibleRow,
  MovimientoExcepcionalRow,
} from '@/lib/services/bodega-reconciliacion'
import { useQueryClient } from '@tanstack/react-query'

type Tab = 'stock' | 'combustible' | 'mov'

const ESTADO_STOCK_LABEL: Record<EstadoReconciliacionStock, string> = {
  cuadrado: 'Cuadrado',
  desviacion_cantidad: 'Desviación cantidad',
  desviacion_valor: 'Desviación valor',
  sin_capa_fifo: 'Sin capa FIFO',
  sin_stock_legacy: 'Sin stock legacy',
}
const ESTADO_STOCK_COLOR: Record<EstadoReconciliacionStock, string> = {
  cuadrado: 'bg-green-100 text-green-700',
  desviacion_cantidad: 'bg-red-100 text-red-700',
  desviacion_valor: 'bg-orange-100 text-orange-700',
  sin_capa_fifo: 'bg-amber-100 text-amber-700',
  sin_stock_legacy: 'bg-blue-100 text-blue-700',
}
const ESTADO_COMB_LABEL: Record<EstadoReconciliacionCombustible, string> = {
  cuadrado: 'Cuadrado',
  sin_varillaje: 'Sin varillaje',
  varillaje_atrasado: 'Varillaje atrasado',
  desviacion_fisica: 'Desviación física',
  kardex_divergente: 'Kardex divergente',
}
const ESTADO_COMB_COLOR: Record<EstadoReconciliacionCombustible, string> = {
  cuadrado: 'bg-green-100 text-green-700',
  sin_varillaje: 'bg-blue-100 text-blue-700',
  varillaje_atrasado: 'bg-amber-100 text-amber-700',
  desviacion_fisica: 'bg-red-100 text-red-700',
  kardex_divergente: 'bg-orange-100 text-orange-700',
}

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

export default function ReconciliacionBodegaPage() {
  const [tab, setTab] = useState<Tab>('stock')
  const qc = useQueryClient()

  const refresh = () => {
    qc.invalidateQueries({ queryKey: ['bodega-reconciliacion'] })
  }

  const resumen = useReconciliacionResumen()

  return (
    <div className="space-y-6 p-6">
      <header className="flex items-start justify-between gap-4 flex-wrap">
        <div>
          <h1 className="text-2xl font-bold flex items-center gap-2">
            <Scale className="h-6 w-6 text-amber-700" />
            Reconciliación Bodega
          </h1>
          <p className="text-sm text-gray-600 mt-1">
            Compara stock legacy (CPP) vs FIFO, varillaje físico vs estanque y audita ajustes/mermas. Solo lectura.
          </p>
        </div>
        <Button variant="outline" size="sm" onClick={refresh} disabled={resumen.isFetching}>
          <RefreshCw className={cn('h-4 w-4 mr-1', resumen.isFetching && 'animate-spin')} />
          Actualizar
        </Button>
      </header>

      {/* KPIs */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
        <KpiStock data={resumen.data} loading={resumen.isLoading} onClick={() => setTab('stock')} active={tab === 'stock'} />
        <KpiCombustible data={resumen.data} loading={resumen.isLoading} onClick={() => setTab('combustible')} active={tab === 'combustible'} />
        <KpiMovimientos data={resumen.data} loading={resumen.isLoading} onClick={() => setTab('mov')} active={tab === 'mov'} />
      </div>

      {/* Tabs */}
      <div className="flex gap-1 border-b border-gray-200">
        <TabButton current={tab} value="stock" label="Stock vs FIFO" icon={<Scale className="h-4 w-4" />} onClick={() => setTab('stock')} />
        <TabButton current={tab} value="combustible" label="Combustible" icon={<Fuel className="h-4 w-4" />} onClick={() => setTab('combustible')} />
        <TabButton current={tab} value="mov" label="Ajustes y mermas (60d)" icon={<FileWarning className="h-4 w-4" />} onClick={() => setTab('mov')} />
      </div>

      {tab === 'stock' && <TabStockFifo />}
      {tab === 'combustible' && <TabCombustible />}
      {tab === 'mov' && <TabMovimientosExcepcionales />}
    </div>
  )
}

// ── KPIs ──────────────────────────────────────────────────────────────────

function KpiStock({
  data, loading, onClick, active,
}: {
  data: ReturnType<typeof useReconciliacionResumen>['data']
  loading: boolean
  onClick: () => void
  active: boolean
}) {
  const s = data?.stock_fifo
  const desviaciones = (s?.desviacion_cantidad ?? 0) + (s?.desviacion_valor ?? 0)
  return (
    <button onClick={onClick} className={cn(
      'text-left rounded-lg border p-4 transition active:scale-[0.99]',
      active ? 'border-amber-500 bg-amber-50' : 'border-gray-200 bg-white hover:border-amber-300',
    )}>
      <div className="flex items-center justify-between">
        <span className="text-xs font-semibold uppercase text-gray-600">Stock vs FIFO</span>
        <Scale className="h-4 w-4 text-amber-700" />
      </div>
      {loading ? <Spinner className="h-4 w-4 mt-2" /> : (
        <>
          <div className="mt-1 text-2xl font-bold tabular-nums">
            {desviaciones} <span className="text-sm font-normal text-gray-500">/ {s?.total ?? 0}</span>
          </div>
          <div className="text-[11px] text-gray-600 mt-1">
            {s?.cuadrado ?? 0} cuadrados · {s?.sin_capa_fifo ?? 0} sin capa FIFO
          </div>
          {s && Math.abs(s.valor_delta_total) > 1 && (
            <div className={cn(
              'text-[11px] mt-1 font-mono',
              s.valor_delta_total > 0 ? 'text-red-700' : 'text-blue-700',
            )}>
              Δ valor: {formatCLP(s.valor_delta_total)}
            </div>
          )}
        </>
      )}
    </button>
  )
}

function KpiCombustible({
  data, loading, onClick, active,
}: {
  data: ReturnType<typeof useReconciliacionResumen>['data']
  loading: boolean
  onClick: () => void
  active: boolean
}) {
  const c = data?.combustible
  const alertas = (c?.varillaje_atrasado ?? 0) + (c?.desviacion_fisica ?? 0) + (c?.kardex_divergente ?? 0) + (c?.sin_varillaje ?? 0)
  return (
    <button onClick={onClick} className={cn(
      'text-left rounded-lg border p-4 transition active:scale-[0.99]',
      active ? 'border-amber-500 bg-amber-50' : 'border-gray-200 bg-white hover:border-amber-300',
    )}>
      <div className="flex items-center justify-between">
        <span className="text-xs font-semibold uppercase text-gray-600">Combustible</span>
        <Fuel className="h-4 w-4 text-amber-700" />
      </div>
      {loading ? <Spinner className="h-4 w-4 mt-2" /> : (
        <>
          <div className="mt-1 text-2xl font-bold tabular-nums">
            {alertas} <span className="text-sm font-normal text-gray-500">/ {c?.total ?? 0} estanques</span>
          </div>
          <div className="text-[11px] text-gray-600 mt-1">
            {c?.cuadrado ?? 0} cuadrados · {c?.varillaje_atrasado ?? 0} varillaje atrasado
          </div>
        </>
      )}
    </button>
  )
}

function KpiMovimientos({
  data, loading, onClick, active,
}: {
  data: ReturnType<typeof useReconciliacionResumen>['data']
  loading: boolean
  onClick: () => void
  active: boolean
}) {
  return (
    <button onClick={onClick} className={cn(
      'text-left rounded-lg border p-4 transition active:scale-[0.99]',
      active ? 'border-amber-500 bg-amber-50' : 'border-gray-200 bg-white hover:border-amber-300',
    )}>
      <div className="flex items-center justify-between">
        <span className="text-xs font-semibold uppercase text-gray-600">Ajustes y mermas (60d)</span>
        <FileWarning className="h-4 w-4 text-amber-700" />
      </div>
      {loading ? <Spinner className="h-4 w-4 mt-2" /> : (
        <>
          <div className="mt-1 text-2xl font-bold tabular-nums">
            {data?.movimientos_excepcionales_60d ?? 0}
          </div>
          <div className="text-[11px] text-gray-600 mt-1">eventos en últimos 60 días</div>
        </>
      )}
    </button>
  )
}

function TabButton({
  current, value, label, icon, onClick,
}: {
  current: Tab
  value: Tab
  label: string
  icon: React.ReactNode
  onClick: () => void
}) {
  const active = current === value
  return (
    <button
      onClick={onClick}
      className={cn(
        'inline-flex items-center gap-2 px-4 py-2 text-sm font-medium border-b-2 -mb-px transition',
        active
          ? 'border-amber-600 text-amber-800'
          : 'border-transparent text-gray-600 hover:text-gray-900 hover:border-gray-300',
      )}
    >
      {icon}
      {label}
    </button>
  )
}

// ── Tab Stock vs FIFO ─────────────────────────────────────────────────────

function TabStockFifo() {
  const [estado, setEstado] = useState<EstadoReconciliacionStock | 'todos'>('todos')
  const [search, setSearch] = useState('')
  const { data, isLoading } = useReconciliacionStockFifo({ estado, search: search || undefined })
  const rows = data ?? []

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between flex-wrap gap-3">
          <CardTitle>Stock legacy (CPP) vs Inventario FIFO</CardTitle>
          <Button
            variant="outline" size="sm"
            disabled={rows.length === 0}
            onClick={() => exportCsv(`reconciliacion-stock-fifo-${new Date().toISOString().slice(0,10)}.csv`, rows as unknown as Record<string, unknown>[])}
          >
            <Download className="h-4 w-4 mr-1" /> Exportar CSV
          </Button>
        </div>
        <div className="flex items-center gap-2 flex-wrap mt-3">
          <FiltroEstadoStock value={estado} onChange={setEstado} />
          <div className="relative flex-1 min-w-[200px] max-w-md">
            <Search className="absolute left-2 top-1/2 -translate-y-1/2 h-4 w-4 text-gray-400" />
            <Input
              placeholder="Buscar producto..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="pl-8"
            />
          </div>
        </div>
      </CardHeader>
      <CardContent className="px-0">
        {isLoading ? (
          <div className="flex items-center justify-center py-10"><Spinner /></div>
        ) : rows.length === 0 ? (
          <div className="text-center text-sm text-gray-500 py-10">Sin filas</div>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Producto</TableHead>
                <TableHead>Bodega</TableHead>
                <TableHead className="text-right">Cant. legacy</TableHead>
                <TableHead className="text-right">Cant. FIFO</TableHead>
                <TableHead className="text-right">Δ cant.</TableHead>
                <TableHead className="text-right">Valor legacy</TableHead>
                <TableHead className="text-right">Valor FIFO</TableHead>
                <TableHead className="text-right">Δ valor</TableHead>
                <TableHead>Estado</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {rows.map((r) => <FilaStock key={`${r.producto_id}-${r.bodega_id}`} r={r} />)}
            </TableBody>
          </Table>
        )}
      </CardContent>
    </Card>
  )
}

function FilaStock({ r }: { r: ReconciliacionStockFifoRow }) {
  const deltaCant = Number(r.delta_cantidad ?? 0)
  const deltaVal = Number(r.delta_valor ?? 0)
  return (
    <TableRow>
      <TableCell>
        <div className="font-medium text-sm">{r.producto_nombre}</div>
        <div className="text-[11px] text-gray-500 font-mono">{r.producto_codigo} · {r.producto_categoria}</div>
      </TableCell>
      <TableCell>
        <div className="text-sm">{r.bodega_nombre}</div>
        <div className="text-[11px] text-gray-500 font-mono">{r.bodega_codigo}</div>
      </TableCell>
      <TableCell className="text-right tabular-nums">{Number(r.cantidad_legacy).toFixed(2)}</TableCell>
      <TableCell className="text-right tabular-nums">{Number(r.cantidad_fifo).toFixed(2)}</TableCell>
      <TableCell className={cn('text-right tabular-nums', Math.abs(deltaCant) > 0.001 && 'text-red-700 font-semibold')}>
        {deltaCant.toFixed(2)}
      </TableCell>
      <TableCell className="text-right tabular-nums">{formatCLP(Number(r.valor_legacy))}</TableCell>
      <TableCell className="text-right tabular-nums">{formatCLP(Number(r.valor_fifo))}</TableCell>
      <TableCell className={cn('text-right tabular-nums', Math.abs(deltaVal) > 1 && 'text-red-700 font-semibold')}>
        {formatCLP(deltaVal)}
      </TableCell>
      <TableCell>
        <Badge className={ESTADO_STOCK_COLOR[r.estado_reconciliacion]}>
          {ESTADO_STOCK_LABEL[r.estado_reconciliacion]}
        </Badge>
      </TableCell>
    </TableRow>
  )
}

function FiltroEstadoStock({
  value, onChange,
}: {
  value: EstadoReconciliacionStock | 'todos'
  onChange: (v: EstadoReconciliacionStock | 'todos') => void
}) {
  const opts: Array<{ v: EstadoReconciliacionStock | 'todos'; label: string }> = [
    { v: 'todos', label: 'Todos' },
    { v: 'desviacion_cantidad', label: 'Desv. cantidad' },
    { v: 'desviacion_valor', label: 'Desv. valor' },
    { v: 'sin_capa_fifo', label: 'Sin capa FIFO' },
    { v: 'sin_stock_legacy', label: 'Sin stock legacy' },
    { v: 'cuadrado', label: 'Cuadrados' },
  ]
  return (
    <div className="flex flex-wrap gap-1">
      {opts.map((o) => (
        <button
          key={o.v}
          onClick={() => onChange(o.v)}
          className={cn(
            'px-2.5 py-1 text-xs rounded-full border transition',
            value === o.v
              ? 'bg-amber-700 text-white border-amber-700'
              : 'bg-white text-gray-700 border-gray-300 hover:border-amber-400',
          )}
        >{o.label}</button>
      ))}
    </div>
  )
}

// ── Tab Combustible ───────────────────────────────────────────────────────

function TabCombustible() {
  const [estado, setEstado] = useState<EstadoReconciliacionCombustible | 'todos'>('todos')
  const { data, isLoading } = useReconciliacionCombustible({ estado })
  const rows = data ?? []

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between flex-wrap gap-3">
          <CardTitle>Reconciliación combustible (estanque vs varillaje vs kardex)</CardTitle>
          <Button
            variant="outline" size="sm"
            disabled={rows.length === 0}
            onClick={() => exportCsv(`reconciliacion-combustible-${new Date().toISOString().slice(0,10)}.csv`, rows as unknown as Record<string, unknown>[])}
          >
            <Download className="h-4 w-4 mr-1" /> Exportar CSV
          </Button>
        </div>
        <div className="flex items-center gap-2 flex-wrap mt-3">
          <FiltroEstadoCombustible value={estado} onChange={setEstado} />
        </div>
      </CardHeader>
      <CardContent className="px-0">
        {isLoading ? (
          <div className="flex items-center justify-center py-10"><Spinner /></div>
        ) : rows.length === 0 ? (
          <div className="text-center text-sm text-gray-500 py-10">Sin estanques</div>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Estanque</TableHead>
                <TableHead className="text-right">Teórico (lt)</TableHead>
                <TableHead className="text-right">Físico últ. (lt)</TableHead>
                <TableHead className="text-right">Δ físico</TableHead>
                <TableHead>Última varilla</TableHead>
                <TableHead className="text-right">CPP estanque</TableHead>
                <TableHead className="text-right">Kardex stock</TableHead>
                <TableHead>Estado</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {rows.map((r) => <FilaCombustible key={r.estanque_id} r={r} />)}
            </TableBody>
          </Table>
        )}
      </CardContent>
    </Card>
  )
}

function FilaCombustible({ r }: { r: ReconciliacionCombustibleRow }) {
  const delta = r.delta_fisico_vs_teorico_lt
  return (
    <TableRow>
      <TableCell>
        <div className="font-medium text-sm">{r.estanque_nombre}</div>
        <div className="text-[11px] text-gray-500 font-mono">{r.estanque_codigo} · cap {Number(r.capacidad_lt).toFixed(0)} lt</div>
      </TableCell>
      <TableCell className="text-right tabular-nums">{Number(r.estanque_stock_teorico_lt).toFixed(1)}</TableCell>
      <TableCell className="text-right tabular-nums">
        {r.varilla_fisico_lt != null ? Number(r.varilla_fisico_lt).toFixed(1) : '—'}
      </TableCell>
      <TableCell className={cn('text-right tabular-nums', delta != null && Math.abs(delta) > 50 && 'text-red-700 font-semibold')}>
        {delta != null ? delta.toFixed(1) : '—'}
      </TableCell>
      <TableCell>
        {r.varilla_fecha ? (
          <div>
            <div className="text-sm">{formatDate(r.varilla_fecha)}</div>
            {r.dias_desde_ultima_varilla != null && (
              <div className={cn(
                'text-[11px]',
                r.dias_desde_ultima_varilla > 7 ? 'text-amber-700 font-semibold' : 'text-gray-500',
              )}>
                hace {r.dias_desde_ultima_varilla}d
              </div>
            )}
          </div>
        ) : <span className="text-xs text-gray-400">sin registro</span>}
      </TableCell>
      <TableCell className="text-right tabular-nums">{formatCLP(Number(r.estanque_cpp_lt))}</TableCell>
      <TableCell className="text-right tabular-nums">
        {r.kardex_stock_lt != null ? Number(r.kardex_stock_lt).toFixed(1) : '—'}
      </TableCell>
      <TableCell>
        <Badge className={ESTADO_COMB_COLOR[r.estado_reconciliacion]}>
          {ESTADO_COMB_LABEL[r.estado_reconciliacion]}
        </Badge>
      </TableCell>
    </TableRow>
  )
}

function FiltroEstadoCombustible({
  value, onChange,
}: {
  value: EstadoReconciliacionCombustible | 'todos'
  onChange: (v: EstadoReconciliacionCombustible | 'todos') => void
}) {
  const opts: Array<{ v: EstadoReconciliacionCombustible | 'todos'; label: string }> = [
    { v: 'todos', label: 'Todos' },
    { v: 'sin_varillaje', label: 'Sin varillaje' },
    { v: 'varillaje_atrasado', label: 'Varillaje atrasado' },
    { v: 'desviacion_fisica', label: 'Desv. física' },
    { v: 'kardex_divergente', label: 'Kardex divergente' },
    { v: 'cuadrado', label: 'Cuadrados' },
  ]
  return (
    <div className="flex flex-wrap gap-1">
      {opts.map((o) => (
        <button
          key={o.v}
          onClick={() => onChange(o.v)}
          className={cn(
            'px-2.5 py-1 text-xs rounded-full border transition',
            value === o.v
              ? 'bg-amber-700 text-white border-amber-700'
              : 'bg-white text-gray-700 border-gray-300 hover:border-amber-400',
          )}
        >{o.label}</button>
      ))}
    </div>
  )
}

// ── Tab Movimientos excepcionales ─────────────────────────────────────────

function TabMovimientosExcepcionales() {
  const [tipo, setTipo] = useState<'ajuste' | 'merma' | 'todos'>('todos')
  const { data, isLoading } = useMovimientosExcepcionales({ tipo })
  const rows = data ?? []

  const totalCosto = useMemo(
    () => rows.reduce((acc, r) => acc + Number(r.costo_total ?? 0), 0),
    [rows],
  )

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between flex-wrap gap-3">
          <div>
            <CardTitle>Ajustes y mermas (últimos 60 días)</CardTitle>
            {rows.length > 0 && (
              <p className="text-xs text-gray-600 mt-1">
                Total impacto: <span className="font-mono font-semibold">{formatCLP(totalCosto)}</span>
              </p>
            )}
          </div>
          <Button
            variant="outline" size="sm"
            disabled={rows.length === 0}
            onClick={() => exportCsv(`mov-excepcionales-${new Date().toISOString().slice(0,10)}.csv`, rows as unknown as Record<string, unknown>[])}
          >
            <Download className="h-4 w-4 mr-1" /> Exportar CSV
          </Button>
        </div>
        <div className="flex items-center gap-2 flex-wrap mt-3">
          {(['todos', 'ajuste', 'merma'] as const).map((t) => (
            <button
              key={t}
              onClick={() => setTipo(t)}
              className={cn(
                'px-2.5 py-1 text-xs rounded-full border transition capitalize',
                tipo === t
                  ? 'bg-amber-700 text-white border-amber-700'
                  : 'bg-white text-gray-700 border-gray-300 hover:border-amber-400',
              )}
            >{t}</button>
          ))}
        </div>
      </CardHeader>
      <CardContent className="px-0">
        {isLoading ? (
          <div className="flex items-center justify-center py-10"><Spinner /></div>
        ) : rows.length === 0 ? (
          <div className="text-center text-sm text-gray-500 py-10 flex flex-col items-center gap-2">
            <CheckCircle2 className="h-8 w-8 text-green-500" />
            Sin ajustes ni mermas en el período
          </div>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Fecha</TableHead>
                <TableHead>Tipo</TableHead>
                <TableHead>Producto</TableHead>
                <TableHead>Bodega</TableHead>
                <TableHead className="text-right">Cantidad</TableHead>
                <TableHead className="text-right">Costo</TableHead>
                <TableHead>Motivo</TableHead>
                <TableHead>Usuario</TableHead>
                <TableHead>OT</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {rows.map((r) => <FilaMov key={r.movimiento_id} r={r} />)}
            </TableBody>
          </Table>
        )}
      </CardContent>
    </Card>
  )
}

function FilaMov({ r }: { r: MovimientoExcepcionalRow }) {
  return (
    <TableRow>
      <TableCell className="text-xs whitespace-nowrap">{formatDateTime(r.fecha)}</TableCell>
      <TableCell>
        <Badge className={r.tipo === 'merma' ? 'bg-red-100 text-red-700' : 'bg-orange-100 text-orange-700'}>
          {r.tipo}
        </Badge>
      </TableCell>
      <TableCell>
        <div className="text-sm font-medium">{r.producto_nombre}</div>
        <div className="text-[11px] text-gray-500 font-mono">{r.producto_codigo}</div>
      </TableCell>
      <TableCell>
        <div className="text-sm">{r.bodega_nombre}</div>
        <div className="text-[11px] text-gray-500 font-mono">{r.bodega_codigo}</div>
      </TableCell>
      <TableCell className="text-right tabular-nums">{Number(r.cantidad).toFixed(2)}</TableCell>
      <TableCell className="text-right tabular-nums">{formatCLP(Number(r.costo_total))}</TableCell>
      <TableCell className="max-w-[260px]">
        <div className="text-xs text-gray-700 line-clamp-2" title={r.motivo ?? ''}>
          {r.motivo ?? <span className="text-gray-400">—</span>}
        </div>
      </TableCell>
      <TableCell>
        <div className="text-xs">{r.usuario_nombre ?? '—'}</div>
        {r.usuario_rol && <div className="text-[10px] text-gray-500 font-mono">{r.usuario_rol}</div>}
      </TableCell>
      <TableCell>
        {r.ot_folio ? (
          <span className="text-xs font-mono">{r.ot_folio}</span>
        ) : <span className="text-xs text-gray-400">—</span>}
      </TableCell>
    </TableRow>
  )
}
