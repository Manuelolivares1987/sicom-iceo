// ============================================================================
// Conectividad REAL (19-11-2026)
// ----------------------------------------------------------------------------
// `navigator.onLine` solo dice si el teléfono tiene una red, no si llega a
// SICOM: el Wi-Fi del campamento con portal cautivo, la antena con barras pero
// sin datos o el 4G que se cae entre rajos dicen "online" y todas las
// consultas quedan colgadas. Y al revés: con la pantalla apagada o tras un
// cambio de antena el evento «online» a veces nunca llega y lo pendiente no
// se sube.
//
// Este módulo es la única fuente de verdad de la conexión:
//   - Sondea /auth/v1/health de Supabase (la base que de verdad usamos), con
//     límite de 5 s: cada 30 s con señal, cada 10 s sin ella, y al volver a la
//     pantalla. Con la app en segundo plano no gasta batería.
//   - Aprende del tráfico real: una respuesta de Supabase = hay red; un error
//     de red = sondear ya.
//   - Sin conexión se declara con 2 fallas seguidas (o si el teléfono dice que
//     no tiene red). Conexión, con 1 éxito.
//   - Al cambiar, dispara los eventos «online»/«offline» del navegador: así
//     TODOS los sincronizadores de las apps de terreno (que ya escuchan esos
//     eventos) se despiertan cuando la señal vuelve de verdad, sin tocarlos
//     uno por uno. Y avisa a React Query, que pausa y reanuda sus consultas.
// ============================================================================

import { onlineManager } from '@tanstack/react-query'

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL || ''
const SUPABASE_ANON = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || ''

const SONDEO_CON_RED_MS = 30_000
const SONDEO_SIN_RED_MS = 10_000
const LIMITE_SONDEO_MS = 5_000
const FALLAS_PARA_OFFLINE = 2

export const EVENTO_CONECTIVIDAD = 'sicom:conectividad'

let iniciado = false
let enLinea = typeof navigator === 'undefined' ? true : navigator.onLine
let fallas = 0
let timer: ReturnType<typeof setTimeout> | null = null
let sondeando = false
let despachando = false

export function estaEnLinea(): boolean {
  return enLinea
}

function fijar(nuevo: boolean) {
  if (nuevo === enLinea) return
  enLinea = nuevo
  despachando = true
  try {
    window.dispatchEvent(new CustomEvent(EVENTO_CONECTIVIDAD, { detail: { enLinea: nuevo } }))
    // Solo si el navegador no lo dijo ya: es lo que despierta a los
    // sincronizadores cuando la señal vuelve sin que el teléfono lo note.
    window.dispatchEvent(new Event(nuevo ? 'online' : 'offline'))
  } finally {
    despachando = false
  }
  programar()
}

async function sondear(): Promise<void> {
  if (sondeando || typeof window === 'undefined') return
  if (!navigator.onLine) { fallas = FALLAS_PARA_OFFLINE; fijar(false); return }
  if (!SUPABASE_URL) return
  sondeando = true
  const ctrl = new AbortController()
  const t = setTimeout(() => ctrl.abort(), LIMITE_SONDEO_MS)
  try {
    const r = await fetch(`${SUPABASE_URL}/auth/v1/health`, {
      headers: { apikey: SUPABASE_ANON },
      cache: 'no-store',
      signal: ctrl.signal,
    })
    // Un portal cautivo responde, pero no con un 200 de Supabase.
    if (r.ok) { fallas = 0; fijar(true) } else registrarFalla()
  } catch {
    registrarFalla()
  } finally {
    clearTimeout(t)
    sondeando = false
    programar()
  }
}

function registrarFalla() {
  fallas += 1
  if (fallas >= FALLAS_PARA_OFFLINE) fijar(false)
}

function programar(ms?: number) {
  if (typeof window === 'undefined') return
  if (timer) clearTimeout(timer)
  timer = null
  if (document.visibilityState === 'hidden') return
  timer = setTimeout(() => { void sondear() }, ms ?? (enLinea ? SONDEO_CON_RED_MS : SONDEO_SIN_RED_MS))
}

/** El cliente de Supabase avisa: llegó una respuesta (hay red). */
export function reportarExitoRed(): void {
  fallas = 0
  if (!enLinea) fijar(true)
}

/** El cliente de Supabase avisa: falló la red (no un error de la base). */
export function reportarFalloRed(): void {
  // Se confirma con un sondeo corto en vez de declarar offline por una consulta.
  programar(500)
}

/** Idempotente. Se llama una vez desde el layout raíz. */
export function iniciarConectividad(): void {
  if (iniciado || typeof window === 'undefined') return
  iniciado = true
  // React Query deja de mirar navigator.onLine y mira esto: pausa las
  // consultas sin conexión real y las reanuda cuando vuelve.
  onlineManager.setEventListener((setOnline) => {
    const h = (e: Event) => setOnline((e as CustomEvent<{ enLinea: boolean }>).detail.enLinea)
    window.addEventListener(EVENTO_CONECTIVIDAD, h)
    setOnline(enLinea)
    return () => window.removeEventListener(EVENTO_CONECTIVIDAD, h)
  })

  window.addEventListener('online', () => { if (!despachando) { fallas = 0; void sondear() } })
  window.addEventListener('offline', () => { if (!despachando) { fallas = FALLAS_PARA_OFFLINE; fijar(false) } })
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') void sondear()
    else if (timer) { clearTimeout(timer); timer = null }
  })
  void sondear()
}
