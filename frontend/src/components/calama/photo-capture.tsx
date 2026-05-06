'use client'

import { useRef, useState } from 'react'
import { Camera, RotateCcw, Check, AlertCircle, Loader2 } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { uploadEvidenciaJornada, tryGeolocate, type EvidenciaMomento } from '@/lib/services/calama-jornada'

export type PhotoCaptureResult = {
  url: string
  storage_path: string
  lat: number | null
  lng: number | null
}

interface PhotoCaptureProps {
  label: string
  momento: EvidenciaMomento
  otId: string
  planOtId: string
  onCapture: (result: PhotoCaptureResult) => void
  required?: boolean
  initialUrl?: string | null
}

// Captura foto desde camara movil + sube a calama-evidencias + reporta
// {url, storage_path, lat, lng} al consumidor. Online-first; en proxima
// iteracion se enchufa cola IndexedDB para offline.
export function PhotoCapture({
  label, momento, otId, planOtId, onCapture, required, initialUrl,
}: PhotoCaptureProps) {
  const inputRef = useRef<HTMLInputElement>(null)
  const [preview, setPreview] = useState<string | null>(initialUrl ?? null)
  const [uploading, setUploading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [result, setResult] = useState<PhotoCaptureResult | null>(
    initialUrl ? { url: initialUrl, storage_path: '', lat: null, lng: null } : null,
  )

  const handleFile = async (file: File) => {
    setError(null)
    setUploading(true)
    setPreview(URL.createObjectURL(file))
    try {
      const [{ url, storage_path }, gps] = await Promise.all([
        uploadEvidenciaJornada({
          blob: file, otId, planOtId, momento,
          ext: (file.name.split('.').pop() || 'jpg').toLowerCase(),
        }),
        tryGeolocate(),
      ])
      const r: PhotoCaptureResult = { url, storage_path, lat: gps.lat, lng: gps.lng }
      setResult(r)
      onCapture(r)
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : 'Error al subir foto'
      setError(msg)
      setPreview(null)
    } finally {
      setUploading(false)
    }
  }

  const reset = () => {
    setPreview(null); setResult(null); setError(null)
    if (inputRef.current) inputRef.current.value = ''
  }

  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between">
        <span className="text-xs font-medium text-gray-700">
          {label}{required && <span className="ml-1 text-red-600">*</span>}
        </span>
        {result && (
          <span className="inline-flex items-center gap-1 text-xs text-green-700">
            <Check className="h-3 w-3" /> Subida
          </span>
        )}
      </div>

      {preview ? (
        <div className="space-y-2">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={preview} alt={label} className="w-full max-h-56 object-cover rounded border border-gray-300" />
          {result?.lat && result?.lng && (
            <div className="text-[10px] text-gray-500 font-mono">
              GPS {result.lat.toFixed(5)}, {result.lng.toFixed(5)}
            </div>
          )}
          {!uploading && (
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

      {uploading && (
        <div className="flex items-center gap-2 text-xs text-amber-700">
          <Loader2 className="h-3 w-3 animate-spin" /> Subiendo evidencia...
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
