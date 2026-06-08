'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { ArrowLeft, Save, AlertCircle, Repeat } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Spinner } from '@/components/ui/spinner'
import { SignaturePad } from '@/components/ui/signature-pad'
import { todayISO } from '@/lib/utils'
import { useToast } from '@/contexts/toast-context'
import { useEstanquesActivos } from '@/hooks/use-combustible-cpp'
import { useRegistrarRecirculacion } from '@/hooks/use-combustible-recirculacion-traspaso'
import {
  PhotoCaptureCombustible,
  type PhotoCaptureCombustibleResult,
} from './photo-capture-combustible'
import {
  uploadBlobEvidenciaCombustible, type TipoEvidenciaCombustible,
} from '@/lib/services/combustible'
import { validarRut } from './evidencia-despacho-bloque'

export function RecirculacionForm() {
  const router = useRouter()
  const toast = useToast()

  const [estanqueId, setEstanqueId] = useState('')
  const [litros, setLitros] = useState<number | ''>('')
  const [equipoDesc, setEquipoDesc] = useState('')
  const [patenteEquipo, setPatenteEquipo] = useState('')

  const [fotoPatente, setFotoPatente] = useState<PhotoCaptureCombustibleResult | null>(null)
  const [fotoEquipo, setFotoEquipo] = useState<PhotoCaptureCombustibleResult | null>(null)
  const [fotoMedIni, setFotoMedIni] = useState<PhotoCaptureCombustibleResult | null>(null)
  const [fotoMedFin, setFotoMedFin] = useState<PhotoCaptureCombustibleResult | null>(null)

  const [lecturaIni, setLecturaIni] = useState<number | ''>('')
  const [lecturaFin, setLecturaFin] = useState<number | ''>('')

  const [nombreOp, setNombreOp] = useState('')
  const [rutOp, setRutOp] = useState('')
  const [rutError, setRutError] = useState<string | null>(null)
  const [firmaUrl, setFirmaUrl] = useState<string | null>(null)
  const [subiendoFirma, setSubiendoFirma] = useState(false)

  const [motivo, setMotivo] = useState('')
  const [observacion, setObservacion] = useState('')
  const [fecha, setFecha] = useState<string>(todayISO())

  const { data: estanques, isLoading: loadEst } = useEstanquesActivos()
  const registrar = useRegistrarRecirculacion()

  const estanque = estanques?.find((e) => e.id === estanqueId)
  const litrosNum = typeof litros === 'number' ? litros : 0
  const stockActual = estanque ? Number(estanque.stock_teorico_lt) : 0
  const excedeStock = estanque && litrosNum > stockActual

  const errores: string[] = []
  if (!estanqueId) errores.push('Selecciona estanque.')
  if (litrosNum <= 0) errores.push('Litros debe ser > 0.')
  if (excedeStock) errores.push(`Stock insuficiente: solicitado ${litrosNum}, disponible ${stockActual.toFixed(2)}.`)
  if (equipoDesc.trim().length < 3) errores.push('Descripción del equipo (mín 3 caracteres).')
  if (!fotoPatente) errores.push('Foto patente del equipo de prueba obligatoria.')
  if (!fotoEquipo) errores.push('Foto del equipo conectado obligatoria.')
  if (!fotoMedIni) errores.push('Foto medidor ANTES obligatoria.')
  if (!fotoMedFin) errores.push('Foto medidor DESPUÉS obligatoria.')
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
        contextoId: estanqueId || 'recirc',
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
      estanque_id:                  estanqueId,
      litros:                       litrosNum,
      equipo_prueba_descripcion:    equipoDesc.trim(),
      patente_equipo_prueba:        patenteEquipo.trim() || null,
      foto_patente_equipo_url:      fotoPatente!.url,
      foto_equipo_url:              fotoEquipo!.url,
      foto_medidor_inicial_url:     fotoMedIni!.url,
      foto_medidor_final_url:       fotoMedFin!.url,
      nombre_operador:              nombreOp.trim(),
      rut_operador:                 rutOp.trim(),
      firma_operador_url:           firmaUrl!,
      motivo:                       motivo.trim(),
      lectura_medidor_inicial_lt:   typeof lecturaIni === 'number' ? lecturaIni : null,
      lectura_medidor_final_lt:     typeof lecturaFin === 'number' ? lecturaFin : null,
      observacion:                  observacion.trim() || null,
      lat:                          fotoMedIni?.lat ?? null,
      lng:                          fotoMedIni?.lng ?? null,
      accuracy:                     fotoMedIni?.accuracy ?? null,
      geolocation_status:           fotoMedIni?.geolocation_status ?? null,
      fecha_inicio:                 fecha ? `${fecha}T00:00:00Z` : null,
    }, {
      onSuccess: (data) => {
        toast.success(`Recirculación ${data.folio} registrada: ${data.litros} lt (stock no cambia)`)
        router.push('/dashboard/combustible')
      },
      onError: (err: unknown) => {
        // Supabase devuelve PostgrestError (no es instancia de Error): extraer .message igual.
        const msg = err instanceof Error
          ? err.message
          : (err && typeof err === 'object' && 'message' in err)
            ? String((err as { message: unknown }).message)
            : 'Error al registrar recirculación'
        toast.error(msg)
      },
    })
  }

  const contextoId = estanqueId || 'recirc'

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-2">
        <Button variant="outline" size="sm" onClick={() => router.back()}>
          <ArrowLeft className="h-4 w-4 mr-1" /> Volver
        </Button>
        <h1 className="text-xl font-bold flex items-center gap-2">
          <Repeat className="h-5 w-5 text-blue-700" />
          Recirculación (prueba de bomba)
        </h1>
      </div>

      <div className="rounded-lg border border-blue-200 bg-blue-50 p-3 text-xs text-blue-900 flex items-start gap-2">
        <AlertCircle className="h-4 w-4 mt-0.5 shrink-0" />
        <div>
          <strong>Operación neutra de stock.</strong> El combustible sale del estanque, alimenta el equipo de
          prueba y vuelve al MISMO estanque. La cantidad que entra debe ser igual a la que sale.
          Por seguridad antifraude, se exige evidencia completa: fotos del equipo, medidor antes/después,
          firma del operador.
        </div>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Datos de la recirculación</CardTitle>
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
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">Litros a recircular *</label>
              <Input type="number" step="0.01" min="0.01" max={stockActual}
                     value={litros}
                     onChange={(e) => setLitros(e.target.value === '' ? '' : Number(e.target.value))}
                     className={excedeStock ? 'border-red-500' : ''} />
              {estanque && (
                <div className="text-[11px] text-gray-600 mt-1">
                  Stock actual: {stockActual.toFixed(2)} lt — el stock <strong>no cambia</strong> tras la operación.
                </div>
              )}
            </div>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">Equipo de prueba * (descripción)</label>
              <Input value={equipoDesc} onChange={(e) => setEquipoDesc(e.target.value)}
                     placeholder="ej: Bomba TCS modelo 700-20SP4AL" />
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">Patente del equipo (si aplica)</label>
              <Input value={patenteEquipo} onChange={(e) => setPatenteEquipo(e.target.value)}
                     placeholder="opcional" />
            </div>
          </div>

          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">Motivo * (mín 5)</label>
            <Input value={motivo} onChange={(e) => setMotivo(e.target.value)}
                   placeholder="ej: Prueba de presión bomba TCS-700" />
          </div>

          <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">Lectura medidor ANTES (lt)</label>
              <Input type="number" step="0.01" min="0" value={lecturaIni}
                     onChange={(e) => setLecturaIni(e.target.value === '' ? '' : Number(e.target.value))} />
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">Lectura medidor DESPUÉS (lt)</label>
              <Input type="number" step="0.01" min="0" value={lecturaFin}
                     onChange={(e) => setLecturaFin(e.target.value === '' ? '' : Number(e.target.value))} />
              <div className="text-[10px] text-gray-500 mt-1">
                Idealmente debe coincidir con la inicial: el combustible volvió al estanque.
              </div>
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">Fecha</label>
              <Input type="date" value={fecha} onChange={(e) => setFecha(e.target.value)} />
            </div>
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
            label="Foto patente del equipo de prueba" tipo="patente"
            contextoId={contextoId} required
            initialUrl={fotoPatente?.url ?? null}
            onCapture={setFotoPatente}
          />
          <PhotoCaptureCombustible
            label="Foto del equipo conectado" tipo="equipo"
            contextoId={contextoId} required
            initialUrl={fotoEquipo?.url ?? null}
            onCapture={setFotoEquipo}
          />
          <PhotoCaptureCombustible
            label="Foto medidor ANTES (lectura inicial)" tipo="medidor_inicial"
            contextoId={contextoId} required
            initialUrl={fotoMedIni?.url ?? null}
            onCapture={setFotoMedIni}
          />
          <PhotoCaptureCombustible
            label="Foto medidor DESPUÉS (tras devolver)" tipo="medidor_final"
            contextoId={contextoId} required
            initialUrl={fotoMedFin?.url ?? null}
            onCapture={setFotoMedFin}
          />
        </CardContent>
      </Card>

      {/* Operador */}
      <Card className="border-purple-200">
        <CardHeader>
          <CardTitle className="text-base">Operador que ejecuta la prueba *</CardTitle>
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
        <CardContent className="py-3">
          <label className="block text-xs font-medium text-gray-700 mb-1">Observación</label>
          <Input value={observacion} onChange={(e) => setObservacion(e.target.value)} placeholder="opcional" />
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
            {registrar.isPending ? 'Registrando...' : 'Registrar recirculación'}
          </Button>
        </CardContent>
      </Card>
    </div>
  )
}
