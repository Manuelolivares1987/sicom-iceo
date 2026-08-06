import { describe, it, expect, beforeEach, vi } from 'vitest'

// En faena el teléfono suele quedar "en línea" pegado a una antena que no cursa
// datos: la petición no falla, se queda esperando. Sin techo de espera la
// pantalla se quedaba en "Cargando…" teniendo los servicios ya descargados.

const cache = new Map<string, unknown>()

vi.mock('@/lib/offline/enex-db', () => ({
  enexDB: () => ({
    cache: {
      get: async (k: string) => (cache.has(k) ? { key: k, value: cache.get(k) } : undefined),
      put: async (row: { key: string; value: unknown }) => { cache.set(row.key, row.value) },
      where: () => ({ startsWith: () => ({ toArray: async () => [] }) }),
    },
    pending: { toArray: async () => [], where: () => ({ equals: () => ({ first: async () => undefined }) }) },
  }),
  newId: () => 'id',
}))

const getTerrenoPendientes = vi.fn()
vi.mock('@/lib/services/enex', () => ({
  getTerrenoPendientes: (...a: unknown[]) => getTerrenoPendientes(...a),
  getPautaItems: vi.fn(), ejecutarPauta: vi.fn(), getEjecucionItems: vi.fn(),
  getPendientePorId: vi.fn(), subirEvidenciaEnex: vi.fn(), subirFirmaEnex: vi.fn(),
}))

const DESCARGADO = [{ programacion_id: 'p-1', instalacion: 'EESS Calama', cumplida: false }]

beforeEach(() => {
  cache.clear()
  getTerrenoPendientes.mockReset()
  vi.stubGlobal('navigator', { onLine: true })
})

describe('getPendientesOffline con la red colgada', () => {
  it('devuelve lo descargado en vez de esperar para siempre', async () => {
    vi.useFakeTimers()
    const { getPendientesOffline } = await import('@/lib/offline/enex-offline')
    cache.set('pend:2026-8', DESCARGADO)
    // La red acepta la conexión pero nunca responde.
    getTerrenoPendientes.mockReturnValue(new Promise(() => {}))

    const p = getPendientesOffline(2026, 8)
    await vi.advanceTimersByTimeAsync(8000)
    const r = await p

    expect(r).toEqual(DESCARGADO)
    vi.useRealTimers()
  })

  it('si la red responde a tiempo, usa el dato fresco y lo deja descargado', async () => {
    const { getPendientesOffline } = await import('@/lib/offline/enex-offline')
    const FRESCO = [{ programacion_id: 'p-2', instalacion: 'Truck Shop', cumplida: false }]
    getTerrenoPendientes.mockResolvedValue(FRESCO)

    expect(await getPendientesOffline(2026, 8)).toEqual(FRESCO)
    expect(cache.get('pend:2026-8')).toEqual(FRESCO)
  })
})
