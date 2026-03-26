'use client'

import { useState, useEffect, useRef, useCallback } from 'react'
import { Html5Qrcode, Html5QrcodeScannerState } from 'html5-qrcode'

interface UseScannerOptions {
  /** Element ID where the camera preview will render */
  elementId?: string
  /** Preferred camera facing mode */
  facingMode?: 'environment' | 'user'
  /** Frames per second for scanning */
  fps?: number
  /** QR box size in pixels */
  qrbox?: number | { width: number; height: number }
}

interface UseScannerReturn {
  startScanning: () => Promise<void>
  stopScanning: () => Promise<void>
  isScanning: boolean
  error: string | null
}

const WEDGE_THRESHOLD_MS = 50 // Max time between keystrokes for barcode wedge
const WEDGE_MIN_LENGTH = 4 // Minimum characters for a valid barcode

/**
 * Hook for barcode scanning using html5-qrcode (camera) and keyboard wedge
 * detection (pistola/barcode gun that emulates fast keystrokes).
 */
export function useScanner(
  onScan: (code: string) => void,
  options: UseScannerOptions = {}
): UseScannerReturn {
  const {
    elementId = 'scanner-region',
    facingMode = 'environment',
    fps = 10,
    qrbox = { width: 250, height: 250 },
  } = options

  const [isScanning, setIsScanning] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const scannerRef = useRef<Html5Qrcode | null>(null)
  const onScanRef = useRef(onScan)
  onScanRef.current = onScan

  // ── Keyboard wedge detection (pistola) ─────────────────
  const wedgeBufferRef = useRef('')
  const wedgeTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const lastKeystrokeRef = useRef(0)

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      const now = Date.now()
      const elapsed = now - lastKeystrokeRef.current
      lastKeystrokeRef.current = now

      // If too much time passed, reset buffer
      if (elapsed > WEDGE_THRESHOLD_MS) {
        wedgeBufferRef.current = ''
      }

      // Enter key = end of barcode from pistola
      if (e.key === 'Enter') {
        if (wedgeBufferRef.current.length >= WEDGE_MIN_LENGTH) {
          e.preventDefault()
          onScanRef.current(wedgeBufferRef.current)
        }
        wedgeBufferRef.current = ''
        return
      }

      // Only accumulate printable single characters
      if (e.key.length === 1) {
        wedgeBufferRef.current += e.key

        // Auto-clear buffer after a pause (in case Enter never comes)
        if (wedgeTimerRef.current) {
          clearTimeout(wedgeTimerRef.current)
        }
        wedgeTimerRef.current = setTimeout(() => {
          wedgeBufferRef.current = ''
        }, 200)
      }
    }

    window.addEventListener('keydown', handleKeyDown)
    return () => {
      window.removeEventListener('keydown', handleKeyDown)
      if (wedgeTimerRef.current) {
        clearTimeout(wedgeTimerRef.current)
      }
    }
  }, [])

  // ── Camera scanning ────────────────────────────────────

  const startScanning = useCallback(async () => {
    setError(null)

    try {
      if (!scannerRef.current) {
        scannerRef.current = new Html5Qrcode(elementId)
      }

      const scanner = scannerRef.current

      // Check if already scanning
      if (scanner.getState() === Html5QrcodeScannerState.SCANNING) {
        return
      }

      await scanner.start(
        { facingMode },
        { fps, qrbox },
        (decodedText) => {
          onScanRef.current(decodedText)
        },
        // Ignore scan failures (expected when no code is in view)
        undefined
      )

      setIsScanning(true)
    } catch (err) {
      const message =
        err instanceof Error ? err.message : 'Error al iniciar la camara'

      // Provide user-friendly error for common permission issues
      if (message.includes('NotAllowedError') || message.includes('Permission')) {
        setError(
          'Permiso de camara denegado. Por favor habilite el acceso a la camara en la configuracion del navegador.'
        )
      } else if (message.includes('NotFoundError')) {
        setError('No se encontro una camara disponible en este dispositivo.')
      } else {
        setError(message)
      }

      setIsScanning(false)
    }
  }, [elementId, facingMode, fps, qrbox])

  const stopScanning = useCallback(async () => {
    try {
      const scanner = scannerRef.current
      if (scanner && scanner.getState() === Html5QrcodeScannerState.SCANNING) {
        await scanner.stop()
      }
    } catch {
      // Ignore stop errors
    } finally {
      setIsScanning(false)
    }
  }, [])

  // ── Cleanup on unmount ─────────────────────────────────
  useEffect(() => {
    return () => {
      if (wedgeTimerRef.current) {
        clearTimeout(wedgeTimerRef.current)
      }
      const scanner = scannerRef.current
      if (scanner) {
        try {
          if (scanner.getState() === Html5QrcodeScannerState.SCANNING) {
            scanner.stop().catch(() => {})
          }
        } catch {
          // Ignore cleanup errors
        }
        scannerRef.current = null
      }
    }
  }, [])

  return { startScanning, stopScanning, isScanning, error }
}
