import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { sendMail, parseRecipients, mailerConfigured } from '@/lib/email/mailer'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

// ============================================================================
// Alerta de vencimiento de exámenes ocupacionales (MIG299)
// ----------------------------------------------------------------------------
// La invoca un cron diario (pg_cron → net.http_post) con el header
// x-cron-secret. La base decide QUÉ toca avisar hoy según el escalamiento
// (fn_prevencion_alertas_pendientes): esta ruta solo arma el correo y lo manda.
//
// Idempotente: los avisos se marcan DESPUÉS de que el correo salió. Si el
// envío falla, no se marcan y se reintentan al día siguiente — mejor un aviso
// repetido que uno perdido.
//
// Requiere en el servidor: CRON_SECRET, SUPABASE_SERVICE_ROLE_KEY, SMTP_*,
// y PREVENCION_EMAIL_TO (o NC_EMAIL_TO como respaldo).
// ============================================================================

type Alerta = {
  examen_id: string
  rut: string
  persona: string
  empresa: string | null
  faena_codigo: string | null
  tipo_nombre: string
  laboratorio: string | null
  fecha_vencimiento: string | null
  dias_restantes: number | null
  nivel: string
}

const NIVEL = {
  vencido:  { label: 'VENCIDO',   color: '#B91C1C', fondo: '#FEE2E2', orden: 0 },
  critico:  { label: '≤ 7 días',  color: '#C2410C', fondo: '#FFEDD5', orden: 1 },
  urgente:  { label: '≤ 14 días', color: '#B45309', fondo: '#FEF3C7', orden: 2 },
  alto:     { label: '≤ 30 días', color: '#A16207', fondo: '#FEF9C3', orden: 3 },
  medio:    { label: '≤ 60 días', color: '#4D7C0F', fondo: '#ECFCCB', orden: 4 },
  sin_dato: { label: 'SIN DATO',  color: '#B91C1C', fondo: '#FEE2E2', orden: 0 },
} as const

const esc = (s: unknown) =>
  String(s ?? '').replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]!))

