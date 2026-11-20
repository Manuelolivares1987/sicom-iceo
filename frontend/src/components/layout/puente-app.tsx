'use client'

// ============================================================================
// Puente con la app Android «SICOM» (20-11-2026)
// ----------------------------------------------------------------------------
// Dentro de la app (WebView) los botones de descarga, «Imprimir / PDF» y los
// links a otra pestaña no hacen nada por sí solos. En vez de tocar las ~150
// pantallas que los usan, acá se interceptan una sola vez y se le pasan al
// teléfono (window.SICOMNativo, MainActivity.java):
//   · descarga (blob:, data:, a[download], archivos de Storage) → Descargas/SICOM y se abre
//   · window.print() → imprimir / guardar como PDF de Android
//   · link externo (otro dominio, WhatsApp, Maps, tel:) → su app
//   · link a otra pestaña de SICOM → misma ventana
// Fuera de la app no hace nada.
// ============================================================================

import { useEffect } from 'react'

type Nativo = {
  guardarArchivo: (base64: string, nombre: string, mime: string) => void
  imprimir: (titulo: string) => void
  abrirExterno: (url: string) => void
}

const EXT_ARCHIVO = /\.(pdf|xlsx?|csv|zip|docx?|pptx?|txt|png|jpe?g|webp|heic)(\?|#|$)/i

function nativo(): Nativo | null {
  const n = (window as unknown as { SICOMNativo?: Nativo }).SICOMNativo
  return n && typeof n.guardarArchivo === 'function' ? n : null
}

function nombreDe(url: string, sugerido?: string | null): string {
  if (sugerido) return sugerido
  try {
    const u = new URL(url, location.href)
    const ultimo = decodeURIComponent(u.pathname.split('/').filter(Boolean).pop() || '')
    if (ultimo && ultimo.includes('.')) return ultimo
  } catch { /* blob: sin nombre */ }
  return `SICOM-${new Date().toISOString().slice(0, 19).replace(/[T:]/g, '-')}`
}

function extensionPara(mime: string): string {
  if (mime.includes('pdf')) return '.pdf'
  if (mime.includes('spreadsheet') || mime.includes('excel')) return '.xlsx'
  if (mime.includes('zip')) return '.zip'
  if (mime.includes('csv')) return '.csv'
  if (mime.includes('word')) return '.docx'
  if (mime.startsWith('image/')) return `.${mime.split('/')[1].replace('jpeg', 'jpg')}`
  return ''
}

async function guardar(n: Nativo, href: string, sugerido?: string | null) {
  try {
    const r = await fetch(href)
    const blob = await r.blob()
    const mime = blob.type || 'application/octet-stream'
    let nombre = nombreDe(href, sugerido)
    if (!/\.[a-z0-9]{2,5}$/i.test(nombre)) nombre += extensionPara(mime)
    const base64 = await new Promise<string>((ok, mal) => {
      const fr = new FileReader()
      fr.onload = () => ok(String(fr.result).split(',')[1] ?? '')
      fr.onerror = () => mal(fr.error)
      fr.readAsDataURL(blob)
    })
    n.guardarArchivo(base64, nombre, mime)
  } catch {
    // Último recurso: que lo abra el navegador del teléfono.
    if (/^https?:/i.test(href)) n.abrirExterno(href)
  }
}

const esArchivo = (url: URL) => EXT_ARCHIVO.test(url.pathname) || url.pathname.includes('/storage/v1/object/')

export function PuenteApp() {
  useEffect(() => {
    const n = nativo()
    if (!n) return

    // Imprimir / PDF
    const printOriginal = window.print
    window.print = () => n.imprimir(document.title || 'SICOM')

    // Decide qué hacer con un link; true = lo manejó el puente.
    const manejar = (href: string, download: string | null, target: string | null): boolean => {
      if (!href) return false
      if (/^(blob|data):/i.test(href) || download !== null) { void guardar(n, href, download || null); return true }
      let url: URL
      try { url = new URL(href, location.href) } catch { return false }
      if (!/^https?:$/.test(url.protocol)) { n.abrirExterno(url.href); return true } // tel:, mailto:, whatsapp:, intent:
      if (url.host !== location.host) {
        if (esArchivo(url)) { void guardar(n, url.href); return true }
        n.abrirExterno(url.href); return true
      }
      if (esArchivo(url)) { void guardar(n, url.href); return true }
      if (target === '_blank') { location.assign(url.href); return true }
      return false
    }

    // Links que están en la pantalla
    const alClic = (ev: MouseEvent) => {
      if (ev.defaultPrevented || ev.button !== 0) return
      const a = (ev.target as Element | null)?.closest?.('a[href]') as HTMLAnchorElement | null
      if (!a) return
      if (manejar(a.getAttribute('href') || '', a.hasAttribute('download') ? a.getAttribute('download') : null, a.getAttribute('target'))) {
        ev.preventDefault()
        ev.stopPropagation()
      }
    }
    document.addEventListener('click', alClic, true)

    // Descargas armadas por código (a = createElement('a'); a.download = …; a.click())
    const clickOriginal = HTMLAnchorElement.prototype.click
    HTMLAnchorElement.prototype.click = function (this: HTMLAnchorElement) {
      if (manejar(this.href, this.hasAttribute('download') ? this.getAttribute('download') : null, this.getAttribute('target'))) return
      return clickOriginal.call(this)
    }

    // window.open(url): archivos, otras pestañas y sitios externos
    const openOriginal = window.open
    window.open = ((url?: string | URL) => {
      const href = url ? String(url) : ''
      if (href && manejar(href, null, '_blank')) return null
      return openOriginal.call(window, url as string)
    }) as typeof window.open

    return () => {
      window.print = printOriginal
      HTMLAnchorElement.prototype.click = clickOriginal
      window.open = openOriginal
      document.removeEventListener('click', alClic, true)
    }
  }, [])

  return null
}
