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
