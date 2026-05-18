import { supabase } from '@/lib/supabase'

export type EstadoPauta =
  | 'al_dia' | 'proxima' | 'critica' | 'vencida' | 'sin_historico'

export type TipoPlan = 'por_tiempo' | 'por_kilometraje' | 'por_horas' | 'por_ciclos' | 'mixto'

export type PautaEstadoRow = {
  activo_id:            string
  activo_codigo:        string
  activo_patente:       string | null
  tipo_equipamiento:    string
  horas_actuales:       number | null
  km_actuales:          number | null
  pauta_id:             string
  pauta_nombre:         string
  tipo_plan:            TipoPlan
  frecuencia_horas:     number | null
  frecuencia_km:        number | null
  frecuencia_dias:      number | null
  duracion_estimada_hrs: number | null
  ultima_fecha:         string | null
  ultimo_horometro:     number | null
  ultimo_km:            number | null
  proximo_horometro:    number | null
  proximo_km:           number | null
  proximo_dia:          string | null
  horas_restantes:      number | null
  km_restantes:         number | null
  dias_restantes:       number | null
  estado_pauta:         EstadoPauta
}

export const ESTADO_LABELS: Record<EstadoPauta, string> = {
  al_dia:        'Al día',
  proxima:       'Próxima',
  critica:       'Crítica',
  vencida:       'Vencida',
  sin_historico: 'Sin histórico',
}

export const ESTADO_COLORS: Record<EstadoPauta, string> = {
  al_dia:        'bg-green-100 text-green-700 border-green-300',
  proxima:       'bg-blue-100 text-blue-700 border-blue-300',
  critica:       'bg-amber-100 text-amber-700 border-amber-300',
  vencida:       'bg-red-100 text-red-700 border-red-300',
  sin_historico: 'bg-zinc-100 text-zinc-600 border-zinc-300',
}

export const ESTADO_ORDEN: Record<EstadoPauta, number> = {
  vencida: 0,
  critica: 1,
  proxima: 2,
  sin_historico: 3,
  al_dia: 4,
}

export async function cargarPautasEstado(): Promise<PautaEstadoRow[]> {
  const { data, error } = await supabase
    .from('v_pautas_estado_activo')
    .select('*')
  if (error) throw error
  const rows = (data ?? []) as PautaEstadoRow[]
  // Orden: por estado_pauta (vencida primero), luego restante asc
  return rows.sort((a, b) => {
    const o = ESTADO_ORDEN[a.estado_pauta] - ESTADO_ORDEN[b.estado_pauta]
    if (o !== 0) return o
    const ra = Math.min(
      a.horas_restantes ?? Infinity,
      a.km_restantes ?? Infinity,
      (a.dias_restantes ?? Infinity),
    )
    const rb = Math.min(
      b.horas_restantes ?? Infinity,
      b.km_restantes ?? Infinity,
      (b.dias_restantes ?? Infinity),
    )
    return ra - rb
  })
}

export function formatRestante(p: PautaEstadoRow): string {
  const partes: string[] = []
  if (p.horas_restantes != null) {
    partes.push(p.horas_restantes < 0
      ? `${Math.abs(p.horas_restantes).toFixed(0)} h vencido`
      : `${p.horas_restantes.toFixed(0)} h`)
  }
  if (p.km_restantes != null) {
    partes.push(p.km_restantes < 0
      ? `${Math.abs(p.km_restantes).toFixed(0)} km vencido`
      : `${p.km_restantes.toFixed(0)} km`)
  }
  if (p.dias_restantes != null) {
    partes.push(p.dias_restantes < 0
      ? `${Math.abs(p.dias_restantes)} d vencido`
      : `${p.dias_restantes} d`)
  }
  return partes.length ? partes.join(' / ') : '—'
}

export function formatUltimo(p: PautaEstadoRow): string {
  if (!p.ultima_fecha) return 'Sin servicio previo'
  const partes: string[] = [p.ultima_fecha]
  if (p.ultimo_horometro != null) partes.push(`${p.ultimo_horometro.toFixed(0)}h`)
  if (p.ultimo_km != null) partes.push(`${p.ultimo_km.toFixed(0)}km`)
  return partes.join(' · ')
}
