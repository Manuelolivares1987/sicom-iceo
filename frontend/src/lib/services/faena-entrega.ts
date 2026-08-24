// ============================================================================
// Entrega de turno de faena (MIG362)
// ----------------------------------------------------------------------------
// El cambio de turno como acto con dos firmas. Cuatro bloques: los camiones,
// los litros, los pendientes y la bodega.
// ============================================================================
import { supabase } from '@/lib/supabase'
import { compressImage } from '@/lib/image/compress'

export type EstadoEquipoEntrega =
  | 'operativo' | 'back_up' | 'en_mantencion' | 'fuera_de_faena' | 'detenido'

export const ESTADOS_EQUIPO: { valor: EstadoEquipoEntrega; texto: string }[] = [
  { valor: 'operativo',      texto: 'Operativo' },
  { valor: 'back_up',        texto: 'Back up' },
  { valor: 'en_mantencion',  texto: 'En mantención' },
  { valor: 'detenido',       texto: 'Detenido' },
  { valor: 'fuera_de_faena', texto: 'Fuera de faena' },
]

export type EquipoEntrega = {
  activo_id: string
  patente: string | null
  equipo: string | null
  estado: EstadoEquipoEntrega
  horometro: number | null
  kilometraje: number | null
  faltan_horas: number | null
  faltan_km: number | null
  desviaciones: number
  desviaciones_detalle: string | null
  observacion: string | null
}

export type PendienteAbierto = {
  id: string
  texto: string
  origen: string
  pedido_por: string | null
  prioridad: string
  dias_abierto: number
  turnos_sin_hacer: number
  ultimo_comentario: string | null
  ultimo_turno_por: string | null
  senal: 'nuevo' | 'arrastrando' | 'atascado'
}

export type EntregaTurno = {
  id: string
  faena_id: string
  turno_saliente: string
  turno_entrante: string
  desde: string
  hasta: string
  estado: 'abierta' | 'entregada' | 'recibida'
  stock_fisico_lt: number | null
  stock_teorico_lt: number | null
  ticket_verificacion: string | null
  conteo_fisico_hecho: boolean
  conteo_omitido_motivo: string | null
  inventario_cerrado: boolean
  inventario_observacion: string | null
  observacion_entrega: string | null
  observacion_recepcion: string | null
  reparos: string | null
  entrega_nombre: string | null
  entrega_firma_url: string | null
  entregado_at: string | null
  recibe_nombre: string | null
  recibe_firma_url: string | null
  recibido_at: string | null
}

export type ResumenTurno = {
  desde: string
  hasta: string
  litros: { venta: number; trasvasije: number; recirculacion: number; calibracion: number; total: number; cargas: number }
  litros_por_dia: { fecha: string; dia: number; noche: number }[]
  pauta: { ejecuciones: number; no_aplica: number; hallazgos: number }
  pendientes: { abiertos: number; atascados: number; arrastrando: number }
}

export type EntregaAbierta = {
  entrega_id: string
  entrega: EntregaTurno
  resumen: ResumenTurno
  equipos: EquipoEntrega[]
  pendientes: PendienteAbierto[]
}

export type RespuestaPendiente = {
  pendiente_id: string
  respuesta: 'hecho' | 'no_alcanzo' | 'no_corresponde'
  comentario?: string | null
}

export async function abrirEntrega(p: {
  faenaId: string; desde: string; hasta: string
  turnoSaliente: string; turnoEntrante: string
}): Promise<EntregaAbierta> {
  const { data, error } = await supabase.rpc('rpc_faena_entrega_abrir', {
    p_faena_id: p.faenaId, p_desde: p.desde, p_hasta: p.hasta,
    p_turno_saliente: p.turnoSaliente, p_turno_entrante: p.turnoEntrante,
  })
  if (error) throw error
  return data as EntregaAbierta
}

