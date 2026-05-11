'use client'

import Link from 'next/link'
import { useParams, useRouter } from 'next/navigation'
import { ArrowLeft, Package, AlertCircle, ExternalLink, FileText } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Spinner } from '@/components/ui/spinner'
import {
  Table, TableHeader, TableBody, TableRow, TableHead, TableCell,
} from '@/components/ui/table'
import { formatCLP, formatDate } from '@/lib/utils'
import { useOCById } from '@/hooks/use-bodega-oc'
import type { EstadoOC, EstadoOCItem, TipoItemOC } from '@/lib/services/bodega-oc'

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

function tipoBadgeColor(t: TipoItemOC): string {
  switch (t) {
    case 'servicio': return 'bg-purple-100 text-purple-700'
    case 'inventariable': return 'bg-blue-100 text-blue-700'
    case 'combustible': return 'bg-amber-100 text-amber-700'
    case 'lubricante': return 'bg-amber-50 text-amber-800'
    case 'repuesto': return 'bg-cyan-100 text-cyan-700'
    case 'consumible': return 'bg-emerald-100 text-emerald-700'
    case 'activo': return 'bg-indigo-100 text-indigo-700'
    case 'otro': return 'bg-gray-100 text-gray-700'
    default: return 'bg-gray-100 text-gray-700'
  }
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

  const itemsPendientesMapeo = oc.items.filter((i) => i.requiere_stock && !i.producto_id).length

  return (
    <div className="p-6 max-w-5xl mx-auto space-y-4">
      <div className="flex items-center gap-2 flex-wrap">
        <Button variant="outline" size="sm" onClick={() => router.back()}>
          <ArrowLeft className="h-4 w-4 mr-1" /> Volver
        </Button>
        <h1 className="text-xl font-bold flex items-center gap-2">
          <Package className="h-5 w-5 text-amber-700" />
          OC {oc.numero_oc}
        </h1>
        {oc.numero_oc_externo && (
          <span className="text-sm text-gray-600 font-mono">ext: {oc.numero_oc_externo}</span>
        )}
        <Badge className={ESTADO_OC_COLOR[oc.estado]}>{oc.estado}</Badge>
        <Badge className={oc.origen === 'externa'
          ? 'bg-purple-100 text-purple-700'
          : 'bg-gray-100 text-gray-700'}>
          origen: {oc.origen}
        </Badge>
        {oc.documento_url && (
          <a
            href={oc.documento_url}
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center gap-1 text-xs text-amber-700 hover:text-amber-900 underline"
          >
            <ExternalLink className="h-3 w-3" /> Ver documento original
          </a>
        )}
      </div>

      <div className="rounded-lg border border-amber-200 bg-amber-50 p-3 text-xs text-amber-800 flex items-start gap-2">
        <AlertCircle className="h-4 w-4 mt-0.5 shrink-0" />
        <div>
          Recepción contra OC se habilitará en la próxima etapa del Frente #2.
          Por ahora solo lectura del detalle.
          {itemsPendientesMapeo > 0 && (
            <div className="mt-1">
              <strong>{itemsPendientesMapeo} ítem(s) inventariable(s)</strong> sin producto mapeado.
              Cuando se habilite recepción, deberás mapearlos antes.
            </div>
          )}
        </div>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Datos</CardTitle>
        </CardHeader>
        <CardContent className="grid grid-cols-2 md:grid-cols-4 gap-3 text-sm">
          <Dato label="Proveedor" value={oc.proveedor ? `${oc.proveedor.codigo} — ${oc.proveedor.nombre}` : '—'} />
          {oc.proveedor_rut_snapshot && (
            <Dato label="RUT (snapshot)" value={<span className="font-mono">{oc.proveedor_rut_snapshot}</span>} />
          )}
          <Dato label="Fecha emisión" value={oc.fecha_emision ? formatDate(oc.fecha_emision) : formatDate(oc.fecha_oc)} />
          {oc.fecha_entrega && (
            <Dato label="Fecha entrega" value={formatDate(oc.fecha_entrega)} />
          )}
          {oc.neto_clp != null && (
            <Dato label="Neto" value={<span className="font-mono">{formatCLP(oc.neto_clp)}</span>} />
          )}
          {oc.iva_clp != null && (
            <Dato label="IVA" value={<span className="font-mono">{formatCLP(oc.iva_clp)}</span>} />
          )}
          <Dato label="Monto total" value={<span className="font-mono font-semibold">{formatCLP(oc.monto_total_clp)}</span>} />
          {oc.forma_pago && (
            <Dato label="Forma de pago" value={oc.forma_pago} />
          )}
          {oc.observacion && (
            <Dato label="Observación" value={oc.observacion} className="md:col-span-4" />
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-base flex items-center gap-2">
            <FileText className="h-4 w-4 text-gray-600" />
            Items ({oc.items.length})
          </CardTitle>
        </CardHeader>
        <CardContent className="px-0">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Código / Descripción</TableHead>
                <TableHead>Tipo</TableHead>
                <TableHead>Unidad</TableHead>
                <TableHead>CC</TableHead>
                <TableHead className="text-right">Comprada</TableHead>
                <TableHead className="text-right">Recibida</TableHead>
                <TableHead className="text-right">Precio CLP</TableHead>
                <TableHead className="text-right">Subtotal</TableHead>
                <TableHead>Estado</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {oc.items.map((it) => (
                <TableRow key={it.id}>
                  <TableCell>
                    {it.codigo_externo && (
                      <div className="text-[11px] text-gray-500 font-mono">ext: {it.codigo_externo}</div>
                    )}
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
                  <TableCell>
                    <div className="flex flex-col gap-1">
                      <Badge className={tipoBadgeColor(it.tipo_item)}>{it.tipo_item}</Badge>
                      {it.requiere_stock ? (
                        <Badge className="bg-blue-50 text-blue-700 text-[10px]">stock</Badge>
                      ) : (
                        <Badge className="bg-gray-50 text-gray-600 text-[10px]">docum.</Badge>
                      )}
                      {it.requiere_stock && !it.producto_id && (
                        <Badge className="bg-amber-100 text-amber-700 text-[10px]">pend. mapeo</Badge>
                      )}
                    </div>
                  </TableCell>
                  <TableCell className="text-sm">
                    {it.unidad}
                    {it.unidad_externa && it.unidad_externa !== it.unidad && (
                      <div className="text-[10px] text-gray-500">ext: {it.unidad_externa}</div>
                    )}
                  </TableCell>
                  <TableCell className="text-xs font-mono">
                    {it.centro_costo_codigo_externo ?? '—'}
                  </TableCell>
                  <TableCell className="text-right tabular-nums">{Number(it.cantidad_comprada).toFixed(2)}</TableCell>
                  <TableCell className="text-right tabular-nums">{Number(it.cantidad_recibida).toFixed(2)}</TableCell>
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
