import { supabase } from '@/lib/supabase'

// ============================================================================
// Panel de Gerencia — cuadrantes Coquimbo y Calama (MIG295)
// ----------------------------------------------------------------------------
// Todo el panel llega en UNA sola llamada a `fn_panel_gerencia`. La autorización
// vive en la base (fn_panel_gerencia_puede_ver): si el usuario no tiene permiso,
// el RPC responde 42501 y aquí se traduce a `noAutorizado`, no a un panel vacío
// —que se confundiría con "no hay datos"—.
// ============================================================================

export type CalidadDato = {
  dias_cargados: number
  dias_transcurridos: number
  cobertura_pct: number | null
  ultimo_dia: string | null
  dias_rezago: number
  equipos_por_dia: number | null
  equipos_ultimo_dia: number | null
  carga_manual: number
  carga_auto: number
  sugerencias_pendientes: number
  cron_estados_activo: boolean
}

/**
 * Taller. Separa tres cosas que MIG295 mezclaba en un solo total:
 *  · `periodo`  — lo que produjo el proceso digital en el mes en curso.
 *  · `arrastre` — lo abierto que nació antes (pasivo del proceso anterior).
 *  · totales vivos — la suma, para cuando lo que importa es la carga real.
 * El checklist digital con OT y NC arrancó en agosto 2026, así que sumarlos
 * hacía ver el proceso nuevo como responsable de un backlog que heredó.
 */
export type PanelTaller = {
  periodo: {
    ot_creadas: number
    ot_abiertas: number
    ot_cerradas: number
    ot_correctivas: number
    ot_preventivas: number
    ot_primera: string | null
    ot_ultima: string | null
    nc_creadas: number
    nc_abiertas: number
    nc_altas: number
    nc_primera: string | null
    nc_ultima: string | null
    nc_por_origen: Record<string, number>
  }
  arrastre: {
    ot_abiertas: number
    ot_mas_antigua: string | null
    ot_dias_prom: number | null
    nc_abiertas: number
    nc_mas_antigua: string | null
  }
  /** Día a día del período; solo días con actividad. */
  por_fecha: { fecha: string, ot: number, nc: number }[]

  ot_abiertas: number
  ot_correctivas: number
  ot_preventivas: number
  ot_en_ejecucion: number
  ot_pausadas: number
  ot_sin_responsable: number
  backlog_dias_prom: number | null
  backlog_mas_antigua: string | null
  ot_creadas_periodo: number
  ot_cerradas_periodo: number
  nc_abiertas: number
  nc_criticas_abiertas: number
  nc_periodo: number
}

export type EquipoDisponibilidad = {
  activo_id: string
  codigo: string
  patente: string | null
  nombre: string | null
  operacion: string | null
  dias_obs: number
  dias_up: number
  dias_down: number
  disponibilidad_pct: number | null
}

export type EquipoDetenido = {
  activo_id: string
  codigo: string
  patente: string | null
  nombre: string | null
  operacion: string | null
  dias_detenido: number
  dias_obs: number
  pct_detenido: number | null
  estado_actual: string | null
  detenido_desde: string | null
  dias_consecutivos: number
  ot_folio: string | null
  ot_estado: string | null
  ot_tipo: string | null
  comentario: string | null
  plan_accion: string | null
  responsable: string | null
  fecha_compromiso: string | null
}

export type CierreCombustibleFaena = {
  codigo: string
  nombre: string
  transacciones: number
  litros_venta: number
  litros_trasvasije: number
  litros_total: number
  fluctuacion_lt: number | null
  /** Fracción, no porcentaje: -0.0008 = -0,08%. */
  fluctuacion_pct: number | null
  dias_con_registro: number | null
  fecha_min: string | null
  fecha_max: string | null
  detalle_por_punto: { clave: string, litros: number }[]
  detalle_por_empresa: { clave: string, litros: number }[]
  fuente_archivo: string | null
  cargado_at: string | null
}

/**
 * Combustible de faenas. La distinción central:
 *  · CONTROLADO — hay cierre mensual cargado (viene de las planillas Excel de
 *    operación). El negocio se está midiendo.
 *  · TRAZADO    — además hay movimientos registrados en el sistema.
 * Hoy Franke y Romeral están controlados pero no trazados; la diferencia entre
 * `litros_total_periodo` y `trazado_en_sistema` es exactamente esa brecha.
 */
