import { supabase } from '@/lib/supabase'

// ── Types ────────────────────────────────────────────────

export interface EstadoDiarioFlota {
  id: string
  activo_id: string
  fecha: string
  estado_codigo: string
  conductor_id?: string
  cliente?: string
  ubicacion?: string
  operacion?: string
  horas_operativas: number
  horas_disponibles: number
  horas_mantencion: number
  km_recorridos: number
  observacion?: string
  registrado_por?: string
  created_at: string
  // Joined fields
  activo?: {
    id: string
    patente: string
    codigo: string
    nombre: string
    tipo: string
    estado: string
    estado_comercial: string
    anio_fabricacion: number
    operacion: string
    cliente_actual: string
    modelo?: { nombre: string; marca?: { nombre: string } }
  }
}

export interface OEEResult {
  activo_id: string
  patente: string
  disponibilidad_mecanica: number
  utilizacion_operativa: number
  calidad_servicio: number
  oee: number
  dias_periodo: number
  dias_operativos: number
  dias_mantencion: number
  dias_fuera_servicio: number
  horas_productivas: number
  horas_disponibles: number
  servicios_totales: number
  servicios_no_conformes: number
}

export interface OEEFlotaResult {
  operacion: string
  total_equipos: number
  disponibilidad_promedio: number
  utilizacion_promedio: number
  calidad_promedio: number
  oee_promedio: number
  clasificacion: string
}

export interface ResumenDiarioFlota {
  fecha: string
  operacion: string
  total_equipos: number
  arrendados: number
  disponibles: number
  uso_interno: number
  leasing: number
  en_mantencion: number
  en_terreno: number
  fuera_servicio: number
  en_habilitacion: number
  en_recepcion: number
  en_venta: number
  disponibilidad_mecanica_pct: number
  tasa_arriendo_pct: number
}

export interface NoConformidad {
  id: string
  activo_id: string
  tipo: string
  descripcion: string
  fecha_evento: string
  severidad: string
  resuelto: boolean
  accion_correctiva?: string
  created_at: string
}

export interface Conductor {
  id: string
  rut: string
  nombre_completo: string
  tipo_licencia: string
  licencia_vencimiento?: string
  semep_vigente: boolean
  semep_vencimiento?: string
  cert_sustancias_peligrosas: boolean
  induccion_faena: boolean
  horas_espera_mes_actual: number
  activo: boolean
}

export interface VerificacionDisponibilidad {
  id: string
  activo_id: string
  ot_id?: string
  resultado: string
  items_total?: number
  items_ok?: number
  items_no_ok?: number
  fecha_verificacion?: string
  vigente_hasta?: string
  verificado_por?: string
  aprobado_por?: string
}

// ── Estado Diario ──────────────────────────────────────

export interface EstadoDiarioFilters {
  fecha_inicio?: string
  fecha_fin?: string
  operacion?: string
  estado_codigo?: string
}

export async function getEstadoDiario(filters?: EstadoDiarioFilters) {
  let query = supabase
    .from('estado_diario_flota')
    .select('*, activo:activos(id, patente, codigo, nombre, tipo, estado, estado_comercial, anio_fabricacion, operacion, cliente_actual, modelo:modelos(nombre, marca:marcas(nombre)))')

  if (filters?.fecha_inicio) {
    query = query.gte('fecha', filters.fecha_inicio)
  }
  if (filters?.fecha_fin) {
    query = query.lte('fecha', filters.fecha_fin)
  }
  if (filters?.operacion) {
    query = query.eq('operacion', filters.operacion)
  }
  if (filters?.estado_codigo) {
    query = query.eq('estado_codigo', filters.estado_codigo)
  }

  const { data, error } = await query.order('fecha', { ascending: false })
  return { data: data as EstadoDiarioFlota[] | null, error }
}

export async function upsertEstadoDiario(registro: {
  activo_id: string
  fecha: string
  estado_codigo: string
  conductor_id?: string
  cliente?: string
  ubicacion?: string
  operacion?: string
  horas_operativas?: number
  horas_disponibles?: number
  horas_mantencion?: number
  km_recorridos?: number
  observacion?: string
}) {
  const { data, error } = await supabase
    .from('estado_diario_flota')
    .upsert(registro, { onConflict: 'activo_id,fecha' })
    .select()
    .single()

  return { data, error }
}

