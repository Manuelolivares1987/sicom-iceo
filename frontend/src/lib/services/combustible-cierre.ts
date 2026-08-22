// ============================================================================
// Cierre físico del turno en Romeral (MIG317)
// ----------------------------------------------------------------------------
// Es el "Registro de Cierre Diario" que hoy se llena a mano en la hoja del día:
// varilla por estanque y numeral por cuentalitros. Los nombres de los campos
// son los mismos que usa la aplicación del mundo Orpak (mi, rfp, rt, mf, v_fis,
// v_mec, var1) a propósito: así los dos sistemas se pueden comparar número a
// número sin traducir nada.
//
// El cálculo NO se hace aquí. Lo hace la base, en v_comb_faena_cierre_punto,
// porque un cálculo que vive en la pantalla se puede editar y uno que vive en
// la base no.
// ============================================================================

import { supabase } from '@/lib/supabase'

export type PuntoMedicion = {
  id: string
  codigo: string
  nombre: string
  tipo: string
  clave_cierre: string | null
  orden_cierre: number | null
  capacidad_lt: number | null
  capacidad_llenado_lt: number | null
  patente: string | null
  medidores: Medidor[]
}

export type Medidor = {
  id: string
  estanque_id: string
  surtidor: string
  numero: string
  etiqueta: string | null
  orden: number
  ultimo_numeral: number | null
}

/** Lo que el operador anotó en un punto. Vacío = todavía no lo midió. */
export type LecturaPunto = {
  estanque_id: string
  mi: number | null
  rfp: number | null
  rt: number | null
  mf: number | null
  agua_mm: number | null
  temperatura_c: number | null
  sin_medicion: boolean
  motivo_sin_medicion: string | null
  // [MIG319] La foto de la varilla. En combustible la medición no se puede
  // volver a verificar: mañana el estanque tiene otro nivel.
  foto_url?: string | null
  sin_foto_motivo?: string | null
}

export type LecturaMedidor = {
  medidor_id: string
  numeral_ini: number | null
  numeral_fin: number | null
  calibracion: number
  foto_url?: string | null
  sin_foto_motivo?: string | null
}

export type CierreInput = {
  faenaId: string
  fecha: string
  turno: string | null
  medidoPor: string | null
  puntos: LecturaPunto[]
  medidores: LecturaMedidor[]
  observacion?: string | null
  firmar?: boolean
  clientUuid?: string | null
}

/** Catálogo de puntos y medidores, para bajarlo al teléfono. */
export async function getPuntosMedicion(faenaId: string): Promise<PuntoMedicion[]> {
  const [est, med] = await Promise.all([
    supabase
      .from('combustible_estanques')
      .select('id, codigo, nombre, tipo, clave_cierre, orden_cierre, capacidad_lt, capacidad_llenado_lt, patente')
      .eq('faena_id', faenaId).eq('activo', true)
      .order('orden_cierre', { nullsFirst: false }),
    supabase
      .from('combustible_faena_medidores')
      .select('id, estanque_id, surtidor, numero, etiqueta, orden, ultimo_numeral')
      .eq('activo', true).order('orden'),
  ])
  if (est.error) throw est.error
  if (med.error) throw med.error

  const medidores = (med.data ?? []) as Medidor[]
  return ((est.data ?? []) as Omit<PuntoMedicion, 'medidores'>[]).map((e) => ({
    ...e,
    medidores: medidores.filter((m) => m.estanque_id === e.id),
  }))
}

/** El cierre del día anterior, para proponer la medición inicial de hoy. */
export async function getCierreAnterior(faenaId: string, fecha: string) {
  const { data, error } = await supabase
    .from('v_comb_faena_cierre_punto')
    .select('estanque_id, mf, fecha')
    .eq('faena_id', faenaId).lt('fecha', fecha)
    .order('fecha', { ascending: false })
    .limit(40)
  if (error) throw error
  // Se queda con la medición final más reciente de cada punto.
  const ultima = new Map<string, number>()
  for (const r of (data ?? []) as { estanque_id: string; mf: number | null }[]) {
    if (r.mf != null && !ultima.has(r.estanque_id)) ultima.set(r.estanque_id, Number(r.mf))
  }
  return ultima
}

export type CierrePuntoCalculado = {
  cierre_id: string
  fecha: string
  turno: string | null
  estado: string
  medido_por: string | null
  estanque_id: string
  estanque_codigo: string
  estanque_nombre: string
  clave_cierre: string | null
  orden_cierre: number | null
  capacidad_llenado_lt: number | null
  mi: number | null
  rfp: number | null
  rt: number | null
  mf: number | null
  sin_medicion: boolean
  motivo_sin_medicion: string | null
  v_fis: number
  v_mec: number
  var1: number
  medidores_total: number
  medidores_leidos: number
  pct_llenado: number | null
}

export async function getCierreDia(faenaId: string, fecha: string): Promise<CierrePuntoCalculado[]> {
  const { data, error } = await supabase
    .from('v_comb_faena_cierre_punto')
    .select('*')
    .eq('faena_id', faenaId).eq('fecha', fecha)
    .order('orden_cierre', { nullsFirst: false })
  if (error) throw error
  return (data ?? []) as CierrePuntoCalculado[]
}

export async function guardarCierre(p: CierreInput) {
  const { data, error } = await supabase.rpc('rpc_comb_faena_guardar_cierre', {
    p_faena_id: p.faenaId,
    p_fecha: p.fecha,
    p_turno: p.turno ?? null,
    p_medido_por: p.medidoPor ?? null,
    p_puntos: p.puntos,
    p_medidores: p.medidores,
    p_observacion: p.observacion ?? null,
    p_firmar: p.firmar ?? false,
    p_client_uuid: p.clientUuid ?? null,
  })
  if (error) throw error
  return data as { cierre_id: string; firmado: boolean }
}

/** Sube la foto de una medición y devuelve su URL pública. */
export async function subirFotoMedicion(file: File | Blob): Promise<string> {
  const path = `romeral-cierre/${Date.now()}_${Math.floor(Math.random() * 1e6)}.jpg`
  const { error } = await supabase.storage
    .from('evidencias-verificacion')
    .upload(path, file, { contentType: 'image/jpeg' })
  if (error) throw error
  return supabase.storage.from('evidencias-verificacion').getPublicUrl(path).data.publicUrl
}

/** Anota un CECO que no está en el catálogo. No lo duplica si ya existe. */
export async function anotarCeco(faenaId: string, codigo: string, empresa?: string, anotadoPor?: string) {
  const { data, error } = await supabase.rpc('rpc_comb_faena_anotar_ceco', {
    p_faena_id: faenaId,
    p_codigo: codigo,
    p_empresa: empresa ?? null,
    p_anotado_por: anotadoPor ?? null,
  })
  if (error) throw error
  return data as { ceco_id: string; codigo: string; nuevo: boolean }
}

// ── Tolerancia ──────────────────────────────────────────────────────────────
// Punto de partida propuesto: ±0,5 % del movimiento del día, con un piso de 50
// litros para que un día de poco movimiento no se marque en rojo por el error
// natural de leer una varilla. Se acuerda con ESMAX y se cambia acá.
export const TOLERANCIA_PCT = 0.005
export const TOLERANCIA_PISO_LT = 50

export function dentroDeTolerancia(vFis: number, vMec: number): boolean {
  const dif = Math.abs(vMec - vFis)
  const base = Math.max(Math.abs(vFis), Math.abs(vMec))
  return dif <= Math.max(base * TOLERANCIA_PCT, TOLERANCIA_PISO_LT)
}
