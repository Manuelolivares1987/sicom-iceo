// App Android «SICOM Terreno» (Capacitor, 20-11-2026). La compila GitHub
// (.github/workflows/app-android.yml) y la publica en una release fija.
export const APK_URL = 'https://github.com/Manuelolivares1987/sicom-iceo/releases/download/sicom-terreno/sicom-terreno.apk'
export const PAGINA_INSTALAR = 'https://pilladoiceo.netlify.app/instalar/'

/** ¿Esta pantalla corre dentro de la app instalada? (la app agrega «SICOMTerreno» al user agent) */
export function enAppTerreno(): boolean {
  return typeof navigator !== 'undefined' && /SICOMTerreno\//.test(navigator.userAgent)
}

export function esAndroid(): boolean {
  return typeof navigator !== 'undefined' && /Android/i.test(navigator.userAgent)
}

// ----------------------------------------------------------------------------
// Última app de terreno usada (/m/franke/, /m/enex/…). El lanzador /m/ abre
// directo ahí, sin red.
// [26-11-2026] Queda ligada a QUIÉN la usó. Antes era del teléfono: el
// supervisor ENEX de Calama entraba en un teléfono que antes usó la cuenta de
// obras civiles y el lanzador lo mandaba a /m/calama/ en vez de a su app.
// ----------------------------------------------------------------------------
export const ULTIMA_APP_KEY = 'sicom-app-terreno'

export function guardarUltimaApp(userId: string, ruta: string): void {
  try { localStorage.setItem(ULTIMA_APP_KEY, JSON.stringify({ id: userId, ruta })) } catch { /* sin storage */ }
}

/**
 * La última app de ESTE usuario, o null. `duenoAnterior` es el dueño del perfil
 * guardado en el teléfono: un valor de antes del cambio (texto plano, sin
 * usuario) solo se acepta si ese perfil es del mismo usuario.
 */
export function leerUltimaApp(userId: string, duenoAnterior?: string | null): string | null {
  try {
    const raw = localStorage.getItem(ULTIMA_APP_KEY)
    if (!raw) return null
    let ruta: string | null = null
    if (raw.startsWith('{')) {
      const v = JSON.parse(raw) as { id?: string; ruta?: string }
      ruta = v.id === userId ? v.ruta ?? null : null
    } else {
      ruta = duenoAnterior === userId ? raw : null
    }
    return ruta && /^\/m\/[a-z0-9-]+\/$/.test(ruta) ? ruta : null
  } catch { return null }
}
