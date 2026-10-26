import { describe, it, expect, beforeEach, vi } from 'vitest'

// Cola «Por enviar» de la app ENEX con señal de faena: intermitente, o antena
// que acepta la conexión y no cursa datos. Lo que se prueba es lo que hacía
// inservible la app: el envío que se corta y vuelve a subir todo, el botón
// Guardar que queda girando, y fotos borradas del teléfono que la pantalla
// todavía usa.

type Row = Record<string, unknown>
function tabla(pk: string) {
  const m = new Map<string, Row>()
  return {
    m,
    get: async (k: string) => (m.has(k) ? { ...m.get(k)! } : undefined),
    put: async (r: Row) => { m.set(r[pk] as string, { ...r }) },
    update: async (k: string, patch: Row) => { if (m.has(k)) m.set(k, { ...m.get(k)!, ...patch }); return m.has(k) ? 1 : 0 },
    delete: async (k: string) => { m.delete(k) },
    toArray: async () => Array.from(m.values()).map((r) => ({ ...r })),
    bulkGet: async (ks: string[]) => ks.map((k) => (m.has(k) ? { ...m.get(k)! } : undefined)),
    bulkDelete: async (ks: string[]) => { ks.forEach((k) => m.delete(k)) },
    each: async (fn: (r: Row) => void) => { Array.from(m.values()).forEach((r) => fn(r)) },
    count: async () => m.size,
    where: (campo: string) => ({
      equals: (v: string) => ({
        delete: async () => { for (const [k, r] of Array.from(m.entries())) if (r[campo] === v) m.delete(k) },
        first: async () => Array.from(m.values()).find((r) => r[campo] === v),
      }),
      startsWith: (pre: string) => ({ toArray: async () => Array.from(m.values()).filter((r) => String(r[campo]).startsWith(pre)) }),
    }),
  }
}

const db = { pending: tabla('local_id'), blobs: tabla('blob_id'), drafts: tabla('programacion_id'), cache: tabla('key') }
let seq = 0
vi.mock('@/lib/offline/enex-db', () => ({ enexDB: () => db, newId: () => `id${++seq}` }))

const subirEvidenciaEnex = vi.fn()
const ejecutarPauta = vi.fn()
vi.mock('@/lib/services/enex', () => ({
  getTerrenoPendientes: vi.fn(), getPautaItems: vi.fn(), getEjecucionItems: vi.fn(),
  getPendientePorId: vi.fn(), getPlanTareasDia: vi.fn(),
  subirEvidenciaEnex: (...a: unknown[]) => subirEvidenciaEnex(...a),
  subirFirmaEnex: vi.fn(async () => 'https://s/firma.png'),
  ejecutarPauta: (...a: unknown[]) => ejecutarPauta(...a),
}))

const foto = () => new File([new Uint8Array([1, 2, 3])], 'f.jpg', { type: 'image/jpeg' })

async function encolarConFotos(n: number) {
  const { queueEjecucion } = await import('@/lib/offline/enex-offline')
  return queueEjecucion({
    programacionId: 'prog-1', conMandante: false, reemplazar: true,
    items: [{ pauta_item_id: 'it-1', resultado: 'ok', antesFiles: Array.from({ length: n }, foto) }],
  })
}

beforeEach(() => {
  vi.useRealTimers()
  Object.values(db).forEach((t) => t.m.clear())
  subirEvidenciaEnex.mockReset()
  ejecutarPauta.mockReset()
  vi.stubGlobal('navigator', { onLine: false })
})

