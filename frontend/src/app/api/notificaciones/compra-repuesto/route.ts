import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { sendMail, parseRecipients, mailerConfigured } from '@/lib/email/mailer'
import { emailShell, chipEstado, MARCA } from '@/lib/email/plantilla'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

// ============================================================================
// Correo a compras: cotizar UN repuesto (2026-09-03, fase de pruebas)
// ----------------------------------------------------------------------------
// NO lo dispara ningún cron: lo autoriza una persona desde la pantalla, al
// mandar el ítem «A compra» (o desde el tablero de seguimiento). La sesión del
// usuario es la autorización — el servidor la valida, lee el pedido con SUS
// permisos (RLS) y arma el correo con todo lo necesario para cotizar: foto,
// descripción, código, cantidad y los datos del camión. El Reply-To apunta a
// quien lo envió, para que compras le responda directo.
//
// Requiere en el servidor: SMTP_* y COMPRAS_EMAIL_TO.
// ============================================================================

type Recurso = {
  id: string
  descripcion: string | null
  producto_nombre: string | null
  producto_codigo: string | null
  cantidad: number
  cantidad_aprobada: number | null
  unidad: string | null
  comentario: string | null
  fotos: string[] | null
  solicitado_nombre: string | null
  estado: string
  dias_desde_solicitud: number | null
  ot_folio: string | null
  activo_patente: string | null
  activo_codigo: string | null
  activo_nombre: string | null
  es_insumo_taller?: boolean
  ceco_nombre?: string | null
}

const esc = (s: unknown) =>
  String(s ?? '').replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]!))

export async function POST(req: Request) {
  const auth = req.headers.get('authorization')
  if (!auth?.startsWith('Bearer ')) {
    return NextResponse.json({ error: 'No autorizado.' }, { status: 401 })
  }
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL
  const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
  if (!url || !anon) {
    return NextResponse.json({ error: 'Falta configuración de Supabase.' }, { status: 500 })
  }
  const to = parseRecipients(process.env.COMPRAS_EMAIL_TO)
  if (!mailerConfigured() || to.length === 0) {
    return NextResponse.json({ error: 'SMTP o COMPRAS_EMAIL_TO no configurados.' }, { status: 500 })
  }

  // La sesión del usuario ES la autorización: se valida y se lee con SUS
  // permisos. Nada de service_role ni secretos de cron en este camino.
  const sb = createClient(url, anon, {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false },
  })
  const { data: userData, error: userErr } = await sb.auth.getUser()
  if (userErr || !userData?.user) {
    return NextResponse.json({ error: 'Sesión inválida.' }, { status: 401 })
  }
  const quien = userData.user.email ?? 'bodega'

  const { recursoId } = await req.json().catch(() => ({}))
  if (!recursoId || typeof recursoId !== 'string') {
    return NextResponse.json({ error: 'Falta el recurso a cotizar.' }, { status: 400 })
  }

  const { data, error } = await sb
    .from('v_ot_recursos_seguimiento')
    .select('*')
    .eq('id', recursoId)
    .maybeSingle()
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  if (!data) return NextResponse.json({ error: 'Pedido no encontrado.' }, { status: 404 })
  const r = data as Recurso

  const nombre = r.producto_nombre ?? r.descripcion ?? 'Repuesto sin descripción'
  const cantidad = r.cantidad_aprobada ?? r.cantidad
  const equipo = r.es_insumo_taller
    ? (r.ceco_nombre ?? 'Insumo del taller')
    : [r.activo_patente, r.activo_codigo].filter(Boolean).join(' · ') || '—'
  const fotos = (r.fotos ?? []).filter(Boolean)

  const dato = (k: string, v: string) => `
    <tr>
      <td style="padding:7px 12px;font-size:11px;color:#6b7280;text-transform:uppercase;
                 letter-spacing:.5px;white-space:nowrap;vertical-align:top">${k}</td>
      <td style="padding:7px 12px;font-size:13px;color:#111827">${v}</td>
    </tr>`

  const base = process.env.NEXT_PUBLIC_SITE_URL || 'https://pilladoiceo.netlify.app'
  const html = emailShell({
    titulo: 'Repuesto para cotizar',
    subtitulo: `Solicitud de bodega · ${new Date().toLocaleDateString('es-CL', { day: '2-digit', month: 'long' })}`,
    cuerpo: `
      <div style="margin-top:16px;border:1px solid #e5e7eb;border-radius:12px;overflow:hidden">
        ${fotos.length > 0 ? `
        <div style="background:#f8faf8;padding:14px;text-align:center">
          <img src="${fotos[0]}" alt="Foto del repuesto"
               style="max-width:100%;max-height:320px;border-radius:8px;border:1px solid #e5e7eb" />
          ${fotos.slice(1, 4).map((u) => `
            <img src="${u}" alt="Foto adicional"
                 style="max-width:31%;max-height:110px;border-radius:6px;border:1px solid #e5e7eb;margin:8px 3px 0" />`).join('')}
        </div>` : ''}
        <div style="padding:16px 16px 6px">
          <div style="font-size:18px;font-weight:800;color:#111827">${esc(nombre)}</div>
          <div style="margin-top:6px">
            ${chipEstado(`${cantidad} ${esc(r.unidad ?? 'un')}`, MARCA.verdeOscuro, MARCA.verdeClaro)}
            ${r.producto_codigo ? ' ' + chipEstado(`Código ${esc(r.producto_codigo)}`, '#374151', '#f3f4f6') : ''}
            ${(r.dias_desde_solicitud ?? 0) > 0
              ? ' ' + chipEstado(`esperando ${r.dias_desde_solicitud} d`, MARCA.ambar, MARCA.ambarFondo) : ''}
          </div>
        </div>
        <table role="presentation" cellpadding="0" cellspacing="0" style="width:100%;margin:8px 0 10px">
          ${dato('Equipo', `<b>${esc(equipo)}</b>${r.activo_nombre ? `<br><span style="color:#6b7280;font-size:12px">${esc(r.activo_nombre)}</span>` : ''}`)}
          ${r.ot_folio ? dato('Orden de trabajo', esc(r.ot_folio)) : ''}
          ${r.solicitado_nombre ? dato('Lo pidió', esc(r.solicitado_nombre)) : ''}
          ${r.comentario ? dato('Comentario', `«${esc(r.comentario)}»`) : ''}
          ${dato('Autorizó el envío', esc(quien))}
        </table>
      </div>
      <p style="margin:14px 0 0;font-size:12px;color:#6b7280">
        Puedes responder este correo directamente: le llega a quien lo envió desde bodega.
      </p>`,
    ctaUrl: `${base}/dashboard/bodega/seguimiento-repuestos/`,
    ctaTexto: 'Ver en Seguimiento de repuestos',
    pie: 'Correo enviado a mano desde bodega (fase de pruebas — nada sale automático). '
       + 'SICOM · Pillado Empresas.',
  })

  const envio = await sendMail({
    to,
    subject: `🛒 Cotizar: ${nombre} × ${cantidad} ${r.unidad ?? 'un'} · ${equipo} · PILLADO`,
    html,
    replyTo: userData.user.email ?? undefined,
  })
  if (!envio.ok) return NextResponse.json({ error: envio.error ?? 'No se pudo enviar' }, { status: 500 })
  return NextResponse.json({ ok: true, enviado_a: to.join(', ') })
}
