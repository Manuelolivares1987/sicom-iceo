import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { sendMail, mailerConfigured } from '@/lib/email/mailer'
import { correoSimple, type ItemSimple } from '@/lib/email/simple'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

// ============================================================================
// Resumen diario de la bitácora de Franke (MIG696) — 07:00 Chile
// ----------------------------------------------------------------------------
// A los supervisores de AMBOS turnos (el que está de descanso también se
// entera de lo que pasa) con copia a Manuel. Las críticas que alguien no ha
// leído en 12 h desde que llegaron al servidor van arriba, con el nombre de
// quien falta: es el escalamiento. Un día sin novedades es una sola línea.
// Lo invoca pg_cron con x-cron-secret. ?previa=1 → solo a Manuel.
// ============================================================================

type Resumen = {
  faena: string
  para: string[]
  cc: string[]
  ciclo: { turno: string; fecha_inicio: string; fecha_fin: string } | null
  novedades_24h: { fecha_hora: string; autor: string | null; turno: string | null; categoria: string; severidad: string; texto: string; equipo: string | null }[]
  criticas_sin_acuse: { texto: string; autor: string | null; fecha_hora: string; faltan: string[] | null }[]
  pendientes: { titulo: string; prioridad: string; vence: string | null; responsable_turno: string | null; equipo: string | null; creado_nombre: string | null; dias: number; vencido: boolean | null }[]
  cerrados_24h: number
  entrega_miercoles: {
    hoy_es_miercoles: boolean
    miercoles: string
    entrega: null | {
      estado: 'abierta' | 'entregada' | 'recibida'; declarada: boolean; litros: number | null
      terceros_hubo: boolean | null; seguridad_sin_novedad: boolean | null; entrega: string | null; recibe: string | null
      camiones: { patente: string | null; fisico: number; teorico: number | null; metodo: string }[] | null
      terceros: { empresa: string; litros: number; autorizado_por: string }[] | null
    }
  }
  bodega_bajo_minimo: string[]
}

const hora = (s: string) => new Date(s).toLocaleString('es-CL', { timeZone: 'America/Santiago', weekday: 'short', hour: '2-digit', minute: '2-digit' })
const SEV: Record<string, string> = { critica: 'CRÍTICA', importante: 'Importante', normal: '' }

