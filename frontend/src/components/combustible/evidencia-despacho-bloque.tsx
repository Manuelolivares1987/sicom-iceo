'use client'

import { useState } from 'react'
import { Camera, PenTool, User } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { SignaturePad } from '@/components/ui/signature-pad'
import {
  PhotoCaptureCombustible,
  type PhotoCaptureCombustibleResult,
} from './photo-capture-combustible'
import {
  uploadBlobEvidenciaCombustible,
  type TipoEvidenciaCombustible,
} from '@/lib/services/combustible'

export interface EvidenciaDespachoPayload {
  // URLs subidas a storage
  foto_patente_url: string | null
  foto_medidor_inicial_url: string | null
  foto_medidor_final_url: string | null
  firma_receptor_url: string | null
  // Datos receptor
  nombre_receptor: string
  rut_receptor: string
  // Geolocalizacion de cada foto
  foto_patente_lat: number | null
  foto_patente_lon: number | null
  foto_patente_ts: string | null
  foto_medidor_inicial_lat: number | null
  foto_medidor_inicial_lon: number | null
  foto_medidor_inicial_ts: string | null
  foto_medidor_final_lat: number | null
  foto_medidor_final_lon: number | null
  foto_medidor_final_ts: string | null
  // Storage paths (auditoria)
  foto_patente_storage_path: string | null
  foto_medidor_inicial_storage_path: string | null
  foto_medidor_final_storage_path: string | null
  firma_receptor_storage_path: string | null
}

export const EVIDENCIA_VACIA: EvidenciaDespachoPayload = {
  foto_patente_url: null,
  foto_medidor_inicial_url: null,
  foto_medidor_final_url: null,
  firma_receptor_url: null,
  nombre_receptor: '',
  rut_receptor: '',
  foto_patente_lat: null, foto_patente_lon: null, foto_patente_ts: null,
  foto_medidor_inicial_lat: null, foto_medidor_inicial_lon: null, foto_medidor_inicial_ts: null,
  foto_medidor_final_lat: null, foto_medidor_final_lon: null, foto_medidor_final_ts: null,
  foto_patente_storage_path: null,
  foto_medidor_inicial_storage_path: null,
  foto_medidor_final_storage_path: null,
  firma_receptor_storage_path: null,
}

export function evidenciaCompleta(e: EvidenciaDespachoPayload): boolean {
  return Boolean(
    e.foto_patente_url
    && e.foto_medidor_inicial_url
    && e.foto_medidor_final_url
    && e.firma_receptor_url
    && e.nombre_receptor.trim().length >= 3
    && e.rut_receptor.trim().length >= 7,
  )
}

// Devuelve [valido, problema] para una validacion de RUT chileno con DV.
export function validarRut(rut: string): [boolean, string | null] {
  const limpio = rut.replace(/[.\s]/g, '').replace(/-/g, '').toUpperCase()
  if (limpio.length < 2) return [false, 'RUT muy corto']
  const cuerpo = limpio.slice(0, -1)
  const dv     = limpio.slice(-1)
  if (!/^\d+$/.test(cuerpo)) return [false, 'RUT debe ser numerico']
  let suma = 0; let multiplo = 2
  for (let i = cuerpo.length - 1; i >= 0; i--) {
    suma += Number(cuerpo[i]) * multiplo
    multiplo = multiplo === 7 ? 2 : multiplo + 1
  }
  const resto = 11 - (suma % 11)
  const dvCalc = resto === 11 ? '0' : resto === 10 ? 'K' : String(resto)
  if (dvCalc !== dv) return [false, 'RUT invalido (DV no coincide)']
  return [true, null]
}

interface Props {
  value: EvidenciaDespachoPayload
  onChange: (v: EvidenciaDespachoPayload) => void
  contextoId: string  // estanqueId o folio para particionar paths en storage
  // Personalizacion de labels (despacho vs recirculacion vs traspaso)
  labelPatente?: string
  labelMedidorInicial?: string
  labelMedidorFinal?: string
  labelFirma?: string
  labelReceptor?: string
  rolReceptor?: string  // "Receptor" | "Operador prueba" | "Operador traspaso"
}

