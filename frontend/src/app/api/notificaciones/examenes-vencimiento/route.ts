import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { sendMail, mailerConfigured } from '@/lib/email/mailer'
import {
  emailShell, seccionTitulo, chipEstado, tablaAbrir, tablaCerrar, celda, MARCA,
} from '@/lib/email/plantilla'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

// ============================================================================
// Alerta de vencimiento de exámenes ocupacionales (MIG299)
// ----------------------------------------------------------------------------
// La invoca un cron diario (pg_cron → net.http_post) con el header
// x-cron-secret. La base decide QUÉ toca avisar hoy según el escalamiento
// (fn_prevencion_alertas_pendientes): esta ruta solo arma el correo y lo manda.
//
// Idempotente: los avisos se marcan DESPUÉS de que el correo salió. Si el
// envío falla, no se marcan y se reintentan al día siguiente — mejor un aviso
// repetido que uno perdido.
//
// NO USA service_role. Esa clave abre toda la base sin restricción, y ponerla
// en las variables de Netlify para leer ~20 filas es desproporcionado: si se
// filtra, se filtra el sistema completo, datos de salud del personal incluidos.
// En su lugar, el MISMO CRON_SECRET que autentica la llamada habilita
// exactamente dos funciones en la base (MIG301), y nada más. La clave anónima
// por sí sola no abre nada.
//
// Los destinatarios NO son una variable de entorno: viven en la base
// (prevencion_alertas_destinatarios, MIG302) porque cada uno declara de qué
// faenas puede recibir información. Un externo acotado a una faena recibe un
// correo que contiene solo esa faena.
//
// Requiere en el servidor: CRON_SECRET y SMTP_*.
// ============================================================================

type Alerta = {
  examen_id: string
  rut: string
  persona: string
  empresa: string | null
  faena_codigo: string | null
  tipo_nombre: string
  laboratorio: string | null
  fecha_vencimiento: string | null
  dias_restantes: number | null
  nivel: string
}

const NIVEL = {
  vencido:  { label: 'VENCIDO',   color: '#B91C1C', fondo: '#FEE2E2', orden: 0 },
  critico:  { label: '≤ 7 días',  color: '#C2410C', fondo: '#FFEDD5', orden: 1 },
  urgente:  { label: '≤ 14 días', color: '#B45309', fondo: '#FEF3C7', orden: 2 },
  alto:     { label: '≤ 30 días', color: '#A16207', fondo: '#FEF9C3', orden: 3 },
  medio:    { label: '≤ 60 días', color: '#4D7C0F', fondo: '#ECFCCB', orden: 4 },
  sin_dato: { label: 'SIN DATO',  color: '#B91C1C', fondo: '#FEE2E2', orden: 0 },
} as const

const esc = (s: unknown) =>
  String(s ?? '').replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]!))

const fmtFecha = (s: string | null) =>
  s ? new Date(s + 'T12:00:00').toLocaleDateString('es-CL',
    { day: '2-digit', month: 'short', year: 'numeric' }) : '—'

export async function POST(req: Request) {
  const secret = process.env.CRON_SECRET
  if (!secret || req.headers.get('x-cron-secret') !== secret) {
    return NextResponse.json({ error: 'No autorizado.' }, { status: 401 })
  }

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
  if (!url || !anonKey) {
    return NextResponse.json({ error: 'Falta la configuración de Supabase.' }, { status: 500 })
  }

  if (!mailerConfigured()) {
    return NextResponse.json({ error: 'SMTP no configurado.' }, { status: 500 })
  }

  // Clave anónima + secreto: la anónima sola no abre nada, y el secreto solo
  // habilita estas dos funciones (MIG301).
  const sb = createClient(url, anonKey, { auth: { persistSession: false } })

  const { data, error } = await sb.rpc('fn_prevencion_alertas_pendientes_cron', {
    p_secreto: secret,
  })
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })

  const todas = (data ?? []) as Alerta[]
  if (todas.length === 0) return NextResponse.json({ ok: true, enviadas: 0 })

  // ── Un correo POR FAENA ─────────────────────────────────────────────────
  // No es una preferencia de formato: es control de alcance. Hay
  // destinatarios externos que solo pueden ver su propia faena (MIG302), y la
  // única forma de garantizarlo es que el correo que reciben contenga
  // únicamente esa faena. Un correo global con todo adentro no se puede
  // "filtrar por destinatario" una vez enviado.
  const porFaena: Record<string, Alerta[]> = {}
  for (const f of todas) {
    const k = f.faena_codigo ?? '(sin faena)'
    ;(porFaena[k] ??= []).push(f)
  }

  const enviados: { faena: string, destinatarios: number, alertas: number }[] = []
  const omitidos: { faena: string, motivo: string }[] = []
  const marcadas: string[] = []

  for (const [faena, filas] of Object.entries(porFaena)) {
    // Lo más urgente primero: el correo se lee de arriba hacia abajo y en dos
    // líneas tiene que quedar claro quién no puede entrar a faena mañana.
    filas.sort((a: Alerta, b: Alerta) => {
      const na = NIVEL[a.nivel as keyof typeof NIVEL]?.orden ?? 9
      const nb = NIVEL[b.nivel as keyof typeof NIVEL]?.orden ?? 9
      return na - nb || (a.dias_restantes ?? 0) - (b.dias_restantes ?? 0)
    })

    const { data: dest, error: errDest } = await sb.rpc('fn_prevencion_destinatarios_cron', {
      p_secreto: secret,
      p_faena: faena === '(sin faena)' ? null : faena,
    })
    if (errDest) return NextResponse.json({ error: errDest.message }, { status: 500 })

    const filasDest = (dest ?? []) as { email: string, modo: string }[]
    const to = filasDest.filter((d) => d.modo === 'para').map((d) => d.email)
    const cc = filasDest.filter((d) => d.modo === 'copia').map((d) => d.email)

    // Sin destinatarios no se marca como avisado: si se marcara, el aviso se
    // perdería para siempre al configurar el correo más tarde.
    if (to.length === 0 && cc.length === 0) {
      omitidos.push({ faena, motivo: 'sin destinatarios configurados' })
      continue
    }

    const r = await enviarCorreoFaena(faena, filas, to, cc)
    if (!r.ok) {
      omitidos.push({ faena, motivo: r.error ?? 'error de envío' })
      continue
    }
    enviados.push({ faena, destinatarios: to.length + cc.length, alertas: filas.length })
    marcadas.push(...filas.map((f: Alerta) => f.examen_id))
  }

  if (marcadas.length > 0) {
    const { error: errMarcar } = await sb.rpc('fn_prevencion_marcar_alertas_cron', {
      p_secreto: secret,
      p_ids: marcadas,
      p_destinatarios: enviados.map((e) => `${e.faena}:${e.destinatarios}`).join(', '),
    })
    if (errMarcar) {
      return NextResponse.json({ ok: true, enviadas: marcadas.length, aviso: errMarcar.message })
    }
  }

  return NextResponse.json({
    ok: true,
    enviadas: marcadas.length,
    correos: enviados,
    omitidos: omitidos.length > 0 ? omitidos : undefined,
  })
}

