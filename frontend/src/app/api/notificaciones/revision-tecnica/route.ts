import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { sendMail, parseRecipients, mailerConfigured } from '@/lib/email/mailer'
import {
  emailShell, seccionTitulo, chipEstado, tablaAbrir, tablaCerrar, celda, MARCA,
} from '@/lib/email/plantilla'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

// ============================================================================
// Aviso semanal: revisión técnica vencida o por vencer (MIG504)
// ----------------------------------------------------------------------------
// Un camión con la RT vencida no puede circular: multa, retención y el
// contrato en riesgo. Este correo llega los lunes con los equipos cuya RT ya
// venció o vence dentro de 30 días (v_certificacion_actual, papeles de flota
// MIG415-429), para agendar la planta de revisión con tiempo.
//
// Lo invoca un cron semanal (pg_cron → net.http_post) con x-cron-secret.
// Sin service_role: el secreto habilita solo fn_rt_por_vencer_cron (MIG301).
// Requiere en el servidor: CRON_SECRET, SMTP_*, RT_EMAIL_TO.
// ============================================================================

type Rt = {
  activo_id: string
  patente: string | null
  codigo: string | null
  nombre: string | null
  cliente: string | null
  fecha_vencimiento: string | null
  dias_restantes: number | null
  estado: 'vencido' | 'por_vencer'
}

const esc = (s: unknown) =>
  String(s ?? '').replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]!))

const fmtFecha = (s: string | null) =>
  s ? new Date(`${s}T12:00:00`).toLocaleDateString('es-CL',
    { day: '2-digit', month: 'short', year: 'numeric' }) : '—'

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
  const to = parseRecipients(process.env.RT_EMAIL_TO)
  if (!mailerConfigured() || to.length === 0) {
    return NextResponse.json({ error: 'SMTP o RT_EMAIL_TO no configurados.' }, { status: 500 })
  }

  const sb = createClient(url, anon, { auth: { persistSession: false } })
  const { data, error } = await sb.rpc('fn_rt_por_vencer_cron', { p_secreto: secret })
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })

  const filas = (data ?? []) as Rt[]
  if (filas.length === 0) return NextResponse.json({ ok: true, equipos: 0 })

  const vencidas = filas.filter((f) => f.estado === 'vencido')
  const porVencer = filas.filter((f) => f.estado === 'por_vencer')

  const fila = (f: Rt, i: number) => {
    const equipo = [f.patente, f.codigo].filter(Boolean).join(' · ') || '—'
    const z = i % 2 === 1
    const chip = f.dias_restantes == null
      ? chipEstado('SIN FECHA', MARCA.rojo, MARCA.rojoFondo)
      : f.dias_restantes < 0
      ? chipEstado(`vencida hace ${-f.dias_restantes} d`, MARCA.rojo, MARCA.rojoFondo)
      : f.dias_restantes === 0
      ? chipEstado('vence HOY', MARCA.rojo, MARCA.rojoFondo)
      : chipEstado(`vence en ${f.dias_restantes} d`, MARCA.ambar, MARCA.ambarFondo)
    return `<tr>
      ${celda(`<b>${esc(equipo)}</b><br><span style="color:#9ca3af;font-size:11px">${esc(f.nombre ?? '')}</span>`, z)}
      ${celda(esc(f.cliente ?? '—'), z)}
      ${celda(`<span style="white-space:nowrap">${fmtFecha(f.fecha_vencimiento)}</span>`, z)}
      ${celda(chip, z, 'text-align:right')}
    </tr>`
  }

  const tabla = (titulo: string, xs: Rt[], color: string, fondo: string) => xs.length === 0 ? '' : `
    ${seccionTitulo(`${titulo} · ${xs.length}`, color, fondo)}
    ${tablaAbrir(['Equipo', 'Cliente', 'Vence', 'Plazo'])}
    ${xs.map(fila).join('')}
    ${tablaCerrar}`

  const base = process.env.NEXT_PUBLIC_SITE_URL || 'https://pilladoiceo.netlify.app'
  const html = emailShell({
    titulo: 'Revisión técnica de la flota',
    subtitulo: `Resumen semanal · ${new Date().toLocaleDateString('es-CL', { day: '2-digit', month: 'long' })}`,
    chips: [
      ...(vencidas.length > 0
        ? [{ n: vencidas.length, label: 'RT vencidas', color: MARCA.rojo, fondo: MARCA.rojoFondo }] : []),
      ...(porVencer.length > 0
        ? [{ n: porVencer.length, label: 'Vencen en ≤30 días', color: MARCA.ambar, fondo: MARCA.ambarFondo }] : []),
    ],
    cuerpo: `
      ${vencidas.length > 0
        ? `<p style="margin:14px 0 0;font-size:13px;color:#4b5563">Un equipo con la RT
           <b style="color:${MARCA.rojo}">vencida</b> no puede circular: agenda la planta de
           revisión primero para estos.</p>` : ''}
      ${tabla('Vencidas — no pueden circular', vencidas, MARCA.rojo, MARCA.rojoFondo)}
      ${tabla('Por vencer (30 días)', porVencer, MARCA.ambar, MARCA.ambarFondo)}`,
    ctaUrl: `${base}/dashboard/flota/verificar/`,
    ctaTexto: 'Ver papeles de la flota',
    pie: 'Resumen semanal (lunes) de la revisión técnica, según el último certificado cargado por '
       + 'equipo. Al cargar la RT renovada en SICOM, el equipo sale solo de esta lista. '
       + 'Correo automático de SICOM · Pillado Empresas.',
  })

  const asunto = vencidas.length > 0
    ? `🔴 Revisión técnica: ${vencidas.length} vencida(s) y ${porVencer.length} por vencer · PILLADO`
    : `🟡 Revisión técnica: ${porVencer.length} equipo(s) vencen en 30 días · PILLADO`

  const r = await sendMail({ to, subject: asunto, html })
  if (!r.ok) return NextResponse.json({ error: r.error ?? 'No se pudo enviar' }, { status: 500 })
  return NextResponse.json({ ok: true, equipos: filas.length, vencidas: vencidas.length, por_vencer: porVencer.length })
}
