import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { sendMail, mailerConfigured } from '@/lib/email/mailer'
import { asuntoInforme, htmlInformeSemanal } from '@/lib/email/enex-informe-semanal'
import type { InformeSemanal } from '@/lib/enex-informe-semanal'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

// Informe semanal a ENEX (MIG679). Lo autoriza una persona desde la pantalla: su
// sesión es la autorización y el RPC valida el permiso antes de que salga nada.

const EMAIL = /^[^\s@<>,;]+@[^\s@<>,;]+\.[^\s@<>,;]+$/
const listaValida = (v: unknown): string[] | null => {
  if (!Array.isArray(v) || v.length > 30) return null
  const l = v.map((x) => String(x).trim()).filter(Boolean)
  return l.every((x) => EMAIL.test(x)) ? l : null
}

export async function POST(req: Request) {
  const auth = req.headers.get('authorization')
  if (!auth?.startsWith('Bearer ')) return NextResponse.json({ error: 'No autorizado.' }, { status: 401 })
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL
  const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
  if (!url || !anon) return NextResponse.json({ error: 'Falta configuración de Supabase.' }, { status: 500 })
  if (!mailerConfigured()) return NextResponse.json({ error: 'El correo no está configurado.' }, { status: 500 })

  const sb = createClient(url, anon, { global: { headers: { Authorization: auth } }, auth: { persistSession: false } })
  const { data: u, error: uErr } = await sb.auth.getUser()
  if (uErr || !u?.user) return NextResponse.json({ error: 'Sesión inválida.' }, { status: 401 })

  const body = await req.json().catch(() => null) as { informe?: InformeSemanal; para?: unknown; copia?: unknown } | null
  const para = listaValida(body?.para)
  const copia = listaValida(body?.copia ?? [])
  const informe = body?.informe
  if (!para || para.length === 0 || !copia) return NextResponse.json({ error: 'Revisa los correos de destino.' }, { status: 400 })
  if (!informe?.semana?.desde || !Array.isArray(informe.faenas) || informe.faenas.length === 0) {
    return NextResponse.json({ error: 'El informe está vacío.' }, { status: 400 })
  }

  let html: string, asunto: string
  try { html = htmlInformeSemanal(informe); asunto = asuntoInforme(informe) }
  catch { return NextResponse.json({ error: 'El informe no tiene el formato esperado.' }, { status: 400 }) }

  const { data: id, error } = await sb.rpc('rpc_enex_informe_semanal_registrar', {
    p_semana_inicio: informe.semana.desde, p_destinatarios: para, p_copia: copia, p_asunto: asunto, p_contenido: informe,
  })
  if (error) return NextResponse.json({ error: error.message }, { status: 403 })

  const envio = await sendMail({ to: para, cc: copia, subject: asunto, html, replyTo: u.user.email ?? undefined })
  await sb.rpc('rpc_enex_informe_semanal_resultado', { p_id: id, p_ok: envio.ok, p_error: envio.error ?? null })
  if (!envio.ok) return NextResponse.json({ error: envio.error ?? 'No se pudo enviar.' }, { status: 502 })
  return NextResponse.json({ ok: true, enviado_a: para })
}
