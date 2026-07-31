// Lógica offline-first de la app de terreno ENEX.
// - Cache de pendientes por período y de los ítems de cada pauta.
// - Cola de ejecuciones (resultados + fotos + firmas) que sube al reconectar.
// - Overlay: refleja lo pendiente sobre la cache para la UI.

import {
  getTerrenoPendientes, getPautaItems, ejecutarPauta, getEjecucionItems,
  subirEvidenciaEnex, subirFirmaEnex,
  type EnexPendiente, type EnexPautaItem, type EnexItemResultado,
} from '@/lib/services/enex'
import { enexDB, newId, type EnexPending, type EnexPendItem, type EnexDraft } from './enex-db'

const isOnline = () => (typeof navigator === 'undefined' ? true : navigator.onLine)
const keyPend = (a: number, m: number) => `pend:${a}-${m}`
const keyItems = (pautaId: string) => `items:${pautaId}`

// ── Pendientes por período ───────────────────────────────────────────────
export async function getPendientesOffline(anio: number, mes: number): Promise<EnexPendiente[]> {
  let base: EnexPendiente[]
  if (isOnline()) {
    try {
      base = await getTerrenoPendientes(anio, mes)
      await enexDB().cache.put({ key: keyPend(anio, mes), value: base, updated_at: new Date().toISOString() })
    } catch { base = await getCachedPend(anio, mes) }
  } else {
    base = await getCachedPend(anio, mes)
  }
  // Overlay: marcar como ejecutada/cumplida lo que está en cola local
  const pend = await enexDB().pending.toArray()
  if (pend.length === 0) return base
  const porProg = new Map(pend.map((p) => [p.programacion_id, p]))
  return base.map((r) => {
    const p = porProg.get(r.programacion_id)
    if (!p) return r
    return { ...r, estado: p.con_mandante ? 'cumplida' : 'ejecutada', cumplida: r.cumplida || p.con_mandante }
  })
}
async function getCachedPend(anio: number, mes: number): Promise<EnexPendiente[]> {
  const row = await enexDB().cache.get(keyPend(anio, mes))
  return (row?.value as EnexPendiente[]) ?? []
}

// ── Ítems de pauta ────────────────────────────────────────────────────────
export async function getPautaItemsOffline(pautaId: string): Promise<EnexPautaItem[]> {
  if (isOnline()) {
    try {
      const items = await getPautaItems(pautaId)
      await enexDB().cache.put({ key: keyItems(pautaId), value: items, updated_at: new Date().toISOString() })
      return items
    } catch { /* cae a cache */ }
  }
  const row = await enexDB().cache.get(keyItems(pautaId))
  return (row?.value as EnexPautaItem[]) ?? []
}

// ── Ítems ya registrados de una ejecución (para reabrir un trabajo) ────────
// [MIG265] También se cachean: sin esto, reabrir un servicio sin señal perdía
// de vista lo ya marcado y las fotos ya subidas.
export type EnexEjecucionItemRow = {
  pauta_item_id: string
  resultado: string | null
  valor_medicion: number | null
  observacion: string | null
  foto_url: string | null
  foto_antes_url: string | null
  foto_despues_url: string | null
  fotos_antes: string[] | null
  fotos_despues: string[] | null
}
const keyEjec = (ejecucionId: string) => `ejec:${ejecucionId}`

export async function getEjecucionItemsOffline(ejecucionId: string): Promise<EnexEjecucionItemRow[]> {
  if (isOnline()) {
    try {
      const rows = (await getEjecucionItems(ejecucionId)) as unknown as EnexEjecucionItemRow[]
      await enexDB().cache.put({ key: keyEjec(ejecucionId), value: rows, updated_at: new Date().toISOString() })
      return rows
    } catch { /* cae a cache */ }
  }
  const row = await enexDB().cache.get(keyEjec(ejecucionId))
  return (row?.value as EnexEjecucionItemRow[]) ?? []
}

