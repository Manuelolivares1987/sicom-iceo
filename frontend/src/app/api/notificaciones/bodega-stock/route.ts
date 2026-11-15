import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { sendMail, mailerConfigured } from '@/lib/email/mailer'
import { correoSimple } from '@/lib/email/simple'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

// ============================================================================
// Aviso de stock bajo en bodegas con mínimo propio (MIG692, Franke primero)
// ----------------------------------------------------------------------------
// Cada 15 minutos. Solo manda cuando NACE una alerta (un producto cruzó su
// mínimo): no repite cada 15 minutos lo mismo. La alerta se cierra sola cuando
// el stock vuelve sobre el mínimo. Destinatarios por bodega en
// bodega_responsables (Franke: supervisores de turno + encargado de bodega,
// copia a Manuel). Lo invoca pg_cron con x-cron-secret; sin service_role.
// ============================================================================

type Grupo = {
  bodega_id: string
  bodega: string
  para: string[]
  cc: string[]
  nuevas: { id: string; producto: string; codigo: string; unidad: string | null; stock: number; minimo: number }[]
  abiertas: number
}

const n = (x: number) => Number(x).toLocaleString('es-CL', { maximumFractionDigits: 2 })

export async function POST(req: Request) {
  const secret = process.env.CRON_SECRET
  if (!secret || req.headers.get('x-cron-secret') !== secret) {
    return NextResponse.json({ error: 'No autorizado.' }, { status: 401 })
  }
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL
  const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
  if (!url || !anon) return NextResponse.json({ error: 'Falta configuración de Supabase.' }, { status: 500 })
  if (!mailerConfigured()) return NextResponse.json({ error: 'El correo no está configurado.' }, { status: 500 })
  const base = process.env.NEXT_PUBLIC_SITE_URL || 'https://pilladoiceo.netlify.app'

  const sb = createClient(url, anon, { auth: { persistSession: false } })
  const { data, error } = await sb.rpc('fn_bodega_alertas_cron', { p_secreto: secret })
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })

  const resultados: { bodega: string; enviado: boolean; alertas: number; error?: string }[] = []
  for (const g of (data ?? []) as Grupo[]) {
    if (!g.nuevas?.length || (g.para.length === 0 && g.cc.length === 0)) continue
    const nombre = g.bodega.split(' (')[0]
    const titulo = `Stock bajo en ${nombre}: ${g.nuevas.length} producto${g.nuevas.length === 1 ? '' : 's'}`
    const { html, text } = correoSimple({
      titulo,
      intro: [
        `Estos productos quedaron en o bajo su mínimo y hay que reponerlos.`,
        g.abiertas > g.nuevas.length ? `En total hay ${g.abiertas} productos bajo el mínimo en esta bodega.` : '',
      ].filter(Boolean),
      secciones: [{
        titulo: 'Reponer',
        items: g.nuevas.map((a) => ({
          titulo: a.producto,
          sub: a.codigo,
          lineas: [{ texto: `Quedan ${n(a.stock)} ${a.unidad ?? ''} · mínimo ${n(a.minimo)}`, alerta: a.stock <= 0 }],
        })),
      }],
      enlace: { url: `${base}/dashboard/bodega/franke/`, texto: 'Ver la bodega' },
      pie: 'SICOM · bodega de faena. Este aviso sale una vez por producto cuando cruza su mínimo; se cierra solo al reponer.',
    })
    const envio = await sendMail({ to: g.para, cc: g.cc, subject: titulo, html, text })
    if (envio.ok) await sb.rpc('fn_bodega_alertas_marcar_cron', { p_secreto: secret, p_ids: g.nuevas.map((a) => a.id) })
    resultados.push({ bodega: nombre, enviado: envio.ok, alertas: g.nuevas.length, error: envio.error })
  }
  return NextResponse.json({ ok: true, resultados })
}
