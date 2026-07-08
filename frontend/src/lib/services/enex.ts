// Módulo Calama-ENEX (MIG206) — control + KPI de cumplimiento del contrato de
// mantención de instalaciones de combustibles/lubricantes ENEX/ESM.
import { supabase } from '@/lib/supabase'

export type EnexFaena = {
  id: string
  codigo: string
  nombre: string
  cliente_minero: string | null
  contrato_minero: string | null
  operador: string | null
  lineas: string[] | null
  vigencia_hasta: string | null
  facturacion_mensual_clp: number
  pct_facturacion: number | null
  activo: boolean
  orden: number
}

export type EnexInstalacion = {
  id: string
  faena_id: string
  codigo: string | null
  nombre: string
  tipo: 'eess' | 'petrolera' | 'semimovil' | 'truck_shop' | 'camion' | 'otro'
  linea: 'combustible' | 'lubricante' | null
  pauta: string | null
  frecuencia_meses: number
  patente: string | null
  activo: boolean
  orden: number
}

export type TipoServicio = 'mantencion' | 'calibracion'

export type EnexPanelRow = {
  programacion_id: string
  periodo_anio: number
  periodo_mes: number
  tipo_servicio: TipoServicio
  fecha_programada: string | null
  prog_observacion: string | null
  instalacion_id: string
  instalacion: string
  instalacion_tipo: string
  instalacion_codigo: string | null
  linea: string | null
  patente: string | null
  faena_id: string
  faena_codigo: string
  faena: string
  ejecucion_id: string | null
  estado: 'ejecutada' | 'cumplida' | 'no_realizada' | null
  fecha_ejecucion: string | null
  ot_numero: string | null
  ejecutor: string | null
  ejec_observacion: string | null
  evidencia_urls: string[] | null
  firma_mandante_url: string | null
  firmante_mandante_nombre: string | null
  firmante_mandante_at: string | null
  cumplida: boolean
}

export type EnexKpi = {
  faena_id: string
  faena_codigo: string
  faena: string
  facturacion_mensual_clp: number
  periodo_anio: number
  periodo_mes: number
  programadas: number
  cumplidas: number
  cumplimiento_pct: number | null
  tramo_multa_pct: number
  monto_riesgo_clp: number
  en_revision_continuidad: boolean
}

export const TIPO_INSTALACION_LABEL: Record<string, string> = {
  eess: 'EESS', petrolera: 'Petrolera', semimovil: 'Semimóvil',
  truck_shop: 'Truck Shop', camion: 'Camión', otro: 'Otro',
}

// ── Catálogo ──────────────────────────────────────────────────────────────
export async function getFaenas(): Promise<EnexFaena[]> {
  const { data, error } = await supabase.from('enex_faenas').select('*').eq('activo', true).order('orden')
  if (error) throw error
  return (data ?? []) as EnexFaena[]
}

export async function getInstalaciones(faenaId?: string): Promise<EnexInstalacion[]> {
  let q = supabase.from('enex_instalaciones').select('*').eq('activo', true).order('orden')
  if (faenaId) q = q.eq('faena_id', faenaId)
  const { data, error } = await q
  if (error) throw error
  return (data ?? []) as EnexInstalacion[]
}

export async function crearInstalacion(p: {
  faenaId: string; nombre: string; tipo: EnexInstalacion['tipo']
  linea?: string | null; codigo?: string | null; patente?: string | null; frecuenciaMeses?: number
}) {
  const { data, error } = await supabase.from('enex_instalaciones').insert({
    faena_id: p.faenaId, nombre: p.nombre, tipo: p.tipo, linea: p.linea ?? null,
    codigo: p.codigo ?? null, patente: p.patente ?? null, frecuencia_meses: p.frecuenciaMeses ?? 3,
  }).select('id').single()
  if (error) throw error
  return data
}

