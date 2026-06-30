import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { sendMail, parseRecipients, mailerConfigured } from '@/lib/email/mailer'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

// Digest de No Conformidades nuevas (sin notificar por correo).
// Lo invoca un cron (pg_cron → net.http_post) con el header x-cron-secret.
// Requiere en el servidor: CRON_SECRET, SUPABASE_SERVICE_ROLE_KEY, SMTP_*, NC_EMAIL_TO.
export async function POST(req: Request) {
  const secret = process.env.CRON_SECRET
  if (!secret || req.headers.get('x-cron-secret') !== secret) {
    return NextResponse.json({ error: 'No autorizado.' }, { status: 401 })
  }

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY
  if (!url || !serviceKey) {
    return NextResponse.json({ error: 'Falta SUPABASE_SERVICE_ROLE_KEY.' }, { status: 500 })
  }
  const to = parseRecipients(process.env.NC_EMAIL_TO)
  if (!mailerConfigured() || to.length === 0) {
    return NextResponse.json({ error: 'SMTP o NC_EMAIL_TO no configurados.' }, { status: 500 })
  }

  const sb = createClient(url, serviceKey, { auth: { persistSession: false } })

  const { data: ncs, error } = await sb
    .from('no_conformidades')
    .select('id, descripcion, severidad, origen, created_at, activo:activos(patente, codigo)')
    .is('email_notificada_at', null)
    .order('created_at', { ascending: true })
    .limit(200)
  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
  if (!ncs || ncs.length === 0) {
    return NextResponse.json({ ok: true, enviadas: 0 })
  }

  type Row = {
    id: string; descripcion: string | null; severidad: string | null; origen: string | null
    created_at: string; activo: { patente: string | null; codigo: string | null } | null
  }
  const filas = ncs as unknown as Row[]
  const fmt = (s: string) => new Date(s).toLocaleString('es-CL', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' })

  const rowsHtml = filas.map((n) => `
    <tr>
      <td style="padding:4px 8px;border-bottom:1px solid #eee">${n.activo?.patente ?? n.activo?.codigo ?? '—'}</td>
      <td style="padding:4px 8px;border-bottom:1px solid #eee">${(n.descripcion ?? '—').replace(/</g, '&lt;')}</td>
      <td style="padding:4px 8px;border-bottom:1px solid #eee">${n.severidad ?? '—'}</td>
      <td style="padding:4px 8px;border-bottom:1px solid #eee">${n.origen ?? '—'}</td>
      <td style="padding:4px 8px;border-bottom:1px solid #eee">${fmt(n.created_at)}</td>
    </tr>`).join('')

  const html = `
    <div style="font-family:system-ui,Arial,sans-serif;font-size:14px;color:#222">
      <h2 style="margin:0 0 8px">⚠ No Conformidades nuevas (${filas.length})</h2>
      <p style="margin:0 0 10px;color:#555">Resumen de no conformidades registradas en PILLADO ICEO.</p>
      <table style="border-collapse:collapse;width:100%;font-size:13px">
        <thead><tr style="background:#f5f5f5;text-align:left">
          <th style="padding:6px 8px">Equipo</th><th style="padding:6px 8px">Descripción</th>
          <th style="padding:6px 8px">Severidad</th><th style="padding:6px 8px">Origen</th><th style="padding:6px 8px">Fecha</th>
        </tr></thead>
        <tbody>${rowsHtml}</tbody>
      </table>
      <p style="margin:14px 0 0;font-size:12px;color:#888">Revísalas en la bandeja: /dashboard/mantenimiento/no-conformidades</p>
    </div>`

  const r = await sendMail({ to, subject: `⚠ ${filas.length} No Conformidad(es) nueva(s) · PILLADO`, html })
  if (!r.ok) {
    return NextResponse.json({ error: r.error ?? 'Error al enviar.' }, { status: 502 })
  }

  // Marcar como notificadas
  const ids = filas.map((n) => n.id)
  await sb.from('no_conformidades').update({ email_notificada_at: new Date().toISOString() }).in('id', ids)

  return NextResponse.json({ ok: true, enviadas: filas.length })
}
