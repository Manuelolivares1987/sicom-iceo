import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { sendMail, parseRecipients, mailerConfigured } from '@/lib/email/mailer'
import { nombreEnergia } from '@/lib/inicio-seguro/psgcc'
import { emailShell, seccionTitulo, MARCA } from '@/lib/email/plantilla'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

// ============================================================================
// [MIG735] Correos del Inicio Seguro ENEX (27-11-2026)
// ----------------------------------------------------------------------------
//   solicitud     el teléfono pidió el visto bueno → Hersaly
//   escalamiento  pasaron 10 min sin respuesta     → Hersaly + Manuel
//   detencion     alguien detuvo la tarea          → Hersaly + Manuel
// La sesión del supervisor es la autorización (sin service_role). Cada correo
// se reclama una sola vez en la base (rpc_inicio_seguro_reclamar_correo).
// ============================================================================

const APROBADOR = 'hersaly.corey@pilladoempresas.cl'
const ESCALAR = 'manuel.olivares@pilladoempresas.cl'

const esc = (s: unknown) =>
  String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]!))

type Fila = {
  id: string; tarea: string; estado: string; solicitado_at: string; detenido_motivo: string | null
  sin_bloqueo_motivo: string | null
  cuadrilla: { nombre: string; habilitado: boolean; pendientes: string[] }[]
  bloqueos: { energia: string; punto: string; foto_bloqueo: string; foto_energia_cero: string }[]
  psgcc: { respuesta: string }[]
  enex_programaciones: { tipo_servicio: string; enex_instalaciones: { nombre: string; enex_faenas: { nombre: string } | null } | null } | null
}

export async function POST(req: Request) {
  const auth = req.headers.get('authorization')
  if (!auth?.startsWith('Bearer ')) return NextResponse.json({ error: 'No autorizado.' }, { status: 401 })
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL
  const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
  if (!url || !anon) return NextResponse.json({ error: 'Falta configuración de Supabase.' }, { status: 500 })
  if (!mailerConfigured()) return NextResponse.json({ error: 'Correo no configurado.' }, { status: 503 })

  const sb = createClient(url, anon, { global: { headers: { Authorization: auth } }, auth: { persistSession: false } })
  const { data: u } = await sb.auth.getUser()
  if (!u?.user) return NextResponse.json({ error: 'Sesión inválida.' }, { status: 401 })

  const { id, tipo } = await req.json().catch(() => ({})) as { id?: string; tipo?: string }
  if (!id || !['solicitud', 'escalamiento', 'detencion'].includes(tipo ?? '')) {
    return NextResponse.json({ error: 'Solicitud inválida.' }, { status: 400 })
  }
  const { data: ok, error: errR } = await sb.rpc('rpc_inicio_seguro_reclamar_correo', { p_id: id, p_tipo: tipo })
  if (errR) return NextResponse.json({ error: errR.message }, { status: 500 })
  if (!ok) return NextResponse.json({ ok: true, enviado: false })

  const { data: f, error } = await sb.from('enex_inicio_seguro')
    .select('id, tarea, estado, solicitado_at, detenido_motivo, sin_bloqueo_motivo, cuadrilla, bloqueos, psgcc, enex_programaciones(tipo_servicio, enex_instalaciones(nombre, enex_faenas(nombre)))')
    .eq('id', id).single<Fila>()
  if (error || !f) return NextResponse.json({ error: error?.message ?? 'No encontrado.' }, { status: 404 })

  const { data: perfil } = await sb.from('usuarios_perfil').select('nombre_completo').eq('id', u.user.id).maybeSingle()
  const quien = perfil?.nombre_completo ?? u.user.email ?? 'Supervisor'
  const lugar = f.enex_programaciones?.enex_instalaciones?.nombre ?? 'Instalación'
  const faena = f.enex_programaciones?.enex_instalaciones?.enex_faenas?.nombre ?? ''
  const base = new URL(req.url).origin
  const enlace = `${base}/m/inicio-seguro/`

  const to = parseRecipients(process.env.INICIO_SEGURO_EMAIL_TO || APROBADOR)
  const cc = tipo === 'solicitud' ? [] : parseRecipients(process.env.INICIO_SEGURO_ESCALAR_TO || ESCALAR)
  const avisos = f.cuadrilla.filter((c) => !c.habilitado)

  const lista = (xs: string[]) => xs.length ? `<ul style="margin:4px 0 12px 18px;padding:0">${xs.map((x) => `<li>${x}</li>`).join('')}</ul>` : ''
  const cuerpo = [
    seccionTitulo('Tarea', MARCA.verdeOscuro, MARCA.verdeClaro),
    `<p>${esc(f.tarea)}</p>`,
    tipo === 'detencion' ? seccionTitulo('Motivo de la detención', MARCA.rojo, MARCA.rojoFondo) + `<p>${esc(f.detenido_motivo)}</p>` : '',
    seccionTitulo('Cuadrilla', MARCA.verdeOscuro, MARCA.verdeClaro),
    lista(f.cuadrilla.map((c) => `${esc(c.nombre)}${c.habilitado ? '' : ` — <span style="color:${MARCA.ambar}">aviso: falta ${esc(c.pendientes.join(', ') || 'requisito')}</span>`}`)),
    seccionTitulo('Bloqueos', MARCA.verdeOscuro, MARCA.verdeClaro),
    f.bloqueos.length
      ? lista(f.bloqueos.map((b) => `${esc(nombreEnergia(b.energia))} · ${esc(b.punto)} — <a href="${esc(b.foto_bloqueo)}">foto bloqueo</a> · <a href="${esc(b.foto_energia_cero)}">foto energía cero</a>`))
      : `<p>Sin bloqueo: ${esc(f.sin_bloqueo_motivo)}</p>`,
    `<p style="color:#555">${f.psgcc.length} controles críticos verificados.</p>`,
  ].join('')

  const asunto = tipo === 'solicitud' ? `Visto bueno pedido · ${lugar}`
    : tipo === 'escalamiento' ? `SIN RESPUESTA 10 min · visto bueno ${lugar}`
    : `TAREA DETENIDA · ${lugar}`
  const html = emailShell({
    titulo: esc(asunto),
    subtitulo: `${esc(faena)} · pide ${esc(quien)}`,
    chips: [
      { n: f.bloqueos.length, label: 'bloqueos', color: MARCA.verdeOscuro, fondo: MARCA.verdeClaro },
      ...(avisos.length ? [{ n: avisos.length, label: 'con cursos pendientes', color: MARCA.ambar, fondo: MARCA.ambarFondo }] : []),
    ],
    cuerpo,
    ctaUrl: tipo === 'detencion' ? undefined : enlace,
    ctaTexto: 'Revisar y dar visto bueno',
  })
  try {
    await sendMail({ to, cc, subject: `Inicio seguro · ${asunto}`, html })
  } catch (e) {
    return NextResponse.json({ error: (e as Error).message }, { status: 502 })
  }
  return NextResponse.json({ ok: true, enviado: true })
}
