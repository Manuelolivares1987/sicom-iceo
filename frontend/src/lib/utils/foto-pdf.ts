// ============================================================================
// Fotos para PDFs (react-pdf) — extraído del informe ENEX (PR #114), donde
// estas tres lecciones se pagaron caras:
//  · react-pdf se CUELGA (promesa que nunca resuelve) si su fetch interno de
//    una imagen remota falla: todo se convierte a data URL antes, con timeout.
//  · las fotos de cámara llegan sin comprimir (~2,3 MB c/u): embebidas tal
//    cual, el PDF se va a los cientos de MB y nunca termina de generarse.
//  · comprimir con toDataURL es SÍNCRONO y congela la pestaña: lo liviano
//    pasa directo y lo pesado va por OffscreenCanvas (asíncrono).
// ============================================================================

/** Descarga una URL y la vuelve data URL, con timeout. null si falla. */
export async function aDataUrl(url: string | null | undefined, timeoutMs = 8000): Promise<string | null> {
  if (!url) return null
  try {
    const ctl = new AbortController()
    const t = setTimeout(() => ctl.abort(), timeoutMs)
    const res = await fetch(url, { signal: ctl.signal })
    clearTimeout(t)
    if (!res.ok) return null
    const blob = await res.blob()
    return await new Promise((resolve) => {
      const fr = new FileReader()
      fr.onload = () => resolve(fr.result as string)
      fr.onerror = () => resolve(null)
      fr.readAsDataURL(blob)
    })
  } catch { return null }
}

/** Bytes reales de un data URL (base64 infla ~4/3). */
const pesoDataUrl = (s: string) => Math.round((s.length - (s.indexOf(',') + 1)) * 0.75)

const LIVIANA_BYTES = 500_000

/** Data URL comprimida: lo liviano pasa directo, lo pesado se reescala. */
export async function aDataUrlComprimida(
  url: string | null | undefined, maxPx = 1400, calidad = 0.72,
): Promise<string | null> {
  const original = await aDataUrl(url, 20_000)
  if (!original) return null
  if (pesoDataUrl(original) <= LIVIANA_BYTES) return original

  let bitmap: ImageBitmap | null = null
  try {
    const blob = await (await fetch(original)).blob()
    bitmap = await createImageBitmap(blob)
    const escala = Math.min(1, maxPx / Math.max(bitmap.width, bitmap.height))
    const w = Math.max(1, Math.round(bitmap.width * escala))
    const h = Math.max(1, Math.round(bitmap.height * escala))

    if (typeof OffscreenCanvas !== 'undefined') {
      const cv = new OffscreenCanvas(w, h)
      const ctx = cv.getContext('2d')
      if (!ctx) return original
      ctx.drawImage(bitmap, 0, 0, w, h)
      const out = await cv.convertToBlob({ type: 'image/jpeg', quality: calidad })
      return await new Promise<string>((resolve) => {
        const fr = new FileReader()
        fr.onload = () => resolve(fr.result as string)
        fr.onerror = () => resolve(original)
        fr.readAsDataURL(out)
      })
    }

    // Sin OffscreenCanvas (Safari antiguo): canvas normal, asumiendo el bloqueo.
    const cv = document.createElement('canvas')
    cv.width = w; cv.height = h
    const ctx = cv.getContext('2d')
    if (!ctx) return original
    ctx.drawImage(bitmap, 0, 0, w, h)
    return cv.toDataURL('image/jpeg', calidad)
  } catch {
    return original   // si el canvas falla, mejor pesada que ausente
  } finally {
    bitmap?.close()
  }
}

/** Procesa en paralelo con tope, cediendo el hilo entre elementos. */
export async function enLotes<T, R>(
  xs: T[], n: number, fn: (x: T) => Promise<R>,
): Promise<R[]> {
  const out: R[] = new Array(xs.length)
  let i = 0
  await Promise.all(Array.from({ length: Math.min(n, xs.length) }, async () => {
    while (i < xs.length) {
      const k = i++
      out[k] = await fn(xs[k])
      await new Promise((r) => setTimeout(r, 0))
    }
  }))
  return out
}
