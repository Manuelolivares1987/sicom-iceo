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

async function abrirOtDesdeLista(page: import('@playwright/test').Page) {
  await page.goto('/m/calama/')
  await expect(page.getByText('Cambio de bomba sumergible').first()).toBeVisible()
  await page.getByRole('link', { name: /Ejecutar/ }).or(page.getByRole('button', { name: /Ejecutar/ })).first().click()
  await expect(page).toHaveURL(new RegExp(`/m/calama/ot/${OT}`))
}

function servidorCalama(fake: FakeSupabase) {
  fake.comoPerfil({ rol: 'tecnico_mantenimiento', nombre_completo: 'Operador Calama' }, null)
  fake.tablas.calama_roles_proyecto = [{ usuario_id: USUARIO_ID, rol_calama: 'operador_calama', activo: true }]
  fake.tablas.calama_plan_semanal_ots = [{
    id: JORNADA, plan_semanal_id: 'ps-1', plan_dia_id: DIA, ot_id: OT, zona_proyecto_id: null, responsable_id: USUARIO_ID,
    prioridad: 1, estado_plan: 'planificada', observaciones: 'Llevar sello de repuesto: el anterior venía fallado', horas_planificadas: 8, avance_objetivo_pct: null,
    secuencia_jornada: 1, visible_en_kanban: true, desprogramada_at: null, anulada_at: null, es_prueba: null,
    llegada_faena_at: null, updated_at: new Date().toISOString(), created_at: new Date().toISOString(),
  }]
  fake.tablas.calama_plan_semanal_dias = [{ id: DIA, fecha: hoy(), nombre_dia: 'Hoy', orden: 1 }]
  fake.tablas.calama_ordenes_trabajo = [{ id: OT, folio: 'CAL-0091', titulo: 'Cambio de bomba sumergible', avance_pct: 10, estado: 'planificada', fecha_programada: hoy(), faena_calama_id: 'fc-1' }]
  fake.tablas.calama_faenas = [{ id: 'fc-1', codigo: 'RT', nombre: 'Radomiro Tomic' }]
  fake.tablas.calama_rechazos_jornada = [{ id: 'r-1', plan_semanal_ot_id: JORNADA, motivo: 'Falta foto del sello instalado', created_at: new Date().toISOString() }]
  fake.tablas.calama_firmas_jornada = []
  fake.tablas.calama_evidencias = []
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
  // [21-11-2026] Nadie aprieta «Descargar jornadas»: con señal se baja solo.
  await expect.poll(() => fake.rpcLlamadas('rpc_calama_preparar_offline_operador').length, { timeout: 30_000 }).toBeGreaterThan(0)
  await expect(page.getByText(/Las jornadas se bajan solas.*última vez/)).toBeVisible({ timeout: 15_000 })

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

  // Vuelve la señal: sube SOLO (sin apretar «Sincronizar»).
  await modoAvion(false)
  await expect.poll(() => fake.tablas.llegadas.length, { timeout: 40_000 }).toBe(1)
  const l = fake.tablas.llegadas[0] as { foto_llegada_url: string; gps_lat: number }
  expect(l.foto_llegada_url).toContain('calama-evidencias')
  expect(l.gps_lat).toBeCloseTo(-22.456, 2)
  await sinPantallaDeError(page)
  expect(erroresJs).toEqual([])
})

