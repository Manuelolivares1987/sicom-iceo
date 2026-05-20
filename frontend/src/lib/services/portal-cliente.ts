import { supabase } from '@/lib/supabase'

// ====== ADMIN ==============================================================

export type PerfilPortalAdmin = {
  id:                 string
  user_id:            string
  email:              string | null
  nombre_visible:     string
  empresa:            string | null
  rut_empresa:        string | null
  contratos_ids:      string[]
  empresas_externas:  string[]
  activo:             boolean
  creado_at:          string
  ultimo_acceso_at:   string | null
  notas:              string | null
  n_contratos:        number | null
  n_empresas:         number | null
}

export async function cargarPerfilesPortal(): Promise<PerfilPortalAdmin[]> {
  const { data, error } = await supabase
    .from('v_admin_perfiles_portal')
    .select('*')
    .order('creado_at', { ascending: false })
  if (error) throw error
  return (data ?? []) as PerfilPortalAdmin[]
}

export async function crearPerfilPortal(params: {
  userId:            string
  nombreVisible:     string
  empresa?:          string
  rutEmpresa?:       string
  contratosIds:      string[]
  empresasExternas:  string[]
  notas?:            string
}): Promise<{ ok: boolean; perfil_id: string }> {
  const { data, error } = await supabase.rpc('rpc_admin_crear_perfil_portal', {
    p_user_id:           params.userId,
    p_nombre_visible:    params.nombreVisible,
    p_empresa:           params.empresa ?? null,
    p_rut_empresa:       params.rutEmpresa ?? null,
    p_contratos_ids:     params.contratosIds,
    p_empresas_externas: params.empresasExternas,
    p_notas:             params.notas ?? null,
  })
  if (error) throw error
  return data as { ok: boolean; perfil_id: string }
}

export async function togglePerfilPortal(userId: string, activo: boolean): Promise<void> {
  const { error } = await supabase.rpc('rpc_admin_toggle_perfil_portal', {
    p_user_id: userId, p_activo: activo,
  })
  if (error) throw error
}

export async function cargarEmpresasExternasDistintas(): Promise<string[]> {
  const { data, error } = await supabase
    .from('vehiculos_autorizados_externos')
    .select('empresa')
    .eq('activo', true)
    .order('empresa')
  if (error) throw error
  return Array.from(new Set((data ?? []).map((r: { empresa: string }) => r.empresa)))
}


// ====== PORTAL (cliente) ===================================================

export type TransaccionCombustibleCliente = {
  id:                          string
  tipo:                        string
  litros:                      number
  lectura_inicial_lt:          number
  lectura_final_lt:            number
  costo_unitario_clp:          number | null
  costo_total_clp:             number | null
  // MIG73: precio de venta al cliente
  precio_venta_clp_lt:         number | null
  total_venta_clp:             number | null
  fecha:                       string
  observaciones:               string | null
  estanque_nombre:             string | null
  estanque_codigo:             string | null
  destino_tipo:                string | null
  destino_descripcion:         string | null
  vehiculo_activo_id:          string | null
  activo_codigo:               string | null
  activo_patente:              string | null
  activo_contrato_id:          string | null
  activo_contrato_codigo:      string | null
  activo_cliente:              string | null
  vehiculo_externo_id:         string | null
  externo_patente:             string | null
  externo_empresa:             string | null
  foto_medidor_inicial_url:    string | null
  foto_medidor_final_url:      string | null
  foto_patente_url:            string | null
  nombre_receptor:             string | null
  rut_receptor:                string | null
  firma_receptor_url:          string | null
  horometro_vehiculo:          number | null
  kilometraje_vehiculo:        number | null
}

export type FiltrosPortal = {
  fechaDesde?: string  // ISO date
  fechaHasta?: string
  patente?:    string  // busqueda libre
  empresa?:    string
}

export async function cargarTransaccionesCliente(filtros: FiltrosPortal = {}): Promise<TransaccionCombustibleCliente[]> {
  let q = supabase
    .from('v_combustible_movimientos_cliente')
    .select('*')
    .order('fecha', { ascending: false })
    .limit(500)

  if (filtros.fechaDesde) q = q.gte('fecha', filtros.fechaDesde + 'T00:00:00')
  if (filtros.fechaHasta) q = q.lte('fecha', filtros.fechaHasta + 'T23:59:59')

  const { data, error } = await q
  if (error) throw error
  let rows = (data ?? []) as TransaccionCombustibleCliente[]
  if (filtros.patente) {
    const q2 = filtros.patente.toLowerCase()
    rows = rows.filter((r) =>
      (r.activo_patente ?? '').toLowerCase().includes(q2) ||
      (r.externo_patente ?? '').toLowerCase().includes(q2)
    )
  }
  if (filtros.empresa) {
    const q2 = filtros.empresa.toLowerCase()
    rows = rows.filter((r) =>
      (r.externo_empresa ?? '').toLowerCase().includes(q2) ||
      (r.activo_cliente  ?? '').toLowerCase().includes(q2)
    )
  }
  return rows
}

export async function marcarAccesoPortal(): Promise<void> {
  await supabase.rpc('rpc_portal_marcar_acceso')
}

// ====== Agregaciones para dashboard ========================================

export type ResumenPorDia = {
  fecha:           string      // YYYY-MM-DD
  transacciones:   number
  litros:          number
  costo:           number
  patentes_unicas: number
}

