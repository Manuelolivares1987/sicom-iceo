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

export type PanelTaller = {
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

export type CombustibleCoquimbo = {
  franke: {
    movimientos_periodo: number
    litros_periodo: number
    ultimo_movimiento: string | null
    camiones_activos: number
    estanques_fijos: number
    dias_cuadre: number
  }
  romeral: {
    ubicaciones: number
    equipos: number
    despachos_periodo: number
    litros_periodo: number
    despachos_total: number
    ultimo_despacho: string | null
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
