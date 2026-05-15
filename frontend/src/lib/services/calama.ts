import { supabase } from '@/lib/supabase'

// ============================================================================
// Tipos
// ============================================================================

export type CalamaPlanificacion = {
  id: string
  codigo: string
  nombre: string
  faena_calama_id: string
  contrato_id: string | null
  linea_negocio: 'combustibles' | 'lubricantes' | 'mejoras_civiles'
  fecha_inicio_plan: string
  fecha_termino_plan: string
  fecha_inicio_real: string | null
  fecha_termino_real: string | null
  monto_estimado: number | null
  estado: 'planificada' | 'en_curso' | 'suspendida' | 'finalizada' | 'cancelada'
  avance_planificado: number
  avance_real: number
  responsable_id: string | null
  descripcion: string | null
  fuente_excel: string | null
  created_at: string
  updated_at: string
}

export type CalamaFaena = {
  id: string
  codigo: string
  nombre: string
  mandante: string | null
  region: string | null
  comuna: string | null
  activo: boolean
}

export type CalamaZona = {
  id: string
  planificacion_id: string
  codigo_zona: string
  nombre: string
  orden: number | null
}

export type CalamaOTEstado =
  | 'planificada' | 'liberada' | 'en_ejecucion' | 'en_pausa'
  | 'finalizada' | 'no_ejecutada' | 'cancelada'

export type CalamaOT = {
  id: string
  folio: string
  planificacion_id: string
  tarea_maestro_id: string | null
  faena_calama_id: string
  titulo: string
  descripcion: string | null
  fecha_programada: string
  hora_inicio_plan: string | null
  hora_termino_plan: string | null
  fecha_inicio_real: string | null
  fecha_termino_real: string | null
  horas_estimadas: number | null
  horas_reales: number | null
  avance_pct: number
  avance_excel_pct: number
  estado: CalamaOTEstado
  prioridad: 'baja' | 'normal' | 'alta' | 'critica'
  responsable_id: string | null
  jefe_sucursal_id: string | null
  requiere_vehiculo_especial: boolean
  detalle_vehiculo_especial: string | null
  observaciones_apertura: string | null
  observaciones_cierre: string | null
  firma_responsable_url: string | null
  firma_jefe_url: string | null
  created_at: string
  updated_at: string
}

export type CalamaOTConRelaciones = CalamaOT & {
  faena?: { codigo: string; nombre: string } | null
  planificacion?: { codigo: string; nombre: string; linea_negocio: string } | null
  tarea_maestro?: { codigo: string; nombre: string; sub_linea: string } | null
}

export type CalamaSubtarea = {
  id: string
  ot_id: string
  orden: number
  descripcion: string
  cantidad_plan: number | null
  cantidad_real: number | null
  unidad: string
  avance_pct: number
  estado: 'pendiente' | 'en_ejecucion' | 'completada' | 'no_aplica'
  asignado_id: string | null
  requiere_evidencia_foto: boolean
  completada_at: string | null
  completada_por: string | null
  observaciones: string | null
}

export type CalamaPrecheck = {
  id: string
  ot_id: string
  epp_completo: boolean
  herramientas_ok: boolean
  vehiculo_confirmado: boolean
  requiere_vehiculo_especial: boolean
  vehiculo_especial_confirmado: boolean
  charla_ods_realizada: boolean
  permisos_trabajo_ok: boolean
  observaciones: string | null
  revisado_por: string | null
  revisado_at: string | null
  liberada_para_ejecucion: boolean
  created_at: string
  updated_at: string
}

export type CalamaMaterial = {
  id: string
  planificacion_id: string
  tarea_maestro_id: string | null
  zona_proyecto_id: string | null
  actividad_relacionada: string | null
  descripcion: string
  unidad: string | null
  cantidad: number | null
  precio_clp: number | null
  valor_uf: number | null
  porcentaje: number | null
  bloque: string | null
}

export type CalamaContacto = {
  id: string
  faena_calama_id: string
  planificacion_id: string | null
  codigo_actividad: string | null
  descripcion: string
  telefono: string | null
  rol: string | null
  activo: boolean
}

export type CalamaObservacion = {
  id: string
  ot_id: string | null
  subtarea_id: string | null
  tipo: string
  severidad: 'info' | 'baja' | 'media' | 'alta'
  titulo: string | null
  detalle: string
  requiere_seguimiento: boolean
  cerrada: boolean
  creada_por: string
  created_at: string
}

