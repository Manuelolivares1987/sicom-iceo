import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

// ============================================================================
// Respaldo de un examen para el portal del mandante (MIG308)
// ----------------------------------------------------------------------------
// Los respaldos de exámenes están en un bucket privado, y así deben quedarse:
// son datos de salud de personas. Este endpoint es el único punto por donde
// salen, y sale un link firmado que caduca en 5 minutos.
//
// Quién autoriza NO es este servidor: es la base. fn_portal_prevencion_archivo
// verifica que el token esté vigente, que el portal tenga permitido entregar
// respaldos y que el examen pertenezca a la faena de ese portal. Si algo de eso
// falla, la base no devuelve ruta y aquí no hay nada que firmar. El servidor
// sólo pone la credencial de storage, que nunca baja al navegador.
// ============================================================================

const BUCKET = 'examenes-personal'
const VIGENCIA_SEG = 300

export async function POST(req: Request) {
  let body: { token?: string; examen_id?: string; acceso_id?: string }
  try {
    body = await req.json()
  } catch {
    return NextResponse.json({ error: 'Petición inválida.' }, { status: 400 })
  }

  const token = (body.token ?? '').trim()
  const examenId = (body.examen_id ?? '').trim()
  const accesoId = (body.acceso_id ?? '').trim()
  if (!token || !examenId || !accesoId) {
    return NextResponse.json({ error: 'Faltan datos.' }, { status: 400 })
  }

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY
  if (!url || !anonKey) {
    return NextResponse.json({ error: 'Servidor sin configurar.' }, { status: 500 })
  }
  if (!serviceKey) {
    // Sin la llave de servidor no se puede firmar. Se dice claro, en vez de
    // dejar al externo dando clics sobre un botón muerto.
    return NextResponse.json(
      { error: 'La descarga de respaldos no está habilitada en este servidor. Solicítelo a Prevención.' },
      { status: 503 },
    )
  }

  // 1. La base decide si este token, con este ingreso identificado (MIG313),
  //    puede ver este examen.
  const publico = createClient(url, anonKey, { auth: { persistSession: false } })
  const { data: path, error } = await publico.rpc('fn_portal_prevencion_archivo', {
    p_token: token,
    p_examen_id: examenId,
    p_acceso_id: accesoId,
  })
  if (error || !path) {
    return NextResponse.json({ error: 'Documento no disponible.' }, { status: 403 })
  }

  // 2. Recién ahora se usa la credencial de storage.
  const admin = createClient(url, serviceKey, { auth: { persistSession: false } })
  const { data: firmado, error: errFirma } = await admin.storage
    .from(BUCKET)
    .createSignedUrl(path as string, VIGENCIA_SEG)

  if (errFirma || !firmado?.signedUrl) {
    return NextResponse.json({ error: 'No se pudo abrir el documento.' }, { status: 500 })
  }

  return NextResponse.json({ url: firmado.signedUrl, expira_en_seg: VIGENCIA_SEG })
}
