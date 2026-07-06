import { supabase } from '@/lib/supabase'

// ============================================================================
// Informe técnico de intervención (Incremento 1 · MIG 191)
// ----------------------------------------------------------------------------
// Servicio de FRONTEND. La escritura pasa SIEMPRE por RPCs SECURITY DEFINER
// (fail-closed en el servidor). El bucket de PDFs es PRIVADO: para visualizar
// se usa createSignedUrl (NO getPublicUrl).
// ============================================================================

export type EstadoInformeIntervencion =
  | 'borrador'
  | 'pendiente_revision'
  | 'observado'
  | 'aprobado'
  | 'cerrado'
  | 'anulado'

export type EstadoTrabajoInforme =
  | 'pendiente'
  | 'en_ejecucion'
  | 'realizado'
  | 'realizado_parcial'
  | 'no_realizado'
  | 'no_aplica'

export interface InformeIntervencion {
  id: string
  folio: string
  ot_id: string
  activo_id: string
  checklist_instance_id: string | null
  plan_semanal_id: string | null
  version: number
  informe_anterior_id: string | null
  es_version_vigente: boolean
  estado: EstadoInformeIntervencion
  tipo_intervencion: string | null
  motivo_ingreso: string | null
  condicion_ingreso: string | null
  diagnostico_resumen: string | null
  trabajo_planificado_resumen: string | null
  trabajo_realizado_resumen: string | null
  trabajos_pendientes_resumen: string | null
  pruebas_resumen: string | null
  resultado_pruebas: string | null
  estado_salida: string | null
  restricciones_operacionales: string | null
  recomendaciones: string | null
  kilometraje_ingreso: number | null
  kilometraje_salida: number | null
  horometro_ingreso: number | null
  horometro_salida: number | null
  fecha_ingreso: string | null
  fecha_inicio: string | null
  fecha_termino: string | null
  ejecutor_principal_id: string | null
  elaborado_por: string | null
  revisado_por: string | null
  aprobado_por: string | null
  firma_ejecutor_url: string | null
  firma_jefe_url: string | null
  pdf_url: string | null
  pdf_sha256: string | null
  snapshot: Record<string, unknown> | null
  motivo_correccion: string | null
  created_at: string
  updated_at: string
  aprobado_at: string | null
  cerrado_at: string | null
  anulado_at: string | null
}

export interface TrabajoInforme {
  id: string
  informe_id: string
  checklist_item_id: string | null
  nc_id: string | null
  sistema: string | null
  componente: string | null
  sintoma: string | null
  diagnostico: string | null
  trabajo_planificado: string | null
  trabajo_realizado: string | null
  estado: EstadoTrabajoInforme
  resultado: string | null
  responsable_id: string | null
  fecha_inicio: string | null
  fecha_termino: string | null
  horas_hombre: number | null
  es_adicional: boolean
  motivo_adicional: string | null
  evidencia_antes_url: string | null
  evidencia_durante_url: string | null
  evidencia_despues_url: string | null
  observacion: string | null
  created_at: string
}

export interface MaterialInforme {
  id: string
  informe_id: string
  producto_id: string | null
  nc_id: string | null
  producto_codigo: string | null
  producto_descripcion: string | null
  unidad: string | null
  cantidad_entregada: number | null
  cantidad_consumida: number | null
  costo_unitario: number | null
  costo_total: number | null
  metodo_costeo: string | null
  capas_resumen: unknown
  fecha_movimiento: string | null
  created_at: string
}

export interface ManoObraInforme {
  id: string
  informe_id: string
  ejecucion_id: string | null
  tecnico_id: string | null
  tecnico_nombre_snapshot: string | null
  started_at: string | null
  finished_at: string | null
  tiempo_total_segundos: number | null
  tiempo_pausado_segundos: number | null
  tiempo_colacion_segundos: number | null
  tiempo_efectivo_segundos: number | null
  costo_hora_snapshot: number | null
  costo_total_snapshot: number | null
  created_at: string
}

export interface PruebaInforme {
  id: string
  informe_id: string
  tipo_prueba: string
  descripcion: string | null
  resultado: string | null
  valor_medido: number | null
  unidad: string | null
  rango_min: number | null
  rango_max: number | null
  responsable_id: string | null
  evidencia_url: string | null
  observacion: string | null
  fecha_prueba: string | null
  created_at: string
}

export interface ActivoInformeInfo {
  patente: string | null
  codigo: string | null
  nombre: string | null
  marca: string | null
  modelo: string | null
}