export type CalamaCurvaSPunto = {
  fecha: string
  avance_plan_pct: number
  avance_real_pct: number
}

export type CalamaCurvaSConteoPunto = {
  planificacion_id: string
  codigo: string
  fecha: string
  total_ots: number
  finalizadas_acum: number
  en_ejecucion_acum: number
  planificadas_acum: number
  avance_plan_pct: number
  completitud_pct: number
  real_pct: number
  proyectado_pct: number
}

// ============================================================================
// Helpers
// ============================================================================

/**
 * Deriva el codigo de zona desde el folio de OT.
 * Folio: OT_<plan>_<excel_codigo> ej OT_VA_25_042_CENTINELA_1.1.0
 * Devuelve "1.0.0".
 */
export function zonaCodeFromFolio(folio: string): string | null {
  const m = /(\d+)\.(\d+)\.(\d+)$/.exec(folio)
  if (!m) return null
  return `${m[1]}.0.0`
}

export function excelCodigoFromFolio(folio: string): string | null {
  const m = /(\d+\.\d+\.\d+)$/.exec(folio)
  return m ? m[1] : null
}

/**
 * Formatea avance % asegurando rango 0-100 y redondeo a 0 decimales.
 * - null/undefined -> "0%"
 * - 0..1 (formato Excel decimal) -> NO se transforma (ya viene normalizado en DB)
 * - 0..100 -> directo
 */
export function formatPct(value: number | null | undefined, decimals = 0): string {
  if (value === null || value === undefined || !Number.isFinite(Number(value))) return '0%'
  const n = Math.max(0, Math.min(100, Number(value)))
  return `${n.toFixed(decimals)}%`
}

export function desviacionPp(real: number | null | undefined, excel: number | null | undefined): number {
  const r = Number(real ?? 0)
  const e = Number(excel ?? 0)
  return Math.round((r - e) * 10) / 10
}

export function avanceTone(real: number, excel: number): 'green' | 'amber' | 'red' {
  if (real >= 100) return 'green'
  if (real >= excel) return 'green'
  if (real >= excel * 0.7 || real >= 50) return 'amber'
  return 'red'
}

export function semaforoAvance(avancePct: number): 'verde' | 'amarillo' | 'rojo' {
  if (avancePct >= 80) return 'verde'
  if (avancePct >= 40) return 'amarillo'
  return 'rojo'
}

export type ProyeccionTermino = {
  diasTranscurridos: number
  avancePorDia: number
  diasRestantesEstimados: number | null
  fechaEstimadaTermino: string | null
  mensaje: string | null
}

/**
 * Proyeccion lineal: dado avance real y fecha base, estima dias restantes
 * y fecha estimada de termino.
 *
 * Casos limite:
 *   - avance <= 0           -> "Sin avance registrado"
 *   - dias <= 0             -> "Aun no hay base suficiente"
 *   - avance >= 100         -> 0 dias restantes, fecha = hoy
 *   - tasa muy lenta (>>365 dias) -> Numero pero con advertencia
 */
export function proyectarTermino(
  avanceRealPct: number,
  fechaInicio: string | Date | null | undefined,
  hoy: Date = new Date(),
): ProyeccionTermino {
  if (!fechaInicio) {
    return { diasTranscurridos: 0, avancePorDia: 0, diasRestantesEstimados: null, fechaEstimadaTermino: null, mensaje: 'Sin fecha de inicio' }
  }
  const inicio = typeof fechaInicio === 'string' ? new Date(fechaInicio) : fechaInicio
  const diasTrans = Math.floor((hoy.getTime() - inicio.getTime()) / 86400000)
  if (diasTrans <= 0) {
    return { diasTranscurridos: 0, avancePorDia: 0, diasRestantesEstimados: null, fechaEstimadaTermino: null, mensaje: 'Aun no hay base suficiente' }
  }
  const real = Math.max(0, Math.min(100, Number(avanceRealPct)))
  if (real <= 0) {
    return { diasTranscurridos: diasTrans, avancePorDia: 0, diasRestantesEstimados: null, fechaEstimadaTermino: null, mensaje: 'Sin avance registrado' }
  }
  if (real >= 100) {
    return {
      diasTranscurridos: diasTrans, avancePorDia: real / diasTrans,
      diasRestantesEstimados: 0,
      fechaEstimadaTermino: hoy.toISOString().slice(0, 10),
      mensaje: 'Completado',
    }
  }
  const tasa = real / diasTrans
  if (tasa <= 0) {
    return { diasTranscurridos: diasTrans, avancePorDia: 0, diasRestantesEstimados: null, fechaEstimadaTermino: null, mensaje: 'Sin ritmo suficiente para proyectar' }
  }
  const restantes = Math.ceil((100 - real) / tasa)
  const fecha = new Date(hoy)
  fecha.setDate(fecha.getDate() + restantes)
  return {
    diasTranscurridos: diasTrans,
    avancePorDia: Math.round(tasa * 100) / 100,
    diasRestantesEstimados: restantes,
    fechaEstimadaTermino: fecha.toISOString().slice(0, 10),
    mensaje: null,
  }
}

