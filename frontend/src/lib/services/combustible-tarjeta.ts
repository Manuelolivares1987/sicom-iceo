// ============================================================================
// Tarjeta de flota Aramco + rendimiento km/L (MIG659)
// ----------------------------------------------------------------------------
// El Excel de portaltarjetas.cl (Transacciones → Exportar → Excel) trae litros y
// monto por carga, pero el odómetro viene vacío: el chofer no lo digita. Los km
// salen del GPS (activo_horas_dia). Los Renault no cargan con tarjeta: su
// computador informa los litros que gastó el motor.
//
// Leer el archivo es en el navegador; la base solo recibe las filas. No se
// duplica nada: cada carga trae su código de autorización.
// ============================================================================

import type { Workbook } from 'exceljs'
import { supabase } from '@/lib/supabase'

export type FilaTarjeta = {
  cod_autorizacion: string
  fecha_hora: string          // 'YYYY-MM-DDTHH:mm:ss', hora local de Chile
  tarjeta: string | null
  tipo_tarjeta: string | null
  patente: string
  tipo_vehiculo: string | null
  centro_costo: string | null
  guia_despacho: string | null
  factura: string | null
  rut_chofer: string | null
  odometro: number | null
  producto: string | null
  estacion: string | null
  comuna: string | null
  pizarra: number | null
  litros: number
  total_pizarra: number | null
  total_descuento: number | null
  total_pago: number | null
}

const norm = (s: unknown) => String(s ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '')
  .toLowerCase().replace(/\s+/g, ' ').trim()

// Encabezado del portal → campo. Se busca por nombre, no por posición.
const COLUMNAS: Record<string, keyof FilaTarjeta | 'fecha'> = {
  'fecha transaccion': 'fecha', 'centro de costo': 'centro_costo', 'tarjeta': 'tarjeta',
  'tipo tarjeta': 'tipo_tarjeta', 'patente': 'patente', 'tipo de vehiculo': 'tipo_vehiculo',
  'guia despacho': 'guia_despacho', 'cod. autorizacion': 'cod_autorizacion', 'factura': 'factura',
  'rut chofer': 'rut_chofer', 'odometro': 'odometro', 'producto': 'producto', 'es': 'estacion',
  'comuna es': 'comuna', 'pizarra ($/l)': 'pizarra', 'volumen (l)': 'litros',
  'total pizarra ($)': 'total_pizarra', 'total descuento ($)': 'total_descuento', 'total pago ($)': 'total_pago',
}
const OBLIGATORIAS = ['fecha', 'patente', 'cod_autorizacion', 'litros']

const texto = (v: unknown): string | null => {
  if (v == null) return null
  if (typeof v === 'object' && 'richText' in (v as object))
    return (v as { richText: { text: string }[] }).richText.map((t) => t.text).join('').trim() || null
  const s = String(v).trim()
  return s === '' ? null : s
}
const numero = (v: unknown): number | null => {
  if (v == null || v === '') return null
  if (typeof v === 'number') return v
  const n = Number(String(v).replace(/\./g, '').replace(',', '.'))
  return Number.isFinite(n) ? n : null
}
const p2 = (n: number) => String(n).padStart(2, '0')
// ExcelJS entrega la fecha de la celda como si fuera UTC: se leen las partes UTC
// para conservar la hora local tal como la muestra el portal.
const fechaLocal = (v: unknown): string | null => {
  if (v instanceof Date && !Number.isNaN(v.getTime()))
    return `${v.getUTCFullYear()}-${p2(v.getUTCMonth() + 1)}-${p2(v.getUTCDate())}T${p2(v.getUTCHours())}:${p2(v.getUTCMinutes())}:${p2(v.getUTCSeconds())}`
  const m = String(v ?? '').match(/^(\d{2})[-/](\d{2})[-/](\d{4})[ T](\d{2}):(\d{2})(?::(\d{2}))?/)
  if (m) return `${m[3]}-${m[2]}-${m[1]}T${m[4]}:${m[5]}:${m[6] ?? '00'}`
  const iso = String(v ?? '').match(/^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}(:\d{2})?/)
  return iso ? iso[0].replace(' ', 'T') + (iso[1] ? '' : ':00') : null
}

