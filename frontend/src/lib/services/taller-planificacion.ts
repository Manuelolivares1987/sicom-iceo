import { supabase } from '@/lib/supabase'

// Equipos hoy en mantención / taller / fuera de servicio (insumo del planificador)
export interface EquipoEnTaller {
  activo_id: string
  patente: string
  equipamiento: string | null
  estado_codigo: string        // M / T / F
  dias_mantencion: number | null
  ultimo_contrato: string | null
  motivo: string | null
}

export async function getEquiposEnTaller(): Promise<EquipoEnTaller[]> {
  const { data, error } = await supabase.rpc('fn_flota_en_mantenimiento')
  if (error) throw error
  return (data ?? []) as EquipoEnTaller[]
}

export interface OtAbierta {
  id: string
  folio: string
  tipo: string
  estado: string
  prioridad: string
  fecha_programada: string | null
  responsable_id: string | null
}

export async function getOtsAbiertasActivo(activoId: string): Promise<OtAbierta[]> {
  const { data, error } = await supabase
    .from('ordenes_trabajo')
    .select('id, folio, tipo, estado, prioridad, fecha_programada, responsable_id')
    .eq('activo_id', activoId)
    .in('estado', ['creada', 'asignada', 'en_ejecucion', 'pausada'])
    .order('created_at', { ascending: false })
  if (error) throw error
  return (data ?? []) as OtAbierta[]
}

export interface Tecnico { id: string; nombre_completo: string; cargo: string | null }

export async function getTecnicos(): Promise<Tecnico[]> {
  const { data, error } = await supabase
    .from('usuarios_perfil')
    .select('id, nombre_completo, cargo')
    .eq('activo', true)
    .eq('rol', 'tecnico_mantenimiento')
    .order('nombre_completo')
  if (error) throw error
  return (data ?? []) as Tecnico[]
}

export interface PlanActivo {
  id: string                   // id del plan_mantenimiento
  nombre: string | null
  pauta_nombre: string | null
  duracion_estimada_hrs: number | null
  /** [MIG490] Cuántos pasos trae la pauta: es el checklist que abre el mecánico. */
  pasos: number
  /**
   * Los pasos, en texto. El planificador tiene que poder ver QUÉ manda hacer la
   * pauta antes de programarla — si no, «PM Mensual» es una sigla y nadie sabe
   * si es lo que el camión necesita esta semana.
   *
   * [MIG494] Ojo: esto es la pauta CRUDA, donde un servicio escalonado dice
   * «SM2 completo». Para ver lo que realmente va a ver el mecánico, con esas
   * referencias abiertas, está `getActividadesDelPlan`.
   */
  actividades: string[]
}

export async function getPlanesActivo(activoId: string): Promise<PlanActivo[]> {
  const { data, error } = await supabase
    .from('planes_mantenimiento')
    // [MIG490] items_checklist: los pasos que el fabricante manda hacer. Ahora
    // son el checklist que abre el mecánico, así que se muestran al planificar.
    .select('id, nombre, pauta:pautas_fabricante(nombre, duracion_estimada_hrs, items_checklist)')
    .eq('activo_id', activoId)
    .eq('activo_plan', true)
    .order('proxima_ejecucion_fecha', { ascending: true, nullsFirst: false })
  if (error) throw error
  type Raw = {
    id: string; nombre: string | null
    pauta: { nombre: string; duracion_estimada_hrs: number | null; items_checklist: unknown[] } | null
  }
  return ((data ?? []) as unknown as Raw[]).map((r) => {
    // Los ítems vienen en dos formas en la base: texto suelto («Cambio aceite
    // motor + filtro») y objeto con orden/obligatorio/foto. Se leen las dos.
    const crudos = Array.isArray(r.pauta?.items_checklist) ? r.pauta!.items_checklist : []
    const actividades = crudos
      .map((it) => typeof it === 'string'
        ? it
        : (it as Record<string, unknown>)?.descripcion
          ?? (it as Record<string, unknown>)?.item
          ?? (it as Record<string, unknown>)?.nombre ?? '')
      .map((t) => String(t).trim())
      .filter(Boolean)
    return {
      id: r.id,
      nombre: r.nombre,
      pauta_nombre: r.pauta?.nombre ?? null,
      duracion_estimada_hrs: r.pauta?.duracion_estimada_hrs ?? null,
      pasos: actividades.length,
      actividades,
    }
  })
}

