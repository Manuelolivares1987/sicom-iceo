// ============================================================================
// Cuánto nos estamos demorando. [MIG399]
// ----------------------------------------------------------------------------
// Los relojes ya existían repartidos por la base; lo que faltaba era leerlos.
// Tres tramos, que es como se vive el trabajo en el taller:
//
//   1. El checklist   — cuánto toma revisar un equipo
//   2. El repuesto    — cuánto pasa entre que se pide y llega
//   3. La NC          — cuánto pasa entre que se detecta y se resuelve
//
// Ninguna de estas consultas rellena huecos. Donde el reloj no corrió, viene
// null y la pantalla lo dice: un cero fingido en un número que paga sueldos es
// peor que un hueco a la vista.
// ============================================================================
import { supabase } from '@/lib/supabase'

export type TiempoChecklist = {
  ejecucion_id: string
  ot_folio: string
  ot_tipo: string | null
  activo_codigo: string | null
  activo_patente: string | null
  ejecutor: string
  estado: string
  started_at: string | null
  finished_at: string | null
  horas_efectivas: number | null
  horas_pausado: number | null
  horas_colacion: number | null
  items_totales: number | null
  items_hechos: number | null
  min_por_item: number | null
  avance_final: number | null
}

export type TiempoRepuesto = {
  recurso_id: string
  ot_folio: string | null
  activo_codigo: string | null
  activo_patente: string | null
  que_se_pidio: string | null
  producto_codigo: string | null
  estado: string
  lo_pidio: string | null
  lo_aprobo: string | null
  pedido_at: string
  aprobado_at: string | null
  vale_folio: string | null
  vale_at: string | null
  entregado_at: string | null
  h_pedir_a_aprobar: number | null
  h_aprobar_a_vale: number | null
  h_vale_a_entrega: number | null
  h_total: number | null
  h_esperando: number | null
}

export type TiempoNC = {
  nc_id: string
  activo_codigo: string | null
  activo_patente: string | null
  descripcion: string | null
  severidad: string | null
  origen: string | null
  estado_planificacion: string | null
  resuelto: boolean | null
  detectada_at: string
  programada_para: string | null
  ot_inicio: string | null
  ot_termino: string | null
  resuelto_en: string | null
  dias_detectada_a_taller: number | null
  dias_detectada_a_resuelta: number | null
  dias_abierta: number | null
}

export async function getTiemposChecklist(): Promise<TiempoChecklist[]> {
  const { data, error } = await supabase
    .from('v_taller_tiempo_checklist').select('*')
    .order('started_at', { ascending: false }).limit(300)
  if (error) throw error
  return (data ?? []) as TiempoChecklist[]
}

export async function getTiemposRepuesto(): Promise<TiempoRepuesto[]> {
  const { data, error } = await supabase
    .from('v_taller_tiempo_repuesto').select('*')
    .order('pedido_at', { ascending: false }).limit(500)
  if (error) throw error
  return (data ?? []) as TiempoRepuesto[]
}

export async function getTiemposNC(): Promise<TiempoNC[]> {
  const { data, error } = await supabase
    .from('v_taller_tiempo_nc').select('*')
    .order('detectada_at', { ascending: false }).limit(500)
  if (error) throw error
  return (data ?? []) as TiempoNC[]
}

/** Promedio que ignora los nulos. Devuelve null si no hay ni un dato. */
export function promedio(xs: Array<number | null | undefined>): number | null {
  const v = xs.filter((x): x is number => typeof x === 'number' && !Number.isNaN(x))
  if (v.length === 0) return null
  return Math.round((v.reduce((a, b) => a + b, 0) / v.length) * 10) / 10
}

/** Mediana: con pocos datos, un caso extremo mueve el promedio y engaña. */
export function mediana(xs: Array<number | null | undefined>): number | null {
  const v = xs.filter((x): x is number => typeof x === 'number' && !Number.isNaN(x)).sort((a, b) => a - b)
  if (v.length === 0) return null
  const m = Math.floor(v.length / 2)
  const r = v.length % 2 ? v[m] : (v[m - 1] + v[m]) / 2
  return Math.round(r * 10) / 10
}

/** Horas a algo que se lee de un vistazo: «3,5 h», «2 días», «—». */
export function horasLegibles(h: number | null | undefined): string {
  if (h == null) return '—'
  if (h < 1) return `${Math.round(h * 60)} min`
  if (h < 48) return `${Math.round(h * 10) / 10} h`
  return `${Math.round((h / 24) * 10) / 10} días`
}