test('Calama: la descarga automática NO borra una llegada hecha sin señal que todavía no sube', async ({ page, context, modoAvion, conSesion, fake }) => {
  servidorCalama(fake)
  await context.grantPermissions(['geolocation'])
  await context.setGeolocation({ latitude: -22.456, longitude: -68.926, accuracy: 10 })
  await conSesion()
  await page.goto('/m/calama/')
  await page.evaluate(async () => { await navigator.serviceWorker.ready })
  await page.reload()
  await expect.poll(() => fake.rpcLlamadas('rpc_calama_preparar_offline_operador').length, { timeout: 30_000 }).toBeGreaterThan(0)

  await modoAvion(true)
  await abrirOtDesdeLista(page)
  await page.locator('input[type="file"]').first().setInputFiles(FOTO)
  await page.getByRole('button', { name: /Registrar llegada/ }).click()
  await expect(page.getByText(/Guardado en este telefono|Pendiente de sincronizar/i).first()).toBeVisible()

  // Vuelve la señal pero el servidor rechaza la llegada por un rato (503): la
  // llegada sigue pendiente mientras la descarga automática vuelve a bajar todo.
  fake.rpcs.rpc_calama_registrar_llegada_faena = () => { throw Object.assign(new Error('Service Unavailable'), { status: 503, code: '503' }) }
  const descargasAntes = fake.rpcLlamadas('rpc_calama_preparar_offline_operador').length
  await modoAvion(false)
  // La descarga automática no se repite antes de 1 min (ahorra datos): se fuerza
  // con «Actualizar ahora», que es la MISMA descarga protegida.
  await page.goto('/m/calama/')
  await page.getByRole('button', { name: /Actualizar ahora/ }).click()
  await expect.poll(() => fake.rpcLlamadas('rpc_calama_preparar_offline_operador').length, { timeout: 30_000 }).toBeGreaterThan(descargasAntes)

  // Sin señal otra vez: la OT sigue mostrando la llegada hecha (no pide registrarla de nuevo).
  await modoAvion(true)
  await abrirOtDesdeLista(page)
  await expect(page.getByText('CAL-0091').or(page.getByText('Cambio de bomba sumergible')).first()).toBeVisible()
  await expect(page.getByRole('button', { name: /Registrar llegada/ })).toHaveCount(0)
})

test('Calama: con la app cerrada y SIN señal, la OT muestra faena, nota del planificador y el rechazo anterior', async ({ page, context, modoAvion, conSesion, fake }) => {
  servidorCalama(fake)
  await conSesion()
  await page.goto('/m/calama/')
  await page.evaluate(async () => { await navigator.serviceWorker.ready })
  await page.reload()
  // Se baja todo solo (jornadas + lo que se mira de cada OT), sin entrar a la OT con señal.
  await expect.poll(() => fake.llamadas.filter((l) => l.ruta === 'calama_rechazos_jornada').length, { timeout: 40_000 }).toBeGreaterThan(0)
  await page.waitForTimeout(1500)

  await modoAvion(true)
  await page.close()
  const p = await context.newPage()
  await p.goto('/m/')
  await p.waitForURL(/\/m\/calama\/?$/)
  await abrirOtDesdeLista(p)
  await expect(p.getByText('Radomiro Tomic')).toBeVisible()
  await expect(p.getByText(/Llevar sello de repuesto/)).toBeVisible()
  await expect(p.getByText(/Falta foto del sello instalado/)).toBeVisible()
  await sinPantallaDeError(p)
})

// ── Calama igual que Franke (22-11-2026) ────────────────────────────────────
test('Calama: con la sesión vencida y SIN señal abre desde el ícono (no pide clave)', async ({ page, modoAvion, conSesion, fake, erroresJs }) => {
  servidorCalama(fake)
  await conSesion()
  await page.goto('/m/calama/')
  await page.evaluate(async () => { await navigator.serviceWorker.ready })
  await page.reload()
  await expect.poll(() => fake.rpcLlamadas('rpc_calama_preparar_offline_operador').length, { timeout: 30_000 }).toBeGreaterThan(0)
  await page.waitForTimeout(1500)
  // Pasa la noche en el rajo: el token vence y no hay señal para renovarlo.
  await page.evaluate((k) => {
    const s = JSON.parse(localStorage.getItem(k) ?? '{}')
    s.expires_at = Math.floor(Date.now() / 1000) - 3600
    localStorage.setItem(k, JSON.stringify(s))
  }, 'sb-e2e-auth-token')
  fake.refrescoFalla = true
  await modoAvion(true)
  await page.goto('/m/')
  await page.waitForURL(/\/m\/calama\/?$/)
  await expect(page.getByText('Cambio de bomba sumergible').first()).toBeVisible()
  await expect(page).not.toHaveURL(/login/)
  await abrirOtDesdeLista(page)
  await expect(page.getByRole('button', { name: /Registrar llegada/ })).toBeVisible()
  await sinPantallaDeError(page)
  expect(erroresJs).toEqual([])
})