// ============================================================================
// Planificaciones
// ============================================================================

export async function getPlanificaciones() {
  const { data, error } = await supabase
    .from('calama_planificaciones')
    .select('*')
    .order('created_at', { ascending: false })
  return { data: data as CalamaPlanificacion[] | null, error }
}

export async function getPlanificacionById(id: string) {
  const { data, error } = await supabase
    .from('calama_planificaciones')
    .select('*')
    .eq('id', id)
    .single()
  return { data: data as CalamaPlanificacion | null, error }
}

export async function getZonasPorPlanificacion(planificacionId: string) {
  const { data, error } = await supabase
    .from('calama_zonas_proyecto')
    .select('*')
    .eq('planificacion_id', planificacionId)
    .order('orden', { ascending: true })
  return { data: data as CalamaZona[] | null, error }
}

// ============================================================================
// Faenas
// ============================================================================

export async function getFaenasCalama() {
  const { data, error } = await supabase
    .from('calama_faenas')
    .select('*')
    .eq('activo', true)
    .order('nombre')
  return { data: data as CalamaFaena[] | null, error }
}

// ============================================================================
// OTs
// ============================================================================

export type OTFilters = {
  planificacionId?: string
  faenaId?: string
  estado?: CalamaOTEstado
  zonaCodigo?: string
  fechaDesde?: string
  fechaHasta?: string
  busqueda?: string
}

/**
 * NOTA FASE 0: Reemplazo de embedded joins de PostgREST por consultas separadas.
 * Las RLS de calama_ordenes_trabajo y calama_ot_subtareas se referencian mutuamente,
 * lo que con joins embebidos puede gatillar 500 en PostgREST. Mantener este patron
 * (queries separadas + enrich client-side) hasta que se simplifique RLS.
 */
async function enriquecerOTs(ots: CalamaOT[]): Promise<CalamaOTConRelaciones[]> {
  if (ots.length === 0) return []

  const faenaIds = Array.from(new Set(ots.map((o) => o.faena_calama_id).filter(Boolean)))
  const planIds = Array.from(new Set(ots.map((o) => o.planificacion_id).filter(Boolean)))
  const tareaIds = Array.from(new Set(ots.map((o) => o.tarea_maestro_id).filter(Boolean) as string[]))

  const [faenasRes, plansRes, tareasRes] = await Promise.all([
    faenaIds.length > 0
      ? supabase.from('calama_faenas').select('id, codigo, nombre').in('id', faenaIds)
      : Promise.resolve({ data: [], error: null }),
    planIds.length > 0
      ? supabase.from('calama_planificaciones').select('id, codigo, nombre, linea_negocio, faena_calama_id').in('id', planIds)
      : Promise.resolve({ data: [], error: null }),
    tareaIds.length > 0
      ? supabase.from('calama_tareas_maestro').select('id, codigo, nombre, sub_linea, descripcion').in('id', tareaIds)
      : Promise.resolve({ data: [], error: null }),
  ])

  type FaenaRow = { id: string; codigo: string; nombre: string }
  type PlanRow = { id: string; codigo: string; nombre: string; linea_negocio: string }
  type TareaRow = { id: string; codigo: string; nombre: string; sub_linea: string }

  const faenaById = new Map<string, FaenaRow>(((faenasRes.data ?? []) as FaenaRow[]).map((f) => [f.id, f]))
  const planById = new Map<string, PlanRow>(((plansRes.data ?? []) as PlanRow[]).map((p) => [p.id, p]))
  const tareaById = new Map<string, TareaRow>(((tareasRes.data ?? []) as TareaRow[]).map((t) => [t.id, t]))

  return ots.map((o) => ({
    ...o,
    faena: faenaById.get(o.faena_calama_id)
      ? { codigo: faenaById.get(o.faena_calama_id)!.codigo, nombre: faenaById.get(o.faena_calama_id)!.nombre }
      : null,
    planificacion: planById.get(o.planificacion_id)
      ? {
          codigo: planById.get(o.planificacion_id)!.codigo,
          nombre: planById.get(o.planificacion_id)!.nombre,
          linea_negocio: planById.get(o.planificacion_id)!.linea_negocio,
        }
      : null,
    tarea_maestro: o.tarea_maestro_id && tareaById.get(o.tarea_maestro_id)
      ? {
          codigo: tareaById.get(o.tarea_maestro_id)!.codigo,
          nombre: tareaById.get(o.tarea_maestro_id)!.nombre,
          sub_linea: tareaById.get(o.tarea_maestro_id)!.sub_linea,
        }
      : null,
  }))
}

