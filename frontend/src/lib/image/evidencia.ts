// Subida de evidencias (fotos/video) del taller al bucket evidencias-verificacion.
//
// 2026-09-17, OT-202609-00037: un operador con iPhone marcó la entrega con
// fotos, en su teléfono se veían, pero al servidor no llegó NINGUNA — y ese
// usuario jamás había logrado subir una. El iPhone entrega la foto tal cual
// sale de la galería (HEIC, 3-6 MB) cuando el input acepta también video, y el
// bucket solo admitía JPG/PNG/WEBP: la subida rebotaba en la cola offline sin
// que nadie lo viera. Aquí toda imagen se lleva a JPEG liviano antes de subir,
// y si igual falla el error dice qué archivo era.

import { supabase } from '@/lib/supabase'
import { compressImage } from './compress'

const EXT_POR_MIME: Record<string, string> = {
  'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp',
  'image/heic': 'heic', 'image/heif': 'heif',
  'video/mp4': 'mp4', 'video/quicktime': 'mov', 'video/webm': 'webm',
}

/** Imagen → JPEG ≤1920 px. Video y lo que no se pueda decodificar vuelven intactos. */
export async function normalizarEvidencia(file: File | Blob): Promise<Blob> {
  if (file.type.startsWith('video/')) return file
  try {
    return await compressImage(file, { maxDim: 1920, quality: 0.8 })
  } catch {
    return file
  }
}

/** Normaliza y sube. `carpeta` sin barra final; devuelve la URL pública. */
export async function subirEvidencia(bucket: string, carpeta: string, file: File | Blob): Promise<string> {
  const blob = await normalizarEvidencia(file)
  const nombre = (file as File).name
  const mime = blob.type || (file as File).type || 'image/jpeg'
  const ext = EXT_POR_MIME[mime] ?? nombre?.split('.').pop()?.toLowerCase() ?? 'jpg'
  const rnd = Math.random().toString(36).slice(2, 8)
  const path = `${carpeta}_${Date.now()}_${rnd}.${ext}`
  const { error } = await supabase.storage.from(bucket).upload(path, blob, { upsert: false, contentType: mime })
  if (error) {
    const mb = (blob.size / 1_048_576).toFixed(1)
    throw new Error(`No se pudo subir la foto (${mime || 'sin tipo'}, ${mb} MB): ${error.message}`)
  }
  return supabase.storage.from(bucket).getPublicUrl(path).data.publicUrl
}
