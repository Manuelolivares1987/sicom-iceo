import { NextResponse } from 'next/server'
import { autenticar, corpusCliente, fichaEquipo } from '@/lib/copiloto/server'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

// ============================================================================
// Copiloto — ficha técnica del equipo (Biblioteca Maestra → corpus):
// VIN, motor, caja, emisiones, ECUs, cómo leer códigos en SU tablero,
// implemento y portal OEM. Se muestra arriba del chat.
// ============================================================================

export async function GET(req: Request) {
  const auth = await autenticar(req)
  if ('error' in auth) return NextResponse.json({ error: auth.error }, { status: auth.status })
  const activoId = new URL(req.url).searchParams.get('activo')
  if (!activoId) return NextResponse.json({ error: 'Falta activo.' }, { status: 400 })

  // RLS de SICOM decide si el usuario puede ver ese equipo
  const { data: a } = await auth.sb.from('activos').select('patente').eq('id', activoId).maybeSingle()
  const patente = (a as { patente?: string | null } | null)?.patente
  if (!patente) return NextResponse.json({ ficha: null })
  try {
    return NextResponse.json({ ficha: await fichaEquipo(corpusCliente(), patente) })
  } catch {
    return NextResponse.json({ ficha: null })
  }
}
