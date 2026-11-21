// Calama (operador OOCC): «Descargar jornadas» con señal, y en el rajo SIN
// señal abrir su OT y registrar la llegada a faena con foto y GPS. Al volver la
// señal sube una vez (foto + registro).
import { test, expect, sinPantallaDeError } from './fixtures'
import { FOTO } from './datos-franke'
import { USUARIO_ID, type FakeSupabase } from './fake-supabase'

const OT = 'ca000000-0000-4000-8000-000000000001'
const JORNADA = 'ca000000-0000-4000-8000-0000000000a1'
const DIA = 'ca000000-0000-4000-8000-0000000000d1'
const hoy = () => new Date().toLocaleDateString('sv-SE', { timeZone: 'America/Santiago' })

function servidorCalama(fake: FakeSupabase) {
  fake.comoPerfil({ rol: 'tecnico_mantenimiento', nombre_completo: 'Operador Calama' }, null)
  fake.tablas.calama_roles_proyecto = [{ usuario_id: USUARIO_ID, rol_calama: 'operador_calama', activo: true }]
  fake.tablas.calama_plan_semanal_ots = [{
    id: JORNADA, plan_semanal_id: 'ps-1', plan_dia_id: DIA, ot_id: OT, zona_proyecto_id: null, responsable_id: USUARIO_ID,
    prioridad: 1, estado_plan: 'planificada', observaciones: null, horas_planificadas: 8, avance_objetivo_pct: null,
    secuencia_jornada: 1, visible_en_kanban: true, desprogramada_at: null, anulada_at: null, es_prueba: null,
    llegada_faena_at: null, updated_at: new Date().toISOString(), created_at: new Date().toISOString(),
  }]
  fake.tablas.calama_plan_semanal_dias = [{ id: DIA, fecha: hoy(), nombre_dia: 'Hoy', orden: 1 }]
  fake.tablas.calama_ordenes_trabajo = [{ id: OT, folio: 'CAL-0091', titulo: 'Cambio de bomba sumergible', avance_pct: 10, estado: 'planificada', fecha_programada: hoy(), faena: { nombre: 'Calama' } }]
  fake.rpcs.rpc_calama_preparar_offline_operador = () => ({ jornadas: [] })
  fake.tablas.llegadas = []
  fake.rpcs.rpc_calama_registrar_llegada_faena = (a, db) => {
    const p = a.p_payload as { client_uuid: string; foto_llegada_url: string; gps_lat: number }
    if (!db.tablas.llegadas.some((x) => x.client_uuid === p.client_uuid)) db.tablas.llegadas.push({ ...p })
    return { success: true }
  }
}

test('Calama: llegada a faena sin señal con foto y GPS, sube una vez', async ({ page, context, modoAvion, conSesion, fake, erroresJs }) => {
  servidorCalama(fake)
  await context.grantPermissions(['geolocation'])
  await context.setGeolocation({ latitude: -22.456, longitude: -68.926, accuracy: 10 })
  await conSesion()
  await page.goto('/m/calama/')
  await page.evaluate(async () => { await navigator.serviceWorker.ready })
  await page.reload()
  await expect.poll(() => page.evaluate(() => !!navigator.serviceWorker.controller)).toBe(true)
  await expect(page.getByText('Cambio de bomba sumergible').first()).toBeVisible()
  await page.getByRole('button', { name: /Descargar jornadas/ }).click()
  await expect.poll(() => fake.rpcLlamadas('rpc_calama_preparar_offline_operador').length).toBeGreaterThan(0)
  await page.waitForTimeout(1000)

  await modoAvion(true)
  await page.goto('/m/')
  await page.waitForURL(/\/m\/calama\/?$/)
  await expect(page.getByText('Cambio de bomba sumergible').first()).toBeVisible()
  await page.getByRole('link', { name: /Ejecutar/ }).or(page.getByRole('button', { name: /Ejecutar/ })).first().click()
  await expect(page).toHaveURL(new RegExp(`/m/calama/ot/${OT}`))
  await page.locator('input[type="file"]').first().setInputFiles(FOTO)
  await page.getByRole('button', { name: /Registrar llegada/ }).click()
  await expect(page.getByText(/Guardado en este telefono|Pendiente de sincronizar/i).first()).toBeVisible()
  expect(fake.tablas.llegadas).toHaveLength(0)

  await modoAvion(false)
  await page.goto('/m/calama/')
  const sinc = page.getByRole('button', { name: /^Sincronizar$/ })
  await expect.poll(async () => {
    if (fake.tablas.llegadas.length) return fake.tablas.llegadas.length
    if (await sinc.isEnabled().catch(() => false)) await sinc.click().catch(() => undefined)
    return fake.tablas.llegadas.length
  }, { timeout: 40_000, intervals: [2000] }).toBe(1)
  const l = fake.tablas.llegadas[0] as { foto_llegada_url: string; gps_lat: number }
  expect(l.foto_llegada_url).toContain('calama-evidencias')
  expect(l.gps_lat).toBeCloseTo(-22.456, 2)
  await sinPantallaDeError(page)
  expect(erroresJs).toEqual([])
})
