import { describe, it, expect, vi } from 'vitest'
import { statusesAEventos, inicioLectura, leerRenault, type RfmsStatus } from '@/lib/gps/renault-rfms'

const VIN = 'VF630N358PD000096'

function st(created: string, extra: Partial<RfmsStatus> = {}, snap: Record<string, unknown> = {}): RfmsStatus {
  return {
    Vin: VIN,
    TriggerType: { TriggerType: 'TIMER' },
    CreatedDateTime: created,
    ReceivedDateTime: created.replace('.000Z', '.900Z'),
    HRTotalVehicleDistance: 24702180,
    EngineTotalFuelUsed: 14482770,
    SnapshotData: {
      GNSSPosition: { Latitude: -21.98, Longitude: -68.68, Heading: 77, Altitude: 3249, Speed: 0 },
      WheelBasedSpeed: 0,
      FuelLevel1: 85.2,
      CatalystFuelLevel: 64.4,
      ...snap,
    },
    ...extra,
  }
}

describe('statusesAEventos', () => {
  it('convierte unidades rFMS: metros → km, ml → litros, segundos → horas', () => {
    const [e] = statusesAEventos([st('2026-10-22T00:33:16.000Z', {
      TotalEngineHours: 1944.8536,
      AccumulatedData: { FuelWheelbaseSpeedZero: 1762660, DurationWheelbaseSpeedZero: 3014334 },
    })])
    expect(e.gps_device_id).toBe(VIN)
    expect(e.odometer_km).toBe(24702.18)
    expect(e.engine_hours).toBe(1944.85)
    expect(e.payload.combustible_total_l).toBe(14482.8)
    expect(e.payload.ralenti_l).toBe(1762.7)
    expect(e.payload.ralenti_h).toBe(837.32)
    expect(e.payload.combustible_pct).toBe(85.2)
    expect(e.payload.adblue_pct).toBe(64.4)
    expect(e.payload.contacto_utc).toBe('2026-10-22T00:33:16.900Z')
  })

  it('ralea los TIMER por minuto pero guarda eventos y lecturas con horómetro', () => {
    const lista = [
      st('2026-10-22T00:28:28.000Z', {}, { WheelBasedSpeed: 24 }),
      st('2026-10-22T00:29:28.000Z', {}, { WheelBasedSpeed: 22 }),
      st('2026-10-22T00:31:28.000Z', {}, { WheelBasedSpeed: 14 }),
      st('2026-10-22T00:33:16.000Z', { TotalEngineHours: 1944.85 }),
      st('2026-10-22T00:34:28.000Z', {}, { WheelBasedSpeed: 30 }),
      st('2026-10-22T00:39:28.000Z', {}, { WheelBasedSpeed: 40 }),
      st('2026-10-22T00:40:00.000Z', { TriggerType: { TriggerType: 'IGNITION_OFF' } }),
    ]
    const ts = statusesAEventos(lista).map((e) => e.ts_gps.slice(11, 19))
    expect(ts).toEqual(['00:28:28', '00:33:16', '00:39:28', '00:40:00'])
  })

  it('ordena por hora aunque Renault las entregue desordenadas', () => {
    const ts = statusesAEventos([
      st('2026-10-22T01:00:00.000Z', { TotalEngineHours: 2 }),
      st('2026-10-22T00:00:00.000Z', { TotalEngineHours: 1 }),
    ]).map((e) => e.engine_hours)
    expect(ts).toEqual([1, 2])
  })

  it('la misma lectura repetida (historia + latestOnly) sale una vez', () => {
    const l = st('2026-10-22T00:33:16.000Z', { TotalEngineHours: 1944.85 })
    expect(statusesAEventos([l, { ...l }])).toHaveLength(1)
  })

  it('descarta el resumen horario sin posición', () => {
    const sinPos = st('2026-10-22T01:00:00.000Z', { TotalEngineHours: 1945.29 })
    delete sinPos.SnapshotData
    expect(statusesAEventos([sinPos])).toEqual([])
  })

  it('motor encendido: por evento, por rpm o por velocidad', () => {
    const [on, off, rpm, quieto] = statusesAEventos([
      st('2026-10-22T00:00:00.000Z', { TriggerType: { TriggerType: 'IGNITION_ON' } }),
      st('2026-10-22T00:10:00.000Z', { TriggerType: { TriggerType: 'IGNITION_OFF' } }, { EngineSpeed: 600 }),
      st('2026-10-22T00:20:00.000Z', {}, { EngineSpeed: 600 }),
      st('2026-10-22T00:30:00.000Z', {}, { EngineSpeed: 0 }),
    ])
    expect([on.ignition, off.ignition, rpm.ignition, quieto.ignition]).toEqual([true, false, true, false])
  })
})

describe('inicioLectura', () => {
  const ahora = Date.parse('2026-10-22T10:00:00.000Z')
  it('sin cursor parte en lo más antiguo que Renault guarda', () => {
    expect(inicioLectura(null, null, ahora)).toBe('2026-10-08T11:00:00.000Z')
  })
  it('con cursor relee 5 minutos de margen', () => {
    expect(inicioLectura('2026-10-22T09:00:00.000Z', null, ahora)).toBe('2026-10-22T08:55:00.000Z')
  })
  it('a mitad de paginación retoma exacto', () => {
    expect(inicioLectura('2026-10-22T09:00:00.000Z', VIN, ahora)).toBe('2026-10-22T09:00:00.000Z')
  })
})

describe('leerRenault', () => {
  it('pagina con lastVin y deja el cursor en lo último recibido', async () => {
    const pagina1 = { VehicleStatus: [st('2026-10-22T00:00:00.000Z')], MoreDataAvailable: true }
    const pagina2 = { VehicleStatus: [st('2026-10-22T00:10:00.000Z')], MoreDataAvailable: false }
    const urls: string[] = []
    const fetchImpl = vi.fn(async (u: string) => {
      urls.push(u)
      const body = u.endsWith('/vehicles') ? { Vehicle: [{ VIN }] } : urls.length === 2 ? pagina1 : pagina2
      return new Response(JSON.stringify(body), { status: 200 })
    }) as unknown as typeof fetch
    const r = await leerRenault({
      baseUrl: 'https://x/rfms', credencial: 'u:p',
      cursorTs: '2026-10-21T23:00:00.000Z', cursorVin: null, fetchImpl,
    })
    expect(r.paginas).toBe(2)
    expect(r.completo).toBe(true)
    expect(urls[2]).toContain(`lastVin=${VIN}`)
    expect(r.cursorTs).toBe('2026-10-22T00:10:00.900Z')
    expect(r.cursorVin).toBeNull()
  })

  it('si se acaban las páginas permitidas, guarda dónde retomar', async () => {
    const fetchImpl = vi.fn(async (u: string) => new Response(JSON.stringify(
      u.endsWith('/vehicles') ? { Vehicle: [] }
        : { VehicleStatus: [st('2026-10-22T00:00:00.000Z')], MoreDataAvailable: true },
    ), { status: 200 })) as unknown as typeof fetch
    const r = await leerRenault({
      baseUrl: 'https://x/rfms', credencial: 'u:p', cursorTs: null, cursorVin: null, maxPaginas: 1, fetchImpl,
    })
    expect(r.completo).toBe(false)
    expect(r.cursorTs).toBe('2026-10-22T00:00:00.900Z')
    expect(r.cursorVin).toBe(VIN)
  })
})