// Tareas (ítems no_ok) del checklist de recepción del equipo
export interface TareaRecepcion {
  instance_id: string
  fecha_recepcion: string | null
  item_id: string
  bloque: string | null
  orden: number
  descripcion: string
  observacion: string | null
  costo_estimado: number | null
  cobrable: string | null
}

export async function getTareasRecepcion(activoId: string): Promise<TareaRecepcion[]> {
  const { data, error } = await supabase.rpc('fn_tareas_recepcion_activo', { p_activo_id: activoId })
  if (error) throw error
  return (data ?? []) as TareaRecepcion[]
}

export async function programarOtRecepcion(params: {
  activoId: string
  prioridad: 'emergencia' | 'alta' | 'normal' | 'baja'
  fecha: string | null
  responsableId: string | null
}): Promise<{ id: string; folio: string; tareas_cargadas: number }> {
  const { data, error } = await supabase.rpc('rpc_programar_ot_recepcion', {
    p_activo_id: params.activoId,
    p_prioridad: params.prioridad,
    p_fecha: params.fecha,
    p_responsable_id: params.responsableId,
  })
  if (error) throw error
  return data as { id: string; folio: string; tareas_cargadas: number }
}

// Patentes que deben entrar a mantención preventiva según su pauta (vencidas/próximas).
// Multi-eje (fecha + km + horas) vía v_taller_preventivas_due (MIG174).
export interface PreventivaDue {
  plan_id: string
  activo_id: string
  patente: string | null
  equipamiento: string | null
  pauta_nombre: string | null
  duracion_estimada_hrs: number | null
  proxima_fecha: string | null
  vencida: boolean
  eje_critico: 'fecha' | 'km' | 'horas'
  detalle: string                 // texto legible del eje crítico (ej. "Vencida por 800 km")
  criticidad: number              // mayor = más urgente
  baseline_confiable: boolean     // false = la lectura km/h del plan está desfasada
  dias_restante: number | null
  dias_vencido: number            // compat: >0 vencida (por fecha), <0 faltan días
}

export async function getPreventivasDue(diasAdelante = 15): Promise<PreventivaDue[]> {
  const { data, error } = await supabase
    .from('v_taller_preventivas_due')
    .select('*')
    .order('criticidad', { ascending: false })
  if (error) throw error
  type Raw = {
    plan_id: string; activo_id: string
    patente: string | null; codigo: string | null; equipamiento: string | null
    pauta_nombre: string | null; duracion_estimada_hrs: number | null
    proxima_fecha: string | null
    dias_restante: number | null; frac_min: number | null
    vencida: boolean; eje_critico: 'fecha' | 'km' | 'horas'
    detalle: string; criticidad: number; baseline_confiable: boolean
  }
  return ((data ?? []) as unknown as Raw[])
    .filter((r) =>
      r.vencida ||
      (r.frac_min != null && r.frac_min <= 0.25) ||
      (r.dias_restante != null && r.dias_restante <= diasAdelante),
    )
    .map((r) => ({
      plan_id: r.plan_id,
      activo_id: r.activo_id,
      patente: r.patente ?? r.codigo ?? '—',
      equipamiento: r.equipamiento ?? null,
      pauta_nombre: r.pauta_nombre ?? null,
      duracion_estimada_hrs: r.duracion_estimada_hrs ?? null,
      proxima_fecha: r.proxima_fecha,
      vencida: r.vencida,
      eje_critico: r.eje_critico,
      detalle: r.detalle,
      criticidad: Number(r.criticidad ?? 0),
      baseline_confiable: r.baseline_confiable !== false,
      dias_restante: r.dias_restante,
      dias_vencido: r.dias_restante != null ? -r.dias_restante : (r.vencida ? 1 : 0),
    }))
}

// ── Revisión Técnica por vencer ─────────────────────────────────────────────
export type RtPorVencer = {
  activo_id: string
  patente: string | null
  codigo: string | null
  nombre: string | null
  fecha_vencimiento: string
  dias_restantes: number   // negativo = ya vencida
}

