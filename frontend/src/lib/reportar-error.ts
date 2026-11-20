// [MIG722, 20-11-2026] El teléfono informa sus propios errores a la base, como
// los informes de fallo de WhatsApp. Usa fetch directo (no el cliente de
// Supabase: puede ser justo lo que falló) y funciona sin sesión.
// Máx. 5 informes por carga de página y sin repetir el mismo mensaje.

const enviados = new Set<string>()

function tokenSesion(): string | null {
  try {
    for (let i = 0; i < localStorage.length; i++) {
      const k = localStorage.key(i)
      if (!k || !k.startsWith('sb-') || !k.endsWith('-auth-token')) continue
      let raw = localStorage.getItem(k) ?? ''
      if (raw.startsWith('base64-')) raw = atob(raw.slice(7))
      const t = (JSON.parse(raw) as { access_token?: string; expires_at?: number })
      if (t?.access_token && (!t.expires_at || t.expires_at * 1000 > Date.now())) return t.access_token
    }
  } catch { /* sin storage */ }
  return null
}

export function reportarError(tipo: string, error: unknown, extra?: Record<string, unknown>): void {
  try {
    const url = process.env.NEXT_PUBLIC_SUPABASE_URL
    const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
    if (!url || !anon || typeof window === 'undefined') return
    const e = error as { name?: string; message?: string; stack?: string; digest?: string } | null
    const mensaje = `${e?.name ?? 'Error'}: ${e?.message ?? String(error)}`
    if (enviados.has(mensaje) || enviados.size >= 5) return
    enviados.add(mensaje)
    const body = JSON.stringify({
      p_tipo: tipo,
      p_mensaje: mensaje,
      p_stack: e?.stack ?? null,
      p_url: location.pathname + location.search,
      p_user_agent: navigator.userAgent,
      p_build: process.env.NEXT_PUBLIC_BUILD_ID ?? null,
      p_extra: {
        digest: e?.digest ?? null,
        online: navigator.onLine,
        sw: !!navigator.serviceWorker?.controller,
        ...extra,
      },
    })
    void fetch(`${url}/rest/v1/rpc/rpc_registrar_error_cliente`, {
      method: 'POST',
      keepalive: true,
      headers: { apikey: anon, Authorization: `Bearer ${tokenSesion() ?? anon}`, 'Content-Type': 'application/json' },
      body,
    }).catch(() => undefined)
  } catch { /* informar nunca puede romper la app */ }
}
