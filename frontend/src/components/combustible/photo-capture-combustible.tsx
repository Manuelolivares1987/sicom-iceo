'use client'

import { useRef, useState } from 'react'
import { Camera, RotateCcw, Check, AlertCircle, Loader2 } from 'lucide-react'
import { compressImage } from '@/lib/image/compress'
import { withTimeout } from '@/lib/upload/with-timeout'
import { tryGeolocate } from '@/lib/services/calama-jornada'
import {
  uploadBlobEvidenciaCombustible,
  type TipoEvidenciaCombustible,
} from '@/lib/services/combustible'
import { Button } from '@/components/ui/button'

const UPLOAD_TIMEOUT_MS = 30_000

export type PhotoCaptureCombustibleResult = {
  url: string
  storage_path: string
  lat: number | null
  lng: number | null
  accuracy: number | null
  geolocation_status: string | null
  ts: string
}

interface Props {
  label: string
  tipo: TipoEvidenciaCombustible
  contextoId: string
  onCapture: (result: PhotoCaptureCombustibleResult) => void
  required?: boolean
  initialUrl?: string | null
}

export function PhotoCaptureCombustible({
  label, tipo, contextoId, onCapture, required, initialUrl,
}: Props) {
  const inputRef = useRef<HTMLInputElement>(null)
  const [preview, setPreview] = useState<string | null>(initialUrl ?? null)
  const [stage, setStage] = useState<'idle' | 'compressing' | 'uploading'>('idle')
  const [error, setError] = useState<string | null>(null)
  const [warning, setWarning] = useState<string | null>(null)
  const [done, setDone] = useState<boolean>(!!initialUrl)
  const busy = stage !== 'idle'

  const handleFile = async (file: File) => {
    setError(null); setWarning(null)
    setStage('compressing')
    try {
      let blob: Blob = file
      try {
        blob = await compressImage(file, { maxDim: 1600, quality: 0.75 })
      } catch { /* keep original */ }
      if (/heic|heif/i.test(blob.type)) {
        setWarning('HEIC detectado. iPhone → Ajustes → Cámara → Formatos → "Más compatible" (JPEG).')
      }
      setPreview(URL.createObjectURL(blob))

      const gps = await tryGeolocate()
      setStage('uploading')
      const { url, storage_path } = await withTimeout(
        uploadBlobEvidenciaCombustible(blob, { tipo, contextoId }),
        UPLOAD_TIMEOUT_MS,
        'upload-evidencia-combustible',
      )
      const result: PhotoCaptureCombustibleResult = {
        url, storage_path,
        lat: gps.lat, lng: gps.lng, accuracy: gps.accuracy,
        geolocation_status: gps.status,
        ts: new Date().toISOString(),
      }
      setDone(true)
      onCapture(result)
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : 'Error al procesar foto'
      setError(msg)
      setPreview(null)
    } finally {
      setStage('idle')
    }
  }

  const reset = () => {
    setPreview(null); setDone(false); setError(null); setWarning(null)
    if (inputRef.current) inputRef.current.value = ''
  }

  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between">
        <span className="text-xs font-medium text-gray-700">
          {label}{required && <span className="ml-1 text-red-600">*</span>}
        </span>
        {done && (
          <span className="inline-flex items-center gap-1 text-xs text-green-700">
            <Check className="h-3 w-3" /> Subida
          </span>
        )}
      </div>

      {preview ? (
        <div className="space-y-2">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={preview} alt={label} className="w-full max-h-56 object-cover rounded border border-gray-300" />
          {!busy && (
            <Button size="sm" variant="ghost" onClick={reset} className="gap-1">
              <RotateCcw className="h-3 w-3" /> Tomar otra
            </Button>
          )}
        </div>
      ) : (
        <label
          className={`flex flex-col items-center justify-center gap-2 rounded-lg border-2 border-dashed
            ${error ? 'border-red-300 bg-red-50' : 'border-gray-300 bg-gray-50'}
            p-4 cursor-pointer hover:bg-gray-100`}
        >
          <input
            ref={inputRef}
            type="file"
            accept="image/*"
            capture="environment"
            className="hidden"
            onChange={(e) => {
              const f = e.target.files?.[0]
              if (f) void handleFile(f)
            }}
          />
          <Camera className="h-8 w-8 text-gray-400" />
          <span className="text-xs text-gray-600">Tomar foto</span>
        </label>
      )}

      {busy && (
        <div className="flex items-center gap-2 text-xs text-amber-700">
          <Loader2 className="h-3 w-3 animate-spin" />
          {stage === 'compressing' ? 'Procesando foto...' : 'Subiendo evidencia...'}
        </div>
      )}
      {warning && !error && (
        <div className="flex items-start gap-2 text-xs text-amber-700">
          <AlertCircle className="h-3 w-3 mt-0.5 shrink-0" /> {warning}
        </div>
      )}
      {error && (
        <div className="flex items-center gap-2 text-xs text-red-700">
          <AlertCircle className="h-3 w-3" /> {error}
        </div>
      )}
    </div>
  )
}
