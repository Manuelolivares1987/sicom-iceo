import { supabase } from '@/lib/supabase'

/** Bucket existente para fotos de verificacion/recepcion (MIG46). */
export const CHECKLIST_BUCKET_FOTOS  = 'evidencias-verificacion'
export const CHECKLIST_BUCKET_FIRMAS = 'calama-firmas'

export type MomentoChecklist =
  | 'entrega_arriendo'
  | 'recepcion_devolucion'
  | 'ready_to_rent'
  | 'preventiva'

export type TipoEquipamiento =
  | 'aljibe_agua' | 'aljibe_combustible' | 'pluma_grua' | 'ampliroll'
  | 'grua_horquilla' | 'camioneta' | 'tracto' | 'generico'

export type ResultadoItem = 'ok' | 'no_ok' | 'na' | 'pendiente'

export type EstadoInstance = 'en_progreso' | 'cerrado' | 'anulado'

export type BloqueChecklist =
  | 'b1_documentacion'
  | 'b2_estado_exterior'
  | 'b3_motor_niveles'
  | 'b_sistema_electrico'
  | 'b_fugas'
  | 'b4_sistema_equipo'
  | 'b5_seguridad_activa'
  | 'b6_diagnostico_electronico'
  | 'b_inventario_seguridad'
  | 'b_kit_invierno'
  | 'b_pruebas_operativas'
  | 'b7_cierre_recepcion'
  | 'a_trabajos_ot'
  | 'b_pruebas_funcionales'
  | 'c_estado_entrega'
  | 'd_cierre_entrega'

export type InstrumentoMedicion =
  | 'check' | 'visual' | 'numerico' | 'manometro' | 'caudalimetro'
  | 'profundimetro' | 'termometro' | 'multimetro' | 'scanner_obd'
  | 'muestra_lab' | 'foto' | 'firma'

export type DefaultCobrable = 'cliente' | 'empresa' | 'compartido' | 'evaluar' | 'na'

/** Tipo de prueba operativa (solo bloque Pruebas operativas). */
export type PruebaTipo = 'ruta' | 'recirculacion' | 'regadio'

export type CategoriaCalidad = 'tecnica' | 'documentacion'

export const BLOQUE_LABELS: Record<BloqueChecklist, string> = {
  b1_documentacion:          'B1. Documentación y certificaciones',
  b2_estado_exterior:        'B2. Estado exterior y cabina',
  b3_motor_niveles:          'B3. Motor y niveles',
  b_sistema_electrico:       'B4. Sistema eléctrico',
  b_fugas:                   'B5. Revisión de fugas por componente',
  b4_sistema_equipo:         'B6. Sistemas específicos del equipamiento',
  b5_seguridad_activa:       'B7. Seguridad activa',
  b6_diagnostico_electronico:'B8. Diagnóstico electrónico',
  b_inventario_seguridad:    'B9. Inventario y elementos de seguridad',
  b_kit_invierno:            'B10. Kit de invierno (opcional)',
  b_pruebas_operativas:      'Pruebas operativas (ruta / recirculación / regadío)',
  b7_cierre_recepcion:       'B11. Cierre y responsabilidades',
  a_trabajos_ot:             'A. Trabajos OT',
  b_pruebas_funcionales:     'B. Pruebas funcionales',
  c_estado_entrega:          'C. Estado entrega',
  d_cierre_entrega:          'D. Cierre',
}

export const PRUEBA_LABELS: Record<PruebaTipo, string> = {
  ruta:          'Ruta',
  recirculacion: 'Recirculación',
  regadio:       'Regadío',
}

export type ChecklistV2Item = {
  id: string                          // instance_item.id
  template_item_id: string
  bloque: BloqueChecklist
  orden: number
  codigo: string
  descripcion: string
  ayuda: string | null
  instrumento: InstrumentoMedicion
  unidad: string | null
  rango_min: number | null
  rango_max: number | null
  obligatorio: boolean
  requiere_foto: boolean
  default_cobrable: DefaultCobrable
  costo_referencial_clp: number | null
  bloque_orden: number
  tiempo_min: number | null
  prueba_tipo: PruebaTipo | null
  categoria_calidad: CategoriaCalidad
  // Estado actual del instance_item
  resultado: ResultadoItem
  valor_numerico: number | null
  observacion: string | null
  foto_url: string | null
  cobrable_override: DefaultCobrable | null
  costo_estimado: number | null
}

export type ChecklistV2Instance = {
  id: string
  template_id: string
  momento_uso: MomentoChecklist
  activo_id: string
  contrato_id: string | null
  fecha_inicio: string
  fecha_cierre: string | null
  estado: EstadoInstance
  horometro: number | null
  kilometraje: number | null
  firma_operador_url: string | null
  firma_cliente_url: string | null
  observaciones: string | null
}

