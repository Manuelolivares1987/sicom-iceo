// Motor de sincronizacion offline-first para ventas Franke en terreno.
// Patron Calama: online-first -> si falla por red, encola local; sync al
// reconectar. Idempotente via client_uuid (dedup en rpc_registrar_venta_franke).

import { frankeDB, type LocalVentaFranke, type LocalBlobVF } from './franke-ventas-db'
import { supabase } from '@/lib/supabase'
import { uploadBlobEvidenciaCombustible } from '@/lib/services/combustible'

export function isOnline(): boolean {
  return typeof navigator === 'undefined' ? true : navigator.onLine
}
function uuid(): string {
  return typeof crypto !== 'undefined' && crypto.randomUUID ? crypto.randomUUID()
    : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
        const r = Math.floor(Math.random() * 16); const v = c === 'x' ? r : (r & 0x3) | 0x8; return v.toString(16)
      })
}
function looksLikeNetworkError(e: unknown): boolean {
  const m = (e instanceof Error ? e.message : String(e)).toLowerCase()
  return m.includes('fetch') || m.includes('network') || m.includes('failed') || m.includes('timeout') || m.includes('offline')
}

export type VentaFrankeInput = {
  estanque_movil_id: string
  cliente_nombre: string
  litros: number
  equipo_codigo?: string | null
  equipo_tipo?: string | null
  precio_clp_lt?: number | null
  operador_nombre?: string | null
  operador_rut?: string | null
  nombre_receptor?: string | null
  rut_receptor?: string | null
  documento_numero?: string | null
  observacion?: string | null
  lat?: number | null
  lng?: number | null
  camionLabel: string
  // blobs (se suben antes del RPC)
  firma?: Blob | null
  foto_patente?: Blob | null
  foto_medidor_inicial?: Blob | null
  foto_medidor_final?: Blob | null
}

function buildRpcParams(client_uuid: string, v: VentaFrankeInput, urls: Record<string, string | null>) {
  return {
    p_client_uuid: client_uuid,
    p_estanque_movil_id: v.estanque_movil_id,
    p_cliente_nombre: v.cliente_nombre,
    p_litros: v.litros,
    p_equipo_codigo: v.equipo_codigo ?? null,
    p_equipo_tipo: v.equipo_tipo ?? null,
    p_precio_clp_lt: v.precio_clp_lt ?? null,
    p_operador_nombre: v.operador_nombre ?? null,
    p_operador_rut: v.operador_rut ?? null,
    p_nombre_receptor: v.nombre_receptor ?? null,
    p_rut_receptor: v.rut_receptor ?? null,
    p_firma_receptor_url: urls.firma ?? null,
    p_foto_patente_url: urls.foto_patente ?? null,
    p_foto_medidor_inicial_url: urls.foto_medidor_inicial ?? null,
    p_foto_medidor_final_url: urls.foto_medidor_final ?? null,
    p_lat: v.lat ?? null,
    p_lng: v.lng ?? null,
    p_documento_numero: v.documento_numero ?? null,
    p_observacion: v.observacion ?? null,
  }
}

async function uploadBlob(b: Blob | null | undefined, contextoId: string): Promise<string | null> {
  if (!b) return null
  const { url } = await uploadBlobEvidenciaCombustible(b, { tipo: 'generico', contextoId, ext: 'jpg' })
  return url
}

/** Online-first. Si hay red: sube blobs + llama el RPC. Si falla por red: encola. */
export async function smartRegistrarVentaFranke(v: VentaFrankeInput): Promise<{ ok: boolean; mode: 'online' | 'offline'; client_uuid: string; folio?: string; message: string }> {
  const cid = uuid()
  if (isOnline()) {
    try {
      const urls = {
        firma: await uploadBlob(v.firma, v.estanque_movil_id),
        foto_patente: await uploadBlob(v.foto_patente, v.estanque_movil_id),
        foto_medidor_inicial: await uploadBlob(v.foto_medidor_inicial, v.estanque_movil_id),
        foto_medidor_final: await uploadBlob(v.foto_medidor_final, v.estanque_movil_id),
      }
      const { data, error } = await supabase.rpc('rpc_registrar_venta_franke', buildRpcParams(cid, v, urls))
      if (error) throw error
      return { ok: true, mode: 'online', client_uuid: cid, folio: (data as any)?.folio, message: 'Venta registrada.' }
    } catch (e) {
      if (!looksLikeNetworkError(e)) throw e
      // cae a offline
    }
  }
  await enqueueVenta(cid, v)
  return { ok: true, mode: 'offline', client_uuid: cid, message: 'Guardado en este teléfono. Se sincronizará al recuperar señal.' }
}

