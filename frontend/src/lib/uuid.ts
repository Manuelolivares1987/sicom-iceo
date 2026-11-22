// ============================================================================
// UUID v4 que funciona en CUALQUIER teléfono (22-11-2026)
// ----------------------------------------------------------------------------
// crypto.randomUUID existe recién desde Chrome 92. El visor web de fábrica de
// Android 10 (el teléfono de Franke) es Chrome 74: ahí no existe. Varios
// módulos tenían un «plan B» que generaba ids como «1795207020668-k3j9x», que
// la base rechaza porque espera un UUID → la pauta/el despacho/el cierre
// quedaban rebotando para siempre. Otros llamaban crypto.randomUUID() directo
// y la pantalla se caía.
//
// uuidV4() usa el nativo si existe; si no, crypto.getRandomValues (Chrome 11+).
// Al importarse, además completa crypto.randomUUID para el código que lo llame
// directo (lo importa lib/supabase, que carga toda la app).
// ============================================================================

const nativo: (() => string) | null =
  typeof crypto !== 'undefined' && typeof (crypto as Crypto & { randomUUID?: () => string }).randomUUID === 'function'
    ? (crypto as Crypto & { randomUUID: () => string }).randomUUID.bind(crypto)
    : null

function v4Aleatorio(): string {
  const b = new Uint8Array(16)
  if (typeof crypto !== 'undefined' && typeof crypto.getRandomValues === 'function') crypto.getRandomValues(b)
  else for (let i = 0; i < 16; i++) b[i] = Math.floor(Math.random() * 256)
  b[6] = (b[6] & 0x0f) | 0x40
  b[8] = (b[8] & 0x3f) | 0x80
  let h = ''
  for (let i = 0; i < 16; i++) h += (b[i] < 16 ? '0' : '') + b[i].toString(16)
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`
}

export function uuidV4(): string {
  return nativo ? nativo() : v4Aleatorio()
}

if (!nativo && typeof crypto !== 'undefined') {
  try {
    Object.defineProperty(crypto, 'randomUUID', { value: v4Aleatorio, configurable: true, writable: true })
  } catch { /* algunos visores no dejan: uuidV4() igual funciona */ }
}
