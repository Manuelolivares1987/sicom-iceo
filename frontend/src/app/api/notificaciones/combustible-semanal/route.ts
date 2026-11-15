import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { sendMail, mailerConfigured } from '@/lib/email/mailer'
import { correoSimple, type ItemSimple } from '@/lib/email/simple'
import { ALERTA_TXT, type Alerta } from '@/lib/services/combustible-tarjeta'
import type { DiferenciaComb, VehiculoSemana } from '@/lib/services/combustible-control'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

// ============================================================================
// Control de combustible: reporte semanal por operación (MIG691)
// ----------------------------------------------------------------------------
// Lunes 08:00: a cada operación (Calama → Jefe de Operaciones Calama; Coquimbo →
// Bodega) con copia a Manuel. Solo los vehículos de SU operación: litros, $ y
// km GPS de la semana, y TODAS las diferencias sin justificar desde el inicio
// del control (no solo las de la semana: lo pendiente se arrastra).
// Jueves 08:00 (?recordatorio=1): solo si quedan pendientes.
// Cada diferencia se justifica en /combustible-justificar/<token>; Manuel la
// acepta o la rechaza en el tablero de control.
// Lo invoca pg_cron con x-cron-secret; sin service_role (fn_*_cron con secreto).
// ?previa=1 → datos reales, solo a Manuel, sin marcar como enviado.
// ============================================================================

type Reporte = {
  reporte_id: string
  token: string
  operacion: string
  semana_desde: string
  semana_hasta: string
  responsable: string | null
  para: string[]
  cc: string[]
  vehiculos: VehiculoSemana[]
  diferencias: DiferenciaComb[]
}

const n0 = (n: number | null | undefined) => (n == null ? '—' : Math.round(n).toLocaleString('es-CL'))
const n1 = (n: number | null | undefined) => (n == null ? '—' : n.toLocaleString('es-CL', { maximumFractionDigits: 1 }))
const fecha = (s: string) => new Date(`${s}T12:00:00`).toLocaleDateString('es-CL', { day: '2-digit', month: 'short' })
const fechaHora = (s: string) => {
  const d = new Date(s)
  return d.toLocaleDateString('es-CL', { weekday: 'short', day: '2-digit', month: 'short' }) + ' ' +
    d.toLocaleTimeString('es-CL', { hour: '2-digit', minute: '2-digit' })
}
const alertaTxt = (a: string) => ALERTA_TXT[a as Alerta] ?? a

