// ============================================================================
// Guardar en el historial. [MIG405]
// ----------------------------------------------------------------------------
// Archivar NO es borrar: el registro queda con quién lo archivó, cuándo y por
// qué, y sale de las pantallas operativas. Lo que se pidió es que se vea más
// limpio, no que desaparezca la historia.
//
// Se archiva en LOTES y el lote se puede deshacer entero. Guardar 114 no
// conformidades de una vez y descubrir que treinta eran reales tiene que tener
// vuelta atrás.
// ============================================================================
import { supabase } from '@/lib/supabase'

/** Las tablas que aceptan archivo. Agregar una es una línea en la BD. */
export type EntidadArchivable =
  | 'no_conformidades'
  | 'ordenes_trabajo'
  | 'bodega_tickets'
  | 'ot_recursos_solicitados'
  | 'checklist_v2_instance'

export type ResultadoArchivo = {
  success: boolean
  archivados: number
  lote_id?: string
  entidad?: string
  motivo?: string
  mensaje?: string
}

export type LoteArchivo = {
  id: string
  entidad: string
  motivo: string
  n_registros: number
  archivado_at: string
  archivado_por_nombre: string
  revertido_at: string | null
  revertido_por_nombre: string | null
  vigente: boolean
}

export async function archivar(
  entidad: EntidadArchivable, ids: string[], motivo: string,
): Promise<ResultadoArchivo> {
  const { data, error } = await supabase.rpc('rpc_archivar', {
    p_entidad: entidad, p_ids: ids, p_motivo: motivo,
  })
  if (error) throw error
  return data as ResultadoArchivo
}

export async function deshacerLote(loteId: string) {
  const { data, error } = await supabase.rpc('rpc_desarchivar_lote', { p_lote: loteId })
  if (error) throw error
  return data as { success: boolean; devueltos: number; entidad: string }
}

/** El historial de lo que se guardó, para poder deshacerlo. */
export async function getLotesArchivo(entidad?: EntidadArchivable): Promise<LoteArchivo[]> {
  let q = supabase.from('v_archivo_lotes').select('*')
    .order('archivado_at', { ascending: false }).limit(100)
  if (entidad) q = q.eq('entidad', entidad)
  const { data, error } = await q
  if (error) throw error
  return (data ?? []) as LoteArchivo[]
}

// ── Por patente [MIG406] ────────────────────────────────────────────────────
// La unidad de trabajo real es el equipo. Ir entidad por entidad obliga a pasar
// por cinco menús para dejar UN camión limpio, y a la quinta alguien se olvida:
// el equipo queda sin NC pero con la OT vieja colgando.

export type EquipoParaArchivar = {
  activo_id: string
  activo_codigo: string
  patente: string | null
  activo_nombre: string | null
  tipo: string | null
  estado: string
  n_nc: number
  n_ot: number
  n_vales: number
  n_recursos: number
  n_checklists: number
  n_total: number
  /** Vales todavía sin despachar: plata parada que conviene ver antes. */
  vales_con_pendiente: number
}

export async function getEquiposParaArchivar(): Promise<EquipoParaArchivar[]> {
  const { data, error } = await supabase
    .from('v_equipos_para_archivar').select('*')
    .order('n_total', { ascending: false })
  if (error) throw error
  return (data ?? []) as EquipoParaArchivar[]
}

export type ResultadoArchivoEquipo = {
  success: boolean
  total: number
  lote_id?: string
  patentes?: string
  hasta?: string
  no_conformidades?: number
  ordenes_trabajo?: number
  vales?: number
  repuestos?: number
  checklists?: number
  mensaje?: string
}

export async function archivarEquipos(
  activoIds: string[], motivo: string, hasta?: string | null,
): Promise<ResultadoArchivoEquipo> {
  const { data, error } = await supabase.rpc('rpc_archivar_equipos', {
    p_activo_ids: activoIds, p_motivo: motivo, p_hasta: hasta ?? null,
  })
  if (error) throw error
  return data as ResultadoArchivoEquipo
}
