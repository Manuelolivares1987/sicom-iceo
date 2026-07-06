// Capa offline-first del PLAN SEMANAL del jefe de taller (Kanban).
// - Cache de lecturas (plan, días, jornadas, KPI, técnicos, checklists) para
//   ver y operar el Kanban sin internet.
// - Cola de mutaciones pendientes (play/pausa/finalizar, mover jornada,
//   asignar responsable/cuadrilla, editar jornada) que se sincroniza al
//   recuperar conexión.
// - Overlay: aplica lo pendiente sobre la cache para que el Kanban refleje
//   las acciones hechas sin señal.
// Usa la misma BD Dexie del taller (sicom-taller-terreno) pero una tabla de
// pendientes propia (pendingPlan) para no interferir con la app del mecánico.

import { supabase } from '@/lib/supabase'
import {
  getPlanSemanalById, getDiasPlanSemanal, getJornadasPlanSemanal, getKpiSemanal,
  getTallerTecnicos, getUsuariosAsignables, getChecklistV3OT,
  rpcGetOrCreatePlanSemanal, rpcMoverJornada, rpcAsignarResponsable, rpcEditarJornada,
  rpcIniciarEjecucion, rpcPausarEjecucion, rpcReanudarEjecucion, rpcFinalizarEjecucion,
  type TallerPlanOTFull,
} from '@/lib/services/taller-plan-semanal'
import { tallerDB, newId, type TallerPlanPending } from './taller-db'

const isOnline = () => (typeof navigator === 'undefined' ? true : navigator.onLine)

// ── Lecturas cache-through ───────────────────────────────────────────────────
// Online: consulta y guarda en cache. Offline (o error de red): última copia.
export async function cachedQuery<T>(key: string, fetcher: () => Promise<T>): Promise<T> {
  const db = tallerDB()
  if (isOnline()) {
    try {
      const fresh = await fetcher()
      await db.cache.put({ key, value: fresh, updated_at: new Date().toISOString() })
      return fresh
    } catch {
      /* cae a la cache */
    }
  }
  const row = await db.cache.get(key)
  if (row === undefined) {
    throw new Error('Sin conexión y sin datos descargados. Abre esta semana con internet (o usa "Descargar semana").')
  }
  return row.value as T
}

// Resolver/crear el plan de la semana. Offline usa el id cacheado de la semana.
export async function getOrCreatePlanOffline(fechaInicio: string, faenaId?: string | null) {
  type R = { success: boolean; plan_semanal_id: string; fecha_inicio: string; fecha_fin: string; creado_nuevo: boolean }
  return cachedQuery<R>(`plansem:${fechaInicio}`, () => rpcGetOrCreatePlanSemanal(fechaInicio, faenaId))
}

export const planCacheKeys = {
  plan: (id: string) => `plan:${id}`,
  dias: (id: string) => `dias:${id}`,
  jornadas: (id: string) => `jornadas:${id}`,
  kpi: (id: string) => `kpi:${id}`,
  tecnicos: (op?: string | null) => `tecnicos:${op ?? 'all'}`,
  usuarios: 'usuarios-asignables',
  checklist: (otId: string) => `checklist:${otId}`,  // compartida con la app del mecánico
}

// ── Overlay de pendientes sobre las jornadas cacheadas ──────────────────────
const NOMBRE_DIA = ['domingo', 'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado']

function nombreDia(fecha: string): string {
  const d = new Date(fecha + 'T12:00:00')
  return NOMBRE_DIA[d.getDay()] ?? fecha
}

