// ============================================================================
// La pauta del mecánico, sin señal
// ----------------------------------------------------------------------------
// La pauta se hace parado frente al camión, en el patio, y ahí la antena va y
// viene. Hasta ahora el borrador quedaba en el teléfono pero abrir y cerrar
// necesitaban red: el mecánico llegaba al camión, la pantalla se quedaba
// cargando y volvía a sacar la libreta. Un sistema que falla en el lugar donde
// se usa no se usa.
//
// TRES COSAS TIENEN QUE FUNCIONAR SIN RED
//   · ABRIR LA JORNADA — qué equipos hay y qué le toca a cada uno
//   · ABRIR UNA PAUTA  — los ítems, con su ayuda y sus repuestos
//   · CERRARLA         — incluidas las fotos de los hallazgos
//
// LAS FOTOS ESPERAN EN EL TELÉFONO, COMPRIMIDAS
// Un turno con hallazgos son varias fotos y a 4 MB cada una llenan el
// IndexedDB. Cuando eso pasa el navegador desaloja o tira QuotaExceededError, y
// el mecánico pierde el día sin enterarse. Se comprimen antes de guardar, no
// antes de subir.
//
// `navigator.onLine` MIENTE: con antena sin datos dice «en línea» y la petición
// no falla, se queda colgada. Por eso todo lo que sale a la red lleva techo de
// tiempo — es la misma lección que costó el «Cargando…» eterno de ENEX.
// ============================================================================
import Dexie, { type Table } from 'dexie'
import { compressImage } from '@/lib/image/compress'
import {
  getAgenda, getItems, guardarPauta, subirFotoPauta,
  type PautaAgenda, type PautaItem, type Respuesta, type GuardarPautaInput,
} from '@/lib/services/faena-pauta'

export type PautaPendiente = Omit<GuardarPautaInput, 'items'> & {
  local_id: string
  created_at: string
  sync_status: 'pending' | 'error'
  intentos: number
  ultimo_error?: string | null
  // Las respuestas con la foto todavía en el teléfono: `foto_blob` es un id
  // local, no una URL. Se cambia por la URL recién al subir.
  items: (Respuesta & { foto_blob?: string | null })[]
  // Para poder mostrarlo en la lista sin catálogo a mano.
  equipo_nombre?: string | null
  pauta_nombre?: string | null
}

type CacheRow = { key: string; value: unknown; updated_at: string }
type BlobRow = { blob_id: string; blob: Blob }

class PautaDB extends Dexie {
  cache!: Table<CacheRow, string>
  pending!: Table<PautaPendiente, string>
  blobs!: Table<BlobRow, string>

  constructor() {
    super('sicom-faena-pauta')
    this.version(1).stores({
      cache: 'key, updated_at',
      pending: 'local_id, sync_status, created_at',
      blobs: 'blob_id',
    })
  }
}

let _db: PautaDB | null = null
export function pautaDB(): PautaDB {
  if (typeof window === 'undefined') throw new Error('pautaDB() solo en cliente')
  if (!_db) _db = new PautaDB()
  return _db
}

const nuevoId = () =>
  (typeof crypto !== 'undefined' && crypto.randomUUID)
    ? crypto.randomUUID()
    : `${Date.now()}-${Math.random().toString(36).slice(2)}`

const isOnline = () => (typeof navigator === 'undefined' ? true : navigator.onLine)

/** Techo de tiempo: con antena sin datos la petición no falla, se cuelga. */
function conTimeout<T>(p: Promise<T>, ms = 8000): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const t = setTimeout(() => reject(new Error('timeout de red')), ms)
    p.then((v) => { clearTimeout(t); resolve(v) }, (e) => { clearTimeout(t); reject(e) })
  })
}

// ── Catálogo ────────────────────────────────────────────────────────────────
const K_AGENDA = (faenaId: string) => `agenda:${faenaId}`
const K_ITEMS  = (pautaId: string) => `items:${pautaId}`

/** La jornada. Con red la refresca y la deja bajada; sin red, la última bajada. */
export async function getAgendaOffline(faenaId: string): Promise<PautaAgenda[] | null> {
  if (isOnline()) {
    try {
      const ag = await conTimeout(getAgenda(faenaId))
      await pautaDB().cache.put({ key: K_AGENDA(faenaId), value: ag, updated_at: new Date().toISOString() })
      return ag
    } catch { /* se cae a lo descargado */ }
  }
  const row = await pautaDB().cache.get(K_AGENDA(faenaId))
  return (row?.value as PautaAgenda[]) ?? null
}

export async function getItemsOffline(pautaId: string): Promise<PautaItem[] | null> {
  if (isOnline()) {
    try {
      const its = await conTimeout(getItems(pautaId))
      await pautaDB().cache.put({ key: K_ITEMS(pautaId), value: its, updated_at: new Date().toISOString() })
      return its
    } catch { /* se cae a lo descargado */ }
  }
  const row = await pautaDB().cache.get(K_ITEMS(pautaId))
  return (row?.value as PautaItem[]) ?? null
}

/**
 * Deja el teléfono listo antes de subir al patio: la agenda y los ítems de
 * TODAS las pautas de la faena. Es lo que hay que tocar el lunes con señal.
 */
