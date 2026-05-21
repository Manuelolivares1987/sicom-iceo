// Compresion de imagenes en el navegador para reducir el peso antes de subir
// a Supabase Storage. Pensado para fotos de terreno (4-12MB) en faena con
// señal debil. Falla "segura": si algo sale mal, devuelve el blob original.

export type CompressOptions = {
  // Dimension maxima del lado mayor (px). Default 1600 (apto evidencia HD).
  maxDim?: number
  // Calidad JPEG/WebP 0..1. Ignorado para PNG. Default 0.75.
  quality?: number
  // Tipo de salida. Default 'image/jpeg'. PNG preserva trazos finos (firmas).
  mimeType?: 'image/jpeg' | 'image/webp' | 'image/png'
  // Si el blob original ya es menor que esto y mimeType coincide, no recomprime.
  // Default 350_000 (350KB).
  skipUnderBytes?: number
}

export async function compressImage(
  input: File | Blob,
  opts: CompressOptions = {},
): Promise<Blob> {
  const maxDim = opts.maxDim ?? 1600
  const quality = opts.quality ?? 0.75
  const mimeType = opts.mimeType ?? 'image/jpeg'
  const skipUnderBytes = opts.skipUnderBytes ?? 350_000

  if (!input.type.startsWith('image/')) return input
  if (input.size <= skipUnderBytes && input.type === mimeType) return input

  const bitmap = await loadBitmap(input)
  if (!bitmap) return input

  const srcW = 'width' in bitmap ? bitmap.width : (bitmap as HTMLImageElement).naturalWidth
  const srcH = 'height' in bitmap ? bitmap.height : (bitmap as HTMLImageElement).naturalHeight
  if (!srcW || !srcH) {
    closeBitmap(bitmap)
    return input
  }

  const scale = Math.min(1, maxDim / Math.max(srcW, srcH))
  const w = Math.max(1, Math.round(srcW * scale))
  const h = Math.max(1, Math.round(srcH * scale))

  try {
    const out = await encodeToBlob(bitmap, w, h, mimeType, quality)
    closeBitmap(bitmap)
    if (!out) return input
    return out.size < input.size ? out : input
  } catch {
    closeBitmap(bitmap)
    return input
  }
}

async function loadBitmap(
  input: File | Blob,
): Promise<ImageBitmap | HTMLImageElement | null> {
  if (typeof createImageBitmap === 'function') {
    try {
      return await createImageBitmap(input, {
        imageOrientation: 'from-image',
      } as ImageBitmapOptions)
    } catch {
      // fall through
    }
  }
  if (typeof document === 'undefined') return null
  const url = URL.createObjectURL(input)
  try {
    const img = new Image()
    img.decoding = 'async'
    img.src = url
    await img.decode()
    return img
  } catch {
    URL.revokeObjectURL(url)
    return null
  } finally {
    setTimeout(() => URL.revokeObjectURL(url), 10_000)
  }
}

function closeBitmap(bitmap: ImageBitmap | HTMLImageElement): void {
  if ('close' in bitmap && typeof bitmap.close === 'function') bitmap.close()
}

async function encodeToBlob(
  bitmap: ImageBitmap | HTMLImageElement,
  w: number,
  h: number,
  mimeType: string,
  quality: number,
): Promise<Blob | null> {
  if (typeof OffscreenCanvas !== 'undefined') {
    try {
      const canvas = new OffscreenCanvas(w, h)
      const ctx = canvas.getContext('2d')
      if (!ctx) throw new Error('no 2d context')
      ctx.drawImage(bitmap as CanvasImageSource, 0, 0, w, h)
      return await canvas.convertToBlob({ type: mimeType, quality })
    } catch {
      // fall back to DOM canvas
    }
  }
  if (typeof document === 'undefined') return null
  const canvas = document.createElement('canvas')
  canvas.width = w
  canvas.height = h
  const ctx = canvas.getContext('2d')
  if (!ctx) return null
  ctx.drawImage(bitmap as CanvasImageSource, 0, 0, w, h)
  return await new Promise<Blob | null>((resolve) =>
    canvas.toBlob(resolve, mimeType, quality),
  )
}
