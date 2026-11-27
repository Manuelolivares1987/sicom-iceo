// ENEX (supervisor/mantenedor en terreno): un servicio de mantención hecho de
// punta a punta SIN señal — actividad con fotos de antes y después, firma del
// mandante, cierre «cumplida» — y que suba una sola vez al volver la señal.
import { test, expect, prepararSinSenal, sinPantallaDeError } from './fixtures'
import { FOTO } from './datos-franke'
import type { FakeSupabase } from './fake-supabase'
import type { Page } from '@playwright/test'

const PROG = 'c0000000-0000-4000-8000-0000000000e1'
const PAUTA = 'c0000000-0000-4000-8000-0000000000a1'
const ITEM = 'c0000000-0000-4000-8000-0000000000b1'

function servidorEnex(fake: FakeSupabase) {
  const ahora = new Date()
  fake.comoPerfil({ rol: 'supervisor', app_terreno: '/m/enex', nombre_completo: 'Mantenedor ENEX' }, null)
  fake.tablas.v_enex_terreno_pendientes = [{
    programacion_id: PROG, periodo_anio: ahora.getFullYear(), periodo_mes: ahora.getMonth() + 1,
    tipo_servicio: 'mantencion', fecha_programada: null, instalacion_id: 'inst-1', instalacion: 'Estanque LB-01',
    instalacion_tipo: 'estanque', patente: null, linea: null, faena_id: 'f-lb', faena_codigo: 'LB', faena: 'Lomas Bayas',
    pauta_id: PAUTA, pauta_nombre: 'Mantención estanque', pauta_borrador: false, pauta_items: 1,
    ejecucion_id: null, estado: 'pendiente', cumplida: false, es_recobro: false, es_comodin: false, origen: 'plan',
  }]
  fake.tablas.enex_pauta_items = [{
    id: ITEM, pauta_id: PAUTA, bloque: 'Estanque', bloque_orden: 1, orden: 1, codigo: 'E-01',
    descripcion: 'Revisar válvula de despacho', periodicidad: 'mensual', tipo_campo: 'ok_nook', unidad: null,
    valor_referencia: null, tolerancia_min: null, tolerancia_max: null, requiere_foto: false, obligatorio: false,
    critico: false, activo: true,
  }]
  fake.tablas.v_enex_plan_tareas = []
  fake.tablas.v_enex_terreno_instalaciones = []
  fake.tablas.v_enex_pauta_lugar_items = []
  fake.tablas.ejecuciones_enex = []
  fake.rpcs.rpc_enex_ejecutar_pauta = (a, db) => {
    const ya = db.tablas.ejecuciones_enex.find((e) => e.client_uuid === a.p_client_uuid)
    if (!ya) db.tablas.ejecuciones_enex.push({ client_uuid: a.p_client_uuid, items: a.p_items, firma: a.p_firma_mandante_url, firmante: a.p_firmante_mandante })
    return { success: true, ejecucion_id: 'ej-enex-1', estado: 'cumplida' }
  }
  // [MIG735] Estos casos prueban la pauta: el inicio seguro ya tiene visto bueno.
  fake.rpcs.rpc_inicio_seguro_estado = () => INICIO_APROBADO
}

const INICIO_APROBADO = {
  id: 'is-1', client_uuid: 'c0000000-0000-4000-8000-0000000000f1', programacion_id: PROG, tarea: 'Mantención',
  cuadrilla: [], art: {}, psgcc: [], bloqueos: [], sin_bloqueo_motivo: 'Solo inspección visual', estado: 'aprobado',
  solicitado_at: new Date().toISOString(), decidido_at: new Date().toISOString(), decidido_por_nombre: 'Prevencionista Prueba',
  comentario: null, detenido_motivo: null, escalado_at: null, minutos_escalamiento: 10,
}

/** Sin señal la app lee el visto bueno guardado en el teléfono. */
async function inicioAprobadoEnTelefono(page: Page) {
  await page.addInitScript(([prog, v]) => {
    const hoy = new Date().toLocaleDateString('sv-SE', { timeZone: 'America/Santiago' })
    localStorage.setItem(`inicio-seguro-estado:${prog}:${hoy}`, v)
  }, [PROG, JSON.stringify(INICIO_APROBADO)] as const)
}

/** Abre (si hace falta) la actividad y la marca OK. Bloque y actividad pueden venir abiertos. */
async function marcarOk(page: Page) {
  const ok = page.getByRole('button', { name: /^OK$/ })
  const actividad = page.getByText('Revisar válvula de despacho')
  if (!(await actividad.isVisible().catch(() => false))) await page.getByRole('button', { name: /Estanque/ }).first().click()
  if (!(await ok.isVisible().catch(() => false))) await actividad.click()
  await ok.click()
}