export async function descargarTodo(faenaId: string): Promise<{ pautas: number; items: number }> {
  const ag = await getAgenda(faenaId)
  await pautaDB().cache.put({ key: K_AGENDA(faenaId), value: ag, updated_at: new Date().toISOString() })

  const pautas = Array.from(new Set(ag.map((a) => a.pauta_id)))
  let items = 0
  for (const p of pautas) {
    const its = await getItems(p)
    await pautaDB().cache.put({ key: K_ITEMS(p), value: its, updated_at: new Date().toISOString() })
    items += its.length
  }
  return { pautas: pautas.length, items }
}

export async function ultimaDescarga(faenaId: string): Promise<string | null> {
  const row = await pautaDB().cache.get(K_AGENDA(faenaId))
  return row?.updated_at ?? null
}

// ── Fotos ───────────────────────────────────────────────────────────────────
export async function guardarFotoLocal(file: File | Blob): Promise<string> {
  const blob = await compressImage(file, { maxDim: 1600, quality: 0.75 })
  const blob_id = nuevoId()
  await pautaDB().blobs.put({ blob_id, blob })
  return blob_id
}

export async function getFotoLocal(blobId: string): Promise<Blob | null> {
  return (await pautaDB().blobs.get(blobId))?.blob ?? null
}

/** URL para mostrar la foto que todavía no sube. */
export async function urlFotoLocal(blobId: string): Promise<string | null> {
  const b = await getFotoLocal(blobId)
  return b ? URL.createObjectURL(b) : null
}

// ── Cola ────────────────────────────────────────────────────────────────────

/**
 * Guarda la pauta. Si hay red la manda de una; si no, queda esperando y sube
 * sola. El resultado dice cuál de las dos pasó, para poder decírselo a la
 * persona con la verdad.
 */
export async function guardarPautaOffline(
  p: Omit<GuardarPautaInput, 'items'> & {
    items: (Respuesta & { foto_blob?: string | null })[]
    equipoNombre?: string | null
    pautaNombre?: string | null
  },
): Promise<{ enviado: boolean; resultado?: Awaited<ReturnType<typeof guardarPauta>> }> {
  const pend: PautaPendiente = {
    ...p,
    local_id: nuevoId(),
    created_at: new Date().toISOString(),
    sync_status: 'pending',
    intentos: 0,
    equipo_nombre: p.equipoNombre ?? null,
    pauta_nombre: p.pautaNombre ?? null,
  }
  await pautaDB().pending.put(pend)

  if (isOnline()) {
    const r = await sincronizar()
    // Si subió, devolvemos lo que dijo el servidor: cuántas no conformidades
    // levantó es lo que el mecánico necesita ver.
    if (r.ok > 0 && r.ultimo) return { enviado: true, resultado: r.ultimo }
    // Quedó en la cola con error: no es una falla que detenga al mecánico, la
    // pauta está guardada. Pero tampoco se le miente diciendo que se envió.
    return { enviado: false }
  }
  return { enviado: false }
}

export async function pendientesCount(): Promise<number> {
  return pautaDB().pending.count()
}

export async function pendientes(): Promise<PautaPendiente[]> {
  return pautaDB().pending.orderBy('created_at').toArray()
}

export async function descartarPendiente(localId: string): Promise<void> {
  const p = await pautaDB().pending.get(localId)
  if (p) {
    for (const i of p.items) if (i.foto_blob) await pautaDB().blobs.delete(i.foto_blob)
  }
  await pautaDB().pending.delete(localId)
}

export async function sincronizar(): Promise<{
  ok: number; error: number
  ultimo?: Awaited<ReturnType<typeof guardarPauta>>
}> {
  if (!isOnline()) return { ok: 0, error: 0 }
  const cola = await pautaDB().pending.orderBy('created_at').toArray()
  let ok = 0, error = 0
  let ultimo: Awaited<ReturnType<typeof guardarPauta>> | undefined

  for (const p of cola) {
    try {
      // Primero las fotos: sin ellas el cierre rebota por el gate de evidencia,
      // y rebotar por una foto que sí se sacó sería el peor de los errores.
      const items: Respuesta[] = []
      for (const i of p.items) {
        let url = i.foto_url ?? null
        if (!url && i.foto_blob) {
          const blob = await getFotoLocal(i.foto_blob)
          if (blob) url = await conTimeout(subirFotoPauta(blob), 30000)
        }
        items.push({
          item_id: i.item_id, resultado: i.resultado ?? null, valor: i.valor ?? null,
          texto: i.texto ?? null, observacion: i.observacion ?? null, foto_url: url,
        })
      }

      const r = await conTimeout(guardarPauta({ ...p, items }), 20000)
      ultimo = r
      for (const i of p.items) if (i.foto_blob) await pautaDB().blobs.delete(i.foto_blob)
      await pautaDB().pending.delete(p.local_id)
      ok += 1
    } catch (e) {
      error += 1
      await pautaDB().pending.update(p.local_id, {
        sync_status: 'error',
        intentos: (p.intentos ?? 0) + 1,
        ultimo_error: e instanceof Error ? e.message : String(e),
      })
    }
  }
  return { ok, error, ultimo }
}
