import { supabase } from '@/lib/supabase'

// ── Types ────────────────────────────────────────────────

export type GembaEvaluacion = 'cumple' | 'no_cumple' | 'no_aplica'
export type GembaLugarTipo = 'taller' | 'faena'
export type GembaEstadoRecorrido = 'en_curso' | 'cerrado'
export type GembaEstadoHallazgo = 'abierta' | 'en_proceso' | 'cerrada'

export interface GembaSeccion {
  titulo: string
  items: string[]
}

export interface GembaPlantilla {
  id: string
  codigo: string
  nombre: string
  cargo: string
  ambito: 'taller' | 'faena' | 'ambos'
  descripcion?: string
  secciones: GembaSeccion[]
  activo: boolean
  /**
   * [MIG288] Roles a los que se les propone este checklist. En este sistema no
   * existe un rol `prevencionista`, y el jefe de taller es `jefe_mantenimiento`:
   * el mapeo vive en la BD, no en el código, para poder corregirlo sin deploy.
   */
  roles: string[]
}

/** El checklist que le toca a un rol, si hay uno solo claro. */
export function plantillaDeRol(
  plantillas: GembaPlantilla[] | null | undefined, rol: string | null | undefined,
): GembaPlantilla | null {
  if (!plantillas?.length || !rol) return null
  const propias = plantillas.filter((p) => (p.roles ?? []).includes(rol))
  return propias.length === 1 ? propias[0] : null
}

export interface GembaRecorrido {
  id: string
  plantilla_id: string
  fecha: string
  hora_inicio?: string
  hora_termino?: string
  lugar_tipo: GembaLugarTipo
  faena_id?: string
  sector?: string
  responsable_id?: string
  acompanantes?: string
  foco?: string
  observaciones?: string
  estado: GembaEstadoRecorrido
  created_at: string
  // Joined
  plantilla?: Pick<GembaPlantilla, 'nombre' | 'cargo' | 'codigo'>
  faena?: { nombre: string; codigo: string }
  responsable?: { nombre_completo?: string; email?: string }
  resumen?: GembaRecorridoResumen
}

export interface GembaRespuesta {
  id: string
  recorrido_id: string
  seccion: string
  orden: number
  item: string
  evaluacion?: GembaEvaluacion | null
  observacion?: string
}

export interface GembaHallazgo {
  id: string
  recorrido_id: string
  respuesta_id?: string
  descripcion: string
  accion_correctiva?: string
  responsable_id?: string
  responsable_texto?: string
  fecha_compromiso?: string
  estado: GembaEstadoHallazgo
  fecha_cierre?: string
  created_at: string
  // Joined
  responsable?: { nombre_completo?: string; email?: string }
  recorrido?: { fecha: string; lugar_tipo: GembaLugarTipo; sector?: string }
}

export interface GembaRecorridoResumen {
  recorrido_id: string
  total_items: number
  cumple: number
  no_cumple: number
  no_aplica: number
  pendientes: number
  pct_cumplimiento: number | null
}

export interface GembaKpi {
  recorridos_mes: number
  recorridos_en_curso: number
  hallazgos_abiertos: number
  hallazgos_vencidos: number
  pct_cumplimiento_90d: number | null
}

// ── Queries ──────────────────────────────────────────────

export async function getGembaPlantillas() {
  const { data, error } = await supabase
    .from('gemba_plantillas')
    .select('*')
    .eq('activo', true)
    .order('nombre')
  return { data: data as GembaPlantilla[] | null, error }
}

export async function getGembaKpi() {
  const { data, error } = await supabase
    .from('vw_gemba_kpi')
    .select('*')
    .maybeSingle()
  return { data: data as GembaKpi | null, error }
}

export async function getGembaRecorridos(limit = 100) {
  const { data, error } = await supabase
    .from('gemba_recorridos')
    .select(
      '*, plantilla:gemba_plantillas(nombre, cargo, codigo), faena:faenas(nombre, codigo), responsable:usuarios_perfil(nombre_completo, email)'
    )
    .order('fecha', { ascending: false })
    .order('created_at', { ascending: false })
    .limit(limit)
  if (error || !data) return { data: null, error }

  // Adjuntar resumen (% cumplimiento) de la vista
  const ids = data.map((r: any) => r.id)
  const { data: resumenes } = await supabase
    .from('vw_gemba_recorrido_resumen')
    .select('*')
    .in('recorrido_id', ids)
  const porId = new Map((resumenes ?? []).map((s: any) => [s.recorrido_id, s]))
  const enriched = data.map((r: any) => ({ ...r, resumen: porId.get(r.id) ?? null }))
  return { data: enriched as GembaRecorrido[], error: null }
}

export async function getGembaRecorrido(id: string) {
  const { data, error } = await supabase
    .from('gemba_recorridos')
    .select(
      '*, plantilla:gemba_plantillas(nombre, cargo, codigo), faena:faenas(nombre, codigo), responsable:usuarios_perfil(nombre_completo, email)'
    )
    .eq('id', id)
    .maybeSingle()
  return { data: data as GembaRecorrido | null, error }
}

