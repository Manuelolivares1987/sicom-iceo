import { supabase } from '@/lib/supabase'
import { compressImage } from '@/lib/image/compress'

// ============================================================================
// Reportabilidad de Prevención por faena (MIG546)
// ----------------------------------------------------------------------------
// El repositorio central que pidió prevención: los supervisores cargan sus
// RIT/VAT/VCT/charlas con evidencia y el consolidado mensual sale solo, en vez
// de pedirle la información a cada supervisor por correo.
// ============================================================================

export interface ActividadTipo {
  codigo: string
  nombre: string
  descripcion: string | null
  requiere_cierre: boolean
  activo: boolean
  orden: number
  // [MIG551] Si el tipo trae títulos permitidos (PGR: H1 ARTP, H2 CtS…),
  // el formulario los muestra como selector en vez de texto libre.
  titulos_opciones: string[] | null
}

export interface EvidenciaArchivo {
  path: string
  nombre: string
  content_type: string
}

export interface PrevencionRegistro {
  id: string
  faena_id: string
  tipo_codigo: string
  fecha_actividad: string
  titulo: string
  descripcion: string | null
  area_sector: string | null
  activo_id: string | null
  estado: 'abierto' | 'cerrado'
  fecha_cierre: string | null
  cierre_observacion: string | null
  duracion_minutos: number | null
  asistentes: number | null
  evidencias: EvidenciaArchivo[]
  creado_por: string
  supervisor_nombre: string | null
  created_at: string
}

export interface GestionMensualFila {
  tipo_codigo: string
  tipo_nombre: string
  requiere_cierre: boolean
  meta: number
  realizados: number
  abiertos: number
  cerrados: number
  pct_cumplimiento: number | null
}

export interface ReportabilidadEstado {
  item_id: string
  nombre: string
  destino: string | null
  fuente: string | null
  dia_limite: number | null
  plantilla: 'e200' | 'grp_cmp' | 'informe_franke' | 'ppt_evidencias' | null
  enviado: boolean
  fecha_envio: string | null
  archivos: EvidenciaArchivo[] | null
  observacion: string | null
}

export interface ConsolidadoMes {
  gestion: GestionMensualFila[]
  indicadores: IndicadoresFila | null
  reportabilidad: ReportabilidadEstado[]
  abiertos_arrastre: Array<{
    id: string
    tipo_codigo: string
    titulo: string
    fecha_actividad: string
    supervisor: string | null
  }>
}

export interface IndicadoresFila {
  id?: string
  faena_id: string
  anio: number
  mes: number
  dotacion_hombres: number
  dotacion_mujeres: number
  hh_hombres: number
  hh_mujeres: number
  accidentes_ctp: number
  accidentes_stp: number
  dias_perdidos: number
  accidentes_trayecto: number
  enfermedades_prof: number
  incidentes_alto_potencial: number
  observaciones: string | null
  // calculados por la vista
  dotacion_total?: number
  hh_total?: number
  indice_frecuencia?: number
  indice_gravedad?: number
  tasa_accidentabilidad?: number
  acum_ctp?: number
  acum_dias_perdidos?: number
  acum_hh?: number
  acum_indice_frecuencia?: number
  acum_indice_gravedad?: number
}

// ── Catálogos ────────────────────────────────────────────────────────────────

export function getActividadTipos() {
  return supabase
    .from('prevencion_actividad_tipos')
    .select('*')
    .eq('activo', true)
    .order('orden')
}

/**
 * [MIG552] Qué tipos ofrece cada faena (catálogo del mandante: Romeral usa
 * RIT/VAT/VCT/EPF, Centinela usa PGR, etc.). Faena sin filas = ve todos.
 */
export function getFaenaTipos() {
  return supabase.from('prevencion_faena_tipos').select('faena_id, tipo_codigo')
}

/**
 * SOLO las faenas donde Pillado tiene personal propio = las que tienen
 * reportabilidad configurada (Manuel, 2026-09-14: Romeral, Franke, Lomas
 * Bayas, Centinela y Spence). Las otras 18 faenas del sistema (talleres,
 * arriendo puro) no aparecen en este módulo. Para sumar una faena nueva se
 * le crean sus ítems de reportabilidad (MIG549 como ejemplo).
 */
export async function getFaenasPrevencion() {
  const [{ data: items, error: e1 }, { data: faenas, error }] = await Promise.all([
    supabase.from('prevencion_reportabilidad_items').select('faena_id').eq('activo', true),
    supabase.from('faenas').select('id, nombre, codigo').order('nombre'),
  ])
  if (error || !faenas) return { data: [], error: error ?? e1 }
  const conItems = new Set((items ?? []).map((i: any) => i.faena_id))
  const conPersonal = faenas.filter((f: any) => conItems.has(f.id))
  // Fallback: si el catálogo quedara vacío por error, mejor mostrar todo que
  // dejar el módulo ciego.
  return { data: conPersonal.length ? conPersonal : faenas, error: null }
}

