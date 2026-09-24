import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { sendMail, parseRecipients, mailerConfigured } from '@/lib/email/mailer'
import { correoSimple, type ItemSimple, type SeccionSimple } from '@/lib/email/simple'

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
// Formato simple (lib/email/simple.ts) agrupado por zona, para no caer en no deseado (24-09).
// ============================================================================

type Incidente = {
  id: string
  patente: string | null
  codigo: string | null
  nombre: string | null
  cliente: string | null
  operacion: string | null
  estado_comercial: string | null
  regla: 'corte_en_marcha' | 'sin_senal' | 'fuera_de_zona' | 'fuera_de_horario'
  /** [MIG572] Texto de la situación para zona/horario. */
  detalle: string | null
  horas_fuera: number | null
  abierto_en: string
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
  /** [MIG572] Contratos cuya zona falta o no está verificada, y arrendados sin contrato. */
  zonas_por_verificar?: { contrato: string; cliente: string | null; problema: string; equipos: string | null }[]
}

const fmtFechaHora = (s: string | null) =>
  s ? new Date(s).toLocaleString('es-CL', {
    timeZone: 'America/Santiago', day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit',
  }) : '—'

const fmtSilencio = (h: number | null) => {
  if (h == null) return '—'
  if (h < 48) return `${Math.round(h)} h`
  return `${Math.round(h / 24)} días`
}

const mapa = (lat: number | null, lng: number | null) =>
  lat != null && lng != null ? `https://maps.google.com/?q=${lat},${lng}` : undefined

/** Cómo estaba el camión cuando el tracker se calló: la pista de si es sospechoso. */
const alCortarse = (i: Incidente) => {
  if (i.regla === 'fuera_de_zona' || i.regla === 'fuera_de_horario') return i.detalle ?? ''
  const bat = i.bateria_pct != null ? `batería ${Math.round(i.bateria_pct)}%` : null
  if (i.regla === 'corte_en_marcha') {
    const vel = i.velocidad_kmh && i.velocidad_kmh > 0 ? `a ${Math.round(i.velocidad_kmh)} km/h` : 'detenido'
    return ['Se cortó andando ' + vel, i.ignicion ? 'motor encendido' : null, bat].filter(Boolean).join(', ')
  }
  return ['Detenido', i.ignicion ? 'motor encendido' : 'motor apagado', bat].filter(Boolean).join(', ')
}

const SEV: Record<Incidente['severidad'], string> = { critico: 'CRÍTICO', alto: 'ALTO', vigilar: 'VIGILAR' }
const ORDEN_ZONA = ['Coquimbo', 'Calama']
const zonaDe = (i: Incidente) => i.operacion?.trim() || 'Sin zona'

function itemIncidente(i: Incidente, conSeveridad = false): ItemSimple {
  const equipo = [i.patente, i.codigo].filter(Boolean).join(' · ') || 'Sin patente'
  const hace = i.regla === 'fuera_de_zona'
    ? `Fuera de su zona hace ${fmtSilencio(i.horas_fuera)}`
    : i.regla === 'fuera_de_horario'
    ? `Fuera de horario (${fmtFechaHora(i.abierto_en)})`
    : `Sin GPS hace ${fmtSilencio(i.horas_sin_contacto)} (desde ${fmtFechaHora(i.ultimo_contacto)})`
  const lineas: ItemSimple['lineas'] = [
    { texto: hace, alerta: true },
    { texto: alCortarse(i), url: mapa(i.latitud, i.longitud) },
  ]
  if (i.cortes_recuperados_60d > 0) {
    lineas.push({ texto: `Se cortó ${i.cortes_recuperados_60d} vez/veces en 60 días y volvió solo: puede ser zona sin cobertura.` })
  }
  return {
    titulo: (conSeveridad ? `[${SEV[i.severidad]}] ` : '') + equipo,
    sub: [i.nombre, i.cliente, i.estado_comercial, zonaDe(i)].filter(Boolean).join(' · '),
    lineas,
  }
}

/** Una sección por zona (Coquimbo, Calama, resto), manteniendo el orden recibido. */
function porZona(xs: Incidente[], titulo: (zona: string, n: number) => string,
                 conSeveridad = false): SeccionSimple[] {
  const m = new Map<string, Incidente[]>()
  for (const i of xs) m.set(zonaDe(i), [...(m.get(zonaDe(i)) ?? []), i])
  return Array.from(m.keys())
    .sort((a, b) => {
      const ia = ORDEN_ZONA.indexOf(a), ib = ORDEN_ZONA.indexOf(b)
      return (ia < 0 ? 99 : ia) - (ib < 0 ? 99 : ib) || a.localeCompare(b)
    })
    .map((z) => ({ titulo: titulo(z, m.get(z)!.length), items: m.get(z)!.map((i) => itemIncidente(i, conSeveridad)) }))
}

