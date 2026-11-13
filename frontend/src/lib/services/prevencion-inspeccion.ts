import { supabase } from '@/lib/supabase'
import { subirEvidencia, urlEvidencia, type EvidenciaArchivo } from '@/lib/services/prevencion-reportabilidad'

// ============================================================================
// Inspección de terreno APR (MIG685)
// ----------------------------------------------------------------------------
// El recorrido del prevencionista en Calama, según el documento «Inspección
// terreno (Prevención de Riesgos) 12-11-26»: 8 etapas, cada punto probado con
// FOTO o con el CONTROL DOCUMENTAL. La base recalcula al guardar lo que no
// depende del ojo del APR (habilitación documental y fatiga), así el teléfono
// no puede marcar «cumple» lo que el portal dice que no.
// ============================================================================

export type EvidenciaTipo = 'foto' | 'documental' | 'fatiga' | 'verbal'
export type Respuesta = 'cumple' | 'no_cumple' | 'no_aplica'

export interface PuntoPlantilla {
  codigo: string
  etapa_orden: number
  etapa: string
  orden: number
  pregunta: string
  ayuda: string | null
  evidencia: EvidenciaTipo
  posterior: boolean
  solo_cruzado: boolean
}

export interface RequisitoEstado {
  tipo_codigo: string
  nombre: string
  categoria: string
  item_codigo: string
  aplica_a: 'todos' | 'conductor'
  estado: string
  vence: string | null
  ok: boolean
}

export interface PersonaHabilitacion {
  personal_id: string
  nombre: string
  rut: string
  rut_provisorio: boolean
  cargo: string | null
  requisitos: RequisitoEstado[]
  habilitado: boolean            // requisitos de todos
  habilitado_conductor: boolean  // + los de conductor
}

export interface Habilitacion {
  generado_at: string
  grupo: string
  requisitos: { tipo_codigo: string, nombre: string, aplica_a: string, item_codigo: string }[]
  personas: PersonaHabilitacion[]
}

export interface FaenaInspeccion {
  faena_id: string
  grupo_personal: string
  nombre: string
  codigo: string
}

export interface FatigaRespuestas {
  horas_24?: number | null
  horas_48?: number | null
  horas_despierto?: number | null
  alcohol?: boolean
  medicamentos?: boolean
  malestar?: boolean
  somnolencia?: boolean
  preocupaciones?: boolean
}

export interface DesviacionInput {
  item_codigo: string
  descripcion: string
  accion?: string
  responsable?: string
  fecha_compromiso?: string
  criticidad?: 'alta' | 'media' | 'baja'
}

export interface InspeccionPayload {
  cliente_uuid: string
  faena_id: string
  fecha: string
  hora_inicio?: string | null
  instalacion?: string | null
  area_sector?: string | null
  trabajo: string
  supervisor?: string | null
  trabajo_cruzado: boolean
  empresas_cruzadas?: string | null
  observacion?: string | null
  personas: { personal_id: string, es_conductor: boolean, fatiga?: FatigaRespuestas }[]
  items: { item_codigo: string, respuesta: Respuesta | null, observacion?: string | null, evidencias: EvidenciaArchivo[] }[]
  desviaciones: DesviacionInput[]
}

export interface InspeccionResumen {
  id: string
  cliente_uuid: string
  faena_id: string
  fecha: string
  hora_inicio: string | null
  instalacion: string | null
  area_sector: string | null
  trabajo: string
  supervisor: string | null
  trabajo_cruzado: boolean
  empresas_cruzadas: string | null
  observacion: string | null
  estado: 'en_curso' | 'pendiente_cierre_art' | 'cerrada'
  resultado: 'conforme' | 'con_desviaciones' | 'critico'
  pct_cumplimiento: number | null
  items_cumple: number
  items_no_cumple: number
  items_no_aplica: number
  items_pendientes: number
  personas_no_habilitadas: number
  inspector_id: string
  inspector_nombre: string | null
  cerrada_at: string | null
  created_at: string
}

export interface InspeccionItem {
  id: string
  item_codigo: string
  etapa: string
  pregunta: string
  evidencia_tipo: EvidenciaTipo
  respuesta: Respuesta | null
  observacion: string | null
  evidencias: EvidenciaArchivo[]
  automatico: boolean
}

export interface InspeccionPersona {
  id: string
  personal_id: string
  nombre: string
  rut: string | null
  es_conductor: boolean
  habilitado: boolean
  requisitos: RequisitoEstado[]
  fatiga_respuestas: FatigaRespuestas | null
  fatiga_resultado: 'apto' | 'apto_observacion' | 'no_apto' | null
  fatiga_motivos: string[] | null
}

