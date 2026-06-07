import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'

// ============================================================================
// Control de Calidad — Gate 1 (chequeo cruzado), Gate 2 (auditoria), diferidos.
// Llama a los RPC de la MIG 125 y a las vistas v_*.
// ============================================================================

export type ChequeoCruzadoItem = {
  id: string
  orden: number
  categoria: string
  descripcion: string
  obligatorio: boolean
  requiere_foto: boolean
  resultado: 'ok' | 'no_ok' | 'na' | 'pendiente'
  observacion: string | null
  foto_url: string | null
}

export type AuditoriaItem = {
  id: string
  categoria: 'tecnica' | 'documentacion'
  orden: number
  descripcion: string
  obligatorio: boolean
  critico: boolean
  resultado: 'ok' | 'no_ok' | 'na' | 'pendiente'
  observacion: string | null
  foto_url: string | null
  referencia_cert_id: string | null
}

// ── Queries ──────────────────────────────────────────────────────────────

/** Cola Gate 1. Por SoD se ocultan los chequeos cuyo ejecutor es el usuario. */
export function useChequeosCruzadosPendientes(excluirUserId?: string) {
  return useQuery({
    queryKey: ['cc-pendientes', excluirUserId],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('v_chequeos_cruzados_pendientes')
        .select('*')
      if (error) throw error
      const rows = data ?? []
      return excluirUserId ? rows.filter((r: any) => r.ejecutor_id !== excluirUserId) : rows
    },
    staleTime: 15_000,
  })
}

export function useChequeoCruzadoItems(chequeoId?: string) {
  return useQuery({
    queryKey: ['cc-items', chequeoId],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('taller_chequeo_cruzado_items')
        .select('*')
        .eq('chequeo_id', chequeoId!)
        .order('orden')
      if (error) throw error
      return (data ?? []) as ChequeoCruzadoItem[]
    },
    enabled: !!chequeoId,
  })
}

export function useAuditoriasPendientes() {
  return useQuery({
    queryKey: ['aud-pendientes'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('v_auditorias_calidad_pendientes')
        .select('*')
      if (error) throw error
      return data ?? []
    },
    staleTime: 15_000,
  })
}

export function useAuditoriaItems(auditoriaId?: string) {
  return useQuery({
    queryKey: ['aud-items', auditoriaId],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('auditoria_calidad_items')
        .select('*')
        .eq('auditoria_id', auditoriaId!)
        .order('categoria')
        .order('orden')
      if (error) throw error
      return (data ?? []) as AuditoriaItem[]
    },
    enabled: !!auditoriaId,
  })
}

export function useDiferidosActivo(activoId?: string) {
  return useQuery({
    queryKey: ['diferidos-activo', activoId],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('v_items_diferidos_activo')
        .select('*')
        .eq('activo_id', activoId!)
        .order('plazo_fecha_limite', { nullsFirst: false })
      if (error) throw error
      return data ?? []
    },
    enabled: !!activoId,
  })
}

export function useKpiCalidadTaller() {
  return useQuery({
    queryKey: ['kpi-calidad-taller'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('v_kpi_calidad_taller')
        .select('*')
        .single()
      if (error) throw error
      return data
    },
    staleTime: 60_000,
  })
}

/** Equipos en mantención candidatos a auditar (Gate 2). */
export function useEquiposParaAuditar() {
  return useQuery({
    queryKey: ['equipos-para-auditar'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('activos')
        .select('id, codigo, patente, nombre, estado')
        .in('estado', ['en_mantenimiento', 'fuera_servicio', 'en_transito'])
        .order('patente')
      if (error) throw error
      return data ?? []
    },
    staleTime: 30_000,
  })
}

// ── Mutations ────────────────────────────────────────────────────────────

