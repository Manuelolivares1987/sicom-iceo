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

  const titulo = `Franke · bitácora del turno · ${new Date().toLocaleDateString('es-CL', { timeZone: 'America/Santiago', weekday: 'long', day: 'numeric', month: 'long' })}`
  const { html, text } = correoSimple({
    titulo,
    intro: [
      r.ciclo ? `En faena: ${r.ciclo.turno}.` : '',
      r.novedades_24h.length === 0 ? 'Últimas 24 horas: sin novedades registradas en la bitácora.' : `Últimas 24 horas: ${r.novedades_24h.length} novedad${r.novedades_24h.length === 1 ? '' : 'es'}, ${r.cerrados_24h} pendiente${r.cerrados_24h === 1 ? '' : 's'} cerrado${r.cerrados_24h === 1 ? '' : 's'}.`,
      r.bodega_bajo_minimo.length ? `Bodega bajo el mínimo: ${r.bodega_bajo_minimo.join(', ')}.` : '',
    ].filter(Boolean),
    secciones: [
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
