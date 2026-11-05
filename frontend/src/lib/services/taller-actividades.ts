// ============================================================================
// Actividades del camión (MIG668): lavado, revisión técnica y otros papeles.
// ----------------------------------------------------------------------------
// Van directo al camión, sin OT: una OT lo marcaría en mantención. Todo pasa por
// RPC; las reglas (evidencia, motivo, quién aprueba) viven en la base.
// ============================================================================

import { supabase } from '@/lib/supabase'
import { subirEvidencia } from '@/lib/image/evidencia'
import { subirDocumentoCert } from '@/lib/services/taller-planificacion'
import type { VistaBarra } from '@/lib/taller-gantt'

export interface BarraGantt {
  id: string
  origen: 'actividad' | 'ot'
  tipo: string
  titulo: string
  corto: string
  inicio: string
  fin: string
  responsable: string | null
  estado: string
  vista: VistaBarra
  folio?: string
  tecnico_id?: string
  evidencia?: 'foto' | 'certificado'
  notas?: string | null
  rechazo_motivo?: string | null
  fotos?: { url: string }[]
  cert_archivo_url?: string | null
  cert_emision?: string | null
  cert_vencimiento?: string | null
  cert_numero?: string | null
}

export interface PapelGantt {
  tipo: string
  etiqueta: string
  estado: 'vencido' | 'por_vencer' | 'sin_fecha'
  dias: number | null
  vence: string | null
}

export interface CamionGantt {
  activo_id: string
  patente: string
  estado_codigo: string | null
  dias: number | null
  en_taller: boolean
  papeles: PapelGantt[]
  barras: BarraGantt[]
}

export interface SinAgendar {
  activo_id: string
  patente: string
  dias: number
  estado_codigo: string
}

export interface GanttTaller {
  hoy: string
  desde: string
  hasta: string
  operacion: string
  camiones: CamionGantt[]
  sin_agendar: SinAgendar[]
}

export interface PantallaTaller extends Partial<GanttTaller> {
  valido: boolean
  nombre?: string
}

export interface TipoActividad {
  codigo: string
  nombre: string
  corto: string
  evidencia: 'foto' | 'certificado'
  requiere_aprobacion: boolean
  orden: number
}

export interface MiActividad {
  id: string
  activo_id: string
  patente: string
  tipo: string
  nombre: string
  evidencia: 'foto' | 'certificado'
  estado: 'programada' | 'hecha'
  fecha_inicio: string
  fecha_fin: string
  notas: string | null
  responsable: string
  rechazo_motivo: string | null
  cert_tipo: string | null
}

export interface PantallaAcceso {
  id: string
  token: string
  nombre: string
  operacion: string
}

async function rpc<T = unknown>(nombre: string, args?: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.rpc(nombre, args)
  if (error) throw new Error(error.message)
  return data as T
}

export const getGanttTaller = (desde: string, hasta: string, operacion: string) =>
  rpc<GanttTaller>('rpc_taller_gantt', { p_desde: desde, p_hasta: hasta, p_operacion: operacion })

export const getPantallaTaller = (token: string) =>
  rpc<PantallaTaller>('rpc_pantalla_taller', { p_token: token })

export const getMisActividades = () => rpc<MiActividad[]>('rpc_taller_mis_actividades')

export async function getTiposActividad(): Promise<TipoActividad[]> {
  const { data, error } = await supabase
    .from('taller_actividad_tipos').select('codigo, nombre, corto, evidencia, requiere_aprobacion, orden')
    .eq('activo', true).order('orden')
  if (error) throw new Error(error.message)
  return (data ?? []) as TipoActividad[]
}

/** Camiones que se pueden planificar, incluso los que hoy no están en el taller. */
export async function getCamionesPlanificables(operacion: string) {
  const { data, error } = await supabase
    .from('activos').select('id, patente')
    .eq('operacion', operacion).not('patente', 'is', null)
    .neq('estado', 'dado_baja').or('es_prueba.is.null,es_prueba.eq.false').or('es_externo.is.null,es_externo.eq.false')
    .order('patente')
  if (error) throw new Error(error.message)
  return (data ?? []) as { id: string; patente: string }[]
}

export const crearActividad = (p: {
  activoId: string; tipo: string; inicio: string; fin: string; tecnicoId: string
  notas?: string | null; motivo?: string | null
}) => rpc<string>('rpc_taller_actividad_crear', {
  p_activo_id: p.activoId, p_tipo: p.tipo, p_inicio: p.inicio, p_fin: p.fin,
  p_tecnico_id: p.tecnicoId, p_notas: p.notas ?? null, p_motivo: p.motivo ?? null,
})

export const reprogramarActividad = (p: {
  id: string; inicio: string; fin: string; tecnicoId?: string | null; motivo?: string | null
}) => rpc('rpc_taller_actividad_reprogramar', {
  p_id: p.id, p_inicio: p.inicio, p_fin: p.fin, p_tecnico_id: p.tecnicoId ?? null, p_motivo: p.motivo ?? null,
})

export const cancelarActividad = (id: string, motivo: string) =>
  rpc('rpc_taller_actividad_cancelar', { p_id: id, p_motivo: motivo })

export const marcarActividadHecha = (id: string) => rpc('rpc_taller_actividad_marcar_hecha', { p_id: id })

export const aprobarActividad = (id: string) => rpc('rpc_taller_actividad_aprobar', { p_id: id })

export const rechazarActividad = (id: string, motivo: string) =>
  rpc('rpc_taller_actividad_rechazar', { p_id: id, p_motivo: motivo })

export async function subirFotosActividad(id: string, archivos: File[]) {
  const urls: { url: string }[] = []
  for (const archivo of archivos) {
    urls.push({ url: await subirEvidencia('evidencias-verificacion', `actividades/${id}/foto`, archivo) })
  }
  return rpc<string>('rpc_taller_actividad_evidencia_foto', { p_id: id, p_fotos: urls })
}

export async function subirCertificadoActividad(p: {
  actividad: Pick<MiActividad, 'id' | 'activo_id' | 'cert_tipo' | 'tipo'>
  archivo: File; emision: string; vencimiento: string; numero?: string | null
}) {
  const url = await subirDocumentoCert(p.actividad.activo_id, p.actividad.cert_tipo ?? p.actividad.tipo, p.archivo)
  return rpc('rpc_taller_actividad_evidencia_cert', {
    p_id: p.actividad.id, p_archivo_url: url, p_emision: p.emision,
    p_vencimiento: p.vencimiento, p_numero: p.numero ?? null,
  })
}

export const getPantallasTaller = () => rpc<PantallaAcceso[]>('rpc_pantalla_taller_listar')
export const crearPantallaTaller = (nombre: string, operacion: string) =>
  rpc<string>('rpc_pantalla_taller_crear', { p_nombre: nombre, p_operacion: operacion })
export const revocarPantallaTaller = (id: string) => rpc('rpc_pantalla_taller_revocar', { p_id: id })
