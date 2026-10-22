// ============================================================================
// GPS de fábrica Renault Trucks — rFMS 2.1 (MIG635)
// ----------------------------------------------------------------------------
// api.renault-trucks.com/rfms con Basic auth. Renault guarda solo 14 días:
// se lee desde un cursor (ReceivedDateTime + VIN, como manda rFMS) y se pasa
// a gps_eventos_log con el mismo formato que Radicom (rpc_ingestar_gps_batch).
//
// Unidades rFMS: distancia en metros, combustible en mililitros, duraciones
// en segundos. Mientras el camión anda llega una lectura por minuto (sin
// horómetro) y cada 10 min una con horómetro; se guarda una cada 5 min más
// todos los eventos (encendido, apagado, PTO) y todas las que traen horómetro.
// ============================================================================

const ACCEPT_VEHICLES = 'application/vnd.fmsstandard.com.vehicles.v2.1+json; UTF-8'
const ACCEPT_STATUSES = 'application/vnd.fmsstandard.com.vehiclestatuses.v2.1+json; UTF-8'

/** Renault no entrega más atrás que esto. */
const DIAS_HISTORIA = 14
/** Entre polls se relee un margen; la base descarta lo repetido. */
const MARGEN_MS = 5 * 60_000
/** Lectura de TIMER sin horómetro: una cada este intervalo por camión. */
const INTERVALO_MS = 5 * 60_000

export type RfmsVehiculo = {
  VIN: string
  Model?: string
  Brand?: string
  EmissionLevel?: string
}

export type RfmsStatus = {
  Vin: string
  TriggerType?: { TriggerType?: string }
  CreatedDateTime: string
  ReceivedDateTime: string
  HRTotalVehicleDistance?: number
  TotalEngineHours?: number
  EngineTotalFuelUsed?: number
  GrossCombinationVehicleWeight?: number
  AccumulatedData?: {
    DurationWheelbaseSpeedZero?: number
    FuelWheelbaseSpeedZero?: number
  }
  SnapshotData?: {
    GNSSPosition?: {
      Latitude: number
      Longitude: number
      Heading?: number
      Altitude?: number
      Speed?: number
      PositionDateTime?: string
    }
    WheelBasedSpeed?: number
    EngineSpeed?: number
    FuelLevel1?: number
    CatalystFuelLevel?: number
    AmbientAirTemperature?: number
  }
}

/** Formato de rpc_ingestar_gps_batch (gps_device_id = VIN). */
export type EventoGps = {
  gps_device_id: string
  ts_gps: string
  lat: number
  lng: number
  speed: number | null
  heading: number | null
  altitude: number | null
  ignition: boolean | null
  movement: string
  connection: string
  odometer_km: number | null
  engine_hours: number | null
  payload: Record<string, unknown>
}

const redondear = (n: number, dec: number) => Math.round(n * 10 ** dec) / 10 ** dec

function encendido(s: RfmsStatus, velocidad: number | null): boolean | null {
  const t = s.TriggerType?.TriggerType
  if (t === 'IGNITION_ON') return true
  if (t === 'IGNITION_OFF') return false
  const rpm = s.SnapshotData?.EngineSpeed
  if ((rpm ?? 0) > 0 || (velocidad ?? 0) > 0) return true
  if (rpm === 0) return false
  return null
}

/**
 * Lecturas rFMS → eventos SICOM. Descarta las que no traen posición (el
 * resumen de cada hora) y ralea los TIMER sin horómetro.
 */
