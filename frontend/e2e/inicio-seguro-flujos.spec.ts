// Inicio Seguro ENEX (MIG735) — casos de borde para presentar a faena:
// visto bueno desde la bandeja, rechazo y reenvío, sin señal, cierre con
// retiro de bloqueos, escalamiento a los 10 min y accesibilidad.
// Datos ficticios. Las capturas quedan en test-results/capturas-inicio-seguro.
import { readFileSync } from 'node:fs'
import { test, expect, prepararSinSenal } from './fixtures'
import { FOTO } from './datos-franke'
import type { FakeSupabase } from './fake-supabase'
import type { Page } from '@playwright/test'

const AXE = readFileSync(require.resolve('axe-core/axe.min.js'), 'utf8')
const PROG = 'c0000000-0000-4000-8000-0000000000e3'
const PAUTA = 'c0000000-0000-4000-8000-0000000000a3'
const FOTO_URL = 'https://example.test/storage/v1/object/public/evidencias-verificacion/inicio-seguro/foto.jpg'
const captura = (page: Page, n: string) => page.screenshot({ path: `test-results/capturas-inicio-seguro/${n}.png`, fullPage: true })

type Fila = Record<string, unknown>

function servidor(fake: FakeSupabase, rol = 'supervisor') {
  const ahora = new Date()
  fake.comoPerfil({ rol, app_terreno: '/m/enex', nombre_completo: rol === 'supervisor' ? 'Supervisor Prueba' : 'Prevencionista Prueba' }, null)
  fake.tablas.v_enex_terreno_pendientes = [{
    programacion_id: PROG, periodo_anio: ahora.getFullYear(), periodo_mes: ahora.getMonth() + 1,
    tipo_servicio: 'mantencion', fecha_programada: null, instalacion_id: 'inst-3', instalacion: 'Sala de bombas SB-02',
    instalacion_tipo: 'estanque', patente: null, linea: null, faena_id: 'f-x', faena_codigo: 'FX', faena: 'Faena Prueba',
    pauta_id: PAUTA, pauta_nombre: 'Mantención sala', pauta_borrador: false, pauta_items: 1,
    ejecucion_id: null, estado: 'pendiente', cumplida: false, es_recobro: false, es_comodin: false, origen: 'plan',
  }]
  fake.tablas.enex_pauta_items = [{
    id: 'c0000000-0000-4000-8000-0000000000b3', pauta_id: PAUTA, bloque: 'Bombas', bloque_orden: 1, orden: 1, codigo: 'B-01',
    descripcion: 'Cambiar filtro de bomba', periodicidad: 'mensual', tipo_campo: 'ok_nook', unidad: null,
    valor_referencia: null, tolerancia_min: null, tolerancia_max: null, requiere_foto: false, obligatorio: false,
    critico: false, activo: true,
  }]
  for (const t of ['v_enex_plan_tareas', 'v_enex_terreno_instalaciones', 'v_enex_pauta_lugar_items', 'ejecuciones_enex']) fake.tablas[t] = []
  fake.rpcs.fn_prevencion_habilitacion = () => ({ personas: [
    { personal_id: 'p1', nombre: 'Técnico Uno', cargo: 'Mantenedor', habilitado: true, requisitos: [] },
    { personal_id: 'p2', nombre: 'Técnico Dos', cargo: 'Mantenedor', habilitado: false,
      requisitos: [{ nombre: 'Curso EDC Energía Eléctrica', ok: false, aplica_a: 'todos' }] },
  ] })
  fake.rpcs.fn_inicio_seguro_es_aprobador = () => rol !== 'supervisor'
  const st: { fila: Fila | null; enviados: Fila[] } = { fila: null, enviados: [] }
  fake.rpcs.rpc_inicio_seguro_estado = () => st.fila
  fake.rpcs.rpc_inicio_seguro_solicitar = (a) => {
    const p = a.p as Fila
    st.enviados.push(p)
    st.fila = { ...p, id: `is-${st.enviados.length}`, estado: 'pendiente', solicitado_at: new Date().toISOString(), escalado_at: null, minutos_escalamiento: 10 }
    return st.fila
  }
  fake.rpcs.rpc_inicio_seguro_cerrar = (a) => { st.fila = { ...st.fila!, estado: 'cerrado', retiro_bloqueos: a.p_retiro }; return null }
  fake.rpcs.rpc_enex_ejecutar_pauta = (a, db) => {
    db.tablas.ejecuciones_enex.push({ client_uuid: a.p_client_uuid })
    return { success: true, ejecucion_id: 'ej-is-1', estado: 'cumplida' }
  }
  return st
}

