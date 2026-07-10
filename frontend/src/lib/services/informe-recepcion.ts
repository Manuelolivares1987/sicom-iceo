import { supabase } from '@/lib/supabase'

export type EstadoInformeRecepcion = 'en_inspeccion' | 'borrador' | 'emitido' | 'cancelado'
export type GravedadHallazgo = 'menor' | 'mayor' | 'critica'
export type TipoCostoRecepcion = 'repuesto' | 'mano_obra' | 'servicio_externo' | 'otro'

export interface InformeRecepcion {
  id: string
  folio: string | null
  activo_id: string
  contrato_id: string | null
  cliente_nombre: string | null
  fecha_entrega_arriendo: string | null
  fecha_recepcion: string
  ot_inspeccion_id: string | null
  ot_correctiva_id: string | null
  verificacion_entrega_id: string | null
  inspector_id: string | null
  inspector_firma_url: string | null
  encargado_cobros_id: string | null
  encargado_firma_url: string | null
  estado: EstadoInformeRecepcion
  subtotal_neto: number
  iva: number
  total: number
  total_no_cobrable: number
  total_cobrable_cliente: number
  pdf_url: string | null
  observaciones_finales: string | null
  emitido_en: string | null
  created_at: string
  updated_at: string
}

export interface InformeHallazgo {
  id: string
  informe_id: string
  checklist_item_id: string | null
  seccion: string | null
  descripcion: string
  gravedad: GravedadHallazgo
  atribuible_cliente: boolean
  fotos: string[]
  observacion: string | null
  created_at: string
}

export interface InformeCosto {
  id: string
  informe_id: string
  tipo: TipoCostoRecepcion
  producto_id: string | null
  tarifa_hh_id: string | null
  descripcion: string
  cantidad: number
  unidad: string | null
  precio_unitario: number
  total: number
  cobrable_cliente: boolean
  hallazgo_id: string | null
  editado_por: string | null
  editado_en: string | null
  created_at: string
}

export interface TarifaHH {
  id: string
  codigo: string
  nombre: string
  tarifa_clp: number
  activo: boolean
}

export interface InformeRecepcionListItem {
  id: string
  folio: string
  estado: EstadoInformeRecepcion
  activo_id: string
  patente: string | null
  activo_codigo: string | null
  activo_nombre: string | null
  cliente_nombre: string | null
  fecha_recepcion: string
  fecha_entrega_arriendo: string | null
  total: number
  total_cobrable_cliente: number
  total_no_cobrable: number
  inspector_id: string | null
  inspector_nombre: string | null
  encargado_cobros_id: string | null
  encargado_nombre: string | null
  emitido_en: string | null
  pdf_url: string | null
  n_hallazgos: number
  n_atrib_cliente: number
  n_costos: number
  created_at: string
}

// ── RPCs ─────────────────────────────────────────────────

export async function iniciarInformeRecepcion(activoId: string, motivo?: string) {
  const { data, error } = await supabase.rpc('fn_iniciar_informe_recepcion', {
    p_activo_id: activoId,
    p_motivo: motivo ?? null,
  })
  return {
    data: data as {
      success: boolean
      informe_id: string
      ot_id: string
      ot_folio: string
      informe_folio: string
      patente: string | null
    } | null,
    error,
  }
}

export async function cerrarInspeccionRecepcion(
  informeId: string,
  firmaTecnicoUrl: string,
) {
  const { data, error } = await supabase.rpc('fn_cerrar_inspeccion_recepcion', {
    p_informe_id: informeId,
    p_firma_tecnico_url: firmaTecnicoUrl,
  })
  return { data, error }
}

/** Vuelca TODOS los ítems NO OK del checklist del informe como hallazgos de
 *  recobro (idempotente — no duplica los ya volcados). MIG214. */
export async function generarHallazgosDesdeChecklist(informeId: string): Promise<{
  creados: number; ya_existian: number; total_no_ok: number; mensaje?: string
}> {
  const { data, error } = await supabase.rpc('fn_generar_hallazgos_desde_checklist', {
    p_informe_id: informeId,
  })
  if (error) throw error
  return data as any
}

// Cierre parcial del día: genera las NC evaluadas hasta ahora (idempotente),
// sin cerrar el informe. Para inspecciones de recepción que duran varios días.
export async function cierreParcialRecepcion(informeId: string, observacion?: string) {
  const { data, error } = await supabase.rpc('fn_cierre_parcial_recepcion', {
    p_informe_id: informeId,
    p_observacion: observacion ?? null,
  })
  return { data, error }
}

export async function emitirInformeRecepcion(args: {
  informeId: string
  firmaEncargadoUrl: string
  pdfUrl: string
  observaciones?: string
}) {
  const { data, error } = await supabase.rpc('fn_emitir_informe_recepcion', {
    p_informe_id: args.informeId,
    p_firma_encargado_url: args.firmaEncargadoUrl,
    p_pdf_url: args.pdfUrl,
    p_observaciones: args.observaciones ?? null,
  })
  return { data, error }
}

// ── Lectura ──────────────────────────────────────────────

export async function getInformeRecepcion(id: string) {
  const { data, error } = await supabase
    .from('informes_recepcion')
    .select('*')
    .eq('id', id)
    .single()
  return { data: data as InformeRecepcion | null, error }
}

/** Informe + equipo + nombres de firmantes, para la versión imprimible. */
export type InformeRecepcionCompleto = InformeRecepcion & {
  activo: {
    codigo: string; nombre: string | null; patente: string | null
    modelo?: { nombre: string; marca?: { nombre: string } | null } | null
  } | null
  inspector: { nombre_completo: string } | null
  encargado: { nombre_completo: string } | null
}

