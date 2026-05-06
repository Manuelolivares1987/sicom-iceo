// Capa de sincronizacion offline -> Supabase para Operacion Calama.
//   - prepareCalamaOffline: descarga jornadas activas del operador y guarda
//     en IndexedDB.
//   - enqueueLocal*: helpers para guardar acciones offline con client_uuid.
//   - syncCalamaPending: sube blobs (fotos/firmas) a Storage y luego llama
//     RPCs (idempotentes via client_uuid).

import { supabase } from '@/lib/supabase'
import { calamaDB } from './calama-db'
import { genClientUuid } from '@/lib/services/calama-jornada'
import type {
  LocalJornada, LocalEvidencia, LocalFirma, LocalEvento,
  LocalBlob, SyncStatus,
} from './calama-offline-types'

// ============================================================================
// PREPARAR OFFLINE
// ============================================================================

export async function prepareCalamaOffline(opts?: { fecha?: string }): Promise<{
  jornadas_count: number; downloaded_at: string
}> {
  const db = calamaDB()
  const { data: userRes } = await supabase.auth.getUser()
  const uid = userRes.user?.id ?? null
  const email = userRes.user?.email ?? null

  // 1) Llamar al RPC bundle (incluye proxima semana).
  const { data: bundle, error: errBundle } = await supabase.rpc(
    'rpc_calama_preparar_offline_operador',
    { p_payload: opts?.fecha ? { fecha: opts.fecha } : {} },
  )
  if (errBundle) throw errBundle
  const jornadasFromBundle = ((bundle?.jornadas as Array<Record<string, unknown>>) ?? [])

  // 2) Adicional: traer todas las jornadas asignadas al usuario (sin filtrar
  //    por fecha) para que pueda trabajar sin internet en los proximos dias.
  const { data: planOts } = await supabase
    .from('calama_plan_semanal_ots')
    .select('*')
    .eq('responsable_id', uid)
  const planOtsArr = (planOts ?? []) as Array<Record<string, unknown>>

  // 3) OT madres (titulo, folio, avance).
  const otIds = Array.from(new Set([
    ...planOtsArr.map((p) => String(p.ot_id)),
    ...jornadasFromBundle.map((j) => String(j.ot_id)),
  ]))
  let otsMap = new Map<string, Record<string, unknown>>()
  if (otIds.length > 0) {
    const { data: ots } = await supabase
      .from('calama_ordenes_trabajo')
      .select('id, folio, titulo, avance_pct, estado')
      .in('id', otIds)
    otsMap = new Map((ots ?? []).map((o) => [String((o as { id: string }).id), o as Record<string, unknown>]))
  }

  // 4) Resolver fecha_jornada de cada plan_ot via plan_semanal_dias.
  const diaIds = Array.from(new Set(planOtsArr.map((p) => String(p.plan_dia_id)).filter(Boolean)))
  let diasMap = new Map<string, string>()
  if (diaIds.length > 0) {
    const { data: dias } = await supabase
      .from('calama_plan_semanal_dias')
      .select('id, fecha').in('id', diaIds)
    diasMap = new Map((dias ?? []).map((d) => [String((d as { id: string }).id), String((d as { fecha: string }).fecha)]))
  }

  const now = new Date().toISOString()

  // 5) Persistir en IndexedDB. Filtramos jornadas que NO esten visibles
  //    (desprogramadas / canceladas) y solo guardamos las que el operador
  //    debe poder ejecutar.
  const localJornadas: LocalJornada[] = planOtsArr
    .filter((p) => {
      const visible = (p.visible_en_kanban as boolean | null) ?? true
      const desprogramada = !!p.desprogramada_at
      const anulada = !!p.anulada_at
      const ep = String(p.estado_plan ?? '')
      const ocultos = ['desprogramada','anulada_prueba','cancelada_operacional','no_ejecutada','reprogramada','aceptada','cerrada']
      return visible && !desprogramada && !anulada && !ocultos.includes(ep)
    })
    .map((p) => {
      const planOtId = String(p.id)
      const otId = String(p.ot_id)
      const ot = otsMap.get(otId)
      const folio = ot ? String(ot.folio) : ''
      const titulo = ot ? String(ot.titulo) : ''
      const avance = ot ? Number(ot.avance_pct ?? 0) : 0
      const fecha = diasMap.get(String(p.plan_dia_id ?? '')) ?? null
      return {
        local_id: planOtId,
        server_id: planOtId,
        ot_id: otId,
        plan_semanal_id: String(p.plan_semanal_id ?? '') || null,
        folio,
        titulo,
        fecha_jornada: fecha,
        zona_codigo: null,
        responsable_id: (p.responsable_id as string | null) ?? null,
        estado_plan_server: String(p.estado_plan ?? 'planificada'),
        estado_plan_local: String(p.estado_plan ?? 'planificada'),
        llegada_faena_at: (p.llegada_faena_at as string | null) ?? null,
        inicio_at: null,
        cierre_at: null,
        avance_pct: avance,
        observaciones: (p.observaciones as string | null) ?? null,
        visible_en_kanban: ((p.visible_en_kanban as boolean | null) ?? true),
        desprogramada: false,
        downloaded_at: now,
        updated_local_at: now,
        sync_status: 'synced' as SyncStatus,
      }
    })

  await db.transaction('rw', db.jornadas, db.settings, async () => {
    // Eliminar jornadas locales obsoletas (que el server ya no devuelve),
    // preservando las que tengan acciones pendientes para no perder
    // trabajo offline aun no sincronizado.
    const newIds = new Set(localJornadas.map((j) => j.local_id))
    const existing = await db.jornadas.toArray()
    for (const j of existing) {
      if (!newIds.has(j.local_id) && j.sync_status !== 'pending') {
        await db.jornadas.delete(j.local_id)
      }
    }
    await db.jornadas.bulkPut(localJornadas)
    await db.settings.put({
      key: 'state',
      last_download_at: now,
      user_id: uid,
      user_email: email,
    })
  })

  return { jornadas_count: localJornadas.length, downloaded_at: now }
}

