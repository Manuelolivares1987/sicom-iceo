// Cambio de cuenta en el mismo teléfono (26-11-2026).
// El supervisor ENEX de Calama recibió un teléfono que tenía abierta la cuenta
// de obras civiles: el nombre largo dejaba «Cerrar sesión» fuera de la pantalla
// y, al entrar con su cuenta, el lanzador lo mandaba a /m/calama/ (la última
// app usada EN EL TELÉFONO) en vez de a su app, /m/enex/.
import { test, expect, sinPantallaDeError } from './fixtures'
import { USUARIO_ID } from './fake-supabase'

// Ancho de un teléfono chico (moto g24 / Android de gama de entrada).
test.use({ viewport: { width: 360, height: 760 } })

test('la cuenta de obras civiles sale y el supervisor ENEX entra a su app', async ({ page, fake, conSesion, erroresJs }) => {
  fake.comoPerfil({ rol: 'colaborador', nombre_completo: 'Operacion Obras Civiles Calama' }, null)
  fake.tablas.calama_roles_proyecto = [{ usuario_id: USUARIO_ID, rol_calama: 'operador_calama', activo: true }]
  await conSesion()
  page.on('dialog', (d) => d.accept())

  await page.goto('/m/calama/')
  await expect(page.getByText(/Operacion Obras Civiles Calama/)).toBeVisible()
  const salir = page.getByRole('button', { name: 'Cerrar sesión' })
  await expect(salir).toBeInViewport({ ratio: 1 })
  await expect(page.getByRole('button', { name: 'Actualizar' }).first()).toBeInViewport({ ratio: 1 })
  // La página no se ensancha más que el teléfono.
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(360)

  await salir.click()
  await page.waitForURL(/\/login\/?/)

  // Entra el supervisor ENEX con su cuenta.
  fake.comoPerfil({ rol: 'supervisor', app_terreno: '/m/enex', enex_mundo: 'combustible', nombre_completo: 'Supervisor Terreno Calama ENEX' }, null)
  fake.tablas.calama_roles_proyecto = []
  await page.getByPlaceholder('nombre@pillado.cl').fill('supervisor.calama.terreno@e2e.test')
  await page.getByPlaceholder('••••••••').fill('clave-e2e')
  await page.locator('button[type="submit"]').click()

  await page.waitForURL(/\/m\/enex\/?$/)
  await expect(page.getByRole('heading', { name: 'Terreno ENEX' })).toBeVisible()
  await expect(page.getByText('Supervisor Terreno Calama ENEX')).toBeVisible()
  await expect(page.getByRole('button', { name: 'Cerrar sesión' })).toBeInViewport({ ratio: 1 })
  await sinPantallaDeError(page)

  // Desde el ícono (/m/) también abre SU app, no la que usó la cuenta anterior.
  await page.goto('/m/')
  await page.waitForURL(/\/m\/enex\/?$/)
  expect(erroresJs).toEqual([])
})
