import { describe, it, expect, vi, afterEach } from 'vitest'

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/

describe('uuidV4 en un teléfono con visor antiguo (sin crypto.randomUUID)', () => {
  const original = Object.getOwnPropertyDescriptor(globalThis.crypto, 'randomUUID')
  afterEach(() => {
    if (original) Object.defineProperty(globalThis.crypto, 'randomUUID', original)
    vi.resetModules()
  })

  it('genera UUID v4 válidos y distintos, y completa crypto.randomUUID', async () => {
    Object.defineProperty(globalThis.crypto, 'randomUUID', { value: undefined, configurable: true, writable: true })
    vi.resetModules()
    const { uuidV4 } = await import('../uuid')
    const ids = new Set(Array.from({ length: 500 }, () => uuidV4()))
    expect(ids.size).toBe(500)
    for (const id of Array.from(ids)) expect(id).toMatch(UUID)
    // El código que llama crypto.randomUUID() directo ya no se cae.
    expect(typeof globalThis.crypto.randomUUID).toBe('function')
    expect(globalThis.crypto.randomUUID()).toMatch(UUID)
  })

  it('con el nativo disponible, lo usa', async () => {
    vi.resetModules()
    const { uuidV4 } = await import('../uuid')
    expect(uuidV4()).toMatch(UUID)
  })
})
