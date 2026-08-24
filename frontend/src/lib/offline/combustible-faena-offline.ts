// Capa offline del despacho de combustible en faena.
//
// En Romeral la señal es mala de verdad, así que el operador tiene que poder
// trabajar el turno completo sin conexión: el catálogo queda bajado en el
// teléfono y cada despacho se guarda local y sube cuando hay red.
//
// Cada despacho lleva un client_uuid: si el envío se reintenta, el servidor
// devuelve el mismo registro en vez de duplicar el litraje.

import Dexie, { type Table } from 'dexie'
import {
  getCatalogoFaena, registrarDespacho, getDespachosDia, subirFotoMedidor,
  trasvasijar, declararMomentoCero,
  type CatalogoFaena, type CombDespacho, type DespachoInput,
} from '@/lib/services/combustible-faena'
import { compressImage } from '@/lib/image/compress'

export type DespachoPendiente = DespachoInput & {
  local_id: string
  client_uuid: string
  created_at: string
  sync_status: 'pending' | 'error'
  intentos: number
  ultimo_error?: string | null
  // Copia de los nombres para poder mostrarlo sin catálogo a mano
  equipo_nombre?: string | null
  ceco_nombre?: string | null
  ubicacion_nombre?: string | null
  camion_nombre?: string | null
  // [MIG281] Las fotos del medidor esperan en el teléfono junto con la carga:
  // se sacan sin señal y suben cuando aparece red.
  foto_ini_blob?: string | null
  foto_fin_blob?: string | null
}

/**
 * [MIG378] Los otros dos movimientos de terreno. El despacho tiene su propia
 * cola desde MIG279 porque es lo de todos los días; estos dos llegaron después
 * y necesitan lo mismo: en Romeral la señal es mala de verdad, y una pantalla
 * que carga sin red pero no guarda es peor que una que no carga — el operador
 * llena todo y lo pierde al apretar el botón.
 *
 * Las fotos viajan por `blob_id`: se guardan en el teléfono y se resuelven a
 * URL recién cuando hay red, igual que las del medidor.
 */
export type MovimientoPendiente = {
  local_id: string
  tipo: 'trasvasije' | 'momento_cero'
  client_uuid: string
  created_at: string
  sync_status: 'pending' | 'error'
  intentos: number
  ultimo_error?: string | null
  /** Lo que se le manda al RPC, con los blob_id donde van las URLs. */
  payload: Record<string, unknown>
  /** Qué campos del payload son blob_id que hay que subir antes. */
  fotos: { campo: string; blob_id: string; indice?: number }[]
  /** Para poder mostrarlo en la lista sin catálogo a mano. */
  resumen: string
}

type CacheRow = { key: string; value: unknown; updated_at: string }
type BlobRow = { blob_id: string; blob: Blob; mime: string }

class CombFaenaDB extends Dexie {
  cache!: Table<CacheRow, string>
  pending!: Table<DespachoPendiente, string>
  blobs!: Table<BlobRow, string>
  movimientos!: Table<MovimientoPendiente, string>

  constructor() {
    super('sicom-combustible-faena')
    this.version(1).stores({
      cache: 'key, updated_at',
      pending: 'local_id, sync_status, created_at',
    })
    // v2: fotos del medidor guardadas en el teléfono hasta que haya señal
    this.version(2).stores({
      cache: 'key, updated_at',
      pending: 'local_id, sync_status, created_at',
      blobs: 'blob_id',
    })
    // v3: el trasvasije y el momento cero también esperan en el teléfono
    this.version(3).stores({
      cache: 'key, updated_at',
      pending: 'local_id, sync_status, created_at',
      blobs: 'blob_id',
      movimientos: 'local_id, tipo, sync_status, created_at',
    })
  }
}

