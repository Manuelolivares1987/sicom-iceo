// Despacho de combustible en faena (MIG279) — el registro que hoy se lleva en
// papel: el camión abastece equipos en terreno y se anota medidor, litros, a
// quién se cargó, dónde, en qué turno y quién lo cargó.
//
// Todo cuelga de la faena: Romeral no comparte catálogo ni reportes con Franke
// ni con la operación de Coquimbo.
import { supabase } from '@/lib/supabase'

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
  })
  if (error) throw error
  return data as { success: boolean; despacho_id: string; litros?: number; duplicado?: boolean }
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
