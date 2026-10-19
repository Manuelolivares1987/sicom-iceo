// ============================================================================
// Portal de flota para el cliente (MIG609)
// ----------------------------------------------------------------------------
// El cliente NO usa Supabase Auth: una sesión `authenticated` lee casi toda la
// base. Entra con correo y contraseña contra portal_flota_cuentas y recibe un
// token propio; cada RPC lo valida y resuelve el alcance en la base. Aquí sólo
// se guarda el token y se llama a las funciones.
// ============================================================================

import { supabase } from '@/lib/supabase'

const CLAVE_SESION = 'portal-flota-sesion'

export type SesionPortalFlota = {
  token: string
  expira_at: string
  nombre: string
  empresa: string | null
  email: string
  debe_cambiar: boolean
}

export type EquipoPortalResumen = {
  activo_id: string
  patente: string
  codigo: string
  nombre: string | null
  tipo: string | null
  marca_modelo: string | null
  anio: number | null
  docs_total: number
  docs_vencidos: number
  docs_por_vencer: number
  docs_sin_fecha: number
  docs_pendientes: number
  ultima_mantencion: string | null
}

export type FlotaPortal = {
  cuenta: { nombre: string; empresa: string | null; email: string; debe_cambiar: boolean }
  generado_at: string
  equipos: EquipoPortalResumen[]
}

export type EstadoDocPortal = 'vencido' | 'por_vencer' | 'vigente' | 'permanente' | 'sin_fecha'

export type DocumentoPortal = {
  tipo: string
  etiqueta: string | null
  numero: string | null
  entidad: string | null
  fecha_emision: string | null
  fecha_vencimiento: string | null
  dias_restantes: number | null
  estado: EstadoDocPortal
  archivo_url: string | null
}

export type MantencionPortal = {
  fecha: string | null
  tipo: string
  titulo: string
  detalle: string | null
  folio: string
  km: number | null
  horas: number | null
  con_observacion: boolean
}

export type FichaEquipoPortal = {
  equipo: {
    activo_id: string
    patente: string
    codigo: string
    nombre: string | null
    tipo: string | null
    marca_modelo: string | null
    anio: number | null
    vin: string | null
    motor: string | null
    capacidad: string | null
    kilometraje: number | null
    horometro: number | null
  }
  documentos: DocumentoPortal[]
  /** Tipos que el contrato exige y no están cargados (MIG612). */
  pendientes: string[]
  mantenciones: MantencionPortal[]
}

// ── Sesión en el navegador ─────────────────────────────────────────────────
export function leerSesion(): SesionPortalFlota | null {
  try {
    const raw = localStorage.getItem(CLAVE_SESION)
    if (!raw) return null
    const s = JSON.parse(raw) as SesionPortalFlota
    if (!s.token || new Date(s.expira_at).getTime() <= Date.now()) {
      localStorage.removeItem(CLAVE_SESION)
      return null
    }
    return s
  } catch {
    return null
  }
}

export function guardarSesion(s: SesionPortalFlota | null) {
  try {
    if (s) localStorage.setItem(CLAVE_SESION, JSON.stringify(s))
    else localStorage.removeItem(CLAVE_SESION)
  } catch {
    /* modo privado: la sesión vive sólo en memoria */
  }
}

/** El RPC avisa así que el token ya no sirve; la pantalla vuelve al ingreso. */
export const esSesionExpirada = (e: unknown) =>
  e instanceof Error && e.message.includes('Vuelva a ingresar')

async function rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.rpc(fn, args)
  if (error) throw new Error(error.message)
  return data as T
}

// ── Llamadas ───────────────────────────────────────────────────────────────
export async function ingresar(email: string, password: string): Promise<SesionPortalFlota> {
  const r = await rpc<SesionPortalFlota & { error?: string }>('rpc_portal_flota_login', {
    p_email: email.trim(),
    p_password: password,
  })
  if (r.error) throw new Error(r.error)
  return r
}

export async function salir(token: string) {
  try {
    await rpc('rpc_portal_flota_logout', { p_token: token })
  } catch {
    /* aunque falle, la sesión local se borra igual */
  }
}

export const cambiarPassword = (token: string, actual: string, nueva: string) =>
  rpc<void>('rpc_portal_flota_cambiar_password', { p_token: token, p_actual: actual, p_nueva: nueva })

export const cargarFlota = (token: string) =>
  rpc<FlotaPortal>('rpc_portal_flota_equipos', { p_token: token })