// Equipos cuya RT (revisión técnica) está vencida o vence dentro de N días.
// Toma la RT MÁS RECIENTE por equipo (la vigente) y filtra las que ya vencen.
export async function getRtPorVencer(diasAdelante = 30): Promise<RtPorVencer[]> {
  const { data, error } = await supabase
    .from('certificaciones')
    .select('fecha_vencimiento, activo:activos(id, patente, codigo, nombre, estado)')
    .eq('tipo', 'revision_tecnica')
    .order('fecha_vencimiento', { ascending: false })
  if (error) throw error
  const limite = Date.now() + diasAdelante * 86400000
  const hoy = Date.now()
  const seen = new Set<string>()
  type Raw = {
    fecha_vencimiento: string | null
    activo: { id: string; patente: string | null; codigo: string | null; nombre: string | null; estado: string } | null
  }
  const out: RtPorVencer[] = []
  for (const row of ((data ?? []) as unknown as Raw[])) {
    const a = row.activo
    if (!a?.id || seen.has(a.id)) continue
    seen.add(a.id)  // 1ª fila por activo = RT más reciente (orden desc)
    if (a.estado === 'dado_baja' || !row.fecha_vencimiento) continue
    const fv = new Date(row.fecha_vencimiento + 'T00:00:00').getTime()
    if (fv <= limite) {
      out.push({
        activo_id: a.id, patente: a.patente, codigo: a.codigo, nombre: a.nombre,
        fecha_vencimiento: row.fecha_vencimiento,
        dias_restantes: Math.ceil((fv - hoy) / 86400000),
      })
    }
  }
  return out.sort((x, y) => x.dias_restantes - y.dias_restantes)
}

// Sube el documento de la nueva RT a 'documentos/rt/<activoId>/'.
export async function subirDocumentoRt(activoId: string, file: File): Promise<string> {
  const safe = file.name.replace(/[^a-zA-Z0-9._-]/g, '_')
  const path = `rt/${activoId}/${Date.now()}-${safe}`
  const { error } = await supabase.storage.from('documentos').upload(path, file, { upsert: false })
  if (error) throw error
  const { data } = supabase.storage.from('documentos').getPublicUrl(path)
  return data.publicUrl
}

// Registra la RT renovada (nuevo doc + nuevo vencimiento) -> certificaciones.
export async function renovarRevisionTecnica(p: {
  activoId: string; fechaEmision: string; fechaVencimiento: string
  archivoUrl?: string | null; numero?: string | null; entidad?: string | null; otId?: string | null
}) {
  const { data, error } = await supabase.rpc('rpc_renovar_revision_tecnica', {
    p_activo_id: p.activoId,
    p_fecha_emision: p.fechaEmision,
    p_fecha_vencimiento: p.fechaVencimiento,
    p_archivo_url: p.archivoUrl ?? null,
    p_numero: p.numero ?? null,
    p_entidad: p.entidad ?? null,
    p_ot_id: p.otId ?? null,
  })
  if (error) throw error
  return data
}

// ── Documentos por vencer / vencidos (todos los tipos) ──────────────────────
export type DocumentoPorVencer = {
  activo_id: string
  patente: string | null
  codigo: string | null
  nombre: string | null
  operacion: string | null
  tipo: string
  fecha_vencimiento: string
  dias_restantes: number   // negativo = vencido
  bloqueante: boolean
  archivo_url: string | null
}

