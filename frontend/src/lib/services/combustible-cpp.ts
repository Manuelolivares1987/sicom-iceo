import { supabase } from '@/lib/supabase'

// ── Tipos ───────────────────────────────────────────────────────────────────

export type EstadoControlCombustible =
  | 'cuadrado'
  | 'sin_varillaje'
  | 'varillaje_atrasado'
  | 'desviacion_fisica'
  | 'stock_negativo'

export interface EstanqueControlRow {
  estanque_id: string
  estanque_codigo: string
  estanque_nombre: string
  activo: boolean
  faena_id: string | null
  capacidad_lt: number
  stock_teorico_lt: number
  cpp_actual: number
  valor_teorico_clp: number
  fecha_ultimo_varillaje: string | null
  ultimo_varillaje_lt: number | null
  fecha_ultimo_movimiento: string | null
  tipo_ultimo_movimiento: string | null
  delta_lt: number | null
  delta_pct: number | null
  dias_desde_varilla: number | null
  estado: EstadoControlCombustible
  stock_minimo_alerta_lt: number
  bajo_minimo: boolean
}

export interface MovimientoCombustibleRow {
  kardex_id: string
  fecha_movimiento: string
  tipo_movimiento: string
  folio_movimiento: string | null
  estanque_id: string
  estanque_codigo: string
  estanque_nombre: string
  litros_entrada: number
  litros_salida: number
  costo_unitario_movimiento: number
  stock_lt_despues: number
  cpp_despues: number
  valor_stock_despues: number
  proveedor_id: string | null
  proveedor_nombre: string | null
  equipo_id: string | null
  equipo_codigo: string | null
  equipo_nombre: string | null
  ceco_id: string | null
  ceco_codigo: string | null
  ceco_nombre: string | null
  cliente_nombre_manual: string | null
  documento_numero: string | null
  observacion: string | null
  evidencia_url: string | null
  created_at: string
}

// ── Resumen ────────────────────────────────────────────────────────────────

export interface ResumenCombustible {
  total_litros: number
  valor_total_clp: number
  estanques_activos: number
  estanques_con_stock: number
  estanques_bajo_minimo: number
  varillaje_atrasado: number
  desviacion_fisica: number
  sin_varillaje: number
  stock_negativo: number
  fecha_ultimo_movimiento: string | null
}

export async function getResumenCombustible(): Promise<{ data: ResumenCombustible | null; error: unknown }> {
  const { data, error } = await supabase
    .from('v_combustible_control_kardex_varillaje')
    .select('*')
  if (error) return { data: null, error }
  const rows = (data ?? []) as EstanqueControlRow[]

  const resumen: ResumenCombustible = {
    total_litros: rows.filter((r) => r.activo).reduce((s, r) => s + Number(r.stock_teorico_lt || 0), 0),
    valor_total_clp: rows.filter((r) => r.activo).reduce((s, r) => s + Number(r.valor_teorico_clp || 0), 0),
    estanques_activos: rows.filter((r) => r.activo).length,
    estanques_con_stock: rows.filter((r) => r.activo && Number(r.stock_teorico_lt) > 0).length,
    estanques_bajo_minimo: rows.filter((r) => r.bajo_minimo && r.activo).length,
    varillaje_atrasado: rows.filter((r) => r.estado === 'varillaje_atrasado').length,
    desviacion_fisica: rows.filter((r) => r.estado === 'desviacion_fisica').length,
    sin_varillaje: rows.filter((r) => r.estado === 'sin_varillaje').length,
    stock_negativo: rows.filter((r) => r.estado === 'stock_negativo').length,
    fecha_ultimo_movimiento: rows.reduce<string | null>(
      (acc, r) => {
        if (!r.fecha_ultimo_movimiento) return acc
        if (!acc) return r.fecha_ultimo_movimiento
        return r.fecha_ultimo_movimiento > acc ? r.fecha_ultimo_movimiento : acc
      },
      null,
    ),
  }
  return { data: resumen, error: null }
}

// ── Queries ─────────────────────────────────────────────────────────────────

export async function getControlEstanques() {
  const { data, error } = await supabase
    .from('v_combustible_control_kardex_varillaje')
    .select('*')
    .order('estanque_codigo')
  return { data: data as EstanqueControlRow[] | null, error }
}