export interface Desviacion {
  id: string
  inspeccion_id: string
  item_codigo: string | null
  personal_id: string | null
  origen: 'item' | 'documental' | 'fatiga'
  criticidad: 'alta' | 'media' | 'baja'
  descripcion: string
  accion: string | null
  responsable: string | null
  fecha_compromiso: string | null
  estado: 'abierta' | 'cerrada'
  cierre_observacion: string | null
  cierre_evidencias: EvidenciaArchivo[]
  cerrada_at: string | null
  created_at: string
}

export interface InspeccionDetalle extends InspeccionResumen {
  items: InspeccionItem[]
  personas: InspeccionPersona[]
  desviaciones: Desviacion[]
}

// ── Catálogos ────────────────────────────────────────────────────────────────

export async function getPlantilla(): Promise<PuntoPlantilla[]> {
  const { data, error } = await supabase
    .from('prevencion_inspeccion_plantilla')
    .select('codigo, etapa_orden, etapa, orden, pregunta, ayuda, evidencia, posterior, solo_cruzado')
    .eq('activo', true)
    .order('etapa_orden').order('orden')
  if (error) throw error
  return (data ?? []) as PuntoPlantilla[]
}

export async function getFaenasInspeccion(): Promise<FaenaInspeccion[]> {
  const { data, error } = await supabase
    .from('prevencion_inspeccion_faenas')
    .select('faena_id, grupo_personal, faenas(nombre, codigo)')
    .eq('activo', true)
  if (error) throw error
  return (data ?? []).map((r: any) => ({
    faena_id: r.faena_id,
    grupo_personal: r.grupo_personal,
    nombre: r.faenas?.nombre ?? '—',
    codigo: r.faenas?.codigo ?? '',
  })).sort((a, b) => a.nombre.localeCompare(b.nombre))
}

export async function getHabilitacion(grupo = 'CALAMA'): Promise<Habilitacion> {
  const { data, error } = await supabase.rpc('fn_prevencion_habilitacion', { p_grupo: grupo })
  if (error) throw error
  return data as Habilitacion
}

// ── Guardar ──────────────────────────────────────────────────────────────────

export async function guardarInspeccion(p: InspeccionPayload) {
  const { data, error } = await supabase.rpc('fn_prevencion_inspeccion_guardar', { p })
  if (error) throw new Error(error.message)
  return data as {
    id: string, estado: string, resultado: string,
    cumple: number, no_cumple: number, no_aplica: number,
    pendientes: number, no_habilitados: number,
  }
}

/** Sube una foto de la inspección al bucket privado de prevención. */
export async function subirFotoInspeccion(file: File, faenaId: string, fecha: string) {
  const [anio, mes] = fecha.split('-').map(Number)
  const { data, error } = await subirEvidencia(file, {
    faenaId, anio, mes, carpeta: 'inspeccion_apr',
  })
  if (error || !data) throw error ?? new Error('No se pudo subir la foto')
  return data
}

export { urlEvidencia }

// ── Lectura ──────────────────────────────────────────────────────────────────

export async function getInspecciones(params: { desde?: string, hasta?: string, faenaId?: string | null } = {}) {
  let q = supabase.from('prevencion_inspecciones').select('*')
    .order('fecha', { ascending: false }).order('created_at', { ascending: false })
  if (params.desde) q = q.gte('fecha', params.desde)
  if (params.hasta) q = q.lte('fecha', params.hasta)
  if (params.faenaId) q = q.eq('faena_id', params.faenaId)
  const { data, error } = await q.limit(500)
  if (error) throw error
  return (data ?? []) as InspeccionResumen[]
}

export async function getMisInspecciones(limit = 20) {
  const { data: u } = await supabase.auth.getUser()
  if (!u.user) return []
  const { data, error } = await supabase.from('prevencion_inspecciones').select('*')
    .eq('inspector_id', u.user.id)
    .order('fecha', { ascending: false }).order('created_at', { ascending: false })
    .limit(limit)
  if (error) throw error
  return (data ?? []) as InspeccionResumen[]
}

export async function getInspeccionDetalle(id: string): Promise<InspeccionDetalle> {
  const [cab, items, personas, desv] = await Promise.all([
    supabase.from('prevencion_inspecciones').select('*').eq('id', id).single(),
    supabase.from('prevencion_inspeccion_items').select('*').eq('inspeccion_id', id),
    supabase.from('prevencion_inspeccion_personas').select('*').eq('inspeccion_id', id).order('nombre'),
    supabase.from('prevencion_inspeccion_desviaciones').select('*').eq('inspeccion_id', id).order('created_at'),
  ])
  if (cab.error) throw cab.error
  return {
    ...(cab.data as InspeccionResumen),
    items: (items.data ?? []) as InspeccionItem[],
    personas: (personas.data ?? []) as InspeccionPersona[],
    desviaciones: (desv.data ?? []) as Desviacion[],
  }
}

