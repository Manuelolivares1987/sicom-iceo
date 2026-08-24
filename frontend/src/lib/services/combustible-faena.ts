// Despacho de combustible en faena (MIG279) — el registro que hoy se lleva en
// papel: el camión abastece equipos en terreno y se anota medidor, litros, a
// quién se cargó, dónde, en qué turno y quién lo cargó.
//
// Todo cuelga de la faena: Romeral no comparte catálogo ni reportes con Franke
// ni con la operación de Coquimbo.
import { supabase } from '@/lib/supabase'
import { compressImage } from '@/lib/image/compress'

export const FAENA_ROMERAL = 'FAE-CMP-ROMERAL'

export type FaenaComb = { id: string; codigo: string; nombre: string }

export type CombCeco = { id: string; codigo: string; empresa: string | null }

export type CombEquipo = {
  id: string
  nombre: string
  descripcion: string | null
  ceco_id: string | null
  ceco?: string | null
  ceco_empresa?: string | null
}

export type CombUbicacion = { id: string; nombre: string }

export type CombCamion = {
  id: string
  codigo: string
  nombre: string
  patente: string | null
}

export type CombDespacho = {
  id: string
  faena_id: string
  fecha: string
  hora: string | null
  turno: string | null
  camion: string | null
  camion_patente: string | null
  equipo: string | null
  equipo_descripcion: string | null
  ceco: string | null
  ceco_empresa: string | null
  ubicacion: string | null
  meter_inicial: number | null
  meter_final: number | null
  litros: number
  operador_nombre: string | null
  observacion: string | null
  anulado: boolean
  anulado_motivo: string | null
  created_at: string
  foto_meter_inicial_url: string | null
  foto_meter_final_url: string | null
  sin_foto_motivo: string | null
}

/** Todo lo que la app de terreno necesita tener bajado para trabajar sin señal. */
export type CatalogoFaena = {
  faena: FaenaComb
  equipos: CombEquipo[]
  ubicaciones: CombUbicacion[]
  camiones: CombCamion[]
  descargado_at: string
}

export async function getFaenaPorCodigo(codigo: string): Promise<FaenaComb | null> {
  const { data, error } = await supabase.from('faenas').select('id, codigo, nombre')
    .eq('codigo', codigo).maybeSingle()
  if (error) throw error
  return (data ?? null) as FaenaComb | null
}

export async function getCatalogoFaena(codigo = FAENA_ROMERAL): Promise<CatalogoFaena> {
  const faena = await getFaenaPorCodigo(codigo)
  if (!faena) throw new Error(`No existe la faena ${codigo}`)

  const [eq, ub, cam] = await Promise.all([
    supabase.from('combustible_faena_equipos')
      .select('id, nombre, descripcion, ceco_id, ceco:combustible_faena_cecos(codigo, empresa)')
      .eq('faena_id', faena.id).eq('activo', true).order('nombre'),
    supabase.from('combustible_faena_ubicaciones')
      .select('id, nombre').eq('faena_id', faena.id).eq('activo', true).order('nombre'),
    supabase.from('combustible_estanques')
      .select('id, codigo, nombre, patente').eq('faena_id', faena.id).eq('activo', true).order('nombre'),
  ])
  if (eq.error) throw eq.error
  if (ub.error) throw ub.error
  if (cam.error) throw cam.error

  type EqRow = Omit<CombEquipo, 'ceco' | 'ceco_empresa'> & {
    ceco: { codigo: string; empresa: string | null } | null
  }
  const equipos: CombEquipo[] = ((eq.data ?? []) as unknown as EqRow[]).map((r) => ({
    id: r.id, nombre: r.nombre, descripcion: r.descripcion, ceco_id: r.ceco_id,
    ceco: r.ceco?.codigo ?? null, ceco_empresa: r.ceco?.empresa ?? null,
  }))

  return {
    faena,
    equipos,
    ubicaciones: (ub.data ?? []) as CombUbicacion[],
    camiones: (cam.data ?? []) as CombCamion[],
    descargado_at: new Date().toISOString(),
  }
}

export type DespachoInput = {
  faenaId: string
  fecha: string
  turno?: string | null
  estanqueId?: string | null
  camionPatente?: string | null
  equipoId?: string | null
  equipoTexto?: string | null
  ubicacionId?: string | null
  ubicacionTexto?: string | null
  meterInicial?: number | null
  meterFinal?: number | null
  litros: number
  operadorNombre?: string | null
  hora?: string | null
  horometro?: number | null
  kilometraje?: number | null
  observacion?: string | null
  clientUuid?: string | null
  fotoMeterInicial?: string | null
  fotoMeterFinal?: string | null
  sinFotoMotivo?: string | null
  // [MIG318] Lo que el catálogo todavía no tiene y quien despacha sí sabe.
  cecoTexto?: string | null
  tipoMovimiento?: 'venta' | 'trasvasije' | 'recirculacion' | 'calibracion'
  flota?: string | null
  destinoEstanqueId?: string | null
  // [MIG363/364] El folio del ticket printer. En Franke es la fuente de verdad
  // de la transacción: sin él la carga registrada no se amarra al papel que
  // quedó arriba del camión. Romeral no lo usa —allá manda Orpak— y por eso va
  // opcional.
  folioTicket?: number | null
}