export function leerAramco(wb: Workbook): { filas: FilaTarjeta[]; descartadas: number } {
  const ws = wb.worksheets[0]
  if (!ws) throw new Error('El archivo no tiene hojas.')
  const idx: Record<string, number> = {}
  ws.getRow(1).eachCell((cell, col) => {
    const k = COLUMNAS[norm(texto(cell.value))]
    if (k && idx[k] == null) idx[k] = col
  })
  const faltan = OBLIGATORIAS.filter((k) => idx[k] == null)
  if (faltan.length)
    throw new Error('No parece el Excel de Transacciones de Aramco Fleet: faltan las columnas de '
      + faltan.map((k) => ({ fecha: 'fecha', patente: 'patente', cod_autorizacion: 'código de autorización', litros: 'volumen' }[k])).join(', ') + '.')

  const filas: FilaTarjeta[] = []
  let descartadas = 0
  ws.eachRow((row, n) => {
    if (n === 1) return
    const v = (k: string) => (idx[k] ? row.getCell(idx[k]).value : null)
    const fecha = fechaLocal(v('fecha')), patente = texto(v('patente')), cod = texto(v('cod_autorizacion'))
    const litros = numero(v('litros'))
    if (!fecha || !patente || !cod || litros == null) { descartadas++; return }
    filas.push({
      cod_autorizacion: cod, fecha_hora: fecha, patente, litros,
      tarjeta: texto(v('tarjeta')), tipo_tarjeta: texto(v('tipo_tarjeta')), tipo_vehiculo: texto(v('tipo_vehiculo')),
      centro_costo: texto(v('centro_costo')), guia_despacho: texto(v('guia_despacho')), factura: texto(v('factura')),
      rut_chofer: texto(v('rut_chofer')), odometro: numero(v('odometro')), producto: texto(v('producto')),
      estacion: texto(v('estacion')), comuna: texto(v('comuna')), pizarra: numero(v('pizarra')),
      total_pizarra: numero(v('total_pizarra')), total_descuento: numero(v('total_descuento')), total_pago: numero(v('total_pago')),
    })
  })
  return { filas, descartadas }
}

export type ResultadoImportacion = {
  importacion_id: string
  filas: number
  nuevas: number
  repetidas: number
  con_posicion_gps: number
  desde: string | null
  hasta: string | null
  patentes_sin_ficha: string[]
}

export async function importarTarjeta(archivo: string, filas: FilaTarjeta[]) {
  const { data, error } = await supabase.rpc('rpc_combustible_tarjeta_importar', { p_archivo: archivo, p_filas: filas })
  if (error) throw error
  return data as ResultadoImportacion
}

export type Importacion = {
  id: string; archivo: string | null; filas: number; nuevas: number; repetidas: number
  desde: string | null; hasta: string | null; created_at: string
}
export async function getImportaciones() {
  const { data, error } = await supabase.from('combustible_tarjeta_importaciones')
    .select('id, archivo, filas, nuevas, repetidas, desde, hasta, created_at')
    .order('created_at', { ascending: false }).limit(8)
  if (error) throw error
  return (data ?? []) as Importacion[]
}

// [MIG660] Los aljibes de combustible cargan para abastecer a otros equipos.
export type Grupo = 'flota' | 'abastecimiento'

export type RendimientoMes = {
  fuente: 'tarjeta' | 'computador'
  activo_id: string | null
  patente: string
  tipo: string | null
  mes: string
  cargas: number | null
  litros: number | null
  monto: number | null
  monto_real: boolean
  km_gps: number | null
  dias_gps: number | null
  horas: number | null
  litros_ralenti: number | null
  cargas_medidas: number | null
  km_medidos: number | null
  km_l: number | null
  costo_km: number | null
  grupo: Grupo
}
export async function getRendimientoMes(desdeMes: string) {
  const { data, error } = await supabase.from('v_combustible_rendimiento_mes').select('*')
    .gte('mes', desdeMes).order('patente').order('mes')
  if (error) throw error
  return (data ?? []) as RendimientoMes[]
}