// Agrupa por dia mostrando el TOTAL A PAGAR del cliente (no el CPP interno).
// MIG73: el portal ve total_venta_clp, no costo_total_clp.
export function agruparPorDia(rows: TransaccionCombustibleCliente[]): ResumenPorDia[] {
  const grupos = new Map<string, {
    transacciones: number; litros: number; costo: number; patentes: Set<string>
  }>()
  for (const r of rows) {
    const fecha = r.fecha.slice(0, 10)
    if (!grupos.has(fecha)) {
      grupos.set(fecha, { transacciones: 0, litros: 0, costo: 0, patentes: new Set() })
    }
    const g = grupos.get(fecha)!
    g.transacciones++
    g.litros += Number(r.litros)
    g.costo  += Number(r.total_venta_clp ?? 0)
    const pat = r.activo_patente ?? r.externo_patente
    if (pat) g.patentes.add(pat)
  }
  return Array.from(grupos.entries())
    .map(([fecha, g]) => ({
      fecha,
      transacciones:   g.transacciones,
      litros:          g.litros,
      costo:           g.costo,
      patentes_unicas: g.patentes.size,
    }))
    .sort((a, b) => a.fecha.localeCompare(b.fecha))
}

// MIG73: el cliente ve total_venta_clp (lo que paga), no costo_total_clp (CPP).
export function calcularKpis(rows: TransaccionCombustibleCliente[]) {
  const litros = rows.reduce((s, r) => s + Number(r.litros), 0)
  const costo  = rows.reduce((s, r) => s + Number(r.total_venta_clp ?? 0), 0)
  const patentes = new Set<string>()
  for (const r of rows) {
    const p = r.activo_patente ?? r.externo_patente
    if (p) patentes.add(p)
  }
  return {
    transacciones: rows.length,
    litros,
    costo,
    patentes_unicas: patentes.size,
  }
}

export async function esUsuarioPortal(): Promise<boolean> {
  const { data, error } = await supabase.rpc('fn_es_usuario_portal')
  if (error) return false
  return data === true
}

// ====== MIG73: Precios de venta de combustible =============================

export type PrecioVentaCombustible = {
  id:              string
  empresa_externa: string | null
  contrato_id:     string | null
  precio_clp_lt:   number
  vigente_desde:   string
  vigente_hasta:   string | null
  moneda:          string
  observacion:     string | null
  created_at:      string
}

export async function listarPreciosVentaCombustible(): Promise<PrecioVentaCombustible[]> {
  const { data, error } = await supabase
    .from('precios_venta_combustible')
    .select('*')
    .order('vigente_desde', { ascending: false })
  if (error) throw error
  return (data ?? []) as PrecioVentaCombustible[]
}

export async function setPrecioVentaCombustible(params: {
  empresa?:       string
  contratoId?:    string
  precioClpLt:    number
  vigenteDesde?:  string  // ISO; default NOW
  observacion?:   string
}): Promise<{ success: boolean; nuevo_id: string; cerrado_id: string | null }> {
  const { data, error } = await supabase.rpc('rpc_admin_set_precio_venta', {
    p_empresa:        params.empresa ?? null,
    p_contrato_id:    params.contratoId ?? null,
    p_precio_clp_lt:  params.precioClpLt,
    p_vigente_desde:  params.vigenteDesde ?? null,
    p_observacion:    params.observacion ?? null,
  })
  if (error) throw error
  return data as { success: boolean; nuevo_id: string; cerrado_id: string | null }
}

export type KpiCliente = {
  transacciones:     number
  litros:            number
  costo_propio:      number  // CPP (interno: costo Pillado)
  total_a_pagar:     number  // Suma de total_venta_clp (lo que el cliente paga)
  patentes_unicas:   number
  filas_sin_precio:  number  // despachos donde no hay precio_venta_clp_lt
}

export function calcularKpisCliente(rows: TransaccionCombustibleCliente[]): KpiCliente {
  const patentes = new Set<string>()
  let litros = 0, costoPropio = 0, totalVenta = 0, sinPrecio = 0
  for (const r of rows) {
    litros      += Number(r.litros)
    costoPropio += Number(r.costo_total_clp ?? 0)
    totalVenta  += Number(r.total_venta_clp ?? 0)
    if (r.precio_venta_clp_lt == null) sinPrecio++
    const p = r.activo_patente ?? r.externo_patente
    if (p) patentes.add(p)
  }
  return {
    transacciones:    rows.length,
    litros,
    costo_propio:     costoPropio,
    total_a_pagar:    totalVenta,
    patentes_unicas:  patentes.size,
    filas_sin_precio: sinPrecio,
  }
}

// ====== MIG74: Corregir patente de despacho ================================
export async function corregirPatenteDespacho(params: {
  id:                       string
  nuevoEquipoId?:           string | null
  nuevoVehiculoExternoId?:  string | null
  motivo:                   string
}): Promise<{ success: boolean; patente_anterior: string; patente_nueva: string; origen: string }> {
  const { data, error } = await supabase.rpc('rpc_admin_corregir_patente_despacho', {
    p_id:                          params.id,
    p_nuevo_equipo_id:             params.nuevoEquipoId ?? null,
    p_nuevo_vehiculo_externo_id:   params.nuevoVehiculoExternoId ?? null,
    p_motivo:                      params.motivo,
  })
  if (error) throw error
  return data as { success: boolean; patente_anterior: string; patente_nueva: string; origen: string }
}

export function totalMesEnCurso(rows: TransaccionCombustibleCliente[]): number {
  const now = new Date()
  const inicioMes = new Date(now.getFullYear(), now.getMonth(), 1).toISOString()
  return rows
    .filter((r) => r.fecha >= inicioMes)
    .reduce((s, r) => s + Number(r.total_venta_clp ?? 0), 0)
}
