// Lógica offline-first de la app del mecánico de taller.
// - Cache de OTs liberadas y de su checklist V03 (para operar sin internet).
// - Cola de cambios pendientes (resultado/observación/foto/cronómetro).
// - Overlay: aplica lo pendiente sobre la cache para que la UI refleje lo local.
// - Sync: sube fotos y aplica los cambios contra Supabase al reconectar.

import { supabase } from '@/lib/supabase'
import { getChecklistV3OT, type ChecklistV3Item } from '@/lib/services/taller-plan-semanal'
import { actualizarItem, subirFotoItem } from '@/lib/services/checklist-v2'
import { iniciarOT, pausarOT } from '@/lib/services/ordenes-trabajo'
import { getRecursosOT, solicitarRecurso, subirFotoRecurso, type OTRecurso } from '@/lib/services/ot-recursos'
import { tallerDB, newId, type TallerPending } from './taller-db'

const FIRMA_BUCKET = 'calama-firmas'
async function subirFirmaMecanico(blob: Blob): Promise<string> {
  const path = `taller-mecanico-firmas/${newId()}.png`
  const { error } = await supabase.storage.from(FIRMA_BUCKET).upload(path, blob, { contentType: 'image/png' })
  if (error) throw error
  return supabase.storage.from(FIRMA_BUCKET).getPublicUrl(path).data.publicUrl
}

export type MecanicoOT = {
  ot_id: string
  ot_folio: string
  ot_tipo: string
  ot_estado: string
  ot_prioridad: string
  preparacion_ok_at: string | null
  fecha_programada: string | null
  activo_id: string | null
  activo_codigo: string | null
  activo_nombre: string | null
  activo_patente: string | null
  cuadrilla: string | null
  responsable_id: string | null
  responsable: string | null
  /** TRUE si la OT trae el nombre/cuenta del usuario autenticado (MIG193). */
  asignada_a_mi: boolean | null
  checklist_total: number | null
  checklist_completados: number | null
  tiempo_estimado_total_min: number | null
}

const isOnline = () => (typeof navigator === 'undefined' ? true : navigator.onLine)

// ── OTs ─────────────────────────────────────────────────────────────────────
export async function fetchAndCacheOTs(): Promise<MecanicoOT[]> {
  const { data, error } = await supabase.from('v_taller_mecanico_ots').select('*')
  if (error) throw error
  const list = (data ?? []) as MecanicoOT[]
  await tallerDB().cache.put({ key: 'ots', value: list, updated_at: new Date().toISOString() })
  return list
}

export async function getCachedOTs(): Promise<MecanicoOT[]> {
  const row = await tallerDB().cache.get('ots')
  return (row?.value as MecanicoOT[]) ?? []
}

export async function getOTs(): Promise<MecanicoOT[]> {
  if (isOnline()) { try { return await fetchAndCacheOTs() } catch { return getCachedOTs() } }
  return getCachedOTs()
}

// ── Checklist ────────────────────────────────────────────────────────────────
async function fetchAndCacheChecklist(otId: string): Promise<ChecklistV3Item[]> {
  const items = await getChecklistV3OT(otId)
  await tallerDB().cache.put({ key: `checklist:${otId}`, value: items, updated_at: new Date().toISOString() })
  return items
}

async function getCachedChecklist(otId: string): Promise<ChecklistV3Item[]> {
  const row = await tallerDB().cache.get(`checklist:${otId}`)
  return (row?.value as ChecklistV3Item[]) ?? []
}

/** Checklist con lo pendiente aplicado encima (para la UI). */
export async function getChecklistMecanico(otId: string): Promise<ChecklistV3Item[]> {
  let base: ChecklistV3Item[]
  if (isOnline()) {
    try { base = await fetchAndCacheChecklist(otId) } catch { base = await getCachedChecklist(otId) }
  } else {
    base = await getCachedChecklist(otId)
  }

  const pend = (await tallerDB().pending.where('ot_id').equals(otId).toArray())
    .filter((p) => p.kind === 'item')
    .sort((a, b) => a.created_at.localeCompare(b.created_at))
  if (pend.length === 0) return base

  // Acumular pendientes por ítem (en orden cronológico).
  const acc = new Map<string, { resultado?: string; observacion?: string | null; fotos_blob_ids?: string[]; mediciones?: { pos: string; mm: number | null }[] }>()
  for (const p of pend) {
    if (!p.instance_item_id) continue
    const cur = acc.get(p.instance_item_id) ?? {}
    if (p.resultado !== undefined) cur.resultado = p.resultado
    if (p.observacion !== undefined) cur.observacion = p.observacion
    // Fotos pendientes: nuevas (array) o legado (una sola).
    const nuevas = p.fotos_blob_ids?.length ? p.fotos_blob_ids : (p.foto_blob_id ? [p.foto_blob_id] : [])
    if (nuevas.length) cur.fotos_blob_ids = [...(cur.fotos_blob_ids ?? []), ...nuevas]
    if (p.mediciones !== undefined) cur.mediciones = p.mediciones
    acc.set(p.instance_item_id, cur)
  }

  return Promise.all(base.map(async (it) => {
    const a = acc.get(it.instance_item_id)
    if (!a) return it
    // Evidencias ya sincronizadas + las locales pendientes (object URLs).
    const fotos: string[] = it.foto_urls?.length ? [...it.foto_urls] : (it.foto_url ? [it.foto_url] : [])
    for (const bid of a.fotos_blob_ids ?? []) {
      const b = await tallerDB().blobs.get(bid)
      if (b) fotos.push(URL.createObjectURL(b.blob))
    }
    return {
      ...it,
      resultado: (a.resultado as ChecklistV3Item['resultado']) ?? it.resultado,
      observacion: a.observacion !== undefined ? a.observacion : it.observacion,
      foto_url: fotos[0] ?? it.foto_url,
      foto_urls: fotos.length ? fotos : it.foto_urls,
      mediciones: a.mediciones !== undefined ? a.mediciones : it.mediciones,
    }
  }))
}

