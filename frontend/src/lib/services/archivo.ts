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
