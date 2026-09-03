import { supabase } from '@/lib/supabase'

// ============================================================================
// Correo a compras para cotizar un repuesto (2026-09-03)
// ----------------------------------------------------------------------------
// Fase de pruebas: NADA sale automático. Cuando bodega manda un ítem «A
// compra», la pantalla pregunta si además quiere avisarle a compras por correo
// — y solo con esa autorización se envía. El servidor valida la SESIÓN del
// usuario (no un secreto de cron): quien autoriza queda identificado y el
// Reply-To del correo apunta a él.
// ============================================================================

export async function enviarCorreoCompras(recursoId: string): Promise<{
  ok: boolean; enviado_a?: string; error?: string
}> {
  const { data: { session } } = await supabase.auth.getSession()
  if (!session?.access_token) return { ok: false, error: 'Sesión expirada: vuelve a entrar.' }
  try {
    // Barra final obligatoria: el sitio usa trailingSlash.
    const res = await fetch('/api/notificaciones/compra-repuesto/', {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        authorization: `Bearer ${session.access_token}`,
      },
      body: JSON.stringify({ recursoId }),
    })
    const j = await res.json().catch(() => ({}))
    if (!res.ok) return { ok: false, error: j.error ?? `Error ${res.status}` }
    return { ok: true, enviado_a: j.enviado_a }
  } catch (e) {
    return { ok: false, error: e instanceof Error ? e.message : 'Sin conexión' }
  }
}
