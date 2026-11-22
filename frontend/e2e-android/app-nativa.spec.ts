// ============================================================================
// La APP SICOM de verdad (APK Capacitor) en un emulador Android 10
// ----------------------------------------------------------------------------
// Lo que las pruebas del navegador no cubren: el ícono, el WebView nativo, el
// arranque en frío SIN red, el botón atrás de Android y el puente nativo
// (guardar archivos en Descargas). La app de prueba apunta a
// http://localhost:3100 (la web compilada con Supabase simulado en
// http://localhost:54321); el emulador llega a ambos por `adb reverse`.
//
// SICOM_ANDROID=1 → emulador (CI, .github/workflows/app-android-e2e.yml).
// Sin la variable → misma prueba en Chromium (para revisar la parte web en el PC).
// ============================================================================
import { execSync } from 'node:child_process'
import { test, expect, type Page, type BrowserContext } from '@playwright/test'
import { FakeSupabase } from '../e2e/fake-supabase'
import { sembrarFranke } from '../e2e/datos-franke'

const ANDROID = process.env.SICOM_ANDROID === '1'
const PKG = 'cl.pilladoempresas.sicomterreno'
const WEB = 'http://localhost:3100'
const PUERTO_FAKE = 54321
const CLAVE_SESION = 'sb-localhost-auth-token'

test.describe.configure({ mode: 'serial' })
// Con el visor antiguo (Android 10 de fábrica) Playwright no se conecta: va app-ui.spec.ts.
test.skip(process.env.SICOM_ANDROID_MODO === 'ui', 'Visor antiguo: lo cubre app-ui.spec.ts')
test.setTimeout(240_000)

