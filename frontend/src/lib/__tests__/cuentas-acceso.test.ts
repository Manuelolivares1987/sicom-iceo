import { describe, it, expect } from 'vitest'
import { nuevoEnlaceAcceso, usarEnlaceAcceso, correoAcceso } from '../server/cuentas'

// Cliente admin falso: guarda app_metadata y la clave de UN usuario.
function adminFalso() {
  const user = { id: '11111111-1111-4111-8111-111111111111', email: 'operador@pillado.cl', app_metadata: { provider: 'email' } as Record<string, unknown> }
  const estado = { clave: null as string | null }
  const admin = {
    auth: {
      admin: {
        getUserById: async (id: string) => (id === user.id ? { data: { user: { ...user, app_metadata: { ...user.app_metadata } } }, error: null } : { data: { user: null }, error: { message: 'no' } }),
        updateUserById: async (_id: string, attrs: { app_metadata?: Record<string, unknown>; password?: string }) => {
          if (attrs.app_metadata) user.app_metadata = attrs.app_metadata
          if (attrs.password) estado.clave = attrs.password
          return { data: { user }, error: null }
        },
      },
    },
  }
  return { admin: admin as never, user, estado }
}
const tokenDe = (enlace: string) => new URL(enlace).searchParams.get('t')!

describe('enlace de acceso (crear mi clave)', () => {
  it('fija la clave y después el mismo enlace ya no sirve', async () => {
    const { admin, user, estado } = adminFalso()
    const { enlace } = await nuevoEnlaceAcceso(admin, user.id)
    expect(user.app_metadata.provider).toBe('email') // no pisa lo demás de app_metadata
    const r = await usarEnlaceAcceso(admin, user.id, tokenDe(enlace), 'clave-segura-1')
    expect(r.email).toBe('operador@pillado.cl')
    expect(estado.clave).toBe('clave-segura-1')
    expect(user.app_metadata.acceso).toBeUndefined()
    await expect(usarEnlaceAcceso(admin, user.id, tokenDe(enlace), 'otra-clave-22')).rejects.toThrow('ENLACE_INVALIDO')
  })

  it('rechaza un token alterado y no toca la clave', async () => {
    const { admin, user, estado } = adminFalso()
    const { enlace } = await nuevoEnlaceAcceso(admin, user.id)
    const t = tokenDe(enlace)
    const alterado = (t[0] === 'A' ? 'B' : 'A') + t.slice(1)
    await expect(usarEnlaceAcceso(admin, user.id, alterado, 'clave-segura-1')).rejects.toThrow('ENLACE_INVALIDO')
    expect(estado.clave).toBeNull()
  })

  it('un enlace nuevo invalida el anterior', async () => {
    const { admin, user } = adminFalso()
    const viejo = await nuevoEnlaceAcceso(admin, user.id)
    await nuevoEnlaceAcceso(admin, user.id)
    await expect(usarEnlaceAcceso(admin, user.id, tokenDe(viejo.enlace), 'clave-segura-1')).rejects.toThrow('ENLACE_INVALIDO')
  })

  it('un enlace vencido no sirve', async () => {
    const { admin, user } = adminFalso()
    const { enlace } = await nuevoEnlaceAcceso(admin, user.id)
    ;(user.app_metadata.acceso as { vence: string }).vence = new Date(Date.now() - 1000).toISOString()
    await expect(usarEnlaceAcceso(admin, user.id, tokenDe(enlace), 'clave-segura-1')).rejects.toThrow('ENLACE_VENCIDO')
  })
})

describe('correo de acceso', () => {
  it('escapa el nombre (sin HTML inyectado) y trae la app solo a terreno', () => {
    const c = correoAcceso({ nombre: '<img src=x onerror=alert(1)> Pérez', email: 'a@b.cl', enlace: 'https://x/crear-clave/?u=1&t=2', terreno: true })
    expect(c.html).not.toContain('<img src=x')
    expect(c.html).toContain('&lt;img')
    expect(c.html).toContain('sicom-terreno.apk')
    expect(correoAcceso({ nombre: 'Ana', email: 'a@b.cl', enlace: 'https://x', terreno: false }).html).not.toContain('sicom-terreno.apk')
  })
})
