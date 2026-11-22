// ============================================================================
// Cuentas de SICOM — lado servidor (22-11-2026)
// ----------------------------------------------------------------------------
// Lo usan /api/admin/cuentas (solo administrador) y /api/cuentas/crear-clave
// (público, con el enlace). Usa la service role: NUNCA importar desde el
// navegador.
//
// Acceso por enlace (decisión de Manuel, 22-11): al crear la cuenta se le manda
// un enlace «Crear mi clave». El token (32 bytes al azar) no se guarda: se
// guarda su SHA-256 y su vencimiento en app_metadata.acceso del usuario (solo
// la service role escribe app_metadata). Al usarse se borra: sirve una vez.
// ============================================================================
import crypto from 'node:crypto'
import { createClient, type SupabaseClient } from '@supabase/supabase-js'

export const VIGENCIA_ACCESO_H = 72
export const SITIO = (process.env.NEXT_PUBLIC_SITE_URL || 'https://pilladoiceo.netlify.app').replace(/\/$/, '')
export const APK_URL = 'https://github.com/Manuelolivares1987/sicom-iceo/releases/download/sicom-terreno/sicom-terreno.apk'

export const ROLES_VALIDOS = [
  'administrador', 'gerencia', 'subgerente_operaciones', 'jefe_operaciones', 'jefe_mantenimiento',
  'supervisor', 'planificador', 'tecnico_mantenimiento', 'bodeguero', 'operador_abastecimiento',
  'comercial', 'prevencionista', 'colaborador', 'auditor', 'auditor_calidad', 'rrhh_incentivos',
  'operador_taller', 'operador_combustible',
] as const
export const APPS_TERRENO = ['/m/franke', '/m/romeral', '/m/calama', '/m/taller', '/m/enex', '/m/prevencion'] as const
export const ROLES_CALAMA = ['operador_calama', 'supervisor_calama', 'jefe_sucursal'] as const
export const MODULOS_VALIDOS = new Set([
  'contratos', 'activos', 'ordenes_trabajo', 'inventario', 'mantenimiento', 'abastecimiento', 'cumplimiento',
  'kpi', 'iceo', 'reportes', 'auditoria', 'admin', 'flota', 'prevencion', 'comercial', 'reporte_diario',
  'operacion_calama', 'bodega', 'mantencion_qr',
])
export const PERMISOS_VALIDOS = new Set(['view', 'create', 'edit', 'delete', 'approve', 'export'])

export function clienteServicio(): SupabaseClient | null {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY
  if (!url || !key) return null
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } })
}

/** Quién llama: solo un administrador activo puede administrar cuentas. */
export async function administradorDe(req: Request, admin: SupabaseClient): Promise<string | null> {
  const token = req.headers.get('authorization')?.replace(/^Bearer\s+/i, '')
  if (!token) return null
  const { data, error } = await admin.auth.getUser(token)
  if (error || !data?.user) return null
  const { data: p } = await admin.from('usuarios_perfil').select('rol, activo').eq('id', data.user.id).maybeSingle()
  return p && p.activo !== false && p.rol === 'administrador' ? data.user.id : null
}

const sha256 = (s: string) => crypto.createHash('sha256').update(s).digest('hex')

/** Genera un enlace nuevo (invalida el anterior) y lo deja anotado en el usuario. */
export async function nuevoEnlaceAcceso(admin: SupabaseClient, userId: string): Promise<{ enlace: string; vence: string }> {
  const { data, error } = await admin.auth.admin.getUserById(userId)
  if (error || !data?.user) throw new Error('La cuenta no existe')
  const token = crypto.randomBytes(32).toString('base64url')
  const vence = new Date(Date.now() + VIGENCIA_ACCESO_H * 3600_000).toISOString()
  const meta = { ...(data.user.app_metadata ?? {}), acceso: { hash: sha256(token), vence } }
  const { error: e2 } = await admin.auth.admin.updateUserById(userId, { app_metadata: meta })
  if (e2) throw e2
  return { enlace: `${SITIO}/crear-clave/?u=${encodeURIComponent(userId)}&t=${token}`, vence }
}