export const cargarFichaEquipo = (token: string, activoId: string) =>
  rpc<FichaEquipoPortal>('rpc_portal_flota_equipo', { p_token: token, p_activo_id: activoId })

export const registrarDescarga = (token: string, activoId: string, detalle: string) =>
  rpc<void>('rpc_portal_flota_registrar_descarga', {
    p_token: token, p_activo_id: activoId, p_detalle: detalle,
  }).catch(() => undefined) // el registro no puede impedir la descarga

// ── Descargas ──────────────────────────────────────────────────────────────
const limpiarNombre = (s: string) => s.replace(/[\\/:*?"<>|]+/g, '-').trim()

export function nombreArchivo(patente: string, etiqueta: string, url: string) {
  const ext = url.split('?')[0].split('.').pop()?.toLowerCase()
  return limpiarNombre(`${patente} - ${etiqueta}`) + (ext && ext.length <= 4 ? `.${ext}` : '.pdf')
}

/** Storage público de Supabase responde como adjunto con `?download=`. */
export function urlDescarga(url: string, nombre: string) {
  return `${url}${url.includes('?') ? '&' : '?'}download=${encodeURIComponent(nombre)}`
}

/** Todos los papeles del camión en un ZIP, nombrados por patente y documento. */
export async function descargarZip(
  patente: string,
  docs: { etiqueta: string; url: string }[],
  onProgreso?: (hechos: number, total: number) => void,
) {
  const JSZip = (await import('jszip')).default
  const zip = new JSZip()
  const usados = new Set<string>()
  let hechos = 0
  const fallidos: string[] = []

  for (const d of docs) {
    try {
      const r = await fetch(d.url)
      if (!r.ok) throw new Error(String(r.status))
      let nombre = nombreArchivo(patente, d.etiqueta, d.url)
      for (let i = 2; usados.has(nombre); i++) nombre = nombre.replace(/(\.\w+)$/, ` (${i})$1`)
      usados.add(nombre)
      zip.file(nombre, await r.blob())
    } catch {
      fallidos.push(d.etiqueta)
    }
    onProgreso?.(++hechos, docs.length)
  }

  const blob = await zip.generateAsync({ type: 'blob' })
  const a = document.createElement('a')
  a.href = URL.createObjectURL(blob)
  a.download = limpiarNombre(`${patente} - Documentación`) + '.zip'
  a.click()
  setTimeout(() => URL.revokeObjectURL(a.href), 10_000)
  return { fallidos }
}

// ── Administración (desde /dashboard/admin/portal-usuarios, sólo administrador) ──
export type CuentaPortalFlota = {
  id: string
  email: string
  nombre: string
  empresa: string | null
  activo: boolean
  debe_cambiar: boolean
  bloqueado: boolean
  ultimo_acceso_at: string | null
  created_at: string
  notas: string | null
  contratos: { id: string; codigo: string; cliente: string | null }[]
  n_equipos: number
  n_ingresos: number
  n_descargas: number
}

export const listarCuentasPortalFlota = () => rpc<CuentaPortalFlota[]>('rpc_admin_portal_flota_listar', {})

export const crearCuentaPortalFlota = (a: {
  email: string; nombre: string; empresa: string; contratos: string[]; password: string; notas?: string
}) =>
  rpc<string>('rpc_admin_portal_flota_crear', {
    p_email: a.email, p_nombre: a.nombre, p_empresa: a.empresa,
    p_contratos: a.contratos, p_password: a.password, p_notas: a.notas ?? null,
  })

export const resetPasswordPortalFlota = (cuentaId: string, password: string) =>
  rpc<void>('rpc_admin_portal_flota_reset_password', { p_cuenta_id: cuentaId, p_password: password })

export const editarCuentaPortalFlota = (cuentaId: string, cambios: { activo?: boolean; contratos?: string[] }) =>
  rpc<void>('rpc_admin_portal_flota_editar', {
    p_cuenta_id: cuentaId, p_activo: cambios.activo ?? null, p_contratos: cambios.contratos ?? null,
  })

/** Contraseña temporal legible para dictar o enviar: sin 0/O ni 1/l/I. */
export function generarPasswordTemporal() {
  const letras = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ'
  const nums = '23456789'
  const r = (s: string) => s[crypto.getRandomValues(new Uint32Array(1))[0] % s.length]
  return Array.from({ length: 6 }, () => r(letras)).join('') + r(nums) + r(nums) + r(nums)
}
