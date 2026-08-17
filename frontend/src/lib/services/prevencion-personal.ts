import { supabase } from '@/lib/supabase'

// ============================================================================
// Control documental de personal — Prevención de Riesgos (MIG298)
// ----------------------------------------------------------------------------
// Pedido por auditoría. Reemplaza la planilla Excel de exámenes ocupacionales.
// ============================================================================

/**
 * Estados del semáforo. Los define la base (v_prevencion_examenes_estado) para
 * que pantalla, correo e informe de auditoría no puedan discrepar.
 *
 *  no_aplica     — exención declarada (ej. "no conduce en faena"). NO es brecha.
 *  observado     — fecha vigente pero el examen no sirve ante el mandante
 *                  (ej. laboratorio no aceptado por CMP).
 *  sin_dato      — falta el registro. En control documental el silencio es
 *                  incumplimiento, nunca conformidad.
 */
export type EstadoExamen =
  | 'vigente' | 'por_vencer_60' | 'por_vencer_30'
  | 'vencido' | 'sin_dato' | 'observado' | 'no_aplica'

export type ExamenPersona = {
  id: string
  personal_id: string
  tipo_codigo: string
  archivo_path?: string | null
  archivo_nombre?: string | null
  renovado_at?: string | null
  fecha_emision_real?: string | null
  /** Cuántas veces se renovó. >0 habilita ver el historial. */
  versiones_anteriores?: number
  /** Urgencia según el escalamiento de MIG299 (ventana de 60 días). */
  nivel_alerta?: 'vencido' | 'critico' | 'urgente' | 'alto' | 'medio' | 'ninguno' | 'sin_dato' | null
  tipo_nombre: string
  categoria: string
  orden: number
  laboratorio: string | null
  fecha_vencimiento: string | null
  dias_restantes: number | null
  aplica: boolean
  motivo_no_aplica: string | null
  observacion: string | null
  observacion_bloqueante: boolean
  archivo_url: string | null
  estado: EstadoExamen
}

export type PersonaControl = {
  personal_id: string
  rut: string
  nombres: string
  apellidos: string | null
  empresa: string | null
  nro_contrato: string | null
  faena_codigo: string | null
  cargo: string | null
  activo: boolean
  observacion: string | null
  vencidos: number
  observados: number
  sin_dato: number
  por_vencer_30: number
  por_vencer_60: number
  vigentes: number
  no_aplica: number
  proximo_vencimiento: string | null
  estado_general: 'no_conforme' | 'observado' | 'por_vencer' | 'conforme'
  examenes: ExamenPersona[]
}

export type ControlDocumental = {
  generado_at: string
  faena: string | null
  resumen: {
    personas: number
    no_conformes: number
    observados: number
    por_vencer: number
    conformes: number
    examenes_vencidos: number
    examenes_sin_dato: number
    examenes_observados: number
  }
  personas: PersonaControl[]
  faenas: { faena: string, personas: number }[]
}

export async function getControlDocumental(faena?: string | null) {
  const { data, error } = await supabase.rpc('fn_prevencion_control_documental', {
    p_faena: faena ?? null,
  })
  if (error) throw error
  return data as ControlDocumental
}

// ============================================================================
// Renovación con respaldo (MIG299)
// ----------------------------------------------------------------------------
// El bucket es PRIVADO: un examen ocupacional es un dato de salud de una
// persona identificada. Se guarda el path (no la URL) y se lee con URL firmada
// temporal — una URL firmada guardada en base sería basura al caducar.
// ============================================================================

export const BUCKET_EXAMENES = 'examenes-personal'

/** Ruta canónica: agrupa por persona y tipo, versionada por fecha de subida. */
export function examenPath(personalId: string, tipoCodigo: string, nombreArchivo: string) {
  const ext = (nombreArchivo.split('.').pop() ?? 'pdf').toLowerCase().slice(0, 5)
  const stamp = new Date().toISOString().replace(/[:.]/g, '-')
  return `personal/${personalId}/${tipoCodigo}/${stamp}.${ext}`
}

export async function subirArchivoExamen(
  personalId: string, tipoCodigo: string, archivo: File,
) {
  const path = examenPath(personalId, tipoCodigo, archivo.name)
  const { error } = await supabase.storage
    .from(BUCKET_EXAMENES)
    // upsert:false — cada renovación es un archivo nuevo, nunca se pisa el
    // anterior: el historial tiene que poder abrirse.
    .upload(path, archivo, { upsert: false, contentType: archivo.type || undefined })
  if (error) throw error
  return path
}