export function EvidenciaDespachoBloque({
  value, onChange, contextoId,
  labelPatente = 'Foto patente del vehículo',
  labelMedidorInicial = 'Foto medidor INICIAL (antes de cargar)',
  labelMedidorFinal = 'Foto medidor FINAL (después de cargar)',
  labelFirma = 'Firma del receptor',
  labelReceptor = 'Receptor',
  rolReceptor = 'Receptor',
}: Props) {
  const [rutError, setRutError] = useState<string | null>(null)
  const [subiendoFirma, setSubiendoFirma] = useState(false)

  const setPatente = (r: PhotoCaptureCombustibleResult) => onChange({
    ...value,
    foto_patente_url: r.url,
    foto_patente_storage_path: r.storage_path,
    foto_patente_lat: r.lat, foto_patente_lon: r.lng, foto_patente_ts: r.ts,
  })
  const setMedInicial = (r: PhotoCaptureCombustibleResult) => onChange({
    ...value,
    foto_medidor_inicial_url: r.url,
    foto_medidor_inicial_storage_path: r.storage_path,
    foto_medidor_inicial_lat: r.lat, foto_medidor_inicial_lon: r.lng, foto_medidor_inicial_ts: r.ts,
  })
  const setMedFinal = (r: PhotoCaptureCombustibleResult) => onChange({
    ...value,
    foto_medidor_final_url: r.url,
    foto_medidor_final_storage_path: r.storage_path,
    foto_medidor_final_lat: r.lat, foto_medidor_final_lon: r.lng, foto_medidor_final_ts: r.ts,
  })

  const onFirma = async (dataUrl: string) => {
    setSubiendoFirma(true)
    try {
      const blob = await (await fetch(dataUrl)).blob()
      const { url, storage_path } = await uploadBlobEvidenciaCombustible(
        blob, { tipo: 'firma' as TipoEvidenciaCombustible, contextoId, ext: 'png' },
      )
      onChange({ ...value, firma_receptor_url: url, firma_receptor_storage_path: storage_path })
    } catch (e) {
      console.error('Error subiendo firma:', e)
    } finally {
      setSubiendoFirma(false)
    }
  }

  const onRutBlur = () => {
    if (!value.rut_receptor.trim()) { setRutError(null); return }
    const [ok, msg] = validarRut(value.rut_receptor)
    setRutError(ok ? null : msg)
  }

  return (
    <div className="space-y-4">
      <Card className="border-blue-200">
        <CardHeader>
          <CardTitle className="text-base flex items-center gap-2">
            <Camera className="h-4 w-4 text-blue-700" />
            Evidencia visual (obligatoria)
          </CardTitle>
        </CardHeader>
        <CardContent className="grid grid-cols-1 md:grid-cols-3 gap-3">
          <PhotoCaptureCombustible
            label={labelPatente} tipo="patente"
            contextoId={contextoId} required
            initialUrl={value.foto_patente_url}
            onCapture={setPatente}
          />
          <PhotoCaptureCombustible
            label={labelMedidorInicial} tipo="medidor_inicial"
            contextoId={contextoId} required
            initialUrl={value.foto_medidor_inicial_url}
            onCapture={setMedInicial}
          />
          <PhotoCaptureCombustible
            label={labelMedidorFinal} tipo="medidor_final"
            contextoId={contextoId} required
            initialUrl={value.foto_medidor_final_url}
            onCapture={setMedFinal}
          />
        </CardContent>
      </Card>

      <Card className="border-purple-200">
        <CardHeader>
          <CardTitle className="text-base flex items-center gap-2">
            <User className="h-4 w-4 text-purple-700" />
            {labelReceptor} (obligatorio)
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">
                Nombre {rolReceptor.toLowerCase()} <span className="text-red-600">*</span>
              </label>
              <Input
                value={value.nombre_receptor}
                onChange={(e) => onChange({ ...value, nombre_receptor: e.target.value })}
                placeholder="Nombre completo"
              />
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">
                RUT {rolReceptor.toLowerCase()} <span className="text-red-600">*</span>
              </label>
              <Input
                value={value.rut_receptor}
                onChange={(e) => onChange({ ...value, rut_receptor: e.target.value })}
                onBlur={onRutBlur}
                placeholder="12.345.678-9"
                className={rutError ? 'border-red-500' : ''}
              />
              {rutError && <div className="text-[11px] text-red-600 mt-1">{rutError}</div>}
            </div>
          </div>

          <div className="rounded border border-purple-100 bg-purple-50 p-3">
            <div className="flex items-center gap-2 text-xs font-medium text-purple-900 mb-2">
              <PenTool className="h-4 w-4" />
              {labelFirma} <span className="text-red-600">*</span>
            </div>
            <SignaturePad
              label=""
              existingUrl={value.firma_receptor_url}
              onCapture={(dataUrl) => void onFirma(dataUrl)}
            />
            {subiendoFirma && (
              <div className="text-[11px] text-amber-700 mt-1">Subiendo firma...</div>
            )}
            {value.firma_receptor_url && !subiendoFirma && (
              <div className="text-[11px] text-green-700 mt-1">Firma cargada ✓</div>
            )}
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
