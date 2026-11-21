// Lo escrito sin señal sube solo, una sola vez, aunque la señal se corte a mitad.
import { test, expect, prepararSinSenal, sinPantallaDeError, subirHastaTerminar } from './fixtures'
import type { FakeSupabase } from './fake-supabase'

/** Imita rpc_faena_novedad_crear: el mismo p_client_uuid no crea otra novedad. */
function servidorBitacora(fake: FakeSupabase) {
  fake.tablas.novedades = []
  fake.rpcs.rpc_faena_comunicacion = (_a, db) => ({ generado_at: new Date().toISOString(), mi_turno: 'A', ciclo: null,
    novedades: db.tablas.novedades.map((n) => ({ ...n, fecha_hora: new Date().toISOString(), autor: 'Otro', acuses: [] })),
    por_leer: [], pendientes: [], equipos: [], resumen: null })
  fake.rpcs.rpc_faena_novedad_crear = (a, db) => {
    const ya = db.tablas.novedades.find((n) => n.client_uuid === a.p_client_uuid)
    if (ya) return ya.id
    const id = `nov-${db.tablas.novedades.length + 1}`
    db.tablas.novedades.push({ id, client_uuid: a.p_client_uuid, texto: a.p_texto, categoria: a.p_categoria, severidad: a.p_severidad })
    return id
  }
}

async function escribirNovedad(page: import('@playwright/test').Page, texto: string) {
  await page.goto('/m/franke/bitacora/')
  await page.getByRole('button', { name: /Escribir novedad del turno/ }).click()
  await page.getByPlaceholder(/Qué pasó/).fill(texto)
  await page.getByRole('button', { name: 'Guardar', exact: true }).click()
}

test('novedad escrita en modo avión: queda ⏱ en el teléfono y sube sola al volver la señal', async ({ page, modoAvion, context, conSesion, fake, erroresJs }) => {
  servidorBitacora(fake)
  await conSesion()
  await prepararSinSenal(page)
  await modoAvion(true)
  await escribirNovedad(page, 'HHWB-44 pierde aceite por el retén trasero')
  await page.goto('/m/franke/pendientes/')
  await expect(page.getByText(/1 por subir/)).toBeVisible()
  expect(fake.rpcLlamadas('rpc_faena_novedad_crear')).toHaveLength(0)

  await modoAvion(false)
  await expect.poll(() => fake.tablas.novedades.length, { timeout: 30_000 }).toBe(1)
  await expect(page.getByText(/Todo subido/)).toBeVisible({ timeout: 30_000 })
  await sinPantallaDeError(page)
  expect(erroresJs).toEqual([])
})

test('se pierde la respuesta del servidor: reintenta y NO duplica ni queda «rechazado»', async ({ page, modoAvion, conSesion, fake }) => {
  servidorBitacora(fake)
  await conSesion()
  await prepararSinSenal(page)
  fake.perderRespuesta.add('rpc_faena_novedad_crear')
  await escribirNovedad(page, 'Camión 3 con neumático bajo')
  // El servidor la guardó, pero el teléfono no se enteró: sigue pendiente.
  await expect.poll(() => fake.tablas.novedades.length).toBe(1)
  await subirHastaTerminar(page)
  expect(fake.tablas.novedades).toHaveLength(1)
  expect(fake.rpcLlamadas('rpc_faena_novedad_crear').length).toBeGreaterThanOrEqual(2)
  await expect(page.getByText(/no aceptado|No se aceptó/)).toHaveCount(0)
})

test('servidor caído (503): espera y reintenta, no marca rechazado', async ({ page, modoAvion, conSesion, fake }) => {
  servidorBitacora(fake)
  await conSesion()
  await prepararSinSenal(page)
  fake.caido = true
  await escribirNovedad(page, 'Corte de energía en el patio')
  await page.goto('/m/franke/pendientes/')
  await expect(page.getByText(/1 por subir/)).toBeVisible()
  await expect(page.getByText(/no aceptado|No se aceptó/)).toHaveCount(0)
  fake.caido = false
  await subirHastaTerminar(page)
  expect(fake.tablas.novedades).toHaveLength(1)
})