/** Guarda una foto en el teléfono y devuelve su id local. */
export async function guardarFotoLocal(file: File | Blob): Promise<string> {
  // Se comprime antes de guardar, no antes de subir: un turno sin señal son
  // cerca de cien fotos, y a 4 MB cada una llenan el IndexedDB del teléfono.
  // Cuando eso pasa el navegador desaloja o tira QuotaExceededError, y el
  // operador pierde el día sin enterarse. Falla segura: si el aparato no
  // puede procesarla, se guarda la original.
  const blob = await compressImage(file, { maxDim: 1600, quality: 0.75 })
  const blob_id = nuevoId()
  await combDB().blobs.put({ blob_id, blob, mime: 'image/jpeg' })
  return blob_id
}

export async function getFotoLocal(blobId: string): Promise<Blob | null> {
  const row = await combDB().blobs.get(blobId)
  return row?.blob ?? null
}

let _db: CombFaenaDB | null = null
export function combDB(): CombFaenaDB {
  if (typeof window === 'undefined') throw new Error('combDB() solo en cliente')
  if (!_db) _db = new CombFaenaDB()
  return _db
}

export function nuevoId(): string {
  return (typeof crypto !== 'undefined' && crypto.randomUUID)
    ? crypto.randomUUID()
    : `${Date.now()}-${Math.random().toString(36).slice(2)}`
}

const isOnline = () => (typeof navigator === 'undefined' ? true : navigator.onLine)

/**
 * `navigator.onLine` dice "en línea" también con antena sin datos —lo normal en
 * faena—, y ahí la petición no falla: se queda colgada. Sin este techo la
 * pantalla se queda cargando para siempre teniendo todo en el teléfono.
 */
function conTimeout<T>(p: Promise<T>, ms = 8000): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const t = setTimeout(() => reject(new Error('timeout de red')), ms)
    p.then((v) => { clearTimeout(t); resolve(v) }, (e) => { clearTimeout(t); reject(e) })
  })
}

// ── Catálogo ────────────────────────────────────────────────────────────────
const KEY_CAT = (codigo: string) => `catalogo:${codigo}`

export async function getCatalogoOffline(codigo: string): Promise<CatalogoFaena | null> {
  if (isOnline()) {
    try {
      const cat = await conTimeout(getCatalogoFaena(codigo))
      await combDB().cache.put({ key: KEY_CAT(codigo), value: cat, updated_at: new Date().toISOString() })
      return cat
    } catch { /* se cae a lo descargado */ }
  }
  const row = await combDB().cache.get(KEY_CAT(codigo))
  return (row?.value as CatalogoFaena) ?? null
}

/** Descarga forzada del catálogo, para dejar el teléfono listo antes de subir. */
export async function descargarCatalogo(codigo: string): Promise<number> {
  const cat = await getCatalogoFaena(codigo)
  await combDB().cache.put({ key: KEY_CAT(codigo), value: cat, updated_at: new Date().toISOString() })
  return cat.equipos.length
}

export async function ultimaDescarga(codigo: string): Promise<string | null> {
  const row = await combDB().cache.get(KEY_CAT(codigo))
  return row?.updated_at ?? null
}

// ── Cola de despachos ───────────────────────────────────────────────────────
export async function guardarDespacho(
  p: DespachoInput,
  etiquetas: Pick<DespachoPendiente,
    'equipo_nombre' | 'ceco_nombre' | 'ubicacion_nombre' | 'camion_nombre'
    | 'foto_ini_blob' | 'foto_fin_blob'>,
): Promise<{ enviado: boolean }> {
  const pend: DespachoPendiente = {
    ...p,
    local_id: nuevoId(),
    client_uuid: p.clientUuid ?? nuevoId(),
    created_at: new Date().toISOString(),
    sync_status: 'pending',
    intentos: 0,
    ...etiquetas,
  }
  pend.clientUuid = pend.client_uuid
  await combDB().pending.put(pend)

  if (isOnline()) {
    const r = await sincronizar()
    return { enviado: r.ok > 0 }
  }
  return { enviado: false }
}

export async function pendientesCount(): Promise<number> {
  return combDB().pending.count()
}

export async function pendientesDelDia(fecha: string): Promise<DespachoPendiente[]> {
  const todos = await combDB().pending.toArray()
  return todos.filter((p) => p.fecha === fecha)
}