describe('cola ENEX con señal intermitente', () => {
  it('un corte a la mitad no vuelve a subir las fotos que ya llegaron', async () => {
    await encolarConFotos(3) // sin señal: queda en el teléfono
    const { syncEnexPending, getBandejaEnex } = await import('@/lib/offline/enex-offline')
    vi.stubGlobal('navigator', { onLine: true })

    let n = 0
    subirEvidenciaEnex.mockImplementation(async () => {
      n++
      if (n === 3) throw new Error('Failed to fetch') // se cae en la tercera
      return `https://s/${n}.jpg`
    })
    expect(await syncEnexPending()).toEqual({ ok: 0, failed: 1 })
    const [fila] = await getBandejaEnex()
    expect(fila).toMatchObject({ estado: 'error', fotos_total: 3, fotos_subidas: 2, motivo: 'Señal insuficiente para terminar el envío' })

    // Vuelve la señal: solo sube la que faltaba.
    subirEvidenciaEnex.mockReset()
    subirEvidenciaEnex.mockResolvedValue('https://s/3.jpg')
    ejecutarPauta.mockResolvedValue({})
    expect(await syncEnexPending()).toEqual({ ok: 1, failed: 0 })
    expect(subirEvidenciaEnex).toHaveBeenCalledTimes(1)
    const payload = ejecutarPauta.mock.calls[0][0] as { items: { fotos_antes: string[] }[] }
    expect(payload.items[0].fotos_antes).toEqual(['https://s/1.jpg', 'https://s/2.jpg', 'https://s/3.jpg'])
    expect(db.pending.m.size).toBe(0)
  })

  it('Guardar no queda girando con una antena que no cursa datos', async () => {
    vi.useFakeTimers()
    vi.stubGlobal('navigator', { onLine: true })
    subirEvidenciaEnex.mockReturnValue(new Promise(() => {})) // nunca contesta

    const p = encolarConFotos(1)
    await vi.advanceTimersByTimeAsync(15_000)
    expect(await p).toEqual({ synced: false, error: null })
    // Lo guardado está en el teléfono.
    expect(db.pending.m.size).toBe(1)
    expect(db.blobs.m.size).toBe(1)

    // El envío sigue por detrás y se corta solo por su techo de tiempo.
    await vi.advanceTimersByTimeAsync(90_000)
    const fila = Array.from(db.pending.m.values())[0]
    expect(fila.sync_status).toBe('error')
  })

  it('dos envíos a la vez no suben dos veces la misma foto', async () => {
    await encolarConFotos(2)
    const { syncEnexPending } = await import('@/lib/offline/enex-offline')
    vi.stubGlobal('navigator', { onLine: true })
    let n = 0
    subirEvidenciaEnex.mockImplementation(async () => `https://s/${++n}.jpg`)
    ejecutarPauta.mockResolvedValue({})

    await Promise.all([syncEnexPending(), syncEnexPending(), syncEnexPending()])
    expect(subirEvidenciaEnex).toHaveBeenCalledTimes(2)
    expect(ejecutarPauta).toHaveBeenCalledTimes(1)
  })

  it('no borra del teléfono una foto que el borrador del servicio todavía usa', async () => {
    const { guardarFotoLocal, guardarDraft, queueEjecucion, syncEnexPending } = await import('@/lib/offline/enex-offline')
    const blobId = await guardarFotoLocal(foto())
    await guardarDraft({ programacion_id: 'prog-1', items: { 'it-1': { resultado: 'ok', antes: [{ id: blobId, blob_id: blobId }], despues: [] } } })
    await queueEjecucion({ programacionId: 'prog-1', conMandante: false, reemplazar: true,
      items: [{ pauta_item_id: 'it-1', resultado: 'ok', antesBlobIds: [blobId] }] })

    vi.stubGlobal('navigator', { onLine: true })
    subirEvidenciaEnex.mockResolvedValue('https://s/a.jpg')
    ejecutarPauta.mockResolvedValue({})
    await syncEnexPending()
    // La pantalla sigue abierta y su autoguardado vuelve a anotar el id local.
    await guardarDraft({ programacion_id: 'prog-1', items: { 'it-1': { resultado: 'ok', antes: [{ id: blobId, blob_id: blobId }], despues: [] } } })
    await syncEnexPending()
    expect(db.blobs.m.has(blobId)).toBe(true)

    // Un segundo «Guardar avance» reusa la URL: ni la vuelve a subir ni la pierde.
    await queueEjecucion({ programacionId: 'prog-1', conMandante: false, reemplazar: true,
      items: [{ pauta_item_id: 'it-1', resultado: 'ok', antesBlobIds: [blobId] }] })
    expect(subirEvidenciaEnex).toHaveBeenCalledTimes(1)
    const ultimo = ejecutarPauta.mock.calls.at(-1)![0] as { items: { fotos_antes: string[] }[] }
    expect(ultimo.items[0].fotos_antes).toEqual(['https://s/a.jpg'])

    // Cerrado el servicio (sin borrador), la foto ya subida sale del teléfono.
    const { borrarDraft } = await import('@/lib/offline/enex-offline')
    await borrarDraft('prog-1')
    await syncEnexPending()
    expect(db.blobs.m.has(blobId)).toBe(false)
  })
})
