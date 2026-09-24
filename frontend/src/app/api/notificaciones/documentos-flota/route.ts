import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { sendMail, parseRecipients, mailerConfigured } from '@/lib/email/mailer'
import {
  emailShell, seccionTitulo, chipEstado, tablaAbrir, tablaCerrar, celda, MARCA,
} from '@/lib/email/plantilla'
import { nombreTipo } from '@/lib/services/control-documental'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

// ============================================================================
// Aviso diario: papeles de flota vencidos o por vencer (MIG575)
// ----------------------------------------------------------------------------
// TODOS los documentos del equipo (RT, SOAP, permiso, hermeticidad, gases,
// SEC, mantención por horas…), con los equipos ARRENDADOS o en LEASING
// primero: son los que el cliente puede parar en la puerta de la faena.
//
// Diario, pero solo si hay algo nuevo: un papel que entró a la lista o bajó de
// tramo (vencido · ≤7 d · ≤15 d · ≤30 d · ≤50 h). Los lunes sale igual, como
// recordatorio completo. La base lleva la cuenta de lo avisado
// (docs_flota_avisos) y se marca DESPUÉS de que el correo salió.
//
// Reemplaza al aviso semanal de revisión técnica (MIG504, pausado).
// Lo invoca el cron 'documentos-flota-diario' con x-cron-secret; sin service_role.
// Destinatarios: DOCS_FLOTA_EMAIL_TO (si no está, RT_EMAIL_TO).
// ?prueba=1 → solo el equipo de laboratorio, solo a Manuel, sin marcar nada.
// ?forzar=1 → manda aunque no haya novedades.
// ?previa=1 → datos REALES, pero solo a Manuel y sin marcar (para ver el correo antes).
// ============================================================================

type Doc = {
  certificacion_id: string
  activo_id: string
  patente: string | null
  codigo: string | null
  nombre: string | null
  cliente: string | null
  estado_comercial: string | null
  en_arriendo: boolean
  zona: string
  faena: string | null
  documento: string
  fecha_vencimiento: string | null
  dias_restantes: number | null
  horas_restantes: number | null
  estado: 'vencido' | 'por_vencer'
  bloqueante: boolean
  tramo: string
  nuevo: boolean
}

const esc = (s: unknown) =>
  String(s ?? '').replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]!))

const fmtFecha = (s: string | null) =>
  s ? new Date(`${s}T12:00:00`).toLocaleDateString('es-CL',
    { day: '2-digit', month: 'short', year: 'numeric' }) : '—'

const COMERCIAL: Record<string, string> = { arrendado: 'Arrendado', leasing: 'Leasing' }

function plazo(d: Doc): string {
  if (d.estado === 'vencido') {
    const hace = d.dias_restantes != null && d.dias_restantes < 0 ? ` hace ${-d.dias_restantes} d` : ''
    return chipEstado(`vencido${hace}`, MARCA.rojo, MARCA.rojoFondo)
  }
  if (d.horas_restantes != null) return chipEstado(`quedan ${d.horas_restantes} h`, MARCA.ambar, MARCA.ambarFondo)
  if (d.dias_restantes === 0) return chipEstado('vence HOY', MARCA.rojo, MARCA.rojoFondo)
  const urgente = (d.dias_restantes ?? 99) <= 7
  return chipEstado(`vence en ${d.dias_restantes} d`,
    urgente ? MARCA.rojo : MARCA.ambar, urgente ? MARCA.rojoFondo : MARCA.ambarFondo)
}

