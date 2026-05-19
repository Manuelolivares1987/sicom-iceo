'use client'

import { useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'
import {
  ArrowLeft, Save, AlertCircle, ArrowDownRight, Camera, Loader2,
} from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Badge } from '@/components/ui/badge'
import { Spinner } from '@/components/ui/spinner'
import { SignaturePad } from '@/components/ui/signature-pad'
import { cn, formatCLP, todayISO } from '@/lib/utils'
import { useToast } from '@/contexts/toast-context'
import {
  useEstanquesActivos, useFaenas, useActivos, useRegistrarSalidaCombustible,
} from '@/hooks/use-combustible-cpp'
import { useOTsValidasSalida, useCECO } from '@/hooks/use-bodega-salida-fifo'
import type {
  SalidaCombustiblePayload, DestinoSalidaCombustible,
} from '@/lib/services/combustible-cpp'
import { uploadEvidenciaCombustible } from '@/lib/services/combustible'
import {
  getVehiculosExternosAutorizados,
  type VehiculoExternoAutorizado,
} from '@/lib/services/combustible'

const DESTINOS: { v: DestinoSalidaCombustible; label: string; hint: string }[] = [
  { v: 'equipo',          label: 'Equipo / vehículo', hint: 'Despacho a un activo del maestro o vehículo externo autorizado' },
  { v: 'ot',              label: 'Orden de Trabajo',  hint: 'Consumo asociado a una OT (estado asignada/en_ejecucion)' },
  { v: 'ceco',            label: 'Centro de Costo',   hint: 'Imputado a un CECO sin OT específica' },
  { v: 'faena',           label: 'Faena',             hint: 'Despacho global a una faena' },
  { v: 'consumo_interno', label: 'Consumo interno',   hint: 'Uso operativo sin destino externo' },
  { v: 'venta_externa',   label: 'Venta externa',     hint: 'Cliente externo identificado por nombre' },
]