/** Arma y envía el correo de UNA faena. */
async function enviarCorreoFaena(
  faena: string, filas: Alerta[], to: string[], cc: string[],
) {
  const vencidos = filas.filter((f) => f.nivel === 'vencido' || f.nivel === 'sin_dato')
  const proximos = filas.filter((f) => f.nivel !== 'vencido' && f.nivel !== 'sin_dato')

  // [2026-09-03] Rediseño con la plantilla de marca (lib/email/plantilla):
  // tarjetas con el número grande, secciones tipo píldora, filas cebra y chip
  // de plazo por persona. Y el ritmo cambió: UN resumen semanal (lunes).
  const fila = (f: Alerta, i: number) => {
    const n = NIVEL[f.nivel as keyof typeof NIVEL] ?? NIVEL.medio
    const dias = f.dias_restantes == null ? 'SIN DATO'
      : f.dias_restantes < 0 ? `vencido hace ${-f.dias_restantes} d`
      : f.dias_restantes === 0 ? 'vence HOY'
      : `vence en ${f.dias_restantes} d`
    const z = i % 2 === 1
    return `<tr>
      ${celda(`<b>${esc(f.persona)}</b><br><span style="color:#9ca3af;font-size:11px">${esc(f.rut)}</span>`, z)}
      ${celda(`${esc(f.tipo_nombre)}<br><span style="color:#9ca3af;font-size:11px">${esc(f.laboratorio ?? '')}</span>`, z)}
      ${celda(`<span style="white-space:nowrap">${fmtFecha(f.fecha_vencimiento)}</span>`, z)}
      ${celda(chipEstado(dias, n.color, n.fondo), z, 'text-align:right')}
    </tr>`
  }

  const tabla = (titulo: string, xs: Alerta[], color: string, fondo: string) => xs.length === 0 ? '' : `
    ${seccionTitulo(`${titulo} · ${xs.length}`, color, fondo)}
    ${tablaAbrir(['Persona', 'Examen', 'Vence', 'Plazo'])}
    ${xs.map(fila).join('')}
    ${tablaCerrar}`

  const base = process.env.NEXT_PUBLIC_SITE_URL || 'https://pilladoiceo.netlify.app'
  const html = emailShell({
    titulo: 'Control documental de personal',
    subtitulo: `Faena ${esc(faena)} · resumen semanal — ${new Date().toLocaleDateString('es-CL', { day: '2-digit', month: 'long' })}`,
    chips: [
      ...(vencidos.length > 0
        ? [{ n: vencidos.length, label: 'Vencidos / sin dato', color: MARCA.rojo, fondo: MARCA.rojoFondo }] : []),
      ...(proximos.length > 0
        ? [{ n: proximos.length, label: 'Por vencer', color: MARCA.ambar, fondo: MARCA.ambarFondo }] : []),
    ],
    cuerpo: `
      ${vencidos.length > 0
        ? `<p style="margin:14px 0 0;font-size:13px;color:#4b5563">Las personas con examen
           <b style="color:${MARCA.rojo}">vencido o sin registro</b> no pueden acreditar
           documentación al día ante el mandante.</p>` : ''}
      ${tabla('Vencidos o sin registro', vencidos, MARCA.rojo, MARCA.rojoFondo)}
      ${tabla('Por vencer', proximos, MARCA.ambar, MARCA.ambarFondo)}`,
    ctaUrl: `${base}/dashboard/prevencion/personal`,
    ctaTexto: 'Renovar exámenes en SICOM',
    pie: 'Resumen semanal (lunes) del control documental. Los datos son del momento del envío. '
       + 'Correo automático de SICOM · Pillado Empresas.',
  })

  const asunto = vencidos.length > 0
    ? `🔴 Exámenes: ${vencidos.length} vencido(s) y ${proximos.length} por vencer · ${faena} · PILLADO`
    : `🟡 Exámenes: ${proximos.length} por vencer · ${faena} · PILLADO`

  return sendMail({ to, cc, subject: asunto, html })
}
