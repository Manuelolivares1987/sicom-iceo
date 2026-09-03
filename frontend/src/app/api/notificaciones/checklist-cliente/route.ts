import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { sendMail, parseRecipients, mailerConfigured } from '@/lib/email/mailer'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

// ============================================================================
// Aviso: el CLIENTE no ha hecho el checklist semanal del QR (MIG502)
// ----------------------------------------------------------------------------
// El cliente que arrienda un equipo debe hacerle un checklist semanal
// escaneando el QR (MIG127/129). Este correo avisa cuando NO lo hace: equipos
// con más de 7 días sin checklist, o que nunca han tenido uno. Mientras el
// cliente cumpla, silencio; cuando se atrasa, insiste a diario hasta que lo
// haga — el mismo criterio que un examen vencido.
//
// Lo invoca un cron diario (pg_cron → net.http_post) con x-cron-secret.
// NO usa service_role: el mismo secreto habilita UNA función en la base
// (fn_checklist_cliente_pendientes_cron, patrón MIG301) y nada más.
//
// Requiere en el servidor: CRON_SECRET, SMTP_*, CHECKLIST_CLIENTE_EMAIL_TO.
// ============================================================================

type Pendiente = {
  activo_id: string
  patente: string | null
  codigo: string | null
  nombre: string | null
  cliente: string | null
  estado_comercial: string | null
  ultima_fecha: string | null
  dias_desde_ultimo: number | null
  estado: string
}

const esc = (s: string) =>
  s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')

export async function POST(req: Request) {
  const secret = process.env.CRON_SECRET
  if (!secret || req.headers.get('x-cron-secret') !== secret) {
    return NextResponse.json({ error: 'No autorizado.' }, { status: 401 })
  }

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL
  const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
  if (!url || !anon) {
    return NextResponse.json({ error: 'Falta configuración de Supabase.' }, { status: 500 })
  }
  const to = parseRecipients(process.env.CHECKLIST_CLIENTE_EMAIL_TO)
  if (!mailerConfigured() || to.length === 0) {
    return NextResponse.json({ error: 'SMTP o CHECKLIST_CLIENTE_EMAIL_TO no configurados.' }, { status: 500 })
  }

  const sb = createClient(url, anon, { auth: { persistSession: false } })
  const { data, error } = await sb.rpc('fn_checklist_cliente_pendientes_cron', { p_secreto: secret })
  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
  const pendientes = (data ?? []) as Pendiente[]
  if (pendientes.length === 0) {
    return NextResponse.json({ ok: true, pendientes: 0 })
  }

  // Agrupar por cliente: el correo se lee para llamar a alguien, y a ese
  // alguien se le llama por cliente, no equipo por equipo.
  const porCliente = new Map<string, Pendiente[]>()
  for (const p of pendientes) {
    const k = p.cliente?.trim() || 'Sin cliente registrado'
    porCliente.set(k, [...(porCliente.get(k) ?? []), p])
  }

  const fila = (p: Pendiente) => {
    const equipo = [p.patente, p.codigo].filter(Boolean).join(' · ') || '—'
    const ultimo = p.ultima_fecha
      ? `${new Date(`${p.ultima_fecha}T12:00:00`).toLocaleDateString('es-CL')} (hace ${p.dias_desde_ultimo} días)`
      : 'NUNCA'
    const rojo = p.estado === 'sin_check' || (p.dias_desde_ultimo ?? 0) > 14
    return `<tr>
      <td style="padding:6px 10px;border-bottom:1px solid #eee"><b>${esc(equipo)}</b><br>
          <span style="color:#666;font-size:12px">${esc(p.nombre ?? '')}</span></td>
      <td style="padding:6px 10px;border-bottom:1px solid #eee;color:${rojo ? '#B91C1C' : '#C2410C'};font-weight:600">
          ${esc(ultimo)}</td>
    </tr>`
  }

  const bloques = Array.from(porCliente.entries()).map(([cliente, eqs]) => `
    <h3 style="margin:18px 0 6px;font-size:15px">${esc(cliente)} — ${eqs.length} equipo${eqs.length > 1 ? 's' : ''}</h3>
    <table style="border-collapse:collapse;width:100%;font-family:sans-serif;font-size:13px">
      <tr style="background:#f3f4f6;text-align:left">
        <th style="padding:6px 10px">Equipo</th>
        <th style="padding:6px 10px">Último checklist del cliente</th>
      </tr>
      ${eqs.map(fila).join('')}
    </table>`).join('')

  const html = `
    <div style="font-family:sans-serif;max-width:640px">
      <h2 style="color:#B91C1C">⚠️ Checklist del cliente pendiente</h2>
      <p style="font-size:14px">${pendientes.length} equipo${pendientes.length > 1 ? 's' : ''} fuera de
      instalaciones ${pendientes.length > 1 ? 'llevan' : 'lleva'} más de 7 días sin el checklist semanal
      que el cliente debe hacer por el QR (o nunca lo han tenido).</p>
      ${bloques}
      <p style="font-size:12px;color:#666;margin-top:16px">
        Detalle y panel de cumplimiento: https://pilladoiceo.netlify.app/dashboard/flota/checklist-cliente/<br>
        Este aviso se repite a diario mientras el atraso siga. Es automático (SICOM).
      </p>
    </div>`

  const r = await sendMail({
    to,
    subject: `⚠️ ${pendientes.length} equipo(s) sin checklist del cliente — ${new Date().toLocaleDateString('es-CL')}`,
    html,
  })
  if (!r.ok) {
    return NextResponse.json({ error: r.error ?? 'No se pudo enviar' }, { status: 500 })
  }
  return NextResponse.json({ ok: true, pendientes: pendientes.length, clientes: porCliente.size })
}