export async function upsertEstadoDiarioBatch(registros: Array<{
  activo_id: string
  fecha: string
  estado_codigo: string
  operacion?: string
  cliente?: string
  ubicacion?: string
  observacion?: string
}>) {
  const { data, error } = await supabase
    .from('estado_diario_flota')
    .upsert(registros, { onConflict: 'activo_id,fecha' })
    .select()

  return { data, error }
}

// ── Resumen Diario (Vista) ─────────────────────────────

export async function getResumenDiario(fechaInicio: string, fechaFin: string, operacion?: string) {
  let query = supabase
    .from('v_resumen_diario_flota')
    .select('*')
    .gte('fecha', fechaInicio)
    .lte('fecha', fechaFin)

  if (operacion) {
    query = query.eq('operacion', operacion)
  }

  const { data, error } = await query.order('fecha', { ascending: true })
  return { data: data as ResumenDiarioFlota[] | null, error }
}

// ── OEE ────────────────────────────────────────────────

export async function calcularOEEActivo(activoId: string, fechaInicio: string, fechaFin: string) {
  const { data, error } = await supabase.rpc('calcular_oee_activo', {
    p_activo_id: activoId,
    p_fecha_inicio: fechaInicio,
    p_fecha_fin: fechaFin,
  })
  return { data: data as OEEResult[] | null, error }
}

export async function calcularOEEFlota(
  fechaInicio: string,
  fechaFin: string,
  contratoId?: string,
  operacion?: string
) {
  const { data, error } = await supabase.rpc('calcular_oee_flota', {
    p_contrato_id: contratoId ?? null,
    p_fecha_inicio: fechaInicio,
    p_fecha_fin: fechaFin,
    p_operacion: operacion ?? null,
  })
  return { data: data as OEEFlotaResult[] | null, error }
}

// ── Verificaciones de Disponibilidad ───────────────────

export async function getVerificacionesActivo(activoId: string) {
  const { data, error } = await supabase
    .from('verificaciones_disponibilidad')
    .select('*')
    .eq('activo_id', activoId)
    .order('created_at', { ascending: false })

  return { data: data as VerificacionDisponibilidad[] | null, error }
}

export async function getVerificacionVigente(activoId: string) {
  const { data, error } = await supabase
    .from('verificaciones_disponibilidad')
    .select('*')
    .eq('activo_id', activoId)
    .eq('resultado', 'aprobado')
    .gte('vigente_hasta', new Date().toISOString())
    .order('vigente_hasta', { ascending: false })
    .limit(1)
    .maybeSingle()

  return { data: data as VerificacionDisponibilidad | null, error }
}

// ── No Conformidades ───────────────────────────────────

export async function getNoConformidades(filters?: {
  activo_id?: string
  fecha_inicio?: string
  fecha_fin?: string
  resuelto?: boolean
}) {
  let query = supabase
    .from('no_conformidades')
    .select('*, activo:activos(patente, nombre, codigo)')

  if (filters?.activo_id) query = query.eq('activo_id', filters.activo_id)
  if (filters?.fecha_inicio) query = query.gte('fecha_evento', filters.fecha_inicio)
  if (filters?.fecha_fin) query = query.lte('fecha_evento', filters.fecha_fin)
  if (filters?.resuelto !== undefined) query = query.eq('resuelto', filters.resuelto)

  const { data, error } = await query.order('fecha_evento', { ascending: false })
  return { data, error }
}

export async function createNoConformidad(nc: {
  activo_id: string
  tipo: string
  descripcion: string
  fecha_evento: string
  severidad?: string
}) {
  const { data, error } = await supabase
    .from('no_conformidades')
    .insert(nc)
    .select()
    .single()

  return { data, error }
}

// ── Conductores ────────────────────────────────────────

export async function getConductores(activos?: boolean) {
  let query = supabase.from('conductores').select('*')
  if (activos !== undefined) query = query.eq('activo', activos)
  const { data, error } = await query.order('nombre_completo')
  return { data: data as Conductor[] | null, error }
}

// ── Alertas Normativas ─────────────────────────────────

