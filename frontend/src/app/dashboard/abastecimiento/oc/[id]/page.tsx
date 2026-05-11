'use client'

import Link from 'next/link'
import { useParams, useRouter } from 'next/navigation'
import { ArrowLeft, Package, AlertCircle } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Spinner } from '@/components/ui/spinner'
import {
  Table, TableHeader, TableBody, TableRow, TableHead, TableCell,
} from '@/components/ui/table'
import { formatCLP, formatDate } from '@/lib/utils'
import { useOCById } from '@/hooks/use-bodega-oc'
import type { EstadoOC, EstadoOCItem } from '@/lib/services/bodega-oc'

const ESTADO_OC_COLOR: Record<EstadoOC, string> = {
  abierta:  'bg-blue-100 text-blue-700',
  parcial:  'bg-amber-100 text-amber-700',
  cerrada:  'bg-green-100 text-green-700',
  anulada:  'bg-gray-200 text-gray-600',
}
const ESTADO_ITEM_COLOR: Record<EstadoOCItem, string> = {
  pendiente: 'bg-gray-100 text-gray-700',
  parcial:   'bg-amber-100 text-amber-700',
  completo:  'bg-green-100 text-green-700',
}

export default function OCDetallePage() {
  const params = useParams<{ id: string }>()
  const router = useRouter()
  const { data: oc, isLoading, isError, error } = useOCById(params.id)

  if (isLoading) {
    return <div className="flex justify-center py-10"><Spinner /></div>
  }
  if (isError || !oc) {
    return (
      <div className="p-6 max-w-4xl mx-auto">
        <div className="rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-800">
          No se pudo cargar la OC. {error instanceof Error ? error.message : ''}
        </div>
        <div className="mt-3">
          <Link href="/dashboard/abastecimiento/oc">
            <Button variant="outline" size="sm">
              <ArrowLeft className="h-4 w-4 mr-1" /> Volver al listado
            </Button>
          </Link>
        </div>
      </div>
    )
  }

  return (
    <div className="p-6 max-w-5xl mx-auto space-y-4">
      <div className="flex items-center gap-2">
        <Button variant="outline" size="sm" onClick={() => router.back()}>
          <ArrowLeft className="h-4 w-4 mr-1" /> Volver
        </Button>
        <h1 className="text-xl font-bold flex items-center gap-2">
          <Package className="h-5 w-5 text-amber-700" />
          OC {oc.numero_oc}
        </h1>
        <Badge className={ESTADO_OC_COLOR[oc.estado]}>{oc.estado}</Badge>
      </div>

      <div className="rounded-lg border border-amber-200 bg-amber-50 p-3 text-xs text-amber-800 flex items-start gap-2">
        <AlertCircle className="h-4 w-4 mt-0.5 shrink-0" />
        <div>
          Recepción contra OC se habilitará en la próxima etapa del Frente #2.
          Por ahora solo lectura del detalle.
        </div>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Datos</CardTitle>
        </CardHeader>
        <CardContent className="grid grid-cols-2 md:grid-cols-4 gap-3 text-sm">
          <Dato label="Proveedor" value={oc.proveedor ? `${oc.proveedor.codigo} — ${oc.proveedor.nombre}` : '—'} />
          <Dato label="Fecha OC"  value={formatDate(oc.fecha_oc)} />
          <Dato label="Estado"    value={<Badge className={ESTADO_OC_COLOR[oc.estado]}>{oc.estado}</Badge>} />
          <Dato label="Monto"     value={<span className="font-mono font-semibold">{formatCLP(oc.monto_total_clp)}</span>} />
          {oc.observacion && (
            <Dato label="Observación" value={oc.observacion} className="md:col-span-4" />
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Items ({oc.items.length})</CardTitle>
        </CardHeader>
        <CardContent className="px-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Producto / Descripción</TableHead>
                <TableHead>Unidad</TableHead>
                <TableHead className="text-right">Comprada</TableHead>
                <TableHead className="text-right">Recibida</TableHead>
                <TableHead className="text-right">Pendiente</TableHead>
                <TableHead className="text-right">Precio CLP</TableHead>
                <TableHead className="text-right">Subtotal</TableHead>
                <TableHead>Estado</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {oc.items.map((it) => (
                <TableRow key={it.id}>
                  <TableCell>
                    {it.producto ? (
                      <>
                        <div className="text-sm font-medium">{it.producto.nombre}</div>
                        <div className="text-[11px] text-gray-500 font-mono">
                          {it.producto.codigo} — {it.descripcion}
                        </div>
                      </>
                    ) : (
                      <div className="text-sm">{it.descripcion}</div>
                    )}
                  </TableCell>
                  <TableCell className="text-sm">{it.unidad}</TableCell>
                  <TableCell className="text-right tabular-nums">{Number(it.cantidad_comprada).toFixed(2)}</TableCell>
                  <TableCell className="text-right tabular-nums">{Number(it.cantidad_recibida).toFixed(2)}</TableCell>
                  <TableCell className="text-right tabular-nums">{Number(it.cantidad_pendiente).toFixed(2)}</TableCell>
                  <TableCell className="text-right tabular-nums">{formatCLP(Number(it.precio_unitario_clp))}</TableCell>
                  <TableCell className="text-right tabular-nums">
                    {formatCLP(Number(it.cantidad_comprada) * Number(it.precio_unitario_clp))}
                  </TableCell>
                  <TableCell>
                    <Badge className={ESTADO_ITEM_COLOR[it.estado]}>{it.estado}</Badge>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>
    </div>
  )
}

function Dato({ label, value, className }: { label: string; value: React.ReactNode; className?: string }) {
  return (
    <div className={className}>
      <div className="text-[11px] uppercase text-gray-500 font-semibold">{label}</div>
      <div className="text-sm mt-0.5">{value}</div>
    </div>
  )
}