const aprobado = (extra: Fila = {}): Fila => ({
  id: 'is-a', client_uuid: 'c0000000-0000-4000-8000-0000000000f3', programacion_id: PROG, tarea: 'Cambio de filtro',
  cuadrilla: [], art: { texto: 'ART' }, psgcc: [], sin_bloqueo_motivo: null, estado: 'aprobado',
  bloqueos: [{ energia: 'hidraulica', punto: 'Válvula bomba 1', foto_bloqueo: FOTO_URL, foto_energia_cero: FOTO_URL }],
  solicitado_at: new Date().toISOString(), decidido_at: new Date().toISOString(), decidido_por_nombre: 'Prevencionista Prueba',
  comentario: 'Ok, adelante', detenido_motivo: null, escalado_at: null, minutos_escalamiento: 10, ...extra,
})

async function correos(page: Page) {
  const tipos: string[] = []
  await page.route('**/api/inicio-seguro/correo/**', async (r) => { tipos.push(r.request().postDataJSON().tipo); await r.fulfill({ json: { ok: true } }) })
  return tipos
}

/** Llena el formulario mínimo: tarea sin energías (motivo), 1 persona, EDC combustibles todo «Sí», ART leída. */
async function llenarFormulario(page: Page) {
  await page.getByPlaceholder(/Cambio de filtro/).fill('Inspección visual de surtidor')
  await page.getByText('Técnico Uno', { exact: true }).click()
  await page.getByText('Manejo de Elementos Combustibles').click()
  const si = page.getByRole('radio', { name: 'Sí' })
  for (let i = 0; i < await si.count(); i++) await si.nth(i).click()
  await page.getByPlaceholder(/Pasos de la tarea/).fill('1. Delimitar el área. 2. Inspeccionar sin abrir líneas. 3. Registrar hallazgos.')
  await page.locator('section', { hasText: 'Leyó y entendió la ART' }).getByRole('checkbox', { name: 'Técnico Uno' }).check()
  await page.getByText('Esta tarea no interviene ninguna energía').click()
  await page.getByPlaceholder(/Explica por qué no hay que bloquear/).fill('Solo inspección visual, no se abren líneas ni tableros')
}

