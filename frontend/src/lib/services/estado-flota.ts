import { supabase } from '@/lib/supabase'

export type EstadoComercial =
  | 'arrendado' | 'disponible' | 'uso_interno' | 'leasing'
  | 'en_recepcion' | 'en_venta' | 'comprometido' | 'en_transito'

export type AccionSugerencia =
  | 'pendiente' | 'aprobada' | 'rechazada' | 'expirada' | 'auto_revertida'

export type OrigenCambioEstado =
  | 'manual' | 'sugerencia' | 'sistema' | 'importado'

export type SugerenciaPendiente = {
  sugerencia_id:        string
  activo_id:            string
  activo_codigo:        string
  activo_patente:       string | null
  tipo_equipamiento:    string
  estado_anterior:      EstadoComercial | null
  estado_sugerido:      EstadoComercial
  razon:                string
  minutos_fuera:        number | null
  generado_at:          string
  minutos_desde_sugerencia: number
  geocerca_id:          string | null
  geocerca_nombre:      string | null
  contrato_codigo:      string | null
  cliente:              string | null
  pos_actual_lat:       number | null
  pos_actual_lng:       number | null
  distancia_a_geocerca_m: number | null
}

export type HistoricoEstadoRow = {
  id:                            number
  activo_id:                     string
  estado_anterior:               EstadoComercial | null
  estado_nuevo:                  EstadoComercial
  cambio_at:                     string
  cambio_por:                    string | null
  origen:                        OrigenCambioEstado
  sugerencia_id:                 string | null
  contrato_id:                   string | null
  razon:                         string | null
  latitud:                       number | null
  longitud:                      number | null
  horometro:                     number | null
  kilometraje:                   number | null
  duracion_estado_anterior_horas: number | null
  // Joineados
  activo_codigo?:                string
  activo_patente?:               string | null
  contrato_codigo?:              string | null
  cliente?:                      string | null
}

export type ActivoFueraGeocerca = {
  activo_id:            string
  activo_codigo:        string
  activo_patente:       string | null
  estado_comercial:     EstadoComercial
  contrato_codigo:      string | null
  cliente:              string | null
  geocerca_id:          string | null
  geocerca_nombre:      string | null
  geocerca_lat:         number | null
  geocerca_lng:         number | null
  geocerca_radio_m:     number | null
  pos_actual_lat:       number | null
  pos_actual_lng:       number | null
  distancia_m:          number | null
  fuera_de_geocerca:    boolean
}

export const ESTADO_LABELS: Record<EstadoComercial, string> = {
  arrendado:    'Arrendado',
  disponible:   'Disponible',
  uso_interno:  'Uso interno',
  leasing:      'Leasing',
  en_recepcion: 'En recepción',
  en_venta:     'En venta',
  comprometido: 'Comprometido',
  en_transito:  'En tránsito',
}

export const ESTADO_COLORS: Record<EstadoComercial, string> = {
  arrendado:    'bg-green-100 text-green-700 border-green-300',
  disponible:   'bg-blue-100 text-blue-700 border-blue-300',
  uso_interno:  'bg-cyan-100 text-cyan-700 border-cyan-300',
  leasing:      'bg-violet-100 text-violet-700 border-violet-300',
  en_recepcion: 'bg-amber-100 text-amber-700 border-amber-300',
  en_venta:     'bg-pink-100 text-pink-700 border-pink-300',
  comprometido: 'bg-orange-100 text-orange-700 border-orange-300',
  en_transito:  'bg-yellow-100 text-yellow-700 border-yellow-300',
}


export async function cargarSugerenciasPendientes(): Promise<SugerenciaPendiente[]> {
  const { data, error } = await supabase
    .from('v_sugerencias_pendientes_con_contexto')
    .select('*')
  if (error) throw error
  return (data ?? []) as SugerenciaPendiente[]
}

