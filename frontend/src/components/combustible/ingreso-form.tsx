'use client'

import { useMemo, useState } from 'react'
import { useRouter } from 'next/navigation'
import { ArrowLeft, Save, AlertCircle, ArrowUpRight, Sparkles } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Spinner } from '@/components/ui/spinner'
import { formatCLP, todayISO } from '@/lib/utils'
import { useToast } from '@/contexts/toast-context'
import {
  useEstanquesActivos, useProveedoresCombustible, useRegistrarIngresoCombustible,
} from '@/hooks/use-combustible-cpp'
import type { IngresoCombustiblePayload } from '@/lib/services/combustible-cpp'

export function IngresoCombustibleForm() {
  const router = useRouter()
  const toast = useToast()
  const [estanqueId, setEstanqueId] = useState('')
  const [litros, setLitros]       = useState<number | ''>('')
  const [costo, setCosto]         = useState<number | ''>('')
  const [proveedorId, setProveedorId] = useState('')
  const [docTipo, setDocTipo]     = useState('factura')
  const [docNumero, setDocNumero] = useState('')
  const [fecha, setFecha]         = useState<string>(todayISO())
  const [observacion, setObservacion] = useState('')

  const { data: estanques, isLoading: loadEst } = useEstanquesActivos()
  const { data: proveedores, isLoading: loadProv } = useProveedoresCombustible()
  const registrar = useRegistrarIngresoCombustible()

  const estanque = estanques?.find((e) => e.id === estanqueId)
  const litrosNum = typeof litros === 'number' ? litros : 0
  const costoNum = typeof costo === 'number' ? costo : 0
  const valorTotal = litrosNum * costoNum

  // CPP simulado
  const cppSimulado = useMemo(() => {
    if (!estanque || litrosNum <= 0 || costoNum < 0) return null
    const stockAct = Number(estanque.stock_teorico_lt)
    const cppAct = Number(estanque.costo_promedio_lt)
    if (stockAct <= 0) return Math.round(costoNum * 10000) / 10000
    const stockPost = stockAct + litrosNum
    return Math.round(((stockAct * cppAct + litrosNum * costoNum) / stockPost) * 10000) / 10000
  }, [estanque, litrosNum, costoNum])

  const excedeCapacidad = estanque && (Number(estanque.stock_teorico_lt) + litrosNum > Number(estanque.capacidad_lt))

  const errores: string[] = []
  if (!estanqueId) errores.push('Selecciona estanque.')
  if (litrosNum <= 0) errores.push('Litros debe ser > 0.')
  if (costoNum < 0) errores.push('Costo debe ser >= 0.')
  if (excedeCapacidad) errores.push(`Ingreso supera capacidad del estanque (${estanque?.capacidad_lt} lt).`)
  if (!docNumero.trim()) errores.push('N° documento obligatorio.')
  const canSubmit = errores.length === 0

  if (loadEst || loadProv) {
    return <div className="flex justify-center py-10"><Spinner /></div>
  }

  const onSubmit = () => {
    if (!canSubmit) {
      toast.error('Revisa los campos marcados')
      return
    }
    const payload: IngresoCombustiblePayload = {
      estanque_id: estanqueId,
      litros: litrosNum,
      costo_unitario_clp: costoNum,
      proveedor_id: proveedorId || null,
      doc_tipo: docTipo,
      doc_numero: docNumero.trim(),
      fecha_movimiento: fecha ? `${fecha}T00:00:00Z` : null,
      observacion: observacion.trim() || null,
    }
    registrar.mutate(payload, {
      onSuccess: (data) => {
        toast.success(
          `Ingreso ${data.folio}: +${data.litros_ingresados} lt @ ${formatCLP(data.costo_unitario_ingreso)} · CPP ${formatCLP(data.cpp_anterior)} → ${formatCLP(data.cpp_nuevo)}`,
        )
        router.push('/dashboard/combustible')
      },
      onError: (err: unknown) => {
        const msg = err instanceof Error ? err.message : 'Error al registrar ingreso'
        toast.error(msg)
      },
    })
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-2">
        <Button variant="outline" size="sm" onClick={() => router.back()}>
          <ArrowLeft className="h-4 w-4 mr-1" /> Volver
        </Button>
        <h1 className="text-xl font-bold flex items-center gap-2">
          <ArrowUpRight className="h-5 w-5 text-green-700" />
          Ingreso valorizado de combustible
        </h1>
      </div>

      <div className="rounded-lg border border-blue-200 bg-blue-50 p-3 text-xs text-blue-900 flex items-start gap-2">
        <AlertCircle className="h-4 w-4 mt-0.5 shrink-0" />
        <div>
          <strong>CPP móvil.</strong> El ingreso recalcula el costo promedio del estanque automáticamente.
          Solo afecta combustible — no toca stock_bodega ni inventario_capas.
        </div>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Datos del ingreso</CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">Estanque *</label>
              <select
                value={estanqueId}
                onChange={(e) => setEstanqueId(e.target.value)}
                className="w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-sm"
              >
                <option value="">— Selecciona estanque —</option>
                {(estanques ?? []).map((e) => (
                  <option key={e.id} value={e.id}>
                    {e.codigo} — {e.nombre} (stock {Number(e.stock_teorico_lt).toFixed(0)} lt / {e.capacidad_lt} lt)
                  </option>
                ))}
              </select>
              {estanque && (
                <div className="text-[11px] text-gray-600 mt-1 flex flex-wrap gap-2">
                  <span>Stock actual: <strong>{Number(estanque.stock_teorico_lt).toFixed(2)} lt</strong></span>
                  <span>CPP actual: <strong>{formatCLP(Number(estanque.costo_promedio_lt))}</strong></span>
                  <span>Capacidad: <strong>{Number(estanque.capacidad_lt).toFixed(0)} lt</strong></span>
                </div>
              )}
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">Proveedor (opcional)</label>
              <select
                value={proveedorId}
                onChange={(e) => setProveedorId(e.target.value)}
                className="w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-sm"
              >
                <option value="">— Sin proveedor —</option>
                {(proveedores ?? []).map((p) => (
                  <option key={p.id} value={p.id}>{p.codigo} — {p.nombre}</option>
                ))}
              </select>
            </div>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">Litros *</label>
              <Input
                type="number" step="0.01" min="0.01"
                value={litros}
                onChange={(e) => setLitros(e.target.value === '' ? '' : Number(e.target.value))}
                className={excedeCapacidad ? 'border-red-500' : ''}
              />
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">Costo unitario CLP/lt *</label>
              <Input
                type="number" step="0.01" min="0"
                value={costo}
                onChange={(e) => setCosto(e.target.value === '' ? '' : Number(e.target.value))}
              />
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">Valor total ingreso</label>
              <div className="h-[42px] flex items-center justify-end px-3 rounded-md bg-gray-50 border border-gray-200 text-sm tabular-nums font-semibold">
                {formatCLP(valorTotal)}
              </div>
            </div>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">Documento</label>
              <select
                value={docTipo}
                onChange={(e) => setDocTipo(e.target.value)}
                className="w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-sm"
              >
                <option value="factura">Factura</option>
                <option value="guia">Guía</option>
                <option value="vale">Vale</option>
                <option value="boleta">Boleta</option>
                <option value="otro">Otro</option>
              </select>
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">N° documento *</label>
              <Input value={docNumero} onChange={(e) => setDocNumero(e.target.value)} placeholder="ej: 12345" />
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">Fecha</label>
              <Input type="date" value={fecha} onChange={(e) => setFecha(e.target.value)} />
            </div>
          </div>

          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">Observación</label>
            <Input value={observacion} onChange={(e) => setObservacion(e.target.value)} placeholder="opcional" />
          </div>

          {cppSimulado != null && estanque && litrosNum > 0 && (
            <div className="rounded-lg border border-green-200 bg-green-50 p-3 text-xs text-green-900 flex items-start gap-2">
              <Sparkles className="h-4 w-4 mt-0.5 shrink-0" />
              <div>
                <strong>Simulación CPP:</strong> {formatCLP(Number(estanque.costo_promedio_lt))} → <strong>{formatCLP(cppSimulado)}</strong>
                {' '}· Stock {Number(estanque.stock_teorico_lt).toFixed(2)} → <strong>{(Number(estanque.stock_teorico_lt) + litrosNum).toFixed(2)} lt</strong>
                {' '}· Valor stock post: {formatCLP((Number(estanque.stock_teorico_lt) + litrosNum) * cppSimulado)}
              </div>
            </div>
          )}
        </CardContent>
      </Card>

      {errores.length > 0 && (estanqueId || litros !== '' || costo !== '') && (
        <div className="rounded-lg border border-amber-200 bg-amber-50 p-2 text-xs text-amber-900">
          <ul className="list-disc list-inside">{errores.map((e, i) => <li key={i}>{e}</li>)}</ul>
        </div>
      )}

      <Card>
        <CardContent className="flex items-center justify-between py-4">
          <Button variant="outline" onClick={() => router.back()} disabled={registrar.isPending}>Cancelar</Button>
          <Button onClick={onSubmit} disabled={!canSubmit || registrar.isPending}>
            {registrar.isPending ? <Spinner className="h-4 w-4 mr-2" /> : <Save className="h-4 w-4 mr-2" />}
            {registrar.isPending ? 'Registrando...' : 'Registrar ingreso'}
          </Button>
        </CardContent>
      </Card>
    </div>
  )
}

