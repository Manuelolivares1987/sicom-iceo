import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { sendMail, mailerConfigured } from '@/lib/email/mailer'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

// ============================================================================
// Envío manual del reporte documental (MIG303)
// ----------------------------------------------------------------------------
// El aviso automático manda solo lo que toca por cadencia. Esto manda la foto
// COMPLETA del momento, cuando prevención la necesita: para responderle al
// mandante, llevarla a una reunión o adelantarse a una auditoría.
//
// Autorización en dos capas:
//   1. La sesión del usuario (su token) identifica QUIÉN envía.
//   2. La base valida que ese usuario pueda ver el control documental.
// El secreto del servidor se usa solo después, para armar el correo — nunca
// llega al navegador.
//
// El destinatario NO lo elige el navegador libremente: se toma de los
// configurados para esa faena (MIG302). Si se pudiera escribir cualquier
// correo desde la UI, el control de alcance de los externos no serviría de
// nada. Se permite agregar uno puntual, y queda registrado quién lo agregó.
// ============================================================================

type Item = {
  examen_id: string
  rut: string
  persona: string
  faena_codigo: string | null
  tipo_nombre: string
  laboratorio: string | null
  fecha_vencimiento: string | null
  dias_restantes: number | null
  estado: string
  observacion: string | null
}

const ESTADO_UI: Record<string, { label: string, color: string, fondo: string, orden: number }> = {
  vencido:       { label: 'VENCIDO',    color: '#B91C1C', fondo: '#FEE2E2', orden: 1 },
  sin_dato:      { label: 'SIN DATO',   color: '#B91C1C', fondo: '#FEE2E2', orden: 2 },
  observado:     { label: 'OBSERVADO',  color: '#C2410C', fondo: '#FFEDD5', orden: 3 },
  por_vencer_30: { label: '≤ 30 días',  color: '#B45309', fondo: '#FEF3C7', orden: 4 },
  por_vencer_60: { label: '≤ 60 días',  color: '#4D7C0F', fondo: '#ECFCCB', orden: 5 },
  vigente:       { label: 'Vigente',    color: '#15803D', fondo: '#DCFCE7', orden: 6 },
}

const esc = (s: unknown) =>
  String(s ?? '').replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]!))

const fmtFecha = (s: string | null) =>
  s ? new Date(s + 'T12:00:00').toLocaleDateString('es-CL',
    { day: '2-digit', month: 'short', year: 'numeric' }) : '—'

