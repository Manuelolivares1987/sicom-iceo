import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { sendMail, parseRecipients, mailerConfigured } from '@/lib/email/mailer'
import {
  emailShell, seccionTitulo, chipEstado, tablaAbrir, tablaCerrar, celda, MARCA,
} from '@/lib/email/plantilla'

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
  // [MIG531] Modo PRUEBA (?prueba=1): la consulta trae SOLO el equipo de
  // laboratorio y el correo va únicamente a Manuel, con asunto [PRUEBA].
  const esPrueba = new URL(req.url).searchParams.get('prueba') === '1'
  const to = esPrueba
    ? ['manuel.olivares@pilladoempresas.cl']
    : parseRecipients(process.env.CHECKLIST_CLIENTE_EMAIL_TO)
  if (!mailerConfigured() || to.length === 0) {
    return NextResponse.json({ error: 'SMTP o CHECKLIST_CLIENTE_EMAIL_TO no configurados.' }, { status: 500 })
  }

  const sb = createClient(url, anon, { auth: { persistSession: false } })
  const { data, error } = await sb.rpc('fn_checklist_cliente_pendientes_cron', { p_secreto: secret, p_incluir_pruebas: esPrueba })
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

  const nunca = pendientes.filter((p) => p.estado === 'sin_check').length

  // [2026-09-03] Rediseño con la plantilla de marca: tarjetas con el número
  // grande, un bloque tipo píldora por CLIENTE (a quién hay que llamar), filas
  // cebra y chip con los días de atraso.
  const fila = (p: Pendiente, i: number) => {
    const equipo = [p.patente, p.codigo].filter(Boolean).join(' · ') || '—'
    const z = i % 2 === 1
    const rojo = p.estado === 'sin_check' || (p.dias_desde_ultimo ?? 0) > 14
    const chip = p.ultima_fecha
      ? chipEstado(`hace ${p.dias_desde_ultimo} días`, rojo ? MARCA.rojo : MARCA.ambar,
                   rojo ? MARCA.rojoFondo : MARCA.ambarFondo)
      : chipEstado('NUNCA', MARCA.rojo, MARCA.rojoFondo)
    const ultimo = p.ultima_fecha
      ? new Date(`${p.ultima_fecha}T12:00:00`).toLocaleDateString('es-CL')
      : 'sin registro'
    return `<tr>
      ${celda(`<b>${esc(equipo)}</b><br><span style="color:#9ca3af;font-size:11px">${esc(p.nombre ?? '')}</span>`, z)}
      ${celda(`<span style="white-space:nowrap">${esc(ultimo)}</span>`, z)}
      ${celda(chip, z, 'text-align:right')}
    </tr>`
  }

  const bloques = Array.from(porCliente.entries()).map(([cliente, eqs]) => `
    ${seccionTitulo(`${esc(cliente)} · ${eqs.length} equipo${eqs.length > 1 ? 's' : ''}`,
                    MARCA.verdeOscuro, MARCA.verdeClaro)}
    ${tablaAbrir(['Equipo', 'Último checklist', 'Atraso'])}
    ${eqs.map(fila).join('')}
    ${tablaCerrar}`).join('')

  const base = process.env.NEXT_PUBLIC_SITE_URL || 'https://pilladoiceo.netlify.app'
  const html = emailShell({
    titulo: 'Checklist del cliente pendiente',
    subtitulo: `Inspección semanal por QR · ${new Date().toLocaleDateString('es-CL', { day: '2-digit', month: 'long' })}`,
    chips: [
      ...(nunca > 0 ? [{ n: nunca, label: 'Nunca lo han hecho', color: MARCA.rojo, fondo: MARCA.rojoFondo }] : []),
      ...(pendientes.length - nunca > 0
        ? [{ n: pendientes.length - nunca, label: 'Atrasados (>7 días)', color: MARCA.ambar, fondo: MARCA.ambarFondo }] : []),
      { n: porCliente.size, label: `Cliente${porCliente.size > 1 ? 's' : ''}`, color: MARCA.verdeOscuro, fondo: MARCA.verdeClaro },
    ],
    cuerpo: `
      <p style="margin:14px 0 0;font-size:13px;color:#4b5563">
        Estos equipos fuera de instalaciones llevan <b>más de 7 días</b> sin el checklist
        semanal que el cliente debe hacer escaneando el QR del equipo.</p>
      ${bloques}`,
    ctaUrl: `${base}/dashboard/flota/checklist-cliente/`,
    ctaTexto: 'Ver panel de cumplimiento',
    pie: 'Este aviso se repite a diario mientras el atraso siga; cuando todos los clientes están '
       + 'al día, no llega nada. Correo automático de SICOM · Pillado Empresas.',
  })

  const r = await sendMail({
    to,
    subject: `${esPrueba ? '[PRUEBA] ' : ''}⚠️ ${pendientes.length} equipo(s) sin checklist del cliente · ${porCliente.size} cliente(s) · PILLADO`,
    html,
  })
  if (!r.ok) {
    return NextResponse.json({ error: r.error ?? 'No se pudo enviar' }, { status: 500 })
  }
  return NextResponse.json({ ok: true, pendientes: pendientes.length, clientes: porCliente.size })
}