export function statusesAEventos(statuses: RfmsStatus[]): EventoGps[] {
  const porVin = new Map<string, RfmsStatus[]>()
  for (const s of statuses) {
    if (!s.Vin || !s.CreatedDateTime) continue
    const l = porVin.get(s.Vin) ?? []
    l.push(s)
    porVin.set(s.Vin, l)
  }

  const eventos: EventoGps[] = []
  for (const [vin, lista] of Array.from(porVin.entries())) {
    lista.sort((a, b) => a.CreatedDateTime.localeCompare(b.CreatedDateTime))
    let ultimoGuardado = -Infinity
    let ralenti: { l: number; h: number } | null = null
    for (const s of lista) {
      const acc = s.AccumulatedData
      if (acc?.FuelWheelbaseSpeedZero != null && acc?.DurationWheelbaseSpeedZero != null) {
        ralenti = {
          l: redondear(acc.FuelWheelbaseSpeedZero / 1000, 1),
          h: redondear(acc.DurationWheelbaseSpeedZero / 3600, 2),
        }
      }
      const pos = s.SnapshotData?.GNSSPosition
      if (!pos || pos.Latitude == null || pos.Longitude == null) continue

      const t = Date.parse(s.CreatedDateTime)
      const trigger = s.TriggerType?.TriggerType ?? 'TIMER'
      const conHorometro = s.TotalEngineHours != null
      if (trigger === 'TIMER' && !conHorometro && t - ultimoGuardado < INTERVALO_MS) continue
      ultimoGuardado = t

      const velocidad = s.SnapshotData?.WheelBasedSpeed ?? pos.Speed ?? null
      const snap = s.SnapshotData
      eventos.push({
        gps_device_id: vin,
        ts_gps: s.CreatedDateTime,
        lat: pos.Latitude,
        lng: pos.Longitude,
        speed: velocidad == null ? null : redondear(velocidad, 1),
        heading: pos.Heading ?? null,
        altitude: pos.Altitude ?? null,
        ignition: encendido(s, velocidad),
        movement: (velocidad ?? 0) >= 5 ? 'moving' : 'parked',
        connection: 'active',
        odometer_km: s.HRTotalVehicleDistance == null ? null : redondear(s.HRTotalVehicleDistance / 1000, 2),
        engine_hours: conHorometro ? redondear(s.TotalEngineHours!, 2) : null,
        payload: {
          fuente: 'rfms',
          trigger,
          contacto_utc: s.ReceivedDateTime,
          combustible_pct: snap?.FuelLevel1 ?? null,
          adblue_pct: snap?.CatalystFuelLevel ?? null,
          combustible_total_l: s.EngineTotalFuelUsed == null ? null : redondear(s.EngineTotalFuelUsed / 1000, 1),
          ralenti_l: ralenti?.l ?? null,
          ralenti_h: ralenti?.h ?? null,
          rpm: snap?.EngineSpeed ?? null,
          peso_kg: s.GrossCombinationVehicleWeight ?? null,
          temp_c: snap?.AmbientAirTemperature ?? null,
          posicion_utc: pos.PositionDateTime ?? null,
        },
      })
    }
  }
  return eventos
}

export type LecturaRenault = {
  vehiculos: RfmsVehiculo[]
  statuses: RfmsStatus[]
  paginas: number
  /** Desde dónde leer la próxima vez. cursorVin solo si quedó a mitad de paginación. */
  cursorTs: string | null
  cursorVin: string | null
  completo: boolean
}

/** Hora de inicio de la lectura: el cursor, o lo más antiguo que Renault guarda. */
export function inicioLectura(cursorTs: string | null, cursorVin: string | null, ahora = Date.now()): string {
  const minimo = ahora - DIAS_HISTORIA * 86_400_000 + 3_600_000
  if (!cursorTs) return new Date(minimo).toISOString()
  const t = Date.parse(cursorTs)
  if (Number.isNaN(t)) return new Date(minimo).toISOString()
  // A mitad de paginación se retoma exacto; si no, con margen.
  const desde = cursorVin ? t : t - MARGEN_MS
  return new Date(Math.max(desde, minimo)).toISOString()
}

export async function leerRenault(opts: {
  baseUrl: string
  credencial: string
  cursorTs: string | null
  cursorVin: string | null
  maxPaginas?: number
  fetchImpl?: typeof fetch
}): Promise<LecturaRenault> {
  const f = opts.fetchImpl ?? fetch
  const base = opts.baseUrl.replace(/\/+$/, '')
  const auth = 'Basic ' + Buffer.from(opts.credencial).toString('base64')
  const maxPaginas = opts.maxPaginas ?? 20

  const get = async (path: string, accept: string) => {
    const res = await f(`${base}${path}`, { headers: { Authorization: auth, Accept: accept } })
    const texto = await res.text()
    if (!res.ok) throw new Error(`Renault ${path.split('?')[0]} → HTTP ${res.status}: ${texto.slice(0, 200)}`)
    return JSON.parse(texto)
  }

  const veh = await get('/vehicles', ACCEPT_VEHICLES)
  const vehiculos: RfmsVehiculo[] = veh.Vehicle ?? []

  const statuses: RfmsStatus[] = []
  let desde = inicioLectura(opts.cursorTs, opts.cursorVin)
  let lastVin = opts.cursorVin
  let maxRecibido: string | null = opts.cursorTs && !opts.cursorVin ? opts.cursorTs : null
  let paginas = 0
  let mas = true

  while (mas && paginas < maxPaginas) {
    const q = new URLSearchParams({ starttime: desde, datetype: 'received' })
    if (lastVin) q.set('lastVin', lastVin)
    const r = await get(`/vehiclestatuses?${q}`, ACCEPT_STATUSES)
    const lote: RfmsStatus[] = r.VehicleStatus ?? []
    paginas++
    statuses.push(...lote)
    for (const s of lote) {
      if (!maxRecibido || s.ReceivedDateTime > maxRecibido) maxRecibido = s.ReceivedDateTime
    }
    mas = Boolean(r.MoreDataAvailable) && lote.length > 0
    if (mas) {
      const ultimo = lote[lote.length - 1]
      desde = ultimo.ReceivedDateTime
      lastVin = ultimo.Vin
    }
  }

  return {
    vehiculos,
    statuses,
    paginas,
    cursorTs: mas ? desde : maxRecibido,
    cursorVin: mas ? lastVin : null,
    completo: !mas,
  }
}