export async function POST(req: Request) {
  const secret = process.env.CRON_SECRET
  if (!secret || req.headers.get('x-cron-secret') !== secret) return NextResponse.json({ error: 'No autorizado.' }, { status: 401 })
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL
  const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
  if (!url || !anon) return NextResponse.json({ error: 'Falta configuración de Supabase.' }, { status: 500 })
  if (!mailerConfigured()) return NextResponse.json({ error: 'El correo no está configurado.' }, { status: 500 })
  const previa = new URL(req.url).searchParams.get('previa') === '1'
  const base = process.env.NEXT_PUBLIC_SITE_URL || 'https://pilladoiceo.netlify.app'

  const sb = createClient(url, anon, { auth: { persistSession: false } })
  const { data, error } = await sb.rpc('fn_faena_resumen_diario_cron', { p_secreto: secret })
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  const r = data as Resumen

  const sinLeer: ItemSimple[] = r.criticas_sin_acuse.map((c) => ({
    titulo: c.texto.slice(0, 140),
    sub: `${c.autor ?? '—'} · ${hora(c.fecha_hora)}`,
    lineas: [{ texto: `Sin leer: ${(c.faltan ?? []).join(', ')}`, alerta: true }],
  }))
  const novedades: ItemSimple[] = r.novedades_24h.map((n) => ({
    titulo: `${SEV[n.severidad] ? SEV[n.severidad] + ' · ' : ''}${n.texto.slice(0, 160)}`,
    sub: `${n.autor ?? '—'}${n.turno ? ` (turno ${n.turno})` : ''} · ${hora(n.fecha_hora)}${n.equipo ? ` · ${n.equipo}` : ''}`,
    lineas: [],
  }))
  const pendientes: ItemSimple[] = r.pendientes.map((p) => ({
    titulo: `${p.vencido ? 'VENCIDO · ' : ''}${p.titulo}`,
    sub: `${p.responsable_turno === 'ambos' ? 'cualquier turno' : `turno ${p.responsable_turno}`} · prioridad ${p.prioridad} · abierto hace ${p.dias} d${p.equipo ? ` · ${p.equipo}` : ''}`,
    lineas: [],
  }))

  // [MIG697] El cambio de turno es los miércoles: ese día se recuerda; desde el
  // jueves, si la entrega no quedó firmada y recibida, va arriba como escalamiento.
  const em = r.entrega_miercoles
  const e = em?.entrega
  const entregaItems: ItemSimple[] = []
  let entregaTitulo = ''
  let entregaNota = ''
  if (em) {
    const dia = new Date(`${em.miercoles}T12:00:00`).toLocaleDateString('es-CL', { day: 'numeric', month: 'long' })
    if (em.hoy_es_miercoles) {
      entregaTitulo = 'Hoy miércoles es cambio de turno'
      entregaNota = 'La entrega debe quedar firmada por quien sale y por quien entra, con los litros de cada camión, si se abasteció a otra empresa y las novedades de seguridad.'
    } else if (!e || e.estado !== 'recibida') {
      entregaTitulo = `Entrega de turno del miércoles ${dia}: ${!e ? 'NO SE HIZO' : e.estado === 'abierta' ? 'abierta, sin firmar' : 'firmada, falta que la reciban'}`
      entregaNota = 'Sin entrega firmada y recibida, el turno que entró no sabe con cuántos litros quedaron los camiones.'
    } else {
      entregaTitulo = `Entrega del miércoles ${dia}: firmada por ${e.entrega ?? '—'} y recibida por ${e.recibe ?? '—'}`
    }
    if (e?.camiones?.length) {
      entregaItems.push({ titulo: `Litros que quedaron: ${Math.round(e.litros ?? 0).toLocaleString('es-CL')} L`, lineas: e.camiones.map((c) => ({
        texto: `${c.patente ?? '—'}: ${Math.round(c.fisico).toLocaleString('es-CL')} L (${c.metodo})${c.teorico != null ? ` · sistema ${Math.round(c.teorico).toLocaleString('es-CL')} L` : ''}`,
        alerta: c.teorico != null && Math.abs(c.fisico - c.teorico) > 200,
      })) })
    }
    if (e) {
      entregaItems.push({ titulo: e.terceros_hubo ? 'Se abasteció a otras empresas' : e.terceros_hubo === false ? 'Sin abastecimiento a otras empresas' : 'Abastecimiento a otras empresas: sin declarar',
        lineas: (e.terceros ?? []).map((t) => ({ texto: `${t.empresa}: ${Math.round(t.litros).toLocaleString('es-CL')} L · autorizó ${t.autorizado_por}`, alerta: true })) })
      entregaItems.push({ titulo: e.seguridad_sin_novedad ? 'Seguridad: sin novedad' : e.seguridad_sin_novedad === false ? 'Seguridad: hubo novedad (ver bitácora)' : 'Seguridad: sin declarar', lineas: [] })
    }
  }

  const titulo = `Franke · bitácora del turno · ${new Date().toLocaleDateString('es-CL', { timeZone: 'America/Santiago', weekday: 'long', day: 'numeric', month: 'long' })}`
  const { html, text } = correoSimple({
    titulo,
    intro: [
      r.ciclo ? `En faena: ${r.ciclo.turno}.` : '',
      r.novedades_24h.length === 0 ? 'Últimas 24 horas: sin novedades registradas en la bitácora.' : `Últimas 24 horas: ${r.novedades_24h.length} novedad${r.novedades_24h.length === 1 ? '' : 'es'}, ${r.cerrados_24h} pendiente${r.cerrados_24h === 1 ? '' : 's'} cerrado${r.cerrados_24h === 1 ? '' : 's'}.`,
      r.bodega_bajo_minimo.length ? `Bodega bajo el mínimo: ${r.bodega_bajo_minimo.join(', ')}.` : '',
    ].filter(Boolean),
    secciones: [
      ...(entregaTitulo ? [{ titulo: entregaTitulo, nota: entregaNota || undefined, items: entregaItems.length ? entregaItems : [{ titulo: em?.hoy_es_miercoles ? 'Abra la entrega en /m/franke/entrega (funciona sin señal si la abrió ayer con señal).' : 'Abra la entrega en /m/franke/entrega.', lineas: [] }] }] : []),
      { titulo: 'Críticas sin leer (más de 12 horas)', nota: 'Quien falta debe abrir la bitácora y marcar «leído y entendido».', items: sinLeer },
      { titulo: 'Novedades de las últimas 24 horas', items: novedades },
      { titulo: `Pendientes abiertos (${r.pendientes.length})`, items: pendientes },
    ],
    enlace: { url: `${base}/m/franke/bitacora/`, texto: 'Abrir la bitácora (funciona sin señal)' },
    pie: 'SICOM · Franke. Este resumen llega todos los días a los supervisores de ambos turnos.',
  })

  const to = previa ? ['manuel.olivares@pilladoempresas.cl'] : r.para
  const cc = previa ? [] : r.cc
  const envio = await sendMail({ to, cc, subject: (previa ? '[VISTA PREVIA] ' : '') + titulo, html, text })
  return NextResponse.json({ ok: envio.ok, error: envio.error, para: to.length, novedades: r.novedades_24h.length, sin_leer: r.criticas_sin_acuse.length })
}
