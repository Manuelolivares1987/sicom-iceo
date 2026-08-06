import { describe, it, expect, beforeEach, vi, afterEach } from 'vitest'

// El operador de terreno entra con el token vencido y sin señal: la app tiene
// que arrancar con la sesión guardada en el teléfono en vez de quedarse en
// "Cargando…". Esto cubre la lectura de esa sesión desde el storage.

const store = new Map<string, string>()

vi.stubGlobal('localStorage', {
  get length() { return store.size },
  key: (i: number) => Array.from(store.keys())[i] ?? null,
  getItem: (k: string) => store.get(k) ?? null,
  setItem: (k: string, v: string) => { store.set(k, v) },
  removeItem: (k: string) => { store.delete(k) },
  clear: () => store.clear(),
})

const CLAVE = 'sb-gvmaucxgjnrxvgleyklf-auth-token'

function sesion(over: Record<string, unknown> = {}) {
  return {
    access_token: 'a', refresh_token: 'r',
    expires_at: Math.floor(Date.now() / 1000) + 3600,
    user: { id: 'u-1', email: 'supervisor.combustible@sicom-iceo.cl' },
    ...over,
  }
}

let leerSesionPersistida: typeof import('../supabase')['leerSesionPersistida']

beforeEach(async () => {
  store.clear()
  vi.resetModules()
  ;({ leerSesionPersistida } = await import('../supabase'))
})

afterEach(() => vi.unstubAllEnvs())

describe('leerSesionPersistida', () => {
  it('devuelve el usuario guardado aunque el token esté vencido', () => {
    store.set(CLAVE, JSON.stringify(sesion({ expires_at: Math.floor(Date.now() / 1000) - 60 })))

    const r = leerSesionPersistida()

    expect(r?.user.id).toBe('u-1')
    expect(r?.expirada).toBe(true)
  })

  it('lee también el formato base64 que usa supabase-js', () => {
    const json = JSON.stringify(sesion())
    const b64 = Buffer.from(json, 'utf-8').toString('base64')
    store.set(CLAVE, `base64-${b64}`)

    expect(leerSesionPersistida()?.user.id).toBe('u-1')
  })

  it('no inventa sesión si no hay refresh_token', () => {
    store.set(CLAVE, JSON.stringify(sesion({ refresh_token: undefined })))
    expect(leerSesionPersistida()).toBeNull()
  })

  it('no inventa sesión si el storage está vacío o corrupto', () => {
    expect(leerSesionPersistida()).toBeNull()
    store.set(CLAVE, '{no es json')
    expect(leerSesionPersistida()).toBeNull()
  })

  it('ignora claves que no son del token de sesión', () => {
    store.set('sicom-perfil-cache', JSON.stringify({ id: 'u-1' }))
    expect(leerSesionPersistida()).toBeNull()
  })
})
