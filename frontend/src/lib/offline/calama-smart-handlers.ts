// Handlers "smart" online-first con fallback offline.
// Si hay conexion y el RPC sale OK -> se ejecuta inmediatamente.
// Si no hay conexion (o el RPC falla por red), se guarda en IndexedDB con
// client_uuid para sincronizar despues con syncCalamaPending().
//
// Esto NO duplica acciones: cada llamada genera UN client_uuid; si online
// llega al server con ese client_uuid, el RPC es idempotente; si offline se
// encola y luego sync lo manda con el mismo client_uuid.

import { supabase } from '@/lib/supabase'
import { enqueueEvento, saveEvidencia, saveFirma } from './calama-sync'
import type { LocalEvento } from './calama-offline-types'

export type SmartResult = { mode: 'online' | 'offline'; client_uuid: string }

function isOnline(): boolean {
  return typeof navigator === 'undefined' ? true : navigator.onLine
}

function looksLikeNetworkError(err: unknown): boolean {
  if (!err) return false
  const msg = err instanceof Error ? err.message : String(err)
  return /Failed to fetch|NetworkError|TypeError|fetch failed|ECONNRESET|ENOTFOUND/i.test(msg)
}

// ── LLEGADA A FAENA (con foto + GPS) ───────────────────────────────────────

export async function smartLlegadaFaena(args: {
  jornada_id: string
  ot_id: string
  blob: Blob
  gps_lat: number | null
  gps_lng: number | null
  gps_accuracy: number | null
  geolocation_status: string
  observacion?: string
}): Promise<SmartResult> {
  // Si ONLINE: subimos blob a Storage e invocamos RPC (camino normal).
  if (isOnline()) {
    try {
      // Path-only upload (no SDK helper porque queremos fallback uniforme).
      const ext = (args.blob.type.split('/')[1] || 'jpg').toLowerCase()
      const path = `ot-${args.ot_id}/jornada-${args.jornada_id}/llegada-${Date.now()}.${ext}`
      const { error: errUp } = await supabase.storage.from('calama-evidencias').upload(path, args.blob, {
        upsert: false, contentType: args.blob.type || 'image/jpeg',
      })
      if (errUp) throw errUp
      const { data: pub } = supabase.storage.from('calama-evidencias').getPublicUrl(path)

      const { error } = await supabase.rpc('rpc_calama_registrar_llegada_faena', {
        p_payload: {
          plan_semanal_ot_id: args.jornada_id,
          foto_llegada_url: pub.publicUrl,
          foto_llegada_storage_path: path,
          gps_lat: args.gps_lat, gps_lng: args.gps_lng,
          gps_accuracy: args.gps_accuracy,
          geolocation_status: args.geolocation_status,
          observacion: args.observacion,
        },
      })
      if (error) throw error
      return { mode: 'online', client_uuid: '' }
    } catch (e) {
      if (!looksLikeNetworkError(e)) throw e
      // sigue al fallback offline
    }
  }
  // OFFLINE / network error: guardar local + encolar evento.
  const ev = await saveEvidencia({
    jornada_id: args.jornada_id, ot_id: args.ot_id,
    contexto: 'llegada_faena', momento: 'llegada',
    storage_path: null, archivo_url: null,
    mime_type: args.blob.type, tamano_bytes: args.blob.size,
    descripcion: args.observacion ?? null,
    gps_lat: args.gps_lat, gps_lng: args.gps_lng,
    gps_accuracy: args.gps_accuracy, geolocation_status: args.geolocation_status,
    tomada_en: new Date().toISOString(),
    blob: args.blob,
  })
  const evento: Omit<LocalEvento, 'local_id' | 'client_uuid' | 'created_at' | 'sync_status' | 'retries' | 'last_error'> = {
    jornada_id: args.jornada_id, ot_id: args.ot_id,
    rpc_tipo: 'llegada_faena',
    payload: {
      plan_semanal_ot_id: args.jornada_id,
      gps_lat: args.gps_lat, gps_lng: args.gps_lng,
      gps_accuracy: args.gps_accuracy,
      geolocation_status: args.geolocation_status,
      observacion: args.observacion,
    },
    blob_refs: [{
      payload_url_key: 'foto_llegada_url',
      payload_path_key: 'foto_llegada_storage_path',
      evidencia_local_id: ev.local_id,
    }],
  }
  const local_id = await enqueueEvento(evento)
  return { mode: 'offline', client_uuid: local_id }
}

// El wizard sigue online-first; esta libreria queda lista para extenderse a
// iniciar/finalizar/aceptar/rechazar/evento_jornada con el mismo patron
// (saveEvidencia/saveFirma + enqueueEvento + blob_refs). syncCalamaPending
// resuelve los blob_refs antes de invocar el RPC final.
