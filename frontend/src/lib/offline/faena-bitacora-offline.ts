// ============================================================================
// Bitácora del turno sin señal (MIG696) — mismo patrón que la pauta y la bodega
// ----------------------------------------------------------------------------
// «No se ocupa porque la señal es malísima» (Manuel, 15-11-2026). Todo lo de
// la bitácora funciona sin señal:
//   · LEER: la última bitácora bajada queda en el teléfono (7 días).
//   · ESCRIBIR: novedad, pendiente, nota/cierre y «leído y entendido» van a una
//     cola con client_uuid y suben solos (sincronizador del layout de Franke).
//   · Lo que está en la cola se MUESTRA de inmediato, mezclado con lo bajado.
// El servidor es idempotente por client_uuid: reintentar nunca duplica.
// ============================================================================

import { haySesionServidor } from '@/lib/supabase'
import { esTransitorio, esDuplicado } from '@/lib/offline/bandeja'
import Dexie, { type Table } from 'dexie'
import { supabase } from '@/lib/supabase'
import { compressImage } from '@/lib/image/compress'
import { subirFotoPauta } from '@/lib/services/faena-pauta'

export type Severidad = 'normal' | 'importante' | 'critica'
export type Categoria = 'seguridad' | 'equipo' | 'operacion' | 'combustible' | 'bodega' | 'personal' | 'mandante' | 'otro'

export type Novedad = {
  id: string; fecha_hora: string; turno: string | null; autor: string | null; autor_id: string | null
  categoria: Categoria; severidad: Severidad; texto: string; foto_url: string | null; equipo: string | null
  leida_por_mi: boolean; acuses: { nombre: string; at: string }[]
  local?: boolean            // todavía en el teléfono
}
export type Pendiente = {
  id: string; titulo: string; detalle: string | null; prioridad: 'alta' | 'media' | 'baja'
  responsable_turno: 'A' | 'B' | 'ambos' | null; vence: string | null; contingencia: string | null
  equipo: string | null; estado: 'abierto' | 'cerrado'; creado_nombre: string | null; created_at: string
  cerrado_nombre: string | null; cerrado_at: string | null; cierre_nota: string | null; vencido: boolean
  notas: { autor: string | null; texto: string; at: string }[]
  local?: boolean
}
export type Bitacora = {
  generado_at: string
  mi_turno: 'A' | 'B' | null
  ciclo: { turno: string; fecha_inicio: string; fecha_fin: string } | null
  novedades: Novedad[]
  por_leer: string[]
  pendientes: Pendiente[]
  equipos: { id: string; patente: string }[]
  resumen: { novedades: number; criticas: number; pendientes_abiertos: number; pendientes_cerrados: number;
             bodega_bajo_minimo: number; combustible_lt: number | null }
}

type OpNovedad = { tipo: 'novedad'; categoria: Categoria; severidad: Severidad; texto: string; activo_id: string | null;
                   equipo: string | null; foto_blob: string | null; fecha_hora: string }
type OpAcuse = { tipo: 'acuse'; ids: string[] }
type OpPendiente = { tipo: 'pendiente'; titulo: string; detalle: string; prioridad: Pendiente['prioridad'];
                     responsable_turno: 'A' | 'B' | 'ambos'; vence: string | null; contingencia: string; activo_id: string | null; equipo: string | null }
type OpNota = { tipo: 'nota'; pendiente_id: string; texto: string; cerrar: boolean }
export type OpBitacora = (OpNovedad | OpAcuse | OpPendiente | OpNota) & {
  local_id: string; faena_id: string; created_at: string; sync_status: 'pending' | 'rechazada'; intentos: number
  ultimo_error?: string | null; autor?: string | null
}

type CacheRow = { key: string; value: unknown; updated_at: string }
type BlobRow = { blob_id: string; blob: Blob }

class BitacoraDB extends Dexie {
  cache!: Table<CacheRow, string>
  pending!: Table<OpBitacora, string>
  blobs!: Table<BlobRow, string>
  constructor() {
    super('sicom-faena-bitacora')
    this.version(1).stores({ cache: 'key, updated_at', pending: 'local_id, sync_status, created_at', blobs: 'blob_id' })
  }
}
let _db: BitacoraDB | null = null
const db = () => {
  if (typeof window === 'undefined') throw new Error('solo en cliente')
  if (!_db) _db = new BitacoraDB()
  return _db
}

const isOnline = () => (typeof navigator === 'undefined' ? true : navigator.onLine)
const nuevoId = () => (typeof crypto !== 'undefined' && 'randomUUID' in crypto ? crypto.randomUUID()
  : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => { const r = (Math.random() * 16) | 0; return (c === 'x' ? r : (r & 0x3) | 0x8).toString(16) }))
