// Los trabajos de faena de punta a punta SIN señal: carga del camión, despacho,
// bodega y pauta del mecánico con foto. Se hace en modo avión, se recupera la
// señal y se revisa qué llegó al servidor (una sola vez, con su foto).
import { test, expect, prepararSinSenal, sinPantallaDeError, subirHastaTerminar } from './fixtures'
import { sembrarFranke, fotosEn, FOTO, CAMION_1, PAUTA_1, ACTIVO_1 } from './datos-franke'

test.beforeEach(async ({ fake, conSesion }) => {
  sembrarFranke(fake)
  await conSesion()
})

test('carga del camión en modo avión, con foto del ticket: sube sola y una vez', async ({ page, modoAvion, context, fake, erroresJs }) => {
  await prepararSinSenal(page)
  await modoAvion(true)
  await page.goto('/m/franke/carga/')
  await page.locator('select').first().selectOption(CAMION_1)
  await page.getByPlaceholder('794').fill('8812')
  await page.locator('input[placeholder="0"]').first().fill('3500')
  await page.locator('input[type="file"]').first().setInputFiles(FOTO)
  await page.getByRole('button', { name: /Registrar carga/ }).click()
  await expect(page.getByText(/Guardada en el teléfono/).first()).toBeVisible()
  expect(fake.tablas.recepciones).toHaveLength(0)

  await modoAvion(false)
  await expect.poll(() => fake.tablas.recepciones.length, { timeout: 30_000 }).toBe(1)
  const r = fake.tablas.recepciones[0]
  expect(r.guia).toBe('8812')
  expect(r.litros).toBe(3500)
  expect(String(r.foto)).toContain('evidencias-verificacion')
  expect(fotosEn(fake, 'romeral-cierre')).toHaveLength(1)
  await sinPantallaDeError(page)
  expect(erroresJs).toEqual([])
})

test('carga del camión: se pierde la respuesta → no se duplica ni se vuelve a subir la foto', async ({ page, modoAvion, fake }) => {
  await prepararSinSenal(page)
  fake.perderRespuesta.add('rpc_comb_faena_recepcion')
  await page.goto('/m/franke/carga/')
  await page.locator('select').first().selectOption(CAMION_1)
  await page.getByPlaceholder('794').fill('8813')
  await page.locator('input[placeholder="0"]').first().fill('1200')
  await page.locator('input[type="file"]').first().setInputFiles(FOTO)
  await page.getByRole('button', { name: /Registrar carga/ }).click()
  // Quedó en el teléfono (el teléfono no supo que llegó) y se reintenta sola.
  await expect(page.getByText(/Guardada en el teléfono/).first()).toBeVisible()
  await subirHastaTerminar(page)
  expect(fake.tablas.recepciones).toHaveLength(1)
  expect(fake.rpcLlamadas('rpc_comb_faena_recepcion').length).toBeGreaterThanOrEqual(2)
})

test('despacho de combustible en modo avión con foto del medidor', async ({ page, modoAvion, context, fake, erroresJs }) => {
  await prepararSinSenal(page)
  await modoAvion(true)
  await page.goto('/m/franke/despacho/')
  await page.getByText(/Falta decir turno, camión y quién carga/).click()
  await page.getByRole('button', { name: 'Día', exact: true }).click()
  await page.locator('select').first().selectOption(CAMION_1)
  await page.getByPlaceholder('¿Quién carga?').fill('Operador Prueba')
  await page.getByRole('button', { name: /Nueva carga/ }).click()
  await page.getByPlaceholder('21707').fill('4401')
  await page.getByPlaceholder(/Buscar por código/).fill('CAEX')
  await page.getByRole('button', { name: /CAEX-101/ }).click()
  await page.locator('input[inputmode="decimal"]').nth(0).fill('1000')
  await page.locator('input[inputmode="decimal"]').nth(1).fill('1250')
  await page.locator('input[type="file"]').last().setInputFiles(FOTO)
  await page.getByRole('button', { name: /Guardar carga/ }).click()
  await expect(page.getByText(/esperando señal|guardad/i).first()).toBeVisible()
  expect(fake.tablas.despachos).toHaveLength(0)

  await modoAvion(false)
  await expect.poll(() => fake.tablas.despachos.length, { timeout: 30_000 }).toBe(1)
  expect(fake.tablas.despachos[0].litros).toBe(250)
  expect(fake.tablas.despachos[0].folio).toBe(4401)
  expect(String(fake.tablas.despachos[0].foto)).toContain('evidencias-verificacion')
  expect(fotosEn(fake, 'romeral')).toHaveLength(1)
  await sinPantallaDeError(page)
  expect(erroresJs).toEqual([])
})

