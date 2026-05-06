'use client'

import { useRef, useState } from 'react'
import { Camera, RotateCcw, Check, AlertCircle, Loader2 } from 'lucide-react'
import { uploadEvidenciaJornada, tryGeolocate, type EvidenciaMomento } from '@/lib/services/calama-jornada'
import { Button } from '@/components/ui/button'

export type PhotoCaptureResult = {
  // Modo 'direct': url y storage_path llenos (subido a Storage).
  // Modo 'capture': url='' y storage_path='', blob no-null.
  url: string
  storage_path: string
  blob: Blob | null
  lat: number | null
  lng: number | null
  accuracy?: number | null
  geolocation_status?: string | null
}

interface PhotoCaptureProps {
  label: string
  momento: EvidenciaMomento
  otId: string
  planOtId: string
  onCapture: (result: PhotoCaptureResult) => void
  required?: boolean
  initialUrl?: string | null
  // 'direct' (default): sube a Storage al capturar; devuelve url+path. Compatible online.
  // 'capture': solo captura Blob + GPS, NO sube; el consumer decide. Requerido para offline-first.
  mode?: 'direct' | 'capture'
}

export function PhotoCapture({
  label, momento, otId, planOtId, onCapture, required, initialUrl,
  mode = 'direct',
}: PhotoCaptureProps) {
  const inputRef = useRef<HTMLInputElement>(null)
  const [preview, setPreview] = useState<string | null>(initialUrl ?? null)
  const [uploading, setUploading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [captured, setCaptured] = useState<boolean>(!!initialUrl)
  const [resultMode, setResultMode] = useState<'direct' | 'capture' | null>(initialUrl ? 'direct' : null)

  const handleFile = async (file: File) => {
    setError(null)
    setPreview(URL.createObjectURL(file))
    try {
      const gps = await tryGeolocate()
      if (mode === 'capture') {
        const r: PhotoCaptureResult = {
          url: '', storage_path: '', blob: file,
          lat: gps.lat, lng: gps.lng, accuracy: gps.accuracy, geolocation_status: gps.status,
        }
        setCaptured(true); setResultMode('capture')
        onCapture(r)
      } else {
        setUploading(true)
        const { url, storage_path } = await uploadEvidenciaJornada({
          blob: file, otId, planOtId, momento,
          ext: (file.name.split('.').pop() || 'jpg').toLowerCase(),
        })
        const r: PhotoCaptureResult = {
          url, storage_path, blob: file,
          lat: gps.lat, lng: gps.lng, accuracy: gps.accuracy, geolocation_status: gps.status,
        }
        setCaptured(true); setResultMode('direct')
        onCapture(r)
      }
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : 'Error al procesar foto'
      setError(msg)
      setPreview(null)
    } finally {
      setUploading(false)
    }
  }

  const reset = () => {
    setPreview(null); setCaptured(false); setResultMode(null); setError(null)
    if (inputRef.current) inputRef.current.value = ''
  }

  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between">
        <span className="text-xs font-medium text-gray-700">
          {label}{required && <span className="ml-1 text-red-600">*</span>}
        </span>
        {captured && (
          <span className="inline-flex items-center gap-1 text-xs text-green-700">
            <Check className="h-3 w-3" />
            {resultMode === 'capture' ? 'Capturada' : 'Subida'}
          </span>
        )}
      </div>

      {preview ? (
        <div className="space-y-2">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={preview} alt={label} className="w-full max-h-56 object-cover rounded border border-gray-300" />
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
