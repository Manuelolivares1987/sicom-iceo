import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { sendMail, parseRecipients, mailerConfigured } from '@/lib/email/mailer'
import { correoSimple, type SeccionSimple } from '@/lib/email/simple'
import { MOTIVO_PAUSA_LABEL } from '@/lib/taller-motivos-pausa'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

// ============================================================================
// Resumen diario del taller (MIG676)
// ----------------------------------------------------------------------------
// En 30 días la campanita juntó 2.791 alertas y se leyeron 128 (4,6 %): un aviso
// por cada NO OK a cada jefe es ruido, y el ruido hace que nadie mire. Esto es
// UN correo al día con lo que pide una decisión: NC nuevas por equipo,
// preventivas vencidas, OT atrasadas, vales a los que no les alcanza el stock y
// trabajo parado esperando repuesto.
//
// Lo invoca el cron 'resumen-diario' (lun-sáb) con x-cron-secret; sin service_role.
// Destinatarios: RESUMEN_EMAIL_TO. Sin esa variable no envía nada.
// ?previa=1 → datos reales, sólo a Manuel.
// ============================================================================

type Resumen = {
  nc_por_equipo: { activo_id: string; patente: string; nuevas: number; observaciones: number; ejemplos: string[] }[]
  preventivas: { patente: string; pauta: string; horas_faltan: number; estado: string; ot_abierta: string | null }[]
  ot_atrasadas: { folio: string; patente: string | null; tipo: string; dias: number }[]
  ot_atrasadas_total: number
  vales_sin_stock: { folio: string; patente: string | null; disponibilidad: string; dias: number }[]
  stock_minimo_total: number
  pausas_espera: { patente: string | null; motivo: string; detalle: string | null; os?: string; ot?: string }[]
}