test('bodega: sacar un filtro con el lector en modo avión, sube una vez', async ({ page, modoAvion, context, fake, erroresJs }) => {
  await prepararSinSenal(page)
  await expect.poll(() => fake.rpcLlamadas('rpc_bodega_faena_catalogo').length, { timeout: 30_000 }).toBeGreaterThan(0)
  await modoAvion(true)
  await page.goto('/m/franke/bodega/')
  const lector = page.getByPlaceholder(/Dispare el lector/)
  await lector.fill('7800000000017')
  await lector.press('Enter')
  await expect(page.getByText('FILTRO ACEITE MACK')).toBeVisible()
  await page.locator('select').first().selectOption(ACTIVO_1)
  await page.getByPlaceholder('Entregado a (nombre)').fill('Mecánico Prueba')
  await page.getByRole('button', { name: /Sacar 1 producto/ }).click()
  await expect(page.getByText(/Guardado en el teléfono/)).toBeVisible()

  await modoAvion(false)
  await expect.poll(() => fake.tablas.salidas.length, { timeout: 30_000 }).toBe(1)
  expect(fake.tablas.salidas[0].activo).toBe(ACTIVO_1)
  await sinPantallaDeError(page)
  expect(erroresJs).toEqual([])
})

test('pauta del mecánico en modo avión: NO OK con foto, se cierra y sube con la foto', async ({ page, modoAvion, context, fake, erroresJs }) => {
  await prepararSinSenal(page)
  // La precarga baja la jornada y los ítems de cada pauta.
  await expect.poll(() => fake.llamadas.filter((l) => l.ruta === 'faena_pauta_item').length, { timeout: 30_000 }).toBeGreaterThan(0)
  await page.waitForTimeout(500)
  await modoAvion(true)
  await page.goto(`/m/franke/pauta/revisar/?p=${PAUTA_1}&a=${ACTIVO_1}`)
  await expect(page.getByText('Nivel de aceite')).toBeVisible()

  // Sin foto, el hallazgo no deja cerrar.
  await page.getByRole('button', { name: /NO OK/ }).nth(0).click()
  await page.getByRole('button', { name: /^OK$/ }).nth(1).click()
  await page.getByRole('button', { name: /Cerrar pauta/ }).click()
  await expect(page.getByText(/necesitan foto/)).toBeVisible()

  await page.locator('input[type="file"]').first().setInputFiles(FOTO)
  await page.getByPlaceholder(/Qué tiene/).fill('Bajo el mínimo')
  await page.getByRole('button', { name: /Cerrar pauta/ }).click()
  await expect(page.getByText(/teléfono|señal/i).first()).toBeVisible()
  expect(fake.tablas.ejecuciones).toHaveLength(0)

  await modoAvion(false)
  await expect.poll(() => fake.tablas.ejecuciones[0]?.estado, { timeout: 30_000 }).toBe('cerrada')
  const items = fake.tablas.ejecuciones[0].items as { resultado: string; foto_url: string | null }[]
  expect(items.find((i) => i.resultado === 'nok')?.foto_url).toContain('pauta-faena/')
  expect(fotosEn(fake, 'pauta-faena')).toHaveLength(1)
  await sinPantallaDeError(page)
  expect(erroresJs).toEqual([])
})
