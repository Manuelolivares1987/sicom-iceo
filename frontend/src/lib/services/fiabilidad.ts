import { supabase } from '@/lib/supabase'

// ── Tipos ────────────────────────────────────────────────

export type CategoriaUso =
  | 'arriendo_comercial'
  | 'leasing_operativo'
  | 'uso_interno'
  | 'venta'

export const CATEGORIA_LABELS: Record<CategoriaUso, string> = {
  arriendo_comercial: 'Arriendo Comercial',
  leasing_operativo: 'Leasing Operativo',
  uso_interno: 'Uso Interno',
  venta: 'Venta',
}

export const CATEGORIA_COLORS: Record<CategoriaUso, string> = {
  arriendo_comercial: 'bg-green-100 text-green-700 border-green-200',
  leasing_operativo: 'bg-blue-100 text-blue-700 border-blue-200',
  uso_interno: 'bg-cyan-100 text-cyan-700 border-cyan-200',
  venta: 'bg-purple-100 text-purple-700 border-purple-200',
}

export interface FiabilidadActivo {
  activo_id: string
  patente: string
  categoria_uso: CategoriaUso | null
  dias_observados: number
  dias_up: number
  dias_down: number
  eventos_falla: number
  mtbf_dias: number
  mttr_dias: number
  disponibilidad_inherente: number
  disponibilidad_fisica: number
}

export interface FiabilidadFlota {
  categoria: CategoriaUso | null
  total_equipos: number
  dias_equipo: number
  dias_up: number
  dias_down: number
  eventos_falla_total: number
  disponibilidad_fisica: number
  utilizacion_bruta: number
  mtbf_agregado: number
  mttr_agregado: number
}

export interface OEEFiabilidadActivo {
  activo_id: string
  patente: string
  total_dias: number
  dias_a: number
  dias_d: number
  dias_h: number
  dias_r: number
  dias_v: number
  dias_u: number
  dias_l: number
  dias_m: number
  dias_t: number
  dias_f: number
  oee_a: number | null
  oee_p: number | null
  oee_q: number | null
  oee_total: number | null
}

// ── RPCs ────────────────────────────────────────────────

export async function getFiabilidadActivo(
  activoId: string,
  fechaInicio: string,
  fechaFin: string,
) {
  const { data, error } = await supabase.rpc('fn_calcular_fiabilidad_activo', {
    p_activo_id: activoId,
    p_fecha_inicio: fechaInicio,
    p_fecha_fin: fechaFin,
  })
  return { data: data?.[0] as FiabilidadActivo | undefined, error }
}

export async function getFiabilidadFlota(
  fechaInicio: string,
  fechaFin: string,
  categoria?: CategoriaUso,
) {
  const { data, error } = await supabase.rpc('fn_calcular_fiabilidad_flota', {
    p_fecha_inicio: fechaInicio,
    p_fecha_fin: fechaFin,
    p_categoria: categoria ?? null,
  })
  return { data: data as FiabilidadFlota[] | null, error }
}

export async function getOEEFiabilidadActivo(
  activoId: string,
  fechaInicio: string,
  fechaFin: string,
) {
  const { data, error } = await supabase.rpc('fn_calcular_oee_fiabilidad_activo', {
    p_activo_id: activoId,
    p_fecha_inicio: fechaInicio,
    p_fecha_fin: fechaFin,
  })
  return { data: data?.[0] as OEEFiabilidadActivo | undefined, error }
}

// ── Lista de activos con categoria y stats combinados ──
// (usado por el dashboard para construir la tabla detalle por equipo)

export interface ActivoFiabilidadDetalle extends FiabilidadActivo {
  marca?: string | null
  modelo?: string | null
  equipamiento?: string | null
  anio_fabricacion?: number | null
  cliente_actual?: string | null
  codigo_ceco?: string | null
  oee_a: number | null
  oee_p: number | null
  oee_q: number | null
  oee_total: number | null
  dias_a: number
  dias_d: number
  dias_h: number
  dias_r: number
  dias_v: number
  dias_u: number
  dias_l: number
  dias_m: number
  dias_t: number
  dias_f: number
}

