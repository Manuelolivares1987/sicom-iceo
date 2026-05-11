'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { ArrowLeft, Save, AlertCircle, ArrowDownRight } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Badge } from '@/components/ui/badge'
import { Spinner } from '@/components/ui/spinner'
import { formatCLP, todayISO } from '@/lib/utils'
import { useToast } from '@/contexts/toast-context'
import {
  useEstanquesActivos, useFaenas, useActivos, useRegistrarSalidaCombustible,
} from '@/hooks/use-combustible-cpp'
import { useOTsValidasSalida, useCECO } from '@/hooks/use-bodega-salida-fifo'
import type {
  SalidaCombustiblePayload, DestinoSalidaCombustible,
} from '@/lib/services/combustible-cpp'

const DESTINOS: { v: DestinoSalidaCombustible; label: string; hint: string }[] = [
  { v: 'equipo',          label: 'Equipo / vehículo', hint: 'Despacho a un activo del maestro' },
  { v: 'ot',              label: 'Orden de Trabajo',  hint: 'Consumo asociado a una OT (estado asignada/en_ejecucion)' },
  { v: 'ceco',            label: 'Centro de Costo',   hint: 'Imputado a un CECO sin OT específica' },
  { v: 'faena',           label: 'Faena',             hint: 'Despacho global a una faena' },
  { v: 'consumo_interno', label: 'Consumo interno',   hint: 'Uso operativo sin destino externo' },
  { v: 'venta_externa',   label: 'Venta externa',     hint: 'Cliente externo identificado por nombre' },
]

