import { test as base, expect, type Page } from '@playwright/test'
import { FakeSupabase, STORAGE_KEY } from './fake-supabase'

type Fixtures = {
  fake: FakeSupabase
  /** Deja al supervisor de prueba con sesión guardada en el teléfono. */
  conSesion: (opts?: { vencida?: boolean }) => Promise<void>
  /** Errores de JavaScript de la página: una prueba sana termina sin ninguno. */
  erroresJs: string[]
  /** Modo avión del teléfono: corta la red de la página Y del service worker. */
  modoAvion: (activo: boolean) => Promise<void>
}

export const test = base.extend<Fixtures>({
  fake: async ({ context }, use, testInfo) => {
    const fake = new FakeSupabase()
    await fake.instalar(context)
    await use(fake)
    if (testInfo.status !== testInfo.expectedStatus) {
      console.log('[e2e] lo que llegó al servidor (sin GET):', JSON.stringify(fake.llamadas
        .filter((l) => l.metodo !== 'GET').map((l) => `${l.metodo} ${l.ruta}`)))
    }
    if (fake.sinManejar.size) console.log('[e2e] sin respuesta preparada:', Array.from(fake.sinManejar).join(', '))
  },
  conSesion: async ({ context, fake }, use) => {
    await use(async (opts) => {
      const s = JSON.stringify(fake.sesion(opts))
      // Solo la primera vez: si la app la renueva o la borra, eso manda.
      await context.addInitScript(([k, v]) => {
        try { if (!sessionStorage.getItem('e2e-sembrada')) { localStorage.setItem(k, v); sessionStorage.setItem('e2e-sembrada', '1') } } catch { /* bloqueado */ }
      }, [STORAGE_KEY, s] as const)
    })
  },
  modoAvion: async ({ context, fake }, use) => {
    await use(async (activo) => { fake.sinRed = activo; await context.setOffline(activo) })
  },
  erroresJs: async ({ page }, use) => {
    const errores: string[] = []
    page.on('pageerror', (e) => errores.push(e.message))
    await use(errores)
  },
})
export { expect }

/** Abre la app con señal y espera a que quede lista para funcionar sin señal. */
export async function prepararSinSenal(page: Page) {
  await page.goto('/m/')
  await page.waitForURL(/\/m\/franke\/?$/)
  await page.evaluate(async () => { await navigator.serviceWorker.ready })
  // Con el service worker al mando, las páginas de terreno quedan guardadas.
  await page.reload()
  await expect.poll(() => page.evaluate(() => !!navigator.serviceWorker.controller)).toBe(true)
  await expect.poll(async () => page.evaluate(async () => {
    const r = await caches.match('/m/franke/')
    return !!r
  }), { timeout: 30_000 }).toBe(true)
}

/** Lo que nunca debe ver el trabajador. */
export async function sinPantallaDeError(page: Page) {
  await expect(page.getByText(/La app no pudo abrir|Application error|Algo salió mal|Algo falló/i)).toHaveCount(0)
}

/** En «Pendientes»: aprieta «Subir ahora» cuando se puede, hasta que diga «Todo subido». */
export async function subirHastaTerminar(page: Page, ms = 30_000) {
  await page.goto('/m/franke/pendientes/')
  const fin = Date.now() + ms
  while (Date.now() < fin) {
    if (await page.getByText(/Todo subido/).isVisible().catch(() => false)) return
    const boton = page.getByRole('button', { name: /Subir ahora/ })
    if (await boton.isEnabled({ timeout: 500 }).catch(() => false)) await boton.click({ timeout: 2000 }).catch(() => undefined)
    await page.waitForTimeout(1000)
  }
  await expect(page.getByText(/Todo subido/)).toBeVisible({ timeout: 1000 })
}
