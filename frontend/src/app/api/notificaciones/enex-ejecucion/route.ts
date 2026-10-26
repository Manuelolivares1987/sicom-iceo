import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { sendMail, parseRecipients, mailerConfigured } from '@/lib/email/mailer'
import {
  emailShell, seccionTitulo, chipEstado, tablaAbrir, tablaCerrar, celda, MARCA,
} from '@/lib/email/plantilla'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

// ============================================================================
// [MIG649] Correo de la ejecución ENEX a la jefatura (26-10-2026)
// ----------------------------------------------------------------------------
// Manuel: al ejecutar en terreno tiene que llegar un correo a Hersaly (jefa de
// los supervisores) y a él con la ejecución, el informe y el detalle de los
// repuestos pedidos.
//
// Lo pide la app de terreno apenas la ejecución llega al servidor (también si
// se trabajó sin señal y subió después). La sesión del supervisor es la
// autorización: se lee con SUS permisos, sin service_role. Qué correo toca lo
// decide rpc_enex_reclamar_correo en una transacción, así un reintento o dos
// teléfonos no lo mandan dos veces:
//   cierre     servicio cumplido → ejecución + informe + todos los repuestos
//   repuestos  avance con repuestos nuevos → solo el pedido, sin esperar el cierre
//
// Destinatarios: ENEX_EMAIL_TO (si no está, Hersaly + Manuel).
// ============================================================================

const DESTINATARIOS_POR_DEFECTO = 'hersaly.corey@pilladoempresas.cl, manuel.olivares@pilladoempresas.cl'

const esc = (s: unknown) =>
  String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]!))

type Repuesto = {
  id: string; descripcion: string; cantidad: number; unidad: string; urgente: boolean
  nota: string | null; estado: string; pedido_por_nombre: string | null
}

const fmtFecha = (iso: string | null | undefined) =>
  iso ? new Date(iso).toLocaleString('es-CL', { timeZone: 'America/Santiago', day: '2-digit', month: '2-digit',
    year: 'numeric', hour: '2-digit', minute: '2-digit' }) : '—'
const fmtDuracion = (seg: number | null | undefined) => {
  if (!seg) return '—'
  const h = Math.floor(seg / 3600), m = Math.round((seg % 3600) / 60)
  return h > 0 ? `${h} h ${m} min` : `${m} min`
}

