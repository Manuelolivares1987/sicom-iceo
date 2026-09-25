// ============================================================================
// Recobro por OT (MIG576): el jefe de taller arma las partidas y da el OK; el
// planificador revisa, carga los costos y emite. Todas las escrituras pasan por
// RPC (la base valida quién puede qué); las lecturas van directo a las tablas.
// ============================================================================
import { supabase } from '@/lib/supabase'
import { getInformeParaWord, getHallazgosParaWord } from '@/lib/services/informe-recepcion'
import { generarInformeRecobroWord, descargarBlob } from '@/lib/docx/informe-recobro-word'

export type TipoPartida = 'repuesto' | 'mano_obra' | 'servicio_externo' | 'otro'

export type PartidaRecobro = {
  id: string
  tipo: TipoPartida
  descripcion: string
  cantidad: number
  unidad: string | null
  precio_unitario: number
  total: number
  cobrable_cliente: boolean
  hallazgo_id: string | null
}

export type InformeRecobroOT = {
  id: string
  folio: string | null
  estado: 'en_inspeccion' | 'borrador' | 'emitido' | 'cancelado'
  ok_jefe_por: string | null
  ok_jefe_at: string | null
  ok_jefe_nota: string | null
  devuelto_nota: string | null
  encargado_cobros_id: string | null
  emitido_en: string | null
  subtotal_neto: number
  iva: number
  total: number
  total_cobrable_cliente: number
  total_no_cobrable: number
}

export type RecobroOT = {
  /** El informe abierto de la OT, o el último emitido si no hay abierto. */
  informe: InformeRecobroOT | null
  partidas: PartidaRecobro[]
  /** Informes ya emitidos de esta OT (puede haber más de uno). */
  emitidos: { id: string; folio: string | null; emitido_en: string | null; total: number }[]
  nombres: Record<string, string>
  /** NC cobrables de la OT que todavía no están en ningún informe. */
  ncPendientes: number
  /** [MIG578] Tareas del checklist que ya están en el informe abierto. */
  itemsEnInforme: string[]
}

/** Perfil del usuario frente al recobro — el mismo criterio que fn_recobro_perfil. */
export function perfilRecobro(rol: string | null | undefined): 'admin' | 'planificador' | 'jefe' | null {
  if (!rol) return null
  if (['administrador', 'gerencia', 'subgerente_operaciones'].includes(rol)) return 'admin'
  if (rol === 'planificador') return 'planificador'
  if (['jefe_mantenimiento', 'jefe_operaciones', 'supervisor'].includes(rol)) return 'jefe'
  return null
}

const CAMPOS = 'id, folio, estado, ok_jefe_por, ok_jefe_at, ok_jefe_nota, devuelto_nota, encargado_cobros_id, '
  + 'emitido_en, subtotal_neto, iva, total, total_cobrable_cliente, total_no_cobrable'

export async function getRecobroOT(otId: string): Promise<RecobroOT> {
  const { data: infs, error } = await supabase
    .from('informes_recepcion')
    .select(CAMPOS)
    .eq('ot_correctiva_id', otId)
    .neq('estado', 'cancelado')
    .order('created_at', { ascending: false })
  if (error) throw new Error(error.message)
  const lista = (infs ?? []) as unknown as InformeRecobroOT[]
  const abierto = lista.find((i) => i.estado === 'borrador' || i.estado === 'en_inspeccion') ?? null
  const emitidos = lista.filter((i) => i.estado === 'emitido')
  const informe = abierto ?? emitidos[0] ?? null

  let partidas: PartidaRecobro[] = []
  let itemsEnInforme: string[] = []
  if (informe) {
    const { data: hs } = await supabase
      .from('informe_recepcion_hallazgos')
      .select('checklist_v2_item_id')
      .eq('informe_id', informe.id)
      .not('checklist_v2_item_id', 'is', null)
    itemsEnInforme = ((hs ?? []) as { checklist_v2_item_id: string }[]).map((h) => h.checklist_v2_item_id)
    const { data, error: e2 } = await supabase
      .from('informe_recepcion_costos')
      .select('id, tipo, descripcion, cantidad, unidad, precio_unitario, total, cobrable_cliente, hallazgo_id')
      .eq('informe_id', informe.id)
      .order('created_at')
    if (e2) throw new Error(e2.message)
    partidas = ((data ?? []) as PartidaRecobro[]).map((p) => ({
      ...p, cantidad: Number(p.cantidad), precio_unitario: Number(p.precio_unitario), total: Number(p.total),
    }))
  }

  const ids = Array.from(new Set(lista.flatMap((i) => [i.ok_jefe_por, i.encargado_cobros_id]).filter(Boolean))) as string[]
  const nombres: Record<string, string> = {}
  if (ids.length > 0) {
    const { data } = await supabase.from('usuarios_perfil').select('id, nombre_completo').in('id', ids)
    for (const u of (data ?? []) as { id: string; nombre_completo: string }[]) nombres[u.id] = u.nombre_completo
  }

  const { data: ncs } = await supabase
    .from('v_nc_recepcion')
    .select('id, recobro, recobro_informe_id, ot_id, plan_ot_id')
    .or(`ot_id.eq.${otId},plan_ot_id.eq.${otId}`)
  const ncPendientes = ((ncs ?? []) as { recobro: string | null; recobro_informe_id: string | null }[])
    .filter((n) => (n.recobro === 'cliente' || n.recobro === 'compartido') && !n.recobro_informe_id).length

  return {
    informe,
    partidas,
    emitidos: emitidos.map((e) => ({ id: e.id, folio: e.folio, emitido_en: e.emitido_en, total: Number(e.total) })),
    nombres,
    ncPendientes,
    itemsEnInforme,
  }
}

