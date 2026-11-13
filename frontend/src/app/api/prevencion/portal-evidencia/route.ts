import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

// ============================================================================
// Fotos de evidencia para el portal del mandante (MIG688)
// ----------------------------------------------------------------------------
// Las fotos de inspecciones y actividades están en el bucket privado
// prevencion-evidencias. Mismo esquema que portal-archivo (MIG308): la BASE
// decide (fn_portal_mandante_evidencia valida link, ingreso vigente y que la
// foto pertenezca a una faena del portal) y este servidor solo firma, con un
// link que caduca. Acepta varias rutas a la vez para cargar una galería.
// ============================================================================

const BUCKET = 'prevencion-evidencias'
const VIGENCIA_SEG = 600
const MAX_RUTAS = 40

export async function POST(req: Request) {
  let body: { token?: string; acceso_id?: string; paths?: string[] }
  try {
    body = await req.json()
  } catch {
    return NextResponse.json({ error: 'Petición inválida.' }, { status: 400 })
  }

  const token = (body.token ?? '').trim()
  const accesoId = (body.acceso_id ?? '').trim()
  const paths = Array.from(new Set((body.paths ?? []).filter((p) => typeof p === 'string' && p))).slice(0, MAX_RUTAS)
  if (!token || !accesoId || !paths.length) {
    return NextResponse.json({ error: 'Faltan datos.' }, { status: 400 })
  }

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY
  if (!url || !anonKey) {
    return NextResponse.json({ error: 'Servidor sin configurar.' }, { status: 500 })
  }
  if (!serviceKey) {
    return NextResponse.json(
      { error: 'Las fotos no están habilitadas en este servidor. Solicítelo a Prevención.' },
      { status: 503 },
    )
  }

  const publico = createClient(url, anonKey, { auth: { persistSession: false } })
  const admin = createClient(url, serviceKey, { auth: { persistSession: false } })

  const urls: Record<string, string> = {}
  for (const p of paths) {
    const { data: ok, error } = await publico.rpc('fn_portal_mandante_evidencia', {
      p_token: token, p_acceso_id: accesoId, p_path: p,
    })
    if (error || !ok) continue
    const { data: firmado } = await admin.storage.from(BUCKET).createSignedUrl(ok as string, VIGENCIA_SEG)
    if (firmado?.signedUrl) urls[p] = firmado.signedUrl
  }
  return NextResponse.json({ urls, expira_en_seg: VIGENCIA_SEG })
}