export async function POST(req: Request) {
  const auth = req.headers.get('authorization')
  if (!auth?.startsWith('Bearer ')) return NextResponse.json({ error: 'No autorizado.' }, { status: 401 })
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL
  const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
  if (!url || !anon) return NextResponse.json({ error: 'Falta configuración de Supabase.' }, { status: 500 })
  const to = parseRecipients(process.env.ENEX_EMAIL_TO || DESTINATARIOS_POR_DEFECTO)
  if (!mailerConfigured() || to.length === 0) {
    return NextResponse.json({ error: 'Correo no configurado.' }, { status: 503 })
  }

  const sb = createClient(url, anon, {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false },
  })
  const { data: userData, error: userErr } = await sb.auth.getUser()
  if (userErr || !userData?.user) return NextResponse.json({ error: 'Sesión inválida.' }, { status: 401 })

  const { ejecucionId } = await req.json().catch(() => ({}))
  if (!ejecucionId || typeof ejecucionId !== 'string') {
    return NextResponse.json({ error: 'Falta la ejecución.' }, { status: 400 })
  }

  // Reclamar primero: desde aquí, otro intento ya no lo manda.
  const { data: reclamo, error: errReclamo } = await sb.rpc('rpc_enex_reclamar_correo', { p_ejecucion_id: ejecucionId })
  if (errReclamo) return NextResponse.json({ error: errReclamo.message }, { status: 500 })
  const tipo = (reclamo as { tipo: 'cierre' | 'repuestos' | 'nada' }).tipo
  const nuevos = ((reclamo as { repuestos_nuevos?: string[] }).repuestos_nuevos) ?? []
  if (tipo === 'nada') return NextResponse.json({ ok: true, tipo })

  const liberar = () => sb.rpc('rpc_enex_liberar_correo', {
    p_ejecucion_id: ejecucionId, p_tipo: tipo, p_repuesto_ids: nuevos,
  })

  try {
    const { data: ej, error: e1 } = await sb.from('enex_ejecuciones').select('*').eq('id', ejecucionId).single()
    if (e1 || !ej) throw new Error(e1?.message ?? 'Ejecución no encontrada')
    const { data: prog } = await sb.from('v_enex_terreno_pendientes')
      .select('instalacion, patente, faena, tipo_servicio, linea, pauta_nombre, fecha_programada')
      .eq('programacion_id', ej.programacion_id).maybeSingle()
    const { data: reps } = await sb.from('enex_repuestos_pedido')
      .select('id, descripcion, cantidad, unidad, urgente, nota, estado, pedido_por_nombre')
      .eq('ejecucion_id', ejecucionId).neq('estado', 'anulado').order('created_at')
    const repuestos = ((reps ?? []) as Repuesto[]).filter((r) => tipo === 'cierre' || nuevos.includes(r.id))

    // Resumen de la pauta: cuánto se trabajó y qué quedó NO OK.
    const { data: filas } = await sb.from('enex_ejecucion_items')
      .select('pauta_item_id, resultado, valor_medicion, observacion').eq('ejecucion_id', ejecucionId)
    const items = (filas ?? []) as { pauta_item_id: string; resultado: string | null; valor_medicion: number | null; observacion: string | null }[]
    const noOk = items.filter((i) => i.resultado === 'no_ok' || i.resultado === 'no')
    let descripcion = new Map<string, { codigo: string | null; descripcion: string }>()
    if (noOk.length > 0) {
      const { data: pi } = await sb.from('enex_pauta_items').select('id, codigo, descripcion')
        .in('id', noOk.map((i) => i.pauta_item_id))
      descripcion = new Map((pi ?? []).map((x: { id: string; codigo: string | null; descripcion: string }) => [x.id, x]))
    }

    const servicio = prog?.tipo_servicio === 'calibracion' ? 'Calibración' : 'Mantención'
    const mundo = prog?.linea === 'lubricante' ? 'Lubricantes' : 'Combustible'
    const lugar = `${prog?.instalacion ?? 'Instalación'}${prog?.patente ? ` · ${prog.patente}` : ''}`
    const urgentes = repuestos.filter((r) => r.urgente).length
    const base = process.env.NEXT_PUBLIC_SITE_URL || 'https://pilladoiceo.netlify.app'
    const quien = ej.tecnico_nombre || ej.ejecutor || userData.user.email || 'Supervisor'

    const datos = [
      ['Servicio', `${servicio} · ${mundo}`],
      ['Faena', prog?.faena ?? '—'],
      ['Instalación', lugar],
      ['Estado', ej.estado === 'cumplida' ? 'CUMPLIDA (firmada por el mandante)' : 'Avance registrado'],
      ['Supervisor', quien],
      ...(ej.firmante_mandante_nombre ? [['Firma mandante', ej.firmante_mandante_nombre]] : []),
      ['Fecha', fmtFecha(ej.fin_at ?? ej.updated_at)],
      ['Tiempo de trabajo', fmtDuracion(ej.duracion_segundos)],
      ...(ej.ot_numero ? [['N° OT mandante', ej.ot_numero]] : []),
      ['Pauta', `${items.filter((i) => i.resultado || i.valor_medicion != null || i.observacion).length} actividades registradas · ${noOk.length} NO OK`],
    ]
    let cuerpo = `<table role="presentation" cellpadding="0" cellspacing="0" style="width:100%;font-size:13px;color:#1f2937;margin-top:14px">
      ${datos.map(([k, v]) => `<tr><td style="padding:5px 0;color:#6b7280;width:150px;vertical-align:top">${esc(k)}</td>
        <td style="padding:5px 0;font-weight:600">${esc(v)}</td></tr>`).join('')}
    </table>`

    if (ej.observacion) {
      cuerpo += seccionTitulo('Observaciones del supervisor', MARCA.verdeOscuro, MARCA.verdeClaro)
      cuerpo += `<div style="font-size:13px;color:#1f2937;white-space:pre-wrap;background:#f8faf8;border-radius:10px;padding:12px 14px">${esc(ej.observacion)}</div>`
    }

    if (repuestos.length > 0) {
      cuerpo += seccionTitulo(`Repuestos pedidos (${repuestos.length})`, urgentes ? MARCA.rojo : MARCA.ambar,
        urgentes ? MARCA.rojoFondo : MARCA.ambarFondo)
      cuerpo += tablaAbrir(['#', 'Repuesto', 'Cant.', 'Detalle', ''])
      repuestos.forEach((r, i) => {
        const z = i % 2 === 1
        cuerpo += `<tr>${celda(String(i + 1), z)}${celda(`<b>${esc(r.descripcion)}</b>`, z)}
          ${celda(`${esc(r.cantidad)} ${esc(r.unidad)}`, z, 'white-space:nowrap')}${celda(esc(r.nota ?? ''), z)}
          ${celda(r.urgente ? chipEstado('URGENTE', MARCA.rojo, MARCA.rojoFondo) : '', z)}</tr>`
      })
      cuerpo += tablaCerrar
    }

    if (noOk.length > 0) {
      cuerpo += seccionTitulo(`Actividades NO OK (${noOk.length})`, MARCA.rojo, MARCA.rojoFondo)
      cuerpo += tablaAbrir(['Código', 'Actividad', 'Observación'])
      noOk.forEach((it, i) => {
        const d = descripcion.get(it.pauta_item_id)
        cuerpo += `<tr>${celda(esc(d?.codigo ?? ''), i % 2 === 1)}${celda(esc(d?.descripcion ?? ''), i % 2 === 1)}
          ${celda(esc(it.observacion ?? ''), i % 2 === 1)}</tr>`
      })
      cuerpo += tablaCerrar
    }

    if (tipo === 'cierre') {
      cuerpo += ej.informe_pdf_url
        ? `<p style="font-size:13px;margin-top:18px">Informe firmado: <a href="${esc(ej.informe_pdf_url)}" style="color:${MARCA.verde};font-weight:700">descargar informe PDF</a>.</p>`
        : `<p style="font-size:13px;margin-top:18px;color:${MARCA.ambar}">El informe PDF no se alcanzó a generar desde el teléfono; se puede generar desde el panel ENEX.</p>`
    }

    const asunto = tipo === 'cierre'
      ? `ENEX · ${servicio} cumplida · ${lugar} · ${prog?.faena ?? ''}${repuestos.length ? ` · ${repuestos.length} repuesto(s)${urgentes ? `, ${urgentes} urgente(s)` : ''}` : ''}`
      : `${urgentes ? 'URGENTE · ' : ''}ENEX · Pedido de repuestos · ${lugar} · ${prog?.faena ?? ''}`

    const html = emailShell({
      titulo: tipo === 'cierre' ? `${servicio} cumplida · ${esc(lugar)}` : `Pedido de repuestos · ${esc(lugar)}`,
      subtitulo: `${mundo} · ${esc(prog?.faena ?? '')} · ${esc(quien)}`,
      chips: [
        ...(tipo === 'cierre' ? [{ n: fmtDuracion(ej.duracion_segundos), label: 'de trabajo', color: MARCA.verdeOscuro, fondo: MARCA.verdeClaro }] : []),
        { n: repuestos.length, label: 'repuestos', color: MARCA.ambar, fondo: MARCA.ambarFondo },
        ...(urgentes ? [{ n: urgentes, label: 'urgentes', color: MARCA.rojo, fondo: MARCA.rojoFondo }] : []),
        ...(tipo === 'cierre' ? [{ n: noOk.length, label: 'NO OK', color: noOk.length ? MARCA.rojo : MARCA.verdeOscuro, fondo: noOk.length ? MARCA.rojoFondo : MARCA.verdeClaro }] : []),
      ],
      cuerpo,
      ctaUrl: tipo === 'cierre' && ej.informe_pdf_url ? ej.informe_pdf_url : `${base}/dashboard/enex/`,
      ctaTexto: tipo === 'cierre' && ej.informe_pdf_url ? 'Abrir informe PDF' : 'Abrir panel ENEX',
    })

    const r = await sendMail({ to, subject: asunto, html, replyTo: userData.user.email ?? undefined })
    if (!r.ok) throw new Error(r.error ?? 'No se pudo enviar')
    return NextResponse.json({ ok: true, tipo, repuestos: repuestos.length })
  } catch (e) {
    await liberar()
    return NextResponse.json({ error: (e as Error).message }, { status: 502 })
  }
}
