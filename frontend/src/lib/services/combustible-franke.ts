import { supabase } from '@/lib/supabase'

// ============================================================================
// Control de combustible Franke (MIG 130). Camiones petroleros = estanques
// moviles; cuadre diario; compras por punto de carga; carga de camion.
// ============================================================================

export async function getCamionesFranke() {
  const { data, error } = await supabase
    .from('combustible_estanques')
    .select('id, codigo, nombre, patente, capacidad_lt, stock_teorico_lt, costo_promedio_lt, activo_id, es_demo')
    .eq('tipo', 'movil')
    .eq('operacion', 'Franke')
    .eq('activo', true)
    .order('es_demo')
    .order('codigo')
  return { data: data ?? [], error }
}

// Catálogo de despacho: empresas + sus equipos (desde el histórico cargado).
// Alimenta el selector en cascada de la app del despachador (empresa → equipo).
export async function getCatalogoDespachoFranke() {
  const { data, error } = await supabase
    .from('combustible_abastecimiento_historico')
    .select('cliente, equipo_codigo, equipo_tipo')
    .order('cliente')
    .order('equipo_codigo')
  return { data: data ?? [], error }
}

export async function getHistoricoAbastecimientoCliente() {
  const { data, error } = await supabase
    .from('v_abastecimiento_historico_cliente')
    .select('*')
    .order('litros_total', { ascending: false })
  return { data: data ?? [], error }
}

export async function limpiarDemosFranke() {
  const { data, error } = await supabase.rpc('rpc_limpiar_demos_franke')
  return { data, error }
}

export async function getPuntosCargaFranke() {
  const { data, error } = await supabase
    .from('combustible_puntos_carga')
    .select('*')
    .eq('operacion', 'Franke')
    .eq('activo', true)
    .order('tipo')
  return { data: data ?? [], error }
}

export async function getCuadreDiarioFranke() {
  const { data, error } = await supabase
    .from('v_combustible_cuadre_diario_franke')
    .select('*')
    .order('dia', { ascending: false })
    .limit(120)
  return { data: data ?? [], error }
}

export async function getComprasPuntoFranke() {
  const { data, error } = await supabase
    .from('v_combustible_compras_punto_franke')
    .select('*')
    .order('litros_total', { ascending: false })
  return { data: data ?? [], error }
}

export async function getVentasFranke() {
  const { data, error } = await supabase
    .from('v_ventas_franke')
    .select('*')
    .order('fecha', { ascending: false })
    .limit(200)
  return { data: data ?? [], error }
}

export async function getVentasFrankeCliente() {
  const { data, error } = await supabase
    .from('v_ventas_franke_cliente')
    .select('*')
    .order('monto_total', { ascending: false })
  return { data: data ?? [], error }
}

export async function registrarCargaCamion(p: {
  estanque_movil_id: string
  punto_carga_id: string | null
  litros: number
  costo_unitario_clp?: number | null
  operador_nombre?: string | null
  operador_rut?: string | null
  firma_operador_url?: string | null
  foto_patente_url?: string | null
  foto_medidor_inicial_url?: string | null
  foto_medidor_final_url?: string | null
  lectura_medidor_inicial?: number | null
  lectura_medidor_final?: number | null
  documento_numero?: string | null
  observacion?: string | null
}) {
  const { data, error } = await supabase.rpc('rpc_registrar_carga_camion', {
    p_estanque_movil_id: p.estanque_movil_id,
    p_punto_carga_id: p.punto_carga_id,
    p_litros: p.litros,
    p_costo_unitario_clp: p.costo_unitario_clp ?? null,
    p_operador_nombre: p.operador_nombre ?? null,
    p_operador_rut: p.operador_rut ?? null,
    p_firma_operador_url: p.firma_operador_url ?? null,
    p_foto_patente_url: p.foto_patente_url ?? null,
    p_foto_medidor_inicial_url: p.foto_medidor_inicial_url ?? null,
    p_foto_medidor_final_url: p.foto_medidor_final_url ?? null,
    p_lectura_medidor_inicial: p.lectura_medidor_inicial ?? null,
    p_lectura_medidor_final: p.lectura_medidor_final ?? null,
    p_documento_numero: p.documento_numero ?? null,
    p_observacion: p.observacion ?? null,
  })
  return { data, error }
}
