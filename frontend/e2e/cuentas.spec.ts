// Administración → Cuentas y «Crear mi clave» (22-11-2026). El servidor de las
// cuentas (/api/admin/cuentas, service role) se simula en el navegador: aquí se
// prueba que la pantalla mande exactamente lo elegido y muestre el enlace.
import { test, expect } from './fixtures'

const ROMERAL = { id: '33333333-3333-4333-8333-333333333333', codigo: 'FAE-CMP-ROMERAL', nombre: 'CMP — Romeral', app_movil: '/m/romeral', panel_web: null }

test('Cuentas: el administrador crea una cuenta con su faena, app y un permiso extra, y obtiene el enlace', async ({ page, conSesion, fake, erroresJs }) => {
  fake.comoPerfil({ rol: 'administrador', nombre_completo: 'Admin Pillado' }, null)
  fake.tablas.faenas.push({ ...ROMERAL, activo: true })
  const enviados: Array<Record<string, unknown>> = []
  await page.route('**/api/admin/cuentas', async (route) => {
    if (route.request().method() === 'GET') {
      return route.fulfill({ json: { correo_configurado: true, cuentas: [
        { id: 'u-1', email: 'luis@pillado.cl', nombre_completo: 'Luis Vera', rol: 'operador_combustible', cargo: null, faena_id: ROMERAL.id,
          faena_nombre: ROMERAL.nombre, activo: true, solo_su_faena: false, app_terreno: null, ultimo_ingreso: null, acceso_vence: null,
          permisos_extra: {}, rol_calama: null },
      ] } })
    }
    enviados.push(route.request().postDataJSON())
    return route.fulfill({ json: { ok: true, user_id: 'u-2', enlace: 'https://sicom.test/crear-clave/?u=u-2&t=abc', enviado: true } })
  })
  await conSesion()
  await page.goto('/dashboard/admin/cuentas/')
  await expect(page.getByText('Luis Vera')).toBeVisible()
  await expect(page.getByRole('cell').getByText('Nunca entró')).toBeVisible()

  await page.getByRole('button', { name: /Nueva cuenta/ }).click()
  await page.getByLabel('Nombre completo').fill('Erick Guerrero')
  await page.getByLabel('Correo (su usuario)').fill('erick@pillado.cl')
  await page.getByLabel('Rol de la cuenta').selectOption('operador_combustible')
  await page.getByLabel('Faena de la cuenta').selectOption(ROMERAL.id)
  await page.getByLabel('App al entrar en el teléfono').selectOption('/m/romeral')
  await page.getByLabel('Ve solo lo de su faena').check()
  await page.getByLabel('Flota: Ver').check()
  await page.getByRole('button', { name: 'Crear cuenta' }).click()

  await expect(page.getByText(/Se envió el correo con el enlace/)).toBeVisible()
  await expect(page.getByLabel('Enlace de acceso')).toHaveValue('https://sicom.test/crear-clave/?u=u-2&t=abc')
  expect(enviados).toHaveLength(1)
  expect(enviados[0]).toMatchObject({
    accion: 'crear', email: 'erick@pillado.cl', nombre_completo: 'Erick Guerrero', rol: 'operador_combustible',
    faena_id: ROMERAL.id, app_terreno: '/m/romeral', solo_su_faena: true, enviar_correo: true,
    permisos_extra: { flota: ['view'] },
  })
  expect(erroresJs).toEqual([])
})

test('Crear mi clave: valida, guarda y muestra cómo entrar; enlace vencido lo explica', async ({ page }) => {
  let respuesta: { status: number; json: Record<string, unknown> } = { status: 200, json: { ok: true, email: 'erick@pillado.cl' } }
  const recibido: Array<Record<string, unknown>> = []
  await page.route('**/api/cuentas/crear-clave', async (route) => {
    recibido.push(route.request().postDataJSON())
    await route.fulfill({ status: respuesta.status, json: respuesta.json })
  })
  await page.goto('/crear-clave/?u=11111111-1111-4111-8111-111111111111&t=tok123')
  const guardar = page.getByRole('button', { name: 'Guardar mi clave' })
  await page.getByLabel('Nueva clave').fill('corta')
  await expect(page.getByText('Mínimo 8 caracteres.')).toBeVisible()
  await page.getByLabel('Nueva clave').fill('clave-segura-1')
  await page.getByLabel('Repite la clave').fill('clave-segura-2')
  await expect(page.getByText('Las dos claves no coinciden.')).toBeVisible()
  await expect(guardar).toBeDisabled()
  await page.getByLabel('Repite la clave').fill('clave-segura-1')
  await guardar.click()
  await expect(page.getByText(/Listo, tu clave quedó guardada/)).toBeVisible()
  await expect(page.getByRole('link', { name: /descargar la app SICOM/i })).toHaveAttribute('href', /sicom-terreno\.apk$/)
  expect(recibido[0]).toEqual({ u: '11111111-1111-4111-8111-111111111111', t: 'tok123', clave: 'clave-segura-1' })

  respuesta = { status: 410, json: { error: 'El enlace venció. Pide a la oficina que te lo reenvíe.' } }
  await page.goto('/crear-clave/?u=11111111-1111-4111-8111-111111111111&t=viejo')
  await page.getByLabel('Nueva clave').fill('clave-segura-1')
  await page.getByLabel('Repite la clave').fill('clave-segura-1')
  await page.getByRole('button', { name: 'Guardar mi clave' }).click()
  await expect(page.getByRole('alert').filter({ hasText: /venció/ })).toBeVisible()
})
