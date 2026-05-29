import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { Resend } from 'resend'
import {
  buildReporteFlotaEmail,
  asuntoReporteFlota,
  type ReporteEmailPayload,
} from '@/lib/email/reporte-flota-email'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

export async function POST(req: Request) {
  const apiKey = process.env.RESEND_API_KEY
  if (!apiKey) {
    return NextResponse.json(
      { error: 'RESEND_API_KEY no configurada en el servidor.' },
      { status: 500 },
    )
  }

  // ── Autenticación: exigir un usuario logueado (evita envíos anónimos) ──
  const token = req.headers.get('authorization')?.replace(/^Bearer\s+/i, '')
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL
  const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
  if (!token || !url || !anon) {
    return NextResponse.json({ error: 'No autorizado.' }, { status: 401 })
  }
  const sb = createClient(url, anon)
  const { data: userData, error: authErr } = await sb.auth.getUser(token)
  if (authErr || !userData?.user) {
    return NextResponse.json({ error: 'Sesión inválida.' }, { status: 401 })
  }

  // ── Validación del body ──
  let body: { to?: unknown; payload?: ReporteEmailPayload; asunto?: string }
  try {
    body = await req.json()
  } catch {
    return NextResponse.json({ error: 'JSON inválido.' }, { status: 400 })
  }

  const to = Array.isArray(body.to)
    ? (body.to as unknown[]).map((x) => String(x).trim()).filter(Boolean)
    : []
  if (to.length === 0) {
    return NextResponse.json({ error: 'Indica al menos un destinatario.' }, { status: 400 })
  }
  const invalidos = to.filter((e) => !EMAIL_RE.test(e))
  if (invalidos.length > 0) {
    return NextResponse.json(
      { error: `Correos inválidos: ${invalidos.join(', ')}` },
      { status: 400 },
    )
  }
  if (!body.payload || typeof body.payload !== 'object') {
    return NextResponse.json({ error: 'Falta el contenido del reporte.' }, { status: 400 })
  }

  // ── Construir y enviar ──
  const payload = body.payload as ReporteEmailPayload
  const html = buildReporteFlotaEmail(payload)
  const subject = body.asunto?.trim() || asuntoReporteFlota(payload)
  const from = process.env.RESEND_FROM || 'Reporte Flota Pillado <onboarding@resend.dev>'

  const resend = new Resend(apiKey)
  const { data, error } = await resend.emails.send({ from, to, subject, html })

  if (error) {
    return NextResponse.json({ error: error.message ?? 'Error al enviar.' }, { status: 502 })
  }
  return NextResponse.json({ ok: true, id: data?.id, enviados: to.length })
}