async function enqueueVenta(client_uuid: string, v: VentaFrankeInput) {
  const db = frankeDB()
  const blob_refs: LocalVentaFranke['blob_refs'] = []
  const blobs: LocalBlobVF[] = []
  const addBlob = (key: string, b: Blob | null | undefined) => {
    if (!b) return
    const blob_id = uuid()
    blobs.push({ blob_id, blob: b, mime: b.type || 'image/jpeg' })
    blob_refs.push({ key, blob_id })
  }
  addBlob('firma', v.firma)
  addBlob('foto_patente', v.foto_patente)
  addBlob('foto_medidor_inicial', v.foto_medidor_inicial)
  addBlob('foto_medidor_final', v.foto_medidor_final)

  const { firma, foto_patente, foto_medidor_inicial, foto_medidor_final, camionLabel, ...rest } = v
  await db.transaction('rw', db.ventas, db.blobs, async () => {
    for (const b of blobs) await db.blobs.put(b)
    await db.ventas.put({
      local_id: uuid(), client_uuid, payload: rest as Record<string, unknown>, blob_refs,
      sync_status: 'pending', retries: 0, last_error: null,
      resumen: { cliente: v.cliente_nombre, litros: v.litros, camion: camionLabel },
      created_at: new Date().toISOString(), synced_at: null, server_folio: null,
    })
  })
}

export async function syncFrankePending(): Promise<{ ok: number; err: number }> {
  if (!isOnline()) return { ok: 0, err: 0 }
  const db = frankeDB()
  const pend = await db.ventas.where('sync_status').anyOf(['pending', 'error']).toArray()
  let ok = 0, err = 0
  for (const venta of pend) {
    try {
      const urls: Record<string, string | null> = {}
      for (const ref of venta.blob_refs) {
        const rec = await db.blobs.get(ref.blob_id)
        if (rec) { const { url } = await uploadBlobEvidenciaCombustible(rec.blob, { tipo: 'generico', contextoId: String(venta.payload.estanque_movil_id), ext: 'jpg' }); urls[ref.key] = url }
      }
      const params = buildRpcParams(venta.client_uuid, venta.payload as unknown as VentaFrankeInput, urls)
      const { data, error } = await supabase.rpc('rpc_registrar_venta_franke', params)
      if (error) throw error
      await db.ventas.update(venta.local_id, { sync_status: 'synced', synced_at: new Date().toISOString(), server_folio: (data as any)?.folio ?? null, last_error: null })
      for (const ref of venta.blob_refs) await db.blobs.delete(ref.blob_id)
      ok++
    } catch (e) {
      await db.ventas.update(venta.local_id, { sync_status: 'error', retries: venta.retries + 1, last_error: e instanceof Error ? e.message : 'error' })
      err++
    }
  }
  return { ok, err }
}

export async function getFrankeCounters(): Promise<{ pendientes: number; errores: number; sincronizadas: number }> {
  const db = frankeDB()
  const [pendientes, errores, sincronizadas] = await Promise.all([
    db.ventas.where('sync_status').equals('pending').count(),
    db.ventas.where('sync_status').equals('error').count(),
    db.ventas.where('sync_status').equals('synced').count(),
  ])
  return { pendientes, errores, sincronizadas }
}

export async function getFrankeVentasLocales(): Promise<LocalVentaFranke[]> {
  return frankeDB().ventas.orderBy('created_at').reverse().toArray()
}

// Cache de camiones para operar offline.
export async function cacheCamionesFranke(camiones: unknown[]): Promise<void> {
  await frankeDB().cache.put({ key: 'camiones', value: camiones, updated_at: new Date().toISOString() })
}
export async function getCamionesCacheFranke(): Promise<any[]> {
  const r = await frankeDB().cache.get('camiones')
  return (r?.value as any[]) ?? []
}

// Cache del catálogo de despacho (empresa → equipo) para operar offline.
export async function cacheCatalogoFranke(catalogo: unknown[]): Promise<void> {
  await frankeDB().cache.put({ key: 'catalogo_despacho', value: catalogo, updated_at: new Date().toISOString() })
}
export async function getCatalogoCacheFranke(): Promise<any[]> {
  const r = await frankeDB().cache.get('catalogo_despacho')
  return (r?.value as any[]) ?? []
}