/** URL temporal para ver el respaldo. Caduca (por defecto 1 hora). */
export async function getUrlFirmadaExamen(path: string, expiresIn = 3600) {
  const { data, error } = await supabase.storage
    .from(BUCKET_EXAMENES)
    .createSignedUrl(path, expiresIn)
  if (error) throw error
  return data?.signedUrl ?? null
}

export type RenovarExamenInput = {
  examenId: string
  personalId: string
  tipoCodigo: string
  fechaVencimiento: string
  fechaEmision?: string | null
  laboratorio?: string | null
  observacion?: string | null
  archivo?: File | null
}

/**
 * Renueva el examen. Si viene archivo, se sube primero al bucket privado y
 * recién entonces se llama al RPC: así nunca queda una fecha nueva apuntando a
 * un respaldo que no se alcanzó a subir.
 */
export async function renovarExamen(i: RenovarExamenInput) {
  let path: string | null = null
  let nombre: string | null = null
  if (i.archivo) {
    path = await subirArchivoExamen(i.personalId, i.tipoCodigo, i.archivo)
    nombre = i.archivo.name
  }

  const { data, error } = await supabase.rpc('fn_prevencion_renovar_examen', {
    p_examen_id: i.examenId,
    p_fecha_vencimiento: i.fechaVencimiento,
    p_fecha_emision: i.fechaEmision ?? null,
    p_laboratorio: i.laboratorio ?? null,
    p_archivo_path: path,
    p_archivo_nombre: nombre,
    p_observacion: i.observacion ?? null,
  })
  if (error) throw error
  return data
}

export type VersionExamen = {
  id: string
  laboratorio: string | null
  fecha_vencimiento: string | null
  observacion: string | null
  archivo_path: string | null
  reemplazado_at: string
  motivo: string | null
}

/** Versiones anteriores: responde "¿estaba vigente el día del incidente?". */
export async function getHistorialExamen(examenId: string) {
  const { data, error } = await supabase
    .from('prevencion_examen_historial')
    .select('id, laboratorio, fecha_vencimiento, observacion, archivo_path, reemplazado_at, motivo')
    .eq('examen_id', examenId)
    .order('reemplazado_at', { ascending: false })
  if (error) throw error
  return (data ?? []) as VersionExamen[]
}

export type ActualizarExamenInput = {
  examenId: string
  laboratorio?: string | null
  fechaVencimiento?: string | null
  aplica?: boolean
  motivoNoAplica?: string | null
  observacion?: string | null
  observacionBloqueante?: boolean
}

/**
 * Edición directa del examen. La autorización la resuelve la RLS
 * (fn_prevencion_personal_puede_editar), no el frontend.
 */
export async function actualizarExamen(i: ActualizarExamenInput) {
  const patch: Record<string, unknown> = {}
  if (i.laboratorio !== undefined) patch.laboratorio = i.laboratorio || null
  if (i.fechaVencimiento !== undefined) patch.fecha_vencimiento = i.fechaVencimiento || null
  if (i.aplica !== undefined) patch.aplica = i.aplica
  if (i.motivoNoAplica !== undefined) patch.motivo_no_aplica = i.motivoNoAplica || null
  if (i.observacion !== undefined) patch.observacion = i.observacion || null
  if (i.observacionBloqueante !== undefined) patch.observacion_bloqueante = i.observacionBloqueante

  const { error } = await supabase
    .from('prevencion_examenes')
    .update(patch)
    .eq('id', i.examenId)
  if (error) throw error
}

// ============================================================================
// Envío del reporte a pedido (MIG303)
// ----------------------------------------------------------------------------
// El aviso automático manda solo lo que toca por cadencia. Esto manda la foto
// completa del momento, cuando prevención la necesita.
//
// Los destinatarios NO viajan desde el navegador: los decide el servidor según
// la faena (MIG302). Si la UI pudiera elegir libremente a quién enviar, el
// control de alcance de los externos no serviría de nada.
// ============================================================================

export type EnviarReporteInput = {
  faena?: string | null
  mensaje?: string | null
  incluirVigentes?: boolean
  /** Destinatario puntual adicional. Va en copia y queda registrado. */
  destinatarioExtra?: string | null
}

export type EnviarReporteResultado = {
  ok: true
  enviados: number
  destinatarios: string[]
  items: number
  vencidos: number
}