export function useResolverChequeoCruzado() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (args: {
      chequeo_id: string
      resultado: 'aprobado' | 'aprobado_con_obs' | 'rechazado'
      items: Array<{ id: string; resultado: string; observacion?: string | null; foto_url?: string | null }>
      avance_verificado?: number | null
      observaciones?: string | null
      firma_url?: string | null
      evidencias?: unknown[]
    }) => {
      const { data, error } = await supabase.rpc('fn_resolver_chequeo_cruzado', {
        p_chequeo_id: args.chequeo_id,
        p_resultado: args.resultado,
        p_items: args.items,
        p_avance_verificado: args.avance_verificado ?? null,
        p_observaciones: args.observaciones ?? null,
        p_firma_url: args.firma_url ?? null,
        p_evidencias: args.evidencias ?? [],
      })
      if (error) throw error
      return data
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['cc-pendientes'] })
      qc.invalidateQueries({ queryKey: ['kpi-calidad-taller'] })
    },
  })
}

export function useIniciarAuditoria() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (args: { activo_id: string; ot_id?: string | null }) => {
      const { data, error } = await supabase.rpc('fn_iniciar_auditoria_calidad', {
        p_activo_id: args.activo_id,
        p_ot_id: args.ot_id ?? null,
      })
      if (error) throw error
      return data
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['aud-pendientes'] })
      qc.invalidateQueries({ queryKey: ['equipos-para-auditar'] })
    },
  })
}

export function useResolverAuditoria() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (args: {
      auditoria_id: string
      resultado: 'aprobado' | 'aprobado_con_observaciones' | 'rechazado'
      items: Array<{ id: string; resultado: string; observacion?: string | null; foto_url?: string | null }>
      motivo_rechazo?: string | null
      observaciones?: string | null
      firma_url?: string | null
      evidencias?: unknown[]
      dias_vigencia?: number
    }) => {
      const { data, error } = await supabase.rpc('fn_resolver_auditoria_calidad', {
        p_auditoria_id: args.auditoria_id,
        p_resultado: args.resultado,
        p_items: args.items,
        p_motivo_rechazo: args.motivo_rechazo ?? null,
        p_observaciones: args.observaciones ?? null,
        p_firma_url: args.firma_url ?? null,
        p_evidencias: args.evidencias ?? [],
        p_dias_vigencia: args.dias_vigencia ?? 3,
      })
      if (error) throw error
      return data
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['aud-pendientes'] })
      qc.invalidateQueries({ queryKey: ['kpi-calidad-taller'] })
      qc.invalidateQueries({ queryKey: ['flota-vehicular'] })
    },
  })
}

export function useDiferirItem() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (args: {
      activo_id: string
      descripcion: string
      sistema?: string | null
      severidad?: 'baja' | 'media' | 'alta' | 'critica'
      es_seguridad?: boolean
      motivo?: string | null
      origen_tipo?: string
      origen_ot_id?: string | null
      origen_auditoria_id?: string | null
      origen_chequeo_id?: string | null
    }) => {
      const { data, error } = await supabase.rpc('fn_diferir_item', {
        p_activo_id: args.activo_id,
        p_descripcion: args.descripcion,
        p_sistema: args.sistema ?? null,
        p_severidad: args.severidad ?? 'media',
        p_es_seguridad: args.es_seguridad ?? false,
        p_motivo: args.motivo ?? null,
        p_origen_tipo: args.origen_tipo ?? 'manual',
        p_origen_ot_id: args.origen_ot_id ?? null,
        p_origen_auditoria_id: args.origen_auditoria_id ?? null,
        p_origen_chequeo_id: args.origen_chequeo_id ?? null,
      })
      if (error) throw error
      return data
    },
    onSuccess: (_d, vars) => {
      qc.invalidateQueries({ queryKey: ['diferidos-activo', vars.activo_id] })
      qc.invalidateQueries({ queryKey: ['kpi-calidad-taller'] })
    },
  })
}

export function useGenerarOtPendientes() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (activo_id: string) => {
      const { data, error } = await supabase.rpc('fn_generar_ot_pendientes', { p_activo_id: activo_id })
      if (error) throw error
      return data
    },
    onSuccess: (_d, activo_id) => {
      qc.invalidateQueries({ queryKey: ['diferidos-activo', activo_id] })
      qc.invalidateQueries({ queryKey: ['ordenes-trabajo'] })
    },
  })
}
