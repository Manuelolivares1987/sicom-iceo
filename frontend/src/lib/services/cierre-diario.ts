import { supabase } from '@/lib/supabase'

// ── Estados del dia (estado_codigo) ────────────────────────
export type EstadoCodigo =
  | 'A' | 'C' | 'D' | 'H' | 'R' | 'M' | 'T' | 'F' | 'V' | 'U' | 'L'

export const ESTADO_CODIGO_LABELS: Record<EstadoCodigo, string> = {
  A: 'Arrendado', C: 'En contrato', D: 'Disponible', H: 'Habilitación',
  R: 'Recepción', M: 'Mantención', T: 'Taller', F: 'Fuera de servicio',
  V: 'Venta', U: 'Uso interno', L: 'Leasing',
}

export const ESTADO_CODIGO_COLORS: Record<EstadoCodigo, string> = {
  A: 'bg-green-100 text-green-700 border-green-300',
  C: 'bg-emerald-100 text-emerald-700 border-emerald-300',
  D: 'bg-blue-100 text-blue-700 border-blue-300',
  H: 'bg-purple-100 text-purple-700 border-purple-300',
  R: 'bg-cyan-100 text-cyan-700 border-cyan-300',
  M: 'bg-amber-100 text-amber-700 border-amber-300',
  T: 'bg-orange-100 text-orange-700 border-orange-300',
  F: 'bg-red-100 text-red-700 border-red-300',
  V: 'bg-pink-100 text-pink-700 border-pink-300',
  U: 'bg-teal-100 text-teal-700 border-teal-300',
  L: 'bg-violet-100 text-violet-700 border-violet-300',
}

export const ESTADO_CODIGO_ORDEN: EstadoCodigo[] =
  ['A', 'C', 'L', 'U', 'D', 'R', 'H', 'M', 'T', 'F', 'V']

// ── Tipos ──────────────────────────────────────────────────
export interface PropuestaCierreRow {
  activo_id: string
  patente: string | null
  codigo: string | null
  equipamiento: string | null
  cliente_actual: string | null
  contrato_id: string | null
  contrato_label: string | null
  estado_previo: EstadoCodigo | null
  estado_sugerido: EstadoCodigo | null
  geocerca_nombre: string | null
  gps_ts: string | null
  gps_lat: number | null
  gps_lng: number | null
  ya_confirmado: boolean
  estado_dia_actual: EstadoCodigo | null
}

export interface ContratoOpcion {
  id: string
  codigo: string
  cliente: string | null
}

export interface CierreItem {
  activo_id: string
  estado_codigo: EstadoCodigo
  contrato_id: string | null
}

// ── RPCs ───────────────────────────────────────────────────

export async function getPropuestaCierre(fecha: string): Promise<PropuestaCierreRow[]> {
  const { data, error } = await supabase.rpc('fn_propuesta_cierre_diario', { p_fecha: fecha })
  if (error) throw error
  return (data ?? []) as PropuestaCierreRow[]
}

export async function getContratosActivos(): Promise<ContratoOpcion[]> {
  const { data, error } = await supabase
    .from('contratos')
    .select('id, codigo, cliente')
    .eq('estado', 'activo')
    .order('codigo')
  if (error) throw error
  return (data ?? []) as ContratoOpcion[]
}

export async function confirmarCierre(
  fecha: string,
  items: CierreItem[],
): Promise<{ success: boolean; confirmados: number; fecha: string }> {
  const { data, error } = await supabase.rpc('rpc_confirmar_cierre_diario', {
    p_fecha: fecha,
    p_items: items,
  })
  if (error) throw error
  return data as { success: boolean; confirmados: number; fecha: string }
}

// ── Helper: frescura del GPS ───────────────────────────────
export function frescuraGps(ts: string | null): { texto: string; viejo: boolean } {
  if (!ts) return { texto: 'sin señal', viejo: true }
  const min = Math.floor((Date.now() - new Date(ts).getTime()) / 60000)
  const viejo = min > 48 * 60
  if (min < 60) return { texto: `hace ${min} min`, viejo }
  const h = Math.floor(min / 60)
  if (h < 24) return { texto: `hace ${h} h`, viejo }
  return { texto: `hace ${Math.floor(h / 24)} d`, viejo }
}