// Pre-descargar todo lo del período para operar sin señal: pendientes, ítems de
// cada pauta y lo ya ejecutado de cada servicio.
export async function prepararEnexOffline(anio: number, mes: number): Promise<number> {
  const pend = await getTerrenoPendientes(anio, mes)
  await enexDB().cache.put({ key: keyPend(anio, mes), value: pend, updated_at: new Date().toISOString() })
  const pautas = Array.from(new Set(pend.map((p) => p.pauta_id).filter(Boolean))) as string[]
  for (const pid of pautas) { try { await getPautaItemsOffline(pid) } catch { /* sigue */ } }
  const ejecuciones = pend.map((p) => p.ejecucion_id).filter(Boolean) as string[]
  for (const eid of ejecuciones) { try { await getEjecucionItemsOffline(eid) } catch { /* sigue */ } }
  await enexDB().cache.put({
    key: `descarga:${anio}-${mes}`, value: { at: new Date().toISOString(), servicios: pend.length },
    updated_at: new Date().toISOString(),
  })
  return pend.length
}

/** Cuándo se bajó por última vez el período (para avisarlo en pantalla). */
export async function ultimaDescargaEnex(anio: number, mes: number): Promise<string | null> {
  const row = await enexDB().cache.get(`descarga:${anio}-${mes}`)
  return (row?.value as { at?: string } | undefined)?.at ?? null
}

// ── Borrador del trabajo en curso ─────────────────────────────────────────
// [MIG265] En terreno la pauta casi nunca se hace completa de una vez. Si el
// mantenedor cerraba la app o se le apagaba el teléfono antes de «Guardar
// avance», perdía todo lo marcado. Ahora cada cambio queda en el teléfono.

/** Guarda una foto recién capturada como blob local y devuelve su id. */
export async function guardarFotoLocal(file: File | Blob): Promise<string> {
  const id = newId()
  await enexDB().blobs.put({ blob_id: id, blob: file, mime: (file as File).type || 'image/jpeg' })
  return id
}

export async function getFotoLocal(blobId: string): Promise<Blob | null> {
  const b = await enexDB().blobs.get(blobId)
  return b?.blob ?? null
}

export async function guardarDraft(draft: Omit<EnexDraft, 'updated_at'>): Promise<void> {
  await enexDB().drafts.put({ ...draft, updated_at: new Date().toISOString() })
}

export async function getDraft(programacionId: string): Promise<EnexDraft | null> {
  return (await enexDB().drafts.get(programacionId)) ?? null
}

/** Al cerrar cumplida: se borra el borrador y sus fotos ya encoladas. */
export async function borrarDraft(programacionId: string): Promise<void> {
  await enexDB().drafts.delete(programacionId)
}

