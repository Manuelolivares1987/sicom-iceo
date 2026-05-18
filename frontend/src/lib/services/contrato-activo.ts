import { supabase } from '@/lib/supabase'

export type HistoricoContratoRow = {
  id:                              number
  activo_id:                       string
  activo_codigo:                   string
  activo_patente:                  string | null
  cambio_at:                       string
  cambio_por:                      string | null
  cambio_por_email:                string | null
  contrato_anterior_id:            string | null
  contrato_anterior_codigo:        string | null
  cliente_anterior:                string | null
  contrato_nuevo_id:               string | null
  contrato_nuevo_codigo:           string | null
  cliente_nuevo:                   string | null
  razon:                           string | null
  estado_comercial_al_momento:     string | null
  horometro:                       number | null
  kilometraje:                     number | null
  duracion_contrato_anterior_dias: number | null
}

export async function cambiarContratoActivo(params: {
  activoId:        string
  nuevoContratoId: string | null
  razon?:          string
}): Promise<{ ok: boolean; sin_cambio?: boolean }> {
  const { data, error } = await supabase.rpc('rpc_cambiar_contrato_activo', {
    p_activo_id:         params.activoId,
    p_nuevo_contrato_id: params.nuevoContratoId,
    p_razon:             params.razon ?? null,
  })
  if (error) throw error
  return data as { ok: boolean; sin_cambio?: boolean }
}

export async function cargarHistoricoContratoActivo(activoId: string): Promise<HistoricoContratoRow[]> {
  const { data, error } = await supabase
    .from('v_historico_contrato_activo_enriquecido')
    .select('*')
    .eq('activo_id', activoId)
    .order('cambio_at', { ascending: false })
  if (error) throw error
  return (data ?? []) as HistoricoContratoRow[]
}
