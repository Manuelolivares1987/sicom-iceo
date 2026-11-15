// [MIG691] Control de combustible por operación: diferencias que exigen
// justificación (enlace del correo semanal) y validación de jefatura.
import { supabase } from '@/lib/supabase'

export type EstadoDiferencia = 'pendiente' | 'por_validar' | 'cerrada' | 'escalada'

export type DiferenciaComb = {
  carga_id: string
  patente: string
  fecha_hora: string
  estacion: string | null
  comuna: string | null
  litros: number
  total_pago: number | null
  km_tramo: number | null
  km_l_tramo: number | null
  km_l_mediana: number | null
  dist_estacion_km: number | null
  litros_sin_explicar_30d: number | null
  alertas: string[]
  chofer: string | null
  estado: EstadoDiferencia
  comentario: string | null
  autor: string | null
  justificada_at: string | null
  nota_validacion: string | null
  rechazada: boolean
}

export type VehiculoSemana = {
  patente: string
  cargas: number
  litros: number
  pago: number
  km: number | null
  km_l: number | null
  km_l_normal: number | null
  sin_explicar_30d: number | null
}

export type ReporteToken =
  | { valido: false; motivo: string }
  | {
      valido: true
      operacion: string
      responsable: string | null
      semana_desde: string
      semana_hasta: string
      vehiculos: VehiculoSemana[]
      diferencias: DiferenciaComb[]
    }

export async function getReporteToken(token: string) {
  const { data, error } = await supabase.rpc('rpc_comb_tarjeta_reporte_token', { p_token: token })
  if (error) throw error
  return data as ReporteToken
}

export async function justificarConToken(token: string, cargaId: string, comentario: string, nombre: string) {
  const { error } = await supabase.rpc('rpc_comb_tarjeta_justificar_token', {
    p_token: token, p_carga_id: cargaId, p_comentario: comentario, p_nombre: nombre,
  })
  if (error) throw error
}

/** Diferencias de cada operación ({ Calama: [...], Coquimbo: [...] }). */
export async function getDiferenciasPorOperacion() {
  const { data, error } = await supabase.rpc('rpc_comb_tarjeta_diferencias_todas')
  if (error) throw error
  return (data ?? {}) as Record<string, DiferenciaComb[]>
}

export async function validarJustificacion(cargaId: string, aceptar: boolean, nota: string) {
  const { error } = await supabase.rpc('rpc_comb_tarjeta_validar', { p_carga_id: cargaId, p_aceptar: aceptar, p_nota: nota })
  if (error) throw error
}

export type DestinatarioReporte = { operacion: string; email: string; nombre: string | null; tipo: 'para' | 'cc'; responsable: boolean }
export async function getDestinatariosReporte() {
  const { data, error } = await supabase.from('combustible_tarjeta_reporte_destinatarios')
    .select('operacion, email, nombre, tipo, responsable').eq('activo', true).order('operacion')
  if (error) throw error
  return (data ?? []) as DestinatarioReporte[]
}

export type ExcluidaAlcance = { patente: string; motivo: string; motivo_alcance: string | null }
export async function getExcluidas() {
  const { data, error } = await supabase.from('combustible_tarjeta_excluidas').select('patente, motivo, motivo_alcance')
  if (error) throw error
  return (data ?? []) as ExcluidaAlcance[]
}

/** Días hábiles-calendario desde la carga (para la antigüedad de lo pendiente). */
export function diasDesde(iso: string, hoy = new Date()) {
  return Math.max(0, Math.floor((hoy.getTime() - new Date(iso).getTime()) / 86_400_000))
}

export function tramoAntiguedad(dias: number): '0-7' | '8-15' | '16-30' | '+30' {
  if (dias <= 7) return '0-7'
  if (dias <= 15) return '8-15'
  if (dias <= 30) return '16-30'
  return '+30'
}