/** Usa el enlace: valida token y vencimiento, fija la clave y borra el token. */
export async function usarEnlaceAcceso(admin: SupabaseClient, userId: string, token: string, clave: string): Promise<{ email: string }> {
  const { data, error } = await admin.auth.admin.getUserById(userId)
  const acceso = (data?.user?.app_metadata as { acceso?: { hash?: string; vence?: string } } | undefined)?.acceso
  if (error || !data?.user || !acceso?.hash || !acceso.vence) throw new Error('ENLACE_INVALIDO')
  const a = Buffer.from(sha256(token), 'hex'), b = Buffer.from(acceso.hash, 'hex')
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) throw new Error('ENLACE_INVALIDO')
  if (new Date(acceso.vence).getTime() < Date.now()) throw new Error('ENLACE_VENCIDO')
  const meta = { ...(data.user.app_metadata ?? {}) } as Record<string, unknown>
  delete meta.acceso
  const { error: e2 } = await admin.auth.admin.updateUserById(userId, { password: clave, app_metadata: meta, email_confirm: true })
  if (e2) throw e2
  return { email: data.user.email ?? '' }
}

const esc = (s: string) => s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]!))

export function correoAcceso(p: { nombre: string; email: string; enlace: string; terreno: boolean }): { subject: string; html: string; text: string } {
  const nombre = esc(p.nombre.split(' ')[0] || p.nombre)
  const boton = (href: string, txt: string, color: string) =>
    `<a href="${href}" style="display:inline-block;background:${color};color:#fff;text-decoration:none;font-weight:600;padding:12px 20px;border-radius:8px">${txt}</a>`
  const terreno = p.terreno ? `
    <h3 style="margin:24px 0 8px;font-size:16px">Si trabajas en terreno con un teléfono Android</h3>
    <ol style="margin:0;padding-left:20px;line-height:1.6">
      <li>Primero crea tu clave con el botón de arriba.</li>
      <li>Descarga la app SICOM: ${boton(APK_URL, 'Descargar la app SICOM', '#374151')}</li>
      <li>Ábrela, toca «Instalar» (si el teléfono lo pide, permite instalar desde esta fuente; si sale Play Protect, «Instalar de todas formas»).</li>
      <li>Entra con tu correo y tu clave. Funciona también sin señal: lo que guardes se sube solo cuando vuelve.</li>
    </ol>` : ''
  const html = `<div style="font-family:Arial,Helvetica,sans-serif;color:#111827;max-width:560px">
    <p style="font-size:16px">Hola ${nombre},</p>
    <p>Se creó tu cuenta en <b>SICOM</b> (Pillado Empresas). Para entrar, primero crea tu clave:</p>
    <p>${boton(esc(p.enlace), 'Crear mi clave', '#257032')}</p>
    <p style="font-size:13px;color:#4b5563">El enlace sirve una sola vez y vence en ${VIGENCIA_ACCESO_H} horas. Si venció, pide a la oficina que te lo reenvíe.</p>
    <p>Tu usuario es tu correo: <b>${esc(p.email)}</b></p>
    <p>Desde el computador entra en <a href="${SITIO}/login/">${SITIO.replace(/^https?:\/\//, '')}</a>.</p>
    ${terreno}
    <p style="margin-top:24px;font-size:12px;color:#6b7280">Si no esperabas este correo, ignóralo: sin crear la clave nadie puede entrar con esta cuenta.</p>
  </div>`
  const text = [
    `Hola ${p.nombre},`, '', 'Se creó tu cuenta en SICOM (Pillado Empresas). Crea tu clave aquí:', p.enlace, '',
    `El enlace sirve una vez y vence en ${VIGENCIA_ACCESO_H} horas. Tu usuario es tu correo: ${p.email}`,
    `Computador: ${SITIO}/login/`,
    ...(p.terreno ? ['', `App para teléfonos Android: ${APK_URL}`] : []),
  ].join('\n')
  return { subject: 'Tu acceso a SICOM', html, text }
}