export const TIPO_DOC_LABEL: Record<string, string> = {
  revision_tecnica: 'Revisión Técnica',
  soap: 'SOAP',
  permiso_circulacion: 'Permiso de Circulación',
  permiso_municipal: 'Permiso Municipal',
  hermeticidad: 'Hermeticidad',
  tc8_sec: 'TC8 SEC',
  inscripcion_sec: 'Inscripción SEC',
  sec: 'SEC',
  seremi: 'SEREMI',
  siss: 'SISS',
  seguro_rc: 'Póliza de Seguro',
  fops_rops: 'FOPS/ROPS',
  cert_gancho: 'Certificación Gancho',
  calibracion: 'Cert. Calibración Surtidor',
  licencia_especial: 'Licencia Especial',
  // Carga documental flota 2026-07 (MIG226)
  analisis_gases: 'Análisis de Gases',
  padron: 'Padrón',
  inscripcion_rnvm: 'Inscripción RNVM',
  homologacion: 'Cert. Homologación',
  optico_sobrellenado: 'Cert. Sist. Óptico Sobrellenado',
  flujo_descarga: 'Cert. Flujo y Descarga',
  sist_riego: 'Cert. Sist. Riego',
  cert_cabina: 'Cert. Cabina',
  laminas_seguridad: 'Cert. Láminas de Seguridad',
  barra_antivuelco: 'Cert. Barra Antivuelco',
  operatividad: 'Cert. Operatividad',
  grilletes_eslingas: 'Cert. Grilletes y Eslingas',
  mant_hidraulico: 'Cert. Mant. Sist. Hidráulico',
  mantencion: 'Cert. Mantención',
  aire_acondicionado: 'Cert. Mant. Aire Acondicionado',
  tacografo: 'Cert. Tacógrafo',
  torque_ruedas: 'Cert. Torque Ruedas',
  ausencia_falla_ecm: 'Cert. Ausencia Falla ECM',
  gps: 'Cert. GPS',
  inventario_neumaticos: 'Inventario Neumáticos',
  ficha_tecnica: 'Ficha Técnica',
  factura_compra: 'Factura de Compra',
  manual: 'Manual',
  otra: 'Otro',
}

// Todos los tipos de documento que acepta la BD (tipo_certificacion_enum),
// ordenados por etiqueta. Es la lista que deben usar TODOS los formularios que
// cargan papeles: si se escribe la lista a mano se vuelve a caer en el bug de
// mandar un tipo que el enum no conoce.
export const TIPOS_DOC_OPCIONES: { value: string; label: string }[] =
  Object.entries(TIPO_DOC_LABEL)
    .map(([value, label]) => ({ value, label }))
    .sort((a, b) => a.label.localeCompare(b.label, 'es'))

// Equipos con documentos vencidos o que vencen dentro de N días (todos los tipos).
export async function getDocumentosPorVencer(diasAdelante = 30): Promise<DocumentoPorVencer[]> {
  const { data, error } = await supabase
    .from('v_documentos_equipo_estado')
    .select('activo_id, patente, codigo, nombre, operacion, tipo, fecha_vencimiento, dias_restantes, bloqueante, archivo_url')
    .lte('dias_restantes', diasAdelante)
    .order('dias_restantes', { ascending: true })
  if (error) throw error
  return (data ?? []) as DocumentoPorVencer[]
}

// Sube el documento renovado a 'documentos/cert/<tipo>/<activoId>/'.
export async function subirDocumentoCert(activoId: string, tipo: string, file: File): Promise<string> {
  const safe = file.name.replace(/[^a-zA-Z0-9._-]/g, '_')
  const path = `cert/${tipo}/${activoId}/${Date.now()}-${safe}`
  const { error } = await supabase.storage.from('documentos').upload(path, file, { upsert: false })
  if (error) throw error
  const { data } = supabase.storage.from('documentos').getPublicUrl(path)
  return data.publicUrl
}

// Registra la renovación (o el alta) de cualquier documento -> certificaciones.
// [MIG272] Es la única puerta de entrada: valida el rol, calcula el estado y
// deja registrado quién cargó el papel.
export async function renovarCertificacion(p: {
  activoId: string; tipo: string; fechaEmision: string; fechaVencimiento: string
  archivoUrl?: string | null; numero?: string | null; entidad?: string | null
  bloqueante?: boolean | null; notas?: string | null
  /**
   * [MIG433] De dónde salió la fecha: 'documento' si el lector la sacó del
   * archivo, 'manual' si la escribió quien sube el papel. Importa: sin esto la
   * base la toma por una fecha del sistema y el control del estándar la
   * descalifica, devolviendo «falta la fecha» sobre un papel recién cargado.
   */
  origen?: 'manual' | 'documento'
  /**
   * [MIG484] Cómo se llama el papel cuando el tipo es «otra». Obligatorio ahí:
   * sin nombre, dos «otros» del mismo equipo se tapan uno al otro —el sistema
   * los toma por versiones del mismo documento—.
   */
  tipoOtro?: string | null
}) {
  const { data, error } = await supabase.rpc('rpc_renovar_certificacion', {
    p_activo_id: p.activoId,
    p_tipo: p.tipo,
    p_fecha_emision: p.fechaEmision,
    p_fecha_vencimiento: p.fechaVencimiento,
    p_archivo_url: p.archivoUrl ?? null,
    p_numero: p.numero ?? null,
    p_entidad: p.entidad ?? null,
    p_bloqueante: p.bloqueante ?? null,
    p_notas: p.notas ?? null,
    p_origen: p.origen ?? 'manual',
    p_tipo_otro: p.tipoOtro?.trim() || null,
  })
  if (error) throw error
  return data
}

