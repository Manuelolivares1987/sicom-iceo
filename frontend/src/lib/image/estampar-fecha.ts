// ============================================================================
// Estampar la fecha y la hora sobre la foto (MIG389)
// ----------------------------------------------------------------------------
// El sistema ya guarda cuándo se sacó cada foto, pero ese dato vive en la base
// y se pierde en cuanto la imagen sale de acá: pegada en un correo, impresa en
// un informe o mandada por WhatsApp, vuelve a ser una foto sin fecha, y una
// foto sin fecha no prueba nada.
//
// La marca va SOBRE el pixel para que viaje con la imagen. No reemplaza al dato
// guardado —ése es el que vale para el sistema— pero hace que el papel diga lo
// mismo que la base.
//
// LA HORA ES LA DEL TELÉFONO, Y ASÍ SE DICE
// No hay forma de verificar el reloj del aparato desde el navegador. Estampar
// una hora como si fuera incuestionable sería fingir una garantía que no
// existe, así que el sistema guarda además la hora de llegada al servidor y las
// dos quedan a la vista.
// ============================================================================

export type FotoEstampada = {
  blob: Blob
  /** Cuándo se sacó, según el reloj del teléfono. */
  tomadaAt: string
  lat: number | null
  lng: number | null
}

/** La ubicación, si el aparato la da rápido. Nunca bloquea la captura. */
async function ubicacion(msTope = 4000): Promise<{ lat: number; lng: number } | null> {
  if (typeof navigator === 'undefined' || !navigator.geolocation) return null
  return new Promise((resolve) => {
    const t = setTimeout(() => resolve(null), msTope)
    navigator.geolocation.getCurrentPosition(
      (p) => { clearTimeout(t); resolve({ lat: p.coords.latitude, lng: p.coords.longitude }) },
      () => { clearTimeout(t); resolve(null) },
      { enableHighAccuracy: false, timeout: msTope, maximumAge: 60_000 },
    )
  })
}

/**
 * Escribe la fecha, la hora y —si la hay— la ubicación en la esquina de la
 * imagen, y la devuelve lista para subir.
 *
 * Si algo falla (un navegador sin canvas, una imagen que no carga) devuelve el
 * archivo original con su fecha: perder la foto por no poder estamparla sería
 * el peor intercambio posible.
 */
export async function estamparFechaHora(
  file: File | Blob,
  opts: { maxDim?: number; calidad?: number; etiqueta?: string } = {},
): Promise<FotoEstampada> {
  const maxDim = opts.maxDim ?? 1600
  const calidad = opts.calidad ?? 0.78
  const tomadaAt = new Date().toISOString()
  const geo = await ubicacion()

  try {
    const bitmap = await createImageBitmap(file as Blob)
    const escala = Math.min(1, maxDim / Math.max(bitmap.width, bitmap.height))
    const w = Math.round(bitmap.width * escala)
    const h = Math.round(bitmap.height * escala)

    const canvas = document.createElement('canvas')
    canvas.width = w
    canvas.height = h
    const ctx = canvas.getContext('2d')
    if (!ctx) throw new Error('sin canvas')
    ctx.drawImage(bitmap, 0, 0, w, h)
    bitmap.close?.()

    const fecha = new Date(tomadaAt)
    const linea1 = fecha.toLocaleString('es-CL', {
      day: '2-digit', month: '2-digit', year: 'numeric',
      hour: '2-digit', minute: '2-digit',
    })
    const linea2 = [
      opts.etiqueta,
      geo ? `${geo.lat.toFixed(5)}, ${geo.lng.toFixed(5)}` : null,
    ].filter(Boolean).join(' · ')

    // El tamaño sigue a la imagen: una marca fija se vuelve ilegible en una
    // foto grande y tapa media pantalla en una chica.
    const px = Math.max(14, Math.round(w * 0.028))
    const pad = Math.round(px * 0.5)
    ctx.font = `600 ${px}px system-ui, -apple-system, sans-serif`
    ctx.textBaseline = 'bottom'

    const anchos = [ctx.measureText(linea1).width, linea2 ? ctx.measureText(linea2).width : 0]
    const cajaW = Math.max(...anchos) + pad * 2
    const cajaH = px * (linea2 ? 2 : 1) + pad * (linea2 ? 2.2 : 1.6)
    const x = pad
    const y = h - pad

    // Banda oscura detrás: sin ella el texto desaparece sobre un piso claro.
    ctx.fillStyle = 'rgba(0, 0, 0, 0.55)'
    ctx.fillRect(x - pad / 2, y - cajaH, cajaW, cajaH)

    ctx.fillStyle = '#ffffff'
    if (linea2) {
      ctx.fillText(linea2, x + pad / 2, y - pad / 2)
      ctx.fillText(linea1, x + pad / 2, y - pad / 2 - px * 1.15)
    } else {
      ctx.fillText(linea1, x + pad / 2, y - pad / 2)
    }

    const blob = await new Promise<Blob | null>((res) =>
      canvas.toBlob(res, 'image/jpeg', calidad))
    if (!blob) throw new Error('no se pudo generar')

    return { blob, tomadaAt, lat: geo?.lat ?? null, lng: geo?.lng ?? null }
  } catch {
    // Falla segura: la foto original, con su fecha igual registrada.
    return { blob: file as Blob, tomadaAt, lat: geo?.lat ?? null, lng: geo?.lng ?? null }
  }
}