test('Calama: jornada COMPLETA sin señal (llegada, inicio, avance, cierre con firma) sube sola, en orden y una vez', async ({ page, context, modoAvion, conSesion, fake, erroresJs }) => {
  test.slow()
  servidorCalama(fake)
  const orden: string[] = []
  const vistos = new Set<string>()
  const registrar = (nombre: string) => (a: Record<string, unknown>) => {
    const p = (a.p_payload ?? {}) as Record<string, unknown>
    const id = String(p.client_uuid ?? p.client_uuid_evidencia ?? p.client_uuid_foto ?? JSON.stringify(p))
    if (!vistos.has(id)) { vistos.add(id); orden.push(nombre) }
    return { success: true }
  }
  fake.rpcs.rpc_calama_registrar_llegada_faena = registrar('llegada')
  fake.rpcs.rpc_calama_iniciar_jornada = registrar('iniciar')
  fake.rpcs.rpc_calama_registrar_evento_jornada = registrar('avance')
  fake.rpcs.rpc_calama_finalizar_jornada = registrar('finalizar')
  await context.grantPermissions(['geolocation'])
  await context.setGeolocation({ latitude: -22.456, longitude: -68.926, accuracy: 10 })
  await conSesion()
  await page.goto('/m/calama/')
  await page.evaluate(async () => { await navigator.serviceWorker.ready })
  await page.reload()
  await expect.poll(() => fake.rpcLlamadas('rpc_calama_preparar_offline_operador').length, { timeout: 30_000 }).toBeGreaterThan(0)
  await page.waitForTimeout(1500)

  await modoAvion(true)
  await abrirOtDesdeLista(page)
  await test.step('llegada a faena', async () => {
    await page.locator('input[type="file"]').first().setInputFiles(FOTO)
    await page.getByRole('button', { name: /Registrar llegada/ }).click()
  })
  await test.step('iniciar jornada con foto ANTES', async () => {
    await expect(page.getByRole('button', { name: /Iniciar jornada/ })).toBeVisible()
    await page.locator('input[type="file"]').first().setInputFiles(FOTO)
    await page.getByRole('button', { name: /Iniciar jornada/ }).click()
  })
  await test.step('guardar avance 50%', async () => {
    await expect(page.getByRole('button', { name: /Guardar avance/ })).toBeVisible()
    await page.getByRole('button', { name: '50%', exact: true }).click()
    await page.getByRole('button', { name: /Guardar avance \(50%\)/ }).click()
    await page.waitForTimeout(800)
  })
  await test.step('cerrar jornada con foto DESPUÉS y firma del operador', async () => {
    await page.getByRole('button', { name: /^Cerrar jornada$/ }).click()
    await page.locator('input[type="file"]').first().setInputFiles(FOTO)
    const lienzo = page.locator('canvas').first()
    const b = (await lienzo.boundingBox())!
    await page.mouse.move(b.x + 20, b.y + 20); await page.mouse.down()
    await page.mouse.move(b.x + 120, b.y + 60, { steps: 8 }); await page.mouse.move(b.x + 200, b.y + 30, { steps: 8 })
    await page.mouse.up()
    await page.getByRole('button', { name: 'Guardar firma' }).click()
    // Avance final 50% (lo guardado): cierre parcial pide comentario.
    await page.getByPlaceholder(/Observacion de cierre/).fill('Queda el sello para mañana')
    await page.getByRole('button', { name: /Cerrar jornada \(50%\)/ }).click()
  })
  // Sin señal, nada llegó al servidor; el teléfono lo muestra pendiente.
  await page.waitForTimeout(1000)
  expect(orden).toEqual([])
  await sinPantallaDeError(page)

  // Vuelve la señal y se pierde la respuesta del inicio: igual queda todo una vez y en orden.
  fake.perderRespuesta.add('rpc_calama_iniciar_jornada')
  await modoAvion(false)
  await expect.poll(() => orden.length, { timeout: 150_000, intervals: [2000] }).toBe(4)
  expect(orden).toEqual(['llegada', 'iniciar', 'avance', 'finalizar'])
  // Fotos y firma subidas a su lugar (una por archivo, sin duplicados).
  const subidas = (fake.tablas.__storage ?? []).map((f) => String(f.path))
  expect(subidas.filter((p) => p.includes('calama-firmas')).length).toBe(1)
  expect(subidas.filter((p) => p.includes('calama-evidencias')).length).toBe(3)
  expect(erroresJs).toEqual([])
})
