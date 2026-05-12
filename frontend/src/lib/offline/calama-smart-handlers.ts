// Smart handlers online-first con fallback offline para Operacion Calama.
//
// Cada handler:
//   1. Genera client_uuid local.
//   2. Si online -> sube blobs a Storage e invoca el RPC. Si funciona, OK.
//   3. Si offline o error de red -> guarda blobs+evidencias+firmas en
//      IndexedDB y encola un evento con blob_refs en sync_queue.
//   4. Devuelve { ok, mode, client_uuid, message }.
//
// Idempotencia: el client_uuid viaja en payload y el backend (MIG29) usa
// ON CONFLICT para no duplicar. syncCalamaPending() reusa el mismo
// client_uuid al reenviar.

import { supabase } from '@/lib/supabase'
import {
  enqueueEvento, saveEvidencia, saveFirma,
} from './calama-sync'
import type { LocalEvento } from './calama-offline-types'
import { calamaDB } from './calama-db'

export type SmartResult = {
  ok: boolean
  mode: 'online' | 'offline'
  client_uuid: string
  message: string
}

function isOnline(): boolean {
  return typeof navigator === 'undefined' ? true : navigator.onLine
}

function looksLikeNetworkError(err: unknown): boolean {
  if (!err) return false
  const msg = err instanceof Error ? err.message : String(err)
  return /Failed to fetch|NetworkError|TypeError|fetch failed|ECONNRESET|ENOTFOUND|Load failed|connection|offline/i.test(msg)
}

// Generar client_uuid una sola vez por accion.
function newCid(): string {
  if (typeof crypto !== 'undefined' && 'randomUUID' in crypto) return crypto.randomUUID()
  return 'cuid-' + Math.random().toString(36).slice(2) + Date.now().toString(36)
}

// ── Subidas Storage usadas en modo online ─────────────────────────────────

async function uploadEvidenciaToStorage(args: {
  blob: Blob; otId: string; planOtId: string; momento: string
}): Promise<{ url: string; storage_path: string }> {
  const ext = (args.blob.type.split('/')[1] || 'jpg').toLowerCase().replace(/[^a-z0-9]/g, '')
  const path = `ot-${args.otId}/jornada-${args.planOtId}/${args.momento}-${Date.now()}.${ext}`
  const { error } = await supabase.storage.from('calama-evidencias').upload(path, args.blob, {
    upsert: false, contentType: args.blob.type || 'image/jpeg',
  })
  if (error) throw error
  const { data } = supabase.storage.from('calama-evidencias').getPublicUrl(path)
  return { url: data.publicUrl, storage_path: path }
}

async function uploadFirmaToStorage(args: {
  blob: Blob; otId: string; planOtId: string; contexto: string
}): Promise<{ url: string; storage_path: string }> {
  const path = `ot-${args.otId}/jornada-${args.planOtId}/${args.contexto}-${Date.now()}.png`
  const { error } = await supabase.storage.from('calama-firmas').upload(path, args.blob, {
    upsert: false, contentType: 'image/png',
  })
  if (error) throw error
  const { data } = supabase.storage.from('calama-firmas').getPublicUrl(path)
  return { url: data.publicUrl, storage_path: path }
}

// ── Helper update local del estado de la jornada en IndexedDB ─────────────

async function patchLocalJornada(planOtId: string, patch: Partial<{
  estado_plan_local: string; llegada_faena_at: string | null;
  inicio_at: string | null; cierre_at: string | null;
  avance_pct: number;
}>): Promise<void> {
  try {
    const db = calamaDB()
    const j = await db.jornadas.get(planOtId)
    if (j) {
      await db.jornadas.update(planOtId, {
        ...patch,
        updated_local_at: new Date().toISOString(),
      })
    }
  } catch { /* db no inicializada en SSR */ }
}

