// Copiloto Prevención Centinela (MIG734): la pantalla del teléfono con los
// atajos y una respuesta en streaming con fuentes. La IA se simula (sin gasto
// de Anthropic en las pruebas); la ruta real se prueba a mano.
import { test, expect, sinPantallaDeError } from './fixtures'

test.use({ viewport: { width: 360, height: 760 } })

test('copiloto prevención: atajo «¿Puede subir?», respuesta con fuentes y extracto OCR', async ({ page, fake, conSesion, erroresJs }) => {
  fake.comoPerfil({ rol: 'supervisor', app_terreno: '/m/enex', nombre_completo: 'Supervisor ENEX' }, null)
  await conSesion()
  let cuerpo: Record<string, unknown> = {}
  await page.route('**/api/copiloto-sso/consulta', async (route) => {
    cuerpo = route.request().postDataJSON()
    const eventos = [
      { t: 'estado', d: 'Revisando en SICOM a Juan Prueba…' },
      { t: 'texto', d: '⛔ **No puede subir**: el examen de altura física está VENCIDO [F1].' },
      { t: 'fuentes', d: [{ n: 1, chunkId: 7, documento: 'RECSS — Reglamento Especial para Empresas Contratistas', codigo: '02',
        seccion: 'Cap. 8 › Mínimos de salud', escaneado: true, citada: true, extracto: 'Evaluaciones de salud según homologación APRIMIN…' }] },
      { t: 'fin', consultaId: 'c-1', duracion_ms: 1200 },
    ]
    await route.fulfill({ status: 200, headers: { 'content-type': 'application/x-ndjson', 'x-copiloto-id': 'c-1' },
                          body: eventos.map((e) => JSON.stringify(e)).join('\n') + '\n' })
  })
  fake.rpcs.rpc_copiloto_sso_feedback = () => null

  await page.goto('/m/copiloto-sso/')
  await expect(page.getByRole('heading', { name: /Copiloto Prevención/ })).toBeVisible()
  await expect(page.getByRole('button', { name: 'Cerrar sesión' })).toBeInViewport({ ratio: 1 })

  await page.getByRole('button', { name: /¿Puede subir\?/ }).click()
  await page.getByLabel('Pregunta').fill('Juan Prueba')
  await page.getByRole('button', { name: 'Enviar' }).click()

  await expect(page.getByText('No puede subir')).toBeVisible()
  expect(cuerpo).toMatchObject({ pregunta: 'Juan Prueba', atajo: 'subir' })
  await expect(page.getByRole('button', { name: /F1 RECSS/ })).toBeVisible()
  await expect(page.getByText('OCR', { exact: true })).toBeVisible()

  // La cita abre el extracto con el aviso de OCR.
  await page.getByRole('button', { name: /F1 RECSS/ }).click()
  await expect(page.getByRole('dialog', { name: 'Fuente' })).toBeVisible()
  await expect(page.getByText(/verifique las cifras en el PDF original/)).toBeVisible()
  await page.getByRole('dialog', { name: 'Fuente' }).getByRole('button', { name: 'Cerrar' }).click()

  await page.getByRole('button', { name: 'Me sirvió', exact: true }).click()
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(360)
  await sinPantallaDeError(page)
  expect(erroresJs).toEqual([])
})