/** Sube una foto del medidor al bucket de evidencias. */
export async function subirFotoMedidor(file: File | Blob): Promise<string> {
  // Segunda red, como en el cierre: lo que ya pasó por el teléfono viene
  // comprimido y esto no lo toca; lo que sube directo se comprime aquí.
  const blob = await compressImage(file, { maxDim: 1600, quality: 0.75 })
  const path = `romeral/${Date.now()}_${Math.floor(Math.random() * 1e6)}.jpg`
  const { error } = await supabase.storage.from('evidencias-verificacion')
    .upload(path, blob, { contentType: 'image/jpeg' })
  if (error) throw error
  return supabase.storage.from('evidencias-verificacion').getPublicUrl(path).data.publicUrl
}

export async function registrarDespacho(p: DespachoInput) {
  const { data, error } = await supabase.rpc('rpc_comb_faena_despachar', {
    p_faena_id: p.faenaId, p_fecha: p.fecha, p_turno: p.turno ?? null,
    p_estanque_id: p.estanqueId ?? null, p_equipo_id: p.equipoId ?? null,
    p_ubicacion_id: p.ubicacionId ?? null,
    p_meter_inicial: p.meterInicial ?? null, p_meter_final: p.meterFinal ?? null,
    p_litros: p.litros,
    p_operador_nombre: p.operadorNombre ?? null, p_hora: p.hora ?? null,
    p_equipo_texto: p.equipoTexto ?? null, p_ubicacion_texto: p.ubicacionTexto ?? null,
    p_camion_patente: p.camionPatente ?? null,
    p_horometro: p.horometro ?? null, p_kilometraje: p.kilometraje ?? null,
    p_observacion: p.observacion ?? null, p_client_uuid: p.clientUuid ?? null,
    p_foto_meter_inicial: p.fotoMeterInicial ?? null,
    p_foto_meter_final: p.fotoMeterFinal ?? null,
    p_sin_foto_motivo: p.sinFotoMotivo ?? null,
    p_ceco_texto: p.cecoTexto ?? null,
    p_tipo_movimiento: p.tipoMovimiento ?? 'venta',
    p_flota: p.flota ?? null,
    p_destino_estanque_id: p.destinoEstanqueId ?? null,
    p_folio_ticket: p.folioTicket ?? null,
  })
  if (error) throw error
  return data as {
    success: boolean; despacho_id: string; litros?: number; duplicado?: boolean
    ceco_id?: string | null; ceco_anotado?: boolean; folio_ticket?: number | null
  }
}

export async function getDespachosDia(faenaId: string, fecha: string): Promise<CombDespacho[]> {
  const { data, error } = await supabase.from('v_comb_faena_despachos').select('*')
    .eq('faena_id', faenaId).eq('fecha', fecha)
    .order('created_at', { ascending: false })
  if (error) throw error
  return (data ?? []) as CombDespacho[]
}

export async function getDespachosRango(faenaId: string, desde: string, hasta: string): Promise<CombDespacho[]> {
  const { data, error } = await supabase.from('v_comb_faena_despachos').select('*')
    .eq('faena_id', faenaId).gte('fecha', desde).lte('fecha', hasta)
    .order('fecha', { ascending: false }).order('created_at', { ascending: false })
  if (error) throw error
  return (data ?? []) as CombDespacho[]
}

export async function anularDespacho(id: string, motivo: string) {
  const { error } = await supabase.rpc('rpc_comb_faena_anular_despacho', { p_id: id, p_motivo: motivo })
  if (error) throw error
}

export type ConsumoCeco = {
  faena_id: string
  periodo: string
  ceco_id: string | null
  ceco: string | null
  ceco_empresa: string | null
  despachos: number
  litros: number
  equipos: number
}

export async function getConsumoPorCeco(faenaId: string, periodo: string): Promise<ConsumoCeco[]> {
  const { data, error } = await supabase.from('v_comb_faena_consumo_ceco').select('*')
    .eq('faena_id', faenaId).eq('periodo', periodo)
    .order('litros', { ascending: false })
  if (error) throw error
  return (data ?? []) as ConsumoCeco[]
}

export const TURNOS = ['Día', 'Noche'] as const

// ── El momento cero y el trasvasije (MIG378-382) ─────────────────────────────
// Dos puntas que faltaban para poder arrancar: declarar con qué se parte, y
// cargar el camión desde una estación.

export type EstanqueFaena = {
  id: string
  faena_id: string
  codigo: string
  nombre: string
  tipo: string | null
  patente: string | null
  capacidad_lt: number | null
  stock_teorico_lt: number | null
  costo_promedio_lt: number | null
  orden_cierre: number | null
  activo: boolean
  /** Si ya se declaró con qué partió. Sin esto, el control no tiene contra qué comparar. */
  tiene_momento_cero: boolean
  momento_cero_fecha: string | null
  momento_cero_litros: number | null
  momento_cero_medido_por: string | null
  llenado_pct: number | null
}