// Adjunta el PDF/foto a un documento ya registrado (sin crear otra fila).
export async function adjuntarArchivoCertificacion(certId: string, archivoUrl: string) {
  const { data, error } = await supabase.rpc('rpc_adjuntar_archivo_certificacion', {
    p_certificacion_id: certId,
    p_archivo_url: archivoUrl,
  })
  if (error) throw error
  return data
}

// ── Recepción por planificar (gatillo desde Sugerencias de estado) ──────────
export type RecepcionPorPlanificar = {
  activo_id: string; patente: string | null; codigo: string | null
  nombre: string | null; fecha_recepcion: string | null
}

export async function getRecepcionesPorPlanificar(): Promise<RecepcionPorPlanificar[]> {
  const { data, error } = await supabase
    .from('v_recepciones_por_planificar').select('*')
    .order('fecha_recepcion', { ascending: true })
  if (error) throw error
  return (data ?? []) as RecepcionPorPlanificar[]
}

// Crea la OT de inspección de recepción (+ informe + checklist) y devuelve la OT.
export async function programarRecepcion(activoId: string): Promise<{ ot_id: string; informe_id: string }> {
  const { data, error } = await supabase.rpc('fn_iniciar_informe_recepcion', { p_activo_id: activoId })
  if (error) throw error
  const d = data as { ot_id: string; informe_id: string }
  return { ot_id: d?.ot_id, informe_id: d?.informe_id }
}

// ── Correctivos de recepción por agendar (NC planificadas, OT sin día) ──────
export type NcOtPorAgendar = {
  nc_id: string; ot_id: string; ot_folio: string; activo_id: string
  patente: string | null; codigo: string | null; descripcion: string; severidad: string
  grupo_trabajo: string | null; horas_estimadas: number | null; tiempo_estimado_dias: number | null
  /** MIG209: la vista agrupa por OT — total de NC del equipo en esa OT. */
  n_ncs: number
}

export async function getNcOtsPorAgendar(): Promise<NcOtPorAgendar[]> {
  const { data, error } = await supabase.from('v_nc_ot_por_agendar').select('*').order('severidad', { ascending: true })
  if (error) throw error
  return (data ?? []) as NcOtPorAgendar[]
}

// ── Equipos auxiliares (jerarquía) ──────────────────────────────────────────
export interface EquipoSimple { id: string; patente: string | null; codigo: string | null; nombre: string | null }

export async function getEquiposPadre(): Promise<EquipoSimple[]> {
  const { data, error } = await supabase
    .from('activos')
    .select('id, patente, codigo, nombre')
    .in('tipo', ['camion_cisterna', 'camion', 'camioneta', 'lubrimovil', 'equipo_menor'])
    .is('activo_padre_id', null)
    .neq('estado', 'dado_baja')
    .order('patente')
  if (error) throw error
  return (data ?? []) as EquipoSimple[]
}

export interface Auxiliar {
  id: string; codigo: string | null; nombre: string | null; tipo: string
  planes: { id: string; pauta_nombre: string | null; duracion_estimada_hrs: number | null }[]
}