export interface InformeIntervencionDetalle {
  informe: InformeIntervencion
  activo: ActivoInformeInfo
  ot: { folio: string | null; tipo: string | null; estado: string | null } | null
  trabajos: TrabajoInforme[]
  materiales: MaterialInforme[]
  manoobra: ManoObraInforme[]
  pruebas: PruebaInforme[]
}

// Campos editables del borrador (subconjunto que acepta rpc_actualizar_borrador_informe)
export type CamposBorradorInforme = Partial<
  Pick<
    InformeIntervencion,
    | 'tipo_intervencion'
    | 'motivo_ingreso'
    | 'condicion_ingreso'
    | 'diagnostico_resumen'
    | 'trabajo_planificado_resumen'
    | 'trabajo_realizado_resumen'
    | 'trabajos_pendientes_resumen'
    | 'pruebas_resumen'
    | 'resultado_pruebas'
    | 'estado_salida'
    | 'restricciones_operacionales'
    | 'recomendaciones'
    | 'kilometraje_ingreso'
    | 'kilometraje_salida'
    | 'horometro_ingreso'
    | 'horometro_salida'
    | 'firma_ejecutor_url'
  >
>

export const BUCKET_INFORMES = 'informes-tecnicos'

// ── Lectura ──────────────────────────────────────────────

/** Informe vigente asociado a la OT (o null si aún no existe). */
export async function getInformePorOt(otId: string) {
  const { data, error } = await supabase
    .from('informes_intervencion')
    .select('*')
    .eq('ot_id', otId)
    .eq('es_version_vigente', true)
    .maybeSingle()
  return { data: (data as InformeIntervencion | null) ?? null, error }
}

/** Cabecera + trabajos + materiales + mano de obra + pruebas + info de activo/OT. */
export async function getInformeDetalle(
  informeId: string,
): Promise<{ data: InformeIntervencionDetalle | null; error: unknown }> {
  const { data: informe, error: errInf } = await supabase
    .from('informes_intervencion')
    .select('*')
    .eq('id', informeId)
    .single()
  if (errInf || !informe) return { data: null, error: errInf }

  const cab = informe as InformeIntervencion

  const [trabajos, materiales, manoobra, pruebas, activoRes, otRes] = await Promise.all([
    supabase
      .from('informe_intervencion_trabajos')
      .select('*')
      .eq('informe_id', informeId)
      .order('created_at'),
    supabase
      .from('informe_intervencion_materiales')
      .select('*')
      .eq('informe_id', informeId)
      .order('created_at'),
    supabase
      .from('informe_intervencion_manoobra')
      .select('*')
      .eq('informe_id', informeId)
      .order('created_at'),
    supabase
      .from('informe_intervencion_pruebas')
      .select('*')
      .eq('informe_id', informeId)
      .order('created_at'),
    supabase
      .from('activos')
      .select('patente, codigo, nombre, modelo:modelos(nombre, marca:marcas(nombre))')
      .eq('id', cab.activo_id)
      .maybeSingle(),
    supabase
      .from('ordenes_trabajo')
      .select('folio, tipo, estado')
      .eq('id', cab.ot_id)
      .maybeSingle(),
  ])

  const activoRaw = activoRes.data as
    | { patente: string | null; codigo: string | null; nombre: string | null; modelo?: { nombre?: string | null; marca?: { nombre?: string | null } | null } | null }
    | null

  const activo: ActivoInformeInfo = {
    patente: activoRaw?.patente ?? null,
    codigo: activoRaw?.codigo ?? null,
    nombre: activoRaw?.nombre ?? null,
    marca: activoRaw?.modelo?.marca?.nombre ?? null,
    modelo: activoRaw?.modelo?.nombre ?? null,
  }

  return {
    data: {
      informe: cab,
      activo,
      ot: (otRes.data as { folio: string | null; tipo: string | null; estado: string | null } | null) ?? null,
      trabajos: (trabajos.data as TrabajoInforme[] | null) ?? [],
      materiales: (materiales.data as MaterialInforme[] | null) ?? [],
      manoobra: (manoobra.data as ManoObraInforme[] | null) ?? [],
      pruebas: (pruebas.data as PruebaInforme[] | null) ?? [],
    },
    error: trabajos.error || materiales.error || manoobra.error || pruebas.error,
  }
}

// ── RPCs (envolturas) ────────────────────────────────────

