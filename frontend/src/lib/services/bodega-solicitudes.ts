import { supabase } from '@/lib/supabase'

export type BodegaSolicitud = {
  id: string
  descripcion: string
  cantidad: number
  unidad: string | null
  foto_url: string | null
  observacion: string | null
  no_conformidad_id: string | null
  activo_id: string | null
  estado: 'pendiente' | 'atendida' | 'rechazada'
  patente: string | null
  activo_codigo: string | null
  solicitado_por_nombre: string | null
  /** [MIG374] El cargo de quien pide: bodega prioriza distinto un pedido de oficina. */
  solicitado_por_cargo?: string | null
  /** [MIG374] Para quién es: oficina, prevención, taller, terreno. */
  area?: string | null
  dias_esperando?: number | null
  nota_bodega: string | null
  created_at: string
}

export async function solicitarMaterialBodega(p: {
  descripcion: string; cantidad?: number; ncId?: string | null; observacion?: string | null; unidad?: string | null
  /** Foto del material solicitado; si no viene y hay NC, la RPC hereda la foto de la NC. */
  fotoUrl?: string | null
  /** [MIG374] El equipo, cuando el pedido es para una patente. */
  activoId?: string | null
  /** [MIG374] Para quién es: oficina, prevención, taller, terreno. */
  area?: string | null
}) {
  const { data, error } = await supabase.rpc('fn_solicitar_material_bodega', {
    p_descripcion: p.descripcion,
    p_cantidad: p.cantidad ?? 1,
    p_nc_id: p.ncId ?? null,
    p_observacion: p.observacion ?? null,
    p_foto_url: p.fotoUrl ?? null,
    p_unidad: p.unidad ?? null,
    p_activo_id: p.activoId ?? null,
    p_area: p.area ?? null,
  })
  if (error) throw error
  return data as { solicitud_id: string }
}

/** Lo que uno mismo pidió, para saber en qué va sin llamar a bodega. */
export async function getMisSolicitudesBodega(): Promise<BodegaSolicitud[]> {
  const { data: u } = await supabase.auth.getUser()
  if (!u?.user) return []
  const { data, error } = await supabase
    .from('bodega_solicitudes')
    .select('id, descripcion, cantidad, unidad, estado, area, nota_bodega, created_at')
    .eq('solicitado_por', u.user.id)
    .order('created_at', { ascending: false })
    .limit(20)
  if (error) throw error
  return (data ?? []) as unknown as BodegaSolicitud[]
}

export async function getSolicitudesBodega(estado?: string): Promise<BodegaSolicitud[]> {
  let q = supabase.from('v_bodega_solicitudes').select('*').order('created_at', { ascending: false })
  if (estado) q = q.eq('estado', estado)
  const { data, error } = await q
  if (error) throw error
  return (data ?? []) as BodegaSolicitud[]
}

export async function atenderSolicitudBodega(p: {
  id: string; estado?: 'atendida' | 'rechazada' | 'pendiente'; nota?: string | null; productoId?: string | null
}) {
  const { data, error } = await supabase.rpc('fn_atender_solicitud_bodega', {
    p_id: p.id,
    p_estado: p.estado ?? 'atendida',
    p_nota: p.nota ?? null,
    p_producto_id: p.productoId ?? null,
  })
  if (error) throw error
  return data
}