const PROTOCOLO = 'Qué hacer con cada crítico: 1) llamar al cliente o a la faena y pedir foto del camión '
  + 'con el horómetro visible; 2) pedir a Radicom el historial del tracker (¿corte de alimentación antes '
  + 'de apagarse?); 3) acusar recibo en SICOM, si nadie lo toma en unas horas el aviso se escala; '
  + '4) si en 24–48 h nadie confirma dónde está, evaluar la denuncia con la patente y el último punto GPS.'

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
  const cta = `${base}/dashboard/flota/centinela/`
  const hoy = new Date().toLocaleDateString('es-CL', { timeZone: 'America/Santiago', day: '2-digit', month: 'long' })

  const avisoIngesta = 'ATENCIÓN: el GPS de toda la flota dejó de llegar a SICOM. Último poll a Radicom: '
    + `${fmtFechaHora(p.ingesta.ultimo_poll)}. Mientras no llegue información, el Centinela no puede vigilar `
    + 'ningún camión (revisar la función gps-radicom-poll y la API de Navixy).'

  let asunto: string
  let correo: { html: string; text: string }
  let marcar = { nuevos: [] as string[], escalados: [] as string[], recuperados: [] as string[], ingesta: false }

  if (modo === 'inmediato') {
    const hayAlgo = p.nuevos.length + p.escalar.length + p.recuperados.length > 0 || p.ingesta.avisar
    if (!hayAlgo) return NextResponse.json({ ok: true, enviado: false })

    const secciones: SeccionSimple[] = [
      ...porZona(p.nuevos, (z, n) => `Críticos nuevos — ${z} (${n})`),
      ...porZona(p.escalar, (z, n) => `Nadie los ha tomado en ${p.horas_escalar} h — ${z} (${n})`),
      {
        titulo: `Se normalizaron (${p.recuperados.length})`,
        items: p.recuperados.map((i) => ({
          titulo: [i.patente, i.codigo].filter(Boolean).join(' · ') || 'Sin patente',
          sub: zonaDe(i),
          lineas: [
            { texto: i.detalle_cierre ?? 'Volvió a reportar' },
            { texto: `Último contacto: ${fmtFechaHora(i.contacto_actual)}`, url: mapa(i.latitud_actual, i.longitud_actual) },
          ],
        })),
      },
    ]
    correo = correoSimple({
      titulo: `Centinela de flota — aviso ${hoy}`,
      intro: [...(p.ingesta.avisar ? [avisoIngesta] : []), ...(p.nuevos.length > 0 ? [PROTOCOLO] : [])],
      secciones,
      enlace: { url: cta, texto: 'Abrir Centinela de flota en SICOM' },
      pie: 'Aviso automático de SICOM. Un camión pasa a crítico cuando el GPS se cortó andando y no vuelve '
         + 'en 48 h, cuando un equipo en arriendo lleva 7 días sin contacto, o cuando lleva 12 h fuera de la '
         + 'zona verificada de su contrato.',
    })
    const partes = [
      p.nuevos.length ? `${p.nuevos.length} crítico(s) nuevo(s)` : '',
      p.escalar.length ? `${p.escalar.length} sin respuesta` : '',
      p.recuperados.length ? `${p.recuperados.length} normalizado(s)` : '',
      p.ingesta.avisar ? 'GPS caído' : '',
    ].filter(Boolean).join(', ')
    asunto = `Centinela GPS: ${partes}`
    marcar = {
      nuevos: p.nuevos.map((i) => i.id),
      escalados: p.escalar.map((i) => i.id),
      recuperados: p.recuperados.map((i) => i.id),
      ingesta: p.ingesta.avisar,
    }
  } else {
    const abiertos = p.abiertos ?? []
    const sinGeo = p.zonas_por_verificar ?? []
    if (abiertos.length === 0 && sinGeo.length === 0 && !p.ingesta.caida) {
      return NextResponse.json({ ok: true, enviado: false })
    }
    const nCrit = abiertos.filter((i) => i.severidad === 'critico').length
    const sinTomar = abiertos.filter((i) => i.severidad === 'critico' && i.estado === 'abierto').length
    // Dentro de cada zona: críticos, luego altos, luego vigilar.
    const rango = { critico: 0, alto: 1, vigilar: 2 } as const
    const ordenados = [...abiertos].sort((x, y) => rango[x.severidad] - rango[y.severidad])
    const secciones: SeccionSimple[] = [
      ...porZona(ordenados, (z, n) => `${z} — ${n} equipo${n === 1 ? '' : 's'} sin reportar o fuera de zona`, true),
      {
        titulo: `Zonas de contrato que faltan o sin verificar (${sinGeo.length})`,
        nota: 'Mientras la zona de un contrato no esté verificada, el Centinela no puede avisar en crítico '
            + 'si sus camiones salen de ella. Se verifica en Centinela → Zonas por contrato.',
        items: sinGeo.map((g) => ({
          titulo: g.contrato,
          sub: g.cliente ?? undefined,
          lineas: [{ texto: g.problema }, ...(g.equipos ? [{ texto: `Equipos: ${g.equipos}` }] : [])],
        })),
      },
    ]
    correo = correoSimple({
      titulo: `Centinela de flota — resumen ${hoy}`,
      intro: [
        ...(p.ingesta.caida ? [avisoIngesta] : []),
        `${nCrit} crítico(s), ${sinTomar} todavía sin acuse, ${abiertos.length} incidente(s) abierto(s) en total. `
        + 'CRÍTICO = correo inmediato; ALTO = detenido y mudo más de 3 días; VIGILAR = corte reciente andando, todavía sin correo.',
      ],
      secciones,
      enlace: { url: cta, texto: 'Abrir Centinela de flota en SICOM' },
      pie: 'Resumen diario automático de SICOM. Un incidente se cierra solo cuando el tracker vuelve, '
         + 'o en SICOM con el motivo y lo que se verificó.',
    })
    asunto = `Centinela GPS, resumen del día: ${nCrit} crítico(s), ${abiertos.length} abierto(s)`
  }

  const r = await sendMail({
    to,
    cc: marcar.escalados.length > 0 ? escala : undefined,
    subject: (esPrueba ? '[PRUEBA] ' : '') + asunto,
    html: correo.html,
    text: correo.text,
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
