// [19-11-2026] Recuperación cuando el teléfono tiene una versión vieja de la app.
// Tras un deploy, Netlify ya no tiene los chunks JS del build anterior; el HTML
// viejo guardado por el service worker los pide, fallan, y la pantalla queda en
// su spinner pre-renderizado para siempre. Primera vez: recarga. Si vuelve a
// fallar en menos de un minuto: «Reparar app» (borra caché del SW, no IndexedDB).
import { repararApp } from '@/components/layout/redireccion-segura'

const CLAVE = 'sicom-recuperacion-chunk'

export function esErrorDeChunk(e: unknown): boolean {
  const err = e as { name?: string; message?: string } | null
  const texto = `${err?.name ?? ''} ${err?.message ?? String(e ?? '')}`
  return /ChunkLoadError|Loading chunk [\w-]+ failed|Loading CSS chunk|Failed to fetch dynamically imported module|Importing a module script failed/i.test(texto)
}

/**
 * 1.ª falla: recarga. 2.ª en menos de 2 min: «Reparar app». 3.ª: no hace nada más
 * (se queda la pantalla de error con sus botones) para no entrar en un bucle
 * de recargas si el problema es del servidor.
 */
export function recuperarVersion(): void {
  let previo = { t: 0, n: 0 }
  try { previo = JSON.parse(sessionStorage.getItem(CLAVE) || '{"t":0,"n":0}') } catch { /* sin storage */ }
  const ahora = Date.now()
  const n = ahora - previo.t < 120_000 ? previo.n + 1 : 1
  try { sessionStorage.setItem(CLAVE, JSON.stringify({ t: ahora, n })) } catch { /* sin storage */ }
  if (n === 1) window.location.reload()
  else if (n === 2) void repararApp()
}