// ============================================================================
// HELPERS DE BLOBS
// ============================================================================

export async function saveBlob(blob: Blob): Promise<string> {
  const db = calamaDB()
  const blob_id = genClientUuid()
  await db.blobs.put({ blob_id, blob, mime: blob.type || 'application/octet-stream', size: blob.size })
  return blob_id
}

export async function getBlob(blob_id: string): Promise<LocalBlob | null> {
  const db = calamaDB()
  return (await db.blobs.get(blob_id)) ?? null
}

export async function deleteBlob(blob_id: string): Promise<void> {
  const db = calamaDB()
  await db.blobs.delete(blob_id)
}

// ============================================================================
// COLA: encolar acciones
// ============================================================================

export async function enqueueEvento(ev: Omit<LocalEvento, 'local_id' | 'client_uuid' | 'created_at' | 'sync_status' | 'retries' | 'last_error'> & {
  client_uuid?: string
}): Promise<string> {
  const db = calamaDB()
  const now = new Date().toISOString()
  const local_id = genClientUuid()
  const client_uuid = ev.client_uuid ?? local_id
  const evento: LocalEvento = {
    local_id, client_uuid, created_at: now,
    sync_status: 'pending', retries: 0, last_error: null,
    ...ev,
  } as LocalEvento
  await db.transaction('rw', db.eventos, db.sync_queue, async () => {
    await db.eventos.put(evento)
    await db.sync_queue.add({
      evento_local_id: local_id, status: 'pending', retries: 0, last_error: null,
      created_at: now, updated_at: now,
    })
  })
  return local_id
}

