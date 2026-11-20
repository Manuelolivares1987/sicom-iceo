import 'fake-indexeddb/auto'
import { beforeEach, describe, expect, it, vi } from 'vitest'

let enLinea = true
let conSesion = true
vi.mock('@/lib/conectividad', () => ({ estaEnLinea: () => enLinea }))
vi.mock('@/lib/supabase', () => ({
  haySesionServidor: () => conSesion,
  leerSesionPersistida: () => ({ user: { id: 'u1' } }),
}))

const B = await import('@/lib/offline/bandeja')

const errorPg = (code: string, message: string) => Object.assign(new Error(message), { code })

describe('bandeja de salida de terreno', () => {
  beforeEach(async () => {
    enLinea = true; conSesion = true
    for (const o of await B.listarBandeja()) await B.descartar(o.id)
  })

  it('clasifica errores: señal/sesión esperan, duplicado = subido, regla = rechazo', () => {
    expect(B.esTransitorio(new TypeError('Failed to fetch'))).toBe(true)
    expect(B.esTransitorio(errorPg('42501', 'No autorizado'))).toBe(true)
    expect(B.esTransitorio(errorPg('PGRST301', 'JWT expired'))).toBe(true)
    expect(B.esDuplicado(errorPg('23505', 'duplicate key'))).toBe(true)
    expect(B.esTransitorio(errorPg('P0001', 'El folio ya fue usado en otra carga'))).toBe(false)
  })

  it('sube, no duplica el mismo identificador y no re-sube la foto ya subida', async () => {
    let intentos = 0
    const subirFoto = vi.fn(async () => 'https://s/foto.jpg')
    B.registrarTipo('t-ok', async (_op, subirBlob) => {
      await subirBlob('foto', subirFoto)
      intentos++
      if (intentos === 1) throw new TypeError('Failed to fetch') // se corta después de subir la foto
    })
    await B.encolar({ id: 'x1', tipo: 't-ok', resumen: 'r', payload: {}, blobs: { foto: new Blob(['a']) } })
    await B.encolar({ id: 'x1', tipo: 't-ok', resumen: 'r', payload: {} })
    expect((await B.listarBandeja()).length).toBe(1)

    expect(await B.sincronizarBandeja()).toBe(0)
    const tras = (await B.listarBandeja())[0]
    expect(tras.estado).toBe('pendiente')
    expect(tras.proximo_at).toBeGreaterThan(Date.now()) // espera antes de reintentar

    expect(await B.sincronizarBandeja(true)).toBe(1)
    expect(await B.contarBandeja()).toBe(0)
    expect(subirFoto).toHaveBeenCalledTimes(1)
  })

  it('sin sesión no intenta nada (no se marca rechazado)', async () => {
    const m = vi.fn(async () => undefined)
    B.registrarTipo('t-ses', m)
    await B.encolar({ id: 's1', tipo: 't-ses', resumen: 'r', payload: {} })
    conSesion = false
    expect(await B.sincronizarBandeja(true)).toBe(0)
    expect(m).not.toHaveBeenCalled()
    expect((await B.listarBandeja())[0].estado).toBe('pendiente')
  })

  it('duplicado en el servidor = ya estaba: se da por subido', async () => {
    B.registrarTipo('t-dup', async () => { throw errorPg('23505', 'duplicate key') })
    await B.encolar({ id: 'd1', tipo: 't-dup', resumen: 'r', payload: {} })
    expect(await B.sincronizarBandeja(true)).toBe(1)
    expect(await B.contarBandeja()).toBe(0)
  })

  it('regla de negocio: queda rechazada con el motivo, sin reintentos', async () => {
    B.registrarTipo('t-rech', async () => { throw errorPg('P0001', 'El camión no existe') })
    await B.encolar({ id: 'r1', tipo: 't-rech', resumen: 'r', payload: {} })
    await B.sincronizarBandeja(true)
    const o = (await B.listarBandeja())[0]
    expect(o.estado).toBe('rechazada')
    expect(o.error).toContain('El camión no existe')
  })
})
