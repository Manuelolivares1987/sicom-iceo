// ============================================================================
// Entrega de unidades: acta simple por camión (MIG665)
// ----------------------------------------------------------------------------
// Quien entrega en terreno elige los camiones, saca 7 fotos de cada uno, anota
// las llaves que recibe el cliente y las copias que quedan en Pillado; quien
// recibe firma una vez para todos. Queda un acta (folio ENT-) por camión.
// Las fotos se suben al sacarlas; la RPC valida que estén las 7.
// ============================================================================

import { supabase } from '@/lib/supabase'
import { subirEvidencia } from '@/lib/image/evidencia'

export const BUCKET_ENTREGAS = 'evidencias-verificacion'

export const FOTOS_ENTREGA = [
  { tipo: 'frente', txt: 'Frente' },
  { tipo: 'atras', txt: 'Atrás' },
  { tipo: 'izquierda', txt: 'Lado izquierdo' },
  { tipo: 'derecha', txt: 'Lado derecho' },
  { tipo: 'cabina', txt: 'Cabina' },
  { tipo: 'tablero', txt: 'Tablero (km y horómetro)' },
  { tipo: 'llaves', txt: 'Llaves que se entregan' },
] as const
export type TipoFoto = (typeof FOTOS_ENTREGA)[number]['tipo']
export const TXT_FOTO: Record<string, string> = Object.fromEntries(FOTOS_ENTREGA.map((f) => [f.tipo, f.txt]))

export type CamionEntrega = {
  id: string; patente: string; codigo: string | null; tipo_equipamiento: string | null
  operacion: string | null; kilometraje_actual: number | null; horas_uso_actual: number | null
}

export type ActaEntrega = {
  id: string; folio: string; lote_id: string; activo_id: string; fecha: string; lugar: string | null
  empresa_recibe: string; recibe_nombre: string; recibe_rut: string; recibe_cargo: string | null
  firma_url: string; km: number | null; horometro: number | null
  llaves_entregadas: number; copias_en_pillado: number; observaciones: string | null
  fotos: { tipo: string; url: string }[]; estado: 'firmada' | 'anulada'; anulada_motivo: string | null
  patente: string; activo_codigo: string | null; tipo_equipamiento: string | null
  modelo: string | null; marca: string | null; entregado_por_nombre: string | null
}

export async function getCamionesEntregables(): Promise<CamionEntrega[]> {
  const { data, error } = await supabase
    .from('activos')
    .select('id, patente, codigo, tipo_equipamiento, operacion, kilometraje_actual, horas_uso_actual')
    .not('patente', 'is', null)
    .order('patente')
  if (error) throw error
  return (data ?? []) as CamionEntrega[]
}

export async function subirFotoEntrega(activoId: string, tipo: string, file: File): Promise<string> {
  return subirEvidencia(BUCKET_ENTREGAS, `entregas/${activoId}/${tipo}`, file)
}

export async function subirFirmaEntrega(dataUrl: string): Promise<string> {
  const blob = await (await fetch(dataUrl)).blob()
  const path = `entregas/firmas/${Date.now()}_${Math.random().toString(36).slice(2, 8)}.png`
  const { error } = await supabase.storage.from(BUCKET_ENTREGAS).upload(path, blob, { contentType: 'image/png' })
  if (error) throw new Error(`No se pudo subir la firma: ${error.message}`)
  return supabase.storage.from(BUCKET_ENTREGAS).getPublicUrl(path).data.publicUrl
}

export type CamionRegistro = {
  activo_id: string; km: string; horometro: string; llaves: number; copias: number
  observaciones: string; fotos: { tipo: string; url: string }[]
}

export async function registrarEntrega(camiones: CamionRegistro[],
  recibe: { empresa: string; nombre: string; rut: string; cargo: string; firma_url: string }, lugar: string) {
  const { data, error } = await supabase.rpc('rpc_entrega_unidades_registrar',
    { p_camiones: camiones, p_recibe: recibe, p_lugar: lugar })
  if (error) throw new Error(error.message)
  return data as { lote_id: string; actas: { patente: string; folio: string }[] }
}

export async function getActas(): Promise<ActaEntrega[]> {
  const { data, error } = await supabase.from('v_entregas_unidad').select('*').order('fecha', { ascending: false }).limit(200)
  if (error) throw error
  return (data ?? []) as ActaEntrega[]
}

export async function getActasLote(loteId: string): Promise<ActaEntrega[]> {
  const { data, error } = await supabase.from('v_entregas_unidad').select('*').eq('lote_id', loteId).order('patente')
  if (error) throw error
  return (data ?? []) as ActaEntrega[]
}

export async function anularActa(id: string, motivo: string) {
  const { error } = await supabase.rpc('rpc_entrega_unidad_anular', { p_id: id, p_motivo: motivo })
  if (error) throw new Error(error.message)
}