export interface FiltrosMovimientos {
  estanque_id?: string
  tipo?: string
  desde?: string
  hasta?: string
}

export async function getMovimientosValorizados(filtros?: FiltrosMovimientos, limit = 100) {
  let q = supabase.from('v_combustible_movimientos_valorizados').select('*')
  if (filtros?.estanque_id) q = q.eq('estanque_id', filtros.estanque_id)
  if (filtros?.tipo) q = q.eq('tipo_movimiento', filtros.tipo)
  if (filtros?.desde) q = q.gte('fecha_movimiento', filtros.desde)
  if (filtros?.hasta) q = q.lte('fecha_movimiento', filtros.hasta)
  const { data, error } = await q.order('fecha_movimiento', { ascending: false }).limit(limit)
  return { data: data as MovimientoCombustibleRow[] | null, error }
}

// ── Selectores auxiliares ───────────────────────────────────────────────────

export interface EstanqueMini {
  id: string
  codigo: string
  nombre: string
  capacidad_lt: number
  stock_teorico_lt: number
  costo_promedio_lt: number
  faena_id: string | null
  activo: boolean
}

export async function listarEstanquesActivos() {
  const { data, error } = await supabase
    .from('combustible_estanques')
    .select('id, codigo, nombre, capacidad_lt, stock_teorico_lt, costo_promedio_lt, faena_id, activo')
    .eq('activo', true)
    .order('codigo')
  return { data: data as EstanqueMini[] | null, error }
}

export interface ProveedorCombustibleMini {
  id: string
  codigo: string
  nombre: string
  rut: string | null
}

export async function listarProveedoresCombustible() {
  const { data, error } = await supabase
    .from('proveedores')
    .select('id, codigo, nombre, rut')
    .eq('activo', true)
    .in('tipo', ['combustible', 'otros'])
    .order('nombre')
  return { data: data as ProveedorCombustibleMini[] | null, error }
}

export interface FaenaMini {
  id: string
  codigo: string | null
  nombre: string
}

export async function listarFaenas() {
  const { data, error } = await supabase
    .from('faenas')
    .select('id, codigo, nombre')
    .order('nombre')
  return { data: data as FaenaMini[] | null, error }
}

export interface ActivoMini {
  id: string
  codigo: string
  nombre: string
  tipo: string | null
}

export async function listarActivos() {
  const { data, error } = await supabase
    .from('activos')
    .select('id, codigo, nombre, tipo')
    .order('codigo')
  return { data: data as ActivoMini[] | null, error }
}

// ── RPCs ───────────────────────────────────────────────────────────────────

export interface IngresoCombustiblePayload {
  estanque_id: string
  litros: number
  costo_unitario_clp: number
  proveedor_id?: string | null
  doc_tipo?: string | null
  doc_numero?: string | null
  fecha_movimiento?: string | null
  observacion?: string | null
  evidencia_url?: string | null
  // MIG65: evidencia visual (foto patente camion + 2 fotos medidor)
  foto_patente_url?:         string | null
  foto_medidor_inicial_url?: string | null
  foto_medidor_final_url?:   string | null
  // MIG66: geo de cada foto + lecturas medidor estanque
  foto_patente_lat?:           number | null
  foto_patente_lon?:           number | null
  foto_patente_ts?:            string | null
  foto_medidor_inicial_lat?:   number | null
  foto_medidor_inicial_lon?:   number | null
  foto_medidor_inicial_ts?:    string | null
  foto_medidor_final_lat?:     number | null
  foto_medidor_final_lon?:     number | null
  foto_medidor_final_ts?:      string | null
  lectura_medidor_inicial_lt?: number | null
  lectura_medidor_final_lt?:   number | null
}

export interface IngresoCombustibleResult {
  success: boolean
  kardex_id: string
  folio: string
  estanque_codigo: string
  litros_ingresados: number
  costo_unitario_ingreso: number
  cpp_anterior: number
  cpp_nuevo: number
  stock_anterior: number
  stock_nuevo: number
  valor_anterior: number
  valor_nuevo: number
}