export async function getDesviaciones(params: { estado?: 'abierta' | 'cerrada' | null } = {}) {
  let q = supabase.from('prevencion_inspeccion_desviaciones')
    .select('*, prevencion_inspecciones(fecha, faena_id, trabajo, instalacion)')
    .order('created_at', { ascending: false })
  if (params.estado) q = q.eq('estado', params.estado)
  const { data, error } = await q.limit(500)
  if (error) throw error
  return (data ?? []) as (Desviacion & {
    prevencion_inspecciones: { fecha: string, faena_id: string, trabajo: string, instalacion: string | null } | null
  })[]
}

export async function cerrarDesviacion(id: string, observacion: string, evidencias: EvidenciaArchivo[]) {
  const { data: u } = await supabase.auth.getUser()
  const { error } = await supabase.from('prevencion_inspeccion_desviaciones').update({
    estado: 'cerrada',
    cierre_observacion: observacion,
    cierre_evidencias: evidencias,
    cerrada_por: u.user?.id ?? null,
    cerrada_at: new Date().toISOString(),
  }).eq('id', id)
  if (error) throw error
}

// ── Etiquetas compartidas ────────────────────────────────────────────────────

export const RESULTADO_LABEL: Record<InspeccionResumen['resultado'], string> = {
  conforme: 'Conforme',
  con_desviaciones: 'Con desviaciones',
  critico: 'Crítico',
}

export const ESTADO_LABEL: Record<InspeccionResumen['estado'], string> = {
  en_curso: 'En curso',
  pendiente_cierre_art: 'Falta cierre ART',
  cerrada: 'Cerrada',
}

export const ESTADO_REQ_LABEL: Record<string, string> = {
  vigente: 'Vigente',
  por_vencer_7: 'Vence ≤7 d',
  por_vencer_14: 'Vence ≤14 d',
  por_vencer_30: 'Vence ≤30 d',
  por_vencer_60: 'Vence ≤60 d',
  no_aplica: 'No aplica',
  vencido: 'Vencido',
  sin_dato: 'Sin registro',
  observado: 'Observado',
}

/**
 * Misma regla que fn_prevencion_evaluar_fatiga (MIG685), para mostrar el
 * resultado en el teléfono antes de guardar. La que vale es la de la base.
 */
export function evaluarFatiga(f: FatigaRespuestas): { resultado: 'apto' | 'apto_observacion' | 'no_apto' | 'incompleta', motivos: string[] } {
  const m: string[] = []
  const obs: string[] = []
  const h24 = f.horas_24, h48 = f.horas_48, hd = f.horas_despierto
  if (h24 == null || h48 == null || hd == null) {
    return { resultado: 'incompleta', motivos: ['Faltan las horas de sueño'] }
  }
  if (h24 < 5) m.push(`Durmió ${h24} h en 24 h (mínimo 5)`)
  if (h48 < 12) m.push(`Durmió ${h48} h en 48 h (mínimo 12)`)
  if (hd > h48) m.push(`Lleva ${hd} h despierto, más que lo dormido en 48 h`)
  if (h24 >= 5 && h24 < 6) obs.push(`Durmió ${h24} h en 24 h`)
  if (f.alcohol) m.push('Consumió alcohol en las últimas 12 h')
  if (f.medicamentos) m.push('Medicamentos que producen somnolencia')
  if (f.malestar) m.push('Se siente enfermo o con malestar')
  if (f.somnolencia) m.push('Señales de somnolencia')
  if (f.preocupaciones) obs.push('Preocupaciones que afectan su concentración')
  if (m.length) return { resultado: 'no_apto', motivos: m }
  if (obs.length) return { resultado: 'apto_observacion', motivos: obs }
  return { resultado: 'apto', motivos: [] }
}

export const PREGUNTAS_FATIGA: { clave: keyof FatigaRespuestas, texto: string }[] = [
  { clave: 'alcohol', texto: '¿Consumió alcohol en las últimas 12 horas?' },
  { clave: 'medicamentos', texto: '¿Tomó medicamentos que producen sueño (antialérgicos, relajantes, antigripales, otros)?' },
  { clave: 'malestar', texto: '¿Se siente enfermo o con un malestar que le impida conducir con seguridad?' },
  { clave: 'somnolencia', texto: '¿Ha tenido bostezos frecuentes, pesadez de párpados o le ha costado mantenerse despierto?' },
  { clave: 'preocupaciones', texto: '¿Tiene preocupaciones personales que le impidan concentrarse en la conducción?' },
]