async function rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.rpc(fn, args)
  if (error) throw new Error(error.message)
  return data as T
}

export const prepararRecobroOT = (otId: string) =>
  rpc<{ informe_id: string; folio: string; nuevo: boolean; nc_traidas: number; partidas_creadas: number }>(
    'rpc_recobro_ot_preparar', { p_ot_id: otId })

export const guardarPartida = (informeId: string, p: {
  id?: string | null; tipo: TipoPartida; descripcion: string; cantidad: number
  unidad?: string | null; cobrable: boolean; precio_unitario?: number | null
}) => rpc<string>('rpc_recobro_partida_guardar', {
  p_informe_id: informeId,
  p_partida_id: p.id ?? null,
  p_tipo: p.tipo,
  p_descripcion: p.descripcion,
  p_cantidad: p.cantidad,
  p_unidad: p.unidad ?? null,
  p_cobrable: p.cobrable,
  p_precio_unitario: p.precio_unitario ?? null,
})

/** [MIG578] Tareas del checklist de la OT → hallazgo con fotos + partida de HH en $0. */
export const agregarDesdeChecklist = (informeId: string, itemIds: string[]) =>
  rpc<{ agregadas: number; ya_estaban: number }>('rpc_recobro_agregar_checklist', {
    p_informe_id: informeId, p_item_ids: itemIds,
  })

export const eliminarPartida = (partidaId: string) =>
  rpc<void>('rpc_recobro_partida_eliminar', { p_partida_id: partidaId })

export const darOkJefe = (informeId: string, nota?: string) =>
  rpc<unknown>('rpc_recobro_ok_jefe', { p_informe_id: informeId, p_nota: nota ?? null })

export const devolverAlJefe = (informeId: string, nota: string) =>
  rpc<unknown>('rpc_recobro_devolver', { p_informe_id: informeId, p_nota: nota })

export const emitirRecobro = (informeId: string) =>
  rpc<{ folio: string; total: number }>('rpc_recobro_emitir', { p_informe_id: informeId, p_observaciones: null })

/** Arma y descarga el Word del recobro de la OT, con la tabla de partidas cobrables. */
export async function descargarWordRecobroOT(r: RecobroOT, otFolio: string | null) {
  const inf = r.informe
  if (!inf) throw new Error('La OT no tiene informe de recobro')
  const [cab, hallazgos] = await Promise.all([getInformeParaWord(inf.id), getHallazgosParaWord(inf.id)])
  if (!cab) throw new Error('No se pudo leer el informe')
  const cobrables = r.partidas.filter((p) => p.cobrable_cliente)
  const blob = await generarInformeRecobroWord(
    {
      folio: cab.folio,
      cliente_nombre: cab.cliente_nombre,
      fecha_recepcion: cab.fecha_recepcion,
      ciudad: cab.ciudad,
      lugar_chequeo: cab.lugar_chequeo,
      tecnico_cargo: cab.tecnico_cargo,
      elaborado_por: cab.elaborado_por,
      patente: cab.patente,
      equipo_nombre: cab.equipo_nombre,
      marca: cab.marca,
      modelo: cab.modelo,
      n_chasis: cab.n_chasis,
      horometro: cab.horometro,
      kilometraje: cab.kilometraje,
      meter_ingreso: cab.meter_ingreso,
      meter_salida: cab.meter_salida,
      nota_final: cab.nota_final,
      firmante_nombre: (inf.ok_jefe_por && r.nombres[inf.ok_jefe_por]) || cab.elaborado_por,
      firmante_cargo: 'Jefe de Taller',
    },
    hallazgos.map((h) => ({
      descripcion: h.descripcion,
      diagnostico: h.diagnostico,
      medida_correctiva: h.medida_correctiva,
      amerita_recobro: h.amerita_recobro,
      observacion: h.observacion,
      fotos: (h.fotos ?? []) as string[],
    })),
    {
      titulo: 'INFORME DE RECOBRO – TRABAJOS IMPUTABLES AL CLIENTE',
      ot_folio: otFolio,
      partidas: cobrables.map((p) => ({
        tipo: p.tipo, descripcion: p.descripcion, cantidad: p.cantidad, unidad: p.unidad,
        precio_unitario: p.precio_unitario, total: p.total,
      })),
      subtotal: Number(inf.total_cobrable_cliente),
      iva: Number(inf.iva),
      total: Number(inf.total),
      emisor_nombre: inf.encargado_cobros_id ? r.nombres[inf.encargado_cobros_id] ?? null : null,
    },
  )
  const borrador = inf.estado !== 'emitido' ? ' BORRADOR' : ''
  descargarBlob(blob, `Recobro ${cab.patente ?? cab.activo_codigo ?? ''} ${inf.folio ?? ''}${borrador}.docx`.replace(/\s+/g, ' ').trim())
}