export async function POST(req: Request) {
  const secret = process.env.CRON_SECRET
  if (!secret || req.headers.get('x-cron-secret') !== secret) {
    return NextResponse.json({ error: 'No autorizado.' }, { status: 401 })
  }
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL
  const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
  if (!url || !anon) return NextResponse.json({ error: 'Falta configuración de Supabase.' }, { status: 500 })
  if (!mailerConfigured()) return NextResponse.json({ error: 'El correo no está configurado.' }, { status: 500 })

  const qs = new URL(req.url).searchParams
  const recordatorio = qs.get('recordatorio') === '1'
  const previa = qs.get('previa') === '1'
  const base = process.env.NEXT_PUBLIC_SITE_URL || 'https://pilladoiceo.netlify.app'

  const sb = createClient(url, anon, { auth: { persistSession: false } })
  const { data, error } = await sb.rpc('fn_comb_tarjeta_semanal_cron', { p_secreto: secret, p_recordatorio: recordatorio })
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })

  const resultados: { operacion: string; enviado: boolean; pendientes: number; error?: string }[] = []
  for (const r of (data ?? []) as Reporte[]) {
    const pendientes = r.diferencias.filter((d) => d.estado === 'pendiente')
    const porValidar = r.diferencias.filter((d) => d.estado === 'por_validar')
    if (recordatorio && pendientes.length === 0) {
      resultados.push({ operacion: r.operacion, enviado: false, pendientes: 0 })
      continue
    }
    const enlace = `${base}/combustible-justificar/${r.token}/`
    const litros = r.vehiculos.reduce((s, v) => s + (v.litros ?? 0), 0)
    const pago = r.vehiculos.reduce((s, v) => s + (v.pago ?? 0), 0)

    const vehiculos: ItemSimple[] = r.vehiculos.map((v) => ({
      titulo: v.patente,
      sub: `${v.cargas} carga${v.cargas === 1 ? '' : 's'}`,
      lineas: [
        { texto: `${n1(v.litros)} L · $${n0(v.pago)} · ${n0(v.km)} km según GPS` },
        ...(v.sin_explicar_30d != null ? [{
          texto: v.sin_explicar_30d > 0
            ? `Últimos 30 días: ${n0(v.sin_explicar_30d)} L más de lo que explican sus km`
            : 'Últimos 30 días: los litros cuadran con los km del GPS',
          alerta: v.sin_explicar_30d > 0,
        }] : []),
      ],
    }))
    const difItem = (d: DiferenciaComb): ItemSimple => ({
      titulo: `${d.patente} · ${fechaHora(d.fecha_hora)}`,
      sub: `${n1(d.litros)} L · $${n0(d.total_pago)} · ${d.estacion ?? ''}`,
      lineas: [
        ...d.alertas.map((a) => ({ texto: alertaTxt(a), alerta: true })),
        ...(d.chofer ? [{ texto: `Chofer en la tarjeta: ${d.chofer}` }] : []),
        ...(d.rechazada && d.nota_validacion ? [{ texto: `Justificación rechazada: ${d.nota_validacion}`, alerta: true }] : []),
      ],
    })

    const titulo = recordatorio
      ? `Recordatorio: ${pendientes.length} diferencia${pendientes.length === 1 ? '' : 's'} de combustible sin justificar · ${r.operacion}`
      : `Control de combustible ${r.operacion} · semana ${fecha(r.semana_desde)} al ${fecha(r.semana_hasta)}`
    const { html, text } = correoSimple({
      titulo,
      intro: [
        `${r.responsable ? r.responsable + ': ' : ''}este es el control semanal de las tarjetas de combustible Aramco de ${r.operacion}. SICOM cruza cada carga con el GPS del vehículo.`,
        pendientes.length > 0
          ? `Hay ${pendientes.length} diferencia${pendientes.length === 1 ? '' : 's'} que debe justificar. Use el enlace al final del correo: por cada una, explique qué pasó y quién cargó. Lo que no se justifique sigue apareciendo cada semana y queda visible para la jefatura.`
          : 'No hay diferencias pendientes de justificar.',
        recordatorio ? '' : `Semana: ${n1(litros)} L · $${n0(pago)} en ${r.vehiculos.length} vehículo${r.vehiculos.length === 1 ? '' : 's'}.`,
      ].filter(Boolean),
      secciones: [
        { titulo: 'Diferencias por justificar', nota: 'Horario normal de carga: lunes a viernes de 07:00 a 19:00.', items: pendientes.map(difItem) },
        { titulo: 'Justificadas, esperando validación de jefatura', items: porValidar.map(difItem) },
        ...(recordatorio ? [] : [{ titulo: 'Consumo de la semana por vehículo', items: vehiculos }]),
      ],
      enlace: pendientes.length > 0 || porValidar.length > 0
        ? { url: enlace, texto: 'Justificar diferencias' }
        : { url: enlace, texto: 'Ver el detalle' },
      pie: 'SICOM · control de combustible. Las tarjetas se sincronizan cada hora con Aramco Fleet y se comparan con el GPS.',
    })

    const to = previa ? ['manuel.olivares@pilladoempresas.cl'] : r.para
    const cc = previa ? [] : r.cc
    const envio = await sendMail({ to, cc, subject: (previa ? '[VISTA PREVIA] ' : '') + titulo, html, text })
    if (!previa) {
      await sb.rpc('fn_comb_tarjeta_semanal_marcar_cron', {
        p_secreto: secret, p_reporte_id: r.reporte_id, p_recordatorio: recordatorio, p_ok: envio.ok, p_error: envio.error ?? null,
      })
    }
    resultados.push({ operacion: r.operacion, enviado: envio.ok, pendientes: pendientes.length, error: envio.error })
  }
  return NextResponse.json({ ok: true, recordatorio, previa, resultados })
}