export async function registrarIngresoCombustible(payload: IngresoCombustiblePayload) {
  const { data, error } = await supabase.rpc('rpc_registrar_ingreso_combustible_valorizado', {
    p_estanque_id:        payload.estanque_id,
    p_litros:             payload.litros,
    p_costo_unitario_clp: payload.costo_unitario_clp,
    p_proveedor_id:       payload.proveedor_id ?? null,
    p_doc_tipo:           payload.doc_tipo ?? null,
    p_doc_numero:         payload.doc_numero ?? null,
    p_fecha_movimiento:   payload.fecha_movimiento ?? null,
    p_observacion:        payload.observacion ?? null,
    p_evidencia_url:      payload.evidencia_url ?? null,
    p_foto_patente_url:         payload.foto_patente_url ?? null,
    p_foto_medidor_inicial_url: payload.foto_medidor_inicial_url ?? null,
    p_foto_medidor_final_url:   payload.foto_medidor_final_url ?? null,
    p_foto_patente_lat:           payload.foto_patente_lat ?? null,
    p_foto_patente_lon:           payload.foto_patente_lon ?? null,
    p_foto_patente_ts:            payload.foto_patente_ts ?? null,
    p_foto_medidor_inicial_lat:   payload.foto_medidor_inicial_lat ?? null,
    p_foto_medidor_inicial_lon:   payload.foto_medidor_inicial_lon ?? null,
    p_foto_medidor_inicial_ts:    payload.foto_medidor_inicial_ts ?? null,
    p_foto_medidor_final_lat:     payload.foto_medidor_final_lat ?? null,
    p_foto_medidor_final_lon:     payload.foto_medidor_final_lon ?? null,
    p_foto_medidor_final_ts:      payload.foto_medidor_final_ts ?? null,
    p_lectura_medidor_inicial_lt: payload.lectura_medidor_inicial_lt ?? null,
    p_lectura_medidor_final_lt:   payload.lectura_medidor_final_lt ?? null,
  })
  if (error) return { data: null, error }
  return { data: data as IngresoCombustibleResult, error: null }
}

export type DestinoSalidaCombustible =
  | 'equipo' | 'ot' | 'ceco' | 'faena' | 'consumo_interno' | 'venta_externa'

export interface SalidaCombustiblePayload {
  estanque_id: string
  litros: number
  destino_tipo: DestinoSalidaCombustible
  motivo: string
  equipo_id?: string | null
  ot_id?: string | null
  ceco_id?: string | null
  faena_id?: string | null
  cliente_nombre?: string | null
  fecha_movimiento?: string | null
  observacion?: string | null
  evidencia_url?: string | null
  // MIG64: vehiculo externo + fotos + receptor
  vehiculo_externo_id?:      string | null
  foto_medidor_inicial_url?: string | null
  foto_medidor_final_url?:   string | null
  foto_patente_url?:         string | null
  firma_receptor_url?:       string | null
  nombre_receptor?:          string | null
  rut_receptor?:             string | null
  // MIG66: geo de cada foto + lecturas medidor estanque
  foto_patente_lat?:           number | null
  foto_patente_lon?:           number | null
  foto_patente_ts?:            string | null
  foto_medidor_inicial_lat?:   number | null
  foto_medidor_inicial_lon?:   number | null
  foto_medidor_inicial_ts?:    string | null
  foto_medidor_final_lat?:     number | null
  foto_medidor_final_lon?:     number | null
  foto_medidor_final_ts?:      string | null
  lectura_medidor_inicial_lt?: number | null
  lectura_medidor_final_lt?:   number | null
}

export interface SalidaCombustibleResult {
  success: boolean
  kardex_id: string
  folio: string
  estanque_codigo: string
  litros_salida: number
  destino_tipo: string
  cpp_vigente: number
  costo_total: number
  stock_anterior: number
  stock_nuevo: number
  tipo_movimiento_kardex: string
}

// ── Despacho con sellos (MIG41) ────────────────────────────────────────────