export async function getOTs(filters?: OTFilters) {
  let query = supabase
    .from('calama_ordenes_trabajo')
    .select('*')
    .order('fecha_programada', { ascending: false })
    .order('folio', { ascending: true })

  if (filters?.planificacionId) query = query.eq('planificacion_id', filters.planificacionId)
  if (filters?.faenaId) query = query.eq('faena_calama_id', filters.faenaId)
  if (filters?.estado) query = query.eq('estado', filters.estado)
  if (filters?.fechaDesde) query = query.gte('fecha_programada', filters.fechaDesde)
  if (filters?.fechaHasta) query = query.lte('fecha_programada', filters.fechaHasta)
  if (filters?.busqueda && filters.busqueda.trim()) {
    const q = filters.busqueda.trim()
    query = query.or(`folio.ilike.%${q}%,titulo.ilike.%${q}%`)
  }

  const { data, error } = await query
  if (error) return { data: null, error }
  const enriched = await enriquecerOTs((data ?? []) as CalamaOT[])
  return { data: enriched, error: null }
}

export async function getOTById(id: string) {
  const { data, error } = await supabase
    .from('calama_ordenes_trabajo')
    .select('*')
    .eq('id', id)
    .single()
  if (error || !data) return { data: null, error }
  const enriched = await enriquecerOTs([data as CalamaOT])
  return { data: enriched[0] ?? null, error: null }
}

export async function getSubtareasPorOT(otId: string) {
  const { data, error } = await supabase
    .from('calama_ot_subtareas')
    .select('*')
    .eq('ot_id', otId)
    .order('orden', { ascending: true })
  return { data: data as CalamaSubtarea[] | null, error }
}

export async function getObservacionesPorOT(otId: string) {
  const { data, error } = await supabase
    .from('calama_observaciones')
    .select('*')
    .eq('ot_id', otId)
    .order('created_at', { ascending: false })
  return { data: data as CalamaObservacion[] | null, error }
}

// ============================================================================
// Materiales y contactos
// ============================================================================

export async function getMaterialesPorPlan(planificacionId: string, zonaProyectoId?: string) {
  let query = supabase
    .from('calama_materiales_planificados')
    .select('*')
    .eq('planificacion_id', planificacionId)
    .order('actividad_relacionada')

  if (zonaProyectoId) query = query.eq('zona_proyecto_id', zonaProyectoId)

  const { data, error } = await query
  return { data: data as CalamaMaterial[] | null, error }
}

export async function getContactosPorFaena(faenaCalamaId: string, planificacionId?: string) {
  let query = supabase
    .from('calama_contactos_mandante')
    .select('*')
    .eq('faena_calama_id', faenaCalamaId)
    .eq('activo', true)
    .order('descripcion')

  if (planificacionId) query = query.eq('planificacion_id', planificacionId)

  const { data, error } = await query
  return { data: data as CalamaContacto[] | null, error }
}

// ============================================================================
// Precheck
// ============================================================================