// ── Panel mensual + KPI ───────────────────────────────────────────────────
export async function getPanelMensual(anio: number, mes: number, faenaId?: string): Promise<EnexPanelRow[]> {
  let q = supabase.from('v_enex_panel_mensual').select('*')
    .eq('periodo_anio', anio).eq('periodo_mes', mes)
  if (faenaId) q = q.eq('faena_id', faenaId)
  const { data, error } = await q
  if (error) throw error
  return (data ?? []) as EnexPanelRow[]
}

export async function getKpiMensual(anio: number, mes: number): Promise<EnexKpi[]> {
  const { data, error } = await supabase.from('v_enex_kpi_mensual').select('*')
    .eq('periodo_anio', anio).eq('periodo_mes', mes)
  if (error) throw error
  return (data ?? []) as EnexKpi[]
}

// ── Acciones ──────────────────────────────────────────────────────────────
export async function programar(p: {
  instalacionId: string; tipoServicio: TipoServicio; anio: number; mes: number
  fecha?: string | null; observacion?: string | null
}) {
  const { data, error } = await supabase.rpc('rpc_enex_programar', {
    p_instalacion_id: p.instalacionId, p_tipo_servicio: p.tipoServicio,
    p_anio: p.anio, p_mes: p.mes, p_fecha: p.fecha ?? null, p_observacion: p.observacion ?? null,
  })
  if (error) throw error
  return data as { success: boolean; programacion_id: string }
}

export async function desprogramar(programacionId: string) {
  const { error } = await supabase.rpc('rpc_enex_desprogramar', { p_programacion_id: programacionId })
  if (error) throw error
}

export async function registrarEjecucion(p: {
  programacionId: string; fecha?: string | null; otNumero?: string | null; ejecutor?: string | null
  observacion?: string | null; evidenciaUrls?: string[] | null
  firmaMandanteUrl?: string | null; firmanteMandante?: string | null
}) {
  const { data, error } = await supabase.rpc('rpc_enex_registrar_ejecucion', {
    p_programacion_id: p.programacionId, p_fecha: p.fecha ?? null, p_ot_numero: p.otNumero ?? null,
    p_ejecutor: p.ejecutor ?? null, p_observacion: p.observacion ?? null,
    p_evidencia_urls: p.evidenciaUrls ?? null,
    p_firma_mandante_url: p.firmaMandanteUrl ?? null, p_firmante_mandante: p.firmanteMandante ?? null,
  })
  if (error) throw error
  return data as { success: boolean; estado: string; cumplida: boolean }
}

export async function duplicarPeriodo(anioOrigen: number, mesOrigen: number, anioDest: number, mesDest: number) {
  const { data, error } = await supabase.rpc('rpc_enex_duplicar_periodo', {
    p_anio_origen: anioOrigen, p_mes_origen: mesOrigen, p_anio_dest: anioDest, p_mes_dest: mesDest,
  })
  if (error) throw error
  return data as { success: boolean; copiadas: number }
}

// Firma del mandante / evidencias → buckets públicos existentes
export async function subirFirmaMandante(dataUrl: string): Promise<string> {
  const bin = dataUrl.split(',')[1]
  const bytes = Uint8Array.from(atob(bin), (c) => c.charCodeAt(0))
  const path = `enex-firmas/${Date.now()}_${Math.floor(Math.random() * 1e6)}.png`
  const { error } = await supabase.storage.from('calama-firmas').upload(path, bytes, { contentType: 'image/png' })
  if (error) throw error
  return supabase.storage.from('calama-firmas').getPublicUrl(path).data.publicUrl
}

export async function subirEvidenciaEnex(file: File): Promise<string> {
  const ext = file.name.split('.').pop()?.toLowerCase() ?? 'jpg'
  const path = `enex/${Date.now()}_${Math.floor(Math.random() * 1e6)}.${ext}`
  const { error } = await supabase.storage.from('evidencias-verificacion').upload(path, file, {
    contentType: file.type || 'image/jpeg',
  })
  if (error) throw error
  return supabase.storage.from('evidencias-verificacion').getPublicUrl(path).data.publicUrl
}

