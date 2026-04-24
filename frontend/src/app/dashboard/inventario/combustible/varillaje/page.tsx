'use client'

import { useEffect, useMemo, useState } from 'react'
import { useSearchParams } from 'next/navigation'
import Link from 'next/link'
import {
  ArrowLeft,
  Camera,
  CheckCircle2,
  AlertCircle,
  Ruler,
  Loader2,
  TrendingDown,
  TrendingUp,
} from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Spinner } from '@/components/ui/spinner'
import { cn, formatDate } from '@/lib/utils'
import {
  useEstanques,
  useVarillajesEstanque,
  useRegistrarVarillaje,
} from '@/hooks/use-combustible'
import { uploadEvidenciaCombustible } from '@/lib/services/combustible'

function fmtLt(n: number | null | undefined) {
  if (n == null) return '—'
  const v = Number(n)
  const sign = v > 0 ? '+' : ''
  return `${sign}${v.toLocaleString('es-CL', { maximumFractionDigits: 1 })} lt`
}

function fmtLtAbs(n: number | null | undefined) {
  if (n == null) return '—'
  return `${Number(n).toLocaleString('es-CL', { maximumFractionDigits: 1 })} lt`
}

export default function VarillajePage() {
  const params = useSearchParams()
  const estanqueInicial = params.get('estanque') || ''

  const [estanqueId, setEstanqueId] = useState(estanqueInicial)
  const [medicion, setMedicion] = useState('')
  const [turno, setTurno] = useState<'dia' | 'noche' | 'unico'>('dia')
  const [generarAjuste, setGenerarAjuste] = useState(true)
  const [observaciones, setObservaciones] = useState('')
  const [fotoUrl, setFotoUrl] = useState<string | null>(null)
  const [uploadingFoto, setUploadingFoto] = useState(false)

  const [submitError, setSubmitError] = useState<string | null>(null)
  const [submitSuccess, setSubmitSuccess] = useState<{
    teorico: number
    fisico: number
    diferencia: number
    ajusteId: string | null
  } | null>(null)

  const { data: estanques } = useEstanques()
  const { data: historial } = useVarillajesEstanque(estanqueId || undefined)
  const registrar = useRegistrarVarillaje()

  const estanque = (estanques ?? []).find((e) => e.id === estanqueId)

  const diferenciaPrevia = useMemo(() => {
    const m = parseFloat(medicion)
    if (isNaN(m) || !estanque) return null
    return m - Number(estanque.stock_teorico_lt ?? 0)
  }, [medicion, estanque])

  async function handleFoto(file: File) {
    if (!estanqueId) {
      setSubmitError('Seleccione el estanque primero.')
      return
    }
    setUploadingFoto(true)
    setSubmitError(null)
    const { url, error } = await uploadEvidenciaCombustible(file, {
      tipo: 'varillaje',
      estanqueId,
    })
    setUploadingFoto(false)
    if (error || !url) {
      setSubmitError(error?.message ?? 'No se pudo subir la foto.')
      return
    }
    setFotoUrl(url)
  }

  async function handleSubmit() {
    setSubmitError(null)
    if (!estanqueId) return setSubmitError('Seleccione el estanque.')
    const m = parseFloat(medicion)
    if (isNaN(m) || m < 0) return setSubmitError('Medicion invalida.')

    try {
      const result = await registrar.mutateAsync({
        estanque_id: estanqueId,
        medicion_fisica_lt: m,
        turno,
        generar_ajuste: generarAjuste,
        foto_varilla_url: fotoUrl,
        observaciones: observaciones || null,
      })
      if (result) {
        setSubmitSuccess({
          teorico: result.teorico_lt,
          fisico: result.fisico_lt,
          diferencia: result.diferencia_lt,
          ajusteId: result.ajuste_id,
        })
      }
    } catch (err: any) {
      setSubmitError(err?.message ?? 'Error al registrar el varillaje.')
    }
  }

  function reset() {
    setSubmitSuccess(null)
    setMedicion('')
    setFotoUrl(null)
    setObservaciones('')
  }

  useEffect(() => {
    if (!estanqueId && (estanques ?? []).length === 1) {
      setEstanqueId(estanques![0].id)
    }
  }, [estanques, estanqueId])

  if (submitSuccess) {
    const isMerma = submitSuccess.diferencia < -0.01
    const isSobrante = submitSuccess.diferencia > 0.01
    return (
      <div className="space-y-6">
        <Card>
          <CardContent className="flex flex-col items-center gap-4 p-8 text-center">
            <div
              className={cn(
                'flex h-16 w-16 items-center justify-center rounded-full',
                Math.abs(submitSuccess.diferencia) < 5
                  ? 'bg-green-100'
                  : 'bg-amber-100'
              )}
            >
              <CheckCircle2
                className={cn(
                  'h-10 w-10',
                  Math.abs(submitSuccess.diferencia) < 5
                    ? 'text-green-600'
                    : 'text-amber-600'
                )}
              />
            </div>
            <div>
              <h2 className="text-xl font-bold text-gray-900">Varillaje registrado</h2>
              <p className="mt-1 text-sm text-gray-500">
                {isMerma
                  ? 'Diferencia negativa detectada'
                  : isSobrante
                    ? 'Diferencia positiva detectada'
                    : 'Sin diferencia significativa'}
              </p>
            </div>

            <div className="grid w-full grid-cols-3 gap-2">
              <div className="rounded-lg bg-gray-50 p-3">
                <p className="text-[10px] uppercase text-gray-500">Teorico</p>
                <p className="text-sm font-semibold">{fmtLtAbs(submitSuccess.teorico)}</p>
              </div>
              <div className="rounded-lg bg-blue-50 p-3">
                <p className="text-[10px] uppercase text-blue-700">Fisico</p>
                <p className="text-sm font-semibold">{fmtLtAbs(submitSuccess.fisico)}</p>
              </div>
              <div
                className={cn(
                  'rounded-lg p-3',
                  isMerma
                    ? 'bg-red-50'
                    : isSobrante
                      ? 'bg-amber-50'
                      : 'bg-green-50'
                )}
              >
                <p className="text-[10px] uppercase text-gray-500">Diferencia</p>
                <p className="text-sm font-semibold">
                  {fmtLt(submitSuccess.diferencia)}
                </p>
              </div>
            </div>

            {submitSuccess.ajusteId && (
              <div className="w-full rounded-lg bg-amber-50 p-3 text-xs text-amber-800">
                Se genero un{' '}
                {isMerma ? 'movimiento de merma' : 'ajuste positivo'} automaticamente
                para reconciliar el stock.
              </div>
            )}

            <div className="flex w-full gap-2">
              <Button onClick={reset} className="flex-1" variant="outline">
                Nuevo varillaje
              </Button>
              <Link href="/dashboard/inventario/combustible" className="flex-1">
                <Button className="w-full">Volver</Button>
              </Link>
            </div>
          </CardContent>
        </Card>
      </div>
    )
  }

  return (
    <div className="space-y-4 pb-20">
      {/* Header */}
      <div className="flex items-center gap-3">
        <Link href="/dashboard/inventario/combustible">
          <Button variant="outline" size="sm" className="gap-1">
            <ArrowLeft className="h-4 w-4" /> Volver
          </Button>
        </Link>
        <h1 className="text-xl font-bold text-gray-900">Varillaje</h1>
      </div>

      {/* Estanque */}
      <Card>
        <CardContent className="space-y-3 p-4">
          <label className="block text-sm font-medium text-gray-700">Estanque</label>
          <select
            value={estanqueId}
            onChange={(e) => setEstanqueId(e.target.value)}
            className="w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm"
          >
            <option value="">— Seleccione —</option>
            {(estanques ?? []).map((e) => (
              <option key={e.id} value={e.id}>
                {e.codigo} · {e.nombre}
              </option>
            ))}
          </select>

          {estanque && (
            <div className="rounded-lg bg-gray-50 p-3 text-sm">
              <div className="flex items-center justify-between">
                <span className="text-gray-600">Stock teorico actual</span>
                <span className="font-bold">{fmtLtAbs(estanque.stock_teorico_lt)}</span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-gray-600">Capacidad</span>
                <span>{fmtLtAbs(estanque.capacidad_lt)}</span>
              </div>
            </div>
          )}
        </CardContent>
      </Card>

      {/* Turno */}
      {estanqueId && (
        <Card>
          <CardContent className="space-y-3 p-4">
            <label className="block text-sm font-medium text-gray-700">Turno</label>
            <div className="grid grid-cols-3 gap-2">
              {(['dia', 'noche', 'unico'] as const).map((t) => (
                <button
                  key={t}
                  onClick={() => setTurno(t)}
                  className={cn(
                    'rounded-lg border px-3 py-2 text-xs font-medium capitalize',
                    turno === t
                      ? 'border-pillado-green-500 bg-pillado-green-50 text-pillado-green-700'
                      : 'border-gray-200 bg-white text-gray-600'
                  )}
                >
                  {t}
                </button>
              ))}
            </div>
          </CardContent>
        </Card>
      )}

      {/* Medicion */}
      {estanqueId && (
        <Card>
          <CardContent className="space-y-3 p-4">
            <label className="block text-sm font-medium text-gray-700">
              <Ruler className="mr-1 inline h-4 w-4" />
              Medicion fisica (litros)
            </label>
            <Input
              type="number"
              step="0.1"
              value={medicion}
              onChange={(e) => setMedicion(e.target.value)}
              placeholder="0.0"
              className="text-2xl font-mono"
              inputMode="decimal"
            />

            {diferenciaPrevia != null && (
              <div
                className={cn(
                  'flex items-center gap-2 rounded-lg p-3 text-sm',
                  Math.abs(diferenciaPrevia) < 5
                    ? 'bg-green-50 text-green-800'
                    : diferenciaPrevia < 0
                      ? 'bg-red-50 text-red-800'
                      : 'bg-amber-50 text-amber-800'
                )}
              >
                {diferenciaPrevia < 0 ? (
                  <TrendingDown className="h-4 w-4" />
                ) : (
                  <TrendingUp className="h-4 w-4" />
                )}
                <span className="font-semibold">Diferencia: {fmtLt(diferenciaPrevia)}</span>
                <span className="text-xs">
                  {diferenciaPrevia < 0
                    ? '(merma)'
                    : diferenciaPrevia > 0
                      ? '(sobrante)'
                      : ''}
                </span>
              </div>
            )}

            <label className="flex items-start gap-2 rounded-lg bg-blue-50 p-3 text-xs">
              <input
                type="checkbox"
                checked={generarAjuste}
                onChange={(e) => setGenerarAjuste(e.target.checked)}
                className="mt-0.5"
              />
              <div>
                <div className="font-medium text-blue-900">
                  Generar ajuste automatico
                </div>
                <div className="text-blue-700">
                  Si hay diferencia, crea un movimiento de merma o ajuste para que el
                  stock teorico coincida con la medicion fisica.
                </div>
              </div>
            </label>
          </CardContent>
        </Card>
      )}

      {/* Foto de la varilla (opcional) */}
      {estanqueId && (
        <Card>
          <CardContent className="space-y-3 p-4">
            <h3 className="text-sm font-semibold text-gray-700">
              Foto de la varilla (opcional)
            </h3>
            {fotoUrl ? (
              <div className="space-y-2">
                <img
                  src={fotoUrl}
                  alt="Varilla"
                  className="h-40 w-full rounded-lg border object-cover"
                />
                <Button
                  variant="outline"
                  size="sm"
                  className="w-full"
                  onClick={() => setFotoUrl(null)}
                >
                  Cambiar foto
                </Button>
              </div>
            ) : (
              <label
                className={cn(
                  'flex cursor-pointer flex-col items-center justify-center gap-2 rounded-lg border-2 border-dashed border-gray-300 p-5 text-center',
                  uploadingFoto && 'opacity-60'
                )}
              >
                {uploadingFoto ? (
                  <Loader2 className="h-6 w-6 animate-spin text-gray-400" />
                ) : (
                  <Camera className="h-6 w-6 text-gray-400" />
                )}
                <span className="text-sm font-medium text-gray-700">
                  {uploadingFoto ? 'Subiendo…' : 'Tomar foto'}
                </span>
                <input
                  type="file"
                  accept="image/*"
                  capture="environment"
                  className="hidden"
                  disabled={uploadingFoto}
                  onChange={(e) => {
                    const f = e.target.files?.[0]
                    if (f) handleFoto(f)
                  }}
                />
              </label>
            )}
          </CardContent>
        </Card>
      )}

      {/* Observaciones */}
      {estanqueId && (
        <Card>
          <CardContent className="space-y-2 p-4">
            <label className="block text-xs font-medium text-gray-600">
              Observaciones
            </label>
            <textarea
              value={observaciones}
              onChange={(e) => setObservaciones(e.target.value)}
              rows={2}
              className="w-full rounded-lg border border-gray-300 p-2 text-sm"
              placeholder="Opcional"
            />
          </CardContent>
        </Card>
      )}

      {/* Historial */}
      {estanqueId && (historial ?? []).length > 0 && (
        <div>
          <h2 className="mb-2 text-sm font-semibold text-gray-700">
            Ultimos varillajes
          </h2>
          <Card>
            <CardContent className="p-0">
              <ul className="divide-y">
                {(historial ?? []).slice(0, 5).map((v) => (
                  <li
                    key={v.id}
                    className="flex items-center gap-3 px-4 py-2.5 text-xs"
                  >
                    <div className="flex-1">
                      <div className="font-medium text-gray-900">
                        {formatDate(v.fecha)} {v.turno ? `· ${v.turno}` : ''}
                      </div>
                      <div className="text-gray-500">
                        Fisico {fmtLtAbs(v.medicion_fisica_lt)} / Teorico{' '}
                        {fmtLtAbs(v.stock_teorico_snapshot_lt)}
                      </div>
                    </div>
                    <div
                      className={cn(
                        'rounded px-2 py-0.5 font-semibold',
                        Math.abs(Number(v.diferencia_lt)) < 5
                          ? 'bg-green-100 text-green-700'
                          : Number(v.diferencia_lt) < 0
                            ? 'bg-red-100 text-red-700'
                            : 'bg-amber-100 text-amber-700'
                      )}
                    >
                      {fmtLt(v.diferencia_lt)}
                    </div>
                  </li>
                ))}
              </ul>
            </CardContent>
          </Card>
        </div>
      )}

      {submitError && (
        <div className="flex items-start gap-2 rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700">
          <AlertCircle className="h-4 w-4 flex-shrink-0" />
          <span>{submitError}</span>
        </div>
      )}

      {/* Submit sticky */}
      <div className="fixed bottom-0 left-0 right-0 z-30 border-t bg-white p-3 lg:static lg:border-0 lg:bg-transparent lg:p-0">
        <Button
          onClick={handleSubmit}
          disabled={registrar.isPending || !estanqueId || !medicion}
          className="w-full"
          size="lg"
        >
          {registrar.isPending ? (
            <>
              <Loader2 className="mr-2 h-4 w-4 animate-spin" />
              Registrando…
            </>
          ) : (
            'Registrar varillaje'
          )}
        </Button>
      </div>
    </div>
  )
}
