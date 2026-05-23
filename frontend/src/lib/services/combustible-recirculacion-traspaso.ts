import { supabase } from '@/lib/supabase'

// ============================================================================
// RECIRCULACION (MIG75)
// ============================================================================

export interface RecirculacionPayload {
  estanque_id: string
  litros: number
  equipo_prueba_descripcion: string
  foto_patente_equipo_url: string
  foto_equipo_url: string
  foto_medidor_inicial_url: string
  foto_medidor_final_url: string
  nombre_operador: string
  rut_operador: string
  firma_operador_url: string
  motivo: string
  patente_equipo_prueba?: string | null
  lectura_medidor_inicial_lt?: number | null
  lectura_medidor_final_lt?: number | null
  observacion?: string | null
  lat?: number | null
  lng?: number | null
  accuracy?: number | null
  geolocation_status?: string | null
  fecha_inicio?: string | null
  fecha_cierre?: string | null
}

export interface RecirculacionResult {
  success: boolean
  recirculacion_id: string
  folio: string
  estanque_codigo: string
  litros: number
  stock_no_cambia: number
  fecha_inicio: string
  fecha_cierre: string
}

export async function registrarRecirculacion(payload: RecirculacionPayload) {
  const { data, error } = await supabase.rpc('rpc_registrar_recirculacion_combustible', {
    p_estanque_id:                  payload.estanque_id,
    p_litros:                       payload.litros,
    p_equipo_prueba_descripcion:    payload.equipo_prueba_descripcion,
    p_foto_patente_equipo_url:      payload.foto_patente_equipo_url,
    p_foto_equipo_url:              payload.foto_equipo_url,
    p_foto_medidor_inicial_url:     payload.foto_medidor_inicial_url,
    p_foto_medidor_final_url:       payload.foto_medidor_final_url,
    p_nombre_operador:              payload.nombre_operador,
    p_rut_operador:                 payload.rut_operador,
    p_firma_operador_url:           payload.firma_operador_url,
    p_motivo:                       payload.motivo,
    p_patente_equipo_prueba:        payload.patente_equipo_prueba ?? null,
    p_lectura_medidor_inicial_lt:   payload.lectura_medidor_inicial_lt ?? null,
    p_lectura_medidor_final_lt:     payload.lectura_medidor_final_lt ?? null,
    p_observacion:                  payload.observacion ?? null,
    p_lat:                          payload.lat ?? null,
    p_lng:                          payload.lng ?? null,
    p_accuracy:                     payload.accuracy ?? null,
    p_geolocation_status:           payload.geolocation_status ?? null,
    p_fecha_inicio:                 payload.fecha_inicio ?? null,
    p_fecha_cierre:                 payload.fecha_cierre ?? null,
  })
  if (error) return { data: null, error }
  return { data: data as RecirculacionResult, error: null }
}

export interface RecirculacionRow {
  recirculacion_id: string
  folio: string
  fecha_inicio: string
  fecha_cierre: string
  estanque_id: string
  estanque_codigo: string
  estanque_nombre: string
  litros: number
  equipo_prueba_descripcion: string
  patente_equipo_prueba: string | null
  foto_patente_equipo_url: string
  foto_equipo_url: string
  lectura_medidor_inicial_lt: number | null
  lectura_medidor_final_lt: number | null
  foto_medidor_inicial_url: string
  foto_medidor_final_url: string
  nombre_operador: string
  rut_operador: string
  firma_operador_url: string
  motivo: string
  observacion: string | null
  operador: string | null
  created_at: string
}

export async function listarRecirculaciones(limit = 50) {
  const { data, error } = await supabase
    .from('v_combustible_recirculaciones')
    .select('*')
    .order('fecha_inicio', { ascending: false })
    .limit(limit)
  return { data: (data ?? []) as RecirculacionRow[], error }
}


// ============================================================================
// TRASPASO ENTRE ESTANQUES (MIG76)
// ============================================================================

