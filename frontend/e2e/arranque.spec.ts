// Arranque: la app abre sin señal, con sesión vencida y con Chrome bloqueando datos.
import { test, expect, prepararSinSenal, sinPantallaDeError } from './fixtures'

const PANTALLAS = [
  { ruta: '/m/franke/', texto: /Franke|Turno|Pauta/i },
  { ruta: '/m/franke/pauta/', texto: /pauta|equipo/i },
  { ruta: '/m/franke/despacho/', texto: /despacho|combustible/i },
  { ruta: '/m/franke/bodega/', texto: /bodega/i },
  { ruta: '/m/franke/bitacora/', texto: /bitácora|novedad/i },
  { ruta: '/m/franke/entrega/', texto: /entrega/i },
  { ruta: '/m/franke/carga/', texto: /carga/i },
  { ruta: '/m/franke/turno/', texto: /turno/i },
  { ruta: '/m/franke/pendientes/', texto: /Pendientes/i },
]

test.describe('arranque sin señal', () => {
  test('la primera vez con señal lleva a Franke y deja todo guardado', async ({ page, conSesion, erroresJs }) => {
    await conSesion()
    await prepararSinSenal(page)
    await sinPantallaDeError(page)
    expect(erroresJs).toEqual([])
  })

  test('en modo avión abre desde el ícono (/m/) y todas las pantallas de Franke', async ({ page, context, conSesion, erroresJs }) => {
    await conSesion()
    await prepararSinSenal(page)
    await context.setOffline(true)
    await page.goto('/m/')
    await page.waitForURL(/\/m\/franke\/?$/)
    for (const p of PANTALLAS) {
      await test.step(p.ruta, async () => {
        await page.goto(p.ruta)
        await expect(page.getByText(p.texto).first()).toBeVisible()
        await sinPantallaDeError(page)
        await expect(page.getByText(/Sin conexión a internet|Sin conexión$/)).toHaveCount(0)
      })
    }
    expect(erroresJs).toEqual([])
  })

  test('con la sesión vencida y sin señal igual abre (no pide clave)', async ({ page, context, conSesion, fake }) => {
    await conSesion()
    await prepararSinSenal(page)
    // Pasa la noche: el token vence y no hay señal para renovarlo.
    await page.evaluate((k) => {
      const s = JSON.parse(localStorage.getItem(k) ?? '{}')
      s.expires_at = Math.floor(Date.now() / 1000) - 3600
      localStorage.setItem(k, JSON.stringify(s))
    }, 'sb-supabase-auth-token')
    fake.refrescoFalla = true
    await context.setOffline(true)
    await page.goto('/m/')
    await page.waitForURL(/\/m\/franke\/?$/)
    await expect(page.getByRole('heading').or(page.getByText(/Franke/)).first()).toBeVisible()
    await expect(page).not.toHaveURL(/login/)
    await sinPantallaDeError(page)
  })
})

test('Chrome con datos del sitio bloqueados: explica qué hacer en vez de caerse', async ({ page, context }) => {
  await context.addInitScript(() => {
    const err = () => { throw new DOMException("Failed to read the 'localStorage' property from 'Window': Access is denied for this document.", 'SecurityError') }
    Object.defineProperty(window, 'localStorage', { get: err, configurable: true })
  })
  await page.goto('/m/')
  await expect(page.getByText(/datos del sitio|Instale la app|bloquead/i).first()).toBeVisible()
  await expect(page.getByText(/La app no pudo abrir/)).toHaveCount(0)
})

test('/instalar/ ofrece la app y /reparar/ limpia y lleva a entrar', async ({ page }) => {
  await page.goto('/instalar/')
  await expect(page.getByRole('link', { name: /Descargar|Instalar/i }).first()).toBeVisible()
  // En Netlify /reparar/ sirve el index.html; next start no sirve índices de public/.
  await page.goto('/reparar/index.html')
  await page.waitForURL(/\/login\//, { timeout: 30_000 })
})