// ── Recursos para reparar (MIG197) ──────────────────────────────────────────
async function fetchAndCacheRecursos(otId: string): Promise<OTRecurso[]> {
  const items = await getRecursosOT(otId)
  await tallerDB().cache.put({ key: `recursos:${otId}`, value: items, updated_at: new Date().toISOString() })
  return items
}

/** Recursos de la OT con los pendientes de sincronizar encima (para la UI). */
export async function getRecursosMecanico(otId: string): Promise<OTRecurso[]> {
  let base: OTRecurso[]
  if (isOnline()) {
    try { base = await fetchAndCacheRecursos(otId) } catch { base = await getCachedRecursos(otId) }
  } else {
    base = await getCachedRecursos(otId)
  }
  const pend = (await tallerDB().pending.where('ot_id').equals(otId).toArray())
    .filter((p) => p.kind === 'recurso')
    .sort((a, b) => a.created_at.localeCompare(b.created_at))
  const locales: OTRecurso[] = await Promise.all(pend.map(async (p) => {
    // Fotos aún no subidas: mostrar las locales como object URLs.
    const fotos: string[] = []
    for (const bid of p.fotos_blob_ids ?? []) {
      const b = await tallerDB().blobs.get(bid)
      if (b) fotos.push(URL.createObjectURL(b.blob))
    }
    return {
      id: p.client_uuid, client_uuid: p.client_uuid, ot_id: otId,
      instance_item_id: p.instance_item_id ?? null,
      producto_id: p.producto_id ?? null,
      descripcion: p.descripcion ?? p.producto_nombre ?? null,
      unidad: p.unidad ?? null,
      cantidad: p.cantidad ?? 0, cantidad_aprobada: null,
      comentario: p.comentario ?? null, fotos: fotos.length ? fotos : null, estado: 'solicitado',
      solicitado_por: null, solicitado_nombre: p.solicitado_nombre ?? null,
      agregado_por_jefe: false, validado_por: null, validado_at: null,
      nota_jefe: null, ticket_id: null, created_at: p.created_at,
      producto_codigo: null, producto_nombre: p.producto_nombre ?? null,
      stock_total: null, validado_por_nombre: null, ticket_folio: null, ticket_estado: null,
      oc_id: null, oc_item_id: null, oc_numero: null, oc_numero_externo: null, oc_estado: null,
      oc_fecha_entrega: null, oc_proveedor: null, oc_cantidad_recibida: null,
    }
  }))
  // Evitar duplicados cuando la solicitud ya llegó al servidor (mismo client_uuid).
  const enServer = new Set(base.map((r) => r.client_uuid).filter(Boolean))
  return [...base, ...locales.filter((l) => !enServer.has(l.client_uuid))]
}

async function getCachedRecursos(otId: string): Promise<OTRecurso[]> {
  const row = await tallerDB().cache.get(`recursos:${otId}`)
  return (row?.value as OTRecurso[]) ?? []
}