const fmtFecha = (s: string | null) =>
  s ? new Date(s + 'T12:00:00').toLocaleDateString('es-CL',
    { day: '2-digit', month: 'short', year: 'numeric' }) : '—'

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

  const to = parseRecipients(
    process.env.PREVENCION_EMAIL_TO || process.env.NC_EMAIL_TO)
  if (!mailerConfigured() || to.length === 0) {
    return NextResponse.json({ error: 'SMTP o PREVENCION_EMAIL_TO no configurados.' }, { status: 500 })
  }

  const sb = createClient(url, serviceKey, { auth: { persistSession: false } })

  const { data, error } = await sb.rpc('fn_prevencion_alertas_pendientes')
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })

  const filas = (data ?? []) as Alerta[]
  if (filas.length === 0) return NextResponse.json({ ok: true, enviadas: 0 })

  // Lo más urgente primero: el correo se lee de arriba hacia abajo y en dos
  // líneas tiene que quedar claro quién no puede entrar a faena mañana.
  filas.sort((a, b) => {
    const na = NIVEL[a.nivel as keyof typeof NIVEL]?.orden ?? 9
    const nb = NIVEL[b.nivel as keyof typeof NIVEL]?.orden ?? 9
    return na - nb || (a.dias_restantes ?? 0) - (b.dias_restantes ?? 0)
  })

  const vencidos = filas.filter((f) => f.nivel === 'vencido' || f.nivel === 'sin_dato')
  const proximos = filas.filter((f) => f.nivel !== 'vencido' && f.nivel !== 'sin_dato')

  const fila = (f: Alerta) => {
    const n = NIVEL[f.nivel as keyof typeof NIVEL] ?? NIVEL.medio
    const dias = f.dias_restantes == null ? '—'
      : f.dias_restantes < 0 ? `hace ${-f.dias_restantes} d`
      : `en ${f.dias_restantes} d`
    return `<tr>
      <td style="padding:6px 8px;border-bottom:1px solid #eee">${esc(f.persona)}<br>
        <span style="color:#888;font-size:11px">${esc(f.rut)}</span></td>
      <td style="padding:6px 8px;border-bottom:1px solid #eee">${esc(f.tipo_nombre)}</td>
      <td style="padding:6px 8px;border-bottom:1px solid #eee">${esc(f.laboratorio ?? '—')}</td>
      <td style="padding:6px 8px;border-bottom:1px solid #eee;white-space:nowrap">${fmtFecha(f.fecha_vencimiento)}</td>
      <td style="padding:6px 8px;border-bottom:1px solid #eee;white-space:nowrap;color:${n.color};font-weight:600">${dias}</td>
    </tr>`
  }

  const tabla = (titulo: string, xs: Alerta[], color: string, fondo: string) => xs.length === 0 ? '' : `
    <h3 style="margin:18px 0 6px;padding:6px 10px;background:${fondo};color:${color};
               border-radius:6px;font-size:14px">${titulo} (${xs.length})</h3>
    <table style="border-collapse:collapse;width:100%;font-size:13px">
      <thead><tr style="background:#f5f5f5;text-align:left">
        <th style="padding:6px 8px">Persona</th><th style="padding:6px 8px">Examen</th>
        <th style="padding:6px 8px">Laboratorio</th><th style="padding:6px 8px">Vence</th>
        <th style="padding:6px 8px">Plazo</th>
      </tr></thead>
      <tbody>${xs.map(fila).join('')}</tbody>
    </table>`

  const base = process.env.NEXT_PUBLIC_SITE_URL || 'https://pilladoiceo.netlify.app'
  const html = `
    <div style="font-family:system-ui,Arial,sans-serif;font-size:14px;color:#222;max-width:760px">
      <h2 style="margin:0 0 4px">Control documental de personal — exámenes por vencer</h2>
      <p style="margin:0 0 12px;color:#555">
        ${vencidos.length > 0
          ? `<b style="color:#B91C1C">${vencidos.length} examen(es) VENCIDO(S)</b> y ${proximos.length} por vencer.`
          : `${proximos.length} examen(es) por vencer.`}
        La alerta se repite con más frecuencia a medida que se acerca la fecha.
      </p>
      ${tabla('Vencidos o sin registro — no pueden acreditar documentación al día',
              vencidos, '#B91C1C', '#FEE2E2')}
      ${tabla('Por vencer', proximos, '#B45309', '#FEF3C7')}
      <p style="margin:16px 0 0;font-size:12px;color:#888">
        Renovar (subiendo el nuevo examen) en
        <a href="${base}/dashboard/prevencion/personal">${base}/dashboard/prevencion/personal</a>
      </p>
    </div>`

  const asunto = vencidos.length > 0
    ? `🔴 ${vencidos.length} examen(es) vencido(s) · Control documental PILLADO`
    : `⚠ ${proximos.length} examen(es) por vencer · Control documental PILLADO`

  const r = await sendMail({ to, subject: asunto, html })
  if (!r.ok) {
    // No se marcan: se reintenta mañana. Un aviso repetido es preferible a uno
    // perdido cuando lo que está en juego es acreditar gente en faena.
    return NextResponse.json({ error: r.error ?? 'Error al enviar.' }, { status: 502 })
  }

  const { error: errMarcar } = await sb.rpc('fn_prevencion_marcar_alertas', {
    p_ids: filas.map((f) => f.examen_id),
    p_destinatarios: to.join(', '),
  })
  if (errMarcar) {
    // El correo salió; solo falló el registro. Se informa para no perder la
    // pista, pero no se trata como fallo de envío.
    return NextResponse.json({ ok: true, enviadas: filas.length, aviso: errMarcar.message })
  }

  return NextResponse.json({
    ok: true,
    enviadas: filas.length,
    vencidos: vencidos.length,
    por_vencer: proximos.length,
  })
}