export async function firmarEntrega(p: {
  entregaId: string
  nombre: string
  firmaUrl: string
  equipos: EquipoEntrega[]
  pendientes: RespuestaPendiente[]
  stockFisico?: number | null
  ticket?: string | null
  conteoHecho: boolean
  conteoOmitidoMotivo?: string | null
  inventarioCerrado: boolean
  inventarioObservacion?: string | null
  observacion?: string | null
}) {
  const { data, error } = await supabase.rpc('rpc_faena_entrega_firmar', {
    p_entrega_id: p.entregaId,
    p_nombre: p.nombre,
    p_firma_url: p.firmaUrl,
    p_equipos: p.equipos,
    p_pendientes: p.pendientes,
    p_stock_fisico: p.stockFisico ?? null,
    p_ticket: p.ticket ?? null,
    p_conteo_hecho: p.conteoHecho,
    p_conteo_omitido_motivo: p.conteoOmitidoMotivo ?? null,
    p_inventario_cerrado: p.inventarioCerrado,
    p_inventario_observacion: p.inventarioObservacion ?? null,
    p_observacion: p.observacion ?? null,
  })
  if (error) throw error
  return data as {
    success: boolean; entrega_id: string; estado: string
    stock_fisico: number | null
    // [MIG365] Nulo cuando no hay un inicial verificado contra el que comparar.
    // Un cero ahí sería una pérdida inventada.
    stock_teorico: number | null
    comparable: boolean
    por_que_no_comparable: string | null
    diferencia: number | null
  }
}

export async function recibirEntrega(p: {
  entregaId: string; nombre: string; firmaUrl: string
  reparos?: string | null; observacion?: string | null
}) {
  const { data, error } = await supabase.rpc('rpc_faena_entrega_recibir', {
    p_entrega_id: p.entregaId, p_nombre: p.nombre, p_firma_url: p.firmaUrl,
    p_reparos: p.reparos ?? null, p_observacion: p.observacion ?? null,
  })
  if (error) throw error
  return data as { success: boolean; entrega_id: string; estado: string }
}

export async function getEntregas(faenaId: string) {
  const { data, error } = await supabase.from('v_faena_entrega_turno').select('*')
    .eq('faena_id', faenaId).order('hasta', { ascending: false }).limit(30)
  if (error) throw error
  return (data ?? []) as (EntregaTurno & {
    faena_codigo: string; equipos: number; desviaciones: number; diferencia_lt: number | null
  })[]
}

export async function getEquiposEntregados(entregaId: string) {
  const { data, error } = await supabase.from('faena_entrega_equipo').select('*')
    .eq('entrega_id', entregaId).order('patente')
  if (error) throw error
  return (data ?? []) as EquipoEntrega[]
}

export async function getResumenTurno(faenaId: string, desde: string, hasta: string, turno?: string | null) {
  const { data, error } = await supabase.rpc('fn_faena_turno_resumen', {
    p_faena_id: faenaId, p_desde: desde, p_hasta: hasta, p_turno: turno ?? null,
  })
  if (error) throw error
  return data as ResumenTurno
}

export async function getBalance(faenaId: string, desde: string, hasta: string) {
  const { data, error } = await supabase.rpc('fn_faena_balance_periodo', {
    p_faena_id: faenaId, p_desde: desde, p_hasta: hasta,
  })
  if (error) throw error
  return data as {
    desde: string; hasta: string
    stock_inicial: number | null; stock_inicial_verificado: boolean
    cargas: number; ventas: number; trasvasijes: number; recirculacion_calibracion: number
    stock_teorico: number; stock_fisico: number | null; stock_fisico_verificado: boolean
    diferencia: number | null; diferencia_pct: number | null
    transacciones: number
    folios: { desde: number | null; hasta: number | null; emitidos: number; faltantes: number }
    ventas_por_ceco: { ceco: string | null; empresa: string | null; litros: number }[]
  }
}

export async function subirFirma(blob: Blob): Promise<string> {
  const comprimida = await compressImage(blob, { maxDim: 1200, quality: 0.8 })
  const path = `entrega-turno/${Date.now()}_${Math.floor(Math.random() * 1e6)}.jpg`
  const { error } = await supabase.storage.from('evidencias-verificacion')
    .upload(path, comprimida, { contentType: 'image/jpeg' })
  if (error) throw error
  return supabase.storage.from('evidencias-verificacion').getPublicUrl(path).data.publicUrl
}

/** El domingo de la semana 7×7 que termina hoy o antes. */
export function periodoSugerido(hoy = new Date()): { desde: string; hasta: string } {
  const iso = (d: Date) =>
    `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
  const hasta = new Date(hoy)
  const desde = new Date(hoy)
  desde.setDate(desde.getDate() - 6)
  return { desde: iso(desde), hasta: iso(hasta) }
}
