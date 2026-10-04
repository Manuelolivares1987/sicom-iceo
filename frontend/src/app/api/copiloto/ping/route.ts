import { NextResponse } from 'next/server'
import { corpusCliente } from '@/lib/copiloto/server'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

// ============================================================================
// Copiloto Técnico — ping diario a la biblioteca (MIG582)
// ----------------------------------------------------------------------------
// La biblioteca de manuales vive en un proyecto Supabase aparte, en plan
// gratuito, que se pausa solo tras una semana sin uso. El 04-10-2026 llevaba
// días pausada (última consulta del taller: 24-09) y nadie lo sabía: el
// copiloto abría, pero sin manuales que citar.
//
// Lo invoca un cron diario (pg_cron → net.http_post) con x-cron-secret. Hace
// una consulta real a la base del corpus —no basta con tocar la URL— y
// responde 502 si no contesta, para que la falla quede en net._http_response.
// ============================================================================
export async function POST(req: Request) {
  const secret = process.env.CRON_SECRET
  if (!secret || req.headers.get('x-cron-secret') !== secret) {
    return NextResponse.json({ error: 'No autorizado.' }, { status: 401 })
  }
  const corpus = corpusCliente()
  if (!corpus) {
    return NextResponse.json({ error: 'Falta COPILOTO_SUPABASE_URL o COPILOTO_SUPABASE_SERVICE_KEY.' }, { status: 500 })
  }
  try {
    const { count, error } = await corpus.from('copiloto_documentos').select('id', { count: 'exact', head: true })
    if (error) return NextResponse.json({ ok: false, error: error.message || 'El corpus no respondió.' }, { status: 502 })
    return NextResponse.json({ ok: true, documentos: count ?? 0 })
  } catch (e) {
    // Proyecto pausado: el dominio deja de resolver y fetch lanza.
    return NextResponse.json({ ok: false, error: e instanceof Error ? e.message : 'El corpus no respondió.' }, { status: 502 })
  }
}
