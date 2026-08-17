import { supabase } from '@/lib/supabase'

// ============================================================================
// Control documental de personal — Prevención de Riesgos (MIG298)
// ----------------------------------------------------------------------------
// Pedido por auditoría. Reemplaza la planilla Excel de exámenes ocupacionales.
// ============================================================================

/**
 * Estados del semáforo. Los define la base (v_prevencion_examenes_estado) para
 * que pantalla, correo e informe de auditoría no puedan discrepar.
 *
 *  no_aplica     — exención declarada (ej. "no conduce en faena"). NO es brecha.
 *  observado     — fecha vigente pero el examen no sirve ante el mandante
 *                  (ej. laboratorio no aceptado por CMP).
 *  sin_dato      — falta el registro. En control documental el silencio es
 *                  incumplimiento, nunca conformidad.
 */
export type EstadoExamen =
  | 'vigente' | 'por_vencer_60' | 'por_vencer_30'
  | 'vencido' | 'sin_dato' | 'observado' | 'no_aplica'

export type ExamenPersona = {
  id: string
  tipo_codigo: string
  tipo_nombre: string
  categoria: string
  orden: number
  laboratorio: string | null
  fecha_vencimiento: string | null
  dias_restantes: number | null
  aplica: boolean
  motivo_no_aplica: string | null
  observacion: string | null
  observacion_bloqueante: boolean
  archivo_url: string | null
  estado: EstadoExamen
}

export type PersonaControl = {
  personal_id: string
  rut: string
  nombres: string
  apellidos: string | null
  empresa: string | null
  nro_contrato: string | null
  faena_codigo: string | null
  cargo: string | null
  activo: boolean
  observacion: string | null
  vencidos: number
  observados: number
  sin_dato: number
  por_vencer_30: number
  por_vencer_60: number
  vigentes: number
  no_aplica: number
  proximo_vencimiento: string | null
  estado_general: 'no_conforme' | 'observado' | 'por_vencer' | 'conforme'
  examenes: ExamenPersona[]
}

export type ControlDocumental = {
  generado_at: string
  faena: string | null
  resumen: {
    personas: number
    no_conformes: number
    observados: number
    por_vencer: number
    conformes: number
    examenes_vencidos: number
    examenes_sin_dato: number
    examenes_observados: number
  }
  personas: PersonaControl[]
  faenas: { faena: string, personas: number }[]
}

export async function getControlDocumental(faena?: string | null) {
  const { data, error } = await supabase.rpc('fn_prevencion_control_documental', {
    p_faena: faena ?? null,
  })
  if (error) throw error
  return data as ControlDocumental
}

export type ActualizarExamenInput = {
  examenId: string
  laboratorio?: string | null
  fechaVencimiento?: string | null
  aplica?: boolean
  motivoNoAplica?: string | null
  observacion?: string | null
  observacionBloqueante?: boolean
}

/**
 * Edición directa del examen. La autorización la resuelve la RLS
 * (fn_prevencion_personal_puede_editar), no el frontend.
 */
export async function actualizarExamen(i: ActualizarExamenInput) {
  const patch: Record<string, unknown> = {}
  if (i.laboratorio !== undefined) patch.laboratorio = i.laboratorio || null
  if (i.fechaVencimiento !== undefined) patch.fecha_vencimiento = i.fechaVencimiento || null
  if (i.aplica !== undefined) patch.aplica = i.aplica
  if (i.motivoNoAplica !== undefined) patch.motivo_no_aplica = i.motivoNoAplica || null
  if (i.observacion !== undefined) patch.observacion = i.observacion || null
  if (i.observacionBloqueante !== undefined) patch.observacion_bloqueante = i.observacionBloqueante

  const { error } = await supabase
    .from('prevencion_examenes')
    .update(patch)
    .eq('id', i.examenId)
  if (error) throw error
}