export async function getPrecheckPorOT(otId: string) {
  const { data, error } = await supabase
    .from('calama_ot_precheck')
    .select('*')
    .eq('ot_id', otId)
    .maybeSingle()
  return { data: data as CalamaPrecheck | null, error }
}

export type PrecheckUpdatePayload = {
  ot_id: string
  epp_completo?: boolean
  herramientas_ok?: boolean
  vehiculo_confirmado?: boolean
  requiere_vehiculo_especial?: boolean
  vehiculo_especial_confirmado?: boolean
  charla_ods_realizada?: boolean
  permisos_trabajo_ok?: boolean
  observaciones?: string | null
}

export async function upsertPrecheck(payload: PrecheckUpdatePayload) {
  const ahora = new Date().toISOString()
  const { data, error } = await supabase
    .from('calama_ot_precheck')
    .upsert(
      { ...payload, revisado_at: ahora },
      { onConflict: 'ot_id' }
    )
    .select('*')
    .single()
  return { data: data as CalamaPrecheck | null, error }
}

export async function liberarOT(otId: string) {
  const { data, error } = await supabase
    .from('calama_ordenes_trabajo')
    .update({ estado: 'liberada', updated_at: new Date().toISOString() })
    .eq('id', otId)
    .eq('estado', 'planificada')
    .select('id, estado')
    .maybeSingle()
  return { data, error }
}

// ============================================================================
// RPCs
// ============================================================================

export async function iniciarEjecucionOT(otId: string) {
  const { data, error } = await supabase.rpc('rpc_calama_iniciar_ejecucion', { p_ot_id: otId })
  return { data, error }
}

export async function registrarAvanceOT(payload: {
  ot_id: string
  subtarea_id?: string | null
  fecha?: string
  avance_acumulado: number
  horas_trabajadas?: number
  cantidad_ejecutada?: number
  descripcion?: string
  gps_lat?: number
  gps_lng?: number
}) {
  const { data, error } = await supabase.rpc('rpc_calama_registrar_avance', { p_payload: payload })
  return { data, error }
}

export async function finalizarOT(payload: {
  ot_id: string
  observaciones_cierre?: string
  firma_responsable_url?: string
  horas_reales?: number
}) {
  const { data, error } = await supabase.rpc('rpc_calama_finalizar_ot', { p_payload: payload })
  return { data, error }
}

export async function reportarNoEjecucionOT(payload: {
  ot_id: string
  causa: string
  detalle?: string
  fecha_evento?: string
  horas_perdidas?: number
  impacto_avance?: number
}) {
  const { data, error } = await supabase.rpc('rpc_calama_reportar_no_ejecucion', { p_payload: payload })
  return { data, error }
}

export async function getCurvaS(planificacionId: string) {
  const { data, error } = await supabase.rpc('rpc_calama_curva_s_faena', {
    p_planificacion_id: planificacionId,
  })
  if (error) return { data: null, error }
  const serie = (data as { serie?: CalamaCurvaSPunto[] } | null)?.serie ?? []
  return { data: serie, error: null }
}

// MIG46 - curva S con 3 metricas oficiales (completitud / real / proyectado)
// reconstruidas dia a dia desde conteo de OTs. Vista v_calama_curva_s_conteo.
export async function getCurvaSConteo(planificacionId: string) {
  const { data, error } = await supabase
    .from('v_calama_curva_s_conteo')
    .select('*')
    .eq('planificacion_id', planificacionId)
    .order('fecha', { ascending: true })
  return { data: (data ?? []) as CalamaCurvaSConteoPunto[], error }
}

// ============================================================================
// KPIs / agregados (queries directas a vistas y tablas)
// ============================================================================

export type DashboardKPIs = {
  total_ots: number
  por_estado: Array<{ estado: CalamaOTEstado; total: number }>
  ots_atrasadas: number
  ots_no_ejecutadas: number
  zonas_intervenidas: number
  materiales_planificados: number
  total_planificaciones: number
  avance_planificado_promedio: number
  avance_real_promedio: number
  desviacion: number
  curva_s_principal: CalamaCurvaSPunto[]
  planificacion_principal_id: string | null
  planificacion_principal_codigo: string | null
}

