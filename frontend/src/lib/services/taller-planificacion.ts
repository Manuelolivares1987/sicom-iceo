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
}

export async function getPlanesActivo(activoId: string): Promise<PlanActivo[]> {
  const { data, error } = await supabase
    .from('planes_mantenimiento')
    .select('id, nombre, pauta:pautas_fabricante(nombre, duracion_estimada_hrs)')
    .eq('activo_id', activoId)
    .eq('activo_plan', true)
    .order('proxima_ejecucion_fecha', { ascending: true, nullsFirst: false })
  if (error) throw error
  type Raw = { id: string; nombre: string | null; pauta: { nombre: string; duracion_estimada_hrs: number | null } | null }
  return ((data ?? []) as unknown as Raw[]).map((r) => ({
    id: r.id,
    nombre: r.nombre,
    pauta_nombre: r.pauta?.nombre ?? null,
    duracion_estimada_hrs: r.pauta?.duracion_estimada_hrs ?? null,
  }))
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

// Patentes que deben entrar a mantención preventiva según su pauta (vencidas/próximas)
export interface PreventivaDue {
  plan_id: string
  activo_id: string
  patente: string | null
  equipamiento: string | null
  pauta_nombre: string | null
  duracion_estimada_hrs: number | null
  proxima_fecha: string | null
  dias_vencido: number          // >0 vencida, <0 faltan días
}

export async function getPreventivasDue(diasAdelante = 15): Promise<PreventivaDue[]> {
  const limite = new Date(Date.now() + diasAdelante * 86400000).toISOString().slice(0, 10)
  const { data, error } = await supabase
    .from('planes_mantenimiento')
    .select('id, proxima_ejecucion_fecha, activo:activos(id, patente, codigo, nombre), pauta:pautas_fabricante(nombre, duracion_estimada_hrs)')
    .eq('activo_plan', true)
    .lte('proxima_ejecucion_fecha', limite)
    .order('proxima_ejecucion_fecha', { ascending: true })
  if (error) throw error
  const hoy = Date.now()
  type Raw = {
    id: string; proxima_ejecucion_fecha: string | null
    activo: { id: string; patente: string | null; codigo: string | null; nombre: string | null } | null
    pauta: { nombre: string | null; duracion_estimada_hrs: number | null } | null
  }
  return ((data ?? []) as unknown as Raw[])
    .filter((r) => r.activo)
    .map((r) => ({
      plan_id: r.id,
      activo_id: r.activo!.id,
      patente: r.activo!.patente ?? r.activo!.codigo ?? '—',
      equipamiento: r.activo!.nombre ?? null,
      pauta_nombre: r.pauta?.nombre ?? null,
      duracion_estimada_hrs: r.pauta?.duracion_estimada_hrs ?? null,
      proxima_fecha: r.proxima_ejecucion_fecha,
      dias_vencido: r.proxima_ejecucion_fecha
        ? Math.round((hoy - new Date(r.proxima_ejecucion_fecha + 'T00:00:00').getTime()) / 86400000)
        : 0,
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

export async function programarOtTaller(params: {
  activoId: string
  tipo: TipoOtTaller
  prioridad: PrioridadTaller
  fecha: string | null
  responsableId: string | null
  planId: string | null
}): Promise<{ id: string; folio: string; estado: string }> {
  const { data, error } = await supabase.rpc('rpc_programar_ot_taller', {
    p_activo_id: params.activoId,
    p_tipo: params.tipo,
    p_prioridad: params.prioridad,
    p_fecha: params.fecha,
    p_responsable_id: params.responsableId,
    p_plan_mantenimiento_id: params.planId,
  })
  if (error) throw error
  return data as { id: string; folio: string; estado: string }
}