export async function getAuxiliares(padreId: string): Promise<Auxiliar[]> {
  const { data, error } = await supabase
    .from('activos')
    .select('id, codigo, nombre, tipo, planes:planes_mantenimiento(id, pauta:pautas_fabricante(nombre, duracion_estimada_hrs))')
    .eq('activo_padre_id', padreId)
    .order('codigo')
  if (error) throw error
  type Raw = { id: string; codigo: string | null; nombre: string | null; tipo: string
    planes: { id: string; pauta: { nombre: string; duracion_estimada_hrs: number | null } | null }[] }
  return ((data ?? []) as unknown as Raw[]).map((a) => ({
    id: a.id, codigo: a.codigo, nombre: a.nombre, tipo: a.tipo,
    planes: (a.planes ?? []).map((p) => ({ id: p.id, pauta_nombre: p.pauta?.nombre ?? null, duracion_estimada_hrs: p.pauta?.duracion_estimada_hrs ?? null })),
  }))
}

export interface PautaOpcion { id: string; nombre: string; duracion_estimada_hrs: number | null }

export async function getPautasTodas(): Promise<PautaOpcion[]> {
  const { data, error } = await supabase
    .from('pautas_fabricante')
    .select('id, nombre, duracion_estimada_hrs')
    .order('nombre')
  if (error) throw error
  return (data ?? []) as PautaOpcion[]
}

export type TipoAuxiliar = 'estanque' | 'bomba' | 'manguera' | 'equipo_menor'

export async function crearAuxiliar(padreId: string, nombre: string, tipo: TipoAuxiliar): Promise<{ id: string; codigo: string }> {
  const { data, error } = await supabase.rpc('rpc_crear_auxiliar', { p_padre_id: padreId, p_nombre: nombre, p_tipo: tipo })
  if (error) throw error
  return data as { id: string; codigo: string }
}

export async function asignarPauta(activoId: string, pautaId: string): Promise<void> {
  const { error } = await supabase.rpc('rpc_asignar_pauta', { p_activo_id: activoId, p_pauta_id: pautaId })
  if (error) throw error
}

export type TipoOtTaller = 'correctivo' | 'preventivo' | 'inspeccion'
export type PrioridadTaller = 'emergencia' | 'alta' | 'normal' | 'baja'

/**
 * Programa el trabajo en el plan semanal. Por defecto REUTILIZA la OT abierta
 * del mismo trabajo en vez de duplicarla (MIG256): así una tarea que se arrastra
 * varias semanas mantiene un solo folio, con su checklist y su avance, hasta que
 * se cierra. `reutilizar: false` fuerza una OT nueva.
 */
export async function programarOtTaller(params: {
  activoId: string
  tipo: TipoOtTaller
  prioridad: PrioridadTaller
  fecha: string | null
  responsableId: string | null
  planId: string | null
  reutilizar?: boolean
}): Promise<{ id: string; folio: string; estado: string; reutilizada?: boolean; mensaje?: string }> {
  const { data, error } = await supabase.rpc('rpc_programar_ot_taller', {
    p_activo_id: params.activoId,
    p_tipo: params.tipo,
    p_prioridad: params.prioridad,
    p_fecha: params.fecha,
    p_responsable_id: params.responsableId,
    p_plan_mantenimiento_id: params.planId,
    p_reutilizar: params.reutilizar ?? true,
  })
  if (error) throw error
  return data as { id: string; folio: string; estado: string; reutilizada?: boolean; mensaje?: string }
}

/** Una OT sigue «abierta» mientras no se ejecute, cierre ni cancele. Es el
 *  complemento exacto del filtro de fn_ot_abierta_reutilizable (MIG256). */
export const ESTADOS_OT_ABIERTA = ['creada', 'asignada', 'en_ejecucion', 'pausada'] as const

/** OT abierta del mismo trabajo, para avisar ANTES de programar. */
export async function getOtAbiertaDelTrabajo(
  activoId: string, tipo: TipoOtTaller, planId: string | null,
): Promise<{
  id: string; folio: string; estado: string; fecha_programada: string | null
  /** [MIG466] Desde cuándo corre el reloj: el bono cuenta días reales, no jornadas. */
  fecha_inicio: string | null; created_at: string
} | null> {
  let q = supabase
    .from('ordenes_trabajo')
    .select('id, folio, estado, fecha_programada, fecha_inicio, created_at, plan_mantenimiento_id')
    .eq('activo_id', activoId)
    .eq('tipo', tipo)
    .in('estado', ESTADOS_OT_ABIERTA)
    .order('created_at', { ascending: false })
    .limit(1)
  q = planId ? q.eq('plan_mantenimiento_id', planId) : q.is('plan_mantenimiento_id', null)
  const { data, error } = await q
  if (error) throw error
  return (data?.[0] as any) ?? null
}

