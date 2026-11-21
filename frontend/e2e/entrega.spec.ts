// [F4] Entrega de turno: se puede abrir una entrega nueva SIN señal con los
// datos que el teléfono bajó con señal (plantilla), y nunca otra semana.
import { test, expect, prepararSinSenal, sinPantallaDeError } from './fixtures'
import type { FakeSupabase } from './fake-supabase'

function servidorEntrega(fake: FakeSupabase) {
  fake.rpcs.rpc_faena_entrega_plantilla = () => ({
    resumen: { litros: { venta: 12500, trasvasije: 0, recirculacion: 0, calibracion: 0, total: 12500, cargas: 9 },
      litros_por_dia: [], pauta: { ejecuciones: 4, hallazgos: 1 }, pendientes: { abiertos: 1, atascados: 0 } },
    equipos: [
      { activo_id: 'a1', patente: 'HHWB-44', equipo: 'Mack Granite', estado: 'operativo', horometro: 5200, desviaciones: 0 },
      { activo_id: 'a2', patente: 'KXTR-19', equipo: 'Volvo FMX', estado: 'en_mantencion', horometro: 8100, desviaciones: 1 },
    ],
    pendientes: [],
    contexto: { camiones: [{ estanque_id: 'e1', patente: 'CC-11', nombre: 'Camión 1', capacidad: 10000, teorico: 3200, estimable: true,
      fisico: null, metodo: null, nota: null }], terceros_hubo: null, terceros: [], ventas_registradas: [], despachos_sin_equipo: [],
      seguridad_sin_novedad: null, seguridad_detalle: null, novedades_seguridad: [], verbal_modo: null },
  })
}

test('abre una entrega NUEVA en modo avión con lo bajado con señal', async ({ page, context, conSesion, fake, erroresJs }) => {
  servidorEntrega(fake)
  await conSesion()
  await prepararSinSenal(page)
  // La precarga baja la plantilla del periodo sugerido.
  await expect.poll(() => fake.rpcLlamadas('rpc_faena_entrega_plantilla').length, { timeout: 30_000 }).toBeGreaterThan(0)
  await page.waitForTimeout(500) // que termine de guardarse en el teléfono

  await context.setOffline(true)
  await page.goto('/m/franke/entrega/')
  await page.getByRole('button', { name: /Abrir la entrega/ }).click()
  await expect(page.getByText(/se armó en el teléfono/)).toBeVisible()
  await expect(page.getByText('HHWB-44').first()).toBeVisible()
  await expect(page.getByText('KXTR-19').first()).toBeVisible()
  await sinPantallaDeError(page)
  // Sin señal no se creó nada en el servidor.
  expect(fake.rpcLlamadas('rpc_faena_entrega_abrir')).toHaveLength(0)
  expect(erroresJs).toEqual([])
})

test('sin datos de ese periodo y sin señal: lo dice claro (no muestra otra semana)', async ({ page, context, conSesion, fake }) => {
  servidorEntrega(fake)
  await conSesion()
  await prepararSinSenal(page)
  await context.setOffline(true)
  await page.goto('/m/franke/entrega/')
  // Un periodo de hace un año: el teléfono no lo tiene.
  const fechas = page.locator('input[type="date"]')
  await fechas.nth(0).fill('2025-01-01')
  await fechas.nth(1).fill('2025-01-08')
  await page.getByRole('button', { name: /Abrir la entrega/ }).click()
  await expect(page.getByText(/no tiene los datos de ese periodo/)).toBeVisible()
  await sinPantallaDeError(page)
})