// Fecha de la primera carga guardada: el mes en que parte el historial está incompleto.
export async function getPrimeraCarga() {
  const { data, error } = await supabase.from('combustible_tarjeta_cargas').select('fecha_hora')
    .order('fecha_hora').limit(1).maybeSingle()
  if (error) throw error
  return (data?.fecha_hora as string | undefined)?.slice(0, 10) ?? null
}

export type Alerta = 'sin_ficha' | 'sin_gps' | 'fuera_estacion' | 'sobre_estanque' | 'sin_movimiento' | 'rendimiento_bajo' | 'dos_cargas_dia'
  | 'litros_dia_excede'
export const ALERTA_TXT: Record<Alerta, string> = {
  sin_ficha: 'Patente no está en SICOM',
  sin_gps: 'Sin GPS: no hay km',
  fuera_estacion: 'El GPS no estaba en la estación',
  sobre_estanque: 'Más litros de los que caben',
  sin_movimiento: 'Cargó sin haberse movido',
  // [MIG662] regla de 30 días: cargó más de lo que gastó andando + un estanque
  rendimiento_bajo: 'Cargó más de lo que explican sus km',
  dos_cargas_dia: 'Dos o más cargas el mismo día',
  litros_dia_excede: 'En el día cargó más de lo que cabe y gastó',
}

export type CargaTarjeta = {
  id: string
  fecha_hora: string
  patente: string
  patente_ver: string
  activo_id: string | null
  tipo_vehiculo: string | null
  tiene_gps: boolean
  producto: string | null
  estacion: string | null
  comuna: string | null
  rut_chofer: string | null
  litros: number
  pizarra_l: number | null
  total_pago: number | null
  gps_lat: number | null
  gps_lng: number | null
  gps_dif_min: number | null
  odometro_gps: number | null
  km_tramo: number | null
  km_l_tramo: number | null
  km_l_mediana: number | null
  dist_estacion_km: number | null
  alertas: Alerta[]
  grupo: Grupo
  capacidad_l: number | null
  litros_dia: number | null
  km_dia: number | null
  litros_30d: number | null
  km_30d: number | null
  litros_sin_explicar_30d: number | null
}
export async function getCargasTarjeta(desde: string, hasta: string) {
  const { data, error } = await supabase.from('v_combustible_tarjeta_cargas')
    .select('id, fecha_hora, patente, patente_ver, activo_id, tipo_vehiculo, tiene_gps, producto, estacion, comuna, rut_chofer, litros, pizarra_l, total_pago, gps_lat, gps_lng, gps_dif_min, odometro_gps, km_tramo, km_l_tramo, km_l_mediana, dist_estacion_km, alertas, grupo, capacidad_l, litros_dia, km_dia, litros_30d, km_30d, litros_sin_explicar_30d')
    .gte('fecha_hora', desde).lt('fecha_hora', hasta)
    .order('fecha_hora', { ascending: false })
  if (error) throw error
  return (data ?? []) as CargaTarjeta[]
}

// [MIG663] Revisión de alertas: por carga o por vehículo-mes. «justificada» sale de
// pendientes; «escalada» sigue visible para seguimiento.
export type EstadoRevision = 'justificada' | 'escalada'
export type RevisionAlerta = {
  id: string; carga_id: string | null; patente: string | null; mes: string | null
  estado: EstadoRevision; comentario: string; created_at: string; revisado_por: string | null
}
export async function getRevisiones() {
  const { data, error } = await supabase.from('v_combustible_tarjeta_revisiones')
    .select('id, carga_id, patente, mes, estado, comentario, created_at, revisado_por')
    .order('created_at', { ascending: false }).limit(2000)
  if (error) throw error
  return (data ?? []) as RevisionAlerta[]
}
export async function revisarAlerta(a: { cargaId?: string; patente?: string; mes?: string; estado: EstadoRevision; comentario: string }) {
  const { error } = await supabase.rpc('rpc_combustible_tarjeta_revisar', {
    p_carga_id: a.cargaId ?? null, p_patente: a.cargaId ? null : a.patente ?? null,
    p_mes: a.cargaId ? null : a.mes ?? null, p_estado: a.estado, p_comentario: a.comentario,
  })
  if (error) throw error
}
export async function borrarRevision(id: string) {
  const { error } = await supabase.rpc('rpc_combustible_tarjeta_revision_borrar', { p_id: id })
  if (error) throw error
}