async function axe(page: Page) {
  await page.addScriptTag({ content: AXE })
  const v = await page.evaluate(async () => {
    const r = await (window as unknown as { axe: { run: (c: unknown, o: unknown) => Promise<{ violations: { id: string; impact: string; nodes: unknown[] }[] }> } })
      .axe.run(document, { runOnly: { type: 'tag', values: ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa'] } })
    return r.violations
  })
  const graves = v.filter((x) => x.impact === 'critical' || x.impact === 'serious')
  for (const x of graves) console.log('[a11y]', x.id, JSON.stringify((x.nodes as { html: string }[]).slice(0, 3).map((n) => n.html.slice(0, 160))))
  return graves.map((x) => `${x.id} (${x.nodes.length})`)
}

test('Bandeja de Hersaly: ve fotos y avisos, no puede rechazar sin comentario, aprueba', async ({ page, conSesion, fake, erroresJs }) => {
  servidor(fake, 'jefe_operaciones')
  const bandeja: Fila[] = [{
    ...aprobado({ estado: 'pendiente', decidido_at: null, comentario: null }),
    instalacion: 'Sala de bombas SB-02', faena: 'Faena Prueba', solicitado_por_nombre: 'Supervisor Prueba',
    cuadrilla: [
      { personal_id: 'p1', nombre: 'Técnico Uno', habilitado: true, pendientes: [], leyo_art: true },
      { personal_id: 'p2', nombre: 'Técnico Dos', habilitado: false, pendientes: ['Curso EDC Energía Eléctrica'], leyo_art: true },
    ],
    psgcc: [{ control: 'hi-2', pregunta: '¿Presión CERO en el manómetro?', respuesta: 'si' }],
  }]
  fake.rpcs.rpc_inicio_seguro_bandeja = () => bandeja
  fake.rpcs.rpc_inicio_seguro_decidir = (a) => {
    if (!a.p_aprobar && !String(a.p_comentario ?? '').trim()) throw new Error('Para rechazar, escriba qué hay que corregir.')
    Object.assign(bandeja[0], { estado: a.p_aprobar ? 'aprobado' : 'rechazado', decidido_at: new Date().toISOString(), comentario: a.p_comentario })
    return bandeja[0]
  }
  await page.route('**/inicio-seguro/foto.jpg', (r) => r.fulfill({ body: FOTO.buffer, contentType: 'image/jpeg' }))
  await conSesion()
  await page.goto('/m/inicio-seguro/')
  await expect(page.getByText('1 esperando visto bueno')).toBeVisible({ timeout: 30_000 })
  await expect(page.getByAltText('Candado y tarjeta — Válvula bomba 1')).toBeVisible()
  await expect(page.getByText(/Aviso: falta Curso EDC Energía Eléctrica/)).toBeVisible()
  await captura(page, '05-bandeja-hersaly')
  expect(await axe(page)).toEqual([])

  await page.getByRole('button', { name: 'Corregir' }).click()
  await expect(page.getByText(/Para rechazar, escriba qué hay que corregir/).first()).toBeVisible()
  expect(bandeja[0].estado).toBe('pendiente')

  await page.getByRole('button', { name: /Visto bueno/ }).click()
  await expect(page.getByText(/Visto bueno dado/).first()).toBeVisible()
  expect(bandeja[0].estado).toBe('aprobado')
  expect(fake.rpcLlamadas('rpc_inicio_seguro_decidir')).toHaveLength(2)
  expect(erroresJs).toEqual([])
})

test('Rechazo: el supervisor ve qué corregir y reenvía como solicitud nueva', async ({ page, conSesion, fake, erroresJs }) => {
  test.slow()
  const st = servidor(fake)
  const tipos = await correos(page)
  await conSesion()
  await page.goto(`/m/enex/servicio/?id=${PROG}`)
  await expect(page.getByTestId('inicio-seguro')).toBeVisible({ timeout: 30_000 })
  await captura(page, '01-formulario-vacio')
  await llenarFormulario(page)
  await captura(page, '02-formulario-lleno')
  expect(await axe(page)).toEqual([])
  await page.getByRole('button', { name: /Pedir visto bueno/ }).click()
  await expect(page.getByTestId('inicio-seguro-esperando')).toBeVisible()
  await captura(page, '03-esperando-visto-bueno')

  Object.assign(st.fila!, { estado: 'rechazado', comentario: 'Falta bloquear la válvula de alimentación', decidido_por_nombre: 'Prevencionista Prueba' })
  await expect(page.getByText('Falta bloquear la válvula de alimentación')).toBeVisible({ timeout: 25_000 })
  await captura(page, '04-rechazado')
  await page.getByRole('button', { name: 'Corregir y volver a enviar' }).click()
  await page.getByRole('button', { name: /Pedir visto bueno/ }).click()
  await expect(page.getByTestId('inicio-seguro-esperando')).toBeVisible()
  expect(st.enviados).toHaveLength(2)
  expect(st.enviados[0].client_uuid).not.toBe(st.enviados[1].client_uuid)
  await expect.poll(() => tipos.filter((t) => t === 'solicitud').length).toBe(2)
  expect(erroresJs).toEqual([])
})

test('Sin señal: lo llenado queda en el teléfono y no deja iniciar', async ({ page, conSesion, fake, modoAvion }) => {
  test.slow()
  servidor(fake)
  await conSesion()
  await prepararSinSenal(page, '/m/enex/')
  await expect(page.getByText(/disponibles sin internet|listo para trabajar sin señal/)).toBeVisible({ timeout: 30_000 })
  await page.goto(`/m/enex/servicio/?id=${PROG}`)
  await expect(page.getByText('Técnico Uno', { exact: true })).toBeVisible({ timeout: 30_000 })   // cuadrilla queda guardada

  await modoAvion(true)
  await page.reload()
  await expect(page.getByTestId('inicio-seguro')).toBeVisible({ timeout: 30_000 })
  await expect(page.getByText('Cambiar filtro de bomba')).toHaveCount(0)
  await llenarFormulario(page)
  await expect(page.getByText(/Para pedir el visto bueno hace falta señal/)).toBeVisible()
  await page.getByRole('button', { name: /Pedir visto bueno/ }).click()
  await expect(page.getByText(/Sin señal\. Todo queda guardado/).first()).toBeVisible()
  expect(fake.rpcLlamadas('rpc_inicio_seguro_solicitar')).toHaveLength(0)
  await captura(page, '06-sin-senal')

  await page.reload()
  await expect(page.getByPlaceholder(/Cambio de filtro/)).toHaveValue('Inspección visual de surtidor', { timeout: 30_000 })
})

test('Cierre: exige foto del retiro de bloqueos y la registra', async ({ page, conSesion, fake, erroresJs }) => {
  test.slow()
  const st = servidor(fake)
  st.fila = aprobado()
  await page.route('**/inicio-seguro/foto.jpg', (r) => r.fulfill({ body: FOTO.buffer, contentType: 'image/jpeg' }))
  await conSesion()
  await page.goto(`/m/enex/servicio/?id=${PROG}`)
  await expect(page.getByRole('button', { name: /Detener tarea/ })).toBeVisible({ timeout: 30_000 })
  await captura(page, '07-trabajando-con-visto-bueno')

  const actividad = page.getByText('Cambiar filtro de bomba')
  if (!(await actividad.isVisible().catch(() => false))) await page.getByRole('button', { name: /Bombas/ }).first().click()
  if (!(await page.getByRole('button', { name: /^OK$/ }).isVisible().catch(() => false))) await actividad.click()
  await page.getByRole('button', { name: /^OK$/ }).click()
  const fotosPauta = page.locator('input[type="file"][multiple]')
  await fotosPauta.nth(0).setInputFiles(FOTO)
  await fotosPauta.nth(1).setInputFiles(FOTO)
  for (const n of [0, 0]) {
    const canvas = page.locator('canvas').nth(n)
    await canvas.scrollIntoViewIfNeeded()
    const b = (await canvas.boundingBox())!
    await page.mouse.move(b.x + 20, b.y + 20); await page.mouse.down()
    await page.mouse.move(b.x + 150, b.y + 50, { steps: 8 }); await page.mouse.up()
    await page.getByRole('button', { name: 'Guardar firma' }).nth(n).click()
    if (n === 0) await page.getByPlaceholder('Nombre de quien firma (ESM/ENEX)').fill('Encargado ESM')
  }
  await page.getByRole('button', { name: /Cerrar \(cumplida\)/ }).click()
  await expect(page.getByText('Falta la foto del retiro de bloqueos antes de cerrar').first()).toBeVisible()
  expect(fake.tablas.ejecuciones_enex).toHaveLength(0)

  await page.getByTestId('retiro-bloqueos').locator('input[type="file"]').setInputFiles(FOTO)
  await expect(page.getByAltText('Bloqueo retirado')).toBeVisible()
  await captura(page, '08-retiro-de-bloqueos')
  await page.getByRole('button', { name: /Cerrar \(cumplida\)/ }).click()
  await expect.poll(() => fake.tablas.ejecuciones_enex.length, { timeout: 30_000 }).toBe(1)
  // Ya en la lista de servicios, el retiro guardado se envía solo.
  await expect.poll(() => fake.rpcLlamadas('rpc_inicio_seguro_cerrar').length, { timeout: 30_000 }).toBe(1)
  expect((st.fila!.retiro_bloqueos as { punto: string }[])[0].punto).toBe('Válvula bomba 1')
  expect(erroresJs).toEqual([])
})

test('Escalamiento: a los 10 min sin respuesta se pide el correo a la jefatura, una vez', async ({ page, conSesion, fake }) => {
  const st = servidor(fake)
  const tipos = await correos(page)
  await page.clock.install({ time: new Date() })
  st.fila = aprobado({ estado: 'pendiente', decidido_at: null, decidido_por_nombre: null, solicitado_at: new Date().toISOString() })
  await conSesion()
  await page.goto(`/m/enex/servicio/?id=${PROG}`)
  await expect(page.getByTestId('inicio-seguro-esperando')).toBeVisible({ timeout: 30_000 })
  await page.clock.fastForward('09:00')
  expect(tipos.filter((t) => t === 'escalamiento')).toHaveLength(0)
  await page.clock.fastForward('01:30')
  await expect.poll(() => tipos.filter((t) => t === 'escalamiento').length, { timeout: 15_000 }).toBe(1)
  st.fila!.escalado_at = new Date().toISOString()
  await page.clock.fastForward('00:30')
  await expect(page.getByText(/se avisó también a Manuel/)).toBeVisible({ timeout: 15_000 })
  await captura(page, '09-escalado')
  expect(tipos.filter((t) => t === 'escalamiento')).toHaveLength(1)
})
