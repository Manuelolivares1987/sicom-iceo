import { supabase } from '@/lib/supabase'
import type { ConversacionCopiloto, DiagnosticoCopiloto, MensajeGuardado } from '@/lib/copiloto/tipos'

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
  { value: 'postratamiento', label: 'Postratamiento (AdBlue/DPF/EGR)' },
  { value: 'implemento', label: 'Implemento (bomba, grúa, polibrazo)' },
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

// ── Conversaciones persistentes (MIG583) ────────────────────────────────────

async function tokenSesion(): Promise<string> {
  const { data: { session } } = await supabase.auth.getSession()
  if (!session?.access_token) throw new Error('Tu sesión expiró. Vuelve a entrar.')
  return session.access_token
}

export async function listarConversaciones(p: {
  activoId?: string | null; otId?: string | null; estado?: 'abierta' | 'resuelta' | 'descartada'; limit?: number
} = {}): Promise<ConversacionCopiloto[]> {
  let q = supabase.from('copiloto_conversaciones')
    .select('id, usuario_id, activo_id, ot_id, diagnostico_id, titulo, estado, mensajes, ultimo_at, created_at, activo:activos(patente, codigo)')
    .order('ultimo_at', { ascending: false }).limit(p.limit ?? 50)
  if (p.activoId) q = q.eq('activo_id', p.activoId)
  if (p.otId) q = q.eq('ot_id', p.otId)
  if (p.estado) q = q.eq('estado', p.estado)
  const { data, error } = await q
  if (error) throw error
  return (data ?? []) as unknown as ConversacionCopiloto[]
}

export async function cargarConversacion(id: string): Promise<{
  conversacion: ConversacionCopiloto; diagnostico: DiagnosticoCopiloto | null; mensajes: MensajeGuardado[]
}> {
  const res = await fetch(`/api/copiloto/conversacion?id=${id}`, { headers: { Authorization: `Bearer ${await tokenSesion()}` } })
  const j = await res.json().catch(() => null)
  if (!res.ok) throw new Error(j?.error ?? `Error ${res.status}`)
  return j
}

// La solución definitiva: cierra la conversación, crea/resuelve el caso y
// pide la lección a la IA (servidor).
export async function resolverConversacion(p: {
  conversacionId: string; causa: string; reparacion: string; sistema?: string | null; sintoma?: string | null
}): Promise<{ diagnosticoId: string; leccion: string | null; diagnostico: DiagnosticoCopiloto | null }> {
  const res = await fetch('/api/copiloto/conversacion', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${await tokenSesion()}` },
    body: JSON.stringify({ accion: 'resolver', ...p }),
  })
  const j = await res.json().catch(() => null)
  if (!res.ok) throw new Error(j?.error ?? `Error ${res.status}`)
  return j
}

// «La falla volvió»: la reparación anterior queda como intento fallido
export async function reabrirConversacion(conversacionId: string, motivo?: string): Promise<void> {
  const { error } = await supabase.rpc('rpc_copiloto_reabrir', { p_conversacion_id: conversacionId, p_motivo: motivo ?? null })
  if (error) throw error
}

// «Era solo una consulta»: no espera solución
export async function cambiarEstadoConversacion(conversacionId: string, estado: 'abierta' | 'descartada'): Promise<void> {
  const { error } = await supabase.from('copiloto_conversaciones').update({ estado }).eq('id', conversacionId)
  if (error) throw error
}

export async function validarCaso(diagnosticoId: string, validado: boolean): Promise<void> {
  const { error } = await supabase.rpc('rpc_copiloto_caso_validar', { p_diagnostico_id: diagnosticoId, p_validado: validado })
  if (error) throw error
}

export async function enviarFeedback(consultaId: string, feedback: 'util' | 'no_util', nota?: string): Promise<void> {
  const { error } = await supabase.rpc('rpc_copiloto_feedback', { p_consulta_id: consultaId, p_feedback: feedback, p_nota: nota ?? null })
  if (error) throw error
}

export async function casosSimilares(activoId: string, texto: string, limit = 3): Promise<CasoSimilar[]> {
  const { data, error } = await supabase.rpc('rpc_copiloto_casos_similares', {
    p_activo_id: activoId, p_texto: texto || 'falla', p_limit: limit,
  })
  if (error) throw error
  return (data ?? []) as CasoSimilar[]
}