export interface TraspasoPayload {
  estanque_origen_id: string
  estanque_destino_id: string
  litros: number
  foto_medidor_origen_inicial_url: string
  foto_medidor_origen_final_url: string
  foto_medidor_destino_inicial_url: string
  foto_medidor_destino_final_url: string
  foto_manguerado_url: string
  nombre_operador: string
  rut_operador: string
  firma_operador_url: string
  motivo: string
  lectura_medidor_origen_inicial?: number | null
  lectura_medidor_origen_final?: number | null
  lectura_medidor_destino_inicial?: number | null
  lectura_medidor_destino_final?: number | null
  observacion?: string | null
  lat?: number | null
  lng?: number | null
  accuracy?: number | null
  geolocation_status?: string | null
  fecha_traspaso?: string | null
}

export interface TraspasoResult {
  success: boolean
  traspaso_id: string
  folio: string
  origen_codigo: string
  destino_codigo: string
  litros: number
  cpp_origen: number
  cpp_destino_antes: number
  cpp_destino_despues: number
  stock_origen_antes: number
  stock_origen_despues: number
  stock_destino_antes: number
  stock_destino_despues: number
  costo_total: number
  kardex_salida_id: string
  kardex_entrada_id: string
}

export async function registrarTraspaso(payload: TraspasoPayload) {
  const { data, error } = await supabase.rpc('rpc_registrar_traspaso_combustible', {
    p_estanque_origen_id:              payload.estanque_origen_id,
    p_estanque_destino_id:             payload.estanque_destino_id,
    p_litros:                          payload.litros,
    p_foto_medidor_origen_inicial_url:  payload.foto_medidor_origen_inicial_url,
    p_foto_medidor_origen_final_url:    payload.foto_medidor_origen_final_url,
    p_foto_medidor_destino_inicial_url: payload.foto_medidor_destino_inicial_url,
    p_foto_medidor_destino_final_url:   payload.foto_medidor_destino_final_url,
    p_foto_manguerado_url:              payload.foto_manguerado_url,
    p_nombre_operador:                 payload.nombre_operador,
    p_rut_operador:                    payload.rut_operador,
    p_firma_operador_url:              payload.firma_operador_url,
    p_motivo:                          payload.motivo,
    p_lectura_medidor_origen_inicial:  payload.lectura_medidor_origen_inicial ?? null,
    p_lectura_medidor_origen_final:    payload.lectura_medidor_origen_final ?? null,
    p_lectura_medidor_destino_inicial: payload.lectura_medidor_destino_inicial ?? null,
    p_lectura_medidor_destino_final:   payload.lectura_medidor_destino_final ?? null,
    p_observacion:                     payload.observacion ?? null,
    p_lat:                             payload.lat ?? null,
    p_lng:                             payload.lng ?? null,
    p_accuracy:                        payload.accuracy ?? null,
    p_geolocation_status:              payload.geolocation_status ?? null,
    p_fecha_traspaso:                  payload.fecha_traspaso ?? null,
  })
  if (error) return { data: null, error }
  return { data: data as TraspasoResult, error: null }
}

export interface TraspasoRow {
  traspaso_id: string
  folio: string
  fecha_traspaso: string
  estanque_origen_id: string
  origen_codigo: string
  origen_nombre: string
  estanque_destino_id: string
  destino_codigo: string
  destino_nombre: string
  litros: number
  cpp_origen_snapshot: number
  costo_total_traspaso: number
  stock_origen_anterior: number
  stock_origen_nuevo: number
  stock_destino_anterior: number
  stock_destino_nuevo: number
  cpp_destino_anterior: number
  cpp_destino_nuevo: number
  nombre_operador: string
  rut_operador: string
  firma_operador_url: string
  motivo: string
  observacion: string | null
  operador: string | null
  created_at: string
}

export async function listarTraspasos(limit = 50) {
  const { data, error } = await supabase
    .from('v_combustible_traspasos')
    .select('*')
    .order('fecha_traspaso', { ascending: false })
    .limit(limit)
  return { data: (data ?? []) as TraspasoRow[], error }
}
