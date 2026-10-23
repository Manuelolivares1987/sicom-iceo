// ============================================================================
// [MIG647] Programa de servicio por modelo
// ----------------------------------------------------------------------------
// El servicio va cada 300 h (intervalo SICOM); lo que se hace en cada uno sigue
// la pauta del fabricante contada en servicios: una operación «cada 3» toca en
// los servicios 3, 6, 9… El kit de repuestos del servicio N° n es la suma de
// los repuestos de las operaciones que tocan en n.
// La escalera (Horas por equipo) dice CUÁNDO; el programa dice QUÉ.
// ============================================================================

import { supabase } from '@/lib/supabase'

export type AccionOperacion = 'sustituir' | 'lubricar' | 'ajustar' | 'inspeccionar' | 'otro'

export type ProgramaModelo = {
  modelo_id: string
  intervalo_horas: number
  fuente: string | null
  notas: string | null
  modelo: { nombre: string; marca: { nombre: string } | null } | null
}

export type Operacion = {
  id: string
  modelo_id: string
  orden: number
  operacion: string
  accion: AccionOperacion
  cada_servicios: number
  nota: string | null
}

export type Repuesto = {
  id: string
  operacion_id: string
  modelo_id: string
  orden: number
  n_parte: string | null
  descripcion: string
  cantidad: number
  unidad: string
  producto_id: string | null
  producto_codigo: string | null
  producto_nombre: string | null
  costo_unitario_actual: number | null
  stock_total: number | null
}

export type ServicioProyectado = {
  activo_id: string
  patente: string | null
  codigo: string | null
  nombre: string | null
  faena: string | null
  modelo_id: string
  modelo: string
  intervalo: number
  horometro: number | null
  horas_por_dia: number | null
  ot_abierta: string | null
  pauta_escalera: string | null
  orden: number
  n_servicio: number
  horas_servicio: number
  horas_faltan: number
  fecha_estimada: string | null
}

export type RepuestoInput = {
  n_parte: string | null
  descripcion: string
  cantidad: number
  unidad: string
  producto_id?: string | null
}

/** ¿Toca esta operación en el servicio N° n? */
export const tocaEnServicio = (op: Pick<Operacion, 'cada_servicios'>, n: number) =>
  n > 0 && n % op.cada_servicios === 0

export async function getProgramas(): Promise<ProgramaModelo[]> {
  const { data, error } = await supabase
    .from('programa_servicio')
    .select('modelo_id, intervalo_horas, fuente, notas, modelo:modelos(nombre, marca:marcas(nombre))')
  if (error) throw new Error(error.message)
  return (data ?? []) as unknown as ProgramaModelo[]
}

export async function getModelos(): Promise<{ id: string; nombre: string; marca: string | null }[]> {
  const { data, error } = await supabase
    .from('modelos').select('id, nombre, marca:marcas(nombre)').order('nombre')
  if (error) throw new Error(error.message)
  return ((data ?? []) as unknown as { id: string; nombre: string; marca: { nombre: string } | null }[])
    .map((m) => ({ id: m.id, nombre: m.nombre, marca: m.marca?.nombre ?? null }))
}

export async function getOperaciones(): Promise<Operacion[]> {
  const { data, error } = await supabase
    .from('programa_servicio_operacion')
    .select('id, modelo_id, orden, operacion, accion, cada_servicios, nota')
    .eq('activo', true)
    .order('cada_servicios').order('orden')
  if (error) throw new Error(error.message)
  return (data ?? []) as Operacion[]
}

export async function getRepuestos(): Promise<Repuesto[]> {
  const { data, error } = await supabase.from('v_programa_repuesto').select('*').order('orden')
  if (error) throw new Error(error.message)
  return (data ?? []) as Repuesto[]
}

export async function getServiciosProyectados(): Promise<ServicioProyectado[]> {
  const { data, error } = await supabase
    .from('v_servicios_proyectados').select('*')
    .order('fecha_estimada', { ascending: true, nullsFirst: false })
  if (error) throw new Error(error.message)
  return (data ?? []) as ServicioProyectado[]
}

export async function puedeEditarPrograma(): Promise<boolean> {
  const { data, error } = await supabase.rpc('fn_programa_servicio_puede_editar')
  if (error) return false
  return !!data
}

export async function guardarOperacion(p: {
  id: string | null; modeloId: string; operacion: string; accion: AccionOperacion
  cada: number; nota: string | null; orden: number | null
}) {
  const { data, error } = await supabase.rpc('rpc_programa_operacion_guardar', {
    p_id: p.id, p_modelo_id: p.modeloId, p_operacion: p.operacion, p_accion: p.accion,
    p_cada: p.cada, p_nota: p.nota, p_orden: p.orden,
  })
  if (error) throw new Error(error.message)
  return data as string
}

export async function quitarOperacion(id: string) {
  const { error } = await supabase.rpc('rpc_programa_operacion_quitar', { p_id: id })
  if (error) throw new Error(error.message)
}

export async function fijarIntervalo(modeloId: string, horas: number) {
  const { error } = await supabase.rpc('rpc_programa_intervalo', { p_modelo_id: modeloId, p_horas: horas })
  if (error) throw new Error(error.message)
}

export async function guardarRepuestos(operacionId: string, items: RepuestoInput[]) {
  const { data, error } = await supabase.rpc('rpc_programa_repuestos_guardar', {
    p_operacion_id: operacionId, p_items: items,
  })
  if (error) throw new Error(error.message)
  return data as number
}

/**
 * Lo pegado desde Excel: una fila por repuesto, columnas separadas por TAB
 * (o «;»): N° parte | Descripción | Cantidad | Unidad. La primera fila se
 * descarta si parece encabezado (sin cantidad numérica).
 */
export function parsearRepuestosPegados(texto: string): RepuestoInput[] {
  const filas: RepuestoInput[] = []
  for (const linea of texto.split(/\r?\n/)) {
    if (!linea.trim()) continue
    const c = linea.split(linea.includes('\t') ? '\t' : ';').map((s) => s.trim())
    const [np, desc, cant, unidad] = c
    const n = Number((cant ?? '').replace(/\./g, '').replace(',', '.'))
    if (!desc || !Number.isFinite(n) || n <= 0) continue
    filas.push({ n_parte: np || null, descripcion: desc, cantidad: n, unidad: unidad || 'un' })
  }
  return filas
}

/** Repuestos que pide el servicio N° n de un modelo. */
export function kitDelServicio(n: number, ops: Operacion[], reps: Repuesto[]) {
  const tocan = ops.filter((o) => tocaEnServicio(o, n))
  const ids = new Set(tocan.map((o) => o.id))
  return { operaciones: tocan, repuestos: reps.filter((r) => ids.has(r.operacion_id)) }
}

/** Clave para sumar el mismo repuesto entre servicios y modelos. */
export const claveRepuesto = (r: Pick<Repuesto, 'producto_id' | 'n_parte' | 'descripcion' | 'unidad'>) =>
  r.producto_id ?? (r.n_parte ? `np:${r.n_parte.toUpperCase()}` : `d:${r.descripcion.toLowerCase()}|${r.unidad}`)