// ============================================================================
// 1. LLEGADA A FAENA
// ============================================================================
export async function smartLlegadaFaena(args: {
  jornada_id: string; ot_id: string; blob: Blob;
  gps_lat: number | null; gps_lng: number | null;
  gps_accuracy: number | null; geolocation_status: string;
  observacion?: string;
}): Promise<SmartResult> {
  const cid = newCid()
  if (isOnline()) {
    try {
      const up = await uploadEvidenciaToStorage({ blob: args.blob, otId: args.ot_id, planOtId: args.jornada_id, momento: 'llegada' })
      const { error } = await supabase.rpc('rpc_calama_registrar_llegada_faena', {
        p_payload: {
          plan_semanal_ot_id: args.jornada_id,
          foto_llegada_url: up.url, foto_llegada_storage_path: up.storage_path,
          gps_lat: args.gps_lat, gps_lng: args.gps_lng,
          gps_accuracy: args.gps_accuracy, geolocation_status: args.geolocation_status,
          observacion: args.observacion, client_uuid: cid,
        },
      })
      if (error) throw error
      await patchLocalJornada(args.jornada_id, { llegada_faena_at: new Date().toISOString() })
      return { ok: true, mode: 'online', client_uuid: cid, message: 'Llegada registrada' }
    } catch (e) {
      if (!looksLikeNetworkError(e)) throw e
    }
  }
  const ev = await saveEvidencia({
    jornada_id: args.jornada_id, ot_id: args.ot_id,
    contexto: 'llegada_faena', momento: 'llegada',
    storage_path: null, archivo_url: null,
    mime_type: args.blob.type, tamano_bytes: args.blob.size,
    descripcion: args.observacion ?? null,
    gps_lat: args.gps_lat, gps_lng: args.gps_lng,
    gps_accuracy: args.gps_accuracy, geolocation_status: args.geolocation_status,
    tomada_en: new Date().toISOString(), blob: args.blob,
  })
  await enqueueEvento({
    client_uuid: cid,
    jornada_id: args.jornada_id, ot_id: args.ot_id,
    rpc_tipo: 'llegada_faena',
    payload: {
      plan_semanal_ot_id: args.jornada_id,
      gps_lat: args.gps_lat, gps_lng: args.gps_lng,
      gps_accuracy: args.gps_accuracy, geolocation_status: args.geolocation_status,
      observacion: args.observacion, client_uuid: cid,
    },
    blob_refs: [{ payload_url_key: 'foto_llegada_url', payload_path_key: 'foto_llegada_storage_path', evidencia_local_id: ev.local_id }],
  })
  await patchLocalJornada(args.jornada_id, { llegada_faena_at: new Date().toISOString() })
  return { ok: true, mode: 'offline', client_uuid: cid, message: 'Guardado en este telefono. Pendiente de sincronizar.' }
}

// ============================================================================
// 2. INICIAR JORNADA (foto antes obligatoria)
// ============================================================================
export async function smartIniciarJornada(args: {
  jornada_id: string; ot_id: string; foto_antes: Blob;
  gps_lat: number | null; gps_lng: number | null;
  gps_accuracy: number | null; geolocation_status: string;
  observacion?: string;
}): Promise<SmartResult> {
  const cid = newCid()
  if (isOnline()) {
    try {
      const up = await uploadEvidenciaToStorage({ blob: args.foto_antes, otId: args.ot_id, planOtId: args.jornada_id, momento: 'antes' })
      const { error } = await supabase.rpc('rpc_calama_iniciar_jornada', {
        p_payload: {
          plan_semanal_ot_id: args.jornada_id,
          foto_antes_url: up.url, foto_antes_storage_path: up.storage_path,
          gps_lat: args.gps_lat, gps_lng: args.gps_lng,
          gps_accuracy: args.gps_accuracy, geolocation_status: args.geolocation_status,
          observacion: args.observacion, client_uuid_evidencia: cid,
        },
      })
      if (error) throw error
      await patchLocalJornada(args.jornada_id, { estado_plan_local: 'en_ejecucion', inicio_at: new Date().toISOString() })
      return { ok: true, mode: 'online', client_uuid: cid, message: 'Jornada iniciada' }
    } catch (e) {
      if (!looksLikeNetworkError(e)) throw e
    }
  }
  const ev = await saveEvidencia({
    jornada_id: args.jornada_id, ot_id: args.ot_id,
    contexto: 'jornada_antes', momento: 'antes',
    storage_path: null, archivo_url: null,
    mime_type: args.foto_antes.type, tamano_bytes: args.foto_antes.size,
    descripcion: args.observacion ?? null,
    gps_lat: args.gps_lat, gps_lng: args.gps_lng,
    gps_accuracy: args.gps_accuracy, geolocation_status: args.geolocation_status,
    tomada_en: new Date().toISOString(), blob: args.foto_antes,
  })
  await enqueueEvento({
    client_uuid: cid,
    jornada_id: args.jornada_id, ot_id: args.ot_id,
    rpc_tipo: 'iniciar_jornada',
    payload: {
      plan_semanal_ot_id: args.jornada_id,
      gps_lat: args.gps_lat, gps_lng: args.gps_lng,
      gps_accuracy: args.gps_accuracy, geolocation_status: args.geolocation_status,
      observacion: args.observacion, client_uuid_evidencia: cid,
    },
    blob_refs: [{ payload_url_key: 'foto_antes_url', payload_path_key: 'foto_antes_storage_path', evidencia_local_id: ev.local_id }],
  })
  await patchLocalJornada(args.jornada_id, { estado_plan_local: 'en_ejecucion', inicio_at: new Date().toISOString() })
  return { ok: true, mode: 'offline', client_uuid: cid, message: 'Inicio guardado. Pendiente de sincronizar.' }
}

