// ============================================================================
// Pauta del mecánico de faena (MIG357-359)
// ----------------------------------------------------------------------------
// Reemplaza las tres viñetas que hoy se escriben siete veces en la entrega de
// turno del mecánico de Franke. Todo cuelga de la faena: la pauta de un modelo
// en Franke no es la de Romeral, y el día que Romeral tenga la suya se siembra
// igual sin tocar este archivo.
// ============================================================================
import { supabase } from '@/lib/supabase'
import { compressImage } from '@/lib/image/compress'

export const FAENA_FRANKE = 'FAE-FRANCKE'

/** Una fila de la agenda: un equipo con una pauta que le toca. */
export type PautaAgenda = {
  faena_id: string
  activo_id: string
  activo_codigo: string | null
  patente: string | null
  activo_nombre: string | null
  activo_estado: string | null
  modelo: string | null
  horas_uso_actual: number | null
  kilometraje_actual: number | null
  pauta_id: string
  pauta_codigo: string
  pauta_nombre: string
  pauta_tipo: 'diaria' | 'programada'
  disparo_horas: number | null
  disparo_km: number | null
  items: number
  ultima_horometro: number | null
  ultima_kilometraje: number | null
  ultima_fecha: string | null
  origen_ultima: 'plan' | 'ejecucion'
  faltan_horas: number | null
  faltan_km: number | null
  senal: 'diaria' | 'vencida' | 'por_vencer' | 'al_dia' | 'sin_datos'
  ejecucion_hoy_id: string | null
  ejecucion_hoy_estado: 'borrador' | 'cerrada' | 'no_aplica' | null
  ejecucion_hoy_turno: string | null
  ejecucion_hoy_por: string | null
}

export type PautaItem = {
  id: string
  pauta_id: string
  orden: number
  bloque: string
  texto: string
  ayuda: string | null
  tipo_respuesta: 'ok_nok' | 'numero' | 'texto'
  unidad: string | null
  obligatorio: boolean
  foto_si_nok: boolean
  critico: boolean
  repuesto: string | null
}

export type Respuesta = {
  item_id: string
  resultado?: 'ok' | 'nok' | 'na' | null
  valor?: number | null
  texto?: string | null
  observacion?: string | null
  foto_url?: string | null
}

export type RespuestaGuardada = Respuesta & { id: string; nc_id: string | null }

export const TURNOS_FRANKE = ['Día', 'Noche'] as const

export async function getFaenaId(codigo = FAENA_FRANKE): Promise<string | null> {
  const { data, error } = await supabase.from('faenas').select('id').eq('codigo', codigo).maybeSingle()
  if (error) throw error
  return data?.id ?? null
}

export async function getAgenda(faenaId: string): Promise<PautaAgenda[]> {
  const { data, error } = await supabase.from('v_faena_pauta_agenda').select('*')
    .eq('faena_id', faenaId)
    .order('pauta_tipo')
    .order('activo_codigo')
  if (error) throw error
  return (data ?? []) as PautaAgenda[]
}

export async function getItems(pautaId: string): Promise<PautaItem[]> {
  const { data, error } = await supabase.from('faena_pauta_item').select('*')
    .eq('pauta_id', pautaId).order('orden')
  if (error) throw error
  return (data ?? []) as PautaItem[]
}

/** Lo ya contestado, para retomar una pauta a medias sin volver a empezar. */
export async function getRespuestas(ejecucionId: string): Promise<RespuestaGuardada[]> {
  const { data, error } = await supabase.from('faena_pauta_ejecucion_item')
    .select('id, item_id, resultado, valor, texto, observacion, foto_url, nc_id')
    .eq('ejecucion_id', ejecucionId)
  if (error) throw error
  return (data ?? []) as RespuestaGuardada[]
}

export async function subirFotoPauta(file: File | Blob): Promise<string> {
  const blob = await compressImage(file, { maxDim: 1600, quality: 0.75 })
  const path = `pauta-faena/${Date.now()}_${Math.floor(Math.random() * 1e6)}.jpg`
  const { error } = await supabase.storage.from('evidencias-verificacion')
    .upload(path, blob, { contentType: 'image/jpeg' })
  if (error) throw error
  return supabase.storage.from('evidencias-verificacion').getPublicUrl(path).data.publicUrl
}

export type GuardarPautaInput = {
  faenaId: string
  pautaId: string
  activoId: string
  fecha: string
  turno?: string | null
  items: Respuesta[]
  horometro?: number | null
  kilometraje?: number | null
  observacion?: string | null
  cerrar?: boolean
  ejecutadoPorNombre?: string | null
  noAplicaMotivo?: string | null
  clientUuid?: string | null
}

export type GuardarPautaResult = {
  success: boolean
  ejecucion_id: string
  estado: 'borrador' | 'cerrada' | 'no_aplica'
  hallazgos?: number
  no_conformidades?: number
}

export async function guardarPauta(p: GuardarPautaInput): Promise<GuardarPautaResult> {
  const { data, error } = await supabase.rpc('rpc_faena_pauta_guardar', {
    p_faena_id: p.faenaId,
    p_pauta_id: p.pautaId,
    p_activo_id: p.activoId,
    p_fecha: p.fecha,
    p_turno: p.turno ?? null,
    p_items: p.items,
    p_horometro: p.horometro ?? null,
    p_kilometraje: p.kilometraje ?? null,
    p_observacion: p.observacion ?? null,
    p_cerrar: p.cerrar ?? false,
    p_ejecutado_por_nombre: p.ejecutadoPorNombre ?? null,
    p_no_aplica_motivo: p.noAplicaMotivo ?? null,
    p_client_uuid: p.clientUuid ?? null,
  })
  if (error) throw error
  return data as GuardarPautaResult
}

/** El texto de la señal, en castellano de terreno y no en nombre de columna. */
export function textoSenal(a: PautaAgenda): string {
  if (a.pauta_tipo === 'diaria') return 'Todos los días'
  if (a.senal === 'sin_datos') return 'Falta la última mantención'
  if (a.senal === 'vencida') return 'Vencida'
  if (a.faltan_horas != null) return `Faltan ${Math.round(a.faltan_horas).toLocaleString('es-CL')} h`
  if (a.faltan_km != null) return `Faltan ${Math.round(a.faltan_km).toLocaleString('es-CL')} km`
  return 'Al día'
}
