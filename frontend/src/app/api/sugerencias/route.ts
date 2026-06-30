import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { sendMail, parseRecipients, mailerConfigured } from '@/lib/email/mailer'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

function construirPrompt(p: {
  texto: string; url: string; titulo: string; usuario: string; rol: string; fecha: string
}): string {
  return [
    `Mejora solicitada por un usuario de PILLADO ICEO (Next.js + Supabase).`,
    ``,
    `Usuario: ${p.usuario}${p.rol ? ` (${p.rol})` : ''}`,
    `Página: ${p.titulo || '—'} — ${p.url || '—'}`,
    `Fecha: ${p.fecha}`,
    ``,
    `Pedido textual del usuario:`,
    `"${p.texto}"`,
    ``,
    `Instrucción para Claude Code:`,
    `Implementa esta mejora en la plataforma. Parte por localizar el código de la página/módulo indicado arriba (la ruta corresponde a app/dashboard/...). Analiza cómo funciona hoy, propón el cambio mínimo y aplícalo respetando las convenciones del repo (servicios en lib/services, hooks en hooks/, migraciones en database/production_run si toca la BD). Verifica tipos antes de commitear.`,
  ].join('\n')
}

export async function POST(req: Request) {
  const token = req.headers.get('authorization')?.replace(/^Bearer\s+/i, '')
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL
  const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
  if (!token || !url || !anon) {
    return NextResponse.json({ error: 'No autorizado.' }, { status: 401 })
  }

  const sb = createClient(url, anon, { global: { headers: { Authorization: `Bearer ${token}` } } })
  const { data: userData, error: authErr } = await sb.auth.getUser(token)
  if (authErr || !userData?.user) {
    return NextResponse.json({ error: 'Sesión inválida.' }, { status: 401 })
  }

  let body: { texto?: string; contextoUrl?: string; contextoTitulo?: string }
  try { body = await req.json() } catch { return NextResponse.json({ error: 'JSON inválido.' }, { status: 400 }) }

  const texto = (body.texto ?? '').trim()
  if (texto.length < 5) {
    return NextResponse.json({ error: 'Escribe una sugerencia un poco más detallada.' }, { status: 400 })
  }

  // Perfil del usuario (nombre + rol) para contexto
  const { data: perfil } = await sb
    .from('usuarios_perfil')
    .select('nombre_completo, rol')
    .eq('id', userData.user.id)
    .maybeSingle()

  const usuario = perfil?.nombre_completo ?? userData.user.email ?? 'Usuario'
  const rol = (perfil?.rol as string | undefined) ?? ''
  const fecha = new Date().toISOString()
  const prompt = construirPrompt({
    texto,
    url: body.contextoUrl ?? '',
    titulo: body.contextoTitulo ?? '',
    usuario, rol, fecha,
  })

  // Guardar la sugerencia (RLS: authenticated)
  const { data: ins, error: insErr } = await sb
    .from('sugerencias')
    .insert({
      texto,
      contexto_url: body.contextoUrl ?? null,
      contexto_titulo: body.contextoTitulo ?? null,
      usuario_id: userData.user.id,
      usuario_nombre: usuario,
      usuario_rol: rol || null,
      prompt_generado: prompt,
    })
    .select('id')
    .single()
  if (insErr) {
    return NextResponse.json({ error: `No se pudo guardar: ${insErr.message}` }, { status: 500 })
  }

  // Enviar por correo (si está configurado el SMTP)
  let emailed = false
  const to = parseRecipients(process.env.SUGERENCIAS_EMAIL_TO || process.env.NC_EMAIL_TO)
  if (mailerConfigured() && to.length > 0) {
    const html = `
      <div style="font-family:system-ui,Arial,sans-serif;font-size:14px;color:#222">
        <h2 style="margin:0 0 8px">💡 Nueva sugerencia · PILLADO ICEO</h2>
        <p style="margin:2px 0"><b>Usuario:</b> ${usuario}${rol ? ` (${rol})` : ''}</p>
        <p style="margin:2px 0"><b>Página:</b> ${body.contextoTitulo ?? '—'} — ${body.contextoUrl ?? '—'}</p>
        <p style="margin:10px 0 4px"><b>Sugerencia:</b></p>
        <blockquote style="margin:0;padding:8px 12px;background:#f5f5f5;border-left:3px solid #f59e0b">${texto.replace(/</g, '&lt;')}</blockquote>
        <p style="margin:14px 0 4px"><b>Prompt listo para Claude Code:</b></p>
        <pre style="white-space:pre-wrap;background:#0f172a;color:#e2e8f0;padding:12px;border-radius:6px;font-size:12px">${prompt.replace(/</g, '&lt;')}</pre>
      </div>`
    const r = await sendMail({
      to,
      subject: `💡 Sugerencia PILLADO: ${texto.slice(0, 60)}${texto.length > 60 ? '…' : ''}`,
      html,
      text: prompt,
    })
    emailed = r.ok
    if (r.ok) {
      await sb.from('sugerencias').update({ email_enviado_at: new Date().toISOString() }).eq('id', ins.id)
    }
  }

  return NextResponse.json({ ok: true, id: ins.id, emailed })
}