export async function getInformeRecepcionCompleto(id: string): Promise<InformeRecepcionCompleto | null> {
  const { data, error } = await supabase
    .from('informes_recepcion')
    .select(`*,
      activo:activos(codigo, nombre, patente, modelo:modelos(nombre, marca:marcas(nombre))),
      inspector:usuarios_perfil!inspector_id(nombre_completo),
      encargado:usuarios_perfil!encargado_cobros_id(nombre_completo)`)
    .eq('id', id)
    .maybeSingle()
  if (error) throw error
  return (data as unknown as InformeRecepcionCompleto | null) ?? null
}

/** Informes del equipo — para la carpeta en la ficha del activo. */
export async function getInformesRecepcionActivo(activoId: string): Promise<InformeRecepcion[]> {
  const { data, error } = await supabase
    .from('informes_recepcion')
    .select('*')
    .eq('activo_id', activoId)
    .order('created_at', { ascending: false })
  if (error) throw error
  return (data ?? []) as InformeRecepcion[]
}

export async function getHallazgosInforme(informeId: string) {
  const { data, error } = await supabase
    .from('informe_recepcion_hallazgos')
    .select('*')
    .eq('informe_id', informeId)
    .order('created_at')
  return { data: data as InformeHallazgo[] | null, error }
}

export async function getCostosInforme(informeId: string) {
  const { data, error } = await supabase
    .from('informe_recepcion_costos')
    .select('*')
    .eq('informe_id', informeId)
    .order('created_at')
  return { data: data as InformeCosto[] | null, error }
}

export async function getInformesRecepcionLista(estado?: EstadoInformeRecepcion) {
  let q = supabase.from('v_informes_recepcion_lista').select('*')
  if (estado) q = q.eq('estado', estado)
  const { data, error } = await q.order('created_at', { ascending: false })
  return { data: data as InformeRecepcionListItem[] | null, error }
}

export async function getTarifasHH() {
  const { data, error } = await supabase
    .from('tarifas_hh')
    .select('*')
    .eq('activo', true)
    .order('nombre')
  return { data: data as TarifaHH[] | null, error }
}

// ── Mutaciones directas (no RPC) ─────────────────────────

export async function agregarHallazgo(payload: {
  informe_id: string
  seccion?: string | null
  descripcion: string
  gravedad?: GravedadHallazgo
  atribuible_cliente?: boolean
  fotos?: string[]
  observacion?: string | null
  checklist_item_id?: string | null
}) {
  const { data, error } = await supabase
    .from('informe_recepcion_hallazgos')
    .insert({
      ...payload,
      fotos: payload.fotos ?? [],
      gravedad: payload.gravedad ?? 'menor',
      atribuible_cliente: payload.atribuible_cliente ?? true,
    })
    .select()
    .single()
  return { data, error }
}

export async function actualizarHallazgo(id: string, patch: Partial<InformeHallazgo>) {
  const { data, error } = await supabase
    .from('informe_recepcion_hallazgos')
    .update(patch)
    .eq('id', id)
    .select()
    .single()
  return { data, error }
}

export async function eliminarHallazgo(id: string) {
  const { error } = await supabase.from('informe_recepcion_hallazgos').delete().eq('id', id)
  return { error }
}

export async function agregarCosto(payload: {
  informe_id: string
  tipo: TipoCostoRecepcion
  descripcion: string
  cantidad: number
  unidad?: string | null
  precio_unitario: number
  producto_id?: string | null
  tarifa_hh_id?: string | null
  cobrable_cliente?: boolean
  hallazgo_id?: string | null
}) {
  const { data, error } = await supabase
    .from('informe_recepcion_costos')
    .insert({
      ...payload,
      cobrable_cliente: payload.cobrable_cliente ?? true,
    })
    .select()
    .single()
  return { data, error }
}

export async function actualizarCosto(id: string, patch: Partial<InformeCosto>) {
  const { data, error } = await supabase
    .from('informe_recepcion_costos')
    .update({ ...patch, editado_en: new Date().toISOString() })
    .eq('id', id)
    .select()
    .single()
  return { data, error }
}

export async function eliminarCosto(id: string) {
  const { error } = await supabase.from('informe_recepcion_costos').delete().eq('id', id)
  return { error }
}

// ── Storage: fotos y firmas ──────────────────────────────

export const BUCKET = 'evidencias-verificacion'

export async function subirFotoHallazgo(informeId: string, hallazgoId: string, file: File | Blob) {
  const ext = file instanceof File ? file.name.split('.').pop() || 'jpg' : 'png'
  const path = `recepcion/${informeId}/hallazgos/${hallazgoId}-${Date.now()}.${ext}`
  const { error: upErr } = await supabase.storage
    .from(BUCKET)
    .upload(path, file, { upsert: false, contentType: (file as File).type || 'image/jpeg' })
  if (upErr) return { data: null, error: upErr }
  const { data } = supabase.storage.from(BUCKET).getPublicUrl(path)
  return { data: data.publicUrl, error: null }
}

export async function subirFirmaInforme(
  informeId: string,
  quien: 'tecnico' | 'encargado',
  dataUrl: string,
) {
  const res = await fetch(dataUrl)
  const blob = await res.blob()
  const path = `recepcion/${informeId}/firma-${quien}.png`
  const { error: upErr } = await supabase.storage
    .from(BUCKET)
    .upload(path, blob, { upsert: true, contentType: 'image/png' })
  if (upErr) return { data: null, error: upErr }
  const { data } = supabase.storage.from(BUCKET).getPublicUrl(path)
  return { data: data.publicUrl, error: null }
}