export interface DespachoSellosPayload {
  estanque_id: string
  litros: number
  destino_tipo: DestinoSalidaCombustible
  sello_inicial: string
  sello_final: string
  motivo: string
  equipo_id?: string | null
  ot_id?: string | null
  ceco_id?: string | null
  faena_id?: string | null
  cliente_nombre?: string | null
  receptor_nombre?: string | null
  receptor_rut?: string | null
  foto_sello_inicial_url?: string | null
  foto_sello_final_url?: string | null
  foto_odometro_url?: string | null
  foto_equipo_url?: string | null
  firma_receptor_url?: string | null
  lat?: number | null
  lng?: number | null
  accuracy?: number | null
  geolocation_status?: string | null
  fecha_movimiento?: string | null
  observacion?: string | null
  evidencia_url?: string | null
}

export interface DespachoSellosResult {
  success: boolean
  despacho_id: string
  movimiento_id: string
  folio_movimiento: string
  stock_final: number
  cpp_usado: number
  costo_total: number
  destino_tipo: string
  litros: number
}

export interface DespachoSellosRow {
  despacho_id: string
  fecha: string
  movimiento_combustible_id: string | null
  folio_movimiento: string | null
  fecha_movimiento: string | null
  estanque_id: string
  estanque_codigo: string
  estanque_nombre: string
  destino_tipo: string
  litros: number
  cpp_usado: number | null
  costo_total: number
  sello_inicial: string
  sello_final: string
  foto_sello_inicial_url: string | null
  foto_sello_final_url: string | null
  foto_odometro_url: string | null
  foto_equipo_url: string | null
  receptor_nombre: string | null
  receptor_rut: string | null
  firma_receptor_url: string | null
  equipo_id: string | null
  equipo_codigo: string | null
  equipo_nombre: string | null
  ot_id: string | null
  ot_folio: string | null
  ceco_id: string | null
  ceco_codigo: string | null
  ceco_nombre: string | null
  faena_id: string | null
  faena_nombre: string | null
  operador_id: string | null
  operador: string | null
  observacion: string | null
}

export async function registrarDespachoConSellos(payload: DespachoSellosPayload) {
  const { data, error } = await supabase.rpc('rpc_registrar_despacho_combustible_con_sellos', {
    p_estanque_id:            payload.estanque_id,
    p_litros:                 payload.litros,
    p_destino_tipo:           payload.destino_tipo,
    p_sello_inicial:          payload.sello_inicial,
    p_sello_final:            payload.sello_final,
    p_motivo:                 payload.motivo,
    p_equipo_id:              payload.equipo_id ?? null,
    p_ot_id:                  payload.ot_id ?? null,
    p_ceco_id:                payload.ceco_id ?? null,
    p_faena_id:               payload.faena_id ?? null,
    p_cliente_nombre:         payload.cliente_nombre ?? null,
    p_receptor_nombre:        payload.receptor_nombre ?? null,
    p_receptor_rut:           payload.receptor_rut ?? null,
    p_foto_sello_inicial_url: payload.foto_sello_inicial_url ?? null,
    p_foto_sello_final_url:   payload.foto_sello_final_url ?? null,
    p_foto_odometro_url:      payload.foto_odometro_url ?? null,
    p_foto_equipo_url:        payload.foto_equipo_url ?? null,
    p_firma_receptor_url:     payload.firma_receptor_url ?? null,
    p_lat:                    payload.lat ?? null,
    p_lng:                    payload.lng ?? null,
    p_accuracy:               payload.accuracy ?? null,
    p_geolocation_status:     payload.geolocation_status ?? null,
    p_fecha_movimiento:       payload.fecha_movimiento ?? null,
    p_observacion:            payload.observacion ?? null,
    p_evidencia_url:          payload.evidencia_url ?? null,
  })
  if (error) return { data: null, error }
  return { data: data as DespachoSellosResult, error: null }
}

export async function listarDespachosConSellos(limit = 50) {
  const { data, error } = await supabase
    .from('v_combustible_despachos_con_sellos')
    .select('*')
    .order('fecha', { ascending: false })
    .limit(limit)
  return { data: data as DespachoSellosRow[] | null, error }
}

