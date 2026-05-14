import { supabase } from '@/lib/supabase'

// ── Tipos ───────────────────────────────────────────────────────────────────

export interface PruebaTerrenoRow {
  ot_id: string
  folio: string
  titulo: string
  ot_estado: string
  avance_pct: number
  fecha_programada: string
  responsable_id: string | null
  responsable_nombre: string | null
  responsable_email: string | null
  plan_semanal_ot_id: string | null
  estado_plan: string | null
  llegada_faena_at: string | null
  cierre_jornada_at: string | null
  created_at: string
  motivo_prueba: string | null
  planificacion_codigo: string | null
  faena_nombre: string | null
  evidencias_count: number
  eventos_count: number
  firmas_count: number
}

export interface CrearJornadaPruebaPayload {
  responsable_id?: string | null
  planificacion_id?: string | null
  faena_id?: string | null
  fecha_jornada?: string | null  // YYYY-MM-DD
}

export interface CrearJornadaPruebaResult {
  success: boolean
  ot_id: string
  folio: string
  plan_semanal_ot_id: string
  plan_semanal_id: string
  plan_dia_id: string
  fecha_jornada: string
  responsable_id: string
  zona_id: string
  planificacion_id: string
  url_mobile: string
  mensaje: string
}

// ── Queries ─────────────────────────────────────────────────────────────────

export async function listarPruebasTerreno() {
  const { data, error } = await supabase
    .from('v_calama_pruebas_terreno')
    .select('*')
    .order('created_at', { ascending: false })
  return { data: data as PruebaTerrenoRow[] | null, error }
}

export async function crearJornadaPrueba(payload: CrearJornadaPruebaPayload) {
  const { data, error } = await supabase.rpc('rpc_calama_crear_jornada_prueba_terreno', {
    p_payload: {
      responsable_id:   payload.responsable_id ?? null,
      planificacion_id: payload.planificacion_id ?? null,
      faena_id:         payload.faena_id ?? null,
      fecha_jornada:    payload.fecha_jornada ?? null,
    },
  })
  if (error) return { data: null, error }
  return { data: data as CrearJornadaPruebaResult, error: null }
}

// Helper para ver evidencias / eventos / firmas de una OT de prueba
export interface EvidenciaPruebaRow {
  id: string
  contexto: string
  momento: string
  tipo: string | null
  archivo_url: string | null
  storage_path: string | null
  descripcion: string | null
  sync_status: string | null
  client_uuid: string | null
  lat: number | null
  lng: number | null
  tomada_en: string | null
  created_at: string
}

export async function listarEvidenciasPrueba(otId: string) {
  const { data, error } = await supabase
    .from('calama_evidencias')
    .select('id, contexto, momento, tipo, archivo_url, storage_path, descripcion, sync_status, client_uuid, lat, lng, tomada_en, created_at')
    .eq('ot_id', otId)
    .eq('es_prueba', true)
    .order('created_at', { ascending: false })
  return { data: data as EvidenciaPruebaRow[] | null, error }
}

export interface EventoPruebaRow {
  id: string
  tipo: string
  motivo: string | null
  comentario: string | null
  avance: number | null
  created_at: string
}

export async function listarEventosPrueba(otId: string) {
  const { data, error } = await supabase
    .from('calama_ot_ejecucion_eventos')
    .select('id, tipo, motivo, comentario, avance, created_at')
    .eq('ot_id', otId)
    .eq('es_prueba', true)
    .order('created_at', { ascending: false })
  return { data: data as EventoPruebaRow[] | null, error }
}

// ── Eliminar prueba ─────────────────────────────────────────────────────────

export interface EliminarPruebaResult {
  success: boolean
  ot_id: string
  folio: string
  eliminado: {
    ot: number
    jornadas: number
    ejecuciones: number
    eventos: number
    evidencias: number
    firmas: number
    precheck: number
    audit: number
  }
  storage: {
    evidencias_borradas: number
    firmas_borradas: number
    errores: string[]
  }
}

// Borra una OT de prueba completamente: archivos en Storage + filas en DB.
// El frontend orquesta: primero recolecta paths, borra Storage, despues llama
// al RPC para borrar las filas. Asi se mantiene el patron oficial de Supabase
// Storage (DELETE en storage.objects no borra el archivo S3).
export async function eliminarPruebaTerreno(otId: string): Promise<{
  data: EliminarPruebaResult | null
  error: Error | null
}> {
  try {
    // 1) Recolectar storage_paths de evidencias y firmas
    const [{ data: evRows }, { data: fiRows }] = await Promise.all([
      supabase
        .from('calama_evidencias')
        .select('storage_path')
        .eq('ot_id', otId)
        .eq('es_prueba', true),
      supabase
        .from('calama_firmas_jornada')
        .select('storage_path')
        .eq('ot_id', otId)
        .eq('es_prueba', true),
    ])

    const pathsEvidencias = ((evRows ?? []) as Array<{ storage_path: string | null }>)
      .map((r) => r.storage_path)
      .filter((p): p is string => !!p)
    const pathsFirmas = ((fiRows ?? []) as Array<{ storage_path: string | null }>)
      .map((r) => r.storage_path)
      .filter((p): p is string => !!p)

    // 2) Borrar archivos en Storage (mejor esfuerzo: si falla, continuamos
    //    con la DB; los archivos quedan orphan pero el sandbox queda limpio)
    const erroresStorage: string[] = []
    let evidenciasBorradas = 0
    let firmasBorradas = 0
    if (pathsEvidencias.length > 0) {
      const { error } = await supabase.storage.from('calama-evidencias').remove(pathsEvidencias)
      if (error) erroresStorage.push(`Storage evidencias: ${error.message}`)
      else evidenciasBorradas = pathsEvidencias.length
    }
    if (pathsFirmas.length > 0) {
      const { error } = await supabase.storage.from('calama-firmas').remove(pathsFirmas)
      if (error) erroresStorage.push(`Storage firmas: ${error.message}`)
      else firmasBorradas = pathsFirmas.length
    }

    // 3) Borrar filas DB via RPC con safety check (es_prueba=true)
    const { data, error } = await supabase.rpc('rpc_calama_eliminar_prueba_terreno', {
      p_payload: { ot_id: otId },
    })
    if (error) return { data: null, error: error as unknown as Error }

    type RpcReturn = {
      success: boolean
      ot_id: string
      folio: string
      eliminado: EliminarPruebaResult['eliminado']
    }
    const r = data as RpcReturn

    return {
      data: {
        success: r.success,
        ot_id: r.ot_id,
        folio: r.folio,
        eliminado: r.eliminado,
        storage: {
          evidencias_borradas: evidenciasBorradas,
          firmas_borradas: firmasBorradas,
          errores: erroresStorage,
        },
      },
      error: null,
    }
  } catch (e) {
    return { data: null, error: e instanceof Error ? e : new Error(String(e)) }
  }
}
