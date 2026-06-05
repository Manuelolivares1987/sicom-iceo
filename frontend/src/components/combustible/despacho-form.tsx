'use client'

import { useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'
import { ArrowLeft, Save, AlertCircle, ShieldCheck, Lock } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Badge } from '@/components/ui/badge'
import { Spinner } from '@/components/ui/spinner'
import { formatCLP, todayISO } from '@/lib/utils'
import { useToast } from '@/contexts/toast-context'
import {
  useEstanquesActivos, useFaenas, useActivos, useRegistrarDespachoConSellos,
} from '@/hooks/use-combustible-cpp'
import { useOTsValidasSalida, useCECO } from '@/hooks/use-bodega-salida-fifo'
import type {
  DespachoSellosPayload, DestinoSalidaCombustible,
} from '@/lib/services/combustible-cpp'
import {
  getVehiculosExternosAutorizados,
  type VehiculoExternoAutorizado,
} from '@/lib/services/combustible'
import {
  PhotoCaptureCombustible,
  type PhotoCaptureCombustibleResult,
} from './photo-capture-combustible'
import {
  EvidenciaDespachoBloque, EVIDENCIA_VACIA, evidenciaCompleta,
  type EvidenciaDespachoPayload,
} from './evidencia-despacho-bloque'

const DESTINOS: { v: DestinoSalidaCombustible; label: string }[] = [
  { v: 'equipo',          label: 'Equipo / vehículo' },
  { v: 'ot',              label: 'Orden de Trabajo' },
  { v: 'ceco',            label: 'Centro de Costo' },
  { v: 'faena',           label: 'Faena' },
  { v: 'consumo_interno', label: 'Consumo interno' },
  { v: 'venta_externa',   label: 'Venta externa' },
]

