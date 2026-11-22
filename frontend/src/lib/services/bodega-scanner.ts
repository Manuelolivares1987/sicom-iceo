// ============================================================================
// Scanner de bodega (rehecho 22-11-2026)
// ----------------------------------------------------------------------------
// El scanner anterior insertaba directo en movimientos_inventario con columnas
// y valores que no existen (tipo_movimiento, salida_consumo, costo_total
// calculado) — no funcionaba nunca — y además se saltaba FIFO y kardex.
// Ahora es solo una forma rápida de ARMAR la lista con la pistola; el registro
// pasa por las mismas funciones de la oficina:
//   salida  → rpc_registrar_salida_bodega (FIFO, exige CECO, OT opcional)
//   entrada → rpc_ingreso_bodega_simple   (proveedor + documento)
// ============================================================================
import { supabase } from '@/lib/supabase'

export type ProductoScan = {
  id: string
  codigo: string
  codigo_barras: string | null
  nombre: string
  unidad_medida: string
  costo_unitario_actual: number
}

const SEL = 'id, codigo, codigo_barras, nombre, unidad_medida, costo_unitario_actual'

/** Producto por código exacto: primero código de barras, después código interno. */
export async function buscarPorCodigo(codigo: string): Promise<ProductoScan | null> {
  const c = codigo.trim()
  if (!c) return null
  const porBarras = await supabase.from('productos').select(SEL).eq('codigo_barras', c).limit(1)
  if (porBarras.error) throw porBarras.error
  if (porBarras.data?.length) return norm(porBarras.data[0])
  const porCodigo = await supabase.from('productos').select(SEL).ilike('codigo', c).limit(1)
  if (porCodigo.error) throw porCodigo.error
  return porCodigo.data?.length ? norm(porCodigo.data[0]) : null
}

/** Búsqueda por nombre/código para asignar un código de barras nuevo. */
export async function buscarParaAsignar(q: string): Promise<ProductoScan[]> {
  const t = q.replace(/[%,()]/g, ' ').trim()
  if (t.length < 2) return []
  const { data, error } = await supabase.from('productos').select(SEL)
    .neq('categoria', 'combustible')
    .or(`nombre.ilike.%${t}%,codigo.ilike.%${t}%`)
    .order('nombre').limit(15)
  if (error) throw error
  return (data ?? []).map(norm)
}

/** Deja el código de barras pistoleado anotado en el producto (MIG725). */
export async function asignarCodigoBarras(productoId: string, codigo: string): Promise<void> {
  const { error } = await supabase.rpc('rpc_producto_asignar_codigo_barras', {
    p_producto_id: productoId, p_codigo: codigo.trim(),
  })
  if (error) {
    if (/function .*rpc_producto_asignar_codigo_barras|does not exist|PGRST202/i.test(`${error.message} ${error.code}`)) {
      throw new Error('Asignar códigos de barras todavía no está habilitado en el servidor (MIG725).')
    }
    throw error
  }
}

/** Stock por producto en una bodega (para avisar si la salida supera lo disponible). */
export async function stockEnBodega(bodegaId: string, productoIds: string[]): Promise<Record<string, number>> {
  if (!bodegaId || productoIds.length === 0) return {}
  const { data, error } = await supabase.from('stock_bodega')
    .select('producto_id, cantidad').eq('bodega_id', bodegaId).in('producto_id', productoIds)
  if (error) throw error
  const out: Record<string, number> = {}
  for (const r of (data ?? []) as Array<{ producto_id: string; cantidad: number }>) out[r.producto_id] = Number(r.cantidad)
  return out
}

export async function registrarSalidaScanner(p: {
  bodega_id: string
  ceco_id: string
  ot_id: string | null
  motivo: string
  entregado_a: string | null
  items: Array<{ producto_id: string; cantidad: number; unidad: string | null }>
}): Promise<{ folio: string }> {
  const { data, error } = await supabase.rpc('rpc_registrar_salida_bodega', {
    p_tipo_salida: p.ot_id ? 'ot' : 'ceco',
    p_bodega_id: p.bodega_id,
    p_ceco_id: p.ceco_id,
    p_ot_id: p.ot_id,
    p_motivo: p.motivo,
    p_items: p.items,
    p_entregado_a: p.entregado_a,
    p_entregado_a_perfil_id: null,
    p_autorizado_por: null,
    p_evidencia_url: null,
    p_observacion: 'Registrada con el Scanner',
  })
  if (error) throw error
  return { folio: String((data as { folio?: string } | null)?.folio ?? '') }
}

function norm(r: unknown): ProductoScan {
  const x = r as ProductoScan
  return { ...x, costo_unitario_actual: Number(x.costo_unitario_actual ?? 0) }
}
