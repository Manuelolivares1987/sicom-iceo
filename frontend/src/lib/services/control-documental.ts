// ============================================================================
// Control documental de flota. [MIG409/410]
// ----------------------------------------------------------------------------
// El lugar donde los papeles se arreglan, no sólo se miran.
//
// Cada certificado llega con lo que el lector sacó de su PDF: la fecha que
// propone, la regla que usó y el trozo de texto que la respalda. Aceptar es un
// clic; el enlace al archivo está siempre a mano para el que quiera verificar.
//
// La misma información alimenta el QR que escanea el cliente (MIG410): si acá
// un papel figura sin fecha, allá dice «vigencia por confirmar», no
// «permanente».
// ============================================================================
import { supabase } from '@/lib/supabase'

export type EstadoDoc = 'vigente' | 'por_vencer' | 'vencido' | 'sin_fecha' | 'no_aplica'
export type Confianza = 'alta' | 'regla_2_anios' | 'sin_ancla' | 'sin_fecha' | 'no_vence' | 'error'

export type EquipoDocumental = {
  activo_id: string
  patente: string
  activo_codigo: string
  activo_nombre: string | null
  activo_tipo: string | null
  activo_estado: string
  total: number
  vencidos: number
  sin_fecha: number
  por_vencer: number
  vigentes: number
  no_aplica: number
  con_propuesta: number
  propuestas_vencidas: number
  vencidos_bloqueantes: number
}

export type PapelEquipo = {
  activo_id: string
  patente: string
  certificacion_id: string
  tipo: string
  numero_certificado: string | null
  entidad_certificadora: string | null
  fecha_emision: string | null
  fecha_vencimiento: string | null
  estado: EstadoDoc
  dias_restantes: number | null
  archivo_url: string | null
  bloqueante: boolean | null
  fecha_origen: string | null
  propuesta_id: string | null
  vencimiento_propuesto: string | null
  emision_propuesta: string | null
  propuesta_confianza: Confianza | null
  propuesta_regla: string | null
  propuesta_evidencia: string | null
  propuesta_vencida: boolean | null
  /** [MIG427] El TIPO completo está marcado como que no vence. */
  tipo_no_caduca: boolean | null
}

export async function getEquiposDocumental(): Promise<EquipoDocumental[]> {
  const { data, error } = await supabase
    .from('v_control_documental_equipo').select('*')
    .order('vencidos', { ascending: false })
    .order('sin_fecha', { ascending: false })
  if (error) throw error
  return (data ?? []) as EquipoDocumental[]
}

export async function getPapelesEquipo(activoId: string): Promise<PapelEquipo[]> {
  const { data, error } = await supabase
    .from('v_control_documental').select('*')
    .eq('activo_id', activoId)
  if (error) throw error
  const orden: Record<string, number> = { vencido: 0, sin_fecha: 1, por_vencer: 2, vigente: 3, no_aplica: 4 }
  return ((data ?? []) as PapelEquipo[]).sort(
    (a, b) => (orden[a.estado] ?? 9) - (orden[b.estado] ?? 9) || a.tipo.localeCompare(b.tipo))
}

/** Fija el vencimiento. `origen` deja escrito de dónde salió la fecha. */
export async function fijarFecha(params: {
  certificacionId: string
  vencimiento: string
  emision?: string | null
  origen: 'documento' | 'regla_2_anios' | 'manual'
  nota?: string | null
}) {
  const { data, error } = await supabase.rpc('rpc_certificacion_fijar_fecha', {
    p_certificacion_id: params.certificacionId,
    p_vencimiento: params.vencimiento,
    p_emision: params.emision ?? null,
    p_origen: params.origen,
    p_nota: params.nota ?? null,
  })
  if (error) throw error
  return data as { success: boolean; vencimiento: string; vencido: boolean; origen: string }
}

/**
 * [MIG427] Decir que un papel no caduca.
 *
 * El alcance importa y no se adivina: «este» habla de un documento —éste no
 * declara vencimiento— y «tipo» de la categoría entera, incluidos los que
 * lleguen mañana. El certificado de cabina es del segundo caso.
 *
 * En un certificado bloqueante la base exige el motivo: afirmar que un papel
 * que autoriza a operar no vence tiene que quedar firmado por alguien.
 */
export async function marcarNoCaduca(params: {
  certificacionId: string
  alcance: 'este' | 'tipo'
  motivo?: string | null
}) {
  const { data, error } = await supabase.rpc('rpc_certificacion_no_caduca', {
    p_certificacion_id: params.certificacionId,
    p_alcance: params.alcance,
    p_motivo: params.motivo ?? null,
  })
  if (error) throw error
  return data as { success: boolean; tipo: string; patente: string; alcance: string; papeles_resueltos: number }
}

/** Deshacer lo anterior: el papel vuelve a pedir fecha. */
export async function vuelveACaducar(certificacionId: string, alcance: 'este' | 'tipo') {
  const { data, error } = await supabase.rpc('rpc_certificacion_vuelve_a_caducar', {
    p_certificacion_id: certificacionId, p_alcance: alcance,
  })
  if (error) throw error
  return data as { success: boolean; tipo: string; papeles_afectados: number }
}

export async function descartarPropuesta(certificacionId: string, motivo: string) {
  const { data, error } = await supabase.rpc('rpc_certificacion_descartar_propuesta', {
    p_certificacion_id: certificacionId, p_motivo: motivo,
  })
  if (error) throw error
  return data as { success: boolean; descartadas: number }
}

// ── Etiquetas ───────────────────────────────────────────────────────────────