export async function ejecutarVerificacionesNormativas() {
  const { data, error } = await supabase.rpc('fn_ejecutar_verificaciones_normativas')
  return { data, error }
}

// ── Flota: activos con campos extendidos ───────────────

export async function getFlotaVehicular() {
  const { data, error } = await supabase
    .from('activos')
    .select('*, modelo:modelos(nombre, marca:marcas(nombre)), contrato:contratos(id, codigo, nombre, cliente)')
    .in('tipo', ['camion_cisterna', 'camion', 'camioneta', 'lubrimovil', 'equipo_menor'])
    .neq('estado', 'dado_baja')
    .order('codigo')

  return { data, error }
}

// ── Estado Nomenclatura ────────────────────────────────

export const ESTADO_DIARIO_LABELS: Record<string, string> = {
  A: 'Arrendado',
  D: 'Disponible',
  H: 'En Habilitación',
  R: 'En Recepción',
  M: 'Mantención (>1 día)',
  T: 'Mantención (<1 día)',
  F: 'Fuera de Servicio',
  V: 'En Venta',
  U: 'Uso Interno',
  L: 'Leasing',
}

export const ESTADO_DIARIO_COLORS: Record<string, string> = {
  A: 'bg-green-500 text-white',
  D: 'bg-blue-500 text-white',
  H: 'bg-amber-400 text-amber-900',
  R: 'bg-purple-500 text-white',
  M: 'bg-orange-500 text-white',
  T: 'bg-yellow-500 text-yellow-900',
  F: 'bg-red-600 text-white',
  V: 'bg-gray-500 text-white',
  U: 'bg-cyan-600 text-white',
  L: 'bg-indigo-500 text-white',
}

export const ESTADO_DIARIO_SHORT: Record<string, string> = {
  A: 'A', D: 'D', H: 'H', R: 'R', M: 'M',
  T: 'T', F: 'F', V: 'V', U: 'U', L: 'L',
}

export const OEE_CLASSIFICATION_COLORS: Record<string, string> = {
  'Clase Mundial': 'text-green-600',
  'Bueno': 'text-blue-600',
  'Aceptable': 'text-amber-600',
  'Deficiente': 'text-red-600',
}

// ── Estados Diarios Automáticos (Migración 30) ─────────

export interface ActualizarEstadoManualParams {
  activo_id: string
  fecha: string
  nuevo_estado: string
  motivo: string
  crear_ot?: boolean
  ot_tipo?: 'preventivo' | 'correctivo' | 'inspeccion' | 'lubricacion'
  ot_prioridad?: 'emergencia' | 'alta' | 'normal' | 'baja'
  ot_responsable_id?: string
  ot_descripcion?: string
}

export interface ActualizarEstadoManualResult {
  success: boolean
  estado_aplicado: string
  ot_creada: boolean
  ot_id?: string
  ot_folio?: string
}

export async function actualizarEstadoDiarioManual(
  params: ActualizarEstadoManualParams,
) {
  const { data, error } = await supabase.rpc('rpc_actualizar_estado_diario_manual', {
    p_activo_id: params.activo_id,
    p_fecha: params.fecha,
    p_nuevo_estado: params.nuevo_estado,
    p_motivo: params.motivo,
    p_crear_ot: params.crear_ot ?? false,
    p_ot_tipo: params.ot_tipo ?? null,
    p_ot_prioridad: params.ot_prioridad ?? 'normal',
    p_ot_responsable_id: params.ot_responsable_id ?? null,
    p_ot_descripcion: params.ot_descripcion ?? null,
  })
  return { data: data as ActualizarEstadoManualResult | null, error }
}

export async function aplicarEstadosAutomaticos(fecha?: string) {
  const { data, error } = await supabase.rpc('fn_aplicar_estados_diarios_automaticos', {
    p_fecha: fecha ?? new Date().toISOString().split('T')[0],
  })
  return { data, error }
}

export async function getEstadoDiarioActivoHoy(activoId: string) {
  const today = new Date().toISOString().split('T')[0]
  const { data, error } = await supabase
    .from('estado_diario_flota')
    .select('*')
    .eq('activo_id', activoId)
    .eq('fecha', today)
    .maybeSingle()
  return { data, error }
}
