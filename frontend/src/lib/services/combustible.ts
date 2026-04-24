import { supabase } from '@/lib/supabase'

// ── Tipos ────────────────────────────────────────────────

export type TipoMovimientoCombustible = 'ingreso' | 'despacho' | 'ajuste' | 'merma'
export type TipoMedidor = 'ingreso' | 'despacho' | 'bidireccional'
export type DestinoDespacho = 'vehiculo_flota' | 'equipo_externo' | 'bidon' | 'otro'

export interface Estanque {
  id: string
  codigo: string
  nombre: string
  capacidad_lt: number
  faena_id: string | null
  ubicacion_detalle: string | null
  stock_teorico_lt: number
  stock_minimo_alerta_lt: number
  activo: boolean
  observaciones: string | null
  created_at: string
  updated_at: string
}

export interface EstanqueResumen {
  id: string
  codigo: string
  nombre: string
  capacidad_lt: number
  stock_teorico_lt: number
  stock_minimo_alerta_lt: number
  faena_id: string | null
  faena_nombre: string | null
  ubicacion_detalle: string | null
  activo: boolean
  pct_llenado: number | null
  bajo_minimo: boolean
  n_medidores: number
  ultima_varillaje_fecha: string | null
  ultima_varillaje_diferencia: number | null
}

export interface Medidor {
  id: string
  estanque_id: string
  tipo: TipoMedidor
  marca: string | null
  modelo: string | null
  numero_serie: string | null
  lectura_acumulada_actual: number
  fecha_ultima_lectura: string | null
  foto_registro_url: string | null
  activo: boolean
  observaciones: string | null
  created_at: string
  updated_at: string
}

export interface MovimientoCombustible {
  id: string
  tipo: TipoMovimientoCombustible
  fecha_hora: string
  litros: number
  lectura_inicial_lt: number | null
  lectura_final_lt: number | null
  foto_medidor_url: string | null
  estanque_id: string
  estanque_codigo: string
  estanque_nombre: string
  medidor_id: string | null
  operador_id: string | null
  operador_nombre: string | null
  proveedor: string | null
  numero_factura: string | null
  costo_unitario_clp: number | null
  costo_total_clp: number | null
  destino_tipo: DestinoDespacho | null
  vehiculo_activo_id: string | null
  vehiculo_codigo: string | null
  vehiculo_nombre: string | null
  destino_descripcion: string | null
  horometro_vehiculo: number | null
  kilometraje_vehiculo: number | null
  observaciones: string | null
  created_at: string
}

export interface Varillaje {
  id: string
  estanque_id: string
  fecha: string
  turno: string | null
  medicion_fisica_lt: number
  stock_teorico_snapshot_lt: number
  diferencia_lt: number
  ajuste_movimiento_id: string | null
  operador_id: string | null
  foto_varilla_url: string | null
  observaciones: string | null
  created_at: string
}

export interface ConsumoVehiculoMes {
  activo_id: string
  activo_codigo: string
  activo_nombre: string | null
  tipo_activo: string
  mes: string
  litros_total: number
  n_despachos: number
  horometro_max: number | null
  horometro_min: number | null
  km_max: number | null
  km_min: number | null
  km_por_litro: number | null
}

// ── Estanques ────────────────────────────────────────────

export async function getEstanques() {
  const { data, error } = await supabase
    .from('v_combustible_estanques_resumen')
    .select('*')
    .order('codigo')
  return { data: data as EstanqueResumen[] | null, error }
}

export async function getEstanqueById(id: string) {
  const { data, error } = await supabase
    .from('v_combustible_estanques_resumen')
    .select('*')
    .eq('id', id)
    .single()
  return { data: data as EstanqueResumen | null, error }
}

// ── Medidores ────────────────────────────────────────────

export async function getMedidoresByEstanque(estanqueId: string) {
  const { data, error } = await supabase
    .from('combustible_medidores')
    .select('*')
    .eq('estanque_id', estanqueId)
    .eq('activo', true)
    .order('created_at')
  return { data: data as Medidor[] | null, error }
}