// ── Registros de terreno ─────────────────────────────────────────────────────

export function getRegistros(params: {
  faenaId?: string
  anio?: number
  mes?: number
  tipoCodigo?: string
  estado?: 'abierto' | 'cerrado'
  limit?: number
}) {
  let q = supabase
    .from('prevencion_registros')
    .select('*')
    .order('fecha_actividad', { ascending: false })
    .order('created_at', { ascending: false })

  if (params.faenaId) q = q.eq('faena_id', params.faenaId)
  if (params.anio && params.mes) {
    const desde = `${params.anio}-${String(params.mes).padStart(2, '0')}-01`
    const hastaDate = new Date(params.anio, params.mes, 1) // 1° del mes siguiente
    const hasta = hastaDate.toISOString().slice(0, 10)
    q = q.gte('fecha_actividad', desde).lt('fecha_actividad', hasta)
  }
  if (params.tipoCodigo) q = q.eq('tipo_codigo', params.tipoCodigo)
  if (params.estado) q = q.eq('estado', params.estado)
  return q.limit(params.limit ?? 500)
}

export async function getMisRegistros(limit = 30) {
  const { data: auth } = await supabase.auth.getUser()
  if (!auth?.user) return { data: [], error: null }
  return supabase
    .from('prevencion_registros')
    .select('*')
    .eq('creado_por', auth.user.id)
    .order('created_at', { ascending: false })
    .limit(limit)
}

export function createRegistro(reg: {
  faena_id: string
  tipo_codigo: string
  fecha_actividad: string
  titulo: string
  descripcion?: string | null
  area_sector?: string | null
  estado: 'abierto' | 'cerrado'
  duracion_minutos?: number | null
  asistentes?: number | null
  evidencias: EvidenciaArchivo[]
}) {
  return supabase.from('prevencion_registros').insert(reg).select().single()
}

export function cerrarRegistro(id: string, observacion?: string) {
  return supabase
    .from('prevencion_registros')
    .update({ estado: 'cerrado', cierre_observacion: observacion ?? null })
    .eq('id', id)
    .select()
    .single()
}

export function updateRegistro(id: string, patch: Partial<PrevencionRegistro>) {
  return supabase.from('prevencion_registros').update(patch).eq('id', id).select().single()
}

export function deleteRegistro(id: string) {
  return supabase.from('prevencion_registros').delete().eq('id', id)
}

// ── Consolidado mensual (una llamada) ────────────────────────────────────────

export async function getConsolidadoMes(faenaId: string, anio: number, mes: number) {
  const { data, error } = await supabase.rpc('rpc_prevencion_consolidado_mes', {
    p_faena_id: faenaId,
    p_anio: anio,
    p_mes: mes,
  })
  return { data: data as ConsolidadoMes | null, error }
}

// ── Programa mensual (metas) ─────────────────────────────────────────────────

export async function upsertMeta(params: {
  faena_id: string
  anio: number
  mes: number
  tipo_codigo: string
  meta: number
}) {
  const { data: auth } = await supabase.auth.getUser()
  return supabase
    .from('prevencion_programa_mensual')
    .upsert(
      { ...params, updated_by: auth?.user?.id ?? null, updated_at: new Date().toISOString() },
      { onConflict: 'faena_id,anio,mes,tipo_codigo' },
    )
}

// ── Indicadores mensuales ────────────────────────────────────────────────────

export function getIndicadoresAnio(faenaId: string, anio: number) {
  return supabase
    .from('v_prevencion_indicadores')
    .select('*')
    .eq('faena_id', faenaId)
    .eq('anio', anio)
    .order('mes')
}

export async function upsertIndicadores(fila: IndicadoresFila) {
  const { data: auth } = await supabase.auth.getUser()
  const {
    dotacion_total, hh_total, indice_frecuencia, indice_gravedad,
    tasa_accidentabilidad, acum_ctp, acum_dias_perdidos, acum_hh,
    acum_indice_frecuencia, acum_indice_gravedad, id, ...editable
  } = fila as any
  return supabase
    .from('prevencion_indicadores_mes')
    .upsert(
      { ...editable, updated_by: auth?.user?.id ?? null, updated_at: new Date().toISOString() },
      { onConflict: 'faena_id,anio,mes' },
    )
}

// ── Checklist de reportabilidad ──────────────────────────────────────────────

export function marcarEnviada(params: {
  item_id: string
  anio: number
  mes: number
  observacion?: string | null
  archivos: EvidenciaArchivo[]
}) {
  return supabase
    .from('prevencion_reportabilidad_envios')
    .upsert(
      {
        item_id: params.item_id,
        anio: params.anio,
        mes: params.mes,
        observacion: params.observacion ?? null,
        archivos: params.archivos,
        fecha_envio: new Date().toISOString().slice(0, 10),
      },
      { onConflict: 'item_id,anio,mes' },
    )
}

