// Datos de Franke para el Supabase simulado + las funciones del servidor que
// importan, con la MISMA regla que el servidor real: el identificador del
// teléfono (client_uuid) hace que un reintento no duplique.
import { FAENA_ID, type FakeSupabase } from './fake-supabase'

export const CAMION_1 = 'e0000000-0000-4000-8000-000000000001'
export const EQUIPO_1 = 'q0000000-0000-4000-8000-000000000001'
export const ACTIVO_1 = 'a0000000-0000-4000-8000-000000000001'
export const PAUTA_1 = 'p0000000-0000-4000-8000-000000000001'
export const ITEM_ACEITE = 'i0000000-0000-4000-8000-000000000001'
export const ITEM_LUCES = 'i0000000-0000-4000-8000-000000000002'
export const BODEGA_ID = 'b0000000-0000-4000-8000-000000000001'
export const PRODUCTO_FILTRO = 'r0000000-0000-4000-8000-000000000001'

/** Foto mínima válida (PNG 1×1): la app la comprime como cualquier foto. */
export const FOTO = {
  name: 'foto.png', mimeType: 'image/png',
  buffer: Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==', 'base64'),
}

export function sembrarFranke(fake: FakeSupabase) {
  const t = fake.tablas
  // ── Combustible ───────────────────────────────────────────────────────
  t.combustible_estanques = [
    { id: CAMION_1, faena_id: FAENA_ID, codigo: 'CAM-1', nombre: 'Camión 1', patente: 'CC-11', tipo: 'movil', activo: true,
      clave_cierre: null, orden_cierre: 1, capacidad_lt: 10000, capacidad_llenado_lt: 9500 },
  ]
  t.combustible_faena_medidores = []
  t.combustible_faena_equipos = [
    { id: EQUIPO_1, faena_id: FAENA_ID, nombre: 'CAEX-101', descripcion: 'Camión de extracción', ceco_id: null, activo: true,
      ceco: { codigo: 'CECO-9', empresa: 'Mina Franke' } },
  ]
  t.combustible_faena_ubicaciones = [{ id: 'u1', faena_id: FAENA_ID, nombre: 'Patio', activo: true }]
  t.v_comb_faena_recepcion = []
  t.v_comb_faena_despachos = []
  t.recepciones = []
  t.despachos = []

  fake.rpcs.rpc_comb_faena_recepcion = (a, db) => {
    const ya = db.tablas.recepciones.find((r) => r.client_uuid === a.p_client_uuid)
    if (!ya) db.tablas.recepciones.push({ client_uuid: a.p_client_uuid, guia: a.p_guia, litros: a.p_litros_guia, foto: a.p_foto_guia })
    return { success: true, duplicado: !!ya, litros_medidor: a.p_litros_guia, diferencia_surtidor_medidor: null }
  }
  fake.rpcs.rpc_comb_faena_despachar = (a, db) => {
    const ya = db.tablas.despachos.find((r) => r.client_uuid === a.p_client_uuid)
    if (!ya) db.tablas.despachos.push({ client_uuid: a.p_client_uuid, litros: a.p_litros, folio: a.p_folio_ticket, foto: a.p_foto_meter_final })
    return { success: true, despacho_id: 'd1', litros: a.p_litros, duplicado: !!ya }
  }

  // ── Bodega ────────────────────────────────────────────────────────────
  t.bodegas = [{ id: BODEGA_ID, codigo: 'BOD-FRK-F01' }]
  t.salidas = []
  fake.rpcs.rpc_bodega_faena_catalogo = () => ({
    generado_at: new Date().toISOString(), puede_operar: true, puede_sacar: true,
    productos: [[PRODUCTO_FILTRO, 'FIL-001', '7800000000017', 'FILTRO ACEITE MACK', 'filtro', 'un', 6, 2]],
    equipos: [{ id: ACTIVO_1, patente: 'HHWB-44', tipo: 'camion_tolva' }],
  })
  fake.rpcs.rpc_bodega_faena_salida = (a, db) => {
    const ya = db.tablas.salidas.find((r) => r.client_uuid === a.p_client_uuid)
    if (!ya) db.tablas.salidas.push({ client_uuid: a.p_client_uuid, items: a.p_items, activo: a.p_activo_id })
    return { ok: true, items: 1, costo_total: 0, bajo_minimo: [], repetida: !!ya }
  }

  // ── Pauta del mecánico ───────────────────────────────────────────────
  t.v_faena_pauta_agenda = [{
    faena_id: FAENA_ID, activo_id: ACTIVO_1, activo_codigo: 'HHWB-44', patente: 'HHWB-44', activo_nombre: 'Mack Granite',
    activo_estado: 'operativo', modelo: 'Mack', horas_uso_actual: 5200, kilometraje_actual: null,
    pauta_id: PAUTA_1, pauta_codigo: 'DIARIA', pauta_nombre: 'Revisión diaria', pauta_tipo: 'diaria',
    disparo_horas: null, disparo_km: null, items: 2, ultima_horometro: 5190, ultima_kilometraje: null, ultima_fecha: null,
    origen_ultima: 'ejecucion', faltan_horas: null, faltan_km: null, faltan_dias: null, senal: 'diaria',
    ejecucion_hoy_id: null, ejecucion_hoy_estado: null, ejecucion_hoy_turno: null, ejecucion_hoy_por: null,
  }]
  const item = (id: string, orden: number, texto: string) => ({
    id, pauta_id: PAUTA_1, orden, bloque: 'Motor', texto, ayuda: null, tipo_respuesta: 'ok_nok', unidad: null,
    obligatorio: true, foto_si_nok: true, foto_obligatoria: false, critico: false, repuesto: null,
  })
  t.faena_pauta_item = [item(ITEM_ACEITE, 1, 'Nivel de aceite'), item(ITEM_LUCES, 2, 'Luces')]
  t.faena_pauta_ejecucion_item = []
  t.ejecuciones = []
  fake.rpcs.rpc_faena_pauta_guardar = (a, db) => {
    const clave = `${a.p_pauta_id}|${a.p_activo_id}|${a.p_fecha}|${a.p_turno ?? ''}`
    let e = db.tablas.ejecuciones.find((x) => x.clave === clave)
    if (!e) { e = { clave, estado: 'borrador', items: [] }; db.tablas.ejecuciones.push(e) }
    if (e.estado === 'cerrada' && !a.p_cerrar) return { success: true, ejecucion_id: 'ej1', estado: 'cerrada', sin_cambios: true }
    e.items = a.p_items
    const items = a.p_items as { resultado: string; foto_url: string | null }[]
    if (a.p_cerrar) {
      const sinFoto = items.filter((i) => i.resultado === 'nok' && !i.foto_url)
      if (sinFoto.length) throw Object.assign(new Error('Estos hallazgos necesitan foto'), { code: '23514' })
      e.estado = 'cerrada'
    }
    return { success: true, ejecucion_id: 'ej1', estado: e.estado, hallazgos: items.filter((i) => i.resultado === 'nok').length, no_conformidades: 0 }
  }
}

/** Fotos que llegaron al servidor bajo una carpeta. */
export const fotosEn = (fake: FakeSupabase, carpeta: string) =>
  (fake.tablas.__storage ?? []).filter((f) => String(f.path).includes(`${carpeta}/`))