// ── Encolar una ejecución ─────────────────────────────────────────────────
export async function queueEjecucion(params: {
  programacionId: string
  conMandante: boolean
  otNumero?: string | null
  ejecutor?: string | null
  tecnicoNombre?: string | null
  observacion?: string | null
  firmanteMandante?: string | null
  items: Array<{
    pauta_item_id: string; resultado?: string | null; valor_medicion?: string | null
    observacion?: string | null; file?: File | null; fotoUrl?: string | null
    // [MIG265] Antes/después en TODO ítem, con varias fotos cada uno: las
    // nuevas viajan como File o como blob ya guardado por el borrador, y las
    // que ya están en el servidor, como URL.
    antesFiles?: File[]; despuesFiles?: File[]
    antesBlobIds?: string[]; despuesBlobIds?: string[]
    fotosAntesUrls?: string[]; fotosDespuesUrls?: string[]
  }>
  firmaTecFile?: Blob | null
  firmaMandFile?: Blob | null
  // [MIG265] Tiempo del trabajo en terreno.
  inicioAt?: string | null
  finAt?: string | null
  duracionSegundos?: number | null
}): Promise<{ synced: boolean }> {
  const db = enexDB()
  // Guardar blobs de fotos + firmas
  const items: EnexPendItem[] = []
  const guardarBlobs = async (files: File[] | undefined): Promise<string[]> => {
    const ids: string[] = []
    for (const f of files ?? []) {
      const id = newId()
      await db.blobs.put({ blob_id: id, blob: f, mime: f.type || 'image/jpeg' })
      ids.push(id)
    }
    return ids
  }
  for (const it of params.items) {
    let blobId: string | null = null
    if (it.file) { blobId = newId(); await db.blobs.put({ blob_id: blobId, blob: it.file, mime: it.file.type || 'image/jpeg' }) }
    // Los blobs del borrador ya están en IndexedDB: se reutilizan tal cual en
    // vez de duplicarlos.
    const antesIds = [...(it.antesBlobIds ?? []), ...(await guardarBlobs(it.antesFiles))]
    const despuesIds = [...(it.despuesBlobIds ?? []), ...(await guardarBlobs(it.despuesFiles))]
    items.push({
      pauta_item_id: it.pauta_item_id, resultado: it.resultado ?? null,
      valor_medicion: it.valor_medicion ?? null, observacion: it.observacion ?? null,
      foto_blob_id: blobId,
      fotos_antes_blob_ids: antesIds, fotos_despues_blob_ids: despuesIds,
      // las que ya estaban subidas viajan como URL y se conservan
      fotos_antes_urls: it.fotosAntesUrls ?? [], fotos_despues_urls: it.fotosDespuesUrls ?? [],
      ...(it.fotoUrl && !blobId ? { foto_url_existente: it.fotoUrl } as unknown as object : {}),
    })
  }
  let firmaTecId: string | null = null
  if (params.firmaTecFile) { firmaTecId = newId(); await db.blobs.put({ blob_id: firmaTecId, blob: params.firmaTecFile, mime: 'image/png' }) }
  let firmaMandId: string | null = null
  if (params.firmaMandFile) { firmaMandId = newId(); await db.blobs.put({ blob_id: firmaMandId, blob: params.firmaMandFile, mime: 'image/png' }) }

  const row: EnexPending = {
    local_id: newId(), client_uuid: newId(), programacion_id: params.programacionId,
    con_mandante: params.conMandante, ot_numero: params.otNumero ?? null,
    ejecutor: params.ejecutor ?? null, tecnico_nombre: params.tecnicoNombre ?? null,
    observacion: params.observacion ?? null, firmante_mandante: params.firmanteMandante ?? null,
    items, firma_tec_blob_id: firmaTecId, firma_mand_blob_id: firmaMandId,
    inicio_at: params.inicioAt ?? null, fin_at: params.finAt ?? null,
    duracion_segundos: params.duracionSegundos ?? null,
    sync_status: 'pending', retries: 0, last_error: null, created_at: new Date().toISOString(),
  }
  // Reemplazar cualquier pendiente previo de la misma programación (última gana)
  await db.pending.where('programacion_id').equals(params.programacionId).delete()
  await db.pending.put(row)

  if (isOnline()) {
    const r = await syncEnexPending()
    const after = await db.pending.get(row.local_id)
    if (after?.sync_status === 'error') throw new Error(after.last_error ?? 'El servidor rechazó la ejecución')
    return { synced: r.ok > 0 && !after }
  }
  return { synced: false }
}

