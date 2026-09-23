import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { sendMail, parseRecipients, mailerConfigured } from '@/lib/email/mailer'
import {
  emailShell, seccionTitulo, chipEstado, tablaAbrir, tablaCerrar, celda, MARCA,
} from '@/lib/email/plantilla'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

// ============================================================================
// Centinela de flota: el camión que deja de reportar GPS, avisa (MIG571)
// ----------------------------------------------------------------------------
// KVWD-27 estuvo 110 días con el tracker cortado (se apagó yendo a 57 km/h) y
// las 48 alertas que generó el sistema quedaron en una tabla que nadie mira.
// Este correo es la salida de esas alertas:
//
//  · modo 'inmediato' (cada hora): críticos nuevos, críticos que nadie tomó en
//    N horas (escalamiento, con copia a CENTINELA_ESCALA_TO) y críticos que
//    volvieron a reportar solos. Silencio si no hay nada.
//  · modo 'resumen' (diario): todo lo abierto + arrendados sin geocerca.
//
// La evaluación la hace la base (fn_centinela_evaluar, cron a los :15); acá
// solo se lee y se avisa. Sin service_role: el secreto habilita solo las dos
// funciones *_cron (MIG301). Requiere CRON_SECRET, SMTP_*, CENTINELA_EMAIL_TO.
// ?prueba=1 manda a Manuel con [PRUEBA] y NO marca nada como avisado.
// ============================================================================

type Incidente = {
  id: string
  patente: string | null
  codigo: string | null
  nombre: string | null
  cliente: string | null
  operacion: string | null
  estado_comercial: string | null
  regla: 'corte_en_marcha' | 'sin_senal'
  severidad: 'vigilar' | 'alto' | 'critico'
  estado: 'abierto' | 'acusado' | 'cerrado'
  ultimo_contacto: string | null
  horas_sin_contacto: number | null
  latitud: number | null
  longitud: number | null
  velocidad_kmh: number | null
  ignicion: boolean | null
  bateria_pct: number | null
  notificado_en: string | null
  latitud_actual: number | null
  longitud_actual: number | null
  contacto_actual: string | null
  detalle_cierre: string | null
  cortes_recuperados_60d: number
}

type Payload = {
  ingesta: { ultimo_poll: string | null; caida: boolean; avisar: boolean }
  horas_escalar: number
  nuevos: Incidente[]
  escalar: Incidente[]
  recuperados: Incidente[]
  abiertos?: Incidente[]
  sin_geocerca?: { patente: string | null; codigo: string | null; cliente: string | null; contrato: string | null }[]
}

const esc = (s: unknown) =>
  String(s ?? '').replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]!))

const fmtFechaHora = (s: string | null) =>
  s ? new Date(s).toLocaleString('es-CL', {
    timeZone: 'America/Santiago', day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit',
  }) : '—'

const fmtSilencio = (h: number | null) => {
  if (h == null) return '—'
  if (h < 48) return `${Math.round(h)} h`
  return `${Math.round(h / 24)} días`
}

const mapa = (lat: number | null, lng: number | null, texto = 'Ver mapa') =>
  lat != null && lng != null
    ? `<a href="https://maps.google.com/?q=${lat},${lng}" style="color:${MARCA.verdeOscuro};font-weight:700">${texto}</a>`
    : '—'

/** Cómo estaba el camión cuando el tracker se calló: la pista de si es sospechoso. */
const alCortarse = (i: Incidente) => {
  const bat = i.bateria_pct != null ? `batería ${Math.round(i.bateria_pct)}%` : null
  if (i.regla === 'corte_en_marcha') {
    const vel = i.velocidad_kmh && i.velocidad_kmh > 0 ? `a ${Math.round(i.velocidad_kmh)} km/h` : 'detenido'
    return [`<b>se cortó andando</b> ${vel}`, i.ignicion ? 'motor encendido' : null, bat].filter(Boolean).join(', ')
  }
  return ['detenido', i.ignicion ? 'motor encendido' : 'motor apagado', bat].filter(Boolean).join(', ')
}

const chipSev = (s: Incidente['severidad']) =>
  s === 'critico' ? chipEstado('CRÍTICO', MARCA.rojo, MARCA.rojoFondo)
  : s === 'alto' ? chipEstado('ALTO', MARCA.ambar, MARCA.ambarFondo)
  : chipEstado('VIGILAR', MARCA.verdeOscuro, MARCA.verdeClaro)