export interface MedidorConEstanque extends Medidor {
  estanque_codigo: string
  estanque_nombre: string
}

export async function getAllMedidores() {
  const { data, error } = await supabase
    .from('combustible_medidores')
    .select('*, estanque:combustible_estanques(codigo, nombre)')
    .order('created_at')
  if (error || !data) return { data: null as MedidorConEstanque[] | null, error }
  const mapped = (data as any[]).map((m) => ({
    ...m,
    estanque_codigo: m.estanque?.codigo ?? '',
    estanque_nombre: m.estanque?.nombre ?? '',
  })) as MedidorConEstanque[]
  return { data: mapped, error: null }
}

export async function updateMedidor(
  id: string,
  patch: Partial<{
    tipo: TipoMedidor
    marca: string | null
    modelo: string | null
    numero_serie: string | null
    activo: boolean
    observaciones: string | null
  }>
) {
  const { data, error } = await supabase
    .from('combustible_medidores')
    .update(patch)
    .eq('id', id)
    .select()
    .single()
  return { data: data as Medidor | null, error }
}

export async function deleteMedidor(id: string) {
  const { count } = await supabase
    .from('combustible_movimientos')
    .select('id', { count: 'exact', head: true })
    .eq('medidor_id', id)
  if ((count ?? 0) > 0) {
    return {
      data: null,
      error: new Error('No se puede eliminar: el medidor tiene movimientos registrados. Desactivalo en su lugar.'),
    }
  }
  const { error } = await supabase.from('combustible_medidores').delete().eq('id', id)
  return { data: !error, error }
}

export async function crearMedidor(payload: {
  estanque_id: string
  tipo?: TipoMedidor
  marca?: string | null
  modelo?: string | null
  numero_serie?: string | null
  lectura_acumulada_actual: number
  foto_registro_url: string
}) {
  const { data, error } = await supabase
    .from('combustible_medidores')
    .insert({
      estanque_id: payload.estanque_id,
      tipo: payload.tipo ?? 'bidireccional',
      marca: payload.marca ?? null,
      modelo: payload.modelo ?? null,
      numero_serie: payload.numero_serie ?? null,
      lectura_acumulada_actual: payload.lectura_acumulada_actual,
      foto_registro_url: payload.foto_registro_url,
    })
    .select()
    .single()
  return { data: data as Medidor | null, error }
}

// ── Movimientos ──────────────────────────────────────────

export interface MovimientoFiltros {
  estanque_id?: string
  tipo?: TipoMovimientoCombustible
  vehiculo_activo_id?: string
  fecha_desde?: string
  fecha_hasta?: string
  limit?: number
}

export async function getMovimientos(filtros?: MovimientoFiltros) {
  let q = supabase
    .from('v_combustible_movimientos_lista')
    .select('*')
    .order('fecha_hora', { ascending: false })

  if (filtros?.estanque_id) q = q.eq('estanque_id', filtros.estanque_id)
  if (filtros?.tipo) q = q.eq('tipo', filtros.tipo)
  if (filtros?.vehiculo_activo_id) q = q.eq('vehiculo_activo_id', filtros.vehiculo_activo_id)
  if (filtros?.fecha_desde) q = q.gte('fecha_hora', filtros.fecha_desde)
  if (filtros?.fecha_hasta) q = q.lte('fecha_hora', filtros.fecha_hasta)
  if (filtros?.limit) q = q.limit(filtros.limit)

  const { data, error } = await q
  return { data: data as MovimientoCombustible[] | null, error }
}

export interface RegistrarMovimientoPayload {
  tipo: TipoMovimientoCombustible
  estanque_id: string
  medidor_id: string
  lectura_inicial_lt: number
  lectura_final_lt: number
  foto_medidor_url?: string | null
  // ingreso
  proveedor?: string | null
  numero_factura?: string | null
  costo_unitario_clp?: number | null
  // despacho
  destino_tipo?: DestinoDespacho | null
  vehiculo_activo_id?: string | null
  destino_descripcion?: string | null
  horometro_vehiculo?: number | null
  kilometraje_vehiculo?: number | null
  observaciones?: string | null
}

