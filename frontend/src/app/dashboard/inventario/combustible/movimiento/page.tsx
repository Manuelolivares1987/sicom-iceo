'use client'

import { useEffect, useMemo, useState } from 'react'
import { useSearchParams, useRouter } from 'next/navigation'
import Link from 'next/link'
import {
  ArrowLeft,
  Camera,
  CheckCircle2,
  AlertCircle,
  Fuel,
  Loader2,
} from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Spinner } from '@/components/ui/spinner'
import { cn, formatCLP } from '@/lib/utils'
import {
  useEstanques,
  useMedidoresEstanque,
  useRegistrarMovimientoCombustible,
} from '@/hooks/use-combustible'
import { useActivos } from '@/hooks/use-activos'
import { uploadEvidenciaCombustible } from '@/lib/services/combustible'
import type {
  TipoMovimientoCombustible,
  DestinoDespacho,
} from '@/lib/services/combustible'

type TipoUI = Extract<TipoMovimientoCombustible, 'ingreso' | 'despacho'>

function fmtLt(n: number | null | undefined) {
  if (n == null) return '—'
  return `${Number(n).toLocaleString('es-CL', { maximumFractionDigits: 1 })} lt`
}

export default function NuevoMovimientoPage() {
  const params = useSearchParams()
  const router = useRouter()
  const tipoInicial = (params.get('tipo') as TipoUI) || 'ingreso'
  const estanqueInicial = params.get('estanque') || ''

  const [tipo, setTipo] = useState<TipoUI>(tipoInicial)
  const [estanqueId, setEstanqueId] = useState(estanqueInicial)
  const [medidorId, setMedidorId] = useState('')
  const [lectInicial, setLectInicial] = useState('')
  const [lectFinal, setLectFinal] = useState('')

  // Ingreso
  const [proveedor, setProveedor] = useState('')
  const [numFactura, setNumFactura] = useState('')
  const [costoUnit, setCostoUnit] = useState('')

  // Despacho
  const [destinoTipo, setDestinoTipo] = useState<DestinoDespacho>('vehiculo_flota')
  const [vehiculoId, setVehiculoId] = useState('')
  const [destinoDescripcion, setDestinoDescripcion] = useState('')
  const [horometro, setHorometro] = useState('')
  const [kilometraje, setKilometraje] = useState('')

  // Foto y observaciones
  const [fotoUrl, setFotoUrl] = useState<string | null>(null)
  const [uploadingFoto, setUploadingFoto] = useState(false)
  const [observaciones, setObservaciones] = useState('')

  // Feedback
  const [submitError, setSubmitError] = useState<string | null>(null)
  const [submitSuccess, setSubmitSuccess] = useState<{
    litros: number
    stock: number
    costo: number | null
  } | null>(null)

  // Data
  const { data: estanques } = useEstanques()
  const { data: medidores, isLoading: loadingMed } = useMedidoresEstanque(estanqueId || undefined)
  const { data: activos } = useActivos()
  const registrar = useRegistrarMovimientoCombustible()

  // Prefill lectura inicial al elegir medidor
  const medidorSel = (medidores ?? []).find((m) => m.id === medidorId)
  useEffect(() => {
    if (medidorSel) {
      setLectInicial(String(medidorSel.lectura_acumulada_actual))
    }
  }, [medidorSel])

  // Auto-seleccionar primer medidor al cargar la lista
  useEffect(() => {
    if ((medidores ?? []).length > 0 && !medidorId) {
      setMedidorId(medidores![0].id)
    }
    if ((medidores ?? []).length === 0) {
      setMedidorId('')
    }
  }, [medidores])

  const estanque = (estanques ?? []).find((e) => e.id === estanqueId)

  const litros = useMemo(() => {
    const i = parseFloat(lectInicial)
    const f = parseFloat(lectFinal)
    if (isNaN(i) || isNaN(f) || f <= i) return 0
    return Math.round((f - i) * 100) / 100
  }, [lectInicial, lectFinal])

  const costoTotal = useMemo(() => {
    const c = parseFloat(costoUnit)
    if (isNaN(c) || litros <= 0) return 0
    return Math.round(c * litros)
  }, [costoUnit, litros])

  const vehiculosFlota = useMemo(
    () =>
      (activos ?? []).filter((a: any) =>
        ['camioneta', 'camion', 'camion_cisterna', 'lubrimovil', 'equipo_bombeo'].includes(
          a.tipo
        )
      ),
    [activos]
  )

  async function handleFoto(file: File) {
    if (!estanqueId) {
      setSubmitError('Seleccione el estanque primero.')
      return
    }
    setUploadingFoto(true)
    setSubmitError(null)
    const { url, error } = await uploadEvidenciaCombustible(file, {
      tipo: 'medidor',
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
    if (!medidorId) return setSubmitError('Seleccione el medidor.')
    const li = parseFloat(lectInicial)
    const lf = parseFloat(lectFinal)
    if (isNaN(li) || isNaN(lf)) return setSubmitError('Lecturas invalidas.')
    if (lf <= li) return setSubmitError('Lectura final debe ser mayor a la inicial.')
    if (!fotoUrl) return setSubmitError('Adjunte la foto del medidor.')

    if (tipo === 'ingreso') {
      if (!proveedor.trim()) return setSubmitError('Ingrese el proveedor.')
      if (!numFactura.trim()) return setSubmitError('Ingrese el numero de factura.')
      const c = parseFloat(costoUnit)
      if (isNaN(c) || c <= 0) return setSubmitError('Costo por litro invalido.')
    }

    if (tipo === 'despacho') {
      if (destinoTipo === 'vehiculo_flota' && !vehiculoId)
        return setSubmitError('Seleccione el vehiculo.')
      if (destinoTipo !== 'vehiculo_flota' && !destinoDescripcion.trim())
        return setSubmitError('Describa el destino.')
    }

    try {
      const result = await registrar.mutateAsync({
        tipo,
        estanque_id: estanqueId,
        medidor_id: medidorId,
        lectura_inicial_lt: li,
        lectura_final_lt: lf,
        foto_medidor_url: fotoUrl,
        proveedor: tipo === 'ingreso' ? proveedor : null,
        numero_factura: tipo === 'ingreso' ? numFactura : null,
        costo_unitario_clp: tipo === 'ingreso' ? parseFloat(costoUnit) : null,
        destino_tipo: tipo === 'despacho' ? destinoTipo : null,
        vehiculo_activo_id:
          tipo === 'despacho' && destinoTipo === 'vehiculo_flota' ? vehiculoId : null,
        destino_descripcion:
          tipo === 'despacho' && destinoTipo !== 'vehiculo_flota'
            ? destinoDescripcion
            : null,
        horometro_vehiculo:
          tipo === 'despacho' && horometro ? parseFloat(horometro) : null,
        kilometraje_vehiculo:
          tipo === 'despacho' && kilometraje ? parseFloat(kilometraje) : null,
        observaciones: observaciones || null,
      })
      if (result) {
        setSubmitSuccess({
          litros: result.litros,
          stock: result.stock_teorico,
          costo: result.costo_total_clp,
        })
      }
    } catch (err: any) {
      setSubmitError(err?.message ?? 'Error al registrar el movimiento.')
    }
  }

  function reset() {
    setSubmitSuccess(null)
    setLectFinal('')
    setFotoUrl(null)
    setObservaciones('')
    setNumFactura('')
    setVehiculoId('')
    setDestinoDescripcion('')
    setHorometro('')
    setKilometraje('')
  }

  if (submitSuccess) {
    return (
      <div className="space-y-6">
        <Card>
          <CardContent className="flex flex-col items-center gap-4 p-8 text-center">
            <div className="flex h-16 w-16 items-center justify-center rounded-full bg-green-100">
              <CheckCircle2 className="h-10 w-10 text-green-600" />
            </div>
            <div>
              <h2 className="text-xl font-bold text-gray-900">Movimiento registrado</h2>
              <p className="mt-1 text-sm text-gray-500">
                {fmtLt(submitSuccess.litros)} {tipo === 'ingreso' ? 'ingresados' : 'despachados'}
              </p>
            </div>
            <div className="grid w-full grid-cols-2 gap-3 text-center">
              <div className="rounded-lg bg-gray-50 p-3">
                <p className="text-xs text-gray-500">Stock actual</p>
                <p className="text-base font-semibold">{fmtLt(submitSuccess.stock)}</p>
              </div>
              {submitSuccess.costo != null && (
                <div className="rounded-lg bg-gray-50 p-3">
                  <p className="text-xs text-gray-500">Costo total</p>
                  <p className="text-base font-semibold">{formatCLP(submitSuccess.costo)}</p>
                </div>
              )}
            </div>
            <div className="flex w-full gap-2">
              <Button onClick={reset} className="flex-1" variant="outline">
                Nuevo movimiento
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
        <h1 className="text-xl font-bold text-gray-900">
          {tipo === 'ingreso' ? 'Ingreso de combustible' : 'Despacho de combustible'}
        </h1>
      </div>

      {/* Selector tipo */}
      <div className="grid grid-cols-2 gap-2 rounded-xl bg-gray-100 p-1">
        {(['ingreso', 'despacho'] as TipoUI[]).map((t) => (
          <button
            key={t}
            onClick={() => setTipo(t)}
            className={cn(
              'rounded-lg px-4 py-2 text-sm font-medium transition-colors',
              tipo === t
                ? 'bg-white text-pillado-green-600 shadow-sm'
                : 'text-gray-500'
            )}
          >
            {t === 'ingreso' ? 'Ingreso (compra)' : 'Despacho'}
          </button>
        ))}
      </div>

      {/* Estanque */}
      <Card>
        <CardContent className="space-y-3 p-4">
          <label className="block text-sm font-medium text-gray-700">Estanque</label>
          <select
            value={estanqueId}
            onChange={(e) => {
              setEstanqueId(e.target.value)
              setMedidorId('')
            }}
            className="w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm"
          >
            <option value="">— Seleccione —</option>
            {(estanques ?? []).map((e) => (
              <option key={e.id} value={e.id}>
                {e.codigo} · {e.nombre} ({fmtLt(e.stock_teorico_lt)})
              </option>
            ))}
          </select>

          {estanque && (
            <div className="rounded-lg bg-blue-50 p-3 text-xs text-blue-900">
              <div className="flex items-center gap-2">
                <Fuel className="h-4 w-4" />
                <span className="font-semibold">
                  Stock: {fmtLt(estanque.stock_teorico_lt)} / {fmtLt(estanque.capacidad_lt)}
                </span>
              </div>
              {tipo === 'ingreso' && litros > 0 && (
                <div className="mt-1">
                  Nuevo stock estimado:{' '}
                  <span className="font-semibold">
                    {fmtLt(Number(estanque.stock_teorico_lt) + litros)}
                  </span>
                </div>
              )}
              {tipo === 'despacho' && litros > 0 && (
                <div className="mt-1">
                  Nuevo stock estimado:{' '}
                  <span className="font-semibold">
                    {fmtLt(Math.max(0, Number(estanque.stock_teorico_lt) - litros))}
                  </span>
                </div>
              )}
            </div>
          )}
        </CardContent>
      </Card>

      {/* Medidor */}
      {estanqueId && (
        <Card>
          <CardContent className="space-y-3 p-4">
            <label className="block text-sm font-medium text-gray-700">Medidor</label>
            {loadingMed ? (
              <Spinner />
            ) : (medidores ?? []).length === 0 ? (
              <div className="rounded-lg bg-amber-50 p-3 text-xs text-amber-800">
                Este estanque no tiene medidores registrados. Cree uno desde
                administracion.
              </div>
            ) : (
              <select
                value={medidorId}
                onChange={(e) => setMedidorId(e.target.value)}
                className="w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm"
              >
                {medidores!.map((m) => (
                  <option key={m.id} value={m.id}>
                    {m.marca ? `${m.marca} ` : ''}
                    {m.modelo ?? ''} {m.numero_serie ? `• ${m.numero_serie}` : ''} (Ult: {m.lectura_acumulada_actual})
                  </option>
                ))}
              </select>
            )}
          </CardContent>
        </Card>
      )}

      {/* Lecturas */}
      {medidorId && (
        <Card>
          <CardContent className="space-y-3 p-4">
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="block text-xs font-medium text-gray-600">
                  Lectura inicial
                </label>
                <Input
                  type="number"
                  step="0.01"
                  value={lectInicial}
                  onChange={(e) => setLectInicial(e.target.value)}
                  className="mt-1 text-lg font-mono"
                  inputMode="decimal"
                />
                <p className="mt-1 text-[11px] text-gray-400">
                  Totalizador al iniciar
                </p>
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-600">
                  Lectura final
                </label>
                <Input
                  type="number"
                  step="0.01"
                  value={lectFinal}
                  onChange={(e) => setLectFinal(e.target.value)}
                  placeholder="0.00"
                  className="mt-1 text-lg font-mono"
                  inputMode="decimal"
                />
                <p className="mt-1 text-[11px] text-gray-400">Al terminar</p>
              </div>
            </div>

            <div
              className={cn(
                'rounded-lg p-3 text-center',
                litros > 0 ? 'bg-green-50' : 'bg-gray-50'
              )}
            >
              <p className="text-xs text-gray-500">Litros del movimiento</p>
              <p className="text-2xl font-bold text-gray-900">{fmtLt(litros)}</p>
            </div>
          </CardContent>
        </Card>
      )}

      {/* Campos ingreso */}
      {tipo === 'ingreso' && medidorId && (
        <Card>
          <CardContent className="space-y-3 p-4">
            <h3 className="text-sm font-semibold text-gray-700">Datos de compra</h3>
            <div>
              <label className="block text-xs font-medium text-gray-600">
                Proveedor
              </label>
              <Input
                value={proveedor}
                onChange={(e) => setProveedor(e.target.value)}
                placeholder="Copec, Shell, Petrobras…"
                className="mt-1"
              />
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="block text-xs font-medium text-gray-600">
                  N° Factura / Guia
                </label>
                <Input
                  value={numFactura}
                  onChange={(e) => setNumFactura(e.target.value)}
                  className="mt-1"
                />
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-600">
                  Costo por litro (CLP)
                </label>
                <Input
                  type="number"
                  step="0.01"
                  value={costoUnit}
                  onChange={(e) => setCostoUnit(e.target.value)}
                  inputMode="decimal"
                  className="mt-1"
                />
              </div>
            </div>
            {costoTotal > 0 && (
              <div className="rounded-lg bg-amber-50 p-3 text-center text-sm">
                <span className="text-gray-600">Costo total estimado: </span>
                <span className="font-bold">{formatCLP(costoTotal)}</span>
              </div>
            )}
          </CardContent>
        </Card>
      )}

      {/* Campos despacho */}
      {tipo === 'despacho' && medidorId && (
        <Card>
          <CardContent className="space-y-3 p-4">
            <h3 className="text-sm font-semibold text-gray-700">Destino</h3>
            <div className="grid grid-cols-2 gap-2">
              {([
                { v: 'vehiculo_flota', l: 'Vehiculo' },
                { v: 'equipo_externo', l: 'Eq. externo' },
                { v: 'bidon', l: 'Bidon' },
                { v: 'otro', l: 'Otro' },
              ] as { v: DestinoDespacho; l: string }[]).map((d) => (
                <button
                  key={d.v}
                  onClick={() => setDestinoTipo(d.v)}
                  className={cn(
                    'rounded-lg border px-3 py-2 text-xs font-medium',
                    destinoTipo === d.v
                      ? 'border-pillado-green-500 bg-pillado-green-50 text-pillado-green-700'
                      : 'border-gray-200 bg-white text-gray-600'
                  )}
                >
                  {d.l}
                </button>
              ))}
            </div>

            {destinoTipo === 'vehiculo_flota' ? (
              <>
                <select
                  value={vehiculoId}
                  onChange={(e) => setVehiculoId(e.target.value)}
                  className="w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm"
                >
                  <option value="">— Seleccione vehiculo —</option>
                  {vehiculosFlota.map((v: any) => (
                    <option key={v.id} value={v.id}>
                      {v.codigo} {v.nombre ? `· ${v.nombre}` : ''}
                    </option>
                  ))}
                </select>
                <div className="grid grid-cols-2 gap-3">
                  <div>
                    <label className="block text-xs font-medium text-gray-600">
                      Horometro
                    </label>
                    <Input
                      type="number"
                      step="0.1"
                      value={horometro}
                      onChange={(e) => setHorometro(e.target.value)}
                      inputMode="decimal"
                      className="mt-1"
                    />
                  </div>
                  <div>
                    <label className="block text-xs font-medium text-gray-600">
                      Kilometraje
                    </label>
                    <Input
                      type="number"
                      step="0.1"
                      value={kilometraje}
                      onChange={(e) => setKilometraje(e.target.value)}
                      inputMode="decimal"
                      className="mt-1"
                    />
                  </div>
                </div>
              </>
            ) : (
              <div>
                <label className="block text-xs font-medium text-gray-600">
                  Describa el destino
                </label>
                <Input
                  value={destinoDescripcion}
                  onChange={(e) => setDestinoDescripcion(e.target.value)}
                  placeholder={
                    destinoTipo === 'bidon'
                      ? 'Bidon 200L taller'
                      : destinoTipo === 'equipo_externo'
                        ? 'Generador obra'
                        : 'Detalle...'
                  }
                  className="mt-1"
                />
              </div>
            )}
          </CardContent>
        </Card>
      )}

      {/* Foto del medidor */}
      {medidorId && (
        <Card>
          <CardContent className="space-y-3 p-4">
            <h3 className="text-sm font-semibold text-gray-700">
              Foto del medidor *
            </h3>
            {fotoUrl ? (
              <div className="space-y-2">
                <img
                  src={fotoUrl}
                  alt="Medidor"
                  className="h-48 w-full rounded-lg border object-cover"
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
                  'flex cursor-pointer flex-col items-center justify-center gap-2 rounded-lg border-2 border-dashed border-gray-300 p-6 text-center',
                  uploadingFoto && 'opacity-60'
                )}
              >
                {uploadingFoto ? (
                  <Loader2 className="h-8 w-8 animate-spin text-gray-400" />
                ) : (
                  <Camera className="h-8 w-8 text-gray-400" />
                )}
                <span className="text-sm font-medium text-gray-700">
                  {uploadingFoto ? 'Subiendo…' : 'Tomar foto'}
                </span>
                <span className="text-xs text-gray-500">
                  Muestra el totalizador con la lectura actual
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
      {medidorId && (
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

      {/* Error */}
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
          disabled={registrar.isPending || !medidorId || !fotoUrl}
          className="w-full"
          size="lg"
        >
          {registrar.isPending ? (
            <>
              <Loader2 className="mr-2 h-4 w-4 animate-spin" />
              Registrando…
            </>
          ) : (
            `Registrar ${tipo === 'ingreso' ? 'ingreso' : 'despacho'}${
              litros > 0 ? ` de ${fmtLt(litros)}` : ''
            }`
          )}
        </Button>
      </div>
    </div>
  )
}