export const ESTADO_DOC: Record<EstadoDoc, { label: string; cls: string; orden: number }> = {
  vencido:    { label: 'Vencido',        cls: 'bg-red-100 text-red-700',       orden: 0 },
  sin_fecha:  { label: 'Falta la fecha', cls: 'bg-orange-100 text-orange-800', orden: 1 },
  por_vencer: { label: 'Por vencer',     cls: 'bg-amber-100 text-amber-800',   orden: 2 },
  vigente:    { label: 'Vigente',        cls: 'bg-green-100 text-green-700',   orden: 3 },
  no_aplica:  { label: 'No caduca',      cls: 'bg-gray-100 text-gray-600',     orden: 4 },
}

/** Qué tan confiable es lo que el lector sacó del archivo. */
export const CONFIANZA: Record<Confianza, { label: string; detalle: string; cls: string }> = {
  alta: {
    label: 'Lo dice el documento',
    detalle: 'La fecha está escrita en el archivo. Es la más segura.',
    cls: 'bg-green-100 text-green-800',
  },
  regla_2_anios: {
    label: 'Regla de 2 años',
    detalle: 'El documento NO declara vigencia: se contaron 2 años desde su fecha. Es un supuesto.',
    cls: 'bg-amber-100 text-amber-800',
  },
  sin_ancla: {
    label: 'Fechas sin etiqueta',
    detalle: 'Tiene fechas pero ninguna dice ser la del documento. Hay que abrirlo.',
    cls: 'bg-gray-100 text-gray-700',
  },
  sin_fecha: {
    label: 'Escaneo ilegible',
    detalle: 'Es una foto de papel, sin texto que leer. Hay que abrirlo y anotar la fecha a mano.',
    cls: 'bg-gray-100 text-gray-700',
  },
  no_vence: { label: 'No caduca', detalle: 'Papel de identidad del equipo.', cls: 'bg-gray-100 text-gray-500' },
  error:    { label: 'No se pudo leer', detalle: 'El archivo no se pudo descargar o abrir.', cls: 'bg-red-100 text-red-700' },
}

export const TIPO_DOC: Record<string, string> = {
  revision_tecnica: 'Revisión técnica', soap: 'SOAP', permiso_circulacion: 'Permiso de circulación',
  seguro_rc: 'Seguro responsabilidad civil', hermeticidad: 'Hermeticidad del estanque',
  laminas_seguridad: 'Láminas de seguridad', analisis_gases: 'Análisis de gases',
  cert_cabina: 'Certificado de cabina', tacografo: 'Tacógrafo', torque_ruedas: 'Torque de ruedas',
  ausencia_falla_ecm: 'Ausencia de falla ECM', operatividad: 'Operatividad', mantencion: 'Mantención',
  mant_hidraulico: 'Mantención hidráulica', aire_acondicionado: 'Aire acondicionado',
  inventario_neumaticos: 'Inventario de neumáticos', grilletes_eslingas: 'Grilletes y eslingas',
  barra_antivuelco: 'Barra antivuelco', sist_riego: 'Sistema de riego', flujo_descarga: 'Flujo de descarga',
  optico_sobrellenado: 'Óptico de sobrellenado', calibracion: 'Calibración', tc8_sec: 'TC8 SEC',
  inscripcion_sec: 'Inscripción SEC', inscripcion_rnvm: 'Inscripción RNVM', padron: 'Padrón',
  ficha_tecnica: 'Ficha técnica', factura_compra: 'Factura de compra', homologacion: 'Homologación',
  gps: 'GPS', cert_gancho: 'Certificado de gancho', sec: 'SEC', seremi: 'SEREMI', otra: 'Otro',
}

export const nombreTipo = (t: string) => TIPO_DOC[t] ?? t.replace(/_/g, ' ')

// ── Cuánto dura cada papel, según sus propios documentos ────────────────────
// [MIG415] La regla de 2 años era un acuerdo para papeles que no declaran
// vigencia. La hermeticidad SÍ la declara —6 meses— y aplicarle un año es
// exactamente cómo doce camiones terminaron circulando con el certificado
// vencido y el sistema en verde. Donde hay estándar, el estándar manda.

export type VigenciaEstandar = { tipo: string; meses: number; fuente: string }

export async function getVigenciasEstandar(): Promise<Record<string, VigenciaEstandar>> {
  const { data, error } = await supabase.from('certificado_vigencia_estandar').select('*')
  if (error) throw error
  const out: Record<string, VigenciaEstandar> = {}
  for (const v of (data ?? []) as VigenciaEstandar[]) out[v.tipo] = v
  return out
}

/** emisión + N meses, en ISO. Devuelve '' si falta la emisión. */
export function sumarMeses(emisionISO: string, meses: number): string {
  if (!emisionISO) return ''
  const [a, m, d] = emisionISO.split('-').map(Number)
  // Día 0 del mes siguiente = último día del mes: así un 31 de enero + 1 mes
  // cae el 28/29 de febrero en vez de saltar a marzo.
  const ultimo = new Date(Date.UTC(a, m - 1 + meses + 1, 0)).getUTCDate()
  const dt = new Date(Date.UTC(a, m - 1 + meses, Math.min(d, ultimo)))
  return dt.toISOString().slice(0, 10)
}

/** Cuántos meses hay entre dos fechas, redondeado. Para comparar con el estándar. */
export function mesesEntre(desdeISO: string, hastaISO: string): number | null {
  if (!desdeISO || !hastaISO) return null
  const d = new Date(desdeISO), h = new Date(hastaISO)
  if (isNaN(+d) || isNaN(+h)) return null
  return Math.round((+h - +d) / (1000 * 60 * 60 * 24 * 30.44))
}
