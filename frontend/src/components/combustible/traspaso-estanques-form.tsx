'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { ArrowLeft, Save, AlertCircle, ArrowRightLeft } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Spinner } from '@/components/ui/spinner'
import { SignaturePad } from '@/components/ui/signature-pad'
import { formatCLP, todayISO } from '@/lib/utils'
import { useToast } from '@/contexts/toast-context'
import { useEstanquesActivos } from '@/hooks/use-combustible-cpp'
import { useRegistrarTraspaso } from '@/hooks/use-combustible-recirculacion-traspaso'
import {
  PhotoCaptureCombustible,
  type PhotoCaptureCombustibleResult,
} from './photo-capture-combustible'
import {
  uploadBlobEvidenciaCombustible, type TipoEvidenciaCombustible,
} from '@/lib/services/combustible'
import { validarRut } from './evidencia-despacho-bloque'

export function TraspasoEstanquesForm() {
  const router = useRouter()
  const toast = useToast()

  const [origenId, setOrigenId] = useState('')
  const [destinoId, setDestinoId] = useState('')
  const [litros, setLitros] = useState<number | ''>('')

  // Lecturas medidores
  const [lecOriIni, setLecOriIni] = useState<number | ''>('')
  const [lecOriFin, setLecOriFin] = useState<number | ''>('')
  const [lecDstIni, setLecDstIni] = useState<number | ''>('')
  const [lecDstFin, setLecDstFin] = useState<number | ''>('')

  // Fotos
  const [fotoOriIni, setFotoOriIni] = useState<PhotoCaptureCombustibleResult | null>(null)
  const [fotoOriFin, setFotoOriFin] = useState<PhotoCaptureCombustibleResult | null>(null)
  const [fotoDstIni, setFotoDstIni] = useState<PhotoCaptureCombustibleResult | null>(null)
  const [fotoDstFin, setFotoDstFin] = useState<PhotoCaptureCombustibleResult | null>(null)
  const [fotoManguerado, setFotoManguerado] = useState<PhotoCaptureCombustibleResult | null>(null)

  // Operador
  const [nombreOp, setNombreOp] = useState('')
  const [rutOp, setRutOp] = useState('')
  const [rutError, setRutError] = useState<string | null>(null)
  const [firmaUrl, setFirmaUrl] = useState<string | null>(null)
  const [subiendoFirma, setSubiendoFirma] = useState(false)

  const [motivo, setMotivo] = useState('')
  const [observacion, setObservacion] = useState('')
  const [fecha, setFecha] = useState<string>(todayISO())

  const { data: estanques, isLoading: loadEst } = useEstanquesActivos()
  const registrar = useRegistrarTraspaso()

  const origen = estanques?.find((e) => e.id === origenId)
  const destino = estanques?.find((e) => e.id === destinoId)
  const litrosNum = typeof litros === 'number' ? litros : 0

  const stockOri = origen ? Number(origen.stock_teorico_lt) : 0
  const stockDst = destino ? Number(destino.stock_teorico_lt) : 0
  const capDst   = destino ? Number(destino.capacidad_lt) : 0
  const cppOri   = origen ? Number(origen.costo_promedio_lt) : 0
  const cppDst   = destino ? Number(destino.costo_promedio_lt) : 0

  const excedeStock = origen && litrosNum > stockOri
  const excedeCapacidad = destino && (stockDst + litrosNum) > capDst

  // CPP destino post-traspaso (simulado)
  const cppDestinoSimulado = (() => {
    const stockDstNuevo = stockDst + litrosNum
    if (stockDstNuevo <= 0) return cppOri
    return ((stockDst * cppDst) + (litrosNum * cppOri)) / stockDstNuevo
  })()

  const errores: string[] = []
  if (!origenId) errores.push('Selecciona estanque ORIGEN.')
  if (!destinoId) errores.push('Selecciona estanque DESTINO.')
  if (origenId && destinoId && origenId === destinoId) errores.push('Origen y destino no pueden ser el mismo.')
  if (litrosNum <= 0) errores.push('Litros debe ser > 0.')
  if (excedeStock) errores.push(`Stock insuficiente en origen: ${litrosNum} > ${stockOri.toFixed(2)} lt.`)
  if (excedeCapacidad) errores.push(`Capacidad excedida en destino: ${stockDst.toFixed(2)} + ${litrosNum} > ${capDst.toFixed(2)} lt.`)
  if (!fotoOriIni) errores.push('Foto medidor ORIGEN INICIAL obligatoria.')
  if (!fotoOriFin) errores.push('Foto medidor ORIGEN FINAL obligatoria.')
  if (!fotoDstIni) errores.push('Foto medidor DESTINO INICIAL obligatoria.')
  if (!fotoDstFin) errores.push('Foto medidor DESTINO FINAL obligatoria.')
  if (!fotoManguerado) errores.push('Foto del manguerado entre estanques obligatoria.')
  if (nombreOp.trim().length < 3) errores.push('Nombre del operador obligatorio.')
  if (rutOp.trim().length < 7) errores.push('RUT del operador obligatorio.')
  if (rutError) errores.push(`RUT operador: ${rutError}`)
  if (!firmaUrl) errores.push('Firma del operador obligatoria.')
  if (motivo.trim().length < 5) errores.push('Motivo mínimo 5 caracteres.')

  const canSubmit = errores.length === 0

  if (loadEst) {
    return <div className="flex justify-center py-10"><Spinner /></div>
  }

  const onRutBlur = () => {
    if (!rutOp.trim()) { setRutError(null); return }
    const [ok, msg] = validarRut(rutOp)
    setRutError(ok ? null : msg)
  }

  const onFirma = async (dataUrl: string) => {
    setSubiendoFirma(true)
    try {
      const blob = await (await fetch(dataUrl)).blob()
      const { url } = await uploadBlobEvidenciaCombustible(blob, {
        tipo: 'firma' as TipoEvidenciaCombustible,
        contextoId: origenId || 'traspaso',
        ext: 'png',
      })
      setFirmaUrl(url)
    } catch (e) {
      toast.error(`Firma: ${(e as Error).message}`)
    } finally {
      setSubiendoFirma(false)
    }
  }

  const onSubmit = () => {
    if (!canSubmit) {
      toast.error('Revisa los campos marcados')
      return
    }
    registrar.mutate({
      estanque_origen_id:                origenId,
      estanque_destino_id:               destinoId,
      litros:                            litrosNum,
      foto_medidor_origen_inicial_url:   fotoOriIni!.url,
      foto_medidor_origen_final_url:     fotoOriFin!.url,
      foto_medidor_destino_inicial_url:  fotoDstIni!.url,
      foto_medidor_destino_final_url:    fotoDstFin!.url,
      foto_manguerado_url:               fotoManguerado!.url,
      nombre_operador:                   nombreOp.trim(),
      rut_operador:                      rutOp.trim(),
      firma_operador_url:                firmaUrl!,
      motivo:                            motivo.trim(),
      lectura_medidor_origen_inicial:    typeof lecOriIni === 'number' ? lecOriIni : null,
      lectura_medidor_origen_final:      typeof lecOriFin === 'number' ? lecOriFin : null,
      lectura_medidor_destino_inicial:   typeof lecDstIni === 'number' ? lecDstIni : null,
      lectura_medidor_destino_final:     typeof lecDstFin === 'number' ? lecDstFin : null,
      observacion:                       observacion.trim() || null,
      lat:                               fotoManguerado?.lat ?? null,
      lng:                               fotoManguerado?.lng ?? null,
      accuracy:                          fotoManguerado?.accuracy ?? null,
      geolocation_status:                fotoManguerado?.geolocation_status ?? null,
      fecha_traspaso:                    fecha ? `${fecha}T00:00:00Z` : null,
    }, {
      onSuccess: (data) => {
        toast.success(
          `Traspaso ${data.folio}: ${data.litros} lt de ${data.origen_codigo} → ${data.destino_codigo}. ` +
          `CPP destino: ${formatCLP(data.cpp_destino_antes)} → ${formatCLP(data.cpp_destino_despues)}`,
        )
        router.push('/dashboard/combustible')
      },
      onError: (err: unknown) => {
        toast.error(err instanceof Error ? err.message : 'Error al registrar traspaso')
      },
    })
  }

  const contextoId = origenId || 'traspaso'

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-2">
        <Button variant="outline" size="sm" onClick={() => router.back()}>
          <ArrowLeft className="h-4 w-4 mr-1" /> Volver
        </Button>
        <h1 className="text-xl font-bold flex items-center gap-2">
          <ArrowRightLeft className="h-5 w-5 text-indigo-700" />
          Traspaso entre estanques
        </h1>
      </div>

      <div className="rounded-lg border border-indigo-200 bg-indigo-50 p-3 text-xs text-indigo-900 flex items-start gap-2">
        <AlertCircle className="h-4 w-4 mt-0.5 shrink-0" />
        <div>
          <strong>Mueve stock entre dos estanques.</strong> El combustible sale del origen al CPP vigente y
          entra al destino al mismo costo unitario; el CPP del destino se recalcula con fórmula móvil.
          Se generan 2 movimientos enlazados en el kárdex.
        </div>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Estanques y litros</CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">Estanque ORIGEN *</label>
              <select value={origenId} onChange={(e) => setOrigenId(e.target.value)}
                      className="w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-sm">
                <option value="">— Selecciona origen —</option>
                {(estanques ?? []).map((e) => (
                  <option key={e.id} value={e.id}>
                    {e.codigo} — {e.nombre} (stock {Number(e.stock_teorico_lt).toFixed(0)} lt)
                  </option>
                ))}
              </select>
              {origen && (
                <div className="text-[11px] text-gray-600 mt-1">
                  Stock: <strong>{stockOri.toFixed(2)} lt</strong> · CPP: <strong>{formatCLP(cppOri)}</strong>
                </div>
              )}
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">Estanque DESTINO *</label>
              <select value={destinoId} onChange={(e) => setDestinoId(e.target.value)}
                      className="w-full rounded-md border border-gray-300 bg-white px-3 py-2 text-sm">
                <option value="">— Selecciona destino —</option>
                {(estanques ?? []).filter((e) => e.id !== origenId).map((e) => (
                  <option key={e.id} value={e.id}>
                    {e.codigo} — {e.nombre} (stock {Number(e.stock_teorico_lt).toFixed(0)} / cap {Number(e.capacidad_lt).toFixed(0)} lt)
                  </option>
                ))}
              </select>
              {destino && (
                <div className="text-[11px] text-gray-600 mt-1">
                  Stock: <strong>{stockDst.toFixed(2)} lt</strong> · Capacidad libre: <strong>{(capDst - stockDst).toFixed(2)} lt</strong> · CPP: <strong>{formatCLP(cppDst)}</strong>
                </div>
              )}
            </div>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">Litros a traspasar *</label>
              <Input type="number" step="0.01" min="0.01"
                     max={stockOri}
                     value={litros}
                     onChange={(e) => setLitros(e.target.value === '' ? '' : Number(e.target.value))}
                     className={excedeStock || excedeCapacidad ? 'border-red-500' : ''} />
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">Motivo * (mín 5)</label>
              <Input value={motivo} onChange={(e) => setMotivo(e.target.value)}
                     placeholder="ej: Rebalanceo entre estanque 15K y 1K" />
            </div>
          </div>

          {origen && destino && litrosNum > 0 && !excedeStock && !excedeCapacidad && (
            <div className="rounded-lg border border-green-200 bg-green-50 p-3 text-xs text-green-900 space-y-1">
              <div className="font-semibold">Preview del traspaso</div>
              <div className="flex flex-wrap gap-x-3 gap-y-1">
                <span>{origen.codigo}: {stockOri.toFixed(2)} → <strong>{(stockOri - litrosNum).toFixed(2)} lt</strong></span>
                <span>{destino.codigo}: {stockDst.toFixed(2)} → <strong>{(stockDst + litrosNum).toFixed(2)} lt</strong></span>
                <span>CPP destino: {formatCLP(cppDst)} → <strong>{formatCLP(cppDestinoSimulado)}</strong></span>
                <span>Costo movido: <strong>{formatCLP(litrosNum * cppOri)}</strong></span>
              </div>
            </div>
          )}
        </CardContent>
      </Card>

      {/* Lecturas medidores */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base">Lecturas medidores (opcional)</CardTitle>
        </CardHeader>
        <CardContent className="grid grid-cols-1 md:grid-cols-4 gap-3">
          <div>
            <label className="block text-[11px] font-medium text-gray-700 mb-1">Origen ANTES (lt)</label>
            <Input type="number" step="0.01" min="0" value={lecOriIni}
                   onChange={(e) => setLecOriIni(e.target.value === '' ? '' : Number(e.target.value))} />
          </div>
          <div>
            <label className="block text-[11px] font-medium text-gray-700 mb-1">Origen DESPUÉS (lt)</label>
            <Input type="number" step="0.01" min="0" value={lecOriFin}
                   onChange={(e) => setLecOriFin(e.target.value === '' ? '' : Number(e.target.value))} />
          </div>
          <div>
            <label className="block text-[11px] font-medium text-gray-700 mb-1">Destino ANTES (lt)</label>
            <Input type="number" step="0.01" min="0" value={lecDstIni}
                   onChange={(e) => setLecDstIni(e.target.value === '' ? '' : Number(e.target.value))} />
          </div>
          <div>
            <label className="block text-[11px] font-medium text-gray-700 mb-1">Destino DESPUÉS (lt)</label>
            <Input type="number" step="0.01" min="0" value={lecDstFin}
                   onChange={(e) => setLecDstFin(e.target.value === '' ? '' : Number(e.target.value))} />
          </div>
        </CardContent>
      </Card>

      {/* Fotos */}
      <Card className="border-blue-200">
        <CardHeader>
          <CardTitle className="text-base">Evidencia visual (obligatoria)</CardTitle>
        </CardHeader>
        <CardContent className="grid grid-cols-1 md:grid-cols-2 gap-3">
          <PhotoCaptureCombustible
            label="Foto medidor ORIGEN inicial" tipo="medidor_inicial"
            contextoId={contextoId} required
            initialUrl={fotoOriIni?.url ?? null}
            onCapture={setFotoOriIni}
          />
          <PhotoCaptureCombustible
            label="Foto medidor ORIGEN final" tipo="medidor_final"
            contextoId={contextoId} required
            initialUrl={fotoOriFin?.url ?? null}
            onCapture={setFotoOriFin}
          />
          <PhotoCaptureCombustible
            label="Foto medidor DESTINO inicial" tipo="medidor_inicial"
            contextoId={destinoId || contextoId} required
            initialUrl={fotoDstIni?.url ?? null}
            onCapture={setFotoDstIni}
          />
          <PhotoCaptureCombustible
            label="Foto medidor DESTINO final" tipo="medidor_final"
            contextoId={destinoId || contextoId} required
            initialUrl={fotoDstFin?.url ?? null}
            onCapture={setFotoDstFin}
          />
          <div className="md:col-span-2">
            <PhotoCaptureCombustible
              label="Foto del manguerado entre estanques" tipo="manguerado"
              contextoId={contextoId} required
              initialUrl={fotoManguerado?.url ?? null}
              onCapture={setFotoManguerado}
            />
          </div>
        </CardContent>
      </Card>

      {/* Operador */}
      <Card className="border-purple-200">
        <CardHeader>
          <CardTitle className="text-base">Operador que ejecuta el traspaso *</CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">Nombre operador *</label>
              <Input value={nombreOp} onChange={(e) => setNombreOp(e.target.value)} placeholder="Nombre completo" />
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">RUT operador *</label>
              <Input value={rutOp} onChange={(e) => setRutOp(e.target.value)} onBlur={onRutBlur}
                     placeholder="12.345.678-9" className={rutError ? 'border-red-500' : ''} />
              {rutError && <div className="text-[11px] text-red-600 mt-1">{rutError}</div>}
            </div>
          </div>
          <div className="rounded border border-purple-100 bg-purple-50 p-3">
            <div className="text-xs font-medium text-purple-900 mb-2">Firma del operador *</div>
            <SignaturePad label="" existingUrl={firmaUrl}
                          onCapture={(d) => void onFirma(d)} />
            {subiendoFirma && <div className="text-[11px] text-amber-700 mt-1">Subiendo firma...</div>}
            {firmaUrl && !subiendoFirma && <div className="text-[11px] text-green-700 mt-1">Firma cargada ✓</div>}
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardContent className="grid grid-cols-1 md:grid-cols-3 gap-3 py-3">
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

      {errores.length > 0 && (origenId || destinoId || litros !== '' || motivo.length > 0) && (
        <div className="rounded-lg border border-amber-200 bg-amber-50 p-2 text-xs text-amber-900">
          <ul className="list-disc list-inside">{errores.map((e, i) => <li key={i}>{e}</li>)}</ul>
        </div>
      )}

      <Card>
        <CardContent className="flex items-center justify-between py-4">
          <Button variant="outline" onClick={() => router.back()} disabled={registrar.isPending}>Cancelar</Button>
          <Button onClick={onSubmit} disabled={!canSubmit || registrar.isPending}>
            {registrar.isPending ? <Spinner className="h-4 w-4 mr-2" /> : <Save className="h-4 w-4 mr-2" />}
            {registrar.isPending ? 'Registrando...' : 'Registrar traspaso'}
          </Button>
        </CardContent>
      </Card>
    </div>
  )
}