export type CombustibleCoquimbo = {
  faenas: CierreCombustibleFaena[]
  litros_total_periodo: number
  con_cierre_cargado: number
  trazado_en_sistema: {
    movimientos_franke: number
    despachos_romeral: number
    ultimo_movimiento: string | null
    ultimo_despacho: string | null
  }
  infraestructura: {
    camiones_activos: number
    estanques_fijos: number
    romeral_ubicaciones: number
    romeral_equipos: number
  }
}

export type FaenaEnex = {
  faena_id: string
  codigo: string
  nombre: string
  cliente_minero: string | null
  operador: string | null
  lineas: string | null
  vigencia_hasta: string | null
  facturacion_mensual: number | null
  pct_facturacion: number | null
  instalaciones: number
  programados: number
  ejecutados: number
  firmados: number
  cumplimiento_pct: number | null
  sin_plan: boolean
  ultima_ejecucion: string | null
  requerimientos_mes: number
  requerimientos_sin_firmar: number
  comentario: string | null
  plan_accion: string | null
  responsable: string | null
  fecha_compromiso: string | null
}

export type Comentario = {
  id: string
  semana: string
  ambito: 'semana' | 'cuadrante' | 'equipo' | 'faena_enex'
  cuadrante: string | null
  activo_id: string | null
  enex_faena_id: string | null
  texto: string
  plan_accion: string | null
  responsable: string | null
  fecha_compromiso: string | null
  autor_id: string | null
  created_at: string
  updated_at: string
}

export type PanelGerencia = {
  semana: {
    inicio: string
    fin: string
    mes_inicio: string
    mes_fin: string
    generado_at: string
  }
  calidad_dato: CalidadDato
  coquimbo: {
    taller: PanelTaller
    combustible: CombustibleCoquimbo
    disponibilidad: {
      equipos: number
      promedio: number | null
      bajo_90: number
      detalle: EquipoDisponibilidad[]
    }
    detenidos: EquipoDetenido[]
    comentario: Comentario | null
  }
  calama: {
    faenas: FaenaEnex[]
    facturacion_total: number | null
    faenas_sin_plan: number
    taller: PanelTaller
    disponibilidad: { equipos: number, promedio: number | null }
    detenidos: EquipoDetenido[]
    comentario: Comentario | null
  }
  comentario_semana: Comentario | null
}

export class PanelNoAutorizadoError extends Error {
  constructor() {
    super('No tienes permiso para ver el Panel de Gerencia.')
    this.name = 'PanelNoAutorizadoError'
  }
}

/** Trae el panel completo de la semana indicada (cualquier día de esa semana). */
export async function getPanelGerencia(semana?: string): Promise<PanelGerencia> {
  const { data, error } = await supabase.rpc('fn_panel_gerencia', {
    p_semana: semana ?? null,
  })
  if (error) {
    // 42501 = insufficient_privilege. Lo lanza fn_panel_gerencia a propósito.
    if (error.code === '42501' || /No autorizado/i.test(error.message)) {
      throw new PanelNoAutorizadoError()
    }
    throw error
  }
  return data as PanelGerencia
}

export type GuardarComentarioInput = {
  semana: string
  ambito: 'semana' | 'cuadrante' | 'equipo' | 'faena_enex'
  cuadrante?: 'coquimbo' | 'calama' | null
  activoId?: string | null
  enexFaenaId?: string | null
  texto: string
  planAccion?: string | null
  responsable?: string | null
  fechaCompromiso?: string | null
}

/**
 * Upsert del comentario. Texto vacío BORRA el comentario de ese ámbito —así el
 * usuario deshace sin necesitar un botón de eliminar aparte.
 */
export async function guardarComentario(input: GuardarComentarioInput) {
  const { data, error } = await supabase.rpc('fn_panel_comentario_guardar', {
    p_semana: input.semana,
    p_ambito: input.ambito,
    p_cuadrante: input.cuadrante ?? null,
    p_activo_id: input.activoId ?? null,
    p_enex_faena_id: input.enexFaenaId ?? null,
    p_texto: input.texto,
    p_plan_accion: input.planAccion ?? null,
    p_responsable: input.responsable ?? null,
    p_fecha_compromiso: input.fechaCompromiso ?? null,
  })
  if (error) throw error
  return data as string | null
}
