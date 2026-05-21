'use client'

import { useState } from 'react'
import { Check, AlertCircle, Loader2 } from 'lucide-react'
import { SignaturePad } from '@/components/ui/signature-pad'
import { uploadFirmaJornada, type FirmaContexto } from '@/lib/services/calama-jornada'
import { compressImage } from '@/lib/image/compress'

export type FirmaCaptureResult = {
  // Modo 'direct': url y storage_path llenos.
  // Modo 'capture': url='' y storage_path='', blob no-null.
  url: string
  storage_path: string
  blob: Blob | null
  dataUrl: string
}

interface FirmaCaptureProps {
  label: string
  contexto: FirmaContexto
  otId: string
  planOtId: string
  onCapture: (result: FirmaCaptureResult) => void
  required?: boolean
  mode?: 'direct' | 'capture'
}

function dataUrlToBlob(dataUrl: string): Blob {
  const base64 = dataUrl.split(',')[1] ?? ''
  const bin = atob(base64)
  const buf = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i)
  return new Blob([buf], { type: 'image/png' })
}

export function FirmaCapture({
  label, contexto, otId, planOtId, onCapture, required, mode = 'direct',
}: FirmaCaptureProps) {
  const [uploading, setUploading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [done, setDone] = useState(false)

  const handleSign = async (dataUrl: string) => {
    setError(null)
    try {
      const raw = dataUrlToBlob(dataUrl)
      // Encoge la firma (HiDPI da PNG de ~30KB; lo bajamos a ~5-10KB) para que
      // el bundle foto+firma viaje rapido en faena con señal debil.
      let blob: Blob = raw
      try {
        blob = await compressImage(raw, { maxDim: 800, mimeType: 'image/png', skipUnderBytes: 0 })
      } catch { /* keep original */ }
      if (mode === 'capture') {
        onCapture({ url: '', storage_path: '', blob, dataUrl })
        setDone(true)
        return
      }
      setUploading(true)
      const { url, storage_path } = await uploadFirmaJornada({
        blob, otId, planOtId, contexto,
      })
      onCapture({ url, storage_path, blob, dataUrl })
      setDone(true)
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : 'Error al procesar firma')
    } finally {
      setUploading(false)
    }
  }

  return (
    <div className="space-y-2 rounded border border-gray-200 bg-white p-3">
      <div className="flex items-center justify-between">
        <span className="text-xs font-medium text-gray-700">
          {label}{required && <span className="ml-1 text-red-600">*</span>}
        </span>
        {done && (
          <span className="inline-flex items-center gap-1 text-xs text-green-700">
            <Check className="h-3 w-3" /> Firma {mode === 'capture' ? 'capturada' : 'subida'}
          </span>
        )}
      </div>

      <SignaturePad onCapture={handleSign} label="" />

      {uploading && (
        <div className="flex items-center gap-2 text-xs text-amber-700">
          <Loader2 className="h-3 w-3 animate-spin" /> Subiendo firma...
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