/** Crea (o devuelve existente) instance de entrega para un activo. */
export async function iniciarChecklistEntrega(params: {
  activoId: string
  contratoId?: string | null
  horometro?: number | null
  kilometraje?: number | null
  operadorId?: string | null
}): Promise<{ instanceId: string }> {
  // 1. Buscar instance abierto
  const { data: existente, error: e1 } = await supabase
    .from('checklist_v2_instance')
    .select('id')
    .eq('activo_id', params.activoId)
    .eq('momento_uso', 'entrega_arriendo')
    .eq('estado', 'en_progreso')
    .maybeSingle()
  if (e1) throw e1
  if (existente?.id) return { instanceId: existente.id }

  // 2. Resolver template activo
  const { data: tpl, error: e2 } = await supabase
    .from('checklist_template_v2')
    .select('id')
    .eq('momento_uso', 'entrega_arriendo')
    .eq('activo', true)
    .single()
  if (e2 || !tpl) throw e2 ?? new Error('Sin template entrega activo')

  // 3. RPC inicializar
  const { data, error } = await supabase.rpc('fn_inicializar_checklist_v2', {
    p_template_id: tpl.id,
    p_activo_id:   params.activoId,
    p_contrato_id: params.contratoId ?? null,
    p_operador_id: params.operadorId ?? null,
    p_horometro:   params.horometro  ?? null,
    p_kilometraje: params.kilometraje ?? null,
    p_informe_id:  null,
    p_entrega_ref: null,
  })
  if (error) throw error
  return { instanceId: data as string }
}

export async function cargarInstance(instanceId: string): Promise<ChecklistV2Instance> {
  const { data, error } = await supabase
    .from('checklist_v2_instance')
    .select('*')
    .eq('id', instanceId)
    .single()
  if (error) throw error
  return data as ChecklistV2Instance
}

export async function cargarItemsInstance(instanceId: string): Promise<ChecklistV2Item[]> {
  const { data, error } = await supabase
    .from('checklist_v2_instance_item')
    .select(`
      id, template_item_id, resultado, valor_numerico, observacion, foto_url,
      cobrable_override, costo_estimado,
      template:checklist_template_v2_item!template_item_id (
        bloque, orden, codigo, descripcion, ayuda, instrumento, unidad,
        rango_min, rango_max, obligatorio, requiere_foto, default_cobrable,
        costo_referencial_clp, bloque_orden, tiempo_min, prueba_tipo, categoria_calidad
      )
    `)
    .eq('instance_id', instanceId)
  if (error) throw error
  type Row = {
    id: string
    template_item_id: string
    resultado: ResultadoItem
    valor_numerico: number | null
    observacion: string | null
    foto_url: string | null
    cobrable_override: DefaultCobrable | null
    costo_estimado: number | null
    template: Record<string, unknown>
  }
  return (data as unknown as Row[]).map((r) => ({
    id:                r.id,
    template_item_id:  r.template_item_id,
    bloque:            r.template.bloque as BloqueChecklist,
    orden:             r.template.orden as number,
    codigo:            r.template.codigo as string,
    descripcion:       r.template.descripcion as string,
    ayuda:             (r.template.ayuda as string | null) ?? null,
    instrumento:       r.template.instrumento as InstrumentoMedicion,
    unidad:            (r.template.unidad as string | null) ?? null,
    rango_min:         (r.template.rango_min as number | null) ?? null,
    rango_max:         (r.template.rango_max as number | null) ?? null,
    obligatorio:       Boolean(r.template.obligatorio),
    requiere_foto:     Boolean(r.template.requiere_foto),
    default_cobrable:  r.template.default_cobrable as DefaultCobrable,
    costo_referencial_clp: (r.template.costo_referencial_clp as number | null) ?? null,
    bloque_orden:      (r.template.bloque_orden as number | null) ?? 99,
    tiempo_min:        (r.template.tiempo_min as number | null) ?? null,
    prueba_tipo:       (r.template.prueba_tipo as PruebaTipo | null) ?? null,
    categoria_calidad: (r.template.categoria_calidad as CategoriaCalidad | null) ?? 'tecnica',
    resultado:         r.resultado,
    valor_numerico:    r.valor_numerico,
    observacion:       r.observacion,
    foto_url:          r.foto_url,
    cobrable_override: r.cobrable_override,
    costo_estimado:    r.costo_estimado,
  })).sort((a, b) => (a.bloque_orden - b.bloque_orden) || (a.orden - b.orden))
}

