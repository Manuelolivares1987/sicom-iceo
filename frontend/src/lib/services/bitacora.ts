import { supabase } from '@/lib/supabase'

// ============================================================================
// Bitácora unificada por equipo (MIG 128) + detalle on-demand por OT.
// ============================================================================

export type BitacoraEvento = {
  activo_id: string
  tipo_registro: 'ot' | 'os_legacy' | 'auditoria' | 'recepcion' | 'diferido' | 'checklist_cliente' | 'informe_tecnico'
  ref_id: string
  fecha: string
  titulo: string
  subtitulo: string | null
  detalle: string | null
  costo: number | null
  responsable: string | null
}

export async function getBitacoraEquipo(activoId: string) {
  const { data, error } = await supabase
    .from('v_bitacora_equipo')
    .select('*')
    .eq('activo_id', activoId)
    .order('fecha', { ascending: false })
  return { data: (data ?? []) as BitacoraEvento[], error }
}

export async function getActivoBasico(activoId: string) {
  const { data, error } = await supabase
    .from('activos')
    .select('id, codigo, patente, nombre, estado, estado_comercial, horas_uso_actual, kilometraje_actual')
    .eq('id', activoId)
    .single()
  return { data, error }
}

/** Detalle profundo de una OT para expandir inline en la bitácora. */
export async function getOtDetalleBitacora(otId: string) {
  const [checklist, evidencias, materiales, ejec] = await Promise.all([
    supabase.from('checklist_ot').select('orden, descripcion, resultado, observacion, foto_url').eq('ot_id', otId).order('orden'),
    supabase.from('evidencias_ot').select('tipo, archivo_url, descripcion').eq('ot_id', otId),
    supabase.from('ot_materiales_planeados').select('cantidad_entregada, estado, producto:productos(nombre, codigo)').eq('ot_id', otId),
    supabase.from('taller_ot_ejecuciones').select('ejecutor_id, started_at, finished_at, tiempo_efectivo_segundos, avance_final, observacion_cierre').eq('ot_id', otId),
  ])
  return {
    checklist: checklist.data ?? [],
    evidencias: evidencias.data ?? [],
    materiales: materiales.data ?? [],
    ejecuciones: ejec.data ?? [],
    error: checklist.error || evidencias.error || materiales.error || ejec.error,
  }
}
