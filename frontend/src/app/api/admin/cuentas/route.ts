// ============================================================================
// /api/admin/cuentas — administrar cuentas de SICOM (solo administrador)
// GET  → lista de cuentas con estado de acceso, permisos extra y rol Calama.
// POST → { accion: 'crear' | 'guardar' | 'enviar_acceso', ... }
// ============================================================================
import { NextResponse } from 'next/server'
import crypto from 'node:crypto'
import type { SupabaseClient } from '@supabase/supabase-js'
import { sendMail, mailerConfigured } from '@/lib/email/mailer'
import {
  clienteServicio, administradorDe, nuevoEnlaceAcceso, correoAcceso,
  ROLES_VALIDOS, APPS_TERRENO, ROLES_CALAMA, MODULOS_VALIDOS, PERMISOS_VALIDOS,
} from '@/lib/server/cuentas'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

type Ajustes = {
  nombre_completo?: string
  rol?: string
  cargo?: string | null
  faena_id?: string | null
  solo_su_faena?: boolean
  app_terreno?: string | null
  activo?: boolean
  rol_calama?: string | null
  permisos_extra?: Record<string, string[]>
}

const malo = (msg: string, status = 400) => NextResponse.json({ error: msg }, { status })

async function preparar(req: Request): Promise<{ admin: SupabaseClient; quien: string } | NextResponse> {
  const admin = clienteServicio()
  if (!admin) return malo('Falta configurar SUPABASE_SERVICE_ROLE_KEY en el servidor.', 500)
  const quien = await administradorDe(req, admin)
  if (!quien) return malo('Solo un administrador puede administrar cuentas.', 403)
  return { admin, quien }
}

function validar(a: Ajustes): string | null {
  if (a.nombre_completo !== undefined && a.nombre_completo.trim().length < 3) return 'El nombre es muy corto.'
  if (a.rol !== undefined && !(ROLES_VALIDOS as readonly string[]).includes(a.rol)) return 'Rol no válido.'
  if (a.app_terreno && !(APPS_TERRENO as readonly string[]).includes(a.app_terreno)) return 'App de terreno no válida.'
  if (a.rol_calama && !(ROLES_CALAMA as readonly string[]).includes(a.rol_calama)) return 'Rol de Calama no válido.'
  for (const [m, ps] of Object.entries(a.permisos_extra ?? {})) {
    if (!MODULOS_VALIDOS.has(m)) return `Módulo no válido: ${m}`
    if (!Array.isArray(ps) || ps.some((p) => !PERMISOS_VALIDOS.has(p))) return `Permisos no válidos en ${m}`
  }
  return null
}

async function aplicar(admin: SupabaseClient, quien: string, userId: string, a: Ajustes) {
  const perfil: Record<string, unknown> = {}
  if (a.nombre_completo !== undefined) perfil.nombre_completo = a.nombre_completo.trim()
  if (a.rol !== undefined) perfil.rol = a.rol
  if (a.cargo !== undefined) perfil.cargo = a.cargo?.trim() || null
  if (a.faena_id !== undefined) perfil.faena_id = a.faena_id || null
  if (a.solo_su_faena !== undefined) perfil.solo_su_faena = a.solo_su_faena
  if (a.app_terreno !== undefined) perfil.app_terreno = a.app_terreno || null
  if (a.activo !== undefined) perfil.activo = a.activo
  if (Object.keys(perfil).length) {
    const { data, error } = await admin.from('usuarios_perfil').update(perfil).eq('id', userId).select('id')
    if (error) throw error
    if (!data?.length) throw new Error('No se encontró el perfil de la cuenta.')
  }
  if (a.permisos_extra !== undefined) {
    const { error } = await admin.from('usuario_permisos_extra').delete().eq('usuario_id', userId)
    if (error) throw error
    const filas = Object.entries(a.permisos_extra)
      .filter(([, ps]) => ps.length > 0)
      .map(([modulo, permisos]) => ({ usuario_id: userId, modulo, permisos, motivo: 'Asignado en Administración → Cuentas' }))
    if (filas.length) {
      const { error: e2 } = await admin.from('usuario_permisos_extra').insert(filas)
      if (e2) throw e2
    }
  }
  if (a.rol_calama !== undefined) {
    const nuevo = a.rol_calama || null
    const { data: activos, error } = await admin.from('calama_roles_proyecto')
      .select('id, rol_calama').eq('usuario_id', userId).eq('activo', true)
    if (error) throw error
    const quitar = (activos ?? []).filter((r) => r.rol_calama !== nuevo).map((r) => r.id)
    if (quitar.length) {
      const { error: e2 } = await admin.from('calama_roles_proyecto')
        .update({ activo: false, revocado_at: new Date().toISOString() }).in('id', quitar)
      if (e2) throw e2
    }
    if (nuevo && !(activos ?? []).some((r) => r.rol_calama === nuevo)) {
      const { error: e3 } = await admin.from('calama_roles_proyecto')
        .insert({ usuario_id: userId, rol_calama: nuevo, activo: true, asignado_por: quien, notas: 'Administración → Cuentas' })
      if (e3) throw e3
    }
  }
}