export async function actualizarItem(itemId: string, patch: Partial<ChecklistV2Item>) {
  const allowed: Partial<Record<keyof ChecklistV2Item, unknown>> = {
    resultado:         patch.resultado,
    valor_numerico:    patch.valor_numerico,
    observacion:       patch.observacion,
    foto_url:          patch.foto_url,
    cobrable_override: patch.cobrable_override,
    costo_estimado:    patch.costo_estimado,
  }
  const body: Record<string, unknown> = { respondido_at: new Date().toISOString() }
  for (const [k, v] of Object.entries(allowed)) if (v !== undefined) body[k] = v
  const { error } = await supabase
    .from('checklist_v2_instance_item')
    .update(body)
    .eq('id', itemId)
  if (error) throw error
}

export async function subirFotoItem(
  instanceId: string,
  itemId: string,
  file: File | Blob,
): Promise<string> {
  const ext  = (file as File).name?.split('.').pop()?.toLowerCase() ?? 'jpg'
  const path = `checklist-v2/${instanceId}/${itemId}_${Date.now()}.${ext}`
  const { error } = await supabase.storage
    .from(CHECKLIST_BUCKET_FOTOS)
    .upload(path, file, { upsert: false, contentType: (file as File).type || 'image/jpeg' })
  if (error) throw error
  const { data } = supabase.storage.from(CHECKLIST_BUCKET_FOTOS).getPublicUrl(path)
  return data.publicUrl
}

export async function subirFirma(
  instanceId: string,
  tipo: 'operador' | 'cliente',
  blob: Blob,
): Promise<string> {
  const path = `checklist-v2-firmas/${instanceId}/${tipo}_${Date.now()}.png`
  const { error } = await supabase.storage
    .from(CHECKLIST_BUCKET_FIRMAS)
    .upload(path, blob, { upsert: false, contentType: 'image/png' })
  if (error) throw error
  const { data } = supabase.storage.from(CHECKLIST_BUCKET_FIRMAS).getPublicUrl(path)
  return data.publicUrl
}

export async function cerrarChecklist(params: {
  instanceId: string
  firmaOperadorUrl: string
  firmaClienteUrl: string
  operadorRut?: string
  operadorNombre?: string
  clienteRut?: string
  clienteNombre?: string
}): Promise<void> {
  const { error } = await supabase.rpc('rpc_cerrar_checklist_v2', {
    p_instance_id:        params.instanceId,
    p_firma_operador_url: params.firmaOperadorUrl,
    p_firma_cliente_url:  params.firmaClienteUrl,
    p_operador_rut:       params.operadorRut    ?? null,
    p_operador_nombre:    params.operadorNombre ?? null,
    p_cliente_rut:        params.clienteRut     ?? null,
    p_cliente_nombre:     params.clienteNombre  ?? null,
  })
  if (error) throw error
}

// ====== Recepcion / Comparacion ============================================

/** Busca el checklist V02 recepcion vinculado a un informe_recepcion. */
export async function buscarInstanceRecepcionPorInforme(
  informeId: string,
): Promise<ChecklistV2Instance | null> {
  const { data, error } = await supabase
    .from('checklist_v2_instance')
    .select('*')
    .eq('informe_recepcion_id', informeId)
    .eq('momento_uso', 'recepcion_devolucion')
    .order('fecha_inicio', { ascending: false })
    .limit(1)
    .maybeSingle()
  if (error) throw error
  return (data as ChecklistV2Instance | null) ?? null
}

export type DiffItem = {
  template_item_id:    string
  codigo_item:         string
  bloque:              BloqueChecklist
  descripcion:         string
  resultado_entrega:   ResultadoItem | null
  resultado_recepcion: ResultadoItem
  valor_entrega:       number | null
  valor_recepcion:     number | null
  delta_valor:         number | null
  foto_entrega_url:    string | null
  foto_recepcion_url:  string | null
  default_cobrable:    DefaultCobrable
  cobrable_final:      DefaultCobrable
  costo_referencial:   number | null
  costo_estimado_real: number | null
  es_hallazgo_nuevo:   boolean
}

export async function compararChecklists(recepcionInstanceId: string): Promise<DiffItem[]> {
  const { data, error } = await supabase.rpc('fn_comparar_checklists_entrega_recepcion', {
    p_recepcion_id: recepcionInstanceId,
  })
  if (error) throw error
  return (data ?? []) as DiffItem[]
}

export async function aplicarDiffAInforme(recepcionInstanceId: string): Promise<{
  ok: boolean; informe_id: string; hallazgos_insertados: number
}> {
  const { data, error } = await supabase.rpc('rpc_aplicar_diff_a_informe', {
    p_recepcion_id: recepcionInstanceId,
  })
  if (error) throw error
  return data as { ok: boolean; informe_id: string; hallazgos_insertados: number }
}
