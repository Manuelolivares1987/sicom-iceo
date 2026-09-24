import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { sendMail, parseRecipients, mailerConfigured } from '@/lib/email/mailer'
import { correoSimple, type ItemSimple, type SeccionSimple } from '@/lib/email/simple'
import { nombreTipo } from '@/lib/services/control-documental'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

// ============================================================================
// Aviso diario: papeles de flota vencidos o por vencer (MIG575)
// ----------------------------------------------------------------------------
// TODOS los documentos del equipo (RT, SOAP, permiso, hermeticidad, gases,
// SEC, mantención por horas…), agrupados por ZONA (Coquimbo, Calama) y dentro
// de cada zona los ARRENDADOS o en LEASING primero: son los que el cliente
// puede parar en la puerta de la faena.
//
// Diario, pero solo si hay algo nuevo: un papel que entró a la lista o bajó de
// tramo (vencido · ≤7 d · ≤15 d · ≤30 d · ≤50 h). Los lunes sale igual, como
// recordatorio completo. La base lleva la cuenta de lo avisado
// (docs_flota_avisos) y se marca DESPUÉS de que el correo salió.
//
// Formato simple (lib/email/simple.ts): casi texto plano + versión texto, para
// que Outlook no lo mande a no deseado (24-09, pedido de Manuel).
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

const fmtFecha = (s: string | null) =>
  s ? new Date(`${s}T12:00:00`).toLocaleDateString('es-CL',
    { day: '2-digit', month: 'short', year: 'numeric' }) : ''

/** Orden de las zonas en el correo: las dos operaciones, y al final lo que no tenga zona. */
const ORDEN_ZONA = ['Coquimbo', 'Calama']

function plazo(d: Doc): string {
  if (d.estado === 'vencido') {
    return d.dias_restantes != null && d.dias_restantes < 0
      ? `VENCIDO hace ${-d.dias_restantes} días` : 'VENCIDO'
  }
  if (d.horas_restantes != null) return `vence en ${d.horas_restantes} horas de horómetro`
  if (d.dias_restantes === 0) return 'vence HOY'
  return `vence en ${d.dias_restantes} días`
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

  // Zona → equipo → papeles. La función ya viene ordenada (arrendados primero,
  // patente, vencidos antes); acá solo se agrupa respetando ese orden.
  const zonas = new Map<string, Map<string, Doc[]>>()
  for (const d of docs) {
    const z = zonas.get(d.zona) ?? new Map<string, Doc[]>()
    z.set(d.activo_id, [...(z.get(d.activo_id) ?? []), d])
    zonas.set(d.zona, z)
  }
  const nombresZona = Array.from(zonas.keys()).sort((a, b) => {
    const ia = ORDEN_ZONA.indexOf(a), ib = ORDEN_ZONA.indexOf(b)
    return (ia < 0 ? 99 : ia) - (ib < 0 ? 99 : ib) || a.localeCompare(b)
  })

  const item = (xs: Doc[]): ItemSimple => {
    const a = xs[0]
    const equipo = [a.patente, a.codigo].filter(Boolean).join(' · ') || 'Sin patente'
    const comercial = a.estado_comercial === 'leasing' ? 'Leasing' : a.en_arriendo ? 'Arrendado' : ''
    const sub = [
      [a.nombre, comercial && `${comercial}${a.cliente ? ` a ${a.cliente}` : ''}`].filter(Boolean).join(' · '),
      a.faena,
    ].filter(Boolean).join(' · ')
    return {
      titulo: equipo,
      sub,
      lineas: xs.map((d) => ({
        texto: `${d.nuevo ? '[NUEVO] ' : ''}${nombreTipo(d.documento)}: ${plazo(d)}`
             + (d.horas_restantes == null && d.fecha_vencimiento ? ` (${fmtFecha(d.fecha_vencimiento)})` : ''),
        alerta: d.estado === 'vencido' || (d.dias_restantes ?? 99) <= 7,
      })),
    }
  }

  const secciones: SeccionSimple[] = nombresZona.map((zona) => {
    const equipos = Array.from(zonas.get(zona)!.values())
    const enArriendo = equipos.filter((xs) => xs[0].en_arriendo).length
    const venc = equipos.flat().filter((d) => d.estado === 'vencido').length
    return {
      titulo: `${zona} — ${equipos.length} equipo${equipos.length === 1 ? '' : 's'}`
            + ` (${enArriendo} en arriendo), ${venc} papel${venc === 1 ? '' : 'es'} vencido${venc === 1 ? '' : 's'}`,
      items: equipos.map(item),
    }
  })

  const vencidos = docs.filter((d) => d.estado === 'vencido').length
  const porVencer = docs.length - vencidos
  const hoy = new Date().toLocaleDateString('es-CL', { timeZone: 'America/Santiago', day: '2-digit', month: 'long' })
  const base = process.env.NEXT_PUBLIC_SITE_URL || 'https://pilladoiceo.netlify.app'

  const { html, text } = correoSimple({
    titulo: `Papeles de flota vencidos o por vencer — ${hoy}`,
    intro: [
      `${vencidos} vencidos y ${porVencer} que vencen en los próximos 30 días (o 50 horas de horómetro).`
      + (nuevos.length > 0
        ? ` ${nuevos.length} son nuevos desde el último aviso: van marcados [NUEVO].`
        : ' Sin novedades desde el último aviso: este es el recordatorio de los lunes.'),
      'Por zona, y en cada zona primero los equipos arrendados o en leasing.',
    ],
    secciones,
    enlace: { url: `${base}/dashboard/flota/control-documental/`, texto: 'Abrir Control documental de flota en SICOM' },
    pie: 'Aviso automático de SICOM. Sale cuando hay novedades y los lunes como recordatorio. '
       + 'Al cargar el papel renovado en SICOM, sale solo de esta lista.',
  })

  const asunto = (esPrueba ? '[PRUEBA] ' : previa ? '[VISTA PREVIA] ' : '')
    + `Papeles de flota: ${vencidos} vencidos, ${porVencer} por vencer`
    + (nuevos.length > 0 ? ` (${nuevos.length} nuevos)` : '')

  const r = await sendMail({ to, subject: asunto, html, text })
  if (!r.ok) return NextResponse.json({ error: r.error ?? 'No se pudo enviar' }, { status: 500 })

  if (!esPrueba && !previa) {
    const items = docs.map((d) => ({ certificacion_id: d.certificacion_id, tramo: d.tramo }))
    const { error: eMarca } = await sb.rpc('fn_docs_flota_marcar_cron', { p_secreto: secret, p_items: items })
    if (eMarca) return NextResponse.json({ ok: true, enviado: true, marcado: false, error: eMarca.message })
  }
  return NextResponse.json({
    ok: true, enviado: true, papeles: docs.length, nuevos: nuevos.length,
    zonas: nombresZona, vencidos, por_vencer: porVencer,
  })
}
