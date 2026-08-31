import { supabase } from '@/lib/supabase'

// ============================================================================
// El bono del taller — MIG452 a MIG456
//
// Son dos mitades: el plan de incentivo (por cada OT cerrada) y el KPI de
// disponibilidad (un monto mensual por persona). El motor calcula las dos y el
// cierre las congela. Mientras el período no esté cerrado, todo lo que se lee
// acá es BORRADOR y así se muestra.
// ============================================================================

export type BonoLinea = {
  tecnico_id: string
  tecnico: string
  cargo: string | null
  ots: number
  plan_formula: number | null
  plan_calculado: number | null
  plan_tope: number | null
  plan_pagado: number | null
  kpi_pagado: number | null
  total: number | null
  dias_cargo: number | null
  dias_corte: number | null
  disponibilidad?: number | null
  tramo: string | null
  /** [MIG458] Lo que IMPIDE pagar: bloquea el cierre del período. */
  falta: string | null
  /** [MIG458] Lo que hay que SABER para leer el número. No bloquea nada. */
  aviso: string | null
  // Sólo cuando viene de un período cerrado.
  id?: string
  acuse_at?: string | null
  acuse_comentario?: string | null
}

export type BonoDetalle = {
  ot_id: string | null
  ot_folio: string | null
  concepto: string | null
  dias: number | null
  tramo: string | null
  participacion: number | null
  base_reparto: string | null
  monto_formula: number | null
  monto_propuesto: number | null
  falta: string | null
  aviso: string | null
}

export type BonoCartola = {
  cerrado: boolean
  borrador: boolean
  periodo: {
    id?: string
    nombre?: string
    desde: string
    hasta: string
    estado?: string
    disponibilidad_pct?: number | null
    disponibilidad_fuente?: string | null
    cerrado_at?: string | null
    cerrado_por?: string | null
    motivo_reapertura?: string | null
  }
  linea: BonoLinea | null
  detalle: BonoDetalle[]
}

export type BonoPeriodo = {
  id: string
  nombre: string
  desde: string
  hasta: string
  estado: 'cerrado' | 'reabierto'
  total_clp: number
  personas: number
  acusadas: number
  disponibilidad_pct: number | null
  cerrado_at: string
  cerrado_por: string | null
}

export type BonoDisponibilidad = {
  disponibilidad_pct: number | null
  promedio_diario_pct: number | null
  dias_equipo: number
  dias_equipo_buenos: number
  dias_con_registro: number
}

/** La cartola de una persona. Sin `tecnicoId` devuelve la del que pregunta. */
export async function getCartola(desde: string, hasta: string, tecnicoId?: string | null) {
  const { data, error } = await supabase.rpc('rpc_taller_bono_cartola', {
    p_desde: desde, p_hasta: hasta, p_tecnico_id: tecnicoId ?? null,
  })
  if (error) throw new Error(error.message)
  return data as BonoCartola
}

/** El resumen de todo el taller en el corte. Es la vista de jefatura. */
export async function getResumenBono(desde: string, hasta: string, disponibilidad?: number | null) {
  const { data, error } = await supabase.rpc('fn_taller_bono_resumen', {
    p_desde: desde, p_hasta: hasta, p_disponibilidad: disponibilidad ?? null,
  })
  if (error) throw new Error(error.message)
  return (data ?? []) as BonoLinea[]
}

export async function getDisponibilidadPeriodo(desde: string, hasta: string) {
  const { data, error } = await supabase.rpc('fn_taller_disponibilidad_periodo', {
    p_desde: desde, p_hasta: hasta,
  })
  if (error) throw new Error(error.message)
  return (Array.isArray(data) ? data[0] : data) as BonoDisponibilidad | null
}

export async function getPeriodos() {
  const { data, error } = await supabase.rpc('rpc_taller_bono_periodos')
  if (error) throw new Error(error.message)
  return (data ?? []) as BonoPeriodo[]
}

export async function cerrarPeriodo(args: {
  nombre: string; desde: string; hasta: string
  disponibilidad?: number | null; notas?: string | null
}) {
  const { data, error } = await supabase.rpc('rpc_taller_bono_cerrar_periodo', {
    p_nombre: args.nombre, p_desde: args.desde, p_hasta: args.hasta,
    p_disponibilidad: args.disponibilidad ?? null, p_notas: args.notas ?? null,
  })
  if (error) throw new Error(error.message)
  return data as { success: boolean; periodo_id: string; personas: number; total_clp: number }
}

export async function reabrirPeriodo(periodoId: string, motivo: string) {
  const { error } = await supabase.rpc('rpc_taller_bono_reabrir_periodo', {
    p_periodo_id: periodoId, p_motivo: motivo,
  })
  if (error) throw new Error(error.message)
}

/** El trabajador firma que revisó su cartola. Con comentario si no está de acuerdo. */
export async function acusarRecibo(lineaId: string, comentario?: string | null) {
  const { error } = await supabase.rpc('rpc_taller_bono_acusar_recibo', {
    p_linea_id: lineaId, p_comentario: comentario ?? null,
  })
  if (error) throw new Error(error.message)
}

// ── Utilidades de presentación ──────────────────────────────────────────────

export function clp(n: number | null | undefined): string {
  if (n == null) return '—'
  return '$' + Math.round(n).toLocaleString('es-CL')
}

/**
 * El corte de remuneraciones del taller va del 24 de un mes al 23 del siguiente,
 * como en las liquidaciones. No es el mes calendario.
 */
export function corteDelMes(ancla: Date): { desde: string; hasta: string; nombre: string } {
  const d = new Date(ancla)
  const hastaMes = d.getDate() >= 24 ? d.getMonth() + 1 : d.getMonth()
  const hasta = new Date(d.getFullYear(), hastaMes, 23)
  const desde = new Date(d.getFullYear(), hastaMes - 1, 24)
  const iso = (x: Date) =>
    `${x.getFullYear()}-${String(x.getMonth() + 1).padStart(2, '0')}-${String(x.getDate()).padStart(2, '0')}`
  const MESES = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
                 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre']
  return {
    desde: iso(desde),
    hasta: iso(hasta),
    nombre: `Corte ${MESES[hasta.getMonth()]} ${hasta.getFullYear()}`,
  }
}

export const CONCEPTO_LABEL: Record<string, string> = {
  MPN: 'Mantención preventiva (en arriendo)',
  MTN: 'Mantención total (post arriendo)',
  RCR: 'Reparación con reemplazo',
  RSR: 'Reparación sin reemplazo',
}