function tablaIncidentes(xs: Incidente[], conSeveridad = false) {
  const fila = (i: Incidente, n: number) => {
    const z = n % 2 === 1
    const equipo = [i.patente, i.codigo].filter(Boolean).join(' · ') || '—'
    const historial = i.cortes_recuperados_60d > 0
      ? `<br><span style="color:#6b7280;font-size:11px">Se cortó ${i.cortes_recuperados_60d} vez/veces en 60 días y volvió solo: puede ser zona sin cobertura.</span>`
      : ''
    return `<tr>
      ${celda(`<b>${esc(equipo)}</b>${conSeveridad ? ` ${chipSev(i.severidad)}` : ''}<br><span style="color:#9ca3af;font-size:11px">${esc(i.nombre ?? '')}</span>`, z)}
      ${celda(`${esc(i.cliente ?? '—')}<br><span style="color:#9ca3af;font-size:11px">${esc(i.estado_comercial ?? '')}${i.operacion ? ` · ${esc(i.operacion)}` : ''}</span>`, z)}
      ${celda(`<b style="color:${MARCA.rojo}">${fmtSilencio(i.horas_sin_contacto)}</b><br><span style="color:#9ca3af;font-size:11px">desde ${fmtFechaHora(i.ultimo_contacto)}</span>`, z)}
      ${celda(`${alCortarse(i)}${historial}`, z)}
      ${celda(mapa(i.latitud, i.longitud, 'Último punto'), z, 'text-align:right;white-space:nowrap')}
    </tr>`
  }
  return `${tablaAbrir(['Equipo', 'Cliente', 'Mudo hace', 'Al cortarse', ''])}
    ${xs.map(fila).join('')}
    ${tablaCerrar}`
}