/** Los estanques de la faena, con lo justo para decidir en terreno. */
export async function getEstanquesFaena(faenaId: string): Promise<EstanqueFaena[]> {
  const { data, error } = await supabase
    .from('v_comb_faena_estanques')
    .select('*')
    .eq('faena_id', faenaId)
    .eq('activo', true)
    .order('orden_cierre', { nullsFirst: false })
  if (error) throw error
  return (data ?? []) as EstanqueFaena[]
}

export type EstanqueAhora = EstanqueFaena & {
  medido_desde: string | null
  litros_ancla: number | null
  /** true = el ancla es un cierre firmado; false = todavía es el momento cero. */
  ancla_es_cierre: boolean
  salido_desde: number
  entrado_desde: number
  estimable: boolean
}

/**
 * Cuánto lleva cada estanque AHORA. Es un estimado y se muestra como tal: la
 * columna firme la fija la varilla al cerrar el turno, esto es lo que pasó
 * desde entonces.
 */
export async function getEstanquesAhora(faenaId: string): Promise<EstanqueAhora[]> {
  const { data, error } = await supabase
    .from('v_comb_faena_estanque_ahora')
    .select('*')
    .eq('faena_id', faenaId)
    .eq('activo', true)
    .order('orden_cierre', { nullsFirst: false })
  if (error) throw error
  return (data ?? []) as EstanqueAhora[]
}

/** Lo estimado ahora mismo, a partir del ancla y lo que pasó después. */
export function litrosAhora(e: EstanqueAhora): number | null {
  if (!e.estimable || e.litros_ancla == null) return null
  return Number(e.litros_ancla) - Number(e.salido_desde ?? 0) + Number(e.entrado_desde ?? 0)
}

export type PuntoMomentoCero = {
  estanque_id: string
  litros: number
  lectura_cm?: number | null
  foto_url?: string | null
  sin_foto_motivo?: string | null
  observacion?: string | null
}

/**
 * El momento cero de la faena: los estanques se varillan juntos y se firman una
 * vez. Cero litros es una declaración válida — un estanque vacío también tiene
 * que quedar anclado.
 */
export async function declararMomentoCero(params: {
  faenaId: string
  fecha: string
  medidoPor: string
  puntos: PuntoMomentoCero[]
  firmaUrl: string
  observacion?: string | null
  clientUuid?: string | null
}) {
  const { data, error } = await supabase.rpc('rpc_comb_faena_stock_inicial', {
    p_faena_id: params.faenaId,
    p_fecha: params.fecha,
    p_medido_por: params.medidoPor,
    p_puntos: params.puntos,
    p_firma_url: params.firmaUrl,
    p_observacion: params.observacion ?? null,
    p_client_uuid: params.clientUuid ?? null,
  })
  if (error) throw error
  return data as {
    success: boolean
    lote_id: string
    declarados: number
    detalle: { codigo: string; litros: number }[]
    /** Los que ya estaban declarados: el momento cero no se pisa. */
    ya_tenian: string[]
    /** Los que quedaron sin declarar. El momento cero sirve completo. */
    faltan: string[]
    duplicado?: boolean
  }
}

/**
 * Pasar combustible de un estanque a otro dentro de la misma faena. A
 * diferencia del despacho, esto SÍ mueve los litros: no consume, redistribuye.
 */
export async function trasvasijar(params: {
  faenaId: string
  fecha: string
  turno?: string | null
  origenId: string
  destinoId: string
  litros: number
  operador: string
  meterInicial?: number | null
  meterFinal?: number | null
  fotoInicial?: string | null
  fotoFinal?: string | null
  sinFotoMotivo?: string | null
  observacion?: string | null
  hora?: string | null
  clientUuid?: string | null
}) {
  const { data, error } = await supabase.rpc('rpc_comb_faena_trasvasije', {
    p_faena_id: params.faenaId,
    p_fecha: params.fecha,
    p_turno: params.turno ?? null,
    p_origen_id: params.origenId,
    p_destino_id: params.destinoId,
    p_litros: params.litros,
    p_operador: params.operador,
    p_meter_inicial: params.meterInicial ?? null,
    p_meter_final: params.meterFinal ?? null,
    p_foto_inicial: params.fotoInicial ?? null,
    p_foto_final: params.fotoFinal ?? null,
    p_sin_foto_motivo: params.sinFotoMotivo ?? null,
    p_observacion: params.observacion ?? null,
    p_hora: params.hora ?? null,
    p_client_uuid: params.clientUuid ?? null,
  })
  if (error) throw error
  return data as {
    success: boolean
    despacho_id: string
    litros: number
    origen: string
    origen_queda: number
    destino: string
    destino_queda: number
    /** Cuando el origen queda bajo su mínimo. No bloquea, avisa. */
    aviso: string | null
    duplicado?: boolean
  }
}
