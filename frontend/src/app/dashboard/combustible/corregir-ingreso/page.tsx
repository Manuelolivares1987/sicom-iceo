'use client'

import { useState } from 'react'
import Link from 'next/link'
import {
  ArrowLeft, AlertTriangle, Ban, X, RefreshCw, FileText, Fuel,
} from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Spinner } from '@/components/ui/spinner'
import { Modal, ModalFooter } from '@/components/ui/modal'
import { Badge } from '@/components/ui/badge'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useToast } from '@/contexts/toast-context'
import {
  useIngresosAnulables, useAnularIngresoCombustible, useEstanquesActivos,
} from '@/hooks/use-combustible-cpp'
import type { IngresoAnulableRow } from '@/lib/services/combustible-cpp'
import { formatCLP, formatDateTime } from '@/lib/utils'

export default function CorregirIngresoPage() {
  useRequireAuth()
  const toast = useToast()

  const [estanqueFiltro, setEstanqueFiltro] = useState<string>('')
  const { data: estanques } = useEstanquesActivos()
  const { data: ingresos, isLoading, refetch, isFetching } =
    useIngresosAnulables(estanqueFiltro || null)

  const [seleccionado, setSeleccionado] = useState<IngresoAnulableRow | null>(null)
  const [motivo, setMotivo] = useState('')

  const anular = useAnularIngresoCombustible()

  const ejecutarAnulacion = () => {
    if (!seleccionado) return
    if (motivo.trim().length < 10) {
      toast.error('Motivo obligatorio (mínimo 10 caracteres)')
      return
    }
    anular.mutate(
      { kardexId: seleccionado.kardex_id, motivo: motivo.trim() },
      {
        onSuccess: (r) => {
          toast.success(
            `Ingreso anulado: ${r.litros_revertidos} lt revertidos. ` +
            `CPP restaurado a ${formatCLP(r.cpp_restaurado)}.`,
          )
          setSeleccionado(null)
          setMotivo('')
        },
        onError: (e) => {
          toast.error(e instanceof Error ? e.message : 'Error al anular')
        },
      },
    )
  }

  return (
    <div className="space-y-4 p-6">
      <Link
        href="/dashboard/combustible"
        className="inline-flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700"
      >
        <ArrowLeft className="h-4 w-4" /> Volver al Panel Combustible
      </Link>

      <div className="rounded-2xl bg-gradient-to-r from-red-700 to-orange-600 p-6 text-white shadow-lg">
        <h1 className="text-2xl font-bold flex items-center gap-2">
          <Ban className="h-6 w-6" />
          Corregir ingreso mal cargado
        </h1>
        <p className="text-sm text-white/90 mt-1">
          Anula un ingreso valorizado erróneo y revierte stock + CPP del estanque al estado previo.
          <strong className="ml-1">Solo administrador / subgerente.</strong>
        </p>
      </div>

      <div className="rounded-lg border border-amber-200 bg-amber-50 p-3 text-xs text-amber-900 flex items-start gap-2">
        <AlertTriangle className="h-4 w-4 mt-0.5 shrink-0" />
        <div>
          <strong>Regla contable:</strong> solo se puede anular un ingreso si NO hubo movimientos
          posteriores en el mismo estanque. Si los hubo, hace un asiento correctivo manual:
          ingresa un movimiento inverso + el ingreso correcto.
        </div>
      </div>

      <Card>
        <CardContent className="p-3 flex flex-wrap items-end gap-3">
          <div className="flex-1 min-w-[220px]">
            <label className="text-xs text-gray-500">Filtrar por estanque</label>
            <select
              value={estanqueFiltro}
              onChange={(e) => setEstanqueFiltro(e.target.value)}
              className="mt-1 w-full rounded border border-gray-300 px-3 py-2 text-sm"
            >
              <option value="">Todos los estanques</option>
              {(estanques ?? []).map((e) => (
                <option key={e.id} value={e.id}>
                  {e.codigo} — {e.nombre}
                </option>
              ))}
            </select>
          </div>
          <Button variant="outline" onClick={() => refetch()} disabled={isFetching}>
            <RefreshCw className={`h-4 w-4 mr-1 ${isFetching ? 'animate-spin' : ''}`} /> Refrescar
          </Button>
        </CardContent>
      </Card>

      {isLoading && (
        <div className="flex items-center gap-2 text-sm text-gray-500">
          <Spinner className="h-4 w-4" /> Cargando ingresos…
        </div>
      )}

      {ingresos && ingresos.length === 0 && (
        <Card>
          <CardContent className="p-8 text-center text-sm text-gray-500">
            <Fuel className="h-8 w-8 mx-auto text-gray-300 mb-2" />
            No hay ingresos de combustible pendientes de revisión.
          </CardContent>
        </Card>
      )}

      <div className="space-y-2">
        {(ingresos ?? []).map((ing) => (
          <Card key={ing.kardex_id}>
            <CardContent className="p-3 flex flex-wrap items-start gap-3 justify-between">
              <div className="flex-1 min-w-[260px]">
                <div className="flex items-center gap-2 flex-wrap">
                  <span className="font-mono text-xs text-gray-500">
                    {ing.folio_movimiento ?? ing.kardex_id.slice(0, 8)}
                  </span>
                  <Badge className="bg-blue-100 text-blue-700">
                    {ing.estanque_codigo} — {ing.estanque_nombre}
                  </Badge>
                  {ing.tiene_posteriores && (
                    <Badge className="bg-amber-100 text-amber-800">
                      <AlertTriangle className="h-3 w-3 mr-1 inline" />
                      Tiene posteriores
                    </Badge>
                  )}
                </div>
                <div className="text-sm text-gray-900 mt-1">
                  <strong>{Number(ing.litros).toLocaleString('es-CL')} lt</strong>
                  <span className="text-gray-500"> × </span>
                  <strong>{formatCLP(Number(ing.precio_unitario))}/lt</strong>
                  <span className="text-gray-500"> = </span>
                  <strong className="font-mono">{formatCLP(Number(ing.valor_ingreso))}</strong>
                </div>
                <div className="text-xs text-gray-500 mt-1 flex flex-wrap gap-3">
                  <span>📅 {formatDateTime(ing.fecha_movimiento)}</span>
                  {ing.proveedor_nombre && <span>🏭 {ing.proveedor_nombre}</span>}
                  {ing.documento_numero && (
                    <span><FileText className="inline h-3 w-3 mr-0.5" />{ing.documento_numero}</span>
                  )}
                </div>
                {ing.observacion && (
                  <div className="text-[11px] text-gray-500 mt-1 italic truncate max-w-xl">
                    {ing.observacion}
                  </div>
                )}
              </div>
              <Button
                variant="danger"
                onClick={() => { setSeleccionado(ing); setMotivo('') }}
                disabled={ing.tiene_posteriores}
                title={ing.tiene_posteriores
                  ? 'No se puede anular: hay movimientos posteriores en este estanque'
                  : 'Anular ingreso'}
              >
                <Ban className="h-4 w-4 mr-1" /> Anular
              </Button>
            </CardContent>
          </Card>
        ))}
      </div>

      <Modal
        open={!!seleccionado}
        onClose={() => !anular.isPending && (setSeleccionado(null), setMotivo(''))}
        title="Anular ingreso de combustible"
      >
        {seleccionado && (
          <div className="space-y-3 text-sm">
            <div className="rounded border bg-red-50 p-2 text-xs text-red-900 space-y-1">
              <div className="flex items-center gap-1 font-semibold">
                <AlertTriangle className="h-4 w-4" /> Esta acción revierte stock y CPP
              </div>
              <div className="font-mono text-red-700">{seleccionado.folio_movimiento}</div>
              <div>
                Estanque: <strong>{seleccionado.estanque_codigo} — {seleccionado.estanque_nombre}</strong>
              </div>
              <div>
                Revertir: <strong>{Number(seleccionado.litros).toLocaleString('es-CL')} lt</strong>
                {' '} × <strong>{formatCLP(Number(seleccionado.precio_unitario))}/lt</strong>
              </div>
              <div>
                Valor total revertido:{' '}
                <strong className="font-mono">{formatCLP(Number(seleccionado.valor_ingreso))}</strong>
              </div>
            </div>

            <div>
              <label className="text-xs text-gray-500">
                Motivo obligatorio (mínimo 10 caracteres) *
              </label>
              <textarea
                rows={3}
                value={motivo}
                onChange={(e) => setMotivo(e.target.value)}
                placeholder="Ej: precio cargado fue 950 cuando factura ENEX dice 920. Re-cargar con valor correcto."
                className="mt-1 w-full rounded border border-red-300 px-3 py-2 text-sm"
              />
              <div className="text-[10px] text-gray-500 mt-0.5">
                {motivo.trim().length}/10 caracteres mínimos
              </div>
            </div>
          </div>
        )}
        <ModalFooter className="-mx-6 -mb-6 mt-4 px-6 pb-6 pt-4 border-t border-gray-100">
          <Button
            variant="secondary"
            onClick={() => { setSeleccionado(null); setMotivo('') }}
            disabled={anular.isPending}
          >
            <X className="h-4 w-4" /> Cancelar
          </Button>
          <Button
            variant="danger"
            onClick={ejecutarAnulacion}
            disabled={motivo.trim().length < 10}
            loading={anular.isPending}
          >
            <Ban className="h-4 w-4" /> Confirmar anulación
          </Button>
        </ModalFooter>
      </Modal>
    </div>
  )
}
