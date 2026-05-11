'use client'

import Link from 'next/link'
import { useState } from 'react'
import { Search, Plus, FileText, RefreshCw, Upload } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Input } from '@/components/ui/input'
import { Spinner } from '@/components/ui/spinner'
import {
  Table, TableHeader, TableBody, TableRow, TableHead, TableCell,
} from '@/components/ui/table'
import { formatCLP, formatDate, cn } from '@/lib/utils'
import { useOCList, useProveedoresActivos } from '@/hooks/use-bodega-oc'
import type { EstadoOC } from '@/lib/services/bodega-oc'
import { useQueryClient } from '@tanstack/react-query'

const ESTADO_COLOR: Record<EstadoOC, string> = {
  abierta:  'bg-blue-100 text-blue-700',
  parcial:  'bg-amber-100 text-amber-700',
  cerrada:  'bg-green-100 text-green-700',
  anulada:  'bg-gray-200 text-gray-600',
}
const ESTADO_LABEL: Record<EstadoOC, string> = {
  abierta: 'Abierta', parcial: 'Parcial', cerrada: 'Cerrada', anulada: 'Anulada',
}

export function OCList() {
  const [estado, setEstado] = useState<EstadoOC | 'todos'>('todos')
  const [proveedorId, setProveedorId] = useState<string>('')
  const [search, setSearch] = useState('')
  const qc = useQueryClient()

  const filtros = {
    estado,
    proveedor_id: proveedorId || undefined,
    search: search.trim() || undefined,
  }

  const { data: ocs, isLoading, isFetching } = useOCList(filtros)
  const { data: proveedores } = useProveedoresActivos()

  const refresh = () => qc.invalidateQueries({ queryKey: ['bodega-oc'] })

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between gap-3 flex-wrap">
          <CardTitle className="flex items-center gap-2">
            <FileText className="h-5 w-5 text-amber-700" />
            Órdenes de Compra
          </CardTitle>
          <div className="flex items-center gap-2 flex-wrap">
            <Button variant="outline" size="sm" onClick={refresh} disabled={isFetching}>
              <RefreshCw className={cn('h-4 w-4 mr-1', isFetching && 'animate-spin')} />
              Actualizar
            </Button>
            <Link href="/dashboard/abastecimiento/oc/nueva">
              <Button variant="outline" size="sm">
                <Plus className="h-4 w-4 mr-1" />
                Crear manual
              </Button>
            </Link>
            <Link href="/dashboard/abastecimiento/oc/importar">
              <Button size="sm">
                <Upload className="h-4 w-4 mr-1" />
                Importar OC externa
              </Button>
            </Link>
          </div>
        </div>

        <div className="flex items-center gap-2 flex-wrap mt-3">
          <PildoraEstado value={estado} onChange={setEstado} />
          <div className="flex-1 min-w-[180px] max-w-[260px]">
            <select
              value={proveedorId}
              onChange={(e) => setProveedorId(e.target.value)}
              className="w-full rounded-md border border-gray-300 bg-white px-2 py-1.5 text-sm"
            >
              <option value="">Todos los proveedores</option>
              {(proveedores ?? []).map((p) => (
                <option key={p.id} value={p.id}>
                  {p.codigo} — {p.nombre}
                </option>
              ))}
            </select>
          </div>
          <div className="relative flex-1 min-w-[180px] max-w-md">
            <Search className="absolute left-2 top-1/2 -translate-y-1/2 h-4 w-4 text-gray-400" />
            <Input
              placeholder="Buscar por N° OC..."
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
        ) : (ocs?.length ?? 0) === 0 ? (
          <div className="text-center text-sm text-gray-500 py-10">
            Sin órdenes de compra todavía. {' '}
            <Link href="/dashboard/abastecimiento/oc/nueva" className="text-amber-700 underline">
              Crear la primera
            </Link>
          </div>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>N° OC</TableHead>
                <TableHead>Origen</TableHead>
                <TableHead>Proveedor</TableHead>
                <TableHead>Fecha</TableHead>
                <TableHead>Estado</TableHead>
                <TableHead className="text-right">Items</TableHead>
                <TableHead className="text-right">Recibido %</TableHead>
                <TableHead className="text-right">Monto</TableHead>
                <TableHead></TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {(ocs ?? []).map((oc) => (
                <TableRow key={oc.id}>
                  <TableCell>
                    <div className="font-mono text-sm">{oc.numero_oc}</div>
                    {oc.numero_oc_externo && (
                      <div className="text-[11px] text-gray-500 font-mono">ext: {oc.numero_oc_externo}</div>
                    )}
                  </TableCell>
                  <TableCell>
                    <Badge className={oc.origen === 'externa'
                      ? 'bg-purple-100 text-purple-700'
                      : 'bg-gray-100 text-gray-700'}>
                      {oc.origen}
                    </Badge>
                  </TableCell>
                  <TableCell>
                    {oc.proveedor ? (
                      <>
                        <div className="text-sm">{oc.proveedor.nombre}</div>
                        <div className="text-[11px] text-gray-500 font-mono">{oc.proveedor.codigo}</div>
                      </>
                    ) : (
                      <span className="text-xs text-gray-400">—</span>
                    )}
                  </TableCell>
                  <TableCell className="text-sm">{formatDate(oc.fecha_oc)}</TableCell>
                  <TableCell>
                    <Badge className={ESTADO_COLOR[oc.estado]}>
                      {ESTADO_LABEL[oc.estado]}
                    </Badge>
                  </TableCell>
                  <TableCell className="text-right tabular-nums">
                    {oc.items_count}
                    {(oc.items_servicios > 0 || oc.items_inventariables > 0) && (
                      <div className="text-[10px] text-gray-500">
                        {oc.items_inventariables}st · {oc.items_servicios}svc
                      </div>
                    )}
                  </TableCell>
                  <TableCell className="text-right tabular-nums">
                    {oc.items_recibidos_pct}%
                  </TableCell>
                  <TableCell className="text-right tabular-nums">
                    {formatCLP(oc.monto_total_clp)}
                  </TableCell>
                  <TableCell>
                    <Link href={`/dashboard/abastecimiento/oc/${oc.id}`}>
                      <Button variant="outline" size="sm">Ver</Button>
                    </Link>
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

function PildoraEstado({
  value, onChange,
}: { value: EstadoOC | 'todos'; onChange: (v: EstadoOC | 'todos') => void }) {
  const opts: Array<{ v: EstadoOC | 'todos'; label: string }> = [
    { v: 'todos', label: 'Todas' },
    { v: 'abierta', label: 'Abiertas' },
    { v: 'parcial', label: 'Parciales' },
    { v: 'cerrada', label: 'Cerradas' },
    { v: 'anulada', label: 'Anuladas' },
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