// ============================================================================
// 3. EVENTO (pause / resume / avance / interferencia / foto_durante)
// ============================================================================
export async function smartRegistrarEvento(args: {
  jornada_id: string; ot_id: string;
  tipo: 'pause' | 'resume' | 'avance' | 'comentario' | 'foto_durante' | 'interferencia';
  motivo?: string; comentario?: string; avance?: number;
  foto?: Blob; momento?: 'durante' | 'interferencia';
  gps_lat: number | null; gps_lng: number | null;
  gps_accuracy: number | null; geolocation_status: string;
}): Promise<SmartResult> {
  const cid = newCid()
  const wantPhoto = !!args.foto
  if (isOnline()) {
    try {
      let foto_url: string | undefined; let foto_storage_path: string | undefined
      if (wantPhoto) {
        const m = args.momento ?? (args.tipo === 'interferencia' ? 'interferencia' : 'durante')
        const up = await uploadEvidenciaToStorage({ blob: args.foto!, otId: args.ot_id, planOtId: args.jornada_id, momento: m })
        foto_url = up.url; foto_storage_path = up.storage_path
      }
      const { error } = await supabase.rpc('rpc_calama_registrar_evento_jornada', {
        p_payload: {
          plan_semanal_ot_id: args.jornada_id,
          tipo: args.tipo, motivo: args.motivo, comentario: args.comentario,
          avance: args.avance, foto_url, foto_storage_path,
          gps_lat: args.gps_lat, gps_lng: args.gps_lng,
          gps_accuracy: args.gps_accuracy, geolocation_status: args.geolocation_status,
          client_uuid: cid,
        },
      })
      if (error) throw error
      const patch: Parameters<typeof patchLocalJornada>[1] = {}
      if (args.tipo === 'pause') patch.estado_plan_local = 'pausada'
      if (args.tipo === 'resume') patch.estado_plan_local = 'en_ejecucion'
      if (args.tipo === 'avance' && args.avance != null) patch.avance_pct = args.avance
      if (Object.keys(patch).length) await patchLocalJornada(args.jornada_id, patch)
      return { ok: true, mode: 'online', client_uuid: cid, message: 'Evento registrado' }
    } catch (e) {
      if (!looksLikeNetworkError(e)) throw e
    }
  }
  // OFFLINE
  const blob_refs: NonNullable<LocalEvento['blob_refs']> = []
  if (wantPhoto) {
    const m = args.momento ?? (args.tipo === 'interferencia' ? 'interferencia' : 'durante')
    const ctx = args.tipo === 'interferencia' ? 'interferencia_mandante' : 'jornada_durante'
    const ev = await saveEvidencia({
      jornada_id: args.jornada_id, ot_id: args.ot_id,
      contexto: ctx as 'jornada_durante' | 'interferencia_mandante',
      momento: m,
      storage_path: null, archivo_url: null,
      mime_type: args.foto!.type, tamano_bytes: args.foto!.size,
      descripcion: args.comentario ?? null,
      gps_lat: args.gps_lat, gps_lng: args.gps_lng,
      gps_accuracy: args.gps_accuracy, geolocation_status: args.geolocation_status,
      tomada_en: new Date().toISOString(), blob: args.foto,
    })
    blob_refs.push({ payload_url_key: 'foto_url', payload_path_key: 'foto_storage_path', evidencia_local_id: ev.local_id })
  }
  await enqueueEvento({
    client_uuid: cid,
    jornada_id: args.jornada_id, ot_id: args.ot_id,
    rpc_tipo: 'evento_jornada',
    payload: {
      plan_semanal_ot_id: args.jornada_id,
      tipo: args.tipo, motivo: args.motivo, comentario: args.comentario,
      avance: args.avance,
      gps_lat: args.gps_lat, gps_lng: args.gps_lng,
      gps_accuracy: args.gps_accuracy, geolocation_status: args.geolocation_status,
      client_uuid: cid,
    },
    blob_refs,
  })
  const patch: Parameters<typeof patchLocalJornada>[1] = {}
  if (args.tipo === 'pause') patch.estado_plan_local = 'pausada'
  if (args.tipo === 'resume') patch.estado_plan_local = 'en_ejecucion'
  if (args.tipo === 'avance' && args.avance != null) patch.avance_pct = args.avance
  if (Object.keys(patch).length) await patchLocalJornada(args.jornada_id, patch)
  return { ok: true, mode: 'offline', client_uuid: cid, message: 'Guardado localmente. Pendiente de sincronizar.' }
}

