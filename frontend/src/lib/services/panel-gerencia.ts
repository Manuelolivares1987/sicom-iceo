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

/** Fluctuación de un estanque. `origen` dice de dónde salió el número. */
export type FluctuacionPunto = {
  punto: string
  litros_despachados: number | null
  fluctuacion_lt: number | null
  /** Fracción: -0.0192 = -1,92%. Null = no se pudo leer, falta carga manual. */
  fluctuacion_pct: number | null
  dias_cuadrados: number | null
  origen: 'orpak' | 'excel' | 'manual'
  corregido_manual: boolean
  motivo_correccion: string | null
  observacion: string | null
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
  corregido_manual: boolean
  motivo_correccion: string | null
  corregido_at: string | null
  corregido_por_nombre: string | null
  /** Lo que decía la planilla antes de la corrección. Evidencia en reunión. */
  valores_originales: Record<string, unknown> | null
  puntos: FluctuacionPunto[]
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
  periodo: { anio: number, mes: number }
  faenas: CierreCombustibleFaena[]
  litros_total_periodo: number
  con_cierre_cargado: number
  corregidos_a_mano: number
  /** Estanques con |fluctuación| > 0,5%, el umbral de gestión. */
  puntos_fuera_umbral: number
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

// ============================================================================
// Portada del panel (MIG305)
// ----------------------------------------------------------------------------
// Tres bloques que no existían y que son los que hacen que el panel se pueda
// leer de arriba abajo: el resumen del negocio completo con su período
// anterior, la lista única de lo que está fuera de norma, y los compromisos
// consolidados con estado propio.
// ============================================================================

/** Cada KPI trae su valor y el del mismo tramo del mes anterior. */
export type PanelResumen = {
  periodo: { desde: string, hasta: string }
  periodo_anterior: { desde: string, hasta: string }
  dias_comparados: number
  disponibilidad: {
    actual: number | null
    anterior: number | null
    meta: number
    equipos: number
    bajo_meta: number
  }
  taller: {
    creadas: number
    cerradas: number
    creadas_ant: number
    cerradas_ant: number
    abiertas_total: number
    arrastre: number
    sin_responsable: number
  }
  nc: {
    creadas: number
    creadas_ant: number
    abiertas: number
    criticas: number
  }
  enex: {
    actual: number | null
    anterior: number | null
    faenas: number
    sin_plan: number
    facturacion_sin_control: number
    facturacion_total: number | null
  }
  combustible: {
    litros: number
    litros_ant: number
    puntos_fuera: number
    con_cierre: number
    /** Fracción: 0.0206 = 2,06%. */
    fluctuacion_peor_pct: number | null
  }
  compromisos: { pendientes: number, vencidos: number, cumplidos: number }
}

export type SeveridadExcepcion = 'critica' | 'alta' | 'media'

/**
 * Una desviación concreta que alguien tiene que resolver. Viene ya ordenada de
 * la base por severidad y, dentro de la misma severidad, por plata en juego y
 * por si tiene o no plan de acción escrito.
 */
export type Excepcion = {
  clave: string
  cuadrante: 'coquimbo' | 'calama' | 'global'
  categoria: 'equipo' | 'contrato' | 'combustible' | 'taller' | 'dato'
  severidad: SeveridadExcepcion
  orden: number
  titulo: string
  detalle: string
  metrica: string
  impacto_clp: number | null
  href: string | null
  activo_id: string | null
  enex_faena_id: string | null
  tiene_plan: boolean
}

/**
 * Equipo en estado 'S' (robo, siniestro total, incautación). Sus días se
 * excluyen del cálculo de disponibilidad —no se suman a los detenidos— pero el
 * equipo NO desaparece del panel: sigue habiendo un seguro y un contrato que
 * alguien tiene que cerrar. Ver MIG306.
 */
export type FueraDeFlota = {
  activo_id: string
  codigo: string
  patente: string | null
  nombre: string | null
  operacion: string
  desde: string
  dias: number
  dias_en_periodo: number
  motivo: string | null
  cliente_actual: string | null
  contrato_activo: boolean
}

export type Compromiso = {
  id: string
  semana: string
  ambito: 'semana' | 'cuadrante' | 'equipo' | 'faena_enex'
  cuadrante: string | null
  activo_id: string | null
  enex_faena_id: string | null
  /** Código de equipo, nombre de faena o del cuadrante. */
  referencia: string
  plan_accion: string
  texto: string | null
  responsable: string | null
  fecha_compromiso: string | null
  compromiso_estado: 'pendiente' | 'cumplido' | 'anulado'
  cumplido_at: string | null
  dias_restantes: number | null
  vencido: boolean
  antiguedad_dias: number
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
  /** Portada: KPI del negocio completo con comparación (MIG305). */
  resumen: PanelResumen
  /** Lo que está fuera de norma, ya ordenado por severidad (MIG305). */
  excepciones: Excepcion[]
  /** Planes de acción de todos los ámbitos, consolidados (MIG305). */
  compromisos: Compromiso[]
  /** Equipos excluidos del cálculo de disponibilidad, pero a la vista (MIG306). */
  fuera_de_flota: FueraDeFlota[]
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
    disponibilidad: {
      equipos: number
      promedio: number | null
      // MIG305 los agregó también en Calama: antes sólo Coquimbo tenía detalle,
      // lo que hacía que el cuadrante se viera vacío sin estarlo.
      bajo_90: number
      detalle: EquipoDisponibilidad[]
    }
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

// ============================================================================
// Corrección manual de las cifras de combustible (MIG297)
// ----------------------------------------------------------------------------
// El valor que carga el script desde las planillas es SIEMPRE una propuesta:
// las planillas de cierre no se dejan parsear de forma confiable (el teórico
// viene precalculado para todo el mes, el último día está a medias, y cada
// estanque tiene distinta cantidad de columnas). Quien manda es esta
// corrección, y por eso el motivo es obligatorio: el número va al Gerente
// General y alguien tiene que responder por él.
// ============================================================================

export type CorregirResumenInput = {
  faenaCodigo: string
  anio: number
  mes: number
  litrosVenta?: number | null
  litrosTrasvasije?: number | null
  fluctuacionLt?: number | null
  /** Fracción, no porcentaje. La UI divide por 100 antes de mandar. */
  fluctuacionPct?: number | null
  transacciones?: number | null
  motivo: string
}

export async function corregirResumenCombustible(i: CorregirResumenInput) {
  const { data, error } = await supabase.rpc('fn_combustible_corregir_resumen', {
    p_faena_codigo: i.faenaCodigo,
    p_anio: i.anio,
    p_mes: i.mes,
    p_litros_venta: i.litrosVenta ?? null,
    p_litros_trasvasije: i.litrosTrasvasije ?? null,
    p_fluctuacion_lt: i.fluctuacionLt ?? null,
    p_fluctuacion_pct: i.fluctuacionPct ?? null,
    p_transacciones: i.transacciones ?? null,
    p_motivo: i.motivo,
  })
  if (error) throw error
  return data
}

export type CorregirFluctuacionInput = {
  faenaCodigo: string
  anio: number
  mes: number
  punto: string
  litrosDespachados?: number | null
  fluctuacionLt?: number | null
  fluctuacionPct?: number | null
  diasCuadrados?: number | null
  observacion?: string | null
  motivo: string
}

export async function corregirFluctuacionPunto(i: CorregirFluctuacionInput) {
  const { data, error } = await supabase.rpc('fn_combustible_corregir_fluctuacion', {
    p_faena_codigo: i.faenaCodigo,
    p_anio: i.anio,
    p_mes: i.mes,
    p_punto: i.punto,
    p_litros_despachados: i.litrosDespachados ?? null,
    p_fluctuacion_lt: i.fluctuacionLt ?? null,
    p_fluctuacion_pct: i.fluctuacionPct ?? null,
    p_dias_cuadrados: i.diasCuadrados ?? null,
    p_observacion: i.observacion ?? null,
    p_motivo: i.motivo,
  })
  if (error) throw error
  return data
}

/**
 * Cierra, anula o reabre un compromiso. Sin esto la lista de planes de acción
 * sólo crece y a la tercera semana nadie la mira.
 */
export async function cambiarEstadoCompromiso(
  id: string,
  estado: 'pendiente' | 'cumplido' | 'anulado',
) {
  const { data, error } = await supabase.rpc('fn_panel_compromiso_estado', {
    p_id: id,
    p_estado: estado,
  })
  if (error) throw error
  return data
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
