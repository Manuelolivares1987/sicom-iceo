// ============================================================================
// Servicio de alertas de mantención (vista global).
// Combina alertas_tempranas + qr_checklist_alertas_calidad.
// Solo usuario autenticado con rol mantención (validado por RLS server-side).
// ============================================================================

import { supabase } from '@/lib/supabase'

export type SemaforoTecnico = 'verde' | 'amarillo' | 'naranja' | 'rojo'
export type SeveridadCalidad = 'baja' | 'media' | 'alta' | 'critica'
export type EstadoAlertaTemprana = 'abierta' | 'en_seguimiento' | 'cerrada' | 'descartada'
export type EstadoAlertaCalidad   = 'abierta' | 'en_revision' | 'confirmada' | 'descartada'

export type TipoAlertaListado = 'temprana' | 'calidad'

// ── Resumen para badge ──────────────────────────────────────────────
export interface ResumenAlertasMantencion {
  total_abiertas: number
  total_criticas: number       // rojas (tempranas) + críticas (calidad)
  alertas_tempranas: {
    total: number
    rojo: number
    naranja: number
    amarillo: number
  }
  alertas_calidad: {
    total: number
    critica: number
    alta: number
    media: number
    baja: number
    sospechosos: number          // checklists con clasificacion='sospechoso' abiertos
  }
}

export async function obtenerResumenAlertasMantencion(): Promise<{
  data: ResumenAlertasMantencion | null
  error: unknown
}> {
  const [tempranasRes, calidadRes, sospechososRes] = await Promise.all([
    supabase
      .from('alertas_tempranas')
      .select('id, semaforo')
      .in('estado', ['abierta', 'en_seguimiento']),
    supabase
      .from('qr_checklist_alertas_calidad')
      .select('id, severidad')
      .in('estado', ['abierta', 'en_revision']),
    supabase
      .from('qr_checklist_respuestas')
      .select('id', { count: 'exact', head: true })
      .eq('clasificacion_calidad', 'sospechoso')
      .eq('estado_revision', 'pendiente'),
  ])

  const error = tempranasRes.error || calidadRes.error || sospechososRes.error
  if (error) return { data: null, error }

  const tempranas = tempranasRes.data ?? []
  const calidad = calidadRes.data ?? []
  const sospechosos = sospechososRes.count ?? 0

  const tempBreakdown = {
    total: tempranas.length,
    rojo: tempranas.filter((a) => a.semaforo === 'rojo').length,
    naranja: tempranas.filter((a) => a.semaforo === 'naranja').length,
    amarillo: tempranas.filter((a) => a.semaforo === 'amarillo').length,
  }
  const calBreakdown = {
    total: calidad.length,
    critica: calidad.filter((a) => a.severidad === 'critica').length,
    alta: calidad.filter((a) => a.severidad === 'alta').length,
    media: calidad.filter((a) => a.severidad === 'media').length,
    baja: calidad.filter((a) => a.severidad === 'baja').length,
    sospechosos,
  }

  return {
    data: {
      total_abiertas: tempBreakdown.total + calBreakdown.total,
      total_criticas: tempBreakdown.rojo + calBreakdown.critica,
      alertas_tempranas: tempBreakdown,
      alertas_calidad: calBreakdown,
    },
    error: null,
  }
}

// ── Listado unificado ───────────────────────────────────────────────
export interface AlertaListadoItem {
  id: string
  tipo: TipoAlertaListado
  activo_id: string
  activo_codigo: string
  activo_nombre: string | null
  // Para tempranas: semaforo. Para calidad: severidad mapeada visualmente.
  severidad_visual: 'rojo' | 'naranja' | 'amarillo' | 'verde'
  codigo_alerta: string                    // codigo_alerta o tipo_alerta
  descripcion: string
  estado: EstadoAlertaTemprana | EstadoAlertaCalidad
  operador: string | null
  score_calidad: number | null             // solo para calidad (via respuesta)
  repeticiones_7d: number | null           // solo tempranas
  created_at: string
  respuesta_id: string | null
}

interface RawTemprana {
  id: string
  activo_id: string
  codigo_alerta: string
  descripcion: string
  semaforo: SemaforoTecnico
  estado: EstadoAlertaTemprana
  repeticiones_7d: number | null
  created_at: string
  respuesta_id: string | null
  activo: { codigo: string; nombre: string | null } | null
  respuesta: { operador_nombre: string | null; score_calidad: number | null } | null
}

interface RawCalidad {
  id: string
  activo_id: string
  checklist_respuesta_id: string
  operador_nombre: string | null
  tipo_alerta: string
  severidad: SeveridadCalidad
  detalle: string
  estado: EstadoAlertaCalidad
  created_at: string
  activo: { codigo: string; nombre: string | null } | null
  respuesta: { score_calidad: number | null } | null
}

function mapSeveridadCalidad(s: SeveridadCalidad): 'rojo' | 'naranja' | 'amarillo' | 'verde' {
  if (s === 'critica') return 'rojo'
  if (s === 'alta')    return 'naranja'
  if (s === 'media')   return 'amarillo'
  return 'verde'
}