export function SalidaCombustibleForm() {
  const router = useRouter()
  const toast = useToast()
  const [estanqueId, setEstanqueId] = useState('')
  const [litros, setLitros]         = useState<number | ''>('')
  const [destino, setDestino]       = useState<DestinoSalidaCombustible>('equipo')
  const [equipoId, setEquipoId]     = useState('')
  const [otId, setOtId]             = useState('')
  const [cecoId, setCecoId]         = useState('')
  const [faenaId, setFaenaId]       = useState('')
  const [clienteNombre, setClienteNombre] = useState('')
  const [motivo, setMotivo]         = useState('')
  const [fecha, setFecha]           = useState<string>(todayISO())
  const [observacion, setObservacion] = useState('')

  const { data: estanques, isLoading: loadEst } = useEstanquesActivos()
  const { data: activos } = useActivos()
  const { data: ots } = useOTsValidasSalida()
  const { data: cecos } = useCECO()
  const { data: faenas } = useFaenas()
  const registrar = useRegistrarSalidaCombustible()

  const estanque = estanques?.find((e) => e.id === estanqueId)
  const litrosNum = typeof litros === 'number' ? litros : 0
  const stockActual = estanque ? Number(estanque.stock_teorico_lt) : 0
  const cppVigente = estanque ? Number(estanque.costo_promedio_lt) : 0
  const costoSimulado = litrosNum * cppVigente
  const excedeStock = estanque && litrosNum > stockActual

  // Helpers requeridos por destino
  const requiereEquipo  = destino === 'equipo'
  const requiereOT      = destino === 'ot'
  const requiereCECO    = destino === 'ceco'
  const requiereFaena   = destino === 'faena'
  const requiereCliente = destino === 'venta_externa'

  const errores: string[] = []
  if (!estanqueId) errores.push('Selecciona estanque.')
  if (litrosNum <= 0) errores.push('Litros debe ser > 0.')
  if (excedeStock) errores.push(`Stock insuficiente: solicitado ${litrosNum} lt, disponible ${stockActual.toFixed(2)} lt.`)
  if (motivo.trim().length < 5) errores.push('Motivo mínimo 5 caracteres.')
  if (requiereEquipo && !equipoId) errores.push('Destino equipo: selecciona el activo.')
  if (requiereOT && !otId) errores.push('Destino OT: selecciona la orden de trabajo.')
  if (requiereCECO && !cecoId) errores.push('Destino CECO: selecciona el centro de costo.')
  if (requiereFaena && !faenaId) errores.push('Destino faena: selecciona la faena.')
  if (requiereCliente && !clienteNombre.trim()) errores.push('Venta externa: nombre del cliente obligatorio.')
  const canSubmit = errores.length === 0

  if (loadEst) {
    return <div className="flex justify-center py-10"><Spinner /></div>
  }

  const onSubmit = () => {
    if (!canSubmit) {
      toast.error('Revisa los campos marcados')
      return
    }
    const payload: SalidaCombustiblePayload = {
      estanque_id: estanqueId,
      litros: litrosNum,
      destino_tipo: destino,
      motivo: motivo.trim(),
      equipo_id: requiereEquipo ? equipoId : null,
      ot_id: requiereOT ? otId : null,
      ceco_id: requiereCECO ? cecoId : null,
      faena_id: requiereFaena ? faenaId : null,
      cliente_nombre: requiereCliente ? clienteNombre.trim() : null,
      fecha_movimiento: fecha ? `${fecha}T00:00:00Z` : null,
      observacion: observacion.trim() || null,
    }
    registrar.mutate(payload, {
      onSuccess: (data) => {
        toast.success(`Salida ${data.folio}: ${data.litros_salida} lt @ ${formatCLP(data.cpp_vigente)} = ${formatCLP(data.costo_total)}`)
        router.push('/dashboard/combustible')
      },
      onError: (err: unknown) => {
        const msg = err instanceof Error ? err.message : 'Error al registrar salida'
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
          <ArrowDownRight className="h-5 w-5 text-amber-700" />
          Salida valorizada de combustible
        </h1>
      </div>

      <div className="rounded-lg border border-blue-200 bg-blue-50 p-3 text-xs text-blue-900 flex items-start gap-2">
        <AlertCircle className="h-4 w-4 mt-0.5 shrink-0" />
        <div>
          La salida costea al <strong>CPP vigente</strong> del estanque y descuenta stock teórico.
          El CPP <strong>no cambia</strong> con las salidas (aritmética CPP móvil).
        </div>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Datos de la salida</CardTitle>
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
                    {e.codigo} — {e.nombre} (stock {Number(e.stock_teorico_lt).toFixed(0)} lt)
                  </option>
                ))}
              </select>
              {estanque && (
                <div className="text-[11px] text-gray-600 mt-1 flex flex-wrap gap-2">
                  <span>Stock: <strong>{stockActual.toFixed(2)} lt</strong></span>
                  <span>CPP: <strong>{formatCLP(cppVigente)}</strong></span>
                </div>
              )}
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">Litros *</label>
              <Input
                type="number" step="0.01" min="0.01"
                max={stockActual}
                value={litros}
                onChange={(e) => setLitros(e.target.value === '' ? '' : Number(e.target.value))}
                className={excedeStock ? 'border-red-500' : ''}
              />
              {litrosNum > 0 && estanque && (
                <div className="text-[11px] text-gray-600 mt-1">
                  Costo estimado: <strong className="font-mono">{formatCLP(costoSimulado)}</strong> ({litrosNum} × {formatCLP(cppVigente)})
                </div>
              )}
            </div>
          </div>

          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">Destino *</label>
            <div className="grid grid-cols-2 md:grid-cols-3 gap-2">
              {DESTINOS.map((d) => (
                <button
                  key={d.v}
                  type="button"
                  onClick={() => setDestino(d.v)}
                  className={`text-left rounded-md border px-3 py-2 text-xs transition ${
                    destino === d.v
                      ? 'border-amber-500 bg-amber-50 text-amber-900'
                      : 'border-gray-300 bg-white text-gray-700 hover:border-amber-400'
                  }`}
                >
                  <div className="font-semibold">{d.label}</div>
                  <div className="text-[10px] text-gray-500 mt-0.5">{d.hint}</div>
                </button>
              ))}
            </div>
          </div>

          {/* Selectores condicionales por destino */}
          {requiereEquipo && (
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">Equipo / vehículo *</label>
              <select
                value={equipoId}
                onChange={(e) => setEquipoId(e.target.value)}
                className="w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-sm"
              >
                <option value="">— Selecciona equipo —</option>
                {(activos ?? []).map((a) => (
                  <option key={a.id} value={a.id}>{a.codigo} — {a.nombre} {a.tipo ? `[${a.tipo}]` : ''}</option>
                ))}
              </select>
            </div>
          )}

          {requiereOT && (
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">Orden de Trabajo *</label>
              <select
                value={otId}
                onChange={(e) => setOtId(e.target.value)}
                className="w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-sm"
              >
                <option value="">— Selecciona OT —</option>
                {(ots ?? []).map((o) => (
                  <option key={o.id} value={o.id}>
                    {o.folio} · {o.tipo} · {o.estado} {o.faena_nombre ? `· ${o.faena_nombre}` : ''}
                  </option>
                ))}
              </select>
            </div>
          )}

          {requiereCECO && (
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">Centro de Costo *</label>
              <select
                value={cecoId}
                onChange={(e) => setCecoId(e.target.value)}
                className="w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-sm"
              >
                <option value="">— Selecciona CECO —</option>
                {(cecos ?? []).map((c) => (
                  <option key={c.id} value={c.id}>{c.codigo} — {c.nombre}</option>
                ))}
              </select>
            </div>
          )}

          {requiereFaena && (
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">Faena *</label>
              <select
                value={faenaId}
                onChange={(e) => setFaenaId(e.target.value)}
                className="w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-sm"
              >
                <option value="">— Selecciona faena —</option>
                {(faenas ?? []).map((f) => (
                  <option key={f.id} value={f.id}>{f.codigo ? `${f.codigo} — ` : ''}{f.nombre}</option>
                ))}
              </select>
            </div>
          )}

          {requiereCliente && (
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">Cliente / razón social *</label>
              <Input
                value={clienteNombre}
                onChange={(e) => setClienteNombre(e.target.value)}
                placeholder="Nombre del cliente externo"
              />
            </div>
          )}

          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">Motivo * (mín 5 chars)</label>
            <Input
              value={motivo}
              onChange={(e) => setMotivo(e.target.value)}
              placeholder="ej: Despacho a camioneta X faena Y"
            />
            <div className="flex gap-1 mt-1 flex-wrap">
              {['Despacho operacional', 'Consumo en OT', 'Mantenimiento', 'Reposición terreno'].map((m) => (
                <button
                  key={m}
                  type="button"
                  onClick={() => setMotivo(m)}
                  className="text-[10px] rounded bg-gray-100 hover:bg-gray-200 px-2 py-0.5"
                >{m}</button>
              ))}
            </div>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">Fecha</label>
              <Input type="date" value={fecha} onChange={(e) => setFecha(e.target.value)} />
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">Observación</label>
              <Input value={observacion} onChange={(e) => setObservacion(e.target.value)} placeholder="opcional" />
            </div>
          </div>

          {/* Preview impacto */}
          {estanque && litrosNum > 0 && !excedeStock && (
            <div className="rounded-lg border border-green-200 bg-green-50 p-3 text-xs text-green-900 space-y-1">
              <div className="font-semibold">Impacto simulado</div>
              <div className="flex flex-wrap gap-x-3 gap-y-1">
                <span>Stock {stockActual.toFixed(2)} → <strong>{(stockActual - litrosNum).toFixed(2)} lt</strong></span>
                <span>CPP <strong>{formatCLP(cppVigente)}</strong> (sin cambio)</span>
                <span>Costo salida: <strong className="font-mono">{formatCLP(costoSimulado)}</strong></span>
                <Badge className="bg-purple-100 text-purple-700">destino: {destino}</Badge>
              </div>
            </div>
          )}
        </CardContent>
      </Card>

      {errores.length > 0 && (estanqueId || litros !== '' || motivo.length > 0) && (
        <div className="rounded-lg border border-amber-200 bg-amber-50 p-2 text-xs text-amber-900">
          <ul className="list-disc list-inside">{errores.map((e, i) => <li key={i}>{e}</li>)}</ul>
        </div>
      )}

      <Card>
        <CardContent className="flex items-center justify-between py-4">
          <Button variant="outline" onClick={() => router.back()} disabled={registrar.isPending}>Cancelar</Button>
          <Button onClick={onSubmit} disabled={!canSubmit || registrar.isPending}>
            {registrar.isPending ? <Spinner className="h-4 w-4 mr-2" /> : <Save className="h-4 w-4 mr-2" />}
            {registrar.isPending ? 'Registrando...' : 'Registrar salida'}
          </Button>
        </CardContent>
      </Card>
    </div>
  )
}
