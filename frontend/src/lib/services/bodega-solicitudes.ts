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
  nota_bodega: string | null
  created_at: string
}

export async function solicitarMaterialBodega(p: {
  descripcion: string; cantidad?: number; ncId?: string | null; observacion?: string | null; unidad?: string | null
}) {
  const { data, error } = await supabase.rpc('fn_solicitar_material_bodega', {
    p_descripcion: p.descripcion,
    p_cantidad: p.cantidad ?? 1,
    p_nc_id: p.ncId ?? null,
    p_observacion: p.observacion ?? null,
    p_foto_url: null,
    p_unidad: p.unidad ?? null,
  })
  if (error) throw error
  return data
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