export async function queueRecurso(params: {
  otId: string
  productoId?: string | null
  productoNombre?: string | null
  descripcion?: string | null
  unidad?: string | null
  cantidad: number
  comentario?: string | null
  solicitadoNombre?: string | null
  fotos?: (File | Blob)[]
  instanceItemId?: string | null
}): Promise<void> {
  const db = tallerDB()
  const fotosIds: string[] = []
  for (const f of params.fotos ?? []) {
    const bid = newId()
    await db.blobs.put({ blob_id: bid, blob: f, mime: (f as File).type || 'image/jpeg' })
    fotosIds.push(bid)
  }
  const row: TallerPending = {
    local_id: newId(), client_uuid: newId(), ot_id: params.otId, kind: 'recurso',
    instance_item_id: params.instanceItemId ?? undefined,
    producto_id: params.productoId ?? null,
    producto_nombre: params.productoNombre ?? null,
    descripcion: params.descripcion ?? null,
    unidad: params.unidad ?? null,
    cantidad: params.cantidad,
    comentario: params.comentario ?? null,
    solicitado_nombre: params.solicitadoNombre ?? null,
    fotos_blob_ids: fotosIds.length ? fotosIds : undefined,
    sync_status: 'pending', retries: 0, last_error: null, created_at: new Date().toISOString(),
  }
  await db.pending.put(row)
  if (isOnline()) {
    try { await syncTallerPending() } catch { /* queda en cola */ }
    const after = await db.pending.get(row.local_id)
    if (after?.sync_status === 'error') {
      throw new Error(after.last_error ?? 'El servidor rechazó la solicitud')
    }
  }
}

// ── Encolar cambios ──────────────────────────────────────────────────────────
export async function queueItem(params: {
  otId: string
  instanceItemId: string
  instanceId: string
  resultado?: 'ok' | 'no_ok' | 'na'
  observacion?: string | null
  files?: (File | Blob)[]
  file?: File | null   // compat: una sola foto
  mediciones?: { pos: string; mm: number | null }[]
}): Promise<void> {
  const db = tallerDB()
  const files = params.files ?? (params.file ? [params.file] : [])
  const fotosIds: string[] = []
  for (const f of files) {
    const bid = newId()
    await db.blobs.put({ blob_id: bid, blob: f, mime: (f as File).type || 'image/jpeg' })
    fotosIds.push(bid)
  }
  const row: TallerPending = {
    local_id: newId(), client_uuid: newId(), ot_id: params.otId, kind: 'item',
    instance_item_id: params.instanceItemId, instance_id: params.instanceId,
    resultado: params.resultado,
    observacion: params.observacion,
    fotos_blob_ids: fotosIds.length ? fotosIds : undefined,
    mediciones: params.mediciones,
    sync_status: 'pending', retries: 0, last_error: null, created_at: new Date().toISOString(),
  }
  await db.pending.put(row)
  if (isOnline()) { try { await syncTallerPending() } catch { /* queda en cola */ } }
}

export async function queueTiming(
  otId: string, accion: 'iniciar' | 'pausar' | 'finalizar', userId: string,
  opts?: { observaciones?: string | null; conObservaciones?: boolean; firma?: File | Blob | null },
): Promise<void> {
  const db = tallerDB()
  let firmaBlobId: string | null = null
  if (opts?.firma) {
    firmaBlobId = newId()
    await db.blobs.put({ blob_id: firmaBlobId, blob: opts.firma, mime: 'image/png' })
  }
  const row: TallerPending = {
    local_id: newId(), client_uuid: newId(), ot_id: otId, kind: 'timing',
    accion, user_id: userId, observaciones: opts?.observaciones ?? null,
    con_observaciones: opts?.conObservaciones ?? false, firma_blob_id: firmaBlobId,
    sync_status: 'pending', retries: 0, last_error: null, created_at: new Date().toISOString(),
  }
  await db.pending.put(row)

  // Optimista: reflejar el cambio de estado en la cache local de OTs.
  const cacheRow = await tallerDB().cache.get('ots')
  if (cacheRow) {
    let list = (cacheRow.value as MecanicoOT[]) ?? []
    if (accion === 'finalizar') {
      list = list.filter((o) => o.ot_id !== otId)
    } else {
      const nuevo = accion === 'iniciar' ? 'en_ejecucion' : 'pausada'
      list = list.map((o) => (o.ot_id === otId ? { ...o, ot_estado: nuevo } : o))
    }
    await tallerDB().cache.put({ key: 'ots', value: list, updated_at: new Date().toISOString() })
  }

  if (isOnline()) {
    try { await syncTallerPending() } catch { /* queda en cola */ }
    // Si el servidor rechazó ESTA acción (p.ej. permiso/estado inválido),
    // avisar al mecánico en vez de fallar en silencio. La acción queda en
    // cola y se reintenta en el próximo sync.
    const after = await db.pending.get(row.local_id)
    if (after?.sync_status === 'error') {
      await fetchAndCacheOTs().catch(() => undefined) // deshacer el optimismo local
      throw new Error(after.last_error ?? 'El servidor rechazó la acción')
    }
  }
}