/** Hoy en Chile, para decidir el recordatorio del lunes. */
function esLunesEnChile(): boolean {
  const dia = new Intl.DateTimeFormat('en-US', { timeZone: 'America/Santiago', weekday: 'short' })
    .format(new Date())
  return dia === 'Mon'
}

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
  const qs = new URL(req.url).searchParams
  const esPrueba = qs.get('prueba') === '1'
  const previa = qs.get('previa') === '1'
  const forzar = qs.get('forzar') === '1' || previa
  const to = esPrueba || previa
    ? ['manuel.olivares@pilladoempresas.cl']
    : parseRecipients(process.env.DOCS_FLOTA_EMAIL_TO || process.env.RT_EMAIL_TO)
  if (!mailerConfigured() || to.length === 0) {
    return NextResponse.json({ error: 'SMTP o DOCS_FLOTA_EMAIL_TO no configurados.' }, { status: 500 })
  }

  const sb = createClient(url, anon, { auth: { persistSession: false } })
  const { data, error } = await sb.rpc('fn_docs_flota_cron', { p_secreto: secret, p_incluir_pruebas: esPrueba })
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })

  const docs = (data ?? []) as Doc[]
  const nuevos = docs.filter((d) => d.nuevo)
  const lunes = esLunesEnChile()
  if (docs.length === 0 || (nuevos.length === 0 && !lunes && !forzar)) {
    return NextResponse.json({ ok: true, enviado: false, papeles: docs.length, nuevos: 0 })
  }

  // Un renglón por equipo, con todos sus papeles adentro. La función ya viene
  // ordenada: arrendados primero, luego zona, patente, vencidos antes.
  const porEquipo = new Map<string, Doc[]>()
  for (const d of docs) porEquipo.set(d.activo_id, [...(porEquipo.get(d.activo_id) ?? []), d])
  const equipos = Array.from(porEquipo.values())
  const arrendados = equipos.filter((xs) => xs[0].en_arriendo)
  const resto = equipos.filter((xs) => !xs[0].en_arriendo)

  const renglon = (xs: Doc[], i: number) => {
    const a = xs[0]
    const z = i % 2 === 1
    const equipo = [a.patente, a.codigo].filter(Boolean).join(' · ') || '—'
    const donde = [a.cliente, a.faena].filter(Boolean).map(esc).join('<br>') || '—'
    const papeles = xs.map((d) => `
      <div style="margin:0 0 6px">
        ${d.nuevo ? chipEstado('NUEVO', '#ffffff', MARCA.naranjo) + ' ' : ''}<b>${esc(nombreTipo(d.documento))}</b>
        ${d.bloqueante ? '<span style="color:#9ca3af;font-size:11px"> · bloqueante</span>' : ''}<br>
        ${plazo(d)} <span style="color:#9ca3af;font-size:11px;white-space:nowrap">${d.horas_restantes != null ? 'por horómetro' : fmtFecha(d.fecha_vencimiento)}</span>
      </div>`).join('')
    return `<tr>
      ${celda(`<b>${esc(equipo)}</b><br><span style="color:#9ca3af;font-size:11px">${esc(a.nombre ?? '')}</span><br><span style="color:#6b7280;font-size:11px">${esc(COMERCIAL[a.estado_comercial ?? ''] ?? '')} · ${esc(a.zona)}</span>`, z)}
      ${celda(`<span style="font-size:12px">${donde}</span>`, z)}
      ${celda(papeles, z)}
    </tr>`
  }

  const bloque = (titulo: string, xs: Doc[][], rojo: boolean) => xs.length === 0 ? '' : `
    ${seccionTitulo(titulo, rojo ? MARCA.rojo : MARCA.verdeOscuro, rojo ? MARCA.rojoFondo : MARCA.verdeClaro)}
    ${tablaAbrir(['Equipo', 'Cliente / dónde', 'Papeles'])}
    ${xs.map(renglon).join('')}
    ${tablaCerrar}`

  const vencidos = docs.filter((d) => d.estado === 'vencido').length
  const porVencer = docs.length - vencidos
  const papelesArriendo = arrendados.reduce((n, xs) => n + xs.length, 0)

  const base = process.env.NEXT_PUBLIC_SITE_URL || 'https://pilladoiceo.netlify.app'
  const html = emailShell({
    titulo: 'Papeles de la flota',
    subtitulo: `${nuevos.length > 0 ? 'Novedades del día' : 'Recordatorio semanal'} · ${new Date().toLocaleDateString('es-CL', { timeZone: 'America/Santiago', day: '2-digit', month: 'long' })}`,
    chips: [
      ...(nuevos.length > 0 ? [{ n: nuevos.length, label: 'Nuevos hoy', color: '#ffffff', fondo: MARCA.naranjo }] : []),
      ...(vencidos > 0 ? [{ n: vencidos, label: 'Vencidos', color: MARCA.rojo, fondo: MARCA.rojoFondo }] : []),
      ...(porVencer > 0 ? [{ n: porVencer, label: 'Vencen pronto', color: MARCA.ambar, fondo: MARCA.ambarFondo }] : []),
      { n: papelesArriendo, label: 'En equipos arrendados', color: MARCA.verdeOscuro, fondo: MARCA.verdeClaro },
    ],
    cuerpo: `
      <p style="margin:14px 0 0;font-size:13px;color:#4b5563">Papeles vencidos o que vencen en
        los próximos 30 días (o 50 horas de horómetro). Primero los equipos <b>arrendados o en
        leasing</b>: el cliente puede no dejarlos entrar a faena. ${nuevos.length > 0
          ? `Lo marcado <b style="color:${MARCA.naranjo}">NUEVO</b> entró hoy a la lista o se acercó más al vencimiento.` : ''}</p>
      ${bloque(`🚚 En arriendo o leasing · ${arrendados.length} equipo${arrendados.length === 1 ? '' : 's'}`, arrendados, true)}
      ${bloque(`🏠 Resto de la flota · ${resto.length} equipo${resto.length === 1 ? '' : 's'}`, resto, false)}`,
    ctaUrl: `${base}/dashboard/flota/control-documental/`,
    ctaTexto: 'Abrir Control documental de flota',
    pie: 'Aviso diario: sale solo cuando hay novedades, y los lunes como recordatorio completo. '
       + 'Al cargar el papel renovado en SICOM, sale solo de esta lista. '
       + 'Correo automático de SICOM · Pillado Empresas.',
  })

  const nuevosArriendo = nuevos.filter((d) => d.en_arriendo).length
  const asunto = (esPrueba ? '[PRUEBA] ' : previa ? '[VISTA PREVIA] ' : '')
    + (vencidos > 0 ? '🔴 ' : '🟡 ')
    + `Papeles de flota: ${vencidos} vencido(s), ${porVencer} por vencer`
    + (nuevos.length > 0 ? ` · ${nuevos.length} nuevo(s)${nuevosArriendo > 0 ? `, ${nuevosArriendo} en arriendo` : ''}` : '')
    + ' · PILLADO'

  const r = await sendMail({ to, subject: asunto, html })
  if (!r.ok) return NextResponse.json({ error: r.error ?? 'No se pudo enviar' }, { status: 500 })

  if (!esPrueba && !previa) {
    const items = docs.map((d) => ({ certificacion_id: d.certificacion_id, tramo: d.tramo }))
    const { error: eMarca } = await sb.rpc('fn_docs_flota_marcar_cron', { p_secreto: secret, p_items: items })
    if (eMarca) return NextResponse.json({ ok: true, enviado: true, marcado: false, error: eMarca.message })
  }
  return NextResponse.json({
    ok: true, enviado: true, papeles: docs.length, nuevos: nuevos.length,
    equipos: equipos.length, arrendados: arrendados.length, vencidos, por_vencer: porVencer,
  })
}