export async function registrarSalidaCombustible(payload: SalidaCombustiblePayload) {
  const { data, error } = await supabase.rpc('rpc_registrar_salida_combustible_valorizada', {
    p_estanque_id:      payload.estanque_id,
    p_litros:           payload.litros,
    p_destino_tipo:     payload.destino_tipo,
    p_motivo:           payload.motivo,
    p_equipo_id:        payload.equipo_id ?? null,
    p_ot_id:            payload.ot_id ?? null,
    p_ceco_id:          payload.ceco_id ?? null,
    p_faena_id:         payload.faena_id ?? null,
    p_cliente_nombre:   payload.cliente_nombre ?? null,
    p_fecha_movimiento: payload.fecha_movimiento ?? null,
    p_observacion:      payload.observacion ?? null,
    p_evidencia_url:    payload.evidencia_url ?? null,
    // MIG64
    p_vehiculo_externo_id:      payload.vehiculo_externo_id ?? null,
    p_foto_medidor_inicial_url: payload.foto_medidor_inicial_url ?? null,
    p_foto_medidor_final_url:   payload.foto_medidor_final_url ?? null,
    p_foto_patente_url:         payload.foto_patente_url ?? null,
    p_firma_receptor_url:       payload.firma_receptor_url ?? null,
    p_nombre_receptor:          payload.nombre_receptor ?? null,
    p_rut_receptor:             payload.rut_receptor ?? null,
    p_foto_patente_lat:           payload.foto_patente_lat ?? null,
    p_foto_patente_lon:           payload.foto_patente_lon ?? null,
    p_foto_patente_ts:            payload.foto_patente_ts ?? null,
    p_foto_medidor_inicial_lat:   payload.foto_medidor_inicial_lat ?? null,
    p_foto_medidor_inicial_lon:   payload.foto_medidor_inicial_lon ?? null,
    p_foto_medidor_inicial_ts:    payload.foto_medidor_inicial_ts ?? null,
    p_foto_medidor_final_lat:     payload.foto_medidor_final_lat ?? null,
    p_foto_medidor_final_lon:     payload.foto_medidor_final_lon ?? null,
    p_foto_medidor_final_ts:      payload.foto_medidor_final_ts ?? null,
    p_lectura_medidor_inicial_lt: payload.lectura_medidor_inicial_lt ?? null,
    p_lectura_medidor_final_lt:   payload.lectura_medidor_final_lt ?? null,
  })
  if (error) return { data: null, error }
  return { data: data as SalidaCombustibleResult, error: null }
}

// ── MIG66: propuesta de litros (historico ultimos 5 despachos al equipo) ──
export interface PropuestaLitrosEquipo {
  equipo_id:  string
  n_muestras: number
  promedio:   number
  stddev:     number
  minimo:     number
  maximo:     number
  ultimos:    Array<{ lt: number; fecha: string }>
}
export async function getPropuestaLitrosEquipo(equipoId: string) {
  const { data, error } = await supabase.rpc('rpc_propuesta_litros_equipo', { p_equipo_id: equipoId })
  if (error) return { data: null, error }
  return { data: data as PropuestaLitrosEquipo, error: null }
}

// ── MIG49: anular ingreso de combustible (corregir precio mal cargado) ─────

export interface IngresoAnulableRow {
  kardex_id: string
  estanque_id: string
  estanque_codigo: string
  estanque_nombre: string
  fecha_movimiento: string
  folio_movimiento: string | null
  litros: number
  precio_unitario: number
  valor_ingreso: number
  proveedor_id: string | null
  proveedor_nombre: string | null
  documento_numero: string | null
  observacion: string | null
  created_at: string
  created_by: string | null
  tiene_posteriores: boolean
}

export interface AnularIngresoResult {
  success: boolean
  kardex_id: string
  estanque_id: string
  litros_revertidos: number
  cpp_restaurado: number
  stock_restaurado: number
  anulado_at: string
  anulado_by: string
}

export async function getIngresosAnulables(estanqueId?: string | null) {
  let q = supabase
    .from('v_combustible_ingresos_anulables')
    .select('*')
    .order('fecha_movimiento', { ascending: false })
  if (estanqueId) q = q.eq('estanque_id', estanqueId)
  const { data, error } = await q
  return { data: (data ?? []) as IngresoAnulableRow[], error }
}

export async function anularIngresoCombustible(kardexId: string, motivo: string) {
  const { data, error } = await supabase.rpc('rpc_anular_ingreso_combustible', {
    p_kardex_id: kardexId,
    p_motivo:    motivo,
  })
  if (error) return { data: null, error }
  return { data: data as AnularIngresoResult, error: null }
}
