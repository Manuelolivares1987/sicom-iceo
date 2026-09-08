import { supabase } from '@/lib/supabase'

// ============================================================================
// Copiloto Técnico — diagnóstico guiado y casos técnicos (MIG543).
// El diagnóstico es un objeto: síntoma → comprobaciones → causa raíz.
// Un caso resuelto queda como conocimiento para el próximo mecánico.
// ============================================================================

export type Comprobacion = {
  descripcion: string
  resultado: 'ok' | 'no_ok' | 'valor'
  valor?: string | null
  at: string
}

export type Diagnostico = {
  id: string
  ot_id: string | null
  activo_id: string
  usuario_id: string
  sintoma: string
  sistema: string | null
  estado: 'abierto' | 'resuelto' | 'descartado'
  comprobaciones: Comprobacion[]
  causa_raiz: string | null
  reparacion: string | null
  resuelto_at: string | null
  created_at: string
}

export type CasoSimilar = {
  id: string
  equipo: string
  mismo_equipo: boolean
  sintoma: string
  causa_raiz: string
  reparacion: string | null
  sistema: string | null
  resuelto_at: string
}

export const SISTEMAS = [
  { value: 'electrico', label: 'Eléctrico' },
  { value: 'motor', label: 'Motor' },
  { value: 'transmision', label: 'Transmisión / caja' },
  { value: 'frenos', label: 'Frenos / aire' },
  { value: 'hidraulica', label: 'Hidráulica / PTO' },
  { value: 'direccion', label: 'Dirección' },
  { value: 'tren_rodaje', label: 'Ejes / suspensión / neumáticos' },
  { value: 'combustible', label: 'Combustible' },
  { value: 'otro', label: 'Otro' },
]

export async function getDiagnosticoDeOT(otId: string): Promise<Diagnostico | null> {
  const { data, error } = await supabase
    .from('copiloto_diagnosticos')
    .select('*')
    .eq('ot_id', otId)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle()
  if (error) throw error
  return data as Diagnostico | null
}

export async function crearDiagnostico(p: {
  otId?: string | null; activoId: string; sintoma: string; sistema?: string | null
}): Promise<Diagnostico> {
  const { data: u } = await supabase.auth.getUser()
  if (!u.user) throw new Error('Sesión expirada')
  const { data, error } = await supabase
    .from('copiloto_diagnosticos')
    .insert({
      ot_id: p.otId ?? null,
      activo_id: p.activoId,
      usuario_id: u.user.id,
      sintoma: p.sintoma.trim(),
      sistema: p.sistema ?? null,
    })
    .select('*')
    .single()
  if (error) throw error
  return data as Diagnostico
}

export async function agregarComprobacion(
  diagnosticoId: string, descripcion: string, resultado: 'ok' | 'no_ok' | 'valor', valor?: string,
): Promise<Comprobacion[]> {
  const { data, error } = await supabase.rpc('rpc_diagnostico_comprobacion', {
    p_diagnostico_id: diagnosticoId,
    p_descripcion: descripcion,
    p_resultado: resultado,
    p_valor: valor ?? null,
  })
  if (error) throw error
  return (data ?? []) as Comprobacion[]
}

export async function resolverDiagnostico(
  diagnosticoId: string, causaRaiz: string, reparacion: string, sistema?: string | null,
): Promise<void> {
  const { error } = await supabase.rpc('rpc_diagnostico_resolver', {
    p_diagnostico_id: diagnosticoId,
    p_causa_raiz: causaRaiz,
    p_reparacion: reparacion,
    p_sistema: sistema ?? null,
  })
  if (error) throw error
}

export async function casosSimilares(activoId: string, texto: string, limit = 3): Promise<CasoSimilar[]> {
  const { data, error } = await supabase.rpc('rpc_copiloto_casos_similares', {
    p_activo_id: activoId, p_texto: texto || 'falla', p_limit: limit,
  })
  if (error) throw error
  return (data ?? []) as CasoSimilar[]
}
