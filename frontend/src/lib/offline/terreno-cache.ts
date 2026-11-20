// ============================================================================
// Caché de lectura de la app de terreno (F3, 20-11-2026)
// ----------------------------------------------------------------------------
// «Primero la red con límite de tiempo; si no contesta, lo último guardado».
// Para las pantallas que antes solo funcionaban con señal (carga del camión,
// el turno). Cada respuesta buena queda guardada en el teléfono.
// ============================================================================

import Dexie, { type Table } from 'dexie'
import { estaEnLinea } from '@/lib/conectividad'

type Fila = { key: string; value: unknown; updated_at: string }

class TerrenoCacheDB extends Dexie {
  cache!: Table<Fila, string>
  constructor() {
    super('sicom-terreno-cache')
    this.version(1).stores({ cache: 'key, updated_at' })
  }
}
let _db: TerrenoCacheDB | null = null
const db = () => (_db ??= new TerrenoCacheDB())

export async function cacheLeer<T>(key: string): Promise<{ value: T; updated_at: string } | null> {
  try {
    const f = await db().cache.get(key)
    return f ? { value: f.value as T, updated_at: f.updated_at } : null
  } catch { return null }
}

export async function cacheGuardar(key: string, value: unknown): Promise<void> {
  try { await db().cache.put({ key, value, updated_at: new Date().toISOString() }) } catch { /* sin IndexedDB */ }
}

function conLimite<T>(p: Promise<T>, ms: number): Promise<T> {
  return new Promise<T>((ok, mal) => {
    const t = setTimeout(() => mal(new Error('timeout de red')), ms)
    p.then((v) => { clearTimeout(t); ok(v) }, (e) => { clearTimeout(t); mal(e) })
  })
}

/**
 * Trae de la red (máx. `ms`) y guarda; si no hay red o falla, devuelve lo
 * guardado. Sin nada guardado, relanza el error.
 */
export async function conRespaldo<T>(key: string, traer: () => Promise<T>, ms = 8000): Promise<T> {
  if (estaEnLinea()) {
    try {
      const v = await conLimite(traer(), ms)
      void cacheGuardar(key, v)
      return v
    } catch (e) {
      const c = await cacheLeer<T>(key)
      if (c) return c.value
      throw e
    }
  }
  const c = await cacheLeer<T>(key)
  if (c) return c.value
  throw new Error('Sin señal y sin datos guardados en este teléfono. Ábralo una vez con señal.')
}