/**
 * Sube lo que haya en cola: primero las fotos, después la carga con sus URLs.
 * Nunca borra sin confirmación del servidor.
 */
export async function sincronizar(): Promise<{ ok: number; failed: number }> {
  if (!isOnline()) return { ok: 0, failed: 0 }
  const cola = await combDB().pending.toArray()
  let ok = 0, failed = 0
  for (const p of cola) {
    try {
      // Las fotos van primero; si una ya subió antes, no se repite.
      let urlIni = p.fotoMeterInicial ?? null
      let urlFin = p.fotoMeterFinal ?? null
      if (!urlIni && p.foto_ini_blob) {
        const b = await getFotoLocal(p.foto_ini_blob)
        if (b) {
          urlIni = await conTimeout(subirFotoMedidor(b), 30_000)
          await combDB().pending.update(p.local_id, { fotoMeterInicial: urlIni })
        }
      }
      if (!urlFin && p.foto_fin_blob) {
        const b = await getFotoLocal(p.foto_fin_blob)
        if (b) {
          urlFin = await conTimeout(subirFotoMedidor(b), 30_000)
          await combDB().pending.update(p.local_id, { fotoMeterFinal: urlFin })
        }
      }

      await conTimeout(registrarDespacho({
        ...p, clientUuid: p.client_uuid,
        fotoMeterInicial: urlIni, fotoMeterFinal: urlFin,
      }), 20_000)

      // Confirmado por el servidor: recién ahí se sueltan las fotos locales.
      if (p.foto_ini_blob) await combDB().blobs.delete(p.foto_ini_blob)
      if (p.foto_fin_blob) await combDB().blobs.delete(p.foto_fin_blob)
      await combDB().pending.delete(p.local_id)
      ok++
    } catch (e) {
      failed++
      await combDB().pending.update(p.local_id, {
        sync_status: 'error', intentos: (p.intentos ?? 0) + 1,
        ultimo_error: (e as Error).message,
      })
    }
  }
  return { ok, failed }
}

/**
 * Lo del día: lo que ya está en el servidor más lo que sigue en el teléfono.
 * El operador tiene que ver su turno completo aunque no haya subido nada.
 */
export async function getDiaOffline(
  faenaId: string, fecha: string,
): Promise<{ servidor: CombDespacho[]; locales: DespachoPendiente[] }> {
  let servidor: CombDespacho[] = []
  if (isOnline()) {
    try { servidor = await conTimeout(getDespachosDia(faenaId, fecha)) } catch { /* sin red: solo lo local */ }
  }
  const locales = await pendientesDelDia(fecha)
  return { servidor, locales }
}

/** Descarta un despacho que todavía no subió (se anotó mal y aún no viaja). */
export async function descartarPendiente(localId: string) {
  await combDB().pending.delete(localId)
}

// ── Trasvasije y momento cero, también sin señal (MIG378) ───────────────────

/** Encola un trasvasije. Si hay red, se intenta subir de inmediato. */
export async function guardarTrasvasije(payload: {
  faenaId: string; fecha: string; turno?: string | null
  origenId: string; destinoId: string; litros: number; operador: string
  meterInicial?: number | null; meterFinal?: number | null
  sinFotoMotivo?: string | null; observacion?: string | null; hora?: string | null
}, fotos: { inicial?: string | null; final?: string | null }, resumen: string) {
  const mov: MovimientoPendiente = {
    local_id: nuevoId(),
    tipo: 'trasvasije',
    client_uuid: nuevoId(),
    created_at: new Date().toISOString(),
    sync_status: 'pending',
    intentos: 0,
    payload: { ...payload },
    fotos: [
      ...(fotos.inicial ? [{ campo: 'fotoInicial', blob_id: fotos.inicial }] : []),
      ...(fotos.final ? [{ campo: 'fotoFinal', blob_id: fotos.final }] : []),
    ],
    resumen,
  }
  await combDB().movimientos.put(mov)
  if (isOnline()) {
    const r = await sincronizarMovimientos()
    return { enviado: r.ok > 0 }
  }
  return { enviado: false }
}

