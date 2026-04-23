'use client'

import { useEffect, useRef, useState } from 'react'
import { Button } from './button'

interface SignaturePadProps {
  onCapture: (dataUrl: string) => void
  label?: string
  existingUrl?: string | null
}

// Canvas de firma a mano alzada — mouse + touch. Al guardar devuelve PNG
// en base64. El consumidor lo sube a storage y pasa la URL final al RPC.
export function SignaturePad({
  onCapture,
  label = 'Firma',
  existingUrl,
}: SignaturePadProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const [drawing, setDrawing] = useState(false)
  const [dirty, setDirty] = useState(false)
  const [dataUrl, setDataUrl] = useState<string | null>(existingUrl ?? null)

  // Inicializar canvas
  useEffect(() => {
    const c = canvasRef.current
    if (!c) return
    // Ajuste por DPI
    const rect = c.getBoundingClientRect()
    const dpr = window.devicePixelRatio || 1
    c.width = rect.width * dpr
    c.height = rect.height * dpr
    const ctx = c.getContext('2d')
    if (!ctx) return
    ctx.scale(dpr, dpr)
    ctx.lineWidth = 2
    ctx.lineCap = 'round'
    ctx.lineJoin = 'round'
    ctx.strokeStyle = '#111827'
    ctx.fillStyle = '#FFFFFF'
    ctx.fillRect(0, 0, rect.width, rect.height)
  }, [])

  const getPoint = (e: React.PointerEvent<HTMLCanvasElement>) => {
    const c = canvasRef.current!
    const rect = c.getBoundingClientRect()
    return { x: e.clientX - rect.left, y: e.clientY - rect.top }
  }

  const handleDown = (e: React.PointerEvent<HTMLCanvasElement>) => {
    e.preventDefault()
    const c = canvasRef.current
    if (!c) return
    c.setPointerCapture(e.pointerId)
    setDrawing(true)
    setDirty(true)
    const ctx = c.getContext('2d')
    const p = getPoint(e)
    if (ctx) {
      ctx.beginPath()
      ctx.moveTo(p.x, p.y)
    }
  }

  const handleMove = (e: React.PointerEvent<HTMLCanvasElement>) => {
    if (!drawing) return
    e.preventDefault()
    const c = canvasRef.current
    if (!c) return
    const ctx = c.getContext('2d')
    const p = getPoint(e)
    if (ctx) {
      ctx.lineTo(p.x, p.y)
      ctx.stroke()
    }
  }

  const handleUp = (e: React.PointerEvent<HTMLCanvasElement>) => {
    e.preventDefault()
    setDrawing(false)
    const c = canvasRef.current
    if (c) c.releasePointerCapture(e.pointerId)
  }

  const clear = () => {
    const c = canvasRef.current
    if (!c) return
    const ctx = c.getContext('2d')
    if (!ctx) return
    const rect = c.getBoundingClientRect()
    ctx.fillStyle = '#FFFFFF'
    ctx.fillRect(0, 0, rect.width, rect.height)
    setDirty(false)
    setDataUrl(null)
  }

  const save = () => {
    const c = canvasRef.current
    if (!c || !dirty) return
    const url = c.toDataURL('image/png')
    setDataUrl(url)
    onCapture(url)
  }

  return (
    <div className="space-y-2">
      <div className="text-xs font-medium text-gray-600">{label}</div>
      {dataUrl ? (
        <div className="space-y-2">
          <div className="rounded border border-gray-300 bg-white p-2">
            <img src={dataUrl} alt="Firma" className="h-24 object-contain mx-auto" />
          </div>
          <Button size="sm" variant="ghost" onClick={() => { setDataUrl(null); clear() }}>
            Firmar de nuevo
          </Button>
        </div>
      ) : (
        <>
          <canvas
            ref={canvasRef}
            className="h-32 w-full touch-none rounded border border-dashed border-gray-400 bg-white cursor-crosshair"
            onPointerDown={handleDown}
            onPointerMove={handleMove}
            onPointerUp={handleUp}
            onPointerLeave={handleUp}
          />
          <div className="flex gap-2">
            <Button size="sm" variant="ghost" onClick={clear} disabled={!dirty}>
              Borrar
            </Button>
            <Button size="sm" variant="primary" onClick={save} disabled={!dirty}>
              Guardar firma
            </Button>
          </div>
        </>
      )}
    </div>
  )
}