export async function saveEvidencia(ev: Omit<LocalEvidencia, 'local_id' | 'client_uuid' | 'sync_status' | 'retries' | 'last_error' | 'blob_id' | 'server_id'> & {
  blob?: Blob
}): Promise<{ local_id: string; client_uuid: string; blob_id: string | null }> {
  const db = calamaDB()
  const local_id = genClientUuid()
  let blob_id: string | null = null
  if (ev.blob) {
    blob_id = await saveBlob(ev.blob)
  }
  const evidencia: LocalEvidencia = {
    local_id,
    client_uuid: local_id,
    server_id: null,
    jornada_id: ev.jornada_id, ot_id: ev.ot_id,
    contexto: ev.contexto, momento: ev.momento,
    blob_id, storage_path: ev.storage_path ?? null, archivo_url: ev.archivo_url ?? null,
    mime_type: ev.mime_type ?? (ev.blob?.type ?? null),
    tamano_bytes: ev.tamano_bytes ?? (ev.blob?.size ?? null),
    descripcion: ev.descripcion ?? null,
    gps_lat: ev.gps_lat ?? null, gps_lng: ev.gps_lng ?? null,
    gps_accuracy: ev.gps_accuracy ?? null, geolocation_status: ev.geolocation_status ?? null,
    tomada_en: ev.tomada_en, sync_status: 'pending', retries: 0, last_error: null,
  }
  await db.evidencias.put(evidencia)
  return { local_id, client_uuid: local_id, blob_id }
}

export async function saveFirma(fi: Omit<LocalFirma, 'local_id' | 'client_uuid' | 'sync_status' | 'retries' | 'last_error' | 'blob_id' | 'server_id'> & {
  blob?: Blob
}): Promise<{ local_id: string; client_uuid: string; blob_id: string | null }> {
  const db = calamaDB()
  const local_id = genClientUuid()
  let blob_id: string | null = null
  if (fi.blob) blob_id = await saveBlob(fi.blob)
  const firma: LocalFirma = {
    local_id, client_uuid: local_id, server_id: null,
    jornada_id: fi.jornada_id, ot_id: fi.ot_id,
    firmante_tipo: fi.firmante_tipo, firmante_nombre: fi.firmante_nombre ?? null,
    firmante_rut: fi.firmante_rut ?? null, contexto: fi.contexto,
    blob_id, storage_path: fi.storage_path ?? null, firma_url: fi.firma_url ?? null,
    observacion: fi.observacion ?? null,
    gps_lat: fi.gps_lat ?? null, gps_lng: fi.gps_lng ?? null,
    gps_accuracy: fi.gps_accuracy ?? null, geolocation_status: fi.geolocation_status ?? null,
    firmado_en: fi.firmado_en, sync_status: 'pending', retries: 0, last_error: null,
  }
  await db.firmas.put(firma)
  return { local_id, client_uuid: local_id, blob_id }
}

// ============================================================================
// CONTADORES UI
// ============================================================================

export async function getOfflineCounters() {
  const db = calamaDB()
  const [pendEv, pendFi, pendEvento, errEv, errFi, errEvento, conflictEvento, jornadas] = await Promise.all([
    db.evidencias.where('sync_status').equals('pending').count(),
    db.firmas.where('sync_status').equals('pending').count(),
    db.eventos.where('sync_status').equals('pending').count(),
    db.evidencias.where('sync_status').equals('error').count(),
    db.firmas.where('sync_status').equals('error').count(),
    db.eventos.where('sync_status').equals('error').count(),
    db.eventos.where('sync_status').equals('conflict').count(),
    db.jornadas.count(),
  ])
  const settings = await db.settings.get('state')
  return {
    pendientes: pendEv + pendFi + pendEvento,
    pendientes_evidencias: pendEv,
    pendientes_firmas: pendFi,
    pendientes_eventos: pendEvento,
    errores: errEv + errFi + errEvento,
    conflictos: conflictEvento,
    jornadas_offline: jornadas,
    last_download_at: settings?.last_download_at ?? null,
  }
}

// ============================================================================
// SUBIR BLOBS A STORAGE
// ============================================================================

async function uploadEvidenciaBlob(local: LocalEvidencia, blob: Blob): Promise<{ url: string; storage_path: string }> {
  const ext = (blob.type.split('/')[1] || 'jpg').toLowerCase().replace(/[^a-z0-9]/g, '')
  const ts = Date.now()
  const path = `ot-${local.ot_id}/jornada-${local.jornada_id}/${local.momento}-${ts}-${local.local_id}.${ext}`
  const { error } = await supabase.storage.from('calama-evidencias').upload(path, blob, {
    upsert: false, contentType: blob.type || 'image/jpeg',
  })
  if (error) throw error
  const { data } = supabase.storage.from('calama-evidencias').getPublicUrl(path)
  return { url: data.publicUrl, storage_path: path }
}