const adb = (cmd: string) => execSync(`adb ${cmd}`, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim()
const esperar = (ms: number) => new Promise((r) => setTimeout(r, ms))

let fake: FakeSupabase
let server: import('node:http').Server

test.beforeAll(async () => {
  fake = new FakeSupabase()
  sembrarFranke(fake)
  // Bitácora: la novedad escrita sin señal (mismo contrato que el servidor real).
  fake.tablas.novedades = []
  fake.rpcs.rpc_faena_comunicacion = (_a, db) => ({ generado_at: new Date().toISOString(), mi_turno: 'A', ciclo: null,
    novedades: db.tablas.novedades.map((n) => ({ ...n, fecha_hora: new Date().toISOString(), autor: 'Otro', acuses: [] })),
    por_leer: [], pendientes: [], equipos: [], resumen: null })
  fake.rpcs.rpc_faena_novedad_crear = (a, db) => {
    const ya = db.tablas.novedades.find((n) => n.client_uuid === a.p_client_uuid)
    if (ya) return ya.id
    db.tablas.novedades.push({ id: `nov-${db.tablas.novedades.length + 1}`, client_uuid: a.p_client_uuid, texto: a.p_texto, categoria: a.p_categoria, severidad: a.p_severidad })
    return 'ok'
  }
  server = await fake.servirHttp(PUERTO_FAKE)
})
test.afterAll(async () => { server?.close() })

// ── Cómo se maneja el «teléfono» en cada modo ───────────────────────────────
type Telefono = {
  abrir: () => Promise<Page>
  cerrarApp: () => Promise<void>
  cortarRed: () => Promise<void>
  volverRed: () => Promise<void>
  atras: () => Promise<void>
  enPrimerPlano: () => Promise<boolean>
  archivoEnDescargas: (nombre: string) => Promise<boolean>
}

async function telefonoAndroid(): Promise<Telefono> {
  const { _android } = await import('playwright')
  const [device] = await _android.devices()
  if (!device) throw new Error('No hay emulador conectado (adb devices)')
  const reverse = () => { adb(`reverse tcp:3100 tcp:3100`); adb(`reverse tcp:${PUERTO_FAKE} tcp:${PUERTO_FAKE}`) }
  reverse()
  return {
    abrir: async () => {
      adb(`shell am start -W -n ${PKG}/.MainActivity`)
      const wv = await device.webView({ pkg: PKG }, { timeout: 60_000 })
      const page = await wv.page()
      await page.waitForURL(/\/(m\/[a-z-]+|login)\/?/, { timeout: 60_000 }).catch(() => undefined)
      return page
    },
    cerrarApp: async () => { adb(`shell am force-stop ${PKG}`); await esperar(1500) },
    // Sin red de verdad: sin wifi ni datos, y sin el puente al servidor de prueba.
    cortarRed: async () => {
      adb('reverse --remove-all')
      adb('shell svc wifi disable'); adb('shell svc data disable')
      fake.sinRed = true
      await esperar(3000)
    },
    volverRed: async () => {
      fake.sinRed = false
      adb('shell svc wifi enable'); adb('shell svc data enable')
      reverse()
      await esperar(5000)
    },
    atras: async () => { adb('shell input keyevent 4'); await esperar(1500) },
    enPrimerPlano: async () => adb('shell dumpsys activity activities').split('\n')
      .some((l) => /mResumedActivity|topResumedActivity/.test(l) && l.includes(PKG)),
    archivoEnDescargas: async (nombre) => adb('shell ls /sdcard/Download/SICOM/ 2>/dev/null || true').includes(nombre),
  }
}

function telefonoNavegador(context: BrowserContext): Telefono {
  let page: Page | null = null
  return {
    // Abrir desde el ícono: si la app ya está abierta, vuelve a la misma.
    abrir: async () => {
      if (page) return page
      page = await context.newPage()
      await page.goto(`${WEB}/m/`)
      await page.waitForURL(/\/(m\/[a-z-]+|login)\/?/, { timeout: 30_000 }).catch(() => undefined)
      return page
    },
    cerrarApp: async () => { await page?.close(); page = null },
    cortarRed: async () => { fake.sinRed = true; await context.setOffline(true) },
    volverRed: async () => { fake.sinRed = false; await context.setOffline(false) },
    atras: async () => { await page?.goBack() },
    enPrimerPlano: async () => true,
    archivoEnDescargas: async () => true, // el puente nativo solo existe en la app
  }
}

async function sinPantallaDeError(page: Page) {
  await expect(page.getByText(/No se pudo cargar esta pantalla|La app no pudo abrir|Algo falló|Application error/i)).toHaveCount(0)
  expect(page.url()).not.toContain('sin-senal.html')
}

test('la app SICOM: arranque en frío SIN red, trabajo sin señal, botón atrás, descargas y subida al volver la red', async () => {
  // En el emulador no se abre ningún navegador: se maneja la app instalada.
  let context: BrowserContext | null = null
  if (!ANDROID) {
    const { chromium, devices } = await import('playwright')
    const b = await chromium.launch()
    context = await b.newContext({ ...devices['Pixel 5'], serviceWorkers: 'allow' })
  }
  const tel = ANDROID ? await telefonoAndroid() : telefonoNavegador(context!)

  await test.step('1. Primera apertura con señal: entra y queda todo guardado', async () => {
    const page = await tel.abrir()
    await page.waitForURL(/\/(login|m)\//, { timeout: 60_000 })
    // Sesión del supervisor de prueba (como si hubiera entrado con su clave).
    await page.evaluate(([k, v]) => localStorage.setItem(k, v), [CLAVE_SESION, JSON.stringify(fake.sesion())] as const)
    await page.goto(`${WEB}/m/`)
    await page.waitForURL(/\/m\/franke\/?$/, { timeout: 60_000 })
    await page.evaluate(async () => { await navigator.serviceWorker.ready })
    await page.reload()
    await expect.poll(() => page.evaluate(() => !!navigator.serviceWorker.controller), { timeout: 30_000 }).toBe(true)
    await expect.poll(() => page.evaluate(async () => !!(await caches.match('/m/franke/bitacora/', { ignoreSearch: true }))), { timeout: 60_000 }).toBe(true)
    // La precarga baja los datos de la faena.
    await expect.poll(() => fake.rpcLlamadas('rpc_faena_comunicacion').length, { timeout: 60_000 }).toBeGreaterThan(0)
    await esperar(2000)
  })

  await test.step('2. Sin red, se cierra la app y se abre de nuevo desde el ícono', async () => {
    await tel.cortarRed()
    await tel.cerrarApp()
    const page = await tel.abrir()
    await page.waitForURL(/\/m\/franke\/?$/, { timeout: 60_000 })
    await expect(page.getByText(/Franke|Turno|Pauta/i).first()).toBeVisible({ timeout: 30_000 })
    await sinPantallaDeError(page)
  })

  await test.step('3. Sin señal: escribir una novedad en la bitácora (queda ⏱)', async () => {
    const page = await tel.abrir()
    await page.goto(`${WEB}/m/franke/bitacora/`)
    await page.getByRole('button', { name: /Escribir novedad del turno/ }).click()
    await page.getByPlaceholder(/Qué pasó/).fill('Prueba en la app nativa sin señal')
    await page.getByRole('button', { name: 'Guardar', exact: true }).click()
    await page.goto(`${WEB}/m/franke/pendientes/`)
    await expect(page.getByText(/1 por subir/)).toBeVisible({ timeout: 30_000 })
    expect(fake.tablas.novedades).toHaveLength(0)
  })

  await test.step('4. Botón atrás de Android: vuelve de pantalla; en el inicio deja la app en segundo plano', async () => {
    const page = await tel.abrir()
    await page.goto(`${WEB}/m/franke/`)
    await page.goto(`${WEB}/m/franke/bodega/`)
    // Que la pantalla termine de abrir antes de apretar atrás.
    await expect(page.getByText(/bodega/i).first()).toBeVisible({ timeout: 30_000 })
    await esperar(1500)
    await tel.atras()
    await expect(page).toHaveURL(/\/m\/franke\/?$/)
    if (ANDROID) {
      // Atrás hasta el inicio: la app NO se cierra (queda en segundo plano).
      for (let i = 0; i < 6 && (await tel.enPrimerPlano()); i++) await tel.atras()
      expect(await tel.enPrimerPlano()).toBe(false)
      expect(adb(`shell pidof ${PKG}`)).not.toBe('')
    }
  })

  await test.step('5. Vuelve la red: la novedad sube sola, una vez', async () => {
    await tel.volverRed()
    const page = await tel.abrir()
    await page.goto(`${WEB}/m/franke/pendientes/`)
    await expect.poll(() => fake.tablas.novedades.length, { timeout: 90_000 }).toBe(1)
    await expect(page.getByText(/Todo subido/)).toBeVisible({ timeout: 30_000 })
  })

  await test.step('6. Puente nativo: un archivo queda en Descargas/SICOM', async () => {
    if (!ANDROID) return
    const page = await tel.abrir()
    const nombre = `prueba-e2e-${Date.now()}.txt`
    await page.evaluate((n) => (window as unknown as { SICOMNativo: { guardarArchivo: (b: string, n: string, m: string) => void } })
      .SICOMNativo.guardarArchivo(btoa('SICOM prueba'), n, 'text/plain'), nombre)
    await expect.poll(() => tel.archivoEnDescargas(nombre), { timeout: 20_000 }).toBe(true)
  })

  await context?.browser()?.close()
})
