import { supabase } from '@/lib/supabase'

// ── Types ────────────────────────────────────────────────

export interface PrevencionResumen {
  certificaciones_vencidas: number
  certificaciones_por_vencer_30d: number
  certificaciones_por_vencer_60d: number
  hds_por_revisar: number
  productos_suspel_activos: number
  bodegas_total: number
  bodegas_autorizacion_vencida: number
  bodegas_inspeccion_vencida: number
  respel_generado_mes_kg: number
  respel_retirado_mes_kg: number
  retiros_sin_sidrep: number
  conductores_semep_vencido: number
  conductores_semep_por_vencer: number
  conductores_fatiga_critica: number
  documentos_vencidos: number
  documentos_por_vencer: number
}

export interface SuspelProducto {
  id: string
  codigo: string
  nombre: string
  nombre_comercial?: string
  clase_un: string
  numero_un?: string
  codigo_nch382?: string
  grupo_embalaje?: string
  punto_inflamacion_c?: number
  hds_url?: string
  hds_version?: string
  hds_fecha_emision?: string
  hds_proxima_revision?: string
  proveedor?: string
  pictogramas?: string[]
  activo: boolean
}

export interface SuspelBodega {
  id: string
  codigo: string
  nombre: string
  tipo: string
  faena_id?: string
  ubicacion?: string
  autorizacion_numero?: string
  autorizacion_fecha?: string
  autorizacion_vencimiento?: string
  autoridad_sanitaria?: string
  capacidad_total_kg?: number
  capacidad_total_litros?: number
  productos_permitidos?: string[]
  tiene_ducha_emergencia: boolean
  tiene_lavaojos: boolean
  tiene_kit_derrame: boolean
  tiene_extintor: boolean
  tiene_rotulado: boolean
  tiene_sistema_contencion: boolean
  plan_emergencia_url?: string
  plan_emergencia_fecha?: string
  ultima_inspeccion?: string
  proxima_inspeccion?: string
  activo: boolean
}

export interface RespelTipo {
  id: string
  codigo: string
  nombre: string
  descripcion?: string
  codigo_ds148?: string
  numero_un?: string
  caracteristicas?: string[]
  tratamiento_sugerido?: string
  unidad_medida: string
  es_activo: boolean
}

export interface RespelMovimiento {
  id: string
  tipo_movimiento: 'generacion' | 'retiro' | 'almacenamiento' | 'correccion'
  fecha: string
  respel_tipo_id: string
  cantidad: number
  unidad: string
  bodega_id?: string
  activo_origen_id?: string
  faena_id?: string
  ot_id?: string
  empresa_receptora_id?: string
  numero_sidrep?: string
  numero_guia_transporte?: string
  certificado_disposicion_url?: string
  observaciones?: string
  created_at: string
  // Joined
  respel_tipo?: RespelTipo
  empresa_receptora?: { nombre: string; rut?: string }
}

export interface RespelEmpresa {
  id: string
  nombre: string
  rut?: string
  autorizacion_numero?: string
  autorizacion_vencimiento?: string
  tipo_autorizacion?: string
  regiones_autorizadas?: string[]
  tratamientos_autorizados?: string[]
  contacto_nombre?: string
  contacto_telefono?: string
  contacto_email?: string
  contrato_vigente: boolean
  activo: boolean
}

// ── Queries ──────────────────────────────────────────────

export async function getPrevencionResumen() {
  const { data, error } = await supabase
    .from('vw_prevencion_resumen')
    .select('*')
    .maybeSingle()
  return { data: data as PrevencionResumen | null, error }
}

export async function getSuspelProductos(activo?: boolean) {
  let q = supabase.from('suspel_productos').select('*')
  if (activo !== undefined) q = q.eq('activo', activo)
  const { data, error } = await q.order('nombre')
  return { data: data as SuspelProducto[] | null, error }
}

export async function getSuspelBodegas(activo?: boolean) {
  let q = supabase.from('suspel_bodegas').select('*')
  if (activo !== undefined) q = q.eq('activo', activo)
  const { data, error } = await q.order('nombre')
  return { data: data as SuspelBodega[] | null, error }
}

export async function getRespelTipos() {
  const { data, error } = await supabase
    .from('respel_tipos')
    .select('*')
    .eq('es_activo', true)
    .order('nombre')
  return { data: data as RespelTipo[] | null, error }
}

export async function getRespelMovimientos(limit = 100) {
  const { data, error } = await supabase
    .from('respel_movimientos')
    .select('*, respel_tipo:respel_tipos(*), empresa_receptora:respel_empresas_receptoras(nombre, rut)')
    .order('fecha', { ascending: false })
    .limit(limit)
  return { data: data as RespelMovimiento[] | null, error }
}

export async function createRespelMovimiento(mov: {
  tipo_movimiento: 'generacion' | 'retiro' | 'almacenamiento' | 'correccion'
  fecha: string
  respel_tipo_id: string
  cantidad: number
  unidad?: string
  bodega_id?: string
  activo_origen_id?: string
  faena_id?: string
  ot_id?: string
  empresa_receptora_id?: string
  numero_sidrep?: string
  observaciones?: string
}) {
  const { data, error } = await supabase
    .from('respel_movimientos')
    .insert(mov)
    .select()
    .single()
  return { data, error }
}

export async function getRespelEmpresas() {
  const { data, error } = await supabase
    .from('respel_empresas_receptoras')
    .select('*')
    .eq('activo', true)
    .order('nombre')
  return { data: data as RespelEmpresa[] | null, error }
}

export async function getCertificacionesProximasVencer(diasAdelante = 60) {
  const hoy = new Date().toISOString().split('T')[0]
  const limite = new Date()
  limite.setDate(limite.getDate() + diasAdelante)
  const limiteStr = limite.toISOString().split('T')[0]

  const { data, error } = await supabase
    .from('certificaciones')
    .select('*, activo:activos(patente, codigo, nombre)')
    .gte('fecha_vencimiento', hoy)
    .lte('fecha_vencimiento', limiteStr)
    .order('fecha_vencimiento', { ascending: true })
  return { data, error }
}

export async function getCertificacionesBloqueantes() {
  const { data, error } = await supabase
    .from('certificaciones')
    .select('*, activo:activos(patente, codigo, nombre)')
    .eq('bloqueante', true)
    .order('fecha_vencimiento', { ascending: true })
  return { data, error }
}