export async function getDetalleFiabilidadFlota(
  fechaInicio: string,
  fechaFin: string,
): Promise<{ data: ActivoFiabilidadDetalle[]; error: unknown }> {
  // 1) Traer todos los activos moviles (no dados de baja) con metadata
  const { data: activos, error: errActivos } = await supabase
    .from('activos')
    .select(
      'id, patente, codigo, nombre, tipo, anio_fabricacion, categoria_uso, cliente_actual, modelo:modelos(nombre, marca:marcas(nombre))',
    )
    .in('tipo', ['camion_cisterna', 'camion', 'camioneta', 'lubrimovil', 'equipo_menor'])
    .neq('estado', 'dado_baja')
    .order('patente')

  if (errActivos || !activos) return { data: [], error: errActivos }

  // 2) Para cada uno, pedir fiabilidad + oee-fiabilidad en paralelo
  const detalles = await Promise.all(
    activos.map(async (a: any) => {
      const [fiab, oee] = await Promise.all([
        getFiabilidadActivo(a.id, fechaInicio, fechaFin),
        getOEEFiabilidadActivo(a.id, fechaInicio, fechaFin),
      ])
      return {
        activo_id: a.id,
        patente: a.patente ?? a.codigo ?? '',
        categoria_uso: a.categoria_uso as CategoriaUso | null,
        marca: a.modelo?.marca?.nombre ?? null,
        modelo: a.modelo?.nombre ?? null,
        equipamiento: a.nombre ?? null,
        anio_fabricacion: a.anio_fabricacion ?? null,
        cliente_actual: a.cliente_actual ?? null,
        codigo_ceco: a.codigo ?? null,
        dias_observados: fiab.data?.dias_observados ?? 0,
        dias_up: fiab.data?.dias_up ?? 0,
        dias_down: fiab.data?.dias_down ?? 0,
        eventos_falla: fiab.data?.eventos_falla ?? 0,
        mtbf_dias: Number(fiab.data?.mtbf_dias ?? 0),
        mttr_dias: Number(fiab.data?.mttr_dias ?? 0),
        disponibilidad_inherente: Number(fiab.data?.disponibilidad_inherente ?? 0),
        disponibilidad_fisica: Number(fiab.data?.disponibilidad_fisica ?? 0),
        dias_a: oee.data?.dias_a ?? 0,
        dias_d: oee.data?.dias_d ?? 0,
        dias_h: oee.data?.dias_h ?? 0,
        dias_r: oee.data?.dias_r ?? 0,
        dias_v: oee.data?.dias_v ?? 0,
        dias_u: oee.data?.dias_u ?? 0,
        dias_l: oee.data?.dias_l ?? 0,
        dias_m: oee.data?.dias_m ?? 0,
        dias_t: oee.data?.dias_t ?? 0,
        dias_f: oee.data?.dias_f ?? 0,
        oee_a: oee.data?.oee_a ?? null,
        oee_p: oee.data?.oee_p ?? null,
        oee_q: oee.data?.oee_q ?? null,
        oee_total: oee.data?.oee_total ?? null,
      } as ActivoFiabilidadDetalle
    }),
  )

  // Solo filas con datos observados
  return { data: detalles.filter((d) => d.dias_observados > 0), error: null }
}

// ── Actualizar categoria_uso del activo (manual) ──

export async function updateCategoriaActivo(
  activoId: string,
  categoria: CategoriaUso | null,
) {
  const { data, error } = await supabase
    .from('activos')
    .update({ categoria_uso: categoria })
    .eq('id', activoId)
    .select('id, patente, categoria_uso')
    .single()
  return { data, error }
}
