import { createClient, type User as SupabaseUser } from '@supabase/supabase-js'

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

export const supabase = createClient(
  supabaseUrl || 'https://placeholder.supabase.co',
  supabaseAnonKey || 'placeholder-key'
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
  if (typeof localStorage === 'undefined') return null
  try {
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