export async function listarAlertasMantencionAbiertas(): Promise<{
  data: AlertaListadoItem[] | null
  error: unknown
}> {
  const [tempranasRes, calidadRes] = await Promise.all([
    supabase
      .from('alertas_tempranas')
      .select(`
        id, activo_id, codigo_alerta, descripcion, semaforo, estado,
        repeticiones_7d, created_at, respuesta_id,
        activo:activos!alertas_tempranas_activo_id_fkey(codigo, nombre),
        respuesta:qr_checklist_respuestas!alertas_tempranas_respuesta_id_fkey(operador_nombre, score_calidad)
      `)
      .in('estado', ['abierta', 'en_seguimiento'])
      .order('created_at', { ascending: false })
      .limit(200),
    supabase
      .from('qr_checklist_alertas_calidad')
      .select(`
        id, activo_id, checklist_respuesta_id, operador_nombre, tipo_alerta,
        severidad, detalle, estado, created_at,
        activo:activos!qr_checklist_alertas_calidad_activo_id_fkey(codigo, nombre),
        respuesta:qr_checklist_respuestas!qr_checklist_alertas_calidad_checklist_respuesta_id_fkey(score_calidad)
      `)
      .in('estado', ['abierta', 'en_revision'])
      .order('created_at', { ascending: false })
      .limit(200),
  ])

  if (tempranasRes.error) return { data: null, error: tempranasRes.error }
  if (calidadRes.error)   return { data: null, error: calidadRes.error }

  const tempranas: AlertaListadoItem[] = ((tempranasRes.data as unknown as RawTemprana[]) ?? []).map((a) => ({
    id: a.id,
    tipo: 'temprana',
    activo_id: a.activo_id,
    activo_codigo: a.activo?.codigo ?? '-',
    activo_nombre: a.activo?.nombre ?? null,
    severidad_visual: a.semaforo === 'verde' ? 'amarillo' : a.semaforo,
    codigo_alerta: a.codigo_alerta,
    descripcion: a.descripcion,
    estado: a.estado,
    operador: a.respuesta?.operador_nombre ?? null,
    score_calidad: a.respuesta?.score_calidad ?? null,
    repeticiones_7d: a.repeticiones_7d,
    created_at: a.created_at,
    respuesta_id: a.respuesta_id,
  }))

  const calidad: AlertaListadoItem[] = ((calidadRes.data as unknown as RawCalidad[]) ?? []).map((a) => ({
    id: a.id,
    tipo: 'calidad',
    activo_id: a.activo_id,
    activo_codigo: a.activo?.codigo ?? '-',
    activo_nombre: a.activo?.nombre ?? null,
    severidad_visual: mapSeveridadCalidad(a.severidad),
    codigo_alerta: a.tipo_alerta,
    descripcion: a.detalle,
    estado: a.estado,
    operador: a.operador_nombre,
    score_calidad: a.respuesta?.score_calidad ?? null,
    repeticiones_7d: null,
    created_at: a.created_at,
    respuesta_id: a.checklist_respuesta_id,
  }))

  // Orden: rojo > naranja > amarillo, luego por fecha desc
  const sevOrden = { rojo: 0, naranja: 1, amarillo: 2, verde: 3 } as const
  const data = [...tempranas, ...calidad].sort((x, y) => {
    const s = sevOrden[x.severidad_visual] - sevOrden[y.severidad_visual]
    if (s !== 0) return s
    return y.created_at.localeCompare(x.created_at)
  })

  return { data, error: null }
}

// ── Acciones: marcar en revisión / cerrar / descartar ───────────────

export async function marcarAlertaEnRevision(alertaId: string, tipo: TipoAlertaListado) {
  if (tipo === 'temprana') {
    // No hay RPC específica; UPDATE directo (RLS UPDATE policy lo permite)
    const { data, error } = await supabase
      .from('alertas_tempranas')
      .update({ estado: 'en_seguimiento' })
      .eq('id', alertaId)
      .select('id, estado')
      .single()
    return { data, error }
  }
  // calidad: RPC existente
  const { data, error } = await supabase.rpc('rpc_revisar_alerta_calidad', {
    p_alerta_id: alertaId,
    p_nuevo_estado: 'en_revision',
    p_accion: 'Marcada en revisión desde panel global',
  })
  return { data, error }
}

export async function cerrarAlertaMantencion(
  alertaId: string,
  tipo: TipoAlertaListado,
  motivo: string,
  descartar = false
) {
  if (motivo.trim().length < 5) {
    return { data: null, error: { message: 'Motivo obligatorio (mín. 5 caracteres).' } }
  }
  if (tipo === 'temprana') {
    if (descartar) {
      // No hay RPC para descartar — UPDATE directo
      const { data, error } = await supabase
        .from('alertas_tempranas')
        .update({
          estado: 'descartada',
          accion_tomada: motivo.trim(),
          cerrada_at: new Date().toISOString(),
        })
        .eq('id', alertaId)
        .select('id, estado')
        .single()
      return { data, error }
    }
    // cerrar = RPC existente
    const { data, error } = await supabase.rpc('rpc_cerrar_alerta_temprana', {
      p_alerta_id: alertaId,
      p_accion: motivo.trim(),
    })
    return { data, error }
  }
  // calidad: confirmar = 'confirmada' / descartar = 'descartada'
  const { data, error } = await supabase.rpc('rpc_revisar_alerta_calidad', {
    p_alerta_id: alertaId,
    p_nuevo_estado: descartar ? 'descartada' : 'confirmada',
    p_accion: motivo.trim(),
  })
  return { data, error }
}
