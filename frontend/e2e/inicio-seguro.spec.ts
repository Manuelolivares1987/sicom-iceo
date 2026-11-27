// Inicio Seguro ENEX (MIG735): sin visto bueno de prevención no se toca la
// pauta. Datos ficticios.
import { test, expect, sinPantallaDeError } from './fixtures'
import { FOTO } from './datos-franke'
import type { FakeSupabase } from './fake-supabase'

const PROG = 'c0000000-0000-4000-8000-0000000000e2'
const PAUTA = 'c0000000-0000-4000-8000-0000000000a2'

function servidor(fake: FakeSupabase) {
  const ahora = new Date()
  fake.comoPerfil({ rol: 'supervisor', app_terreno: '/m/enex', nombre_completo: 'Supervisor Prueba' }, null)
  fake.tablas.v_enex_terreno_pendientes = [{
    programacion_id: PROG, periodo_anio: ahora.getFullYear(), periodo_mes: ahora.getMonth() + 1,
    tipo_servicio: 'mantencion', fecha_programada: null, instalacion_id: 'inst-2', instalacion: 'Sala de bombas SB-01',
    instalacion_tipo: 'estanque', patente: null, linea: null, faena_id: 'f-x', faena_codigo: 'FX', faena: 'Faena Prueba',
    pauta_id: PAUTA, pauta_nombre: 'Mantención sala', pauta_borrador: false, pauta_items: 1,
    ejecucion_id: null, estado: 'pendiente', cumplida: false, es_recobro: false, es_comodin: false, origen: 'plan',
  }]
  fake.tablas.enex_pauta_items = [{
    id: 'c0000000-0000-4000-8000-0000000000b2', pauta_id: PAUTA, bloque: 'Bombas', bloque_orden: 1, orden: 1, codigo: 'B-01',
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
  let fila: Record<string, unknown> | null = null
  fake.rpcs.rpc_inicio_seguro_estado = () => fila
  fake.rpcs.rpc_inicio_seguro_solicitar = (a) => {
    const p = a.p as Record<string, unknown>
    fila ??= { ...p, id: 'is-9', estado: 'pendiente', solicitado_at: new Date().toISOString(), escalado_at: null, minutos_escalamiento: 10 }
    return fila
  }
  fake.rpcs.rpc_inicio_seguro_detener = (a) => { Object.assign(fila!, { estado: 'detenido', detenido_motivo: a.p_motivo }); return null }
  return {
    aprobar: () => { Object.assign(fila!, { estado: 'aprobado', decidido_por_nombre: 'Prevencionista Prueba', decidido_at: new Date().toISOString() }) },
    fila: () => fila,
  }
}

test('Inicio seguro: sin visto bueno no se ve la pauta; con visto bueno aparece y se puede detener', async ({ page, conSesion, fake, erroresJs }) => {
  test.slow()
  const srv = servidor(fake)
  const correos: string[] = []
  await page.route('**/api/inicio-seguro/correo/**', async (r) => {
    correos.push(r.request().postDataJSON().tipo)
    await r.fulfill({ json: { ok: true } })
  })
  await conSesion()
  await page.goto(`/m/enex/servicio/?id=${PROG}`)

  await expect(page.getByTestId('inicio-seguro')).toBeVisible({ timeout: 30_000 })
  await expect(page.getByText('Cambiar filtro de bomba')).toHaveCount(0)
  const pedir = page.getByRole('button', { name: /Pedir visto bueno/ })
  await expect(pedir).toBeDisabled()

  await page.getByPlaceholder(/Cambio de filtro/).fill('Cambio de filtro en bomba 1')
  await page.getByText('Técnico Uno', { exact: true }).click()
  await page.getByText('Técnico Dos', { exact: true }).click()
  // Le falta el curso: solo un aviso, no bloquea.
  await expect(page.getByText(/Aviso: le falta Curso EDC Energía Eléctrica/)).toBeVisible()

  await page.getByText('Interacción con Energía Hidráulica').click()
  const si = page.getByRole('radio', { name: 'Sí' })
  await expect(si).toHaveCount(5)
  // Un «No» detiene: no se puede pedir visto bueno.
  await page.getByRole('radio', { name: 'No', exact: true }).first().click()
  await expect(page.getByText(/control crítico NO está implementado/)).toBeVisible()
  for (let i = 0; i < 5; i++) await si.nth(i).click()

  await page.getByPlaceholder(/Pasos de la tarea/).fill('1. Aislar y bloquear la bomba. 2. Despresurizar y verificar cero en el manómetro. 3. Cambiar el filtro.')
  const leyo = page.locator('section', { hasText: 'Leyó y entendió la ART' })
  await leyo.getByRole('checkbox', { name: 'Técnico Uno' }).check()
  await leyo.getByRole('checkbox', { name: 'Técnico Dos' }).check()

  await page.getByLabel('Energía', { exact: true }).selectOption('hidraulica')
  await page.getByLabel('Punto de bloqueo').fill('Válvula de bola bomba 1')
  await page.locator('label', { hasText: 'Candado y tarjeta' }).locator('input[type="file"]').setInputFiles(FOTO)
  await page.locator('label', { hasText: 'Energía cero (medición)' }).locator('input[type="file"]').setInputFiles(FOTO)
  await expect(page.getByAltText('Candado y tarjeta')).toBeVisible()
  await expect(page.getByAltText('Energía cero (medición)')).toBeVisible()

  await expect(pedir).toBeEnabled()
  await pedir.click()
  await expect(page.getByTestId('inicio-seguro-esperando')).toBeVisible()
  await expect(page.getByText('NO inicies la tarea todavía.')).toBeVisible()
  const f = srv.fila()!
  expect((f.bloqueos as { foto_bloqueo: string }[])[0].foto_bloqueo).toContain('inicio-seguro/')
  expect((f.cuadrilla as { habilitado: boolean }[]).map((c) => c.habilitado)).toEqual([true, false])
  await expect.poll(() => correos).toContain('solicitud')

  srv.aprobar()
  await expect(page.getByRole('button', { name: /Detener tarea/ })).toBeVisible({ timeout: 25_000 })
  await expect(page.getByTestId('retiro-bloqueos')).toBeVisible()
  await expect(page.getByTestId('inicio-seguro')).toHaveCount(0)

  await page.getByRole('button', { name: /Detener tarea/ }).click()
  await page.getByLabel('Motivo de la detención').fill('Manómetro no marca cero')
  await page.getByRole('button', { name: 'Detener', exact: true }).click()
  await expect(page.getByText('Tarea DETENIDA', { exact: true })).toBeVisible()
  await expect.poll(() => correos).toContain('detencion')
  await sinPantallaDeError(page)
  expect(erroresJs).toEqual([])
})