function aplicarPendiente(j: TallerPlanOTFull, p: TallerPlanPending): TallerPlanOTFull {
  switch (p.kind) {
    case 'timing':
      switch (p.accion) {
        case 'iniciar':
          return { ...j, jornada_estado: 'en_ejecucion', ot_estado: 'en_ejecucion',
                   ejecucion_activa_id: `offline:${p.local_id}`, ejecucion_activa_estado: 'en_ejecucion' }
        case 'pausar':
          return { ...j, jornada_estado: 'pausada', ot_estado: 'pausada', ejecucion_activa_estado: 'pausada' }
        case 'reanudar':
          return { ...j, jornada_estado: 'en_ejecucion', ot_estado: 'en_ejecucion', ejecucion_activa_estado: 'en_ejecucion' }
        case 'finalizar':
          return { ...j, jornada_estado: 'finalizada', ot_estado: 'ejecutada_ok',
                   ejecucion_activa_id: null, ejecucion_activa_estado: null,
                   ultima_ejecucion_avance: p.avance_final ?? 100 }
        default: return j
      }
    case 'mover':
      return p.fecha_destino
        ? { ...j, dia_fecha: p.fecha_destino, dia_nombre: nombreDia(p.fecha_destino) }
        : j
    case 'asignar':
      return {
        ...j,
        responsable_id: p.responsable_id ?? null,
        responsable: p.responsable_nombre ?? j.responsable,
        cuadrilla: p.cuadrilla !== undefined ? p.cuadrilla : j.cuadrilla,
      }
    case 'editar':
      return {
        ...j,
        responsable_id: p.responsable_id !== undefined ? p.responsable_id : j.responsable_id,
        responsable: p.responsable_nombre ?? j.responsable,
        cuadrilla: p.cuadrilla !== undefined ? p.cuadrilla : j.cuadrilla,
        horas_planificadas: p.horas !== undefined ? p.horas : j.horas_planificadas,
        avance_objetivo_pct: p.avance_objetivo !== undefined ? p.avance_objetivo : j.avance_objetivo_pct,
        observaciones: p.observaciones !== undefined ? (p.observaciones ?? j.observaciones) : j.observaciones,
      }
    default: return j
  }
}

export async function getJornadasOffline(planSemanalId: string): Promise<TallerPlanOTFull[]> {
  const base = await cachedQuery(planCacheKeys.jornadas(planSemanalId), () => getJornadasPlanSemanal(planSemanalId))
  const pend = (await tallerDB().pendingPlan.toArray())
    .sort((a, b) => a.created_at.localeCompare(b.created_at))
  if (pend.length === 0) return base
  return base.map((j) => {
    let out = j
    for (const p of pend) if (p.plan_ot_id === j.plan_ot_id) out = aplicarPendiente(out, p)
    return out
  })
}

// Lecturas simples con cache
export const getPlanOffline = (id: string) => cachedQuery(planCacheKeys.plan(id), () => getPlanSemanalById(id))
export const getDiasOffline = (id: string) => cachedQuery(planCacheKeys.dias(id), () => getDiasPlanSemanal(id))
export const getKpiOffline = (id: string) => cachedQuery(planCacheKeys.kpi(id), () => getKpiSemanal(id))
export const getTecnicosOffline = (op?: string | null) => cachedQuery(planCacheKeys.tecnicos(op), () => getTallerTecnicos(op))
export const getUsuariosOffline = () => cachedQuery(planCacheKeys.usuarios, () => getUsuariosAsignables())
export const getChecklistV3Offline = (otId: string) => cachedQuery(planCacheKeys.checklist(otId), () => getChecklistV3OT(otId))

// ── Mutaciones: online directo, offline a la cola ────────────────────────────
async function encolar(row: Omit<TallerPlanPending, 'local_id' | 'sync_status' | 'retries' | 'last_error' | 'created_at'>): Promise<{ success: true; offline: true }> {
  await tallerDB().pendingPlan.put({
    ...row,
    local_id: newId(),
    sync_status: 'pending', retries: 0, last_error: null,
    created_at: new Date().toISOString(),
  })
  return { success: true, offline: true }
}

export async function iniciarEjecucionOffline(p: { otId: string; planOtId?: string | null; observacion?: string | null }) {
  if (isOnline()) return rpcIniciarEjecucion(p.otId, p.observacion)
  return encolar({ kind: 'timing', accion: 'iniciar', ot_id: p.otId, plan_ot_id: p.planOtId ?? null, observacion: p.observacion ?? null })
}

