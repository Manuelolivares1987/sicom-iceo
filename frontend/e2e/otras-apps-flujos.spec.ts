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

// [22-11-2026] «Sacan fotos y no se ven en otro dispositivo»: el 12-11 el
// servidor no dejó guardar la foto en la tarea (la OT ya había cambiado de
// estado) SIN dar error; la app la daba por subida y la borraba del teléfono.
test('Taller: foto sin señal en una tarea; si el servidor no la guarda, NO se pierde y sube una sola vez', async ({ page, modoAvion, conSesion, fake, erroresJs }) => {
  test.slow()
  const ITEM = 'i0000000-0000-4000-8000-000000000001'
  const INST = 'n0000000-0000-4000-8000-000000000001'
  fake.comoPerfil({ rol: 'operador_taller', nombre_completo: 'Mecánico Taller' }, null)
  fake.tablas.v_taller_mecanico_ots = [{
    ot_id: OT_ID, ot_folio: 'OT-2026-0777', ot_tipo: 'correctivo', ot_estado: 'en_ejecucion', ot_prioridad: 'normal',
    preparacion_ok_at: new Date().toISOString(), fecha_programada: hoy(), activo_id: 'a1', activo_codigo: 'HHWB-44', activo_nombre: 'Mack',
    activo_patente: 'HHWB-44', cuadrilla: null, responsable_id: null, responsable: 'Mecánico Taller', asignada_a_mi: true,
    checklist_total: 1, checklist_completados: 0, tiempo_estimado_total_min: 60, horas_planificadas: null,
    fecha_entrega_plan: null, fecha_grupo: hoy(), relojes: [],
  }]
  fake.tablas.v_taller_ot_checklist_v3 = [{
    instance_item_id: ITEM, instance_id: INST, ot_id: OT_ID, instance_estado: 'en_progreso', bloque: 'b01_reparacion', bloque_orden: 1, orden: 1,
    codigo: null, descripcion: 'Cambio de bujes de Bugy de ambos lados', tiempo_min: 60, tiempo_editado: false, requiere_foto: false,
    obligatorio: false, critico: false, categoria_calidad: null, resultado: null, observacion: null, foto_url: null, foto_urls: null,
    excluido: false, es_custom: true, mediciones: null, tipo_respuesta: 'ok_no_ok', valor_numerico: null, observado: false,
  }]
  fake.tablas.checklist_v2_instance_item = [{ id: ITEM, instance_id: INST, resultado: null, foto_url: null, foto_urls: [] }]
  // Medidores sin anotar: la visita parte SIN señal y se anotan en el teléfono.
  fake.tablas.checklist_v2_instance = [{ id: INST, ot_id: OT_ID, horometro: null, kilometraje: null, cuenta_litros: null,
    medidores_por: null, activo_id: 'a1', activos: { tipo: 'grua', tipo_equipamiento: null } }]
  fake.tablas.medidores = []
  fake.rpcs.rpc_taller_registrar_medidores = (a, db) => {
    db.tablas.medidores.push({ hm: a.p_horometro })
    Object.assign(db.tablas.checklist_v2_instance[0], { horometro: a.p_horometro, medidores_por: 'u-1' })
    return { success: true }
  }
  fake.rpcs.rpc_taller_reanudar_ejecucion_ot = () => ({ sin_ejecucion: true })
  fake.rpcs.rpc_taller_iniciar_ejecucion_ot = () => ({ success: true })
  const fotosSubidas = () => (fake.tablas.__storage ?? []).map((f) => String(f.path)).filter((p) => p.includes(`checklist-v2/${INST}/${ITEM}`))
  await conSesion()
  await prepararSinSenal(page, '/m/taller/')
  await page.getByText('OT-2026-0777').first().click()
  await expect(page.getByText('Cambio de bujes de Bugy de ambos lados')).toBeVisible()

  await modoAvion(true)
  await expect(page.getByText(/El checklist está bloqueado/)).toBeVisible()
  await page.getByText('Horómetro (h)').locator('xpath=..').locator('input').fill('1234')
  await page.getByRole('button', { name: 'Guardar medidores' }).click()
  await expect(page.getByText(/El checklist está bloqueado/)).toHaveCount(0)
  await page.getByRole('button', { name: 'OK', exact: true }).first().click()
  await page.locator('input[type="file"][multiple]').last().setInputFiles(FOTO)
  await expect(page.getByText(/todavía en este teléfono/)).toBeVisible()
  expect(fotosSubidas()).toHaveLength(0)

  // Vuelve la señal, pero el servidor no deja guardar la tarea (sin dar error).
  fake.escrituraBloqueada.add('checklist_v2_instance_item')
  await modoAvion(false)
  await expect(page.getByText(/El servidor no guardó este cambio/).first()).toBeVisible({ timeout: 60_000 })
  await expect(page.getByText(/todavía en este teléfono/)).toBeVisible()
  expect(fake.tablas.checklist_v2_instance_item[0].foto_urls).toEqual([])

  // El jefe lo destraba: al reintentar sube y la foto queda en la tarea, UNA vez.
  fake.escrituraBloqueada.delete('checklist_v2_instance_item')
  await page.reload()
  await expect.poll(() => (fake.tablas.checklist_v2_instance_item[0].foto_urls as string[]).length, { timeout: 60_000 }).toBe(1)
  expect(fake.tablas.medidores).toEqual([{ hm: 1234 }])
  expect(fotosSubidas()).toHaveLength(1)
  expect(String((fake.tablas.checklist_v2_instance_item[0].foto_urls as string[])[0])).toContain(fotosSubidas()[0])
  await sinPantallaDeError(page)
  expect(erroresJs).toEqual([])
})