async function uploadFirmaBlob(local: LocalFirma, blob: Blob): Promise<{ url: string; storage_path: string }> {
  const ts = Date.now()
  const path = `ot-${local.ot_id}/jornada-${local.jornada_id}/${local.contexto}-${ts}-${local.local_id}.png`
  const { error } = await supabase.storage.from('calama-firmas').upload(path, blob, {
    upsert: false, contentType: 'image/png',
  })
  if (error) throw error
  const { data } = supabase.storage.from('calama-firmas').getPublicUrl(path)
  return { url: data.publicUrl, storage_path: path }
}

// ============================================================================
// SINCRONIZAR PENDIENTES
// ============================================================================

export type SyncResult = {
  ok: number
  err: number
  errors: Array<{ tipo: string; local_id: string; mensaje: string }>
}

const RPC_BY_TIPO: Record<string, string> = {
  iniciar_jornada:   'rpc_calama_iniciar_jornada',
  evento_jornada:    'rpc_calama_registrar_evento_jornada',
  finalizar_jornada: 'rpc_calama_finalizar_jornada',
  llegada_faena:     'rpc_calama_registrar_llegada_faena',
  aceptacion:        'rpc_calama_registrar_aceptacion_jornada',
  rechazo:           'rpc_calama_registrar_rechazo_jornada',
  reprogramar:       'rpc_calama_reprogramar_saldo_ot',
}