export async function POST(req: Request) {
  const secret = process.env.CRON_SECRET
  if (!secret || req.headers.get('x-cron-secret') !== secret) {
    return NextResponse.json({ error: 'No autorizado.' }, { status: 401 })
  }
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL
  const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
  if (!url || !anon) return NextResponse.json({ error: 'Falta configuración de Supabase.' }, { status: 500 })

  const previa = new URL(req.url).searchParams.get('previa') === '1'
  const to = previa ? ['manuel.olivares@pilladoempresas.cl'] : parseRecipients(process.env.RESUMEN_EMAIL_TO)
  if (!mailerConfigured() || to.length === 0) {
    return NextResponse.json({ ok: true, enviado: false, motivo: 'RESUMEN_EMAIL_TO o SMTP sin configurar' })
  }

  const sb = createClient(url, anon, { auth: { persistSession: false } })
  const { data, error } = await sb.rpc('fn_resumen_diario_cron', { p_secreto: secret })
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  const r = data as Resumen
  const base = process.env.NEXT_PUBLIC_SITE_URL || 'https://pilladoiceo.netlify.app'

  const secciones: SeccionSimple[] = []

  if (r.pausas_espera.length) {
    secciones.push({
      titulo: `Trabajo parado esperando (${r.pausas_espera.length})`,
      nota: 'Pausas de ayer por repuesto o equipo no disponible: es tiempo de taller perdido.',
      items: r.pausas_espera.map((p) => ({
        titulo: p.patente ?? '—', sub: p.os ?? p.ot ?? undefined,
        lineas: [{ texto: `${MOTIVO_PAUSA_LABEL[p.motivo] ?? p.motivo}${p.detalle ? `: ${p.detalle}` : ''}`, alerta: true }],
      })),
    })
  }
  if (r.nc_por_equipo.length) {
    secciones.push({
      titulo: `No conformidades nuevas (${r.nc_por_equipo.reduce((s, e) => s + e.nuevas, 0)} en ${r.nc_por_equipo.length} equipos)`,
      items: r.nc_por_equipo.map((e) => ({
        titulo: e.patente,
        sub: `${e.nuevas} nueva${e.nuevas > 1 ? 's' : ''}${e.observaciones ? `, ${e.observaciones} observación${e.observaciones > 1 ? 'es' : ''} (no bloquean)` : ''}`,
        lineas: e.ejemplos.map((t) => ({ texto: t })),
      })),
    })
  }
  if (r.preventivas.length) {
    secciones.push({
      titulo: `Preventivas por horas (${r.preventivas.length})`,
      items: r.preventivas.map((p) => ({
        titulo: p.patente,
        sub: p.pauta,
        lineas: [
          { texto: p.estado === 'vencida' ? `Vencida por ${Math.abs(p.horas_faltan)} h` : `Faltan ${p.horas_faltan} h`, alerta: p.estado === 'vencida' },
          { texto: p.ot_abierta ? `Tiene OT ${p.ot_abierta}` : 'Sin OT: hay que programarla', alerta: !p.ot_abierta },
        ],
      })),
    })
  }
  if (r.vales_sin_stock.length) {
    secciones.push({
      titulo: `Vales a los que no les alcanza el stock (${r.vales_sin_stock.length})`,
      nota: 'Considera lo que ya pidieron los vales anteriores. Comprar o reasignar antes de que llegue el mecánico.',
      items: r.vales_sin_stock.map((v) => ({
        titulo: v.folio, sub: v.patente ?? undefined,
        lineas: [{ texto: `${v.disponibilidad === 'sin_stock' ? 'Sin stock' : 'Stock parcial'} · espera ${v.dias} día${v.dias === 1 ? '' : 's'}`, alerta: v.disponibilidad === 'sin_stock' }],
      })),
    })
  }
  if (r.ot_atrasadas_total > 0) {
    secciones.push({
      titulo: `OT que debían empezar y no empezaron (${r.ot_atrasadas_total})`,
      nota: r.ot_atrasadas_total > r.ot_atrasadas.length ? `Las ${r.ot_atrasadas.length} más antiguas:` : undefined,
      items: r.ot_atrasadas.map((o) => ({
        titulo: o.folio, sub: `${o.patente ?? '—'} · ${o.tipo}`,
        lineas: [{ texto: `${o.dias} día${o.dias === 1 ? '' : 's'} de atraso`, alerta: o.dias > 7 }],
      })),
    })
  }

  const hoy = new Date().toLocaleDateString('es-CL', { timeZone: 'America/Santiago', weekday: 'long', day: '2-digit', month: 'long' })
  const intro = secciones.length
    ? ['Lo que pide una decisión hoy. Un solo correo en vez de una alerta por cada hallazgo.']
    : ['Sin pendientes que pidan una decisión hoy.']
  if (r.stock_minimo_total > 0) {
    intro.push(`Ojo: ${r.stock_minimo_total} productos figuran bajo su stock mínimo. Con tantos, lo más probable es que los mínimos estén mal cargados: conviene revisarlos en Inventario antes de usar ese aviso.`)
  }

  const { html, text } = correoSimple({
    titulo: `Resumen del taller — ${hoy}`,
    intro,
    secciones,
    enlace: { url: `${base}/dashboard/mantenimiento/no-conformidades/`, texto: 'Abrir SICOM' },
    pie: 'Resumen automático de SICOM, de lunes a sábado. Reemplaza los avisos sueltos de cada hallazgo.',
  })
  const asunto = (previa ? '[VISTA PREVIA] ' : '')
    + `Resumen del taller: ${r.nc_por_equipo.length} equipos con NC nuevas, ${r.preventivas.length} preventivas, ${r.vales_sin_stock.length} vales sin stock`

  const env = await sendMail({ to, subject: asunto, html, text })
  if (!env.ok) return NextResponse.json({ error: env.error ?? 'No se pudo enviar' }, { status: 500 })
  return NextResponse.json({ ok: true, enviado: true, secciones: secciones.length })
}