// ── Sync ────────────────────────────────────────────────────────────────
export async function syncEnexPending(): Promise<{ ok: number; failed: number }> {
  if (!isOnline()) return { ok: 0, failed: 0 }
  const db = enexDB()
  const rows = (await db.pending.toArray()).sort((a, b) => a.created_at.localeCompare(b.created_at))
  let ok = 0, failed = 0
  for (const p of rows) {
    try {
      // subir fotos de ítems (única + antes/después de actividades críticas)
      const itemsPayload: EnexItemResultado[] = []
      for (const it of p.items) {
        const ex = it as unknown as { foto_url_existente?: string; foto_antes_url_existente?: string; foto_despues_url_existente?: string }
        let fotoUrl: string | null = ex.foto_url_existente ?? null
        if (it.foto_blob_id) {
          const b = await db.blobs.get(it.foto_blob_id)
          if (b) fotoUrl = await subirEvidenciaEnex(new File([b.blob], 'foto.jpg', { type: b.mime }))
        }
        // [MIG265] Galerías: primero lo ya subido, después lo capturado offline.
        const subirGaleria = async (ids: string[] | undefined, nombre: string): Promise<string[]> => {
          const urls: string[] = []
          for (const id of ids ?? []) {
            const b = await db.blobs.get(id)
            if (b) urls.push(await subirEvidenciaEnex(new File([b.blob], nombre + '.jpg', { type: b.mime })))
          }
          return urls
        }
        const antesPrev = it.fotos_antes_urls
          ?? (ex.foto_antes_url_existente ? [ex.foto_antes_url_existente] : [])
        const despuesPrev = it.fotos_despues_urls
          ?? (ex.foto_despues_url_existente ? [ex.foto_despues_url_existente] : [])
        const fotosAntes = [...antesPrev, ...(await subirGaleria(it.fotos_antes_blob_ids, 'antes'))]
        const fotosDespues = [...despuesPrev, ...(await subirGaleria(it.fotos_despues_blob_ids, 'despues'))]

        itemsPayload.push({
          pauta_item_id: it.pauta_item_id, resultado: it.resultado ?? null,
          valor_medicion: it.valor_medicion ?? null, foto_url: fotoUrl,
          foto_antes_url: fotosAntes[0] ?? null, foto_despues_url: fotosDespues[0] ?? null,
          fotos_antes: fotosAntes, fotos_despues: fotosDespues,
          observacion: it.observacion ?? null,
        })
      }
      // firmas
      let firmaTecUrl: string | null = null
      if (p.firma_tec_blob_id) { const b = await db.blobs.get(p.firma_tec_blob_id); if (b) firmaTecUrl = await subirFirmaBlob(b.blob) }
      let firmaMandUrl: string | null = null
      if (p.con_mandante && p.firma_mand_blob_id) { const b = await db.blobs.get(p.firma_mand_blob_id); if (b) firmaMandUrl = await subirFirmaBlob(b.blob) }

      await ejecutarPauta({
        programacionId: p.programacion_id, items: itemsPayload,
        otNumero: p.ot_numero, ejecutor: p.ejecutor, observacion: p.observacion,
        firmaTecnicoUrl: firmaTecUrl, tecnicoNombre: p.tecnico_nombre,
        firmaMandanteUrl: firmaMandUrl, firmanteMandante: p.firmante_mandante,
        clientUuid: p.client_uuid,
        inicioAt: p.inicio_at ?? null, finAt: p.fin_at ?? null,
        duracionSegundos: p.duracion_segundos ?? null,
      })
      // limpiar blobs
      for (const it of p.items) {
        if (it.foto_blob_id) await db.blobs.delete(it.foto_blob_id)
        if (it.foto_antes_blob_id) await db.blobs.delete(it.foto_antes_blob_id)
        if (it.foto_despues_blob_id) await db.blobs.delete(it.foto_despues_blob_id)
        for (const id of it.fotos_antes_blob_ids ?? []) await db.blobs.delete(id)
        for (const id of it.fotos_despues_blob_ids ?? []) await db.blobs.delete(id)
      }
      if (p.firma_tec_blob_id) await db.blobs.delete(p.firma_tec_blob_id)
      if (p.firma_mand_blob_id) await db.blobs.delete(p.firma_mand_blob_id)
      await db.pending.delete(p.local_id)
      ok++
    } catch (e) {
      failed++
      await db.pending.update(p.local_id, { sync_status: 'error', retries: (p.retries || 0) + 1, last_error: (e as Error).message })
    }
  }
  return { ok, failed }
}

// Sube una firma (blob PNG) al bucket público reutilizando el helper de dataURL.
async function subirFirmaBlob(blob: Blob): Promise<string> {
  const dataUrl: string = await new Promise((resolve, reject) => {
    const fr = new FileReader()
    fr.onload = () => resolve(fr.result as string)
    fr.onerror = reject
    fr.readAsDataURL(blob)
  })
  return subirFirmaEnex(dataUrl)
}

export async function getEnexPendingCount(): Promise<number> {
  return enexDB().pending.count()
}
