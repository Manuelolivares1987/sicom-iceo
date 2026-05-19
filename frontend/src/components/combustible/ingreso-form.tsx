'use client'

import { useMemo, useState } from 'react'
import { useRouter } from 'next/navigation'
import {
  ArrowLeft, Save, AlertCircle, ArrowUpRight, Sparkles, Camera, Loader2, MapPin,
} from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Spinner } from '@/components/ui/spinner'
import { cn, formatCLP, todayISO } from '@/lib/utils'
import { useToast } from '@/contexts/toast-context'
import { useAuth } from '@/contexts/auth-context'
import {
  useEstanquesActivos, useProveedoresCombustible, useRegistrarIngresoCombustible,
} from '@/hooks/use-combustible-cpp'
import type { IngresoCombustiblePayload } from '@/lib/services/combustible-cpp'
import { uploadEvidenciaCombustible } from '@/lib/services/combustible'
import { capturarFotoConGeo, FotoGeoError } from '@/lib/services/foto-geo'

interface FotoSellada {
  url: string
  lat: number
  lon: number
  ts:  string
  accuracy: number
}

export function IngresoCombustibleForm() {
  const router = useRouter()
  const toast = useToast()
  const { user } = useAuth()

  const [estanqueId, setEstanqueId] = useState('')
  const [litros, setLitros]       = useState<number | ''>('')
  const [costo, setCosto]         = useState<number | ''>('')
  const [proveedorId, setProveedorId] = useState('')
  const [docTipo, setDocTipo]     = useState('factura')
  const [docNumero, setDocNumero] = useState('')
  const [fecha, setFecha]         = useState<string>(todayISO())
  const [observacion, setObservacion] = useState('')

  // MIG65 + MIG66
  const [fotoPatente, setFotoPatente] = useState<FotoSellada | null>(null)
  const [fotoInicial, setFotoInicial] = useState<FotoSellada | null>(null)
  const [fotoFinal, setFotoFinal]     = useState<FotoSellada | null>(null)
  const [uploadingPat, setUploadingPat] = useState(false)
  const [uploadingIni, setUploadingIni] = useState(false)
  const [uploadingFin, setUploadingFin] = useState(false)

  // MIG66: lecturas medidor estanque (opcional)
  const [lecturaIni, setLecturaIni] = useState<number | ''>('')
  const [lecturaFin, setLecturaFin] = useState<number | ''>('')

  const { data: estanques, isLoading: loadEst } = useEstanquesActivos()
  const { data: proveedores, isLoading: loadProv } = useProveedoresCombustible()
  const registrar = useRegistrarIngresoCombustible()

  const estanque = estanques?.find((e) => e.id === estanqueId)
  const litrosNum = typeof litros === 'number' ? litros : 0
  const costoNum = typeof costo === 'number' ? costo : 0
  const valorTotal = litrosNum * costoNum

  // Diferencia de medidor → propuesta de litros
  const diffMedidor = useMemo(() => {
    if (typeof lecturaIni !== 'number' || typeof lecturaFin !== 'number') return null
    const d = lecturaFin - lecturaIni
    return d > 0 ? Math.round(d * 100) / 100 : null
  }, [lecturaIni, lecturaFin])

  const desviacionLitros = useMemo(() => {
    if (diffMedidor == null || litrosNum <= 0) return null
    return Math.round(Math.abs(diffMedidor - litrosNum) * 100) / 100
  }, [diffMedidor, litrosNum])

  const desviacionFueraTolerancia =
    diffMedidor != null && desviacionLitros != null &&
    desviacionLitros > Math.max(litrosNum * 0.03, 1)

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
  if (!fotoPatente) errores.push('Foto de la PATENTE del camión proveedor obligatoria (con GPS activo).')
  if (!fotoInicial) errores.push('Foto del medidor ANTES obligatoria (con GPS activo).')
  if (!fotoFinal)   errores.push('Foto del medidor DESPUÉS obligatoria (con GPS activo).')
  const canSubmit = errores.length === 0

  if (loadEst || loadProv) {
    return <div className="flex justify-center py-10"><Spinner /></div>
  }

  async function handleFoto(file: File, tipo: 'patente' | 'inicial' | 'final') {
    if (!estanqueId) { toast.error('Selecciona el estanque primero.'); return }
    const setUp = tipo === 'patente' ? setUploadingPat : tipo === 'inicial' ? setUploadingIni : setUploadingFin
    setUp(true)
    try {
      // 1) Capturar geo + estampar overlay
      const sello = await capturarFotoConGeo(file, {
        usuarioEmail: user?.email ?? null,
        contexto: `Ingreso combustible · ${estanque?.codigo ?? ''} · ${tipo.toUpperCase()}`,
      })
      // 2) Subir el blob con overlay
      const sealedFile = new File([sello.blob], `${tipo}_${Date.now()}.jpg`, { type: 'image/jpeg' })
      const { url, error } = await uploadEvidenciaCombustible(sealedFile, { tipo: 'medidor', estanqueId })
      if (error || !url) throw error ?? new Error('No se pudo subir')

      const data: FotoSellada = { url, lat: sello.lat, lon: sello.lon, ts: sello.ts, accuracy: sello.accuracy }
      if (tipo === 'patente') setFotoPatente(data)
      else if (tipo === 'inicial') setFotoInicial(data)
      else setFotoFinal(data)
    } catch (e) {
      if (e instanceof FotoGeoError) {
        toast.error(`Foto ${tipo} bloqueada: ${e.message}`)
      } else {
        toast.error(`Foto ${tipo}: ${(e as Error).message}`)
      }
    } finally {
      setUp(false)
    }
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
      foto_patente_url:         fotoPatente!.url,
      foto_medidor_inicial_url: fotoInicial!.url,
      foto_medidor_final_url:   fotoFinal!.url,
      foto_patente_lat:           fotoPatente!.lat,
      foto_patente_lon:           fotoPatente!.lon,
      foto_patente_ts:            fotoPatente!.ts,
      foto_medidor_inicial_lat:   fotoInicial!.lat,
      foto_medidor_inicial_lon:   fotoInicial!.lon,
      foto_medidor_inicial_ts:    fotoInicial!.ts,
      foto_medidor_final_lat:     fotoFinal!.lat,
      foto_medidor_final_lon:     fotoFinal!.lon,
      foto_medidor_final_ts:      fotoFinal!.ts,
      lectura_medidor_inicial_lt: typeof lecturaIni === 'number' ? lecturaIni : null,
      lectura_medidor_final_lt:   typeof lecturaFin === 'number' ? lecturaFin : null,
    }
    registrar.mutate(payload, {
      onSuccess: (data) => {
        const w = (data as unknown as { warning_medidor?: string | null }).warning_medidor
        if (w) toast.info(`Aviso: ${w}`)
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
          <strong>CPP móvil + evidencia geo-verificada.</strong> Cada foto se firma con GPS, fecha y
          usuario antes de subirse (anti-reciclaje). Opcionalmente puedes anotar las lecturas del
          totalizador para validar que los litros declarados coinciden con la diferencia física.
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
              <label className="block text-xs font-medium text-gray-700 mb-1">Litros ingresados *</label>
              <Input
                type="number" step="0.01" min="0.01"
                value={litros}
                onChange={(e) => setLitros(e.target.value === '' ? '' : Number(e.target.value))}
                className={excedeCapacidad ? 'border-red-500' : ''}
                placeholder="ej: 2000"
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

          {/* MIG66: lecturas medidor opcionales */}
          <div className="rounded-lg border border-indigo-200 bg-indigo-50/50 p-3 space-y-2">
            <div className="text-xs font-semibold text-indigo-900">
              Lectura del totalizador del estanque (opcional, recomendado)
            </div>
            <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
              <div>
                <label className="block text-[11px] text-gray-700 mb-1">Lectura ANTES (lt)</label>
                <Input type="number" step="0.01" min="0" value={lecturaIni}
                       onChange={(e) => setLecturaIni(e.target.value === '' ? '' : Number(e.target.value))} />
              </div>
              <div>
                <label className="block text-[11px] text-gray-700 mb-1">Lectura DESPUÉS (lt)</label>
                <Input type="number" step="0.01" min="0" value={lecturaFin}
                       onChange={(e) => setLecturaFin(e.target.value === '' ? '' : Number(e.target.value))} />
              </div>
              <div>
                <label className="block text-[11px] text-gray-700 mb-1">Diferencia (propuesta)</label>
                <div className={cn(
                  'h-[42px] flex items-center px-3 rounded-md border text-sm tabular-nums font-semibold',
                  diffMedidor == null ? 'bg-gray-50 border-gray-200 text-gray-400'
                  : desviacionFueraTolerancia ? 'bg-amber-50 border-amber-300 text-amber-900'
                  : 'bg-green-50 border-green-300 text-green-900',
                )}>
                  {diffMedidor != null ? `${diffMedidor.toFixed(2)} lt` : '—'}
                </div>
              </div>
            </div>
            {diffMedidor != null && (
              <div className="text-[11px]">
                {desviacionFueraTolerancia ? (
                  <span className="text-amber-700">
                    Diferencia medidor ({diffMedidor.toFixed(2)} lt) difiere de litros declarados
                    ({litrosNum.toFixed(2)} lt) en {desviacionLitros?.toFixed(2)} lt (&gt; 3%). Revisa antes de guardar.
                  </span>
                ) : litrosNum > 0 ? (
                  <span className="text-green-700">
                    Diferencia coincide con litros declarados (±{desviacionLitros?.toFixed(2)} lt).
                  </span>
                ) : (
                  <button type="button" className="text-blue-700 underline"
                          onClick={() => setLitros(diffMedidor)}>
                    Usar {diffMedidor.toFixed(2)} lt como litros ingresados
                  </button>
                )}
              </div>
            )}
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
              </div>
            </div>
          )}
        </CardContent>
      </Card>

      {/* Evidencia visual obligatoria con geo */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base">
            Evidencia visual con GPS <span className="text-red-500">*</span>
          </CardTitle>
        </CardHeader>
        <CardContent>
          <p className="text-xs text-gray-500 mb-3">
            Cada foto se firma automáticamente con <b>fecha/hora del sistema + coordenadas GPS</b>.
            Si el dispositivo no entrega ubicación, la foto se rechaza.
          </p>
          <div className="grid gap-3 sm:grid-cols-3">
            <FotoSlot titulo="PATENTE CAMIÓN *" colorBadge="bg-purple-100 text-purple-700"
                      foto={fotoPatente} uploading={uploadingPat}
                      onClear={() => setFotoPatente(null)}
                      onFile={(f) => handleFoto(f, 'patente')} />
            <FotoSlot titulo="ANTES (medidor inicial) *" colorBadge="bg-blue-100 text-blue-700"
                      foto={fotoInicial} uploading={uploadingIni}
                      onClear={() => setFotoInicial(null)}
                      onFile={(f) => handleFoto(f, 'inicial')} />
            <FotoSlot titulo="DESPUÉS (medidor final) *" colorBadge="bg-green-100 text-green-700"
                      foto={fotoFinal} uploading={uploadingFin}
                      onClear={() => setFotoFinal(null)}
                      onFile={(f) => handleFoto(f, 'final')} />
          </div>
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

function FotoSlot({ titulo, colorBadge, foto, uploading, onClear, onFile }: {
  titulo: string; colorBadge: string; foto: FotoSellada | null; uploading: boolean
  onClear: () => void; onFile: (f: File) => void
}) {
  return (
    <div className="space-y-2">
      <div className={cn('inline-block rounded-full px-2 py-0.5 text-[10px] font-bold', colorBadge)}>
        {titulo}
      </div>
      {foto ? (
        <div className="space-y-2">
          <img src={foto.url} alt={titulo} className="h-40 w-full rounded-lg border object-cover" />
          <div className="text-[10px] text-gray-600 flex items-center gap-1">
            <MapPin className="h-3 w-3" />
            {foto.lat.toFixed(5)}, {foto.lon.toFixed(5)} (±{Math.round(foto.accuracy)}m) · {new Date(foto.ts).toLocaleString('es-CL', { hour12: false })}
          </div>
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
            {uploading ? 'Geolocalizando + subiendo…' : 'Tomar foto'}
          </span>
          <span className="text-[10px] text-gray-500">Requiere GPS activo</span>
          <input type="file" accept="image/*" capture="environment" className="hidden"
                 disabled={uploading}
                 onChange={(e) => { const f = e.target.files?.[0]; if (f) onFile(f) }} />
        </label>
      )}
    </div>
  )
}
