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
import { compressImage } from '@/lib/image/compress'

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
  // Lo que el supervisor de turno declara haber revisado del turno. Si no
  // coincide con lo que hay en el sistema, el cierre se rechaza: puede haber
  // llegado una carga desde terreno mientras revisaba.
  verificacion?: { despachos: number; litros: number } | null
  // Qué hizo el turno con cada cosa que quedó pendiente. Sin esto, el cierre
  // no se firma cuando hay pendientes abiertos.
  pendientes?: { pendiente_id: string; respuesta: string; comentario?: string | null }[] | null
}

/** El resumen del turno que el supervisor mira antes de firmar. */
export type ResumenDelDia = {
  faena_id: string
  fecha: string
  despachos: number
  litros: number
  ventas: number
  trasvasijes: number
  litros_trasvasije: number
  sin_ceco: number
  sin_foto: number
  operadores: number
}

export async function getResumenDelDia(faenaId: string, fecha: string) {
  const { data, error } = await supabase
    .from('v_comb_faena_dia_para_verificar').select('*')
    .eq('faena_id', faenaId).eq('fecha', fecha).maybeSingle()
  if (error) throw error
  return (data ?? {
    faena_id: faenaId, fecha, despachos: 0, litros: 0, ventas: 0,
    trasvasijes: 0, litros_trasvasije: 0, sin_ceco: 0, sin_foto: 0, operadores: 0,
  }) as ResumenDelDia
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
    p_verificacion: p.verificacion ?? null,
    p_pendientes: p.pendientes ?? null,
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
  // Segunda red: las fotos que ya pasaron por el teléfono vienen comprimidas y
  // esto no las toca (compressImage no recomprime bajo 350 kB). Las que suben
  // directo —la guía de la recepción, por ejemplo— se comprimen aquí. En faena
  // la diferencia entre 4 MB y 250 kB es que la foto llegue o no llegue.
  const blob = await compressImage(file, { maxDim: 1600, quality: 0.75 })
  const path = `romeral-cierre/${Date.now()}_${Math.floor(Math.random() * 1e6)}.jpg`
  const { error } = await supabase.storage
    .from('evidencias-verificacion')
    .upload(path, blob, { contentType: 'image/jpeg' })
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
// NO es un criterio inventado: sale de la aplicación que ya se construyó para
// Romeral (función varClass), en litros absolutos y con tres niveles.
//
//   < 200 L  cuadra        200–500 L  atención        ≥ 500 L  investigar
//
// Validada contra los 9 días de junio 2026: de las 22 mediciones de puntos con
// contador propio, 19 quedaron bajo 200 L y las 22 bajo 500 L. Ninguna se pasó.
//
// Un umbral porcentual sería peor acá: castiga los días de poco movimiento y
// perdona los de mucho, cuando el error de leer una varilla no depende de
// cuánto se despachó — depende del tanque.
export const TOL_CUADRA_LT = 200
export const TOL_ALERTA_LT = 500

export type ResultadoCuadre = 'cuadra' | 'atencion' | 'investigar'

export function evaluarCuadre(vFis: number, vMec: number): ResultadoCuadre {
  const dif = Math.abs(vMec - vFis)
  if (dif < TOL_CUADRA_LT) return 'cuadra'
  if (dif < TOL_ALERTA_LT) return 'atencion'
  return 'investigar'
}

/** Compatibilidad: "dentro de tolerancia" es cuadra o atención. */
export function dentroDeTolerancia(vFis: number, vMec: number): boolean {
  return evaluarCuadre(vFis, vMec) !== 'investigar'
}

// ── Recepción de flota primaria (MIG320) ────────────────────────────────────
// Dos números distintos a propósito: lo que dice la guía y lo que entró al
// estanque. Si se guarda uno solo, la diferencia entre ambos desaparece — y esa
// diferencia es el control.

export type DestinoRecepcion = { estanque_id: string; litros: number }

export type RecepcionInput = {
  faenaId: string
  fecha: string
  destinos: DestinoRecepcion[]
  guia?: string | null
  viaje?: string | null
  camion?: string | null
  proveedor?: string | null
  litrosGuia?: number | null
  hora?: string | null
  recibidoPor?: string | null
  sello?: string | null
  observacion?: string | null
  fotoGuia?: string | null
  sinFotoMotivo?: string | null
  confirmar?: boolean
  clientUuid?: string | null
}

export type Recepcion = {
  id: string
  fecha: string
  hora: string | null
  guia: string | null
  viaje: string | null
  camion: string | null
  proveedor: string | null
  litros_guia: number | null
  litros_recibidos: number
  diferencia_vs_guia: number | null
  diferencia_pct: number | null
  foto_guia_url: string | null
  sin_foto_motivo: string | null
  recibido_por: string | null
  sello: string | null
  observacion: string | null
  estado: string
  destinos: { estanque_id: string; estanque: string; clave: string | null; litros: number }[] | null
}

export async function registrarRecepcion(p: RecepcionInput) {
  const { data, error } = await supabase.rpc('rpc_comb_faena_recepcion', {
    p_faena_id: p.faenaId,
    p_fecha: p.fecha,
    p_destinos: p.destinos,
    p_guia: p.guia ?? null,
    p_viaje: p.viaje ?? null,
    p_camion: p.camion ?? null,
    p_proveedor: p.proveedor ?? null,
    p_litros_guia: p.litrosGuia ?? null,
    p_hora: p.hora ?? null,
    p_recibido_por: p.recibidoPor ?? null,
    p_sello: p.sello ?? null,
    p_observacion: p.observacion ?? null,
    p_foto_guia: p.fotoGuia ?? null,
    p_sin_foto_motivo: p.sinFotoMotivo ?? null,
    p_confirmar: p.confirmar ?? false,
    p_client_uuid: p.clientUuid ?? null,
  })
  if (error) throw error
  return data as {
    recepcion_id: string
    litros_recibidos: number
    diferencia_vs_guia: number | null
    confirmada: boolean
  }
}

export async function getRecepcionesDia(faenaId: string, fecha: string): Promise<Recepcion[]> {
  const { data, error } = await supabase
    .from('v_comb_faena_recepcion').select('*')
    .eq('faena_id', faenaId).eq('fecha', fecha)
    .order('created_at', { ascending: false })
  if (error) throw error
  return (data ?? []) as Recepcion[]
}

// ── Control diario (MIG321) ─────────────────────────────────────────────────
export type ControlDia = {
  faena_id: string
  fecha: string
  estado_cierre: string | null
  medido_por: string | null
  puntos_medidos: number | null
  puntos_total: number | null
  puntos_fuera_tolerancia: number | null
  grupos_atencion: number | null
  puntos_sin_contador: number | null
  v_fis: number | null
  v_mec: number | null
  var1: number | null
  // 'incompleto' = se midió la varilla pero falta leer algún contador. No
  // cuadra ni descuadra: no se puede saber, y decir otra cosa sería mentir.
  volumen_estado: 'sin_cierre' | 'borrador' | 'revisar' | 'incompleto' | 'cuadrado'
  despachos: number | null
  litros_total: number | null
  litros_venta: number | null
  litros_trasvasije: number | null
  sin_ceco: number | null
  equipo_sin_mapear: number | null
  // 'por_registrar' = la carga trae su código de CECO y se sabe de quién es,
  // pero ese código no tiene ficha en la faena. Falta un alta, no un dato.
  imputacion_estado: 'sin_datos' | 'incompleta' | 'por_registrar' | 'completa'
  ceco_fuera_del_maestro: number | null
  transacciones_orpak: number | null
  recepciones: number | null
  litros_recibidos: number | null
  recepciones_sin_confirmar: number | null
  recepciones_con_diferencia: number | null
}

export async function getControlDiario(faenaId: string, desde: string, hasta: string) {
  const { data, error } = await supabase
    .from('v_comb_faena_control_diario').select('*')
    .eq('faena_id', faenaId).gte('fecha', desde).lte('fecha', hasta)
    .order('fecha', { ascending: false })
  if (error) throw error
  return (data ?? []) as ControlDia[]
}

export type Excepcion = {
  faena_id: string
  fecha: string | null
  tipo: string
  referencia: string | null
  detalle: string | null
  litros: number | null
  cantidad: number | null
}

export async function getExcepciones(faenaId: string) {
  const { data, error } = await supabase
    .from('v_comb_faena_excepciones').select('*')
    .eq('faena_id', faenaId)
    .order('fecha', { ascending: false, nullsFirst: true })
    .limit(200)
  if (error) throw error
  return (data ?? []) as Excepcion[]
}

export async function confirmarCeco(cecoId: string, codigo?: string, empresa?: string) {
  const { data, error } = await supabase.rpc('rpc_comb_faena_confirmar_ceco', {
    p_ceco_id: cecoId, p_codigo: codigo ?? null, p_empresa: empresa ?? null,
  })
  if (error) throw error
  return data as { confirmado?: boolean; fusionado_con?: string; despachos_movidos?: number }
}

// ── Lo que quedó pendiente del turno anterior (MIG344/345) ──────────────────
//
// La queja del mandante: se le pide algo al turno de día y el de noche no lo
// hace. Un pendiente no es una nota — es algo con dueño y con cierre, y vive
// dentro del cierre del turno porque es el único ritual que el turno ya está
// obligado a completar. Un módulo aparte no lo abriría nadie.

export type Pendiente = {
  id: string
  faena_id: string
  texto: string
  origen: 'mandante' | 'supervisor' | 'oficina' | 'sistema'
  pedido_por: string | null
  prioridad: 'normal' | 'alta'
  creado_at: string
  dias_abierto: number
  turnos_sin_hacer: number
  ultimo_comentario: string | null
  ultimo_turno_por: string | null
  // 'nuevo' todavía no lo vio ningún turno · 'arrastrando' uno o dos turnos ·
  // 'atascado' tres o más, que ya es otro problema.
  senal: 'nuevo' | 'arrastrando' | 'atascado'
}

export type RespuestaPendiente = {
  pendiente_id: string
  respuesta: 'hecho' | 'no_alcanzo' | 'no_corresponde'
  comentario?: string | null
}

export async function getPendientesAbiertos(faenaId: string) {
  const { data, error } = await supabase
    .from('v_comb_faena_pendientes_abiertos').select('*')
    .eq('faena_id', faenaId)
    .order('prioridad').order('creado_at')
  if (error) throw error
  return (data ?? []) as Pendiente[]
}

export async function crearPendiente(p: {
  faenaId: string
  texto: string
  origen?: Pendiente['origen']
  pedidoPor?: string | null
  prioridad?: Pendiente['prioridad']
}) {
  const { data, error } = await supabase.rpc('rpc_comb_pendiente_crear', {
    p_faena_id: p.faenaId,
    p_texto: p.texto,
    p_origen: p.origen ?? 'supervisor',
    p_pedido_por: p.pedidoPor ?? null,
    p_prioridad: p.prioridad ?? 'normal',
  })
  if (error) throw error
  return data as { pendiente_id: string }
}