export async function pausarEjecucionOffline(p: { ejecucionId?: string | null; otId?: string | null; planOtId?: string | null; motivo?: string | null }) {
  if (isOnline() && p.ejecucionId && !p.ejecucionId.startsWith('offline:')) {
    return rpcPausarEjecucion(p.ejecucionId, p.motivo)
  }
  return encolar({ kind: 'timing', accion: 'pausar', ot_id: p.otId ?? null, plan_ot_id: p.planOtId ?? null, ejecucion_id: p.ejecucionId ?? null, motivo: p.motivo ?? null })
}

export async function reanudarEjecucionOffline(p: { ejecucionId?: string | null; otId?: string | null; planOtId?: string | null }) {
  if (isOnline() && p.ejecucionId && !p.ejecucionId.startsWith('offline:')) {
    return rpcReanudarEjecucion(p.ejecucionId)
  }
  return encolar({ kind: 'timing', accion: 'reanudar', ot_id: p.otId ?? null, plan_ot_id: p.planOtId ?? null, ejecucion_id: p.ejecucionId ?? null })
}

export async function finalizarEjecucionOffline(p: { ejecucionId?: string | null; otId?: string | null; planOtId?: string | null; avanceFinal?: number; observacion?: string | null }) {
  if (isOnline() && p.ejecucionId && !p.ejecucionId.startsWith('offline:')) {
    return rpcFinalizarEjecucion(p.ejecucionId, p.avanceFinal ?? 100, p.observacion)
  }
  return encolar({ kind: 'timing', accion: 'finalizar', ot_id: p.otId ?? null, plan_ot_id: p.planOtId ?? null, ejecucion_id: p.ejecucionId ?? null, avance_final: p.avanceFinal ?? 100, observacion: p.observacion ?? null })
}

export async function moverJornadaOffline(p: { planOtId: string; fechaDestino: string; responsableId?: string | null; motivo?: string | null }) {
  if (isOnline()) return rpcMoverJornada(p.planOtId, p.fechaDestino, p.responsableId, p.motivo)
  return encolar({ kind: 'mover', plan_ot_id: p.planOtId, ot_id: null, fecha_destino: p.fechaDestino, responsable_id: p.responsableId ?? null, motivo: p.motivo ?? null })
}

export async function asignarResponsableOffline(p: { planOtId: string; responsableId: string | null; responsableNombre?: string | null; cuadrilla?: string | null; motivo?: string | null }) {
  if (isOnline()) return rpcAsignarResponsable(p.planOtId, p.responsableId, p.cuadrilla, p.motivo)
  return encolar({ kind: 'asignar', plan_ot_id: p.planOtId, ot_id: null, responsable_id: p.responsableId, responsable_nombre: p.responsableNombre ?? null, cuadrilla: p.cuadrilla ?? null, motivo: p.motivo ?? null })
}

export async function editarJornadaOffline(p: {
  planOtId: string
  responsableId?: string | null
  responsableNombre?: string | null
  cuadrilla?: string | null
  horasPlanificadas?: number | null
  avanceObjetivo?: number | null
  observaciones?: string | null
  motivo?: string | null
}) {
  if (isOnline()) return rpcEditarJornada(p)
  return encolar({
    kind: 'editar', plan_ot_id: p.planOtId, ot_id: null,
    responsable_id: p.responsableId ?? null, responsable_nombre: p.responsableNombre ?? null,
    cuadrilla: p.cuadrilla ?? null, horas: p.horasPlanificadas ?? null,
    avance_objetivo: p.avanceObjetivo ?? null, observaciones: p.observaciones ?? null,
    motivo: p.motivo ?? null,
  })
}