function conTimeout<T>(p: PromiseLike<T>, ms = 10000): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const t = setTimeout(() => reject(new Error('timeout de red')), ms)
    Promise.resolve(p).then((v) => { clearTimeout(t); resolve(v) }, (e) => { clearTimeout(t); reject(e) })
  })
}
// [F3, 20-11-2026] Un error de señal o de sesión (42501 «No autorizado», JWT
// vencido, red) NO es un rechazo: antes quedaba «rechazada» para siempre.
const esRechazo = (e: unknown) => !esTransitorio(e) && !esDuplicado(e) && !!e && typeof e === 'object' && 'code' in e
  && typeof (e as { code: unknown }).code === 'string' && (e as { code: string }).code !== ''
const mensaje = (e: unknown) => (e instanceof Error ? e.message : typeof e === 'object' && e && 'message' in e ? String((e as { message: unknown }).message) : String(e))
const K = (faenaId: string) => `bitacora:${faenaId}`

/** Bitácora: con señal la baja y la guarda; sin señal, la última guardada. */
export async function getBitacora(faenaId: string, forzar = false): Promise<{ data: Bitacora | null; guardada_at: string | null }> {
  const row = await db().cache.get(K(faenaId))
  const reciente = row && Date.now() - new Date(row.updated_at).getTime() < 30_000
  if (isOnline() && (forzar || !reciente)) {
    try {
      const { data, error } = await conTimeout(supabase.rpc('rpc_faena_comunicacion', { p_faena_id: faenaId, p_dias: 7 }), 15000)
      if (error) throw error
      const ahora = new Date().toISOString()
      await db().cache.put({ key: K(faenaId), value: data, updated_at: ahora })
      return { data: data as Bitacora, guardada_at: ahora }
    } catch { /* se usa lo guardado */ }
  }
  return { data: (row?.value as Bitacora) ?? null, guardada_at: row?.updated_at ?? null }
}

/** Mezcla lo bajado con lo que está en la cola, para verlo al tiro. */
export function conCola(b: Bitacora, cola: OpBitacora[]): Bitacora {
  const pend = cola.filter((o) => o.sync_status === 'pending' && o.faena_id)
  const acusadas = new Set(pend.flatMap((o) => (o.tipo === 'acuse' ? o.ids : [])))
  const nuevasNov: Novedad[] = pend.filter((o): o is OpBitacora & OpNovedad => o.tipo === 'novedad').map((o) => ({
    id: o.local_id, fecha_hora: o.fecha_hora, turno: b.mi_turno, autor: o.autor ?? 'Yo', autor_id: null,
    categoria: o.categoria, severidad: o.severidad, texto: o.texto, foto_url: null, equipo: o.equipo,
    leida_por_mi: true, acuses: [], local: true,
  }))
  const nuevosPend: Pendiente[] = pend.filter((o): o is OpBitacora & OpPendiente => o.tipo === 'pendiente').map((o) => ({
    id: o.local_id, titulo: o.titulo, detalle: o.detalle || null, prioridad: o.prioridad, responsable_turno: o.responsable_turno,
    vence: o.vence, contingencia: o.contingencia || null, equipo: o.equipo, estado: 'abierto', creado_nombre: o.autor ?? 'Yo',
    created_at: o.created_at, cerrado_nombre: null, cerrado_at: null, cierre_nota: null, vencido: false, notas: [], local: true,
  }))
  const notas = pend.filter((o): o is OpBitacora & OpNota => o.tipo === 'nota')
  const pendientes = [...nuevosPend, ...b.pendientes].map((p) => {
    const mias = notas.filter((n) => n.pendiente_id === p.id)
    if (!mias.length) return p
    const cierre = mias.find((n) => n.cerrar)
    return {
      ...p,
      notas: [...p.notas, ...mias.map((n) => ({ autor: n.autor ?? 'Yo', texto: (n.cerrar ? 'CERRADO: ' : '') + n.texto, at: n.created_at }))],
      ...(cierre ? { estado: 'cerrado' as const, cierre_nota: cierre.texto, cerrado_nombre: cierre.autor ?? 'Yo', cerrado_at: cierre.created_at } : {}),
    }
  })
  return {
    ...b,
    novedades: [...nuevasNov, ...b.novedades.map((n) => (acusadas.has(n.id) ? { ...n, leida_por_mi: true } : n))],
    por_leer: b.por_leer.filter((id) => !acusadas.has(id)),
    pendientes,
  }
}

export async function guardarFotoLocal(file: File): Promise<string> {
  const blob = await compressImage(file, { maxDim: 1600, quality: 0.75 })
  const id = nuevoId()
  await db().blobs.put({ blob_id: id, blob })
  return id
}

type NuevaOp = (Omit<OpNovedad, never> | OpAcuse | OpPendiente | OpNota) & { faena_id: string; autor?: string | null }