// ============================================================================
// 4. FINALIZAR JORNADA (foto despues + firma operador)
// ============================================================================
export async function smartFinalizarJornada(args: {
  jornada_id: string; ot_id: string;
  avance_final: number;
  foto_despues: Blob; firma_operador: Blob;
  gps_lat: number | null; gps_lng: number | null;
  gps_accuracy: number | null; geolocation_status: string;
  observacion?: string;
}): Promise<SmartResult> {
  const cid = newCid()
  // UUIDs separados para foto y firma: las RPC los castean a UUID y
  // la concatenacion `${cid}-foto` produce un valor invalido (22P02).
  // Generamos arriba del branch online/offline para que ambos usen los
  // mismos valores y la sync offline no duplique tras un fallo post-RPC.
  const cidFoto = newCid()
  const cidFirma = newCid()
  if (isOnline()) {
    try {
      const upFoto  = await uploadEvidenciaToStorage({ blob: args.foto_despues, otId: args.ot_id, planOtId: args.jornada_id, momento: 'despues' })
      const upFirma = await uploadFirmaToStorage({ blob: args.firma_operador, otId: args.ot_id, planOtId: args.jornada_id, contexto: 'cierre_operador' })
      const { error } = await supabase.rpc('rpc_calama_finalizar_jornada', {
        p_payload: {
          plan_semanal_ot_id: args.jornada_id,
          avance_final: args.avance_final,
          foto_despues_url: upFoto.url, foto_despues_storage_path: upFoto.storage_path,
          firma_operador_url: upFirma.url, firma_operador_storage_path: upFirma.storage_path,
          observacion: args.observacion,
          gps_lat: args.gps_lat, gps_lng: args.gps_lng,
          gps_accuracy: args.gps_accuracy, geolocation_status: args.geolocation_status,
          client_uuid_foto: cidFoto, client_uuid_firma: cidFirma,
        },
      })
      if (error) throw error
      await patchLocalJornada(args.jornada_id, {
        estado_plan_local: 'pendiente_aprobacion',
        cierre_at: new Date().toISOString(),
        avance_pct: args.avance_final,
      })
      return { ok: true, mode: 'online', client_uuid: cid, message: 'Jornada cerrada' }
    } catch (e) {
      if (!looksLikeNetworkError(e)) throw e
    }
  }
  const ev = await saveEvidencia({
    jornada_id: args.jornada_id, ot_id: args.ot_id,
    contexto: 'jornada_despues', momento: 'despues',
    storage_path: null, archivo_url: null,
    mime_type: args.foto_despues.type, tamano_bytes: args.foto_despues.size,
    descripcion: args.observacion ?? null,
    gps_lat: args.gps_lat, gps_lng: args.gps_lng,
    gps_accuracy: args.gps_accuracy, geolocation_status: args.geolocation_status,
    tomada_en: new Date().toISOString(), blob: args.foto_despues,
  })
  const fi = await saveFirma({
    jornada_id: args.jornada_id, ot_id: args.ot_id,
    firmante_tipo: 'operador', firmante_nombre: null, firmante_rut: null,
    contexto: 'cierre_operador',
    storage_path: null, firma_url: null, observacion: args.observacion ?? null,
    gps_lat: args.gps_lat, gps_lng: args.gps_lng,
    gps_accuracy: args.gps_accuracy, geolocation_status: args.geolocation_status,
    firmado_en: new Date().toISOString(), blob: args.firma_operador,
  })
  await enqueueEvento({
    client_uuid: cid,
    jornada_id: args.jornada_id, ot_id: args.ot_id,
    rpc_tipo: 'finalizar_jornada',
    payload: {
      plan_semanal_ot_id: args.jornada_id, avance_final: args.avance_final,
      observacion: args.observacion,
      gps_lat: args.gps_lat, gps_lng: args.gps_lng,
      gps_accuracy: args.gps_accuracy, geolocation_status: args.geolocation_status,
      client_uuid_foto: cidFoto, client_uuid_firma: cidFirma,
    },
    blob_refs: [
      { payload_url_key: 'foto_despues_url',    payload_path_key: 'foto_despues_storage_path',    evidencia_local_id: ev.local_id },
      { payload_url_key: 'firma_operador_url',  payload_path_key: 'firma_operador_storage_path',  firma_local_id: fi.local_id },
    ],
  })
  await patchLocalJornada(args.jornada_id, {
    estado_plan_local: 'pendiente_aprobacion',
    cierre_at: new Date().toISOString(),
    avance_pct: args.avance_final,
  })
  return { ok: true, mode: 'offline', client_uuid: cid, message: 'Cierre guardado. Pendiente de sincronizar.' }
}