const PROTOCOLO = `
  <div style="margin:16px 0 0;padding:12px 16px;border-left:4px solid ${MARCA.rojo};background:#fff7f7;font-size:13px;color:#374151">
    <b>Qué hacer con cada crítico</b>
    <ol style="margin:6px 0 0 18px;padding:0">
      <li>Llamar al cliente o a la faena (portería, administrador del contrato) y pedir <b>foto del camión con el horómetro visible</b>.</li>
      <li>Pedir a Radicom el historial de eventos del tracker: ¿registró corte de alimentación antes de apagarse?</li>
      <li><b>Acusar recibo en SICOM</b>: si nadie lo toma en unas horas, el aviso se escala.</li>
      <li>Si en 24–48 h nadie confirma dónde está el camión: evaluar la denuncia con la patente y el último punto GPS.</li>
    </ol>
  </div>`

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
  const esPrueba = new URL(req.url).searchParams.get('prueba') === '1'
  const body = await req.json().catch(() => ({})) as { modo?: string }
  const modo = body.modo === 'resumen' ? 'resumen' : 'inmediato'

  const to = esPrueba
    ? ['manuel.olivares@pilladoempresas.cl']
    : parseRecipients(process.env.CENTINELA_EMAIL_TO)
  const escala = esPrueba ? [] : parseRecipients(process.env.CENTINELA_ESCALA_TO)
  if (!mailerConfigured() || to.length === 0) {
    return NextResponse.json({ error: 'SMTP o CENTINELA_EMAIL_TO no configurados.' }, { status: 500 })
  }

  const sb = createClient(url, anon, { auth: { persistSession: false } })
  const { data, error } = await sb.rpc('fn_centinela_correo_cron', { p_secreto: secret, p_modo: modo })
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  const p = data as Payload

  const base = process.env.NEXT_PUBLIC_SITE_URL || 'https://pilladoiceo.netlify.app'
  const cta = { ctaUrl: `${base}/dashboard/flota/centinela/`, ctaTexto: 'Abrir Centinela de flota' }
  const hoy = new Date().toLocaleDateString('es-CL', { timeZone: 'America/Santiago', day: '2-digit', month: 'long' })

  const bloqueIngesta = p.ingesta.caida ? `
    ${seccionTitulo('⚠️ El GPS de toda la flota dejó de llegar a SICOM', MARCA.rojo, MARCA.rojoFondo)}
    <p style="margin:10px 0 0;font-size:13px;color:#4b5563">Último poll a Radicom: <b>${fmtFechaHora(p.ingesta.ultimo_poll)}</b>.
    Mientras no llegue información, el Centinela <b>no puede vigilar</b> ningún camión. Revisar la
    función <code>gps-radicom-poll</code> y la API de Navixy.</p>` : ''

  let asunto: string
  let html: string
  let marcar = { nuevos: [] as string[], escalados: [] as string[], recuperados: [] as string[], ingesta: false }

  if (modo === 'inmediato') {
    const hayAlgo = p.nuevos.length + p.escalar.length + p.recuperados.length > 0 || p.ingesta.avisar
    if (!hayAlgo) return NextResponse.json({ ok: true, enviado: false })

    const cuerpo = [
      p.ingesta.avisar ? bloqueIngesta : '',
      p.nuevos.length > 0 ? `
        ${seccionTitulo(`🔴 Dejaron de reportar · ${p.nuevos.length}`, MARCA.rojo, MARCA.rojoFondo)}
        ${tablaIncidentes(p.nuevos)}
        ${PROTOCOLO}` : '',
      p.escalar.length > 0 ? `
        ${seccionTitulo(`⏰ Nadie los ha tomado en ${p.horas_escalar} h · ${p.escalar.length}`, MARCA.ambar, MARCA.ambarFondo)}
        <p style="margin:10px 0 0;font-size:13px;color:#4b5563">Se avisaron y siguen sin acuse de recibo en SICOM.</p>
        ${tablaIncidentes(p.escalar)}` : '',
      p.recuperados.length > 0 ? `
        ${seccionTitulo(`✅ Volvieron a reportar · ${p.recuperados.length}`, MARCA.verdeOscuro, MARCA.verdeClaro)}
        ${tablaAbrir(['Equipo', 'Estuvo mudo', 'Volvió', 'Dónde está ahora'])}
        ${p.recuperados.map((i, n) => `<tr>
          ${celda(`<b>${esc([i.patente, i.codigo].filter(Boolean).join(' · '))}</b>`, n % 2 === 1)}
          ${celda(fmtSilencio(i.horas_sin_contacto), n % 2 === 1)}
          ${celda(fmtFechaHora(i.contacto_actual), n % 2 === 1)}
          ${celda(mapa(i.latitud_actual, i.longitud_actual, 'Ubicación actual'), n % 2 === 1, 'text-align:right')}
        </tr>`).join('')}
        ${tablaCerrar}` : '',
    ].join('')

    html = emailShell({
      titulo: 'Centinela de flota',
      subtitulo: `Aviso · ${hoy}`,
      chips: [
        ...(p.nuevos.length ? [{ n: p.nuevos.length, label: 'Críticos nuevos', color: MARCA.rojo, fondo: MARCA.rojoFondo }] : []),
        ...(p.escalar.length ? [{ n: p.escalar.length, label: 'Sin respuesta', color: MARCA.ambar, fondo: MARCA.ambarFondo }] : []),
        ...(p.recuperados.length ? [{ n: p.recuperados.length, label: 'Volvieron', color: MARCA.verdeOscuro, fondo: MARCA.verdeClaro }] : []),
      ],
      cuerpo,
      ...cta,
      pie: 'Un camión pasa a crítico cuando el GPS se cortó andando y no vuelve en 48 h, o cuando un '
         + 'equipo en arriendo lleva 7 días sin contacto. Correo automático de SICOM · Pillado Empresas.',
    })
    const partes = [
      p.nuevos.length ? `${p.nuevos.length} camión(es) dejaron de reportar` : '',
      p.escalar.length ? `${p.escalar.length} sin respuesta` : '',
      p.recuperados.length ? `${p.recuperados.length} volvieron` : '',
      p.ingesta.avisar ? 'GPS caído' : '',
    ].filter(Boolean).join(' · ')
    asunto = `${p.nuevos.length || p.escalar.length || p.ingesta.avisar ? '🔴' : '✅'} Centinela: ${partes} · PILLADO`
    marcar = {
      nuevos: p.nuevos.map((i) => i.id),
      escalados: p.escalar.map((i) => i.id),
      recuperados: p.recuperados.map((i) => i.id),
      ingesta: p.ingesta.avisar,
    }
  } else {
    const abiertos = p.abiertos ?? []
    const sinGeo = p.sin_geocerca ?? []
    if (abiertos.length === 0 && sinGeo.length === 0 && !p.ingesta.caida) {
      return NextResponse.json({ ok: true, enviado: false })
    }
    const nCrit = abiertos.filter((i) => i.severidad === 'critico').length
    const sinTomar = abiertos.filter((i) => i.severidad === 'critico' && i.estado === 'abierto').length
    const porSev = (s: Incidente['severidad']) => abiertos.filter((i) => i.severidad === s)
    const titulos: Record<Incidente['severidad'], [string, string, string]> = {
      critico: ['🔴 Críticos', MARCA.rojo, MARCA.rojoFondo],
      alto: ['🟠 Detenidos y mudos más de 3 días', MARCA.ambar, MARCA.ambarFondo],
      vigilar: ['🟡 Cortes recientes andando (vigilar, todavía sin correo)', MARCA.verdeOscuro, MARCA.verdeClaro],
    }
    const cuerpo = [
      bloqueIngesta,
      ...(['critico', 'alto', 'vigilar'] as const).map((s) => {
        const xs = porSev(s)
        if (xs.length === 0) return ''
        const [t, c, f] = titulos[s]
        return `${seccionTitulo(`${t} · ${xs.length}`, c, f)}${tablaIncidentes(xs)}`
      }),
      sinGeo.length > 0 ? `
        ${seccionTitulo(`📍 Arrendados sin zona definida · ${sinGeo.length}`, MARCA.ambar, MARCA.ambarFondo)}
        <p style="margin:10px 0 0;font-size:13px;color:#4b5563">Su contrato no tiene geocerca: no se puede saber si salieron de su zona de trabajo.</p>
        ${tablaAbrir(['Equipo', 'Cliente', 'Contrato'])}
        ${sinGeo.map((g, n) => `<tr>
          ${celda(`<b>${esc([g.patente, g.codigo].filter(Boolean).join(' · '))}</b>`, n % 2 === 1)}
          ${celda(esc(g.cliente ?? '—'), n % 2 === 1)}
          ${celda(esc(g.contrato ?? '—'), n % 2 === 1)}
        </tr>`).join('')}
        ${tablaCerrar}` : '',
    ].join('')

    html = emailShell({
      titulo: 'Centinela de flota',
      subtitulo: `Resumen del día · ${hoy}`,
      chips: [
        { n: nCrit, label: 'Críticos', color: MARCA.rojo, fondo: MARCA.rojoFondo },
        { n: sinTomar, label: 'Sin acuse', color: MARCA.ambar, fondo: MARCA.ambarFondo },
        { n: abiertos.length, label: 'Abiertos', color: MARCA.verdeOscuro, fondo: MARCA.verdeClaro },
      ],
      cuerpo,
      ...cta,
      pie: 'Resumen diario de los equipos que no reportan GPS. Un incidente se cierra solo cuando el '
         + 'tracker vuelve, o en SICOM con el motivo y lo que se verificó. Correo automático de SICOM · Pillado Empresas.',
    })
    asunto = `${nCrit > 0 ? '🔴' : '🟡'} Centinela · resumen: ${nCrit} crítico(s), ${abiertos.length} abierto(s) · PILLADO`
  }

  const r = await sendMail({
    to,
    cc: marcar.escalados.length > 0 ? escala : undefined,
    subject: (esPrueba ? '[PRUEBA] ' : '') + asunto,
    html,
  })
  if (!r.ok) return NextResponse.json({ error: r.error ?? 'No se pudo enviar' }, { status: 500 })

  if (!esPrueba && modo === 'inmediato') {
    const { error: e2 } = await sb.rpc('fn_centinela_marcar_cron', {
      p_secreto: secret,
      p_nuevos: marcar.nuevos,
      p_escalados: marcar.escalados,
      p_recuperados: marcar.recuperados,
      p_ingesta: marcar.ingesta,
    })
    if (e2) return NextResponse.json({ ok: true, enviado: true, error_marcar: e2.message }, { status: 500 })
  }
  return NextResponse.json({ ok: true, enviado: true, modo, ...Object.fromEntries(
    Object.entries(marcar).map(([k, v]) => [k, Array.isArray(v) ? v.length : v])) })
}
