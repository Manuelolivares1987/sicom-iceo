// Cambio de versión: llega una versión nueva de la app con cosas sin subir en el
// teléfono. Se aplica sin perder nada y la app sigue abriendo sin señal.
import fs from 'node:fs'
import path from 'node:path'
import { test, expect, prepararSinSenal, sinPantallaDeError } from './fixtures'

// Corre en su propio proyecto, DESPUÉS de las demás (playwright.config.ts):
// cambia el sw.js servido para simular que se publicó una versión nueva.
const SW = path.join(__dirname, '..', 'public', 'sw.js')
// La versión nueva contesta «v2» cuando se le pregunta: así se sabe cuál manda.
const MARCA = ";self.addEventListener('message', (e) => { if (e.data === 'e2e-version') e.source.postMessage('v2') })"
// El sw.js limpio (sin marca, aunque una corrida anterior se haya cortado).
const limpio = () => fs.readFileSync(SW, 'utf8').split(`\n${MARCA}\n`)[0]
let original = ''
test.beforeAll(() => { original = limpio(); fs.writeFileSync(SW, original) })
// afterEach corre aunque la prueba se pase de tiempo (un finally no).
test.afterEach(() => { fs.writeFileSync(SW, original) })

test('versión nueva con pendientes en el teléfono: se actualiza sin perder nada y sigue sin señal', async ({ page, modoAvion, conSesion, fake }) => {
  fake.rpcs.rpc_faena_comunicacion = () => ({ generado_at: new Date().toISOString(), mi_turno: 'A', ciclo: null,
    novedades: [], por_leer: [], pendientes: [], equipos: [], resumen: null })
  await conSesion()
  await prepararSinSenal(page)

  const version = () => page.evaluate(() => new Promise<string>((ok) => {
    const c = navigator.serviceWorker.controller
    if (!c) return ok('sin-sw')
    const t = setTimeout(() => ok('v1'), 1000)
    navigator.serviceWorker.addEventListener('message', (e) => { if (e.data === 'v2') { clearTimeout(t); ok('v2') } }, { once: true })
    c.postMessage('e2e-version')
  }))
  expect(await version()).toBe('v1')

  // Una novedad queda en el teléfono: el servidor está caído.
  fake.caido = true
  await page.goto('/m/franke/bitacora/')
  await page.getByRole('button', { name: /Escribir novedad del turno/ }).click()
  await page.getByPlaceholder(/Qué pasó/).fill('Novedad que no alcanzó a subir')
  await page.getByRole('button', { name: 'Guardar', exact: true }).click()

  fs.writeFileSync(SW, `${original}\n${MARCA}\n`)
  {
    // Abrir la app: si la versión nueva llega al arrancar se aplica sola; si
    // llega después, aparece «Actualizar». Cualquiera de los dos caminos sirve.
    await page.goto('/m/franke/pendientes/')
    await page.evaluate(async () => { await (await navigator.serviceWorker.getRegistration())?.update() }).catch(() => undefined)
    await expect.poll(async () => {
      const boton = page.getByRole('button', { name: 'Actualizar', exact: true })
      const estado = await page.evaluate(async () => {
        const r = await navigator.serviceWorker.getRegistration()
        return { esperando: !!r?.waiting, instalando: !!r?.installing }
      }).catch(() => ({ esperando: false, instalando: true }))
      if (await boton.isVisible().catch(() => false)) await boton.click().catch(() => undefined)
      // Bajada y esperando: el trabajador vuelve a abrir la app y se aplica.
      else if (estado.esperando) await page.reload().catch(() => undefined)
      else if (!estado.instalando) await page.evaluate(async () => { await (await navigator.serviceWorker.getRegistration())?.update() }).catch(() => undefined)
      return version().catch(() => 'recargando')
    }, { timeout: 60_000, intervals: [1500] }).toBe('v2')
    await page.waitForLoadState('load')

    // Lo pendiente sigue en el teléfono.
    await page.goto('/m/franke/pendientes/')
    await expect(page.getByText(/1 por subir/)).toBeVisible()

    // Con la versión nueva, sigue abriendo en modo avión.
    await modoAvion(true)
    await page.goto('/m/')
    await page.waitForURL(/\/m\/franke\/?$/)
    await page.goto('/m/franke/pauta/')
    await sinPantallaDeError(page)

    // Vuelve la señal y el servidor: sube.
    await modoAvion(false)
    fake.caido = false
    await page.goto('/m/franke/pendientes/')
    await expect(page.getByText(/Todo subido/)).toBeVisible({ timeout: 40_000 })
  }
})
