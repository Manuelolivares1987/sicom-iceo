// Scanner de bodega rehecho (22-11-2026): pistola → lista → salida FIFO (CECO,
// OT opcional) o entrada (proveedor + documento); código desconocido → se
// asigna a un producto. Registra con las mismas RPC de la oficina.
import { test, expect } from './fixtures'

const BODEGA = 'b0000000-0000-4000-8000-000000000001'
const FILTRO = { id: 'p0000000-0000-4000-8000-000000000001', codigo: 'REP-0001', codigo_barras: '7801234567890', nombre: 'Filtro de aceite Mack', unidad_medida: 'un', costo_unitario_actual: 12500, categoria: 'repuestos' }
const ACEITE = { id: 'p0000000-0000-4000-8000-000000000002', codigo: 'LUB-0040', codigo_barras: null, nombre: 'Aceite 15W40 balde', unidad_medida: 'un', costo_unitario_actual: 48000, categoria: 'lubricantes' }

test('Scanner: pistola arma la lista, asigna un código nuevo y registra la salida FIFO con CECO', async ({ page, conSesion, fake, erroresJs }) => {
  fake.comoPerfil({ rol: 'bodeguero', nombre_completo: 'Bodeguero Coquimbo' }, null)
  fake.tablas.productos = [{ ...FILTRO }, { ...ACEITE }]
  fake.tablas.bodegas = [{ id: BODEGA, codigo: 'BOD-CQB', nombre: 'Bodega Coquimbo', tipo: 'central', faena_id: 'f1' }]
  fake.tablas.stock_bodega = [
    { bodega_id: BODEGA, producto_id: FILTRO.id, cantidad: 10 },
    { bodega_id: BODEGA, producto_id: ACEITE.id, cantidad: 4 },
  ]
  fake.tablas.centros_costo = [{ id: 'c1', codigo: 'CC-TALLER', nombre: 'Taller Coquimbo', area: null, activo: true }]
  fake.tablas.ordenes_trabajo = []
  fake.tablas.asignaciones = []
  fake.rpcs.rpc_producto_asignar_codigo_barras = (a, db) => {
    const p = db.tablas.productos.find((x) => x.id === a.p_producto_id)!
    p.codigo_barras = a.p_codigo
    db.tablas.asignaciones.push({ ...a })
    return { success: true }
  }
  fake.tablas.salidas = []
  fake.rpcs.rpc_registrar_salida_bodega = (a, db) => { db.tablas.salidas.push({ ...a }); return { success: true, folio: 'SAL-0001' } }

  await conSesion()
  await page.goto('/dashboard/inventario/scanner/')
  await page.getByRole('combobox').first().selectOption(BODEGA)
  const pistola = page.getByLabel('Código')

  // Código conocido, dos veces → una línea con cantidad 2.
  await pistola.fill('7801234567890'); await pistola.press('Enter')
  await expect(page.getByText('Filtro de aceite Mack')).toBeVisible()
  await pistola.fill('7801234567890'); await pistola.press('Enter')
  await expect(page.getByLabel('Cantidad').first()).toHaveValue('2')

  // Código desconocido → se asigna al aceite y entra a la lista.
  await pistola.fill('7809999000011'); await pistola.press('Enter')
  await expect(page.getByText(/7809999000011 no está en el catálogo/)).toBeVisible()
  await page.getByPlaceholder(/Nombre o código interno/).fill('Aceite')
  await page.getByRole('listitem').filter({ hasText: 'Aceite 15W40 balde' }).getByRole('button', { name: /Asignar/ }).click()
  await expect(page.getByText('Aceite 15W40 balde', { exact: true })).toBeVisible()
  expect(fake.tablas.asignaciones).toEqual([{ p_producto_id: ACEITE.id, p_codigo: '7809999000011' }])

  // Salida contra CECO (sin OT).
  await page.locator('select').nth(1).selectOption('c1')
  await page.getByPlaceholder(/Motivo/).fill('Mantención camión AI-20-02')
  await page.getByRole('button', { name: /Registrar salida \(2\)/ }).click()
  await expect(page.getByText(/Salida registrada \(SAL-0001\)/)).toBeVisible()
  expect(fake.tablas.salidas).toHaveLength(1)
  const s = fake.tablas.salidas[0] as { p_tipo_salida: string; p_ceco_id: string; p_ot_id: unknown; p_items: Array<{ producto_id: string; cantidad: number }> }
  expect(s.p_tipo_salida).toBe('ceco')
  expect(s.p_ceco_id).toBe('c1')
  expect(s.p_ot_id).toBeNull()
  expect(s.p_items).toEqual(expect.arrayContaining([
    expect.objectContaining({ producto_id: FILTRO.id, cantidad: 2 }),
    expect.objectContaining({ producto_id: ACEITE.id, cantidad: 1 }),
  ]))
  expect(erroresJs).toEqual([])
})