export async function crearDesdeOt(otId: string) {
  const { data, error } = await supabase.rpc('rpc_crear_informe_intervencion_desde_ot', {
    p_ot_id: otId,
  })
  return { data: data as string | null, error }
}

export async function actualizarBorrador(informeId: string, campos: CamposBorradorInforme) {
  const { data, error } = await supabase.rpc('rpc_actualizar_borrador_informe', {
    p_informe_id: informeId,
    p_campos: campos,
  })
  return { data, error }
}

export async function enviarRevision(informeId: string) {
  const { data, error } = await supabase.rpc('rpc_enviar_informe_revision', {
    p_informe_id: informeId,
  })
  return { data, error }
}

export async function observar(informeId: string, motivo: string) {
  const { data, error } = await supabase.rpc('rpc_observar_informe', {
    p_informe_id: informeId,
    p_motivo: motivo,
  })
  return { data, error }
}

export async function aprobar(informeId: string) {
  const { data, error } = await supabase.rpc('rpc_aprobar_informe_intervencion', {
    p_informe_id: informeId,
  })
  return { data, error }
}

export async function cerrar(informeId: string) {
  const { data, error } = await supabase.rpc('rpc_cerrar_informe_intervencion', {
    p_informe_id: informeId,
  })
  return { data, error }
}

export async function anular(informeId: string, motivo: string) {
  const { data, error } = await supabase.rpc('rpc_anular_informe_intervencion', {
    p_informe_id: informeId,
    p_motivo: motivo,
  })
  return { data, error }
}

export async function crearNuevaVersion(informeId: string, motivo: string) {
  const { data, error } = await supabase.rpc('rpc_crear_nueva_version_informe', {
    p_informe_id: informeId,
    p_motivo: motivo,
  })
  return { data: data as string | null, error }
}

// ── PDF: generar + subir + registrar (bucket privado) ────

/** Ruta canónica del PDF en el bucket privado. */
export function pdfPath(informe: Pick<InformeIntervencion, 'activo_id' | 'folio' | 'version'>): string {
  // folio ya incluye el prefijo 'IT-'; se evita el doble prefijo IT-IT-
  return `activos/${informe.activo_id}/informes/${informe.folio}/v${informe.version}/${informe.folio}-v${informe.version}.pdf`
}

async function sha256Hex(blob: Blob): Promise<string> {
  const buf = await blob.arrayBuffer()
  const hash = await crypto.subtle.digest('SHA-256', buf)
  return Array.from(new Uint8Array(hash))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')
}

/** URL firmada temporal para visualizar el PDF privado. */
export async function getSignedPdfUrl(path: string, expiresIn = 3600) {
  const { data, error } = await supabase.storage
    .from(BUCKET_INFORMES)
    .createSignedUrl(path, expiresIn)
  return { data: data?.signedUrl ?? null, error }
}

/**
 * Genera el PDF del informe aprobado, lo sube al bucket privado (upsert:false),
 * calcula su SHA-256, lo registra vía RPC y devuelve una URL firmada para verlo.
 */
export async function generarYSubirPDF(
  informe: InformeIntervencion,
): Promise<{ path: string; signedUrl: string | null; sha256: string; error: unknown }> {
  // Import diferido para no arrastrar @react-pdf al bundle de quien solo lee.
  const { generarPDFInformeTecnico } = await import(
    '@/components/informe-intervencion/pdf-informe-tecnico'
  )
  const { data: detalle, error: errDet } = await getInformeDetalle(informe.id)
  if (errDet || !detalle) {
    return { path: '', signedUrl: null, sha256: '', error: errDet ?? new Error('No se pudo cargar el detalle') }
  }

  const blob = await generarPDFInformeTecnico(detalle)
  const sha256 = await sha256Hex(blob)
  const path = pdfPath(informe)

  const { error: upErr } = await supabase.storage
    .from(BUCKET_INFORMES)
    .upload(path, blob, { upsert: false, contentType: 'application/pdf' })
  if (upErr) return { path, signedUrl: null, sha256, error: upErr }

  const { error: regErr } = await supabase.rpc('rpc_registrar_pdf_informe', {
    p_informe_id: informe.id,
    p_pdf_url: path,
    p_sha256: sha256,
  })
  if (regErr) return { path, signedUrl: null, sha256, error: regErr }

  const { data: signedUrl } = await getSignedPdfUrl(path)
  return { path, signedUrl, sha256, error: null }
}
