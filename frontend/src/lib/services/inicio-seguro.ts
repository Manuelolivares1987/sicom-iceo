import { supabase } from '@/lib/supabase'
import { compressImage } from '@/lib/image/compress'
import type { EdcId } from '@/lib/inicio-seguro/psgcc'

// ============================================================================
// Inicio Seguro (MIG735): bloqueos con foto + visto bueno de Hersaly antes de
// iniciar un servicio ENEX. La escritura va por RPC; el correo lo pide el
// teléfono a /api/inicio-seguro/correo (sin service_role).
// ============================================================================

export type EstadoInicio = 'pendiente' | 'aprobado' | 'rechazado' | 'detenido' | 'cerrado'

export type Bloqueo = { energia: string; punto: string; foto_bloqueo: string; foto_energia_cero: string }
export type RespuestaPsgcc = { edc: EdcId; control: string; pregunta: string; fuente: string; respuesta: 'si' | 'no' | 'na' }
export type MiembroCuadrilla = { personal_id: string; nombre: string; habilitado: boolean; pendientes: string[]; leyo_art: boolean }

export type InicioSeguro = {
  id: string
  client_uuid: string
  programacion_id: string
  tarea: string
  cuadrilla: MiembroCuadrilla[]
  art: { texto?: string; asistida?: boolean }
  psgcc: RespuestaPsgcc[]
  bloqueos: Bloqueo[]
  sin_bloqueo_motivo: string | null
  estado: EstadoInicio
  solicitado_at: string
  decidido_at: string | null
  decidido_por_nombre?: string | null
  comentario: string | null
  detenido_motivo: string | null
  minutos_escalamiento?: number
  escalado_at: string | null
  // bandeja
  instalacion?: string
  faena?: string
  tipo_servicio?: string
  solicitado_por_nombre?: string | null
}

export type PersonaHabilitacion = {
  personal_id: string; nombre: string; cargo: string | null; habilitado: boolean
  requisitos: { nombre: string; ok: boolean; aplica_a: string }[]
}

export async function getEstadoInicio(programacionId: string): Promise<InicioSeguro | null> {
  const { data, error } = await supabase.rpc('rpc_inicio_seguro_estado', { p_programacion_id: programacionId })
  if (error) throw new Error(error.message)
  return (data as InicioSeguro | null) ?? null
}

export async function getCuadrillaCalama(): Promise<PersonaHabilitacion[]> {
  const { data, error } = await supabase.rpc('fn_prevencion_habilitacion', { p_grupo: 'CALAMA' })
  if (error) throw new Error(error.message)
  return ((data as { personas?: PersonaHabilitacion[] })?.personas ?? [])
}

export async function subirFotoInicio(blob: Blob): Promise<string> {
  const liviana = await compressImage(blob as File, { maxDim: 1600, quality: 0.75 }).catch(() => blob)
  const path = `inicio-seguro/${Date.now()}_${Math.floor(Math.random() * 1e6)}.jpg`
  const { error } = await supabase.storage.from('evidencias-verificacion').upload(path, liviana, { contentType: 'image/jpeg' })
  if (error) throw new Error(error.message)
  return supabase.storage.from('evidencias-verificacion').getPublicUrl(path).data.publicUrl
}

export async function solicitarInicio(payload: Record<string, unknown>): Promise<InicioSeguro> {
  const { data, error } = await supabase.rpc('rpc_inicio_seguro_solicitar', { p: payload })
  if (error) throw new Error(error.message)
  return data as InicioSeguro
}

/** Pide el correo (solicitud o escalamiento). No bloquea: si falla, el visto bueno igual se puede dar desde la bandeja. */
export async function pedirCorreo(id: string, tipo: 'solicitud' | 'escalamiento' | 'detencion'): Promise<void> {
  try {
    const { data: { session } } = await supabase.auth.getSession()
    await fetch('/api/inicio-seguro/correo/', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${session?.access_token ?? ''}` },
      body: JSON.stringify({ id, tipo }),
    })
  } catch { /* sin señal: se reintenta en el próximo ciclo */ }
}

export async function detenerInicio(id: string, motivo: string): Promise<void> {
  const { error } = await supabase.rpc('rpc_inicio_seguro_detener', { p_id: id, p_motivo: motivo })
  if (error) throw new Error(error.message)
}

export async function cerrarInicio(id: string, retiro: { punto: string; foto_retiro: string }[]): Promise<void> {
  const { error } = await supabase.rpc('rpc_inicio_seguro_cerrar', { p_id: id, p_retiro: retiro })
  if (error) throw new Error(error.message)
}

export async function getBandejaInicio(): Promise<InicioSeguro[]> {
  const { data, error } = await supabase.rpc('rpc_inicio_seguro_bandeja')
  if (error) throw new Error(error.message)
  return (data ?? []) as InicioSeguro[]
}

export async function decidirInicio(id: string, aprobar: boolean, comentario: string): Promise<void> {
  const { error } = await supabase.rpc('rpc_inicio_seguro_decidir', { p_id: id, p_aprobar: aprobar, p_comentario: comentario })
  if (error) throw new Error(error.message)
}

export async function soyAprobador(): Promise<boolean> {
  const { data } = await supabase.rpc('fn_inicio_seguro_es_aprobador')
  return !!data
}