export async function registrarMovimiento(payload: RegistrarMovimientoPayload) {
  const { data, error } = await supabase.rpc('fn_registrar_movimiento_combustible', {
    p_tipo: payload.tipo,
    p_estanque_id: payload.estanque_id,
    p_medidor_id: payload.medidor_id,
    p_lectura_inicial_lt: payload.lectura_inicial_lt,
    p_lectura_final_lt: payload.lectura_final_lt,
    p_foto_medidor_url: payload.foto_medidor_url ?? null,
    p_proveedor: payload.proveedor ?? null,
    p_numero_factura: payload.numero_factura ?? null,
    p_costo_unitario_clp: payload.costo_unitario_clp ?? null,
    p_destino_tipo: payload.destino_tipo ?? null,
    p_vehiculo_activo_id: payload.vehiculo_activo_id ?? null,
    p_destino_descripcion: payload.destino_descripcion ?? null,
    p_horometro_vehiculo: payload.horometro_vehiculo ?? null,
    p_kilometraje_vehiculo: payload.kilometraje_vehiculo ?? null,
    p_observaciones: payload.observaciones ?? null,
  })
  return {
    data: data as {
      success: boolean
      movimiento_id: string
      litros: number
      stock_teorico: number
      costo_total_clp: number | null
    } | null,
    error,
  }
}

// ── Varillaje ────────────────────────────────────────────

export async function getVarillajesByEstanque(estanqueId: string, limit = 30) {
  const { data, error } = await supabase
    .from('combustible_varillaje')
    .select('*')
    .eq('estanque_id', estanqueId)
    .order('fecha', { ascending: false })
    .order('created_at', { ascending: false })
    .limit(limit)
  return { data: data as Varillaje[] | null, error }
}

export interface RegistrarVarillajePayload {
  estanque_id: string
  medicion_fisica_lt: number
  turno?: string | null
  generar_ajuste?: boolean
  foto_varilla_url?: string | null
  observaciones?: string | null
}

export async function registrarVarillaje(payload: RegistrarVarillajePayload) {
  const { data, error } = await supabase.rpc('fn_registrar_varillaje_combustible', {
    p_estanque_id: payload.estanque_id,
    p_medicion_fisica_lt: payload.medicion_fisica_lt,
    p_turno: payload.turno ?? null,
    p_generar_ajuste: payload.generar_ajuste ?? false,
    p_foto_varilla_url: payload.foto_varilla_url ?? null,
    p_observaciones: payload.observaciones ?? null,
  })
  return {
    data: data as {
      success: boolean
      varillaje_id: string
      teorico_lt: number
      fisico_lt: number
      diferencia_lt: number
      ajuste_id: string | null
    } | null,
    error,
  }
}

// ── Rendimiento ──────────────────────────────────────────

export async function getConsumoVehiculoMes(mesISO?: string) {
  let q = supabase.from('v_combustible_consumo_vehiculo_mes').select('*')
  if (mesISO) q = q.eq('mes', mesISO)
  const { data, error } = await q.order('litros_total', { ascending: false })
  return { data: data as ConsumoVehiculoMes[] | null, error }
}

// ── Upload foto ──────────────────────────────────────────
// Devuelve la URL publica. Guardada bajo path: {tipo}/{estanqueId}/{timestamp}-{filename}

export async function uploadEvidenciaCombustible(
  file: File,
  opts: { tipo: 'medidor' | 'varillaje'; estanqueId: string }
): Promise<{ url: string | null; error: Error | null }> {
  const safeName = file.name.replace(/[^a-zA-Z0-9._-]/g, '_')
  const path = `${opts.tipo}/${opts.estanqueId}/${Date.now()}-${safeName}`
  const { error } = await supabase.storage
    .from('evidencias-combustible')
    .upload(path, file, { cacheControl: '3600', upsert: false })
  if (error) return { url: null, error }
  const { data } = supabase.storage.from('evidencias-combustible').getPublicUrl(path)
  return { url: data.publicUrl, error: null }
}