export async function POST(req: Request) {
  const secret = process.env.CRON_SECRET
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
  if (!secret || !url || !anonKey) {
    return NextResponse.json({ error: 'Servidor sin configurar.' }, { status: 500 })
  }
  if (!mailerConfigured()) {
    return NextResponse.json({ error: 'Correo no configurado.' }, { status: 500 })
  }

  // ── 1. ¿Quién envía? ──
  const auth = req.headers.get('authorization') ?? ''
  const token = auth.startsWith('Bearer ') ? auth.slice(7) : null
  if (!token) return NextResponse.json({ error: 'Sesión requerida.' }, { status: 401 })

  const sbUser = createClient(url, anonKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false },
  })
  const { data: userData, error: errUser } = await sbUser.auth.getUser()
  if (errUser || !userData?.user) {
    return NextResponse.json({ error: 'Sesión inválida.' }, { status: 401 })
  }

  // La base decide si puede: no se confía en el rol que diga el navegador.
  const { data: puede, error: errPerm } = await sbUser.rpc('fn_prevencion_personal_puede_ver')
  if (errPerm || puede !== true) {
    return NextResponse.json({ error: 'No autorizado para enviar este reporte.' }, { status: 403 })
  }

  const body = await req.json().catch(() => ({})) as {
    faena?: string | null
    mensaje?: string | null
    incluirVigentes?: boolean
    destinatarioExtra?: string | null
  }
  const faena = body.faena ?? null

  // ── 2. Contenido ──
  const sb = createClient(url, anonKey, { auth: { persistSession: false } })
  const { data, error } = await sb.rpc('fn_prevencion_reporte_envio_cron', {
    p_secreto: secret,
    p_faena: faena,
    p_incluir_vigentes: body.incluirVigentes ?? false,
  })
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })

  const items = (data ?? []) as Item[]
  if (items.length === 0) {
    return NextResponse.json({ ok: false, error: 'No hay nada que reportar para esa faena.' }, { status: 400 })
  }

  // ── 3. Destinatarios: los configurados para esa faena ──
  const { data: dest, error: errDest } = await sb.rpc('fn_prevencion_destinatarios_cron', {
    p_secreto: secret, p_faena: faena,
  })
  if (errDest) return NextResponse.json({ error: errDest.message }, { status: 500 })

  const filasDest = (dest ?? []) as { email: string, modo: string }[]
  const to = filasDest.filter((d) => d.modo === 'para').map((d) => d.email)
  const cc = filasDest.filter((d) => d.modo === 'copia').map((d) => d.email)

  // Un destinatario puntual (ej. alguien que lo pidió para una reunión). Va en
  // copia y queda registrado, para que no se confunda con la lista estable.
  const extra = (body.destinatarioExtra ?? '').trim()
  if (extra) {
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(extra)) {
      return NextResponse.json({ error: 'El correo adicional no es válido.' }, { status: 400 })
    }
    cc.push(extra)
  }
  if (to.length === 0 && cc.length === 0) {
    return NextResponse.json({ error: 'No hay destinatarios configurados para esa faena.' }, { status: 400 })
  }

  // ── 4. Correo ──
  const vencidos = items.filter((i) => i.estado === 'vencido' || i.estado === 'sin_dato')
  const resto = items.filter((i) => i.estado !== 'vencido' && i.estado !== 'sin_dato')

  const fila = (i: Item) => {
    const st = ESTADO_UI[i.estado] ?? ESTADO_UI.por_vencer_60
    const dias = i.dias_restantes == null ? '—'
      : i.dias_restantes < 0 ? `hace ${-i.dias_restantes} d` : `en ${i.dias_restantes} d`
    return `<tr>
      <td style="padding:6px 8px;border-bottom:1px solid #eee">${esc(i.persona)}<br>
        <span style="color:#888;font-size:11px">${esc(i.rut)}</span></td>
      <td style="padding:6px 8px;border-bottom:1px solid #eee">${esc(i.tipo_nombre)}</td>
      <td style="padding:6px 8px;border-bottom:1px solid #eee">${esc(i.laboratorio ?? '—')}</td>
      <td style="padding:6px 8px;border-bottom:1px solid #eee;white-space:nowrap">${fmtFecha(i.fecha_vencimiento)}</td>
      <td style="padding:6px 8px;border-bottom:1px solid #eee;white-space:nowrap;
                 color:${st.color};font-weight:600">${st.label} · ${dias}</td>
    </tr>`
  }

  const tabla = (titulo: string, xs: Item[], color: string, fondo: string) => xs.length === 0 ? '' : `
    <h3 style="margin:18px 0 6px;padding:6px 10px;background:${fondo};color:${color};
               border-radius:6px;font-size:14px">${titulo} (${xs.length})</h3>
    <table style="border-collapse:collapse;width:100%;font-size:13px">
      <thead><tr style="background:#f5f5f5;text-align:left">
        <th style="padding:6px 8px">Persona</th><th style="padding:6px 8px">Examen</th>
        <th style="padding:6px 8px">Laboratorio</th><th style="padding:6px 8px">Vence</th>
        <th style="padding:6px 8px">Estado</th>
      </tr></thead><tbody>${xs.map(fila).join('')}</tbody>
    </table>`

  const quien = userData.user.email ?? 'el equipo de Prevención'
  const base = process.env.NEXT_PUBLIC_SITE_URL || 'https://pilladoiceo.netlify.app'
  const titulo = `Estado documental de personal${faena ? ` — ${faena}` : ''}`

  const html = `
    <div style="font-family:system-ui,Arial,sans-serif;font-size:14px;color:#222;max-width:760px">
      <h2 style="margin:0 0 4px">${esc(titulo)}</h2>
      <p style="margin:0 0 4px;color:#555">
        Reporte al ${new Date().toLocaleDateString('es-CL', { day: '2-digit', month: 'long', year: 'numeric' })}.
        ${vencidos.length > 0
          ? `<b style="color:#B91C1C">${vencidos.length} examen(es) vencido(s) o sin registro</b> y ${resto.length} por vencer u observado(s).`
          : `${resto.length} examen(es) por vencer u observado(s). Sin vencimientos.`}
      </p>
      ${body.mensaje ? `<div style="margin:12px 0;padding:10px 12px;background:#F1F5F9;
          border-left:3px solid #64748B;border-radius:4px;white-space:pre-wrap">${esc(body.mensaje)}</div>` : ''}
      ${tabla('Vencidos o sin registro', vencidos, '#B91C1C', '#FEE2E2')}
      ${tabla('Por vencer u observados', resto, '#B45309', '#FEF3C7')}
      <p style="margin:16px 0 0;font-size:12px;color:#888">
        Enviado desde SICOM-ICEO por ${esc(quien)} ·
        <a href="${base}/dashboard/prevencion/personal">ver en la plataforma</a>
      </p>
    </div>`

  const asunto = vencidos.length > 0
    ? `${titulo} — ${vencidos.length} vencido(s)`
    : `${titulo} — ${resto.length} por vencer`

  const r = await sendMail({ to, cc, subject: asunto, html })
  if (!r.ok) return NextResponse.json({ error: r.error ?? 'Error al enviar.' }, { status: 502 })

  // ── 5. Registro: la evidencia de que se avisó ──
  await sb.rpc('fn_prevencion_registrar_envio', {
    p_secreto: secret,
    p_faena: faena,
    p_destinatarios: [...to, ...cc].join(', '),
    p_asunto: asunto,
    p_total: items.length,
    p_vencidos: vencidos.length,
    p_mensaje: body.mensaje ?? null,
    p_enviado_por: userData.user.id,
  })

  return NextResponse.json({
    ok: true,
    enviados: to.length + cc.length,
    destinatarios: [...to, ...cc],
    items: items.length,
    vencidos: vencidos.length,
  })
}