// ── [MIG441] Los papeles del equipo, al momento de planificarlo ─────────────

export type PapelProblema = {
  tipo: string
  /** 'vencido' | 'por_vencer' | 'sin_fecha' */
  estado: string
  fecha_vencimiento: string | null
  dias_restantes: number | null
}

/**
 * Papeles vencidos, por vencer o sin fecha de un equipo.
 *
 * Se pregunta a la base y no se filtra la lista de "documentos por vencer" en
 * el cliente: esa lista trae sólo lo que vence dentro de N días y se quedaría
 * sin los que no tienen fecha, que son justamente de los que no sabemos nada.
 * Es la misma función que usa el trigger que avisa a la jefatura, así que lo
 * que ve el planificador y lo que se notifica no se pueden separar.
 */
export async function getPapelesProblema(activoId: string): Promise<PapelProblema[]> {
  const { data, error } = await supabase.rpc('rpc_activo_papeles_problema', { p_activo_id: activoId })
  if (error) throw error
  return (data ?? []) as PapelProblema[]
}

export function papelProblemaTexto(p: PapelProblema): string {
  if (p.estado === 'vencido') return `vencido hace ${Math.abs(p.dias_restantes ?? 0)} días`
  if (p.estado === 'por_vencer') return `vence en ${p.dias_restantes ?? 0} días`
  return 'sin fecha de vencimiento'
}

// ── [MIG472] Cierres con tareas pendientes, esperando a la jefatura ─────────
//
// Cerrar con obligatorias sin hacer se puede, pero no en silencio: la OT queda
// marcada y no paga bono hasta que el jefe de taller la apruebe o la devuelva.

export type CierrePorValidar = {
  ot_id: string
  folio: string
  patente: string | null
  equipo: string | null
  fecha_termino: string | null
  pendientes: number
  total: number
  motivo: string | null
  cerro: string | null
  cuadrilla: string | null
}

export async function getCierresPorValidar(): Promise<CierrePorValidar[]> {
  const { data, error } = await supabase.rpc('rpc_taller_cierres_por_validar')
  if (error) throw new Error(error.message)
  return (data ?? []) as CierrePorValidar[]
}

export async function validarCierre(otId: string, aprueba: boolean, comentario?: string | null) {
  const { data, error } = await supabase.rpc('rpc_taller_validar_cierre', {
    p_ot_id: otId, p_aprueba: aprueba, p_comentario: comentario ?? null,
  })
  if (error) throw new Error(error.message)
  return data as { success: boolean; folio: string; estado: string }
}

/**
 * [MIG484] Los nombres de «otro» que ya se usaron en la flota.
 *
 * Se ofrecen al cargar uno nuevo para que el mismo papel no termine escrito de
 * tres formas distintas («ADAS», «Adas tercer ojo», «Certificado ADAS»).
 */
export async function getTiposOtrosUsados(): Promise<{ nombre: string; usos: number }[]> {
  const { data, error } = await supabase
    .from('v_certificado_tipos_otros').select('nombre, usos')
  if (error) throw new Error(error.message)
  return (data ?? []) as { nombre: string; usos: number }[]
}

/**
 * [MIG494] Los pasos que va a ver el mecánico para este plan.
 *
 * No es lo mismo que `plan.actividades`: los servicios del fabricante son
 * escalonados y en la pauta el SM3 dice «SM2 completo». Acá esa referencia
 * viene abierta, con cada paso heredado marcado con el servicio del que sale.
 * El planificador tiene que aprobar la misma lista que recibe el taller.
 */
export async function getActividadesDelPlan(planId: string): Promise<{
  orden: number; descripcion: string; ayuda: string | null
}[]> {
  const { data, error } = await supabase
    .from('v_pauta_actividades')
    .select('orden, descripcion, ayuda')
    .eq('plan_mantenimiento_id', planId)
    .order('orden')
  if (error) throw error
  return (data ?? []) as { orden: number; descripcion: string; ayuda: string | null }[]
}