async function firmar(page: Page, n: number) {
  const canvas = page.locator('canvas').nth(n)
  await canvas.scrollIntoViewIfNeeded()
  const b = (await canvas.boundingBox())!
  await page.mouse.move(b.x + 20, b.y + 20)
  await page.mouse.down()
  await page.mouse.move(b.x + 120, b.y + 60, { steps: 8 })
  await page.mouse.move(b.x + 200, b.y + 30, { steps: 8 })
  await page.mouse.up()
  await page.getByRole('button', { name: 'Guardar firma' }).nth(n).click()
}

test('ENEX: servicio completo en modo avión (fotos antes/después + firma) y sube una vez', async ({ page, modoAvion, conSesion, fake, erroresJs }) => {
  servidorEnex(fake)
  await inicioAprobadoEnTelefono(page)
  await conSesion()
  await prepararSinSenal(page, '/m/enex/')
  await expect(page.getByText(/disponibles sin internet|listo para trabajar sin señal/)).toBeVisible({ timeout: 30_000 })

  await modoAvion(true)
  await page.goto('/m/enex/')
  await page.getByRole('button', { name: /Agenda del mes/ }).click()
  await page.getByText('Estanque LB-01').first().click()
  await expect(page).toHaveURL(new RegExp(`/m/enex/servicio/\\?id=${PROG}`))
  await marcarOk(page)
  const fotos = page.locator('input[type="file"]')
  await fotos.nth(0).setInputFiles(FOTO)                                       // antes
  await fotos.nth(1).setInputFiles(FOTO)                                       // después
  await expect(page.getByRole('button', { name: /Antes \(1\)/ })).toBeVisible()
  await expect(page.getByRole('button', { name: /Después \(1\)/ })).toBeVisible()

  await firmar(page, 0)                                                        // técnico
  await page.getByPlaceholder('Nombre de quien firma (ESM/ENEX)').fill('Encargado ESM')
  await firmar(page, 0)                                                        // mandante (el del técnico ya es imagen)
  await page.getByRole('button', { name: /Cerrar \(cumplida\)/ }).click()
  await expect(page.getByText(/Guardado en el teléfono/).first()).toBeVisible()
  expect(fake.tablas.ejecuciones_enex).toHaveLength(0)

  await modoAvion(false)
  await expect.poll(() => fake.tablas.ejecuciones_enex.length, { timeout: 40_000 }).toBe(1)
  const e = fake.tablas.ejecuciones_enex[0]
  expect(e.firmante).toBe('Encargado ESM')
  expect(String(e.firma)).toContain('http')
  const it = (e.items as { pauta_item_id: string; resultado: string; fotos_antes?: string[]; fotos_despues?: string[] }[])[0]
  expect(it.resultado).toBe('ok')
  await sinPantallaDeError(page)
  expect(erroresJs).toEqual([])
})

test('ENEX: se pierde la respuesta al cerrar → no se duplica', async ({ page, conSesion, fake }) => {
  test.slow()
  servidorEnex(fake)
  await conSesion()
  await prepararSinSenal(page, '/m/enex/')
  await expect(page.getByText(/disponibles sin internet|listo para trabajar sin señal/)).toBeVisible({ timeout: 30_000 })
  fake.perderRespuesta.add('rpc_enex_ejecutar_pauta')
  await page.goto(`/m/enex/servicio/?id=${PROG}`)
  await marcarOk(page)
  const fotos = page.locator('input[type="file"]')
  await fotos.nth(0).setInputFiles(FOTO)
  await fotos.nth(1).setInputFiles(FOTO)
  await firmar(page, 0)
  await page.getByPlaceholder('Nombre de quien firma (ESM/ENEX)').fill('Encargado ESM')
  await firmar(page, 0)
  await page.getByRole('button', { name: /Cerrar \(cumplida\)/ }).click()
  // El agente de ENEX reintenta solo cada minuto.
  await expect.poll(() => fake.rpcLlamadas('rpc_enex_ejecutar_pauta').length, { timeout: 80_000 }).toBeGreaterThanOrEqual(2)
  expect(fake.tablas.ejecuciones_enex).toHaveLength(1)
  // Las 2 fotos y las 2 firmas subieron una sola vez (el reintento no las repite).
  const subidas = (fake.tablas.__storage ?? []).map((f) => String(f.path))
  expect(subidas.filter((x) => x.includes('/enex/'))).toHaveLength(2)
  expect(subidas.filter((x) => x.includes('enex-firmas/'))).toHaveLength(2)
})
