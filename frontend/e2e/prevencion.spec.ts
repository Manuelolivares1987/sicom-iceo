// Prevención — inspección de terreno APR: se PREPARA con señal (baja la plantilla
// y el estado documental de la cuadrilla), se llena SIN señal en el rajo (con
// fotos), sobrevive a cerrar la app, y se ENVÍA al volver la señal, una vez.
import { test, expect, sinPantallaDeError } from './fixtures'
import { FOTO } from './datos-franke'
import type { FakeSupabase } from './fake-supabase'
import type { Page } from '@playwright/test'

const FAENA_CAL = '44444444-4444-4444-8444-444444444444'

function servidorPrevencion(fake: FakeSupabase) {
  fake.comoPerfil({ rol: 'prevencionista', nombre_completo: 'APR de Prueba' }, null)
  fake.tablas.prevencion_inspeccion_faenas = [{ faena_id: FAENA_CAL, grupo_personal: 'CALAMA', activo: true, faenas: { nombre: 'Calama ENEX', codigo: 'CAL' } }]
  fake.tablas.prevencion_inspeccion_plantilla = [
    { codigo: 'T1', etapa_orden: 1, etapa: 'Traslado', orden: 1, pregunta: 'Vehículo con check list del día', ayuda: null, evidencia: 'foto', posterior: false, solo_cruzado: false, activo: true },
    { codigo: 'T2', etapa_orden: 1, etapa: 'Traslado', orden: 2, pregunta: 'Cinturón de seguridad en uso', ayuda: null, evidencia: 'verbal', posterior: false, solo_cruzado: false, activo: true },
  ]
  fake.rpcs.fn_prevencion_habilitacion = () => ({
    generado_at: new Date().toISOString(), grupo: 'CALAMA', requisitos: [],
    personas: [{ personal_id: 'per-1', nombre: 'Juan Pérez', rut: '11.111.111-1', rut_provisorio: false, cargo: 'Mantenedor', requisitos: [], habilitado: true, habilitado_conductor: true }],
  })
  fake.tablas.prevencion_inspecciones = []
  fake.tablas.inspecciones_recibidas = []
  fake.rpcs.fn_prevencion_inspeccion_guardar = (a, db) => {
    const p = a.p as { cliente_uuid: string; trabajo: string; items: { item_codigo: string; respuesta: string | null; evidencias: unknown[] }[] }
    const ya = db.tablas.inspecciones_recibidas.find((x) => x.cliente_uuid === p.cliente_uuid)
    if (ya) Object.assign(ya, { veces: (ya.veces as number) + 1, items: p.items })
    else db.tablas.inspecciones_recibidas.push({ cliente_uuid: p.cliente_uuid, trabajo: p.trabajo, items: p.items, veces: 1 })
    return { id: 'insp-1', estado: 'cerrada', resultado: 'conforme', cumple: 2, no_cumple: 0, no_aplica: 0, pendientes: 0, no_habilitados: 0 }
  }
}

async function prepararInspeccion(page: Page) {
  await page.goto('/m/prevencion/inspeccion/')
  await page.getByRole('button', { name: /Nueva inspección/ }).click()
  await page.getByRole('combobox', { name: 'Faena' }).selectOption(FAENA_CAL)
  await page.getByRole('button', { name: /Preparar inspección/ }).click()
  await page.waitForURL(/\/m\/prevencion\/inspeccion\/editar\/\?id=/)
  await expect(page.getByText(/Datos de la inspección/)).toBeVisible()
}

async function llenarSinSenal(page: Page) {
  await page.getByLabel('Trabajo inspeccionado').fill('Mantención surtidor EDS 3')
  await page.getByRole('button', { name: 'Cuadrilla', exact: true }).click()
  await page.getByRole('button', { name: /Juan Pérez/ }).click()
  await page.getByRole('button', { name: /Traslado/ }).first().click()
  const cumple = page.getByRole('button', { name: 'Cumple', exact: true })
  await cumple.nth(0).click()
  await page.locator('input[type="file"]').first().setInputFiles(FOTO)
  await cumple.nth(1).click()
}

test('Prevención: inspección APR preparada con señal, llenada sin señal (con foto), enviada al volver la señal', async ({ page, context, modoAvion, conSesion, fake, erroresJs }) => {
  servidorPrevencion(fake)
  await conSesion()
  await page.goto('/m/prevencion/')
  await page.evaluate(async () => { await navigator.serviceWorker.ready })
  await page.reload()
  await expect.poll(() => page.evaluate(() => !!navigator.serviceWorker.controller)).toBe(true)
  await expect.poll(() => page.evaluate(async () => !!(await caches.match('/m/prevencion/inspeccion/editar/', { ignoreSearch: true }))), { timeout: 30_000 }).toBe(true)

  await prepararInspeccion(page)
  const url = page.url()
  await modoAvion(true)
  await llenarSinSenal(page)

  // Se cierra la app en el rajo y se vuelve a abrir: todo sigue ahí.
  await page.close()
  const p2 = await context.newPage()
  await p2.goto(url)
  await expect(p2.getByLabel('Trabajo inspeccionado')).toHaveValue('Mantención surtidor EDS 3')
  await p2.getByRole('button', { name: 'Resumen', exact: true }).click()
  await expect(p2.getByText(/1 foto solo en el teléfono/)).toBeVisible()
  const enviar = p2.getByRole('button', { name: /Enviar inspección/ })
  await enviar.click()
  await expect(p2.getByText(/Sin señal\. La inspección queda guardada/)).toBeVisible()
  expect(fake.tablas.inspecciones_recibidas).toHaveLength(0)

  await modoAvion(false)
  await enviar.click()
  await expect(p2.getByText(/Inspección cerrada y enviada/)).toBeVisible({ timeout: 30_000 })
  expect(fake.tablas.inspecciones_recibidas).toHaveLength(1)
  const items = fake.tablas.inspecciones_recibidas[0].items as { item_codigo: string; evidencias: unknown[] }[]
  expect(items.find((i) => i.item_codigo === 'T1')?.evidencias).toHaveLength(1)
  await sinPantallaDeError(p2)
  expect(erroresJs).toEqual([])
})

test('Prevención: se pierde la respuesta al enviar → «Enviar de nuevo» no duplica ni re-sube la foto', async ({ page, conSesion, fake }) => {
  servidorPrevencion(fake)
  await conSesion()
  await page.goto('/m/prevencion/')
  await prepararInspeccion(page)
  await llenarSinSenal(page)
  await page.getByRole('button', { name: 'Resumen', exact: true }).click()
  fake.perderRespuesta.add('fn_prevencion_inspeccion_guardar')
  await page.getByRole('button', { name: /Enviar inspección/ }).click()
  await expect(page.getByText(/Quedó guardada en el teléfono|Failed to fetch|No se pudo enviar/).first()).toBeVisible({ timeout: 30_000 })
  const fotosAntes = (fake.tablas.__storage ?? []).length
  await page.getByRole('button', { name: /Enviar inspección|Enviar de nuevo/ }).click()
  await expect(page.getByText(/Inspección cerrada y enviada/)).toBeVisible({ timeout: 30_000 })
  expect(fake.tablas.inspecciones_recibidas).toHaveLength(1)
  expect(fake.tablas.inspecciones_recibidas[0].veces).toBe(2)
  expect((fake.tablas.__storage ?? []).length).toBe(fotosAntes)
})
