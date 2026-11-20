import 'fake-indexeddb/auto'
import { beforeEach, describe, expect, it, vi } from 'vitest'

// [F4, MIG723] Entrega de turno sin señal: abrir con la plantilla, firmar,
// crear en el servidor al volver la señal, y que el reintento no se rechace.

let enLinea = false
Object.defineProperty(globalThis, 'navigator', { value: { get onLine() { return enLinea } }, configurable: true })

vi.mock('@/lib/supabase', () => ({ haySesionServidor: () => true, leerSesionPersistida: () => null }))
vi.mock('@/lib/conectividad', () => ({ estaEnLinea: () => enLinea }))

const S = vi.hoisted(() => ({
  abrirEntrega: vi.fn(), declararEntrega: vi.fn(), firmarEntrega: vi.fn(), recibirEntrega: vi.fn(),
  getContextoEntrega: vi.fn(), getPlantillaEntrega: vi.fn(), subirFirma: vi.fn(),
}))
vi.mock('@/lib/services/faena-entrega', () => S)

import * as E from '@/lib/offline/faena-entrega-offline'

const P = { faenaId: 'f1', desde: '2026-11-18', hasta: '2026-11-25', turnoSaliente: 'B', turnoEntrante: 'A' }
const plantilla = {
  resumen: { desde: P.desde, hasta: P.hasta },
  equipos: [{ activo_id: 'a1', patente: 'AB12', equipo: 'Mack', estado: 'operativo' }],
  pendientes: [],
  contexto: { camiones: [{ estanque_id: 'e1', patente: 'CC11' }], terceros: [] },
}
const declaracion = { entregaId: '', camiones: [{ estanque_id: 'e1', litros: 900, metodo: 'cuentalitros' }],
  tercerosHubo: false, terceros: [], seguridadSinNovedad: true, seguridadDetalle: null, verbalModo: 'presencial' }
const firmaParams = (entregaId: string) => ({
  entregaId, nombre: 'Supervisor', equipos: [], pendientes: [], stockFisico: 900,
  conteoHecho: true, inventarioCerrado: true,
})
const errorPg = (code: string, message: string) => Object.assign(new Error(message), { code })

describe('entrega de turno sin señal (F4)', () => {
  beforeEach(async () => {
    Object.values(S).forEach((f) => f.mockReset())
    for (const o of await E.colaEntrega()) await E.descartarEntrega(o.local_id)
    S.getPlantillaEntrega.mockResolvedValue(plantilla)
    S.subirFirma.mockResolvedValue('https://s/firma.jpg')
    S.getContextoEntrega.mockResolvedValue(plantilla.contexto)
    S.declararEntrega.mockResolvedValue({ ok: true })
    enLinea = true
    await E.guardarPlantilla(P.faenaId, P.desde, P.hasta)
  })

  it('sin plantilla del periodo, sin señal: lo dice en vez de mostrar otra semana', async () => {
    enLinea = false
    await expect(E.abrirEntregaOffline({ ...P, desde: '2026-10-01', hasta: '2026-10-08' }))
      .rejects.toThrow(/no tiene los datos de ese periodo/)
  })

  it('abre sin señal, firma, y al volver la señal la crea con el mismo id y firma con su identificador', async () => {
    enLinea = false
    const r = await E.abrirEntregaOffline(P)
    expect(r.local).toBe(true)
    expect(r.data.equipos).toHaveLength(1)
    const idLocal = r.data.entrega_id

    const env = await E.firmarOffline(firmaParams(idLocal), new Blob(['f']), { ...declaracion, entregaId: idLocal })
    expect(env.enviado).toBe(false)
    // Se ve firmada en el teléfono.
    expect((await E.abrirEntregaOffline(P)).data.entrega.estado).toBe('entregada')

    enLinea = true
    S.abrirEntrega.mockResolvedValue({ entrega_id: idLocal, entrega: { id: idLocal, faena_id: 'f1', ...P, estado: 'abierta' } })
    S.firmarEntrega.mockResolvedValue({ success: true })
    const s = await E.sincronizar()
    expect(s.ok).toBe(1)
    expect(S.abrirEntrega).toHaveBeenCalledWith(expect.objectContaining({ id: idLocal, desde: P.desde }))
    const op = S.firmarEntrega.mock.calls[0][0]
    expect(op.entregaId).toBe(idLocal)
    expect(op.clientUuid).toBeTruthy()
    expect(S.declararEntrega).toHaveBeenCalledWith(expect.objectContaining({ entregaId: idLocal }), op.clientUuid)
    expect(S.subirFirma).toHaveBeenCalledWith(expect.any(Blob), `${op.clientUuid}-firmar`)
    expect(await E.pendientesCount()).toBe(0)
  })

  it('si otro teléfono ya la había abierto, firma sobre la del servidor (otro id)', async () => {
    const P2 = { ...P, desde: '2026-11-25', hasta: '2026-12-02' }
    await E.guardarPlantilla(P2.faenaId, P2.desde, P2.hasta)
    enLinea = false
    const idLocal = (await E.abrirEntregaOffline(P2)).data.entrega_id
    await E.firmarOffline(firmaParams(idLocal), new Blob(['f']), { ...declaracion, entregaId: idLocal })
    enLinea = true
    S.abrirEntrega.mockResolvedValue({ entrega_id: 'real-1', entrega: { id: 'real-1', faena_id: 'f1', ...P2, estado: 'abierta' } })
    S.firmarEntrega.mockResolvedValue({ success: true })
    await E.sincronizar()
    expect(S.firmarEntrega.mock.calls[0][0].entregaId).toBe('real-1')
    expect(S.declararEntrega.mock.calls[0][0].entregaId).toBe('real-1')
  })

  it('firmada por otra persona: queda «no aceptada» con el motivo (no se da por subida)', async () => {
    S.firmarEntrega.mockRejectedValue(errorPg('23514', 'Esta entrega ya está entregada (firmó Juan el 19-11 08:10).'))
    const r = await E.firmarOffline(firmaParams('real-2'), new Blob(['f']), { ...declaracion, entregaId: 'real-2' })
    expect(r.rechazo).toMatch(/firmó Juan/)
    expect((await E.colaEntrega())[0].sync_status).toBe('rechazada')
  })

  it('sin señal a mitad de camino: sigue pendiente, no rechazada', async () => {
    S.firmarEntrega.mockRejectedValue(new TypeError('Failed to fetch'))
    const r = await E.firmarOffline(firmaParams('real-3'), new Blob(['f']), { ...declaracion, entregaId: 'real-3' })
    expect(r.enviado).toBe(false)
    expect(r.rechazo).toBeUndefined()
    expect(await E.pendientesCount()).toBe(1)
  })
})
