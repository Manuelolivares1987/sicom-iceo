import { supabase } from '@/lib/supabase'

export type TipoGeocerca =
  | 'base_pillado' | 'faena_cliente' | 'bodega'
  | 'taller_externo' | 'zona_restringida' | 'punto_interes'

export type Geocerca = {
  id:            string
  nombre:        string
  tipo:          TipoGeocerca
  centro_lat:    number
  centro_lng:    number
  radio_m:       number
  contrato_id:   string | null
  color:         string
  descripcion:   string | null
  activo:        boolean
  created_at:    string
  // Joineados
  contrato_codigo?: string | null
  cliente?:         string | null
}

export type GeocercaInsert = Omit<Geocerca,
  'id' | 'created_at' | 'contrato_codigo' | 'cliente' | 'activo'
> & { activo?: boolean }

export const TIPO_LABELS: Record<TipoGeocerca, string> = {
  base_pillado:     'Base Pillado',
  faena_cliente:    'Faena cliente',
  bodega:           'Bodega',
  taller_externo:   'Taller externo',
  zona_restringida: 'Zona restringida',
  punto_interes:    'Punto de interés',
}

export const TIPO_COLORS_DEFAULT: Record<TipoGeocerca, string> = {
  base_pillado:     '#10B981',  // verde
  faena_cliente:    '#3B82F6',  // azul
  bodega:           '#F59E0B',  // ámbar
  taller_externo:   '#8B5CF6',  // violeta
  zona_restringida: '#EF4444',  // rojo
  punto_interes:    '#6B7280',  // gris
}

export async function cargarGeocercas(): Promise<Geocerca[]> {
  const { data, error } = await supabase
    .from('gps_geocercas')
    .select(`
      *,
      contrato:contratos!contrato_id ( codigo, cliente )
    `)
    .order('tipo')
    .order('nombre')
  if (error) throw error
  type Raw = Geocerca & { contrato: { codigo: string; cliente: string } | null }
  return ((data ?? []) as unknown as Raw[]).map((g) => ({
    ...g,
    contrato_codigo: g.contrato?.codigo ?? null,
    cliente:         g.contrato?.cliente ?? null,
  }))
}

export async function crearGeocerca(g: GeocercaInsert): Promise<Geocerca> {
  const { data, error } = await supabase
    .from('gps_geocercas')
    .insert({
      nombre:      g.nombre,
      tipo:        g.tipo,
      centro_lat:  g.centro_lat,
      centro_lng:  g.centro_lng,
      radio_m:     g.radio_m,
      contrato_id: g.contrato_id,
      color:       g.color,
      descripcion: g.descripcion,
      activo:      g.activo ?? true,
    })
    .select()
    .single()
  if (error) throw error
  return data as Geocerca
}

export async function actualizarGeocerca(id: string, patch: Partial<GeocercaInsert & { activo: boolean }>): Promise<void> {
  const { error } = await supabase
    .from('gps_geocercas')
    .update(patch)
    .eq('id', id)
  if (error) throw error
}

export async function eliminarGeocerca(id: string): Promise<void> {
  const { error } = await supabase
    .from('gps_geocercas')
    .delete()
    .eq('id', id)
  if (error) throw error
}

export type ContratoOption = { id: string; codigo: string; cliente: string }

export async function cargarContratosActivos(): Promise<ContratoOption[]> {
  // Nota: la tabla contratos no tiene columna 'activo' — listamos todos
  // y dejamos que la UI ordene/filtre si hace falta.
  const { data, error } = await supabase
    .from('contratos')
    .select('id, codigo, cliente')
    .order('codigo')
  if (error) throw error
  return (data ?? []) as ContratoOption[]
}