export async function enviarReporteDocumental(
  input: EnviarReporteInput,
): Promise<EnviarReporteResultado> {
  // La sesión identifica quién envía; la base valida que pueda.
  const { data: { session } } = await supabase.auth.getSession()
  if (!session) throw new Error('Sesión expirada. Vuelve a entrar.')

  const r = await fetch('/api/prevencion/enviar-reporte', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${session.access_token}`,
    },
    body: JSON.stringify(input),
  })
  const j = await r.json().catch(() => ({}))
  if (!r.ok || !j?.ok) throw new Error(j?.error ?? 'No se pudo enviar el reporte.')
  return j as EnviarReporteResultado
}

// ============================================================================
// Gestión de los ítems de una persona
// ----------------------------------------------------------------------------
// Sacar una exigencia (ej. la licencia de mina a quien no entra a mina) NO es
// borrarla: es declararla EXENTA con su motivo. Un ítem borrado desaparece sin
// dejar rastro y al recargar la planilla vuelve a aparecer como brecha; uno
// exento queda dicho, con quién lo decidió y por qué, que es lo que hay que
// mostrarle a una auditoría.
//
// El borrado real existe solo para lo que nunca debió estar (un tipo creado por
// error), y por eso está separado y en rojo en la interfaz.
// ============================================================================

export type TipoExamen = {
  codigo: string
  nombre: string
  categoria: string
  orden: number
}

export async function getTiposExamen() {
  const { data, error } = await supabase
    .from('prevencion_examen_tipos')
    .select('codigo, nombre, categoria, orden')
    .eq('activo', true)
    .order('orden')
  if (error) throw error
  return (data ?? []) as TipoExamen[]
}

/** Declara que la exigencia no aplica a esta persona. El motivo es obligatorio. */
export async function marcarNoAplica(examenId: string, motivo: string) {
  const m = motivo.trim()
  if (!m) throw new Error('Indica por qué no aplica: queda como respaldo ante auditoría.')
  const { error } = await supabase
    .from('prevencion_examenes')
    .update({
      aplica: false,
      motivo_no_aplica: m,
      // Una exención no arrastra el estado anterior: si mañana vuelve a
      // exigirse, se parte de cero y no de una fecha vieja que confunde.
      observacion_bloqueante: false,
    })
    .eq('id', examenId)
  if (error) throw error
}

/** Vuelve a exigir algo que estaba exento. */
export async function marcarAplica(examenId: string) {
  const { error } = await supabase
    .from('prevencion_examenes')
    .update({ aplica: true, motivo_no_aplica: null })
    .eq('id', examenId)
  if (error) throw error
}

/** Agrega a la persona un tipo que no tenía registrado. */
export async function agregarExamen(personalId: string, tipoCodigo: string) {
  const { error } = await supabase
    .from('prevencion_examenes')
    .insert({ personal_id: personalId, tipo_codigo: tipoCodigo, aplica: true })
  if (error) {
    if (error.code === '23505') throw new Error('Esa persona ya tiene ese ítem.')
    throw error
  }
}

/**
 * Borrado real. Solo para lo que nunca debió existir: pierde el historial de
 * versiones del ítem (cascade). Para "esta persona no lo necesita" va
 * marcarNoAplica, que sí deja constancia.
 */
export async function eliminarExamen(examenId: string) {
  const { error } = await supabase
    .from('prevencion_examenes')
    .delete()
    .eq('id', examenId)
  if (error) throw error
}

export type ActualizarPersonaInput = {
  personalId: string
  faenaCodigo?: string | null
  cargo?: string | null
  activo?: boolean
  observacion?: string | null
}

/**
 * Datos de la persona. Desactivar en vez de borrar: alguien que ya no trabaja
 * sale de los tableros y de las alertas, pero su historial documental queda
 * —hay fiscalizaciones que preguntan por gente que ya no está—.
 */
export async function actualizarPersona(i: ActualizarPersonaInput) {
  const patch: Record<string, unknown> = {}
  if (i.faenaCodigo !== undefined) patch.faena_codigo = i.faenaCodigo || null
  if (i.cargo !== undefined) patch.cargo = i.cargo || null
  if (i.activo !== undefined) patch.activo = i.activo
  if (i.observacion !== undefined) patch.observacion = i.observacion || null

  const { error } = await supabase
    .from('prevencion_personal')
    .update(patch)
    .eq('id', i.personalId)
  if (error) throw error
}
