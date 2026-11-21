// Trabajo real SIN señal en las otras apps de terreno: Romeral (despacho con
// las dos fotos del medidor) y Taller (abrir una OT que nunca se abrió con señal).
import { test, expect, prepararSinSenal, sinPantallaDeError } from './fixtures'
import { FOTO } from './datos-franke'

const ROMERAL_ID = '33333333-3333-4333-8333-333333333333'
const ROMERAL = { id: ROMERAL_ID, codigo: 'FAE-CMP-ROMERAL', nombre: 'Romeral', app_movil: '/m/romeral', panel_web: false }
const OT_ID = 'o0000000-0000-4000-8000-000000000001'
const hoy = () => new Date().toLocaleDateString('sv-SE', { timeZone: 'America/Santiago' })

test('Romeral: despacho en modo avión con foto inicial y final del medidor, sube una vez', async ({ page, modoAvion, conSesion, fake, erroresJs }) => {
  fake.comoPerfil({ rol: 'operador_combustible', nombre_completo: 'Operador Romeral' }, ROMERAL)
  fake.tablas.combustible_estanques = [{ id: 'e-rom-1', faena_id: ROMERAL_ID, codigo: 'CAM-R1', nombre: 'Camión R1', patente: 'RR-11', tipo: 'movil', activo: true }]
  fake.tablas.combustible_faena_equipos = [{ id: 'q-rom-1', faena_id: ROMERAL_ID, nombre: 'PALA-07', descripcion: 'Pala', ceco_id: null, activo: true, ceco: null }]
  fake.tablas.combustible_faena_ubicaciones = []
  fake.tablas.v_comb_faena_despachos = []
  fake.tablas.despachos = []
  fake.rpcs.rpc_comb_faena_despachar = (a, db) => {
    const ya = db.tablas.despachos.find((r) => r.client_uuid === a.p_client_uuid)
    if (!ya) db.tablas.despachos.push({ client_uuid: a.p_client_uuid, litros: a.p_litros, ini: a.p_foto_meter_inicial, fin: a.p_foto_meter_final })
    return { success: true, despacho_id: 'd1', litros: a.p_litros, duplicado: !!ya }
  }
  await conSesion()
  await prepararSinSenal(page, '/m/romeral/')
  await expect.poll(() => fake.llamadas.filter((l) => l.ruta === 'combustible_faena_equipos').length, { timeout: 30_000 }).toBeGreaterThan(0)

  await modoAvion(true)
  await page.goto('/m/romeral/')
  await page.getByText(/Completa turno, camión y quién carga/).click()
  await page.getByRole('button', { name: 'Día', exact: true }).click()
  await page.getByRole('button', { name: /RR-11/ }).click()
  await page.getByPlaceholder('Nombre del operador').fill('Operador Romeral')
  await page.getByRole('button', { name: /Nueva carga/ }).click()
  await page.getByPlaceholder(/Busca: pala/).fill('PALA')
  await page.getByRole('button', { name: /PALA-07/ }).click()
  const medidor = page.locator('input[placeholder="0"]')
  await medidor.nth(0).fill('5000')
  await medidor.nth(1).fill('5320')
  const fotos = page.locator('input[type="file"]')
  await fotos.nth(0).setInputFiles(FOTO)
  await fotos.nth(1).setInputFiles(FOTO)
  await page.getByRole('button', { name: /Guardar carga/ }).click()
  await expect(page.getByText(/Guardada en el teléfono/).first()).toBeVisible()
  expect(fake.tablas.despachos).toHaveLength(0)

  await modoAvion(false)
  await expect.poll(() => fake.tablas.despachos.length, { timeout: 40_000 }).toBe(1)
  expect(fake.tablas.despachos[0].litros).toBe(320)
  expect(String(fake.tablas.despachos[0].ini)).toContain('romeral/')
  expect(String(fake.tablas.despachos[0].fin)).toContain('romeral/')
  await sinPantallaDeError(page)
  expect(erroresJs).toEqual([])
})

test('Taller: en modo avión abre una OT que nunca se abrió con señal', async ({ page, modoAvion, conSesion, fake }) => {
  fake.comoPerfil({ rol: 'operador_taller', nombre_completo: 'Mecánico Taller' }, null)
  fake.tablas.v_taller_mecanico_ots = [{
    ot_id: OT_ID, ot_folio: 'OT-2026-0777', ot_tipo: 'preventivo', ot_estado: 'en_ejecucion', ot_prioridad: 'normal',
    preparacion_ok_at: null, fecha_programada: hoy(), activo_id: 'a1', activo_codigo: 'HHWB-44', activo_nombre: 'Mack',
    activo_patente: 'HHWB-44', cuadrilla: null, responsable_id: null, responsable: 'Mecánico Taller', asignada_a_mi: true,
    checklist_total: 0, checklist_completados: 0, tiempo_estimado_total_min: null, horas_planificadas: null,
    fecha_entrega_plan: null, fecha_grupo: hoy(), relojes: [],
  }]
  await conSesion()
  await prepararSinSenal(page, '/m/taller/')
  await expect(page.getByText('OT-2026-0777').first()).toBeVisible()
  // «Guardar sin internet», como se le indica al mecánico.
  const guardar = page.getByRole('button', { name: /Guardar sin internet/ })
  if (await guardar.isVisible().catch(() => false)) {
    await guardar.click()
    await expect(page.getByText(/OTs guardadas en el teléfono/)).toBeVisible()
  }

  await modoAvion(true)
  await page.goto('/m/taller/')
  await page.getByText('OT-2026-0777').first().click()
  await expect(page).toHaveURL(new RegExp(`/m/taller/ot/${OT_ID}`))
  await expect(page.getByText(/No se pudo cargar esta pantalla/)).toHaveCount(0)
  await expect(page.getByText('OT-2026-0777').first()).toBeVisible()
  await sinPantallaDeError(page)
})