// ── Pautas (checklists) — motor MIG207 ────────────────────────────────────
export type TipoCampo = 'ok_nook' | 'medicion' | 'si_no' | 'texto'
export type Periodicidad = 'trimestral' | 'mensual' | 'anual' | 'semestral' | 'requerimiento'

export type EnexPauta = {
  id: string
  codigo: string
  nombre: string
  tipo_servicio: TipoServicio
  aplica_tipos: string[]
  linea: string | null
  version: number
  es_borrador: boolean
  activo: boolean
}
export type EnexPautaItem = {
  id: string
  pauta_id: string
  bloque: string
  bloque_orden: number
  orden: number
  codigo: string | null
  descripcion: string
  periodicidad: Periodicidad
  tipo_campo: TipoCampo
  unidad: string | null
  valor_referencia: number | null
  tolerancia_min: number | null
  tolerancia_max: number | null
  requiere_foto: boolean
  obligatorio: boolean
  activo: boolean
}

export const TIPO_CAMPO_LABEL: Record<TipoCampo, string> = {
  ok_nook: 'OK / NO OK', medicion: 'Medición (valor)', si_no: 'Sí / No', texto: 'Texto libre',
}

export async function getPautas(): Promise<EnexPauta[]> {
  const { data, error } = await supabase.from('enex_pautas').select('*').eq('activo', true).order('tipo_servicio').order('codigo')
  if (error) throw error
  return (data ?? []) as EnexPauta[]
}
export async function getPautaItems(pautaId: string): Promise<EnexPautaItem[]> {
  const { data, error } = await supabase.from('enex_pauta_items').select('*')
    .eq('pauta_id', pautaId).eq('activo', true).order('bloque_orden').order('orden')
  if (error) throw error
  return (data ?? []) as EnexPautaItem[]
}
export async function guardarPauta(p: {
  id?: string | null; codigo: string; nombre: string; tipoServicio: TipoServicio
  aplicaTipos: string[]; linea?: string | null; esBorrador?: boolean
}) {
  const { data, error } = await supabase.rpc('rpc_enex_pauta_guardar', {
    p_id: p.id ?? null, p_codigo: p.codigo, p_nombre: p.nombre, p_tipo_servicio: p.tipoServicio,
    p_aplica_tipos: p.aplicaTipos, p_linea: p.linea ?? null, p_es_borrador: p.esBorrador ?? true,
  })
  if (error) throw error
  return data as { success: boolean; pauta_id: string }
}
export async function guardarPautaItem(p: {
  id?: string | null; pautaId: string; bloque: string; bloqueOrden: number; orden: number
  codigo?: string | null; descripcion: string; periodicidad: Periodicidad; tipoCampo: TipoCampo
  unidad?: string | null; valorReferencia?: number | null; toleranciaMin?: number | null
  toleranciaMax?: number | null; requiereFoto?: boolean; obligatorio?: boolean
}) {
  const { data, error } = await supabase.rpc('rpc_enex_pauta_item_guardar', {
    p_id: p.id ?? null, p_pauta_id: p.pautaId, p_bloque: p.bloque, p_bloque_orden: p.bloqueOrden,
    p_orden: p.orden, p_codigo: p.codigo ?? null, p_descripcion: p.descripcion,
    p_periodicidad: p.periodicidad, p_tipo_campo: p.tipoCampo, p_unidad: p.unidad ?? null,
    p_valor_referencia: p.valorReferencia ?? null, p_tolerancia_min: p.toleranciaMin ?? null,
    p_tolerancia_max: p.toleranciaMax ?? null, p_requiere_foto: p.requiereFoto ?? false,
    p_obligatorio: p.obligatorio ?? true,
  })
  if (error) throw error
  return data as { success: boolean; item_id: string }
}
export async function eliminarPautaItem(itemId: string) {
  const { error } = await supabase.rpc('rpc_enex_pauta_item_eliminar', { p_item_id: itemId })
  if (error) throw error
}

export const MESES = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
  'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre']
export const clp = (n: number | null | undefined) =>
  '$' + Math.round(Number(n || 0)).toLocaleString('es-CL')
