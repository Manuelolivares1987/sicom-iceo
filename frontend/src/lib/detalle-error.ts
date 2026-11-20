// [20-11-2026] Texto corto con el error exacto, la versión de la app y del navegador:
// una foto de la pantalla de error del teléfono basta para saber qué falló.

export function detalleError(error: Error & { digest?: string }): string {
  const ua = typeof navigator !== 'undefined' ? navigator.userAgent : ''
  const chrome = /(Chrome|CriOS|SamsungBrowser|Firefox|Version)\/[\d.]+/.exec(ua)?.[0] ?? ua.slice(0, 40)
  const android = /Android [\d.]+/.exec(ua)?.[0] ?? ''
  const pila = (error?.stack ?? '').split(/\r?\n/).slice(1, 3).map((l) => l.trim()).join(' | ')
  return [
    `${error?.name ?? 'Error'}: ${(error?.message ?? String(error)).slice(0, 220)}`,
    error?.digest ? `digest ${error.digest}` : '',
    pila.slice(0, 220),
    `v ${process.env.NEXT_PUBLIC_BUILD_ID ?? '?'} · ${android} ${chrome}`,
    typeof location !== 'undefined' ? location.pathname : '',
  ].filter(Boolean).join(' · ')
}
