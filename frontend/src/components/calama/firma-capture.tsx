'use client'

import { useState } from 'react'
import { Check, AlertCircle, Loader2 } from 'lucide-react'
import { SignaturePad } from '@/components/ui/signature-pad'
import { uploadFirmaJornada, type FirmaContexto } from '@/lib/services/calama-jornada'

export type FirmaCaptureResult = {
  url: string
  storage_path: string
  dataUrl: string
}

interface FirmaCaptureProps {
  label: string
  contexto: FirmaContexto
  otId: string
  planOtId: string
  onCapture: (result: FirmaCaptureResult) => void
  required?: boolean
}

// Captura firma a mano alzada via SignaturePad y la sube al bucket
// calama-firmas. Devuelve {url, storage_path} para que el caller lo
// envie al RPC.
export function FirmaCapture({
  label, contexto, otId, planOtId, onCapture, required,
}: FirmaCaptureProps) {
  const [uploading, setUploading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [result, setResult] = useState<FirmaCaptureResult | null>(null)

  const handleSign = async (dataUrl: string) => {
    setError(null)
    setUploading(true)
    try {
      const { url, storage_path } = await uploadFirmaJornada({
        dataUrl, otId, planOtId, contexto,
      })
      const r: FirmaCaptureResult = { url, storage_path, dataUrl }
      setResult(r)
      onCapture(r)
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : 'Error al subir firma'
      setError(msg)
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
        {result && (
          <span className="inline-flex items-center gap-1 text-xs text-green-700">
            <Check className="h-3 w-3" /> Firma subida
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
