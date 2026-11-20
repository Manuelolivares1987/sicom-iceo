// [20-11-2026] ¿Este navegador deja que SICOM guarde datos en el teléfono?
// En Franke un Chrome tenía bloqueados «Datos del sitio en el dispositivo» para
// la página: con solo LEER `localStorage` lanza SecurityError y la app no abría.
// Sin almacenamiento no hay sesión que se mantenga ni trabajo sin señal: hay que
// decirlo claro y explicar cómo habilitarlo.
export function almacenamientoBloqueado(): boolean {
  if (typeof window === 'undefined') return false
  try {
    const s = window.localStorage
    s.setItem('__sicom_prueba', '1')
    s.removeItem('__sicom_prueba')
    return false
  } catch {
    return true
  }
}

export const esErrorDeAlmacenamiento = (e: unknown): boolean =>
  /localStorage|sessionStorage|indexedDB|Access is denied for this document/i.test(
    `${(e as { name?: string })?.name ?? ''} ${(e as { message?: string })?.message ?? String(e ?? '')}`)