// ============================================================================
// 5. ACEPTAR JORNADA (mandante)
// ============================================================================
export async function smartAceptarJornada(args: {
  jornada_id: string; ot_id: string;
  firma_mandante: Blob;
  firmante_nombre: string; firmante_rut?: string;
  gps_lat: number | null; gps_lng: number | null;
  gps_accuracy: number | null; geolocation_status: string;
  observacion?: string;
}): Promise<SmartResult> {
  const cid = newCid()
  if (isOnline()) {
    try {
      const upFirma = await uploadFirmaToStorage({ blob: args.firma_mandante, otId: args.ot_id, planOtId: args.jornada_id, contexto: 'aceptacion' })
      const { error } = await supabase.rpc('rpc_calama_registrar_aceptacion_jornada', {
        p_payload: {
          plan_semanal_ot_id: args.jornada_id,
          firma_mandante_url: upFirma.url, firma_mandante_storage_path: upFirma.storage_path,
          firmante_nombre: args.firmante_nombre, firmante_rut: args.firmante_rut,
          observacion: args.observacion,
          gps_lat: args.gps_lat, gps_lng: args.gps_lng,
          gps_accuracy: args.gps_accuracy, geolocation_status: args.geolocation_status,
          client_uuid: cid,
        },
      })
      if (error) throw error
      await patchLocalJornada(args.jornada_id, { estado_plan_local: 'aceptada' })
      return { ok: true, mode: 'online', client_uuid: cid, message: 'Jornada aceptada' }
    } catch (e) {
      if (!looksLikeNetworkError(e)) throw e
    }
  }
  const fi = await saveFirma({
    jornada_id: args.jornada_id, ot_id: args.ot_id,
    firmante_tipo: 'mandante', firmante_nombre: args.firmante_nombre, firmante_rut: args.firmante_rut ?? null,
    contexto: 'aceptacion',
    storage_path: null, firma_url: null, observacion: args.observacion ?? null,
    gps_lat: args.gps_lat, gps_lng: args.gps_lng,
    gps_accuracy: args.gps_accuracy, geolocation_status: args.geolocation_status,
    firmado_en: new Date().toISOString(), blob: args.firma_mandante,
  })
  await enqueueEvento({
    client_uuid: cid,
    jornada_id: args.jornada_id, ot_id: args.ot_id,
    rpc_tipo: 'aceptacion',
    payload: {
      plan_semanal_ot_id: args.jornada_id,
      firmante_nombre: args.firmante_nombre, firmante_rut: args.firmante_rut,
      observacion: args.observacion,
      gps_lat: args.gps_lat, gps_lng: args.gps_lng,
      gps_accuracy: args.gps_accuracy, geolocation_status: args.geolocation_status,
      client_uuid: cid,
    },
    blob_refs: [{ payload_url_key: 'firma_mandante_url', payload_path_key: 'firma_mandante_storage_path', firma_local_id: fi.local_id }],
  })
  await patchLocalJornada(args.jornada_id, { estado_plan_local: 'aceptada' })
  return { ok: true, mode: 'offline', client_uuid: cid, message: 'Aceptacion guardada. Pendiente de sincronizar.' }
}