/** Encola el momento cero. Las fotos de varilla van una por estanque. */
export async function guardarMomentoCero(payload: {
  faenaId: string; fecha: string; medidoPor: string
  puntos: { estanque_id: string; litros: number; lectura_cm?: number | null;
            sin_foto_motivo?: string | null }[]
  observacion?: string | null
}, fotosPunto: (string | null)[], firmaBlobId: string, resumen: string) {
  const mov: MovimientoPendiente = {
    local_id: nuevoId(),
    tipo: 'momento_cero',
    client_uuid: nuevoId(),
    created_at: new Date().toISOString(),
    sync_status: 'pending',
    intentos: 0,
    payload: { ...payload },
    fotos: [
      { campo: 'firmaUrl', blob_id: firmaBlobId },
      ...fotosPunto
        .map((b, i) => (b ? { campo: 'punto_foto', blob_id: b, indice: i } : null))
        .filter((x): x is { campo: string; blob_id: string; indice: number } => x !== null),
    ],
    resumen,
  }
  await combDB().movimientos.put(mov)
  if (isOnline()) {
    const r = await sincronizarMovimientos()
    return { enviado: r.ok > 0 }
  }
  return { enviado: false }
}

export async function movimientosPendientesCount(): Promise<number> {
  return combDB().movimientos.count()
}

export async function movimientosPendientes(): Promise<MovimientoPendiente[]> {
  return combDB().movimientos.orderBy('created_at').toArray()
}

export async function descartarMovimiento(localId: string) {
  const m = await combDB().movimientos.get(localId)
  if (m) for (const f of m.fotos) await combDB().blobs.delete(f.blob_id)
  await combDB().movimientos.delete(localId)
}

/**
 * Sube la cola de trasvasijes y momentos cero. Mismo trato que el despacho:
 * las fotos primero, el movimiento después, y nada se borra del teléfono hasta
 * que el servidor confirma.
 */
export async function sincronizarMovimientos(): Promise<{ ok: number; failed: number }> {
  if (!isOnline()) return { ok: 0, failed: 0 }
  const cola = await combDB().movimientos.toArray()
  let ok = 0, failed = 0

  for (const m of cola) {
    try {
      // Las fotos que aún no tienen URL se suben ahora y se anotan en el
      // payload, para que un reintento no las vuelva a subir.
      const payload = { ...m.payload } as Record<string, unknown>
      const puntos = Array.isArray(payload.puntos)
        ? [...(payload.puntos as Record<string, unknown>[])]
        : []

      for (const f of m.fotos) {
        const yaEsta = f.indice != null
          ? !!puntos[f.indice]?.foto_url
          : !!payload[f.campo]
        if (yaEsta) continue
        const b = await getFotoLocal(f.blob_id)
        if (!b) continue
        const url = await conTimeout(subirFotoMedidor(b), 30_000)
        if (f.indice != null) {
          puntos[f.indice] = { ...puntos[f.indice], foto_url: url }
        } else {
          payload[f.campo] = url
        }
      }
      if (puntos.length) payload.puntos = puntos
      await combDB().movimientos.update(m.local_id, { payload })

      if (m.tipo === 'trasvasije') {
        await conTimeout(trasvasijar({
          ...(payload as Parameters<typeof trasvasijar>[0]),
          clientUuid: m.client_uuid,
        }), 20_000)
      } else {
        await conTimeout(declararMomentoCero({
          ...(payload as Parameters<typeof declararMomentoCero>[0]),
          clientUuid: m.client_uuid,
        }), 30_000)
      }

      // Confirmado: recién ahí se sueltan las fotos del teléfono.
      for (const f of m.fotos) await combDB().blobs.delete(f.blob_id)
      await combDB().movimientos.delete(m.local_id)
      ok++
    } catch (e) {
      failed++
      await combDB().movimientos.update(m.local_id, {
        sync_status: 'error', intentos: (m.intentos ?? 0) + 1,
        ultimo_error: (e as Error).message,
      })
    }
  }
  return { ok, failed }
}