/** Encola y, si hay señal, sube de inmediato. Devuelve si quedó arriba o en el teléfono. */
export async function registrar(op: NuevaOp): Promise<{ enviado: boolean; rechazo?: string }> {
  const fila = { ...op, local_id: nuevoId(), created_at: new Date().toISOString(), sync_status: 'pending', intentos: 0 } as OpBitacora
  await db().pending.put(fila)
  if (!isOnline()) return { enviado: false }
  return subirUna(fila)
}

async function subirUna(o: OpBitacora): Promise<{ enviado: boolean; rechazo?: string }> {
  try {
    if (o.tipo === 'novedad') {
      let foto: string | null = null
      if (o.foto_blob) {
        const b = await db().blobs.get(o.foto_blob)
        if (b) foto = await conTimeout(subirFotoPauta(b.blob), 30000)
      }
      const { error } = await conTimeout(supabase.rpc('rpc_faena_novedad_crear', {
        p_faena_id: o.faena_id, p_categoria: o.categoria, p_severidad: o.severidad, p_texto: o.texto,
        p_activo_id: o.activo_id, p_foto_url: foto, p_fecha_hora: o.fecha_hora, p_client_uuid: o.local_id,
      }), 15000)
      if (error) throw error
      if (o.foto_blob) await db().blobs.delete(o.foto_blob)
    } else if (o.tipo === 'acuse') {
      const ids = o.ids.filter((x) => /^[0-9a-f-]{36}$/i.test(x))
      if (ids.length) {
        const { error } = await conTimeout(supabase.rpc('rpc_faena_novedad_acusar', { p_ids: ids }), 15000)
        if (error) throw error
      }
    } else if (o.tipo === 'pendiente') {
      const { error } = await conTimeout(supabase.rpc('rpc_faena_pendiente_crear', {
        p_faena_id: o.faena_id, p_titulo: o.titulo, p_detalle: o.detalle, p_prioridad: o.prioridad,
        p_responsable_turno: o.responsable_turno, p_vence: o.vence, p_contingencia: o.contingencia,
        p_activo_id: o.activo_id, p_client_uuid: o.local_id,
      }), 15000)
      if (error) throw error
    } else {
      const { error } = await conTimeout(supabase.rpc('rpc_faena_pendiente_nota', {
        p_pendiente_id: o.pendiente_id, p_texto: o.texto, p_cerrar: o.cerrar, p_client_uuid: o.local_id,
      }), 15000)
      if (error) throw error
    }
    await db().pending.delete(o.local_id)
    return { enviado: true }
  } catch (e) {
    if (esDuplicado(e)) { await db().pending.delete(o.local_id); return { enviado: true } }
    if (esRechazo(e)) {
      await db().pending.update(o.local_id, { sync_status: 'rechazada', intentos: o.intentos + 1, ultimo_error: mensaje(e) })
      return { enviado: false, rechazo: mensaje(e) }
    }
    await db().pending.update(o.local_id, { intentos: o.intentos + 1, ultimo_error: mensaje(e) })
    return { enviado: false }
  }
}

export async function colaBitacora(): Promise<OpBitacora[]> {
  return db().pending.orderBy('created_at').toArray()
}
export async function pendientesCount(): Promise<number> {
  return db().pending.where('sync_status').equals('pending').count()
}
export async function descartar(localId: string) {
  const o = await db().pending.get(localId)
  if (o?.tipo === 'novedad' && o.foto_blob) await db().blobs.delete(o.foto_blob)
  await db().pending.delete(localId)
}

/**
 * Sube en orden. Una nota sobre un pendiente creado sin señal espera a que su
 * pendiente suba (su id local no existe en el servidor): se salta y reintenta.
 */
export async function sincronizar(): Promise<{ ok: number; error: number; rechazadas: number }> {
  // [20-11-2026] Sin sesión válida no se sube: el servidor lo rechazaría como anónimo.
  if (!haySesionServidor()) return { ok: 0, error: 0, rechazadas: 0 }
  if (!isOnline()) return { ok: 0, error: 0, rechazadas: 0 }
  const cola = await db().pending.where('sync_status').equals('pending').sortBy('created_at')
  const localesPend = new Set(cola.filter((o) => o.tipo === 'pendiente').map((o) => o.local_id))
  let ok = 0, error = 0, rechazadas = 0
  for (const o of cola) {
    if (o.tipo === 'nota' && localesPend.has(o.pendiente_id)) {
      // El pendiente subió con client_uuid = su local_id; su id real se resuelve desde el servidor.
      const { data } = await supabase.from('faena_pendientes').select('id').eq('client_uuid', o.pendiente_id).maybeSingle()
      if (!data?.id) continue
      await db().pending.update(o.local_id, { pendiente_id: data.id } as Partial<OpBitacora>)
      ;(o as OpNota).pendiente_id = data.id
    }
    const r = await subirUna(o)
    if (r.enviado) { ok += 1; if (o.tipo === 'pendiente') localesPend.add(o.local_id) }
    else if (r.rechazo) rechazadas += 1
    else { error += 1; break }
  }
  return { ok, error, rechazadas }
}
