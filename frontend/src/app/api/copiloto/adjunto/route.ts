import { NextResponse } from 'next/server'
import { randomUUID } from 'node:crypto'
import { autenticar, corpusCliente, BUCKET_ADJUNTOS, TIPOS_ADJUNTO, MAX_BYTES_ADJUNTO } from '@/lib/copiloto/server'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

// ============================================================================
// Copiloto — adjuntos del mecánico (2026-09-19).
// Manuel: «que el mecánico pueda subir fotos o archivos desde su teléfono».
// Devuelve una URL firmada para que el teléfono suba DIRECTO al storage del
// corpus (Netlify corta los requests en ~6 MB; un PDF de manual pesa más).
// La ruta queda bajo <uid>/ y /api/copiloto/consulta solo acepta rutas del
// mismo usuario.
// ============================================================================

export async function POST(req: Request) {
  const auth = await autenticar(req)
  if ('error' in auth) return NextResponse.json({ error: auth.error }, { status: auth.status })

  let body: { nombre?: string; tipo?: string; bytes?: number; activoId?: string; proponer?: boolean }
  try { body = await req.json() } catch { return NextResponse.json({ error: 'JSON inválido.' }, { status: 400 }) }
  const tipo = (body.tipo ?? '').toLowerCase()
  if (!TIPOS_ADJUNTO.includes(tipo)) {
    return NextResponse.json({ error: 'Solo fotos (JPG, PNG, WEBP) o PDF.' }, { status: 400 })
  }
  if (!body.bytes || body.bytes > MAX_BYTES_ADJUNTO) {
    return NextResponse.json({ error: 'El archivo supera 20 MB.' }, { status: 400 })
  }
  const corpus = corpusCliente()
  if (!corpus) return NextResponse.json({ error: 'El almacenamiento del copiloto no está disponible.' }, { status: 503 })

  const nombre = (body.nombre ?? 'archivo').replace(/[^\w.\- ()áéíóúñÁÉÍÓÚÑ]/g, '_').slice(0, 120) || 'archivo'
  const ext = tipo === 'application/pdf' ? 'pdf' : tipo.split('/')[1]
  const path = `${auth.uid}/${new Date().toISOString().slice(0, 10)}/${randomUUID()}.${ext}`

  const { data, error } = await corpus.storage.from(BUCKET_ADJUNTOS).createSignedUploadUrl(path)
  if (error || !data) return NextResponse.json({ error: 'No se pudo preparar la subida.' }, { status: 502 })

  await corpus.from('copiloto_adjuntos').insert({
    usuario_id: auth.uid, activo_id: body.activoId ?? null, storage_path: path, nombre, tipo,
    bytes: body.bytes, propuesto_biblioteca: !!body.proponer,
  })
  return NextResponse.json({ path, uploadUrl: data.signedUrl, nombre, tipo })
}

// Proponer (o retirar) un adjunto propio a la biblioteca del taller: un PDF
// (manual, informe) o una FOTO con su descripción (etiqueta de fusibles en la
// tapa, placa del motor/bomba/grúa, diagrama pegado en el equipo).
// Jefatura lo revisa e ingiere con: copiloto-conocimiento.mjs --aportes
export async function PATCH(req: Request) {
  const auth = await autenticar(req)
  if ('error' in auth) return NextResponse.json({ error: auth.error }, { status: auth.status })
  let body: { path?: string; proponer?: boolean; descripcion?: string }
  try { body = await req.json() } catch { return NextResponse.json({ error: 'JSON inválido.' }, { status: 400 }) }
  if (!body.path?.startsWith(`${auth.uid}/`)) return NextResponse.json({ error: 'No autorizado.' }, { status: 403 })
  const descripcion = (body.descripcion ?? '').trim().slice(0, 500) || null
  const corpus = corpusCliente()
  if (!corpus) return NextResponse.json({ error: 'No disponible.' }, { status: 503 })
  const { error } = await corpus.from('copiloto_adjuntos')
    .update({ propuesto_biblioteca: !!body.proponer, ...(descripcion ? { descripcion } : {}) })
    .eq('storage_path', body.path).eq('usuario_id', auth.uid)
  if (error) return NextResponse.json({ error: 'No se pudo marcar.' }, { status: 502 })
  return NextResponse.json({ ok: true })
}
