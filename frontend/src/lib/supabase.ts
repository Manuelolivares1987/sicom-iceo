// Completa crypto.randomUUID en visores antiguos (Android 10 de fábrica).
import '@/lib/uuid'
import { createClient, type User as SupabaseUser } from '@supabase/supabase-js'
import { reportarExitoRed, reportarFalloRed } from '@/lib/conectividad'

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL || ''
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || ''

// Fail loudly en el navegador si faltan las env vars (en build estático están
// ausentes y el placeholder evita romper la generación de páginas).
if (typeof window !== 'undefined' && (!supabaseUrl || !supabaseAnonKey)) {
  // eslint-disable-next-line no-console
  console.error(
    '[supabase] NEXT_PUBLIC_SUPABASE_URL y/o NEXT_PUBLIC_SUPABASE_ANON_KEY no están definidas. ' +
      'Configure las variables en .env.local (desarrollo) o en Netlify (producción).'
  )
}

/**
 * [19-11-2026] Ninguna llamada a Supabase puede esperar para siempre.
 * Con señal a medias el navegador deja la petición abierta minutos: la
 * pantalla queda en «Cargando…» y el código offline de cada app (que sabe
 * usar lo guardado cuando la consulta FALLA) nunca se entera. Con límite, la
 * consulta falla a tiempo y cada app cae a lo que tiene en el teléfono.
 * Fotos y PDF (Storage) y las funciones (Copiloto) tienen más margen.
 */
function limitePara(url: string): number {
  if (url.includes('/storage/v1/')) return 300_000
  if (url.includes('/functions/v1/')) return 150_000
  if (url.includes('/auth/v1/')) return 20_000
  return 60_000
}

export function fetchConLimite(input: RequestInfo | URL, init?: RequestInit): Promise<Response> {
  const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url
  const ctrl = new AbortController()
  const t = setTimeout(() => ctrl.abort(), limitePara(url))
  const externo = init?.signal
  if (externo) {
    if (externo.aborted) ctrl.abort()
    else externo.addEventListener('abort', () => ctrl.abort(), { once: true })
  }
  return fetch(input, { ...init, signal: ctrl.signal })
    .then((r) => { reportarExitoRed(); return r })
    .catch((e) => {
      // Lo cancelado por la propia pantalla no es un problema de señal.
      if (!externo?.aborted) reportarFalloRed()
      throw e
    })
    .finally(() => clearTimeout(t))
}

export const supabase = createClient(
  supabaseUrl || 'https://placeholder.supabase.co',
  supabaseAnonKey || 'placeholder-key',
  { global: { fetch: fetchConLimite } },
)

/**
 * La sesión tal como quedó guardada en el teléfono, leída del storage sin pasar
 * por la red.
 *
 * En terreno el token de acceso dura una hora: al día siguiente, sin señal,
 * `supabase.auth.getSession()` intenta refrescarlo y puede quedarse esperando
 * indefinidamente. La sesión sigue existiendo — solo no se pudo revalidar —,
 * así que esto permite arrancar la app igual y trabajar con lo descargado.
 */
export function leerSesionPersistida(): { user: SupabaseUser; expirada: boolean } | null {
  try {
    if (typeof localStorage === 'undefined') return null
    for (let i = 0; i < localStorage.length; i++) {
      const k = localStorage.key(i)
      if (!k || !k.startsWith('sb-') || !k.endsWith('-auth-token')) continue

      let raw = localStorage.getItem(k)
      if (!raw) continue
      if (raw.startsWith('base64-')) raw = decodificarBase64(raw.slice(7))

      const s = JSON.parse(raw) as {
        refresh_token?: string
        expires_at?: number
        user?: SupabaseUser
      }
      // Sin refresh_token no hay sesión que valga: no inventamos una.
      if (!s?.refresh_token || !s?.user?.id) continue

      return {
        user: s.user,
        expirada: !!s.expires_at && s.expires_at * 1000 < Date.now(),
      }
    }
  } catch { /* storage ilegible: se sigue sin sesión local */ }
  return null
}

function decodificarBase64(b64: string): string {
  const bin = atob(b64)
  const bytes = Uint8Array.from(bin, (c) => c.charCodeAt(0))
  return new TextDecoder().decode(bytes)
}


/**
 * [20-11-2026] ¿Hay una sesión que el servidor pueda aceptar? (token guardado
 * con refresh_token). Sin esto, las colas sin señal subían como anónimo cuando
 * la sesión se había perdido, el servidor respondía «No autorizado» y el
 * registro quedaba marcado «rechazado» para siempre. Sin sesión, se espera.
 */
export function haySesionServidor(): boolean {
  return leerSesionPersistida() !== null
}

// Identidad del equipo: quién trabaja en este teléfono. Sobrevive a que la
// sesión se pierda por mala señal (como WhatsApp: el teléfono sigue siendo de
// esa persona). Solo se borra con «Cerrar sesión».
const IDENTIDAD_KEY = 'sicom-identidad-equipo'

export function guardarIdentidadEquipo(u: SupabaseUser): void {
  try { localStorage.setItem(IDENTIDAD_KEY, JSON.stringify({ user: u, at: Date.now() })) } catch { /* noop */ }
}

export function leerIdentidadEquipo(): SupabaseUser | null {
  try {
    const raw = typeof localStorage !== 'undefined' ? localStorage.getItem(IDENTIDAD_KEY) : null
    if (!raw) return null
    const j = JSON.parse(raw) as { user?: SupabaseUser }
    return j?.user?.id ? j.user : null
  } catch { return null }
}

export function borrarIdentidadEquipo(): void {
  try { localStorage.removeItem(IDENTIDAD_KEY) } catch { /* noop */ }
}
