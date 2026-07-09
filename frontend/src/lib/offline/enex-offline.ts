// Lógica offline-first de la app de terreno ENEX.
// - Cache de pendientes por período y de los ítems de cada pauta.
// - Cola de ejecuciones (resultados + fotos + firmas) que sube al reconectar.
// - Overlay: refleja lo pendiente sobre la cache para la UI.

import {
  getTerrenoPendientes, getPautaItems, ejecutarPauta,
  subirEvidenciaEnex, subirFirmaEnex,
  type EnexPendiente, type EnexPautaItem, type EnexItemResultado,
} from '@/lib/services/enex'
import { enexDB, newId, type EnexPending, type EnexPendItem } from './enex-db'

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

// Pre-descargar todo lo del período para operar sin señal
export async function prepararEnexOffline(anio: number, mes: number): Promise<number> {
  const pend = await getTerrenoPendientes(anio, mes)
  await enexDB().cache.put({ key: keyPend(anio, mes), value: pend, updated_at: new Date().toISOString() })
  const pautas = Array.from(new Set(pend.map((p) => p.pauta_id).filter(Boolean))) as string[]
  let n = 0
  for (const pid of pautas) { try { await getPautaItemsOffline(pid); n++ } catch { /* sigue */ } }
  return pend.length
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
  items: Array<{ pauta_item_id: string; resultado?: string | null; valor_medicion?: string | null; observacion?: string | null; file?: File | null; fotoUrl?: string | null }>
  firmaTecFile?: Blob | null
  firmaMandFile?: Blob | null
}): Promise<{ synced: boolean }> {
  const db = enexDB()
  // Guardar blobs de fotos + firmas
  const items: EnexPendItem[] = []
  for (const it of params.items) {
    let blobId: string | null = null
    if (it.file) { blobId = newId(); await db.blobs.put({ blob_id: blobId, blob: it.file, mime: it.file.type || 'image/jpeg' }) }
    items.push({
      pauta_item_id: it.pauta_item_id, resultado: it.resultado ?? null,
      valor_medicion: it.valor_medicion ?? null, observacion: it.observacion ?? null,
      foto_blob_id: blobId ?? (it.fotoUrl ? null : null),
      // conservar url ya subida si venía (edición): la mandamos tal cual
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
      // subir fotos de ítems
      const itemsPayload: EnexItemResultado[] = []
      for (const it of p.items) {
        let fotoUrl: string | null = (it as unknown as { foto_url_existente?: string }).foto_url_existente ?? null
        if (it.foto_blob_id) {
          const b = await db.blobs.get(it.foto_blob_id)
          if (b) fotoUrl = await subirEvidenciaEnex(new File([b.blob], 'foto.jpg', { type: b.mime }))
        }
        itemsPayload.push({
          pauta_item_id: it.pauta_item_id, resultado: it.resultado ?? null,
          valor_medicion: it.valor_medicion ?? null, foto_url: fotoUrl, observacion: it.observacion ?? null,
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
      })
      // limpiar blobs
      for (const it of p.items) if (it.foto_blob_id) await db.blobs.delete(it.foto_blob_id)
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