// ============================================================================
// 6. RECHAZAR JORNADA (mandante)
// ============================================================================
export async function smartRechazarJornada(args: {
  jornada_id: string; ot_id: string;
  motivo: string; requiere_rehacer?: boolean;
  fotos_rechazo?: Blob[]; firma_mandante: Blob;
  firmante_nombre: string;
  gps_lat: number | null; gps_lng: number | null;
  gps_accuracy: number | null; geolocation_status: string;
  observacion?: string;
}): Promise<SmartResult> {
  const cid = newCid()
  if (isOnline()) {
    try {
      const fotosUploaded: Array<{ url: string; storage_path: string; client_uuid: string }> = []
      for (const f of args.fotos_rechazo ?? []) {
        // Cada foto necesita su propio UUID: la RPC casteia a UUID, asi
        // que concatenar `${cid}-foto-N` produce 22P02. newCid() resuelve.
        const cuid = newCid()
        const up = await uploadEvidenciaToStorage({ blob: f, otId: args.ot_id, planOtId: args.jornada_id, momento: 'rechazo' })
        fotosUploaded.push({ url: up.url, storage_path: up.storage_path, client_uuid: cuid })
      }
      const upFirma = await uploadFirmaToStorage({ blob: args.firma_mandante, otId: args.ot_id, planOtId: args.jornada_id, contexto: 'rechazo' })
      const { error } = await supabase.rpc('rpc_calama_registrar_rechazo_jornada', {
        p_payload: {
          plan_semanal_ot_id: args.jornada_id,
          motivo: args.motivo, requiere_rehacer: args.requiere_rehacer ?? true,
          fotos: fotosUploaded,
          firma_mandante_url: upFirma.url, firma_mandante_storage_path: upFirma.storage_path,
          firmante_nombre: args.firmante_nombre, observacion: args.observacion,
          gps_lat: args.gps_lat, gps_lng: args.gps_lng,
          gps_accuracy: args.gps_accuracy, geolocation_status: args.geolocation_status,
          client_uuid_rechazo: newCid(), client_uuid_firma: newCid(),
        },
      })
      if (error) throw error
      await patchLocalJornada(args.jornada_id, { estado_plan_local: 'rechazada' })
      return { ok: true, mode: 'online', client_uuid: cid, message: 'Jornada rechazada' }
    } catch (e) {
      if (!looksLikeNetworkError(e)) throw e
    }
  }
  // OFFLINE: no encolamos rechazo todavia (caso raro: mandante en terreno sin red)
  // Lo tratamos como online error por simplicidad y dejamos que reintente con red.
  throw new Error('Rechazo de mandante requiere conexion. Reintenta cuando vuelva la senal.')
}