async function enviarAcceso(admin: SupabaseClient, userId: string, enviarCorreo: boolean) {
  const { data: p, error } = await admin.from('usuarios_perfil')
    .select('email, nombre_completo, app_terreno, faena:faenas!usuarios_perfil_faena_id_fkey(app_movil)')
    .eq('id', userId).maybeSingle()
  if (error) throw error
  if (!p?.email) throw new Error('La cuenta no tiene correo.')
  const { enlace, vence } = await nuevoEnlaceAcceso(admin, userId)
  let enviado = false, errorCorreo: string | undefined
  if (enviarCorreo) {
    if (!mailerConfigured()) errorCorreo = 'El correo del sistema no está configurado: copia el enlace y envíalo por WhatsApp.'
    else {
      const faena = (Array.isArray(p.faena) ? p.faena[0] : p.faena) as { app_movil?: string | null } | null
      const c = correoAcceso({ nombre: p.nombre_completo ?? '', email: p.email, enlace, terreno: !!(p.app_terreno || faena?.app_movil) })
      const r = await sendMail({ to: [p.email], subject: c.subject, html: c.html, text: c.text })
      enviado = r.ok
      if (!r.ok) errorCorreo = r.error ?? 'No se pudo enviar el correo.'
    }
  }
  return { enlace, vence, enviado, errorCorreo }
}

export async function GET(req: Request) {
  const ctx = await preparar(req)
  if (ctx instanceof NextResponse) return ctx
  const { admin } = ctx
  const [perfiles, extras, calama] = await Promise.all([
    admin.from('usuarios_perfil')
      .select('id, email, nombre_completo, rol, cargo, faena_id, activo, solo_su_faena, app_terreno, faena:faenas!usuarios_perfil_faena_id_fkey(nombre)')
      .order('nombre_completo'),
    admin.from('usuario_permisos_extra').select('usuario_id, modulo, permisos'),
    admin.from('calama_roles_proyecto').select('usuario_id, rol_calama').eq('activo', true),
  ])
  if (perfiles.error) return malo(perfiles.error.message, 500)
  const auth = new Map<string, { ultimo: string | null; acceso_vence: string | null }>()
  for (let page = 1; page <= 20; page++) {
    const { data, error } = await admin.auth.admin.listUsers({ page, perPage: 200 })
    if (error) return malo(error.message, 500)
    for (const u of data.users) {
      const acc = (u.app_metadata as { acceso?: { vence?: string } } | undefined)?.acceso
      auth.set(u.id, { ultimo: u.last_sign_in_at ?? null, acceso_vence: acc?.vence ?? null })
    }
    if (data.users.length < 200) break
  }
  const ext = new Map<string, Record<string, string[]>>()
  for (const r of (extras.data ?? []) as Array<{ usuario_id: string; modulo: string; permisos: string[] }>) {
    (ext.get(r.usuario_id) ?? ext.set(r.usuario_id, {}).get(r.usuario_id)!)[r.modulo] = r.permisos
  }
  const cal = new Map<string, string>()
  for (const r of (calama.data ?? []) as Array<{ usuario_id: string; rol_calama: string }>) cal.set(r.usuario_id, r.rol_calama)
  const cuentas = (perfiles.data ?? []).map((p) => ({
    ...p,
    faena_nombre: (Array.isArray(p.faena) ? p.faena[0] : p.faena)?.nombre ?? null,
    ultimo_ingreso: auth.get(p.id)?.ultimo ?? null,
    acceso_vence: auth.get(p.id)?.acceso_vence ?? null,
    permisos_extra: ext.get(p.id) ?? {},
    rol_calama: cal.get(p.id) ?? null,
  }))
  return NextResponse.json({ cuentas, correo_configurado: mailerConfigured() })
}

export async function POST(req: Request) {
  const ctx = await preparar(req)
  if (ctx instanceof NextResponse) return ctx
  const { admin, quien } = ctx
  let body: Ajustes & { accion?: string; user_id?: string; email?: string; enviar_correo?: boolean }
  try { body = await req.json() } catch { return malo('JSON inválido.') }

  try {
    if (body.accion === 'crear') {
      const email = (body.email ?? '').trim().toLowerCase()
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return malo('Correo no válido.')
      if (!body.nombre_completo || !body.rol) return malo('Falta el nombre o el rol.')
      const v = validar(body); if (v) return malo(v)
      const { data: creado, error } = await admin.auth.admin.createUser({
        email, email_confirm: true,
        // Clave al azar que nadie conoce: la persona crea la suya con el enlace.
        password: crypto.randomBytes(24).toString('base64url'),
        user_metadata: { nombre_completo: body.nombre_completo.trim(), rol: body.rol },
      })
      if (error || !creado?.user) {
        const m = error?.message ?? ''
        return malo(/already|registered|exists/i.test(m) ? 'Ya existe una cuenta con ese correo.' : (m || 'No se pudo crear la cuenta.'))
      }
      const id = creado.user.id
      const { error: ePerfil } = await admin.from('usuarios_perfil').upsert({
        id, email, nombre_completo: body.nombre_completo.trim(), rol: body.rol, activo: true,
      })
      if (ePerfil) {
        await admin.auth.admin.deleteUser(id).catch(() => undefined)
        throw ePerfil
      }
      await aplicar(admin, quien, id, { ...body, activo: true })
      const acceso = await enviarAcceso(admin, id, body.enviar_correo !== false)
      return NextResponse.json({ ok: true, user_id: id, ...acceso })
    }

    if (body.accion === 'guardar') {
      if (!body.user_id) return malo('Falta la cuenta.')
      const v = validar(body); if (v) return malo(v)
      if (body.user_id === quien && (body.activo === false || (body.rol && body.rol !== 'administrador'))) {
        return malo('No puedes quitarte a ti mismo el rol de administrador ni desactivar tu propia cuenta.')
      }
      await aplicar(admin, quien, body.user_id, body)
      return NextResponse.json({ ok: true })
    }

    if (body.accion === 'enviar_acceso') {
      if (!body.user_id) return malo('Falta la cuenta.')
      const acceso = await enviarAcceso(admin, body.user_id, body.enviar_correo !== false)
      return NextResponse.json({ ok: true, ...acceso })
    }
    return malo('Acción no válida.')
  } catch (e) {
    return malo((e as Error)?.message ?? 'Error inesperado', 500)
  }
}
