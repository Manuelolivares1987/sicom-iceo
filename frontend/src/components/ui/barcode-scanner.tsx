'use client'

import { useEffect, useRef, useState } from 'react'
import { Camera, X } from 'lucide-react'
import { Button } from './button'

interface Props {
  onScan: (code: string) => void
  onClose?: () => void
  active?: boolean
}

// Scanner de código de barras / QR usando la cámara (html5-qrcode).
// Soporta EAN-13, EAN-8, Code-128, QR, etc. La primera vez pide
// permiso de cámara.
export function BarcodeScanner({ onScan, onClose, active = true }: Props) {
  const containerRef = useRef<HTMLDivElement>(null)
  const scannerRef = useRef<any>(null)
  const [ready, setReady] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (!active || !containerRef.current) return
    let cancelled = false

    // Dynamic import para que no bloquee SSR
    import('html5-qrcode').then(({ Html5Qrcode }) => {
      if (cancelled || !containerRef.current) return
      const id = 'html5qr-box'
      containerRef.current.id = id
      const scanner = new Html5Qrcode(id, { verbose: false })
      scannerRef.current = scanner

      scanner
        .start(
          { facingMode: 'environment' },
          { fps: 10, qrbox: { width: 260, height: 140 } },
          (decoded) => {
            onScan(decoded)
          },
          () => {/* ignore per-frame errors */},
        )
        .then(() => {
          if (!cancelled) setReady(true)
        })
        .catch((err: unknown) => {
          setError(err instanceof Error ? err.message : 'Error al acceder a la cámara')
        })
    }).catch((err) => {
      setError(err instanceof Error ? err.message : 'Lib scanner no disponible')
    })

    return () => {
      cancelled = true
      if (scannerRef.current) {
        try { scannerRef.current.stop().catch(() => {}) } catch { /* empty */ }
        try { scannerRef.current.clear() } catch { /* empty */ }
      }
    }
  }, [active, onScan])

  return (
    <div className="relative rounded-lg border bg-black p-2">
      <div ref={containerRef} className="mx-auto aspect-video w-full max-w-md overflow-hidden rounded bg-black" />
      {!ready && !error && (
        <div className="absolute inset-0 flex items-center justify-center text-white">
          <Camera className="h-6 w-6 animate-pulse" />
          <span className="ml-2 text-sm">Activando cámara…</span>
        </div>
      )}
      {error && (
        <div className="absolute inset-0 flex items-center justify-center">
          <div className="rounded bg-red-600 px-3 py-2 text-sm text-white">{error}</div>
        </div>
      )}
      {onClose && (
        <Button
          variant="ghost"
          size="sm"
          className="absolute right-2 top-2 text-white hover:bg-white/10"
          onClick={onClose}
        >
          <X className="h-4 w-4" />
        </Button>
      )}
      <p className="mt-2 text-center text-xs text-gray-300">
        Apunta el código de barras dentro del recuadro. Detecta EAN-13, Code-128, QR.
      </p>
    </div>
  )
}