export async function validarSugerencia(
  sugerenciaId: string,
  accion: 'aprobar' | 'rechazar',
  comentario?: string,
): Promise<void> {
  const { error } = await supabase.rpc('rpc_validar_sugerencia', {
    p_sugerencia_id: sugerenciaId,
    p_accion: accion,
    p_comentario: comentario ?? null,
  })
  if (error) throw error
}

export async function cargarHistoricoEstado(params: {
  activoId?: string
  fechaDesde?: string
  fechaHasta?: string
  limit?: number
}): Promise<HistoricoEstadoRow[]> {
  let q = supabase
    .from('historico_estado_activo')
    .select(`
      *,
      activo:activos!activo_id ( codigo, patente ),
      contrato:contratos!contrato_id ( codigo, cliente )
    `)
    .order('cambio_at', { ascending: false })
    .limit(params.limit ?? 200)

  if (params.activoId)   q = q.eq('activo_id', params.activoId)
  if (params.fechaDesde) q = q.gte('cambio_at', params.fechaDesde)
  if (params.fechaHasta) q = q.lte('cambio_at', params.fechaHasta)

  const { data, error } = await q
  if (error) throw error
  type Raw = HistoricoEstadoRow & {
    activo: { codigo: string; patente: string | null } | null
    contrato: { codigo: string; cliente: string } | null
  }
  return ((data ?? []) as unknown as Raw[]).map((r) => ({
    ...r,
    activo_codigo:   r.activo?.codigo,
    activo_patente:  r.activo?.patente ?? null,
    contrato_codigo: r.contrato?.codigo ?? null,
    cliente:         r.contrato?.cliente ?? null,
  }))
}

export async function cargarActivosFueraGeocercaAhora(): Promise<ActivoFueraGeocerca[]> {
  // Combina v_activo_geocerca_esperada con gps_estado_actual y calcula distancia
  const { data, error } = await supabase
    .from('v_activo_geocerca_esperada')
    .select(`
      activo_id, activo_codigo, activo_patente, estado_comercial,
      contrato_codigo, cliente,
      geocerca_id, geocerca_nombre, geocerca_lat, geocerca_lng, geocerca_radio_m,
      estado:gps_estado_actual!activo_id ( latitud, longitud )
    `)
  if (error) throw error

  type Raw = Omit<ActivoFueraGeocerca, 'pos_actual_lat' | 'pos_actual_lng' | 'distancia_m' | 'fuera_de_geocerca'> & {
    estado: { latitud: number | null; longitud: number | null } | null
  }
  const rows = ((data ?? []) as unknown as Raw[]).map((r) => {
    const lat = r.estado?.latitud ?? null
    const lng = r.estado?.longitud ?? null
    let dist: number | null = null
    let fuera = false
    if (lat != null && lng != null && r.geocerca_lat != null && r.geocerca_lng != null && r.geocerca_radio_m != null) {
      dist = haversineMeters(lat, lng, r.geocerca_lat, r.geocerca_lng)
      fuera = dist > r.geocerca_radio_m
    }
    return {
      ...r,
      pos_actual_lat:    lat,
      pos_actual_lng:    lng,
      distancia_m:       dist,
      fuera_de_geocerca: fuera,
    }
  })
  return rows
}

function haversineMeters(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371000
  const dLat = ((lat2 - lat1) * Math.PI) / 180
  const dLng = ((lng2 - lng1) * Math.PI) / 180
  const a = Math.sin(dLat / 2) ** 2 +
            Math.cos((lat1 * Math.PI) / 180) * Math.cos((lat2 * Math.PI) / 180) *
            Math.sin(dLng / 2) ** 2
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
}

export function formatHaceMin(min: number | null): string {
  if (min == null) return '—'
  if (min < 1) return 'hace segundos'
  if (min < 60) return `hace ${min} min`
  const h = Math.floor(min / 60)
  if (h < 24) return `hace ${h} h`
  const d = Math.floor(h / 24)
  return `hace ${d} d`
}
