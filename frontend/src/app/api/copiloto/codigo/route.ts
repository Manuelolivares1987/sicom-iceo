import { NextResponse } from 'next/server'
import { autenticar, corpusCliente, slug, buscarCodigo } from '@/lib/copiloto/server'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

// ============================================================================
// Copiloto — búsqueda DIRECTA de códigos de falla (sin IA, instantánea).
// El mecánico escribe "3251 0" o "SPN 3251 FMI 0" y ve significado, causas y
// comprobaciones con su fuente. Si quiere más, lo pasa al copiloto.
// ============================================================================

export async function POST(req: Request) {
  const auth = await autenticar(req)
  if ('error' in auth) return NextResponse.json({ error: auth.error }, { status: auth.status })

  let body: { texto?: string; activoId?: string }
  try { body = await req.json() } catch { return NextResponse.json({ error: 'JSON inválido.' }, { status: 400 }) }
  const texto = (body.texto ?? '').trim()
  if (texto.length < 2) return NextResponse.json({ error: 'Escribe el código.' }, { status: 400 })

  const corpus = corpusCliente()
  if (!corpus) return NextResponse.json({ error: 'La tabla de códigos aún no está disponible.' }, { status: 503 })

  let marca: string | null = null
  if (body.activoId) {
    const { data } = await auth.sb.from('activos')
      .select('modelo:modelos(marca:marcas(nombre))').eq('id', body.activoId).maybeSingle()
    const m = (data as { modelo?: { marca?: { nombre?: string } } } | null)?.modelo?.marca?.nombre
    marca = slug(m)
  }
  try {
    const codigos = await buscarCodigo(corpus, texto, marca, 12)
    return NextResponse.json({ codigos, marca })
  } catch {
    return NextResponse.json({ error: 'No se pudo consultar la tabla de códigos.' }, { status: 502 })
  }
}
