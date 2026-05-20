'use client'

import { useMemo, useState } from 'react'
import { useRouter } from 'next/navigation'
import {
  ArrowLeft, Save, Scale, Sparkles, ShieldAlert, Camera, Loader2, MapPin,
} from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Spinner } from '@/components/ui/spinner'
import { formatCLP, todayISO, cn, errorMessage } from '@/lib/utils'
import { useToast } from '@/contexts/toast-context'
import { useAuth } from '@/contexts/auth-context'
import {
  useEstanquesActivos, useAjustarStockEstanque,
} from '@/hooks/use-combustible-cpp'
import type { AjustarStockEstanquePayload } from '@/lib/services/combustible-cpp'
import { uploadEvidenciaCombustible } from '@/lib/services/combustible'
import { capturarFotoConGeo, FotoGeoError } from '@/lib/services/foto-geo'

interface FotoSellada {
  url: string
  lat: number
  lon: number
  ts:  string
  accuracy: number
}

export default function AjusteStockEstanquePage() {
  const router = useRouter()
  const toast = useToast()
  const { user } = useAuth()

  const [estanqueId, setEstanqueId]       = useState('')
  const [litrosCorrectos, setLitros]      = useState<number | ''>('')
  const [motivo, setMotivo]               = useState('')
  const [evidenciaUrl, setEvidenciaUrl]   = useState('')
  const [fecha, setFecha]                 = useState<string>(todayISO())
  const [tambienCPP, setTambienCPP]       = useState(false)
  const [nuevoCPP, setNuevoCPP]           = useState<number | ''>('')
  const [foto, setFoto]                   = useState<FotoSellada | null>(null)
  const [uploadingFoto, setUploadingFoto] = useState(false)

  const { data: estanques, isLoading: loadEst } = useEstanquesActivos()
  const ajustar = useAjustarStockEstanque()

  const estanque = estanques?.find((e) => e.id === estanqueId)
  const stockActual = estanque ? Number(estanque.stock_teorico_lt) : 0
  const cppActual   = estanque ? Number(estanque.costo_promedio_lt) : 0
  const capacidad   = estanque ? Number(estanque.capacidad_lt) : 0

  const litrosNum = typeof litrosCorrectos === 'number' ? litrosCorrectos : 0
  const cppNum    = typeof nuevoCPP === 'number' ? nuevoCPP : null

  const delta = useMemo(() => {
    if (!estanque || litrosCorrectos === '') return null
    return Math.round((litrosNum - stockActual) * 100) / 100
  }, [estanque, litrosCorrectos, litrosNum, stockActual])

  const valorAnterior = stockActual * cppActual
  const cppUsar = tambienCPP && cppNum != null ? cppNum : cppActual
  const valorNuevo = litrosNum * cppUsar

  const errores: string[] = []
  if (!estanqueId) errores.push('Selecciona estanque.')
  if (litrosCorrectos === '' || litrosNum < 0) errores.push('Litros correctos debe ser >= 0.')
  if (estanque && litrosNum > capacidad) errores.push(`Excede capacidad del estanque (${capacidad} lt).`)
  if (motivo.trim().length < 10) errores.push('Motivo obligatorio (mínimo 10 caracteres).')
  if (tambienCPP && (nuevoCPP === '' || (cppNum != null && cppNum < 0))) {
    errores.push('Nuevo CPP debe ser >= 0.')
  }
  if (!foto) errores.push('Foto del varillaje/medidor obligatoria (con GPS activo).')
  const canSubmit = errores.length === 0

  async function handleFoto(file: File) {
    if (!estanqueId) { toast.error('Selecciona el estanque primero.'); return }
    setUploadingFoto(true)
    try {
      const sello = await capturarFotoConGeo(file, {
        usuarioEmail: user?.email ?? null,
        contexto: `Ajuste stock · ${estanque?.codigo ?? ''}`,
      })
      const sealedFile = new File([sello.blob], `ajuste_${Date.now()}.jpg`, { type: 'image/jpeg' })
      const { url, error } = await uploadEvidenciaCombustible(sealedFile, { tipo: 'medidor', estanqueId })
      if (error || !url) throw error ?? new Error('No se pudo subir')
      setFoto({ url, lat: sello.lat, lon: sello.lon, ts: sello.ts, accuracy: sello.accuracy })
    } catch (e) {
      if (e instanceof FotoGeoError) toast.error(`Foto bloqueada: ${e.message}`)
      else toast.error(`Foto: ${(e as Error).message}`)
    } finally {
      setUploadingFoto(false)
    }
  }

  const onSubmit = () => {
    if (!canSubmit) { toast.error('Revisa los campos marcados'); return }

    const payload: AjustarStockEstanquePayload = {
      estanque_id:      estanqueId,
      litros_correctos: litrosNum,
      motivo:           motivo.trim(),
      foto_url:         foto!.url,
      foto_lat:         foto!.lat,
      foto_lon:         foto!.lon,
      foto_ts:          foto!.ts,
      evidencia_url:    evidenciaUrl.trim() || null,
      fecha_movimiento: fecha ? `${fecha}T00:00:00Z` : null,
      nuevo_cpp:        tambienCPP && cppNum != null ? cppNum : null,
    }

    ajustar.mutate(payload, {
      onSuccess: (res) => {
        if (res.sin_cambios) {
          toast.info(res.mensaje ?? 'No hubo cambios.')
        } else {
          const deltaStr = (res.delta ?? 0) >= 0 ? `+${res.delta}` : `${res.delta}`
          toast.success(
            `Ajuste ${res.folio}: ${res.estanque_codigo} ${res.stock_anterior}→${res.stock_nuevo} lt (${deltaStr} lt)`,
          )
          router.push('/dashboard/combustible/control')
        }
      },
      onError: (err: unknown) => {
        toast.error(errorMessage(err, 'Error al ajustar stock'))
      },
    })
  }

  if (loadEst) {
    return <div className="flex justify-center py-10"><Spinner /></div>
  }

  return (
    <div className="p-4 sm:p-6 max-w-3xl mx-auto space-y-4">
      <div className="flex items-center gap-2">
        <Button variant="outline" size="sm" onClick={() => router.back()}>
          <ArrowLeft className="h-4 w-4 mr-1" /> Volver
        </Button>
        <h1 className="text-xl font-bold flex items-center gap-2">
          <Scale className="h-5 w-5 text-purple-700" />
          Ajuste de stock físico
        </h1>
      </div>

      <div className="rounded-lg border border-purple-200 bg-purple-50 p-3 text-xs text-purple-900 flex items-start gap-2">
        <ShieldAlert className="h-4 w-4 mt-0.5 shrink-0" />
        <div>
          Ajusta el <strong>stock físico real</strong> de un estanque (corrige diferencias por varillaje,
          stock inicial mal cargado, evaporación, etc). Requiere <strong>foto del varillaje con GPS</strong> +
          motivo (mín 10 chars). Solo administrador, subgerente o jefe de mantenimiento.
        </div>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Datos del ajuste</CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
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
                  {e.codigo} — {e.nombre} (stock {Number(e.stock_teorico_lt).toFixed(2)} lt / {e.capacidad_lt} lt)
                </option>
              ))}
            </select>
          </div>

          {estanque && (
            <div className="rounded-lg border border-gray-200 bg-gray-50 p-3 grid grid-cols-3 gap-2 text-xs">
              <div>
                <div className="text-gray-500 uppercase text-[10px]">Stock actual</div>
                <div className="font-mono font-semibold text-base">{stockActual.toFixed(2)} lt</div>
              </div>
              <div>
                <div className="text-gray-500 uppercase text-[10px]">CPP actual</div>
                <div className="font-mono font-semibold">{formatCLP(cppActual)}</div>
              </div>
              <div>
                <div className="text-gray-500 uppercase text-[10px]">Valor actual</div>
                <div className="font-mono font-semibold">{formatCLP(valorAnterior)}</div>
              </div>
            </div>
          )}

          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">Litros correctos *</label>
              <Input
                type="number" step="0.01" min="0" max={capacidad || undefined}
                value={litrosCorrectos}
                onChange={(e) => setLitros(e.target.value === '' ? '' : Number(e.target.value))}
                placeholder="ej: 850.50"
              />
              <p className="text-[10px] text-gray-500 mt-1">
                Valor REAL del estanque (medición física actual). El sistema calcula la diferencia.
              </p>
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">Fecha del ajuste</label>
              <Input type="date" value={fecha} onChange={(e) => setFecha(e.target.value)} />
            </div>
          </div>

          {delta != null && estanque && (
            <div className={cn(
              'rounded-lg border p-3 text-xs space-y-1',
              delta > 0 ? 'border-green-200 bg-green-50 text-green-900'
              : delta < 0 ? 'border-amber-200 bg-amber-50 text-amber-900'
              : 'border-gray-200 bg-gray-50 text-gray-700',
            )}>
              <div className="font-semibold flex items-center gap-1">
                <Sparkles className="h-3 w-3" />
                Impacto del ajuste
              </div>
              <div className="flex flex-wrap gap-x-3 gap-y-1 font-mono">
                <span>Stock: <strong>{stockActual.toFixed(2)} → {litrosNum.toFixed(2)} lt</strong></span>
                <span>Δ: <strong>{delta >= 0 ? '+' : ''}{delta.toFixed(2)} lt</strong></span>
                <span>Valor: <strong>{formatCLP(valorAnterior)} → {formatCLP(valorNuevo)}</strong></span>
              </div>
            </div>
          )}

          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">
              Motivo del ajuste * (mínimo 10 caracteres)
            </label>
            <textarea
              value={motivo}
              onChange={(e) => setMotivo(e.target.value)}
              className="w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-sm min-h-[70px]"
              placeholder="ej: Stock inicial mal cargado por error de captura. Varillaje físico entrega 850.5 lt."
            />
            <div className="text-[10px] text-gray-500 mt-1">{motivo.length} / mín 10</div>
          </div>

          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">URL evidencia extra (opcional)</label>
            <Input
              value={evidenciaUrl}
              onChange={(e) => setEvidenciaUrl(e.target.value)}
              placeholder="https://... (acta firmada, otro documento)"
            />
          </div>

          <div className="rounded-lg border border-amber-200 bg-amber-50/50 p-3">
            <label className="flex items-center gap-2 cursor-pointer">
              <input type="checkbox" checked={tambienCPP}
                     onChange={(e) => setTambienCPP(e.target.checked)} />
              <span className="text-sm font-medium text-amber-900">
                Corregir también el CPP (costo promedio)
              </span>
            </label>
            {tambienCPP && (
              <div className="mt-2">
                <label className="block text-xs font-medium text-gray-700 mb-1">Nuevo CPP CLP/lt</label>
                <Input
                  type="number" step="0.01" min="0"
                  value={nuevoCPP}
                  onChange={(e) => setNuevoCPP(e.target.value === '' ? '' : Number(e.target.value))}
                  placeholder={`actual: ${cppActual.toFixed(4)}`}
                />
                <p className="text-[10px] text-gray-500 mt-1">
                  Solo úsalo si Finanzas validó un costo distinto al actual.
                </p>
              </div>
            )}
          </div>
        </CardContent>
      </Card>

      {/* Foto obligatoria con geo */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base">
            Foto del varillaje / medidor con GPS <span className="text-red-500">*</span>
          </CardTitle>
        </CardHeader>
        <CardContent>
          <p className="text-xs text-gray-500 mb-3">
            Captura el varillaje físico que justifica el ajuste. La foto se firma con
            <b> fecha/hora del sistema + coordenadas GPS</b>. Si el dispositivo no entrega
            ubicación, la foto se rechaza.
          </p>
          <div className="max-w-xs">
            <FotoSlot foto={foto} uploading={uploadingFoto}
                      onClear={() => setFoto(null)}
                      onFile={handleFoto} />
          </div>
        </CardContent>
      </Card>

      {errores.length > 0 && (estanqueId || litrosCorrectos !== '' || motivo.length > 0) && (
        <div className="rounded-lg border border-amber-200 bg-amber-50 p-2 text-xs text-amber-900">
          <ul className="list-disc list-inside">{errores.map((e, i) => <li key={i}>{e}</li>)}</ul>
        </div>
      )}

      <Card>
        <CardContent className="flex items-center justify-between py-4">
          <Button variant="outline" onClick={() => router.back()} disabled={ajustar.isPending}>
            Cancelar
          </Button>
          <Button onClick={onSubmit} disabled={!canSubmit || ajustar.isPending}
                  className="bg-purple-600 hover:bg-purple-700">
            {ajustar.isPending ? <Spinner className="h-4 w-4 mr-2" /> : <Save className="h-4 w-4 mr-2" />}
            {ajustar.isPending ? 'Ajustando...' : 'Aplicar ajuste'}
          </Button>
        </CardContent>
      </Card>
    </div>
  )
}

function FotoSlot({ foto, uploading, onClear, onFile }: {
  foto: FotoSellada | null; uploading: boolean
  onClear: () => void; onFile: (f: File) => void
}) {
  return (
    <div className="space-y-2">
      <div className="inline-block rounded-full bg-purple-100 px-2 py-0.5 text-[10px] font-bold text-purple-700">
        VARILLAJE / MEDIDOR *
      </div>
      {foto ? (
        <div className="space-y-2">
          <img src={foto.url} alt="Varillaje" className="h-44 w-full rounded-lg border object-cover" />
          <div className="text-[10px] text-gray-600 flex items-center gap-1">
            <MapPin className="h-3 w-3" />
            {foto.lat.toFixed(5)}, {foto.lon.toFixed(5)} (±{Math.round(foto.accuracy)}m) · {new Date(foto.ts).toLocaleString('es-CL', { hour12: false })}
          </div>
          <Button variant="outline" size="sm" className="w-full" onClick={onClear}>Cambiar foto</Button>
        </div>
      ) : (
        <label className={cn(
          'flex h-44 cursor-pointer flex-col items-center justify-center gap-1 rounded-lg border-2 border-dashed border-gray-300 p-3 text-center hover:border-gray-400',
          uploading && 'opacity-60',
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