export function DespachoSellosForm() {
  const router = useRouter()
  const toast = useToast()
  const [estanqueId, setEstanqueId] = useState('')
  const [litros, setLitros] = useState<number | ''>('')
  const [destino, setDestino] = useState<DestinoSalidaCombustible>('equipo')
  const [equipoId, setEquipoId] = useState('')
  const [otId, setOtId] = useState('')
  const [cecoId, setCecoId] = useState('')
  const [faenaId, setFaenaId] = useState('')
  const [clienteNombre, setClienteNombre] = useState('')

  // Externo
  const [esExterno, setEsExterno] = useState(false)
  const [vehiculoExternoId, setVehiculoExternoId] = useState('')
  const [externos, setExternos] = useState<VehiculoExternoAutorizado[]>([])
  const [kilometraje, setKilometraje] = useState<number | ''>('')

  // Sellos antifraude
  const [selloInicial, setSelloInicial] = useState('')
  const [selloFinal, setSelloFinal] = useState('')
  const [fotoSelloIni, setFotoSelloIni] = useState<PhotoCaptureCombustibleResult | null>(null)
  const [fotoSelloFin, setFotoSelloFin] = useState<PhotoCaptureCombustibleResult | null>(null)
  const [fotoOdometro, setFotoOdometro] = useState<PhotoCaptureCombustibleResult | null>(null)
  const [fotoEquipo, setFotoEquipo] = useState<PhotoCaptureCombustibleResult | null>(null)

  // Evidencia del despacho (patente + 2 medidor + firma + receptor)
  const [evidencia, setEvidencia] = useState<EvidenciaDespachoPayload>(EVIDENCIA_VACIA)

  const [motivo, setMotivo] = useState('')
  const [observacion, setObservacion] = useState('')
  const [fecha, setFecha] = useState<string>(todayISO())

  const { data: estanques, isLoading: loadEst } = useEstanquesActivos()
  const { data: activos } = useActivos()
  const { data: ots } = useOTsValidasSalida()
  const { data: cecos } = useCECO()
  const { data: faenas } = useFaenas()
  const registrar = useRegistrarDespachoConSellos()

  useEffect(() => {
    if (destino === 'equipo') {
      getVehiculosExternosAutorizados().then(setExternos).catch(() => { /* skip */ })
    }
  }, [destino])

  useEffect(() => {
    if (destino !== 'equipo') {
      setEsExterno(false)
      setVehiculoExternoId('')
    }
  }, [destino])

  const estanque = estanques?.find((e) => e.id === estanqueId)
  const litrosNum = typeof litros === 'number' ? litros : 0
  const stockActual = estanque ? Number(estanque.stock_teorico_lt) : 0
  const cppVigente = estanque ? Number(estanque.costo_promedio_lt) : 0
  const costoEstimado = litrosNum * cppVigente
  const excedeStock = estanque && litrosNum > stockActual

  const errores: string[] = []
  if (!estanqueId) errores.push('Selecciona estanque.')
  if (litrosNum <= 0) errores.push('Litros debe ser > 0.')
  if (excedeStock) errores.push(`Stock insuficiente: solicitado ${litrosNum}, disponible ${stockActual.toFixed(2)}.`)
  if (motivo.trim().length < 5) errores.push('Motivo mínimo 5 caracteres.')
  if (selloInicial.trim().length === 0) errores.push('Sello inicial obligatorio.')
  if (selloFinal.trim().length === 0) errores.push('Sello final obligatorio.')
  if (!fotoSelloIni)  errores.push('Foto del sello INICIAL obligatoria.')
  if (!fotoSelloFin)  errores.push('Foto del sello FINAL obligatoria.')
  if (!fotoOdometro)  errores.push('Foto del odómetro/horómetro obligatoria.')
  if (!fotoEquipo)    errores.push('Foto del equipo obligatoria.')
  if (destino === 'equipo' && !esExterno && !equipoId) errores.push('Destino equipo: selecciona el activo.')
  if (destino === 'equipo' && esExterno && !vehiculoExternoId) errores.push('Vehículo externo: selecciona la patente autorizada.')
  if (esExterno && (typeof kilometraje !== 'number' || kilometraje < 0)) errores.push('Vehículo externo: kilometraje obligatorio.')
  if (destino === 'ot' && !otId) errores.push('Destino OT: selecciona la orden de trabajo.')
  if (destino === 'ceco' && !cecoId) errores.push('Destino CECO: selecciona el centro de costo.')
  if (destino === 'faena' && !faenaId) errores.push('Destino faena: selecciona la faena.')
  if (destino === 'venta_externa' && !clienteNombre.trim()) errores.push('Venta externa: nombre del cliente obligatorio.')
  if (destino !== 'consumo_interno' && !evidenciaCompleta(evidencia)) {
    errores.push('Completa la evidencia obligatoria: foto patente, fotos medidor inicio/fin, firma y datos del receptor.')
  }

  const canSubmit = errores.length === 0

  if (loadEst) {
    return <div className="flex justify-center py-10"><Spinner /></div>
  }

  const onSubmit = () => {
    if (!canSubmit) {
      toast.error('Revisa los campos marcados')
      return
    }
    const payload: DespachoSellosPayload = {
      estanque_id:           estanqueId,
      litros:                litrosNum,
      destino_tipo:          destino,
      sello_inicial:         selloInicial.trim(),
      sello_final:           selloFinal.trim(),
      motivo:                motivo.trim(),
      equipo_id:             destino === 'equipo' && !esExterno ? equipoId : null,
      ot_id:                 destino === 'ot' ? otId : null,
      ceco_id:               destino === 'ceco' ? cecoId : null,
      faena_id:              destino === 'faena' ? faenaId : null,
      cliente_nombre:        destino === 'venta_externa' ? clienteNombre.trim() : null,
      vehiculo_externo_id:   esExterno ? vehiculoExternoId : null,
      receptor_nombre:       evidencia.nombre_receptor.trim(),
      receptor_rut:          evidencia.rut_receptor.trim(),
      foto_sello_inicial_url: fotoSelloIni?.url ?? '',
      foto_sello_final_url:   fotoSelloFin?.url ?? '',
      foto_odometro_url:      fotoOdometro?.url ?? '',
      foto_equipo_url:        fotoEquipo?.url ?? '',
      foto_patente_url:         evidencia.foto_patente_url ?? '',
      foto_medidor_inicial_url: evidencia.foto_medidor_inicial_url ?? '',
      foto_medidor_final_url:   evidencia.foto_medidor_final_url ?? '',
      firma_receptor_url:       evidencia.firma_receptor_url ?? '',
      // Si es hoy, enviamos null para que el RPC use NOW() y quede la HORA real.
      // Si está retrofechada, se guarda como fecha-solo (sin hora inventada).
      fecha_movimiento:       !fecha || fecha === todayISO() ? null : `${fecha}T00:00:00Z`,
      observacion:            observacion.trim() || null,
      kilometraje_vehiculo:   esExterno && typeof kilometraje === 'number' ? kilometraje : null,
    }
    registrar.mutate(payload, {
      onSuccess: (data) => {
        toast.success(
          `Despacho ${data.folio_movimiento}: ${data.litros} lt @ ${formatCLP(data.cpp_usado)} = ${formatCLP(data.costo_total)} · sellos OK`,
        )
        router.push('/dashboard/combustible')
      },
      onError: (err: unknown) => {
        const msg = err instanceof Error ? err.message : 'Error al registrar despacho'
        toast.error(msg)
      },
    })
  }

  const contextoId = estanqueId || 'sin-estanque'

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-2">
        <Button variant="outline" size="sm" onClick={() => router.back()}>
          <ArrowLeft className="h-4 w-4 mr-1" /> Volver
        </Button>
        <h1 className="text-xl font-bold flex items-center gap-2">
          <ShieldCheck className="h-5 w-5 text-amber-700" />
          Despacho con sellos
        </h1>
      </div>

      <div className="rounded-lg border border-blue-200 bg-blue-50 p-3 text-xs text-blue-900 flex items-start gap-2">
        <AlertCircle className="h-4 w-4 mt-0.5 shrink-0" />
        <div>
          <strong>Trazabilidad antifraude.</strong> Todos los despachos (internos y externos) requieren foto
          de la patente, fotos del medidor antes/después, firma del receptor con nombre y RUT, además de los
          sellos del estanque.
        </div>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Datos del despacho</CardTitle>
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
                  Costo estimado: <strong className="font-mono">{formatCLP(costoEstimado)}</strong>
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
                      ? 'border-amber-500 bg-amber-50 text-amber-900 font-semibold'
                      : 'border-gray-300 bg-white text-gray-700 hover:border-amber-400'
                  }`}
                >{d.label}</button>
              ))}
            </div>
          </div>

          {destino === 'equipo' && (
            <div className="rounded-lg border border-amber-200 bg-amber-50/50 p-3 space-y-2">
              <label className="flex items-center gap-2 cursor-pointer">
                <input type="checkbox" checked={esExterno}
                       onChange={(e) => setEsExterno(e.target.checked)} />
                <span className="text-sm font-medium text-amber-900">
                  Vehículo EXTERNO autorizado (no es flota Pillado)
                </span>
              </label>
              {esExterno && (
                <div className="space-y-2">
                  <Selector
                    label="Patente autorizada *"
                    value={vehiculoExternoId}
                    onChange={setVehiculoExternoId}
                    opciones={externos.map((v) => ({ v: v.id, label: `${v.patente} · ${v.empresa}` }))}
                  />
                  <div>
                    <label className="block text-xs font-medium text-gray-700 mb-1">
                      Kilometraje del vehículo * (km)
                    </label>
                    <Input
                      type="number" step="1" min="0"
                      value={kilometraje}
                      onChange={(e) => setKilometraje(e.target.value === '' ? '' : Number(e.target.value))}
                      placeholder="ej: 123456"
                    />
                    <div className="text-[10px] text-amber-700 mt-1">
                      Obligatorio: permite calcular rendimiento (lt/km) del vehículo externo.
                    </div>
                  </div>
                </div>
              )}
            </div>
          )}

          {destino === 'equipo' && !esExterno && (
            <Selector
              label="Equipo de la flota *"
              value={equipoId}
              onChange={setEquipoId}
              opciones={(activos ?? []).map((a) => ({ v: a.id, label: `${a.codigo} — ${a.nombre} ${a.tipo ? `[${a.tipo}]` : ''}` }))}
            />
          )}
          {destino === 'ot' && (
            <Selector
              label="Orden de Trabajo *"
              value={otId}
              onChange={setOtId}
              opciones={(ots ?? []).map((o) => ({ v: o.id, label: `${o.folio} · ${o.tipo} · ${o.estado}` }))}
            />
          )}
          {destino === 'ceco' && (
            <Selector
              label="Centro de Costo *"
              value={cecoId}
              onChange={setCecoId}
              opciones={(cecos ?? []).map((c) => ({ v: c.id, label: `${c.codigo} — ${c.nombre}` }))}
            />
          )}
          {destino === 'faena' && (
            <Selector
              label="Faena *"
              value={faenaId}
              onChange={setFaenaId}
              opciones={(faenas ?? []).map((f) => ({ v: f.id, label: f.nombre }))}
            />
          )}
          {destino === 'venta_externa' && (
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">Cliente / razón social *</label>
              <Input value={clienteNombre} onChange={(e) => setClienteNombre(e.target.value)} placeholder="Nombre del cliente" />
            </div>
          )}

          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">Motivo * (mín 5)</label>
            <Input value={motivo} onChange={(e) => setMotivo(e.target.value)} placeholder="ej: Despacho a camioneta X faena Y" />
          </div>
        </CardContent>
      </Card>

      {/* Sellos antifraude — fotos REALES */}
      <Card className="border-amber-200">
        <CardHeader>
          <CardTitle className="text-base flex items-center gap-2">
            <Lock className="h-4 w-4 text-amber-700" />
            Sellos antifraude (obligatorios)
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">Sello inicial *</label>
              <Input value={selloInicial} onChange={(e) => setSelloInicial(e.target.value)} placeholder="ej: SLI-001234" />
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">Sello final *</label>
              <Input value={selloFinal} onChange={(e) => setSelloFinal(e.target.value)} placeholder="ej: SLF-001235" />
            </div>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
            <PhotoCaptureCombustible
              label="Foto sello INICIAL" tipo="sello_inicial"
              contextoId={contextoId} required
              initialUrl={fotoSelloIni?.url ?? null}
              onCapture={setFotoSelloIni}
            />
            <PhotoCaptureCombustible
              label="Foto sello FINAL" tipo="sello_final"
              contextoId={contextoId} required
              initialUrl={fotoSelloFin?.url ?? null}
              onCapture={setFotoSelloFin}
            />
            <PhotoCaptureCombustible
              label="Foto odómetro / horómetro" tipo="odometro"
              contextoId={contextoId} required
              initialUrl={fotoOdometro?.url ?? null}
              onCapture={setFotoOdometro}
            />
            <PhotoCaptureCombustible
              label="Foto del equipo" tipo="equipo"
              contextoId={contextoId} required
              initialUrl={fotoEquipo?.url ?? null}
              onCapture={setFotoEquipo}
            />
          </div>
        </CardContent>
      </Card>

      {/* Evidencia despacho: patente + 2 fotos medidor + firma + receptor */}
      {destino !== 'consumo_interno' && (
        <EvidenciaDespachoBloque
          value={evidencia}
          onChange={setEvidencia}
          contextoId={contextoId}
          labelReceptor="Receptor del combustible"
          rolReceptor="Receptor"
        />
      )}

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Fecha y observación</CardTitle>
        </CardHeader>
        <CardContent className="grid grid-cols-1 md:grid-cols-3 gap-3">
          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">Fecha</label>
            <Input type="date" value={fecha} onChange={(e) => setFecha(e.target.value)} />
          </div>
          <div className="md:col-span-2">
            <label className="block text-xs font-medium text-gray-700 mb-1">Observación</label>
            <Input value={observacion} onChange={(e) => setObservacion(e.target.value)} placeholder="opcional" />
          </div>
        </CardContent>
      </Card>

      {estanque && litrosNum > 0 && !excedeStock && (
        <div className="rounded-lg border border-green-200 bg-green-50 p-3 text-xs text-green-900 flex flex-wrap gap-x-3 gap-y-1">
          <strong>Preview:</strong>
          <span>Stock {stockActual.toFixed(2)} → <strong>{(stockActual - litrosNum).toFixed(2)} lt</strong></span>
          <span>CPP <strong>{formatCLP(cppVigente)}</strong> (no cambia)</span>
          <span>Costo: <strong>{formatCLP(costoEstimado)}</strong></span>
          <Badge className="bg-purple-100 text-purple-700">destino: {destino}</Badge>
        </div>
      )}

      {errores.length > 0 && (estanqueId || litros !== '' || motivo.length > 0 || selloInicial.length > 0) && (
        <div className="rounded-lg border border-amber-200 bg-amber-50 p-2 text-xs text-amber-900">
          <ul className="list-disc list-inside">{errores.map((e, i) => <li key={i}>{e}</li>)}</ul>
        </div>
      )}

      <Card>
        <CardContent className="flex items-center justify-between py-4">
          <Button variant="outline" onClick={() => router.back()} disabled={registrar.isPending}>Cancelar</Button>
          <Button onClick={onSubmit} disabled={!canSubmit || registrar.isPending}>
            {registrar.isPending ? <Spinner className="h-4 w-4 mr-2" /> : <Save className="h-4 w-4 mr-2" />}
            {registrar.isPending ? 'Registrando...' : 'Registrar despacho con sellos'}
          </Button>
        </CardContent>
      </Card>
    </div>
  )
}

function Selector({ label, value, onChange, opciones }: {
  label: string
  value: string
  onChange: (v: string) => void
  opciones: Array<{ v: string; label: string }>
}) {
  return (
    <div>
      <label className="block text-xs font-medium text-gray-700 mb-1">{label}</label>
      <select
        value={value}
        onChange={(e) => onChange(e.target.value)}
        className="w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-sm"
      >
        <option value="">— Selecciona —</option>
        {opciones.map((o) => <option key={o.v} value={o.v}>{o.label}</option>)}
      </select>
    </div>
  )
}