// ── Sync ─────────────────────────────────────────────────────────────────────
export async function syncTallerPending(): Promise<{ ok: number; failed: number }> {
  if (!isOnline()) return { ok: 0, failed: 0 }
  const db = tallerDB()
  const items = (await db.pending.toArray()).sort((a, b) => a.created_at.localeCompare(b.created_at))
  let ok = 0, failed = 0
  for (const p of items) {
    try {
      if (p.kind === 'item') {
        // Fotos pendientes: nuevas (array) o legado (una sola).
        const blobIds = p.fotos_blob_ids?.length ? p.fotos_blob_ids : (p.foto_blob_id ? [p.foto_blob_id] : [])
        const nuevasUrls: string[] = []
        if (blobIds.length && p.instance_id && p.instance_item_id) {
          for (const bid of blobIds) {
            const b = await db.blobs.get(bid)
            if (b) nuevasUrls.push(await subirFotoItem(p.instance_id, p.instance_item_id, b.blob))
          }
        }
        if (nuevasUrls.length && p.instance_item_id) {
          // Anexar a las evidencias que ya tenga el ítem (no pisar las previas).
          const { data: cur } = await supabase
            .from('checklist_v2_instance_item').select('foto_urls').eq('id', p.instance_item_id).single()
          const prev = ((cur?.foto_urls as string[] | null) ?? []).filter(Boolean)
          const merged = [...prev, ...nuevasUrls]
          await actualizarItem(p.instance_item_id, {
            resultado: p.resultado, observacion: p.observacion ?? undefined,
            foto_urls: merged, foto_url: merged[0], mediciones: p.mediciones,
          })
        } else {
          await actualizarItem(p.instance_item_id!, {
            resultado: p.resultado, observacion: p.observacion ?? undefined, mediciones: p.mediciones,
          })
        }
        for (const bid of blobIds) await db.blobs.delete(bid)
      } else if (p.kind === 'recurso') {
        // Subir primero las fotos del repuesto (si las hay)
        const fotosUrls: string[] = []
        for (const bid of p.fotos_blob_ids ?? []) {
          const b = await db.blobs.get(bid)
          if (b) fotosUrls.push(await subirFotoRecurso(p.ot_id, b.blob))
        }
        await solicitarRecurso({
          otId: p.ot_id, cantidad: p.cantidad ?? 0,
          productoId: p.producto_id, descripcion: p.descripcion,
          unidad: p.unidad, comentario: p.comentario,
          solicitadoNombre: p.solicitado_nombre,
          clientUuid: p.client_uuid,   // idempotente: reintentos no duplican
          fotos: fotosUrls.length ? fotosUrls : null,
          instanceItemId: p.instance_item_id ?? null,
        })
        for (const bid of p.fotos_blob_ids ?? []) await db.blobs.delete(bid)
      } else if (p.accion === 'finalizar') {
        // Finalizar requiere firma del técnico → setea firma y transiciona vía RPC.
        let firmaUrl: string | null = null
        if (p.firma_blob_id) {
          const b = await db.blobs.get(p.firma_blob_id)
          if (b) firmaUrl = await subirFirmaMecanico(b.blob)
        }
        const { error } = await supabase.rpc('rpc_taller_finalizar_mecanico', {
          p_ot_id: p.ot_id, p_firma_tecnico_url: firmaUrl,
          p_con_observaciones: p.con_observaciones ?? false, p_observaciones: p.observaciones ?? null,
        })
        if (error) throw error
        if (p.firma_blob_id) await db.blobs.delete(p.firma_blob_id)
      } else {
        const r = p.accion === 'iniciar' ? await iniciarOT(p.ot_id, p.user_id!)
          : await pausarOT(p.ot_id, p.user_id!, p.observaciones ?? undefined)
        if (r.error) throw r.error
      }
      await db.pending.delete(p.local_id)
      ok++
    } catch (e) {
      const msg = (e as Error).message ?? ''
      // Acción de cronómetro que ya no aplica porque la OT cambió de estado en
      // el servidor (p.ej. quedó "pausar" en cola y la OT ya está finalizada):
      // descartarla — reintentarla jamás va a funcionar y su error se le
      // mostraba al mecánico en cada acción nueva.
      if (p.kind === 'timing' && /transici[oó]n inv[aá]lida/i.test(msg)) {
        if (p.firma_blob_id) await db.blobs.delete(p.firma_blob_id)
        await db.pending.delete(p.local_id)
        continue
      }
      failed++
      await db.pending.update(p.local_id, {
        sync_status: 'error', retries: (p.retries || 0) + 1, last_error: msg,
      })
    }
  }
  return { ok, failed }
}

export async function getPendingCount(): Promise<number> {
  return tallerDB().pending.count()
}

/** Pre-cachea la lista y el checklist de cada OT para operar sin internet. */
export async function prepareTallerOffline(otIds: string[]): Promise<number> {
  await fetchAndCacheOTs().catch(() => undefined)
  let n = 0
  for (const id of otIds) {
    try { await fetchAndCacheChecklist(id); n++ } catch { /* sigue con las demás */ }
  }
  return n
}
