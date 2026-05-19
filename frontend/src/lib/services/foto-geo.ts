// frontend/src/lib/services/foto-geo.ts
// MIG66: Captura de foto con GPS + overlay anti-reciclaje.
//
// Flujo:
//   1. Pide navigator.geolocation.getCurrentPosition (high accuracy).
//   2. Lee la imagen original a un canvas.
//   3. Estampa overlay con fecha/hora/lat-lon/usuario en la esquina inferior.
//   4. Devuelve { blob, lat, lon, ts, accuracy } para que el caller lo suba.
//
// Si el navegador rechaza la geolocalizacion (permiso denegado, timeout, etc)
// la promesa se rechaza con FotoGeoError. El form debe bloquear el submit.

export interface FotoGeoResult {
  blob:     Blob
  lat:      number
  lon:      number
  ts:       string   // ISO 8601 del momento de la captura
  accuracy: number   // metros
}

export interface FotoGeoContext {
  usuarioEmail?: string | null
  contexto?:     string | null   // ej: "Ingreso combustible · ICB-20260519"
}

export class FotoGeoError extends Error {
  code: 'geo_denied' | 'geo_timeout' | 'geo_unsupported' | 'image_load' | 'canvas'
  constructor(code: FotoGeoError['code'], message: string) {
    super(message)
    this.code = code
  }
}

function getPosition(): Promise<GeolocationPosition> {
  return new Promise((resolve, reject) => {
    if (typeof navigator === 'undefined' || !navigator.geolocation) {
      reject(new FotoGeoError('geo_unsupported', 'Geolocalizacion no soportada por el navegador.'))
      return
    }
    navigator.geolocation.getCurrentPosition(
      resolve,
      (err) => {
        if (err.code === err.PERMISSION_DENIED) {
          reject(new FotoGeoError('geo_denied', 'Permiso de ubicacion denegado. Habilita el GPS para evitar fraude.'))
        } else if (err.code === err.TIMEOUT) {
          reject(new FotoGeoError('geo_timeout', 'No se pudo obtener la ubicacion (timeout). Reintenta al aire libre.'))
        } else {
          reject(new FotoGeoError('geo_timeout', err.message || 'No se pudo obtener la ubicacion.'))
        }
      },
      { enableHighAccuracy: true, timeout: 15000, maximumAge: 0 },
    )
  })
}

function fileToImage(file: File): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file)
    const img = new Image()
    img.onload = () => { resolve(img); URL.revokeObjectURL(url) }
    img.onerror = () => {
      URL.revokeObjectURL(url)
      reject(new FotoGeoError('image_load', 'No se pudo leer la imagen.'))
    }
    img.src = url
  })
}

function canvasToBlob(canvas: HTMLCanvasElement, mime = 'image/jpeg', quality = 0.85): Promise<Blob> {
  return new Promise((resolve, reject) => {
    canvas.toBlob(
      (b) => b ? resolve(b) : reject(new FotoGeoError('canvas', 'No se pudo serializar la imagen.')),
      mime, quality,
    )
  })
}

/**
 * Captura una foto con geo + overlay. La foto subida YA trae el sello.
 */
export async function capturarFotoConGeo(file: File, ctx: FotoGeoContext = {}): Promise<FotoGeoResult> {
  // 1) Geo primero (si falla, no procesamos imagen)
  const pos = await getPosition()
  const lat = pos.coords.latitude
  const lon = pos.coords.longitude
  const accuracy = pos.coords.accuracy
  const ts = new Date().toISOString()

  // 2) Imagen → canvas
  const img = await fileToImage(file)
  // Limitar tamaño máx (lado largo 1600 px) para no inflar storage
  const MAX = 1600
  let w = img.naturalWidth, h = img.naturalHeight
  if (Math.max(w, h) > MAX) {
    const scale = MAX / Math.max(w, h)
    w = Math.round(w * scale)
    h = Math.round(h * scale)
  }

  const canvas = document.createElement('canvas')
  canvas.width = w; canvas.height = h
  const cx = canvas.getContext('2d')
  if (!cx) throw new FotoGeoError('canvas', 'Canvas no disponible.')
  cx.drawImage(img, 0, 0, w, h)

  // 3) Overlay (caja semitransparente abajo)
  const padding = Math.round(w * 0.012)
  const fontSize = Math.max(14, Math.round(w * 0.022))
  cx.font = `bold ${fontSize}px system-ui, sans-serif`
  const lines = [
    `${new Date(ts).toLocaleString('es-CL', { hour12: false })}`,
    `Lat ${lat.toFixed(6)}, Lon ${lon.toFixed(6)} (±${Math.round(accuracy)} m)`,
    ctx.usuarioEmail ? `Usuario: ${ctx.usuarioEmail}` : null,
    ctx.contexto ? `${ctx.contexto}` : null,
    `Pillado · evidencia firmada`,
  ].filter(Boolean) as string[]

  const lineH = Math.round(fontSize * 1.25)
  const boxH = lineH * lines.length + padding * 2
  cx.fillStyle = 'rgba(0,0,0,0.55)'
  cx.fillRect(0, h - boxH, w, boxH)

  cx.fillStyle = '#FFFFFF'
  cx.textBaseline = 'top'
  lines.forEach((ln, i) => {
    cx.fillText(ln, padding, h - boxH + padding + i * lineH)
  })

  // Banner pequeño en esquina superior con marca + timestamp
  const banner = `PILLADO · ${new Date(ts).toLocaleString('es-CL', { hour12: false })}`
  cx.font = `bold ${Math.round(fontSize * 0.8)}px system-ui, sans-serif`
  const bw = cx.measureText(banner).width + padding * 2
  cx.fillStyle = 'rgba(45,139,61,0.85)' // verde Pillado
  cx.fillRect(0, 0, bw, Math.round(fontSize * 1.6))
  cx.fillStyle = '#FFFFFF'
  cx.fillText(banner, padding, padding * 0.6)

  const blob = await canvasToBlob(canvas, 'image/jpeg', 0.82)
  return { blob, lat, lon, ts, accuracy }
}