export async function syncCalamaPending(): Promise<SyncResult> {
  const db = calamaDB()
  if (typeof navigator !== 'undefined' && !navigator.onLine) {
    return { ok: 0, err: 0, errors: [{ tipo: 'system', local_id: '', mensaje: 'Sin conexion' }] }
  }
  let ok = 0, err = 0
  const errors: SyncResult['errors'] = []

  // 1) Subir blobs pendientes (evidencias + firmas) a Storage.
  const evPend = await db.evidencias.where('sync_status').anyOf(['pending','error']).toArray()
  for (const ev of evPend) {
    if (ev.archivo_url && ev.storage_path) continue  // ya subida (estado raro)
    if (!ev.blob_id) continue
    try {
      const blobRec = await db.blobs.get(ev.blob_id)
      if (!blobRec) {
        await db.evidencias.update(ev.local_id, { sync_status: 'error', last_error: 'Blob local ausente' })
        errors.push({ tipo: 'evidencia_blob', local_id: ev.local_id, mensaje: 'Blob local ausente' })
        err++
        continue
      }
      const { url, storage_path } = await uploadEvidenciaBlob(ev, blobRec.blob)
      await db.evidencias.update(ev.local_id, {
        archivo_url: url, storage_path, retries: ev.retries + 1, last_error: null,
      })
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : 'Error subida evidencia'
      await db.evidencias.update(ev.local_id, {
        sync_status: 'error', retries: ev.retries + 1, last_error: msg,
      })
      errors.push({ tipo: 'evidencia_blob', local_id: ev.local_id, mensaje: msg })
      err++
    }
  }

  const fiPend = await db.firmas.where('sync_status').anyOf(['pending','error']).toArray()
  for (const fi of fiPend) {
    if (fi.firma_url && fi.storage_path) continue
    if (!fi.blob_id) continue
    try {
      const blobRec = await db.blobs.get(fi.blob_id)
      if (!blobRec) {
        await db.firmas.update(fi.local_id, { sync_status: 'error', last_error: 'Blob firma ausente' })
        errors.push({ tipo: 'firma_blob', local_id: fi.local_id, mensaje: 'Blob firma ausente' })
        err++
        continue
      }
      const { url, storage_path } = await uploadFirmaBlob(fi, blobRec.blob)
      await db.firmas.update(fi.local_id, {
        firma_url: url, storage_path, retries: fi.retries + 1, last_error: null,
      })
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : 'Error subida firma'
      await db.firmas.update(fi.local_id, {
        sync_status: 'error', retries: fi.retries + 1, last_error: msg,
      })
      errors.push({ tipo: 'firma_blob', local_id: fi.local_id, mensaje: msg })
      err++
    }
  }

  // 2) Procesar cola de eventos en orden de creacion.
  const items = await db.sync_queue.where('status').anyOf(['pending','error']).sortBy('created_at')
  for (const it of items) {
    try {
      const evento = await db.eventos.get(it.evento_local_id)
      if (!evento) {
        await db.sync_queue.update(it.id!, { status: 'synced', updated_at: new Date().toISOString() })
        continue
      }
      // Resolver blob_refs: poblar URLs en payload.
      const payload: Record<string, unknown> = { ...evento.payload }
      let abortar = false
      for (const ref of evento.blob_refs ?? []) {
        if (ref.evidencia_local_id) {
          const ev = await db.evidencias.get(ref.evidencia_local_id)
          if (!ev || !ev.archivo_url) { abortar = true; break }
          payload[ref.payload_url_key]  = ev.archivo_url
          payload[ref.payload_path_key] = ev.storage_path
        } else if (ref.firma_local_id) {
          const fi = await db.firmas.get(ref.firma_local_id)
          if (!fi || !fi.firma_url) { abortar = true; break }
          payload[ref.payload_url_key]  = fi.firma_url
          payload[ref.payload_path_key] = fi.storage_path
        }
      }
      if (abortar) {
        await db.eventos.update(evento.local_id, {
          sync_status: 'error', retries: evento.retries + 1,
          last_error: 'Blob asociado no se subio',
        })
        await db.sync_queue.update(it.id!, {
          status: 'error', retries: it.retries + 1,
          last_error: 'Blob asociado no se subio',
          updated_at: new Date().toISOString(),
        })
        errors.push({ tipo: evento.rpc_tipo, local_id: evento.local_id, mensaje: 'Blob asociado no se subio' })
        err++
        continue
      }

      // Asegurar client_uuid en el payload.
      if (!payload.client_uuid && !payload.client_uuid_evidencia && !payload.client_uuid_foto && !payload.client_uuid_firma) {
        payload.client_uuid = evento.client_uuid
      }

      const rpcName = RPC_BY_TIPO[evento.rpc_tipo]
      if (!rpcName) {
        await db.eventos.update(evento.local_id, { sync_status: 'error', last_error: `tipo desconocido ${evento.rpc_tipo}` })
        errors.push({ tipo: evento.rpc_tipo, local_id: evento.local_id, mensaje: 'tipo RPC desconocido' })
        err++
        continue
      }
      const { error } = await supabase.rpc(rpcName, { p_payload: payload })
      if (error) {
        // Detectar conflicto: el server rechaza por estado/permiso, no es
        // problema de red. Marcar 'conflict' para que la UI lo distinga.
        const isConflict = /no admite cambios|estado .* no|no encontrado|no autorizado|no se mueve|no se quita|no se cancela|no se desprograma|requiere correccion|aceptada|cerrada|llegada a faena no/i
          .test(error.message)
        const newStatus: SyncStatus = isConflict ? 'conflict' : 'error'
        await db.eventos.update(evento.local_id, {
          sync_status: newStatus, retries: evento.retries + 1, last_error: error.message,
        })
        await db.sync_queue.update(it.id!, {
          status: newStatus, retries: it.retries + 1, last_error: error.message,
          updated_at: new Date().toISOString(),
        })
        errors.push({ tipo: evento.rpc_tipo, local_id: evento.local_id, mensaje: error.message })
        err++
        continue
      }
      // OK: marcar synced + marcar evidencias/firmas asociadas como synced.
      await db.eventos.update(evento.local_id, { sync_status: 'synced', last_error: null })
      await db.sync_queue.update(it.id!, { status: 'synced', updated_at: new Date().toISOString() })
      for (const ref of evento.blob_refs ?? []) {
        if (ref.evidencia_local_id) await db.evidencias.update(ref.evidencia_local_id, { sync_status: 'synced', last_error: null })
        if (ref.firma_local_id)     await db.firmas.update(ref.firma_local_id, { sync_status: 'synced', last_error: null })
      }
      ok++
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : 'Error desconocido'
      errors.push({ tipo: 'system', local_id: it.evento_local_id, mensaje: msg })
      err++
    }
  }

  return { ok, err, errors }
}