export async function getDashboardKPIs(): Promise<{ data: DashboardKPIs | null; error: Error | null }> {
  try {
    const [
      { data: ots, error: errOts },
      { data: planificaciones, error: errPlan },
      { count: zonasCount, error: errZonas },
      { count: matCount, error: errMat },
    ] = await Promise.all([
      supabase.from('calama_ordenes_trabajo').select('id, estado, fecha_programada'),
      supabase.from('calama_planificaciones').select('*'),
      supabase.from('calama_zonas_proyecto').select('id', { count: 'exact', head: true }),
      supabase.from('calama_materiales_planificados').select('id', { count: 'exact', head: true }),
    ])

    if (errOts) throw errOts
    if (errPlan) throw errPlan
    if (errZonas) throw errZonas
    if (errMat) throw errMat

    const otsList = (ots ?? []) as Array<{ estado: CalamaOTEstado; fecha_programada: string }>
    const plans = (planificaciones ?? []) as CalamaPlanificacion[]
    const hoy = new Date().toISOString().slice(0, 10)

    const porEstadoMap = new Map<CalamaOTEstado, number>()
    let atrasadas = 0
    let noEjec = 0
    for (const ot of otsList) {
      porEstadoMap.set(ot.estado, (porEstadoMap.get(ot.estado) ?? 0) + 1)
      if (ot.estado === 'no_ejecutada') noEjec++
      if (
        ot.fecha_programada < hoy
        && !['finalizada', 'cancelada', 'no_ejecutada'].includes(ot.estado)
      ) atrasadas++
    }

    const planPrincipal = plans
      .filter((p) => p.estado !== 'cancelada')
      .sort((a, b) => (a.created_at < b.created_at ? 1 : -1))[0] ?? null

    let curvaS: CalamaCurvaSPunto[] = []
    if (planPrincipal) {
      const r = await getCurvaS(planPrincipal.id)
      curvaS = r.data ?? []
    }

    const avancePlan = plans.length === 0
      ? 0
      : plans.reduce((acc, p) => acc + Number(p.avance_planificado || 0), 0) / plans.length
    const avanceReal = plans.length === 0
      ? 0
      : plans.reduce((acc, p) => acc + Number(p.avance_real || 0), 0) / plans.length

    return {
      data: {
        total_ots: otsList.length,
        por_estado: Array.from(porEstadoMap.entries()).map(([estado, total]) => ({ estado, total })),
        ots_atrasadas: atrasadas,
        ots_no_ejecutadas: noEjec,
        zonas_intervenidas: zonasCount ?? 0,
        materiales_planificados: matCount ?? 0,
        total_planificaciones: plans.length,
        avance_planificado_promedio: Math.round(avancePlan * 100) / 100,
        avance_real_promedio: Math.round(avanceReal * 100) / 100,
        desviacion: Math.round((avanceReal - avancePlan) * 100) / 100,
        curva_s_principal: curvaS,
        planificacion_principal_id: planPrincipal?.id ?? null,
        planificacion_principal_codigo: planPrincipal?.codigo ?? null,
      },
      error: null,
    }
  } catch (e) {
    return { data: null, error: e as Error }
  }
}

export async function getResumenPlanificaciones() {
  const { data, error } = await supabase
    .from('calama_planificaciones')
    .select('*')
    .order('created_at', { ascending: false })
  if (error) return { data: null, error }

  const planes = (data ?? []) as CalamaPlanificacion[]
  const faenaIds = Array.from(new Set(planes.map((p) => p.faena_calama_id)))
  const { data: faenas } = faenaIds.length > 0
    ? await supabase.from('calama_faenas').select('id, codigo, nombre').in('id', faenaIds)
    : { data: [] }
  type FaenaRow = { id: string; codigo: string; nombre: string }
  const faenaById = new Map<string, FaenaRow>(((faenas ?? []) as FaenaRow[]).map((f) => [f.id, f]))

  const enriched = await Promise.all(
    planes.map(async (p) => {
      const { count } = await supabase
        .from('calama_ordenes_trabajo')
        .select('id', { count: 'exact', head: true })
        .eq('planificacion_id', p.id)
      const f = faenaById.get(p.faena_calama_id)
      return {
        ...p,
        total_ots: count ?? 0,
        faena: f ? { codigo: f.codigo, nombre: f.nombre } : null,
      }
    }),
  )
  return { data: enriched, error: null }
}
