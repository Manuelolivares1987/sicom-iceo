import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { leerRenault, statusesAEventos } from '@/lib/gps/renault-rfms'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'
export const maxDuration = 60

// ============================================================================
// Poll del GPS de fábrica Renault Trucks (rFMS) — MIG635
// ----------------------------------------------------------------------------
// pg_cron 'gps-renault-rfms' cada 15 min → acá. Sin service_role: el secreto
// habilita solo fn_renault_rfms_config_cron (credencial + cursor) y
// rpc_renault_ingestar_cron (enlace por VIN + ingesta + cursor), MIG301.
// Requiere CRON_SECRET.
// ============================================================================

export async function POST(req: Request) {
  const secret = process.env.CRON_SECRET
  if (!secret || req.headers.get('x-cron-secret') !== secret) {
    return NextResponse.json({ error: 'No autorizado' }, { status: 401 })
  }
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL
  const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
  if (!url || !anon) {
    return NextResponse.json({ error: 'Falta configuración de Supabase' }, { status: 500 })
  }
  const sb = createClient(url, anon, { auth: { persistSession: false } })

  const { data: cfg, error: eCfg } = await sb.rpc('fn_renault_rfms_config_cron', { p_secreto: secret })
  if (eCfg) return NextResponse.json({ error: eCfg.message }, { status: 500 })
  if (!cfg?.activo) return NextResponse.json({ omitido: 'Proveedor Renault inactivo' })
  if (!cfg.base_url || !cfg.credencial) {
    return NextResponse.json({ error: 'Renault sin URL o credencial' }, { status: 500 })
  }

  try {
    const lectura = await leerRenault({
      baseUrl: cfg.base_url,
      credencial: cfg.credencial,
      cursorTs: cfg.cursor_ts ?? null,
      cursorVin: cfg.cursor_vin ?? null,
    })
    const eventos = statusesAEventos(lectura.statuses)
    const { data, error } = await sb.rpc('rpc_renault_ingestar_cron', {
      p_secreto: secret,
      p_vehiculos: lectura.vehiculos.map((v) => ({ vin: v.VIN, modelo: v.Model ?? null })),
      p_eventos: eventos,
      p_cursor_ts: lectura.cursorTs,
      p_cursor_vin: lectura.cursorVin,
    })
    if (error) throw new Error(error.message)
    return NextResponse.json({
      ok: true,
      vehiculos: lectura.vehiculos.length,
      lecturas: lectura.statuses.length,
      paginas: lectura.paginas,
      completo: lectura.completo,
      eventos: eventos.length,
      resultado: data,
    })
  } catch (e) {
    return NextResponse.json({ error: e instanceof Error ? e.message : String(e) }, { status: 502 })
  }
}