function dataUrlToBlob(dataUrl: string): Blob {
  const base64 = dataUrl.split(',')[1] ?? ''
  const bin = atob(base64)
  const buf = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i)
  return new Blob([buf], { type: 'image/png' })
}

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

  // MIG64: externos + fotos + receptor
  const [esExterno, setEsExterno]           = useState(false)
  const [vehiculoExternoId, setVehiculoExternoId] = useState('')
  const [externos, setExternos]             = useState<VehiculoExternoAutorizado[]>([])
  const [fotoInicial, setFotoInicial]       = useState<string | null>(null)
  const [fotoFinal, setFotoFinal]           = useState<string | null>(null)
  const [fotoPatente, setFotoPatente]       = useState<string | null>(null)
  const [nombreReceptor, setNombreReceptor] = useState('')
  const [rutReceptor, setRutReceptor]       = useState('')
  const [firmaDataUrl, setFirmaDataUrl]     = useState<string | null>(null)
  const [uploadingIni, setUploadingIni]     = useState(false)
  const [uploadingFin, setUploadingFin]     = useState(false)
  const [uploadingPat, setUploadingPat]     = useState(false)
  const [submitting, setSubmitting]         = useState(false)

  const { data: estanques, isLoading: loadEst } = useEstanquesActivos()
  const { data: activos } = useActivos()
  const { data: ots } = useOTsValidasSalida()
  const { data: cecos } = useCECO()
  const { data: faenas } = useFaenas()
  const registrar = useRegistrarSalidaCombustible()

  useEffect(() => {
    if (destino === 'equipo') {
      getVehiculosExternosAutorizados().then(setExternos).catch(() => { /* skip */ })
    }
  }, [destino])

  // Si cambian destino a algo distinto de equipo, limpiar externo
  useEffect(() => {
    if (destino !== 'equipo') setEsExterno(false)
  }, [destino])

  const estanque = estanques?.find((e) => e.id === estanqueId)
  const litrosNum = typeof litros === 'number' ? litros : 0
  const stockActual = estanque ? Number(estanque.stock_teorico_lt) : 0
  const cppVigente = estanque ? Number(estanque.costo_promedio_lt) : 0
  const costoSimulado = litrosNum * cppVigente
  const excedeStock = estanque && litrosNum > stockActual

  const requiereEquipo  = destino === 'equipo'
  const requiereOT      = destino === 'ot'
  const requiereCECO    = destino === 'ceco'
  const requiereFaena   = destino === 'faena'
  const requiereCliente = destino === 'venta_externa'

  const requiereFotos = destino === 'equipo'  // a equipo (flota o externo) -> 2 fotos medidor

  const errores: string[] = []
  if (!estanqueId) errores.push('Selecciona estanque.')
  if (litrosNum <= 0) errores.push('Litros debe ser > 0.')
  if (excedeStock) errores.push(`Stock insuficiente: solicitado ${litrosNum} lt, disponible ${stockActual.toFixed(2)} lt.`)
  if (motivo.trim().length < 5) errores.push('Motivo mínimo 5 caracteres.')
  if (requiereEquipo && !esExterno && !equipoId) errores.push('Destino equipo: selecciona el activo de la flota.')
  if (requiereEquipo && esExterno && !vehiculoExternoId) errores.push('Vehiculo externo: selecciona la patente autorizada.')
  if (requiereOT && !otId) errores.push('Destino OT: selecciona la orden de trabajo.')
  if (requiereCECO && !cecoId) errores.push('Destino CECO: selecciona el centro de costo.')
  if (requiereFaena && !faenaId) errores.push('Destino faena: selecciona la faena.')
  if (requiereCliente && !clienteNombre.trim()) errores.push('Venta externa: nombre del cliente obligatorio.')

  if (requiereFotos && !fotoInicial) errores.push('Foto del medidor ANTES (inicial) obligatoria.')
  if (requiereFotos && !fotoFinal) errores.push('Foto del medidor DESPUES (final) obligatoria.')
  if (esExterno && !fotoPatente)   errores.push('Foto de la PATENTE obligatoria para vehículo externo.')
  if (esExterno && !firmaDataUrl)  errores.push('Firma del RECEPTOR obligatoria para vehículo externo.')
  if (esExterno && !nombreReceptor.trim()) errores.push('Nombre del receptor obligatorio para vehículo externo.')

  const canSubmit = errores.length === 0 && !submitting

  if (loadEst) {
    return <div className="flex justify-center py-10"><Spinner /></div>
  }

  async function handleFoto(file: File, tipo: 'inicial' | 'final' | 'patente') {
    if (!estanqueId) { toast.error('Selecciona el estanque primero.'); return }
    const setUp = tipo === 'inicial' ? setUploadingIni : tipo === 'final' ? setUploadingFin : setUploadingPat
    setUp(true)
    try {
      const { url, error } = await uploadEvidenciaCombustible(file, { tipo: 'medidor', estanqueId })
      if (error || !url) throw error ?? new Error('No se pudo subir')
      if (tipo === 'inicial') setFotoInicial(url)
      else if (tipo === 'final') setFotoFinal(url)
      else setFotoPatente(url)
    } catch (e) {
      toast.error(`Foto ${tipo}: ${(e as Error).message}`)
    } finally {
      setUp(false)
    }
  }

  async function subirFirma(): Promise<string | null> {
    if (!firmaDataUrl || !estanqueId) return null
    const blob = dataUrlToBlob(firmaDataUrl)
    const file = new File([blob], `firma_${Date.now()}.png`, { type: 'image/png' })
    const { url, error } = await uploadEvidenciaCombustible(file, { tipo: 'medidor', estanqueId })
    if (error) throw error
    return url
  }

  const onSubmit = async () => {
    if (!canSubmit) {
      toast.error('Revisa los campos marcados')
      return
    }
    setSubmitting(true)
    try {
      // Subir firma si la hay
      let firmaUrl: string | null = null
      if (firmaDataUrl) {
        try { firmaUrl = await subirFirma() }
        catch (e) { toast.error(`Firma: ${(e as Error).message}`); setSubmitting(false); return }
      }

      const payload: SalidaCombustiblePayload = {
        estanque_id: estanqueId,
        litros: litrosNum,
        destino_tipo: destino,
        motivo: motivo.trim(),
        equipo_id: requiereEquipo && !esExterno ? equipoId : null,
        ot_id: requiereOT ? otId : null,
        ceco_id: requiereCECO ? cecoId : null,
        faena_id: requiereFaena ? faenaId : null,
        cliente_nombre: requiereCliente ? clienteNombre.trim() : null,
        fecha_movimiento: fecha ? `${fecha}T00:00:00Z` : null,
        observacion: observacion.trim() || null,
        // MIG64
        vehiculo_externo_id: esExterno ? vehiculoExternoId : null,
        foto_medidor_inicial_url: fotoInicial,
        foto_medidor_final_url:   fotoFinal,
        foto_patente_url:         fotoPatente,
        firma_receptor_url:       firmaUrl,
        nombre_receptor:          nombreReceptor.trim() || null,
        rut_receptor:             rutReceptor.trim() || null,
      }

      registrar.mutate(payload, {
        onSuccess: (data) => {
          toast.success(`Salida ${data.folio}: ${data.litros_salida} lt @ ${formatCLP(data.cpp_vigente)} = ${formatCLP(data.costo_total)}`)
          router.push('/dashboard/combustible')
        },
        onError: (err: unknown) => {
          const msg = err instanceof Error ? err.message : 'Error al registrar salida'
          toast.error(msg)
          setSubmitting(false)
        },
        onSettled: () => setSubmitting(false),
      })
    } catch (e) {
      toast.error((e as Error).message)
      setSubmitting(false)
    }
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
          Las salidas a equipos requieren <strong>2 fotos del medidor</strong>. Los despachos a
          vehículos externos autorizados (LISSET LOPEZ G, MYG, etc.) también requieren <strong>foto de la patente + firma del receptor</strong>.
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
              <select value={estanqueId} onChange={(e) => setEstanqueId(e.target.value)}
                      className="w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-sm">
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
              <Input type="number" step="0.01" min="0.01" max={stockActual}
                     value={litros}
                     onChange={(e) => setLitros(e.target.value === '' ? '' : Number(e.target.value))}
                     className={excedeStock ? 'border-red-500' : ''} />
              {litrosNum > 0 && estanque && (
                <div className="text-[11px] text-gray-600 mt-1">
                  Costo estimado: <strong className="font-mono">{formatCLP(costoSimulado)}</strong>
                </div>
              )}
            </div>
          </div>

          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">Destino *</label>
            <div className="grid grid-cols-2 md:grid-cols-3 gap-2">
              {DESTINOS.map((d) => (
                <button key={d.v} type="button" onClick={() => setDestino(d.v)}
                        className={`text-left rounded-md border px-3 py-2 text-xs transition ${
                          destino === d.v
                            ? 'border-amber-500 bg-amber-50 text-amber-900'
                            : 'border-gray-300 bg-white text-gray-700 hover:border-amber-400'
                        }`}>
                  <div className="font-semibold">{d.label}</div>
                  <div className="text-[10px] text-gray-500 mt-0.5">{d.hint}</div>
                </button>
              ))}
            </div>
          </div>

          {/* Toggle externo (solo si destino=equipo) */}
          {requiereEquipo && (
            <div className="rounded-lg border border-amber-200 bg-amber-50/50 p-3">
              <label className="flex items-center gap-2 cursor-pointer">
                <input type="checkbox" checked={esExterno}
                       onChange={(e) => setEsExterno(e.target.checked)} />
                <span className="text-sm font-medium text-amber-900">
                  Vehiculo EXTERNO autorizado (no es flota Pillado)
                </span>
                <span className="ml-auto text-[10px] text-amber-700">
                  {esExterno ? 'Requiere foto patente + firma receptor' : ''}
                </span>
              </label>
            </div>
          )}

          {requiereEquipo && esExterno && (
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">Vehiculo externo autorizado *</label>
              <select value={vehiculoExternoId} onChange={(e) => setVehiculoExternoId(e.target.value)}
                      className="w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-sm">
                <option value="">— Selecciona patente —</option>
                {externos.map((v) => (
                  <option key={v.id} value={v.id}>{v.patente} · {v.empresa}</option>
                ))}
              </select>
            </div>
          )}

          {requiereEquipo && !esExterno && (
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">Equipo de la flota *</label>
              <select value={equipoId} onChange={(e) => setEquipoId(e.target.value)}
                      className="w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-sm">
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
              <select value={otId} onChange={(e) => setOtId(e.target.value)}
                      className="w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-sm">
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
              <select value={cecoId} onChange={(e) => setCecoId(e.target.value)}
                      className="w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-sm">
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
              <select value={faenaId} onChange={(e) => setFaenaId(e.target.value)}
                      className="w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-sm">
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
              <Input value={clienteNombre} onChange={(e) => setClienteNombre(e.target.value)}
                     placeholder="Nombre del cliente externo" />
            </div>
          )}

          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">Motivo * (mín 5 chars)</label>
            <Input value={motivo} onChange={(e) => setMotivo(e.target.value)}
                   placeholder="ej: Despacho a camioneta X faena Y" />
            <div className="flex gap-1 mt-1 flex-wrap">
              {['Despacho operacional', 'Consumo en OT', 'Mantenimiento', 'Reposición terreno'].map((m) => (
                <button key={m} type="button" onClick={() => setMotivo(m)}
                        className="text-[10px] rounded bg-gray-100 hover:bg-gray-200 px-2 py-0.5">{m}</button>
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

      {/* Fotos del medidor (cuando destino es equipo o externo) */}
      {requiereFotos && (
        <Card>
          <CardHeader>
            <CardTitle className="text-base">Fotos del medidor <span className="text-red-500">*</span></CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-xs text-gray-500 mb-3">
              Captura el totalizador <b>ANTES</b> y <b>DESPUÉS</b> del despacho. La diferencia
              entre ambas lecturas valida los litros entregados.
            </p>
            <div className="grid gap-3 sm:grid-cols-2">
              <FotoSlot titulo="ANTES (medidor inicial)" colorBadge="bg-blue-100 text-blue-700"
                        fotoUrl={fotoInicial} uploading={uploadingIni}
                        onClear={() => setFotoInicial(null)}
                        onFile={(f) => handleFoto(f, 'inicial')} />
              <FotoSlot titulo="DESPUÉS (medidor final)" colorBadge="bg-green-100 text-green-700"
                        fotoUrl={fotoFinal} uploading={uploadingFin}
                        onClear={() => setFotoFinal(null)}
                        onFile={(f) => handleFoto(f, 'final')} />
            </div>
          </CardContent>
        </Card>
      )}

      {/* Receptor (cuando es externo) */}
      {esExterno && (
        <Card>
          <CardHeader>
            <CardTitle className="text-base">Receptor <span className="text-red-500">*</span></CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            <p className="text-xs text-gray-500">
              Vehículo externo: foto de la patente + firma del receptor obligatorios para defender el cobro.
            </p>
            <div className="grid gap-3 sm:grid-cols-2">
              <FotoSlot titulo="FOTO PATENTE *" colorBadge="bg-purple-100 text-purple-700"
                        fotoUrl={fotoPatente} uploading={uploadingPat}
                        onClear={() => setFotoPatente(null)}
                        onFile={(f) => handleFoto(f, 'patente')} />
              <div className="space-y-2">
                <div className="inline-block rounded-full bg-indigo-100 px-2 py-0.5 text-[10px] font-bold text-indigo-700">
                  DATOS RECEPTOR *
                </div>
                <Input placeholder="Nombre del receptor *" value={nombreReceptor}
                       onChange={(e) => setNombreReceptor(e.target.value)} />
                <Input placeholder="RUT (opcional)" value={rutReceptor}
                       onChange={(e) => setRutReceptor(e.target.value)} />
              </div>
            </div>
            <div>
              <div className="inline-block rounded-full bg-emerald-100 px-2 py-0.5 text-[10px] font-bold text-emerald-700">
                FIRMA RECEPTOR *
              </div>
              <div className="mt-1 rounded border bg-white p-1">
                <SignaturePad label="Firma" onCapture={(d) => setFirmaDataUrl(d)} existingUrl={firmaDataUrl} />
              </div>
            </div>
          </CardContent>
        </Card>
      )}

      {errores.length > 0 && (estanqueId || litros !== '' || motivo.length > 0) && (
        <div className="rounded-lg border border-amber-200 bg-amber-50 p-2 text-xs text-amber-900">
          <ul className="list-disc list-inside">{errores.map((e, i) => <li key={i}>{e}</li>)}</ul>
        </div>
      )}

      <Card>
        <CardContent className="flex items-center justify-between py-4">
          <Button variant="outline" onClick={() => router.back()} disabled={submitting}>Cancelar</Button>
          <Button onClick={onSubmit} disabled={!canSubmit}>
            {submitting ? <Spinner className="h-4 w-4 mr-2" /> : <Save className="h-4 w-4 mr-2" />}
            {submitting ? 'Registrando...' : 'Registrar salida'}
          </Button>
        </CardContent>
      </Card>
    </div>
  )
}

function FotoSlot({ titulo, colorBadge, fotoUrl, uploading, onClear, onFile }: {
  titulo: string; colorBadge: string; fotoUrl: string | null; uploading: boolean
  onClear: () => void; onFile: (f: File) => void
}) {
  return (
    <div className="space-y-2">
      <div className={cn('inline-block rounded-full px-2 py-0.5 text-[10px] font-bold', colorBadge)}>
        {titulo}
      </div>
      {fotoUrl ? (
        <div className="space-y-2">
          <img src={fotoUrl} alt={titulo} className="h-40 w-full rounded-lg border object-cover" />
          <Button variant="outline" size="sm" className="w-full" onClick={onClear}>Cambiar foto</Button>
        </div>
      ) : (
        <label className={cn(
          'flex h-40 cursor-pointer flex-col items-center justify-center gap-1 rounded-lg border-2 border-dashed border-gray-300 p-3 text-center hover:border-gray-400',
          uploading && 'opacity-60'
        )}>
          {uploading
            ? <Loader2 className="h-7 w-7 animate-spin text-gray-400" />
            : <Camera className="h-7 w-7 text-gray-400" />}
          <span className="text-xs font-medium text-gray-700">
            {uploading ? 'Subiendo…' : 'Tomar foto'}
          </span>
          <input type="file" accept="image/*" capture="environment" className="hidden"
                 disabled={uploading}
                 onChange={(e) => { const f = e.target.files?.[0]; if (f) onFile(f) }} />
        </label>
      )}
    </div>
  )
}