// ── Sync ─────────────────────────────────────────────────────────────────────
// La ejecución iniciada offline no tiene id real: al sincronizar se resuelve
// con el id devuelto por iniciar, o buscando la ejecución activa de la OT.
async function resolverEjecucionActiva(otId: string): Promise<string | null> {
  const { data, error } = await supabase
    .from('taller_ot_ejecuciones')
    .select('id')
    .eq('ot_id', otId)
    .in('estado', ['en_ejecucion', 'pausada'])
    .order('started_at', { ascending: false })
    .limit(1)
    .maybeSingle()
  if (error) throw error
  return (data?.id as string | undefined) ?? null
}

export async function syncTallerPlanPending(): Promise<{ ok: number; failed: number }> {
  if (!isOnline()) return { ok: 0, failed: 0 }
  const db = tallerDB()
  const rows = (await db.pendingPlan.toArray()).sort((a, b) => a.created_at.localeCompare(b.created_at))
  const ejecMap = new Map<string, string>()
  let ok = 0, failed = 0

  for (const p of rows) {
    try {
      if (p.kind === 'timing') {
        if (p.accion === 'iniciar') {
          const r = await rpcIniciarEjecucion(p.ot_id!, p.observacion)
          ejecMap.set(`offline:${p.local_id}`, r.ejecucion_id)
        } else {
          let ejecId = p.ejecucion_id ?? null
          if (!ejecId || ejecId.startsWith('offline:')) {
            ejecId = (ejecId && ejecMap.get(ejecId)) || (p.ot_id ? await resolverEjecucionActiva(p.ot_id) : null)
          }
          if (!ejecId) throw new Error('No se encontró la ejecución activa de la OT')
          if (p.accion === 'pausar') await rpcPausarEjecucion(ejecId, p.motivo)
          else if (p.accion === 'reanudar') await rpcReanudarEjecucion(ejecId)
          else await rpcFinalizarEjecucion(ejecId, p.avance_final ?? 100, p.observacion)
        }
      } else if (p.kind === 'mover') {
        await rpcMoverJornada(p.plan_ot_id!, p.fecha_destino!, p.responsable_id, p.motivo)
      } else if (p.kind === 'asignar') {
        await rpcAsignarResponsable(p.plan_ot_id!, p.responsable_id ?? null, p.cuadrilla, p.motivo)
      } else if (p.kind === 'editar') {
        await rpcEditarJornada({
          planOtId: p.plan_ot_id!,
          responsableId: p.responsable_id, cuadrilla: p.cuadrilla,
          horasPlanificadas: p.horas, avanceObjetivo: p.avance_objetivo,
          observaciones: p.observaciones, motivo: p.motivo,
        })
      }
      await db.pendingPlan.delete(p.local_id)
      ok++
    } catch (e) {
      failed++
      await db.pendingPlan.update(p.local_id, {
        sync_status: 'error', retries: (p.retries || 0) + 1, last_error: (e as Error).message,
      })
    }
  }
  return { ok, failed }
}

export async function getPlanPendingCount(): Promise<number> {
  return tallerDB().pendingPlan.count()
}

// ── Descargar la semana para trabajar sin internet ──────────────────────────
export async function descargarSemanaOffline(fechaInicio: string): Promise<{ jornadas: number; checklists: number }> {
  const plan = await getOrCreatePlanOffline(fechaInicio)
  const id = plan.plan_semanal_id
  await Promise.all([
    getPlanOffline(id),
    getDiasOffline(id),
    getKpiOffline(id).catch(() => undefined),
    getTecnicosOffline(null).catch(() => undefined),
    getUsuariosOffline().catch(() => undefined),
  ])
  const jornadas = await cachedQuery(planCacheKeys.jornadas(id), () => getJornadasPlanSemanal(id))
  let checklists = 0
  const otIds = Array.from(new Set(jornadas.map((j) => j.ot_id).filter(Boolean))) as string[]
  for (const otId of otIds) {
    try { await getChecklistV3Offline(otId); checklists++ } catch { /* sigue con las demás */ }
  }
  return { jornadas: jornadas.length, checklists }
}
