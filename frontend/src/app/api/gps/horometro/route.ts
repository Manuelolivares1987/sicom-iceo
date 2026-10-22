import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { autenticar } from '@/lib/copiloto/server'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'
export const maxDuration = 30

// ============================================================================
// Corregir horómetro / odómetro en Radicom y SICOM a la vez — MIG641
// ----------------------------------------------------------------------------
// POST {accion:'leer', activoId}      → lo que marcan Radicom (ahora) y SICOM.
// POST {accion:'corregir', activoId, horas, km, moverBases, nota}
//   1. rpc_horometro_preparar con el token del usuario (permiso + fuente).
//   2. Lee el contador Radicom en este instante: la diferencia se mide contra
//      él, no contra la lectura de las 05:00 (el camión trabajó entre medio).
//   3. Lo fija en Radicom (tracker/counter/value/set).
//   4. rpc_horometro_corregir aplica la diferencia en SICOM. Si Radicom no
//      acepta el cambio, SICOM no se toca.
// La clave de Radicom no sale del servidor (secreto cron_alertas, MIG301).
// ============================================================================

type Tipo = 'engine_hours' | 'odometer'
type Preparado = { fuente: 'radicom' | 'renault' | 'sin_gps'; tracker_id: string | null; horas: number | null; km: number | null }
type Radicom = { base: string; hash: string }

async function navixy(r: Radicom, accion: string, body: Record<string, unknown>) {
  const res = await fetch(`${r.base}/tracker/counter/value/${accion}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ hash: r.hash, ...body }),
  })
  const j = await res.json().catch(() => ({}))
  if (!j?.success) {
    const st = j?.status
    throw new Error(st?.description ? `Radicom: ${st.description} (código ${st.code})` : `Radicom respondió HTTP ${res.status}`)
  }
  return j
}

async function leerContador(r: Radicom, trackerId: string, type: Tipo): Promise<number | null> {
  try {
    const j = await navixy(r, 'get', { tracker_id: Number(trackerId), type })
    return typeof j.value === 'number' ? j.value : null
  } catch {
    return null   // sin contador de ese tipo (código 204)
  }
}

async function credencialRadicom(): Promise<Radicom> {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL!
  const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
  const secret = process.env.CRON_SECRET
  if (!secret) throw new Error('Falta CRON_SECRET en el servidor')
  const sb = createClient(url, anon, { auth: { persistSession: false } })
  const { data, error } = await sb.rpc('fn_radicom_credencial_cron', { p_secreto: secret })
  if (error) throw new Error(error.message)
  if (!data?.base_url || !data?.hash) throw new Error('Radicom sin URL o clave configurada')
  return { base: String(data.base_url).replace(/\/+$/, ''), hash: data.hash }
}

const num = (v: unknown) => (v === null || v === undefined || v === '' ? null : Number(v))

export async function POST(req: Request) {
  const auth = await autenticar(req)
  if ('error' in auth) return NextResponse.json({ error: auth.error }, { status: auth.status })
  const { sb } = auth

  const body = await req.json().catch(() => ({}))
  const activoId = String(body.activoId ?? '')
  if (!/^[0-9a-f-]{36}$/i.test(activoId)) return NextResponse.json({ error: 'Equipo inválido' }, { status: 400 })

  const { data: prep, error: ePrep } = await sb.rpc('rpc_horometro_preparar', { p_activo_id: activoId })
  if (ePrep) return NextResponse.json({ error: ePrep.message }, { status: 403 })
  const p = prep as Preparado

  try {
    const radicom = p.fuente === 'radicom' && p.tracker_id ? await credencialRadicom() : null
    const gpsHoras = radicom ? await leerContador(radicom, p.tracker_id!, 'engine_hours') : null
    const gpsKm = radicom ? await leerContador(radicom, p.tracker_id!, 'odometer') : null

    if (body.accion === 'leer') {
      return NextResponse.json({ fuente: p.fuente, horas_sicom: p.horas, km_sicom: p.km, horas_gps: gpsHoras, km_gps: gpsKm })
    }
    if (body.accion !== 'corregir') return NextResponse.json({ error: 'Acción inválida' }, { status: 400 })
    if (p.fuente === 'renault') {
      return NextResponse.json({ error: 'Este camión toma el horómetro de su computador (Renault); no se corrige.' }, { status: 400 })
    }

    const horas = num(body.horas)
    const km = num(body.km)
    if ((horas !== null && !(horas > 0)) || (km !== null && !(km > 0)) || (horas === null && km === null)) {
      return NextResponse.json({ error: 'Indica un horómetro u odómetro mayor que cero.' }, { status: 400 })
    }

    // Antes: Radicom en este instante; sin GPS, lo que tiene SICOM.
    const horasAntes = radicom ? (gpsHoras ?? p.horas) : p.horas
    const kmAntes = radicom ? (gpsKm ?? p.km) : p.km
    const registro: Record<string, unknown> = { ok: true, tracker_id: p.tracker_id, antes: { horas: gpsHoras, km: gpsKm } }

    if (radicom) {
      // Si el segundo contador falla, el primero ya quedó: se registra lo que entró.
      let horasOk: number | null = null
      let kmOk: number | null = null
      try {
        if (horas !== null) {
          await navixy(radicom, 'set', { tracker_id: Number(p.tracker_id), type: 'engine_hours', value: horas })
          horasOk = horas
        }
        if (km !== null) {
          await navixy(radicom, 'set', { tracker_id: Number(p.tracker_id), type: 'odometer', value: km })
          kmOk = km
        }
      } catch (e) {
        if (horasOk === null && kmOk === null) throw e
        registro.error_parcial = (e as Error).message
      }
      const { data, error } = await sb.rpc('rpc_horometro_corregir', {
        p_activo_id: activoId, p_fuente: 'radicom',
        p_horas_antes: horasAntes, p_horas: horasOk, p_km_antes: kmAntes, p_km: kmOk,
        p_mover_bases: Boolean(body.moverBases), p_nota: String(body.nota ?? ''), p_radicom: registro,
      })
      if (error) {
        return NextResponse.json({
          error: `Radicom ya quedó corregido, pero SICOM no: ${error.message}. Avisa a soporte antes de las 05:00.`,
        }, { status: 500 })
      }
      return NextResponse.json({ ...data, fuente: 'radicom', aviso: registro.error_parcial ?? null })
    }

    const { data, error } = await sb.rpc('rpc_horometro_corregir', {
      p_activo_id: activoId, p_fuente: 'sin_gps',
      p_horas_antes: horasAntes, p_horas: horas, p_km_antes: kmAntes, p_km: km,
      p_mover_bases: Boolean(body.moverBases), p_nota: String(body.nota ?? ''), p_radicom: null,
    })
    if (error) return NextResponse.json({ error: error.message }, { status: 400 })
    return NextResponse.json({ ...data, fuente: 'sin_gps', aviso: null })
  } catch (e) {
    return NextResponse.json({ error: (e as Error).message }, { status: 502 })
  }
}