export async function getGembaRespuestas(recorridoId: string) {
  const { data, error } = await supabase
    .from('gemba_respuestas')
    .select('*')
    .eq('recorrido_id', recorridoId)
    .order('orden')
  return { data: data as GembaRespuesta[] | null, error }
}

export async function getGembaHallazgos(recorridoId?: string, soloAbiertos = false) {
  let q = supabase
    .from('gemba_hallazgos')
    .select(
      '*, responsable:usuarios_perfil(nombre_completo, email), recorrido:gemba_recorridos(fecha, lugar_tipo, sector)'
    )
  if (recorridoId) q = q.eq('recorrido_id', recorridoId)
  if (soloAbiertos) q = q.neq('estado', 'cerrada')
  const { data, error } = await q.order('created_at', { ascending: false })
  return { data: data as GembaHallazgo[] | null, error }
}

// ── Mutations ────────────────────────────────────────────

/**
 * Crea un recorrido y pre-carga sus respuestas desde la plantilla elegida.
 */
export async function createGembaRecorrido(input: {
  plantilla_id: string
  fecha: string
  lugar_tipo: GembaLugarTipo
  faena_id?: string
  sector?: string
  acompanantes?: string
  foco?: string
  hora_inicio?: string
}) {
  const { data: auth } = await supabase.auth.getUser()
  const uid = auth?.user?.id

  // 1. Leer la plantilla
  const { data: plantilla, error: ePlantilla } = await supabase
    .from('gemba_plantillas')
    .select('*')
    .eq('id', input.plantilla_id)
    .single()
  if (ePlantilla || !plantilla) return { data: null, error: ePlantilla }

  // 2. Crear el recorrido
  const { data: recorrido, error: eRecorrido } = await supabase
    .from('gemba_recorridos')
    .insert({
      plantilla_id: input.plantilla_id,
      fecha: input.fecha,
      hora_inicio: input.hora_inicio || null,
      lugar_tipo: input.lugar_tipo,
      faena_id: input.lugar_tipo === 'faena' ? input.faena_id : null,
      sector: input.sector || null,
      acompanantes: input.acompanantes || null,
      foco: input.foco || null,
      responsable_id: uid ?? null,
      created_by: uid ?? null,
    })
    .select()
    .single()
  if (eRecorrido || !recorrido) return { data: null, error: eRecorrido }

  // 3. Pre-cargar respuestas desde las secciones de la plantilla
  const secciones = (plantilla.secciones ?? []) as GembaSeccion[]
  let orden = 0
  const filas = secciones.flatMap((sec) =>
    sec.items.map((item) => ({
      recorrido_id: recorrido.id,
      seccion: sec.titulo,
      orden: ++orden,
      item,
    }))
  )
  const { error: eRespuestas } = await supabase.from('gemba_respuestas').insert(filas)
  if (eRespuestas) return { data: null, error: eRespuestas }

  return { data: recorrido as GembaRecorrido, error: null }
}

export async function updateGembaRespuesta(
  id: string,
  cambios: { evaluacion?: GembaEvaluacion | null; observacion?: string }
) {
  const { data, error } = await supabase
    .from('gemba_respuestas')
    .update(cambios)
    .eq('id', id)
    .select()
    .single()
  return { data: data as GembaRespuesta | null, error }
}

export async function createGembaHallazgo(input: {
  recorrido_id: string
  respuesta_id?: string
  descripcion: string
  accion_correctiva?: string
  responsable_texto?: string
  fecha_compromiso?: string
}) {
  const { data: auth } = await supabase.auth.getUser()
  const { data, error } = await supabase
    .from('gemba_hallazgos')
    .insert({ ...input, created_by: auth?.user?.id ?? null })
    .select()
    .single()
  return { data: data as GembaHallazgo | null, error }
}

export async function updateGembaHallazgo(
  id: string,
  cambios: {
    descripcion?: string
    accion_correctiva?: string
    responsable_texto?: string
    fecha_compromiso?: string
    estado?: GembaEstadoHallazgo
    fecha_cierre?: string | null
  }
) {
  const { data, error } = await supabase
    .from('gemba_hallazgos')
    .update(cambios)
    .eq('id', id)
    .select()
    .single()
  return { data: data as GembaHallazgo | null, error }
}

export async function cerrarGembaRecorrido(id: string, observaciones?: string) {
  const hora = new Date().toTimeString().slice(0, 5)
  const { data, error } = await supabase
    .from('gemba_recorridos')
    .update({ estado: 'cerrado', hora_termino: hora, observaciones: observaciones || null })
    .eq('id', id)
    .select()
    .single()
  return { data: data as GembaRecorrido | null, error }
}

export async function getFaenasActivas() {
  const { data, error } = await supabase
    .from('faenas')
    .select('id, nombre, codigo')
    .eq('estado', 'activa')
    .order('nombre')
  return { data: data as Array<{ id: string; nombre: string; codigo: string }> | null, error }
}