export function desmarcarEnvio(itemId: string, anio: number, mes: number) {
  return supabase
    .from('prevencion_reportabilidad_envios')
    .delete()
    .eq('item_id', itemId)
    .eq('anio', anio)
    .eq('mes', mes)
}

// ── Evidencias (bucket privado prevencion-evidencias) ────────────────────────
// Estructura documental pedida por prevención: Faena → Año → Mes → carpeta.

export async function subirEvidencia(
  file: File,
  ruta: { faenaId: string; anio: number; mes: number; carpeta: string },
): Promise<{ data: EvidenciaArchivo | null; error: Error | null }> {
  const esImagen = file.type.startsWith('image/')
  const blob = esImagen ? await compressImage(file) : file
  const limpio = file.name.replace(/[^a-zA-Z0-9._-]/g, '_').slice(-80)
  const nombreFinal = esImagen && !/\.(jpe?g)$/i.test(limpio) ? `${limpio}.jpg` : limpio
  const path =
    `${ruta.faenaId}/${ruta.anio}/${String(ruta.mes).padStart(2, '0')}/` +
    `${ruta.carpeta}/${Date.now()}-${nombreFinal}`

  const { error } = await supabase.storage
    .from('prevencion-evidencias')
    .upload(path, blob, {
      contentType: esImagen ? 'image/jpeg' : file.type || 'application/octet-stream',
      upsert: false,
    })
  if (error) return { data: null, error: error as unknown as Error }
  return {
    data: {
      path,
      nombre: file.name,
      content_type: esImagen ? 'image/jpeg' : file.type || 'application/octet-stream',
    },
    error: null,
  }
}

// ── Fase 2 (MIG547): config por faena, monitoreo y generadores ──────────────

export interface FaenaConfigDatos {
  empresa?: Record<string, string>
  experto?: Record<string, string>
  mandante?: Record<string, string>
  faena_nombre?: string
  instalacion?: Record<string, string>
  contrato?: Record<string, string>
  mutual?: string
  [k: string]: unknown
}

export function getFaenaConfig(faenaId: string) {
  return supabase
    .from('prevencion_faena_config')
    .select('faena_id, datos, updated_at')
    .eq('faena_id', faenaId)
    .maybeSingle()
}

export async function upsertFaenaConfig(faenaId: string, datos: FaenaConfigDatos) {
  const { data: auth } = await supabase.auth.getUser()
  return supabase
    .from('prevencion_faena_config')
    .upsert(
      {
        faena_id: faenaId,
        datos,
        updated_by: auth?.user?.id ?? null,
        updated_at: new Date().toISOString(),
      },
      { onConflict: 'faena_id' },
    )
}

export interface MonitoreoSupervisor {
  faena_id: string
  anio: number
  mes: number
  creado_por: string
  supervisor: string
  rol: string | null
  total: number
  abiertos: number
  ultima_carga: string
  por_tipo: Record<string, number> | null
}

export function getMonitoreoMes(faenaId: string, anio: number, mes: number) {
  return supabase
    .from('v_prevencion_monitoreo_supervisores')
    .select('*')
    .eq('faena_id', faenaId)
    .eq('anio', anio)
    .eq('mes', mes)
    .order('total', { ascending: false })
}

export function getSupervisoresFaena(faenaId: string) {
  return supabase.rpc('rpc_prevencion_supervisores_faena', { p_faena_id: faenaId })
}

// ── Supervisores rotativos (MIG548): asignación supervisor ↔ faenas ─────────
// Los de Calama cubren Lomas y Centinela a la vez; la asignación define a
// quién se le cobra la carga del mes en el monitoreo (no restringe la carga).

export interface SupervisorAsignable {
  usuario_id: string
  nombre: string
  email: string
  rol: string
  faena_fija: boolean
  asignado: boolean
}

export function getSupervisoresAsignables(faenaId: string) {
  return supabase.rpc('rpc_prevencion_supervisores_asignables', { p_faena_id: faenaId })
}

export async function asignarSupervisorFaena(usuarioId: string, faenaId: string) {
  const { data: auth } = await supabase.auth.getUser()
  return supabase.from('prevencion_supervisor_faenas').upsert(
    { usuario_id: usuarioId, faena_id: faenaId, created_by: auth?.user?.id ?? null },
    { onConflict: 'usuario_id,faena_id' },
  )
}

export function quitarSupervisorFaena(usuarioId: string, faenaId: string) {
  return supabase
    .from('prevencion_supervisor_faenas')
    .delete()
    .eq('usuario_id', usuarioId)
    .eq('faena_id', faenaId)
}

export async function urlEvidencia(path: string): Promise<string | null> {
  const { data } = await supabase.storage
    .from('prevencion-evidencias')
    .createSignedUrl(path, 60 * 60) // 1 hora: se abre y se mira, no se comparte
  return data?.signedUrl ?? null
}
