'use client'

import { useEffect, useMemo, useState } from 'react'
import Link from 'next/link'
import {
  RefreshCw, MapPin, MessageSquare, ChevronRight, AlertTriangle,
  Calendar, LogOut, ClipboardCheck, CheckCircle2, Play, Pause,
  ChevronDown, ChevronUp, ChevronLeft,
} from 'lucide-react'
import { Spinner } from '@/components/ui/spinner'
import { useAuth } from '@/contexts/auth-context'
import { usePermissions } from '@/hooks/use-permissions'
import { useMisOTsAsignadas, useUsuariosAsignables } from '@/hooks/use-calama-plan-semanal'
import { useCalamaOTs } from '@/hooks/use-calama'
import { useQueryClient } from '@tanstack/react-query'
import {
  excelCodigoFromFolio, zonaCodeFromFolio,
  type CalamaOTConRelaciones,
} from '@/lib/services/calama'
import type { CalamaJornadaAsignada } from '@/lib/services/calama-plan-semanal'
import { OfflineStatusBanner, OfflineCountersCompact } from '@/components/calama-mobile/offline-status'
import { OfflineActions } from '@/components/calama-mobile/offline-actions'
import { calamaDB } from '@/lib/offline/calama-db'
import { useNetworkStatus } from '@/hooks/use-calama-offline'

type SeccionTipo = 'atrasadas' | 'dia' | 'sin_fecha' | 'futuras' | 'completadas'

interface SeccionVista {
  tipo: SeccionTipo
  key: string
  label: string
  esHoy?: boolean
  items: Array<{ planOt: CalamaJornadaAsignada; ot: CalamaOTConRelaciones }>
}

const DIAS_CORTOS = ['Dom', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb']
const DIAS_INICIAL = ['L', 'M', 'X', 'J', 'V', 'S', 'D']
const MESES_CORTOS = ['ene','feb','mar','abr','may','jun','jul','ago','sep','oct','nov','dic']

// Fechas en zona local (no UTC). toISOString() convierte a UTC, lo que rompe
// el calculo de semana en horarios donde UTC ya esta en el dia siguiente.
function pad2(n: number): string { return n < 10 ? `0${n}` : `${n}` }
function localISO(d: Date): string {
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`
}
function isoToday(): string { return localISO(new Date()) }
function startOfWeekISOOffset(weekOffset: number): string {
  const d = new Date(); const dow = d.getDay()
  const diff = (dow === 0 ? -6 : 1) - dow
  d.setDate(d.getDate() + diff + weekOffset * 7)
  return localISO(d)
}
function endOfWeekISOOffset(weekOffset: number): string {
  const d = new Date(startOfWeekISOOffset(weekOffset) + 'T00:00:00')
  d.setDate(d.getDate() + 6)
  return localISO(d)
}
function diasDeSemana(weekStart: string): string[] {
  const out: string[] = []
  const d = new Date(weekStart + 'T00:00:00')
  for (let i = 0; i < 7; i++) {
    out.push(localISO(d))
    d.setDate(d.getDate() + 1)
  }
  return out
}
function rangoSemanaLabel(weekStart: string, weekEnd: string): string {
  const a = new Date(weekStart + 'T00:00:00')
  const b = new Date(weekEnd + 'T00:00:00')
  if (a.getMonth() === b.getMonth()) {
    return `${a.getDate()}–${b.getDate()} ${MESES_CORTOS[a.getMonth()]}`
  }
  return `${a.getDate()} ${MESES_CORTOS[a.getMonth()]} – ${b.getDate()} ${MESES_CORTOS[b.getMonth()]}`
}
function formatDiaCorto(fechaISO: string): string {
  const d = new Date(fechaISO + 'T00:00:00')
  return `${DIAS_CORTOS[d.getDay()]} ${d.getDate()} ${MESES_CORTOS[d.getMonth()]}`
}

export default function MobileCalamaPage() {
  const { perfil, signOut } = useAuth()
  const { rol } = usePermissions()
  const esAdminOPlanificador = ['administrador', 'gerencia', 'subgerente_operaciones', 'supervisor', 'planificador', 'jefe_operaciones'].includes(rol ?? '')
  const qc = useQueryClient()
  // Admin/planificador: por default ven TODAS las jornadas. Operador: solo las suyas.
  const [verTodas, setVerTodas] = useState<boolean>(esAdminOPlanificador)
  // Sincronizar default cuando se carga el rol
  useEffect(() => { setVerTodas(esAdminOPlanificador) }, [esAdminOPlanificador])
  const misOtsQuery = useMisOTsAsignadas({ todas: verTodas })
  const { data: planOts, isLoading, isError, isFetching } = misOtsQuery
  // serverLoaded = la query del server YA respondio (con [] o filas).
  // Distinto de undefined (loading): cuando es undefined NO usamos local
  // todavia (para no parpadear con datos viejos).
  const serverLoaded = planOts !== undefined && !isError
  const { data: ots } = useCalamaOTs()
  const online = useNetworkStatus()

  // Fallback IndexedDB: cuando misOts no trae datos (offline o error de red)
  // y hay jornadas descargadas localmente, las usamos en su lugar.
  const [localJornadas, setLocalJornadas] = useState<CalamaJornadaAsignada[]>([])
  const [localOts, setLocalOts] = useState<CalamaOTConRelaciones[]>([])
  useEffect(() => {
    let cancelled = false
    void (async () => {
      try {
        const db = calamaDB()
        const ljs = await db.jornadas.toArray()
        if (cancelled) return
        const mapped: CalamaJornadaAsignada[] = ljs.map((j) => ({
          id: j.local_id,
          plan_semanal_id: j.plan_semanal_id ?? '',
          plan_dia_id: '',
          ot_id: j.ot_id,
          zona_proyecto_id: null,
          responsable_id: j.responsable_id,
          prioridad: 0,
          estado_plan: j.estado_plan_local as CalamaJornadaAsignada['estado_plan'],
          observaciones: j.observaciones,
          horas_planificadas: null,
          avance_objetivo_pct: null,
          secuencia_jornada: null,
          reprogramada_desde_id: null,
          motivo_reprogramacion: null,
          visible_en_kanban: j.visible_en_kanban,
          requiere_decision_programador: false,
          desprogramada_at: null, desprogramada_by: null,
          motivo_desprogramacion: null, observacion_desprogramacion: null,
          anulada_at: null, anulada_by: null, motivo_anulacion: null,
          es_prueba: null,
          llegada_faena_at: j.llegada_faena_at,
          llegada_faena_usuario_id: null, llegada_faena_evidencia_id: null,
          llegada_faena_lat: null, llegada_faena_lng: null,
          llegada_faena_accuracy: null, llegada_faena_geo_status: null,
          created_by: null, created_at: j.downloaded_at, updated_at: j.updated_local_at,
          fecha_jornada: j.fecha_jornada,
          nombre_dia: null, orden_dia: null,
        }))
        setLocalJornadas(mapped)

        // Sintetizar OTs minimas para que el resto del page.tsx funcione.
        const otsLocal: CalamaOTConRelaciones[] = ljs.map((j) => ({
          id: j.ot_id, folio: j.folio, titulo: j.titulo,
          fecha_programada: j.fecha_jornada ?? '',
          avance_pct: j.avance_pct,
          estado: j.estado_plan_local || 'planificada',
          faena: { nombre: '—' } as { nombre: string },
          responsable_id: j.responsable_id,
        } as unknown as CalamaOTConRelaciones))
        setLocalOts(otsLocal)
      } catch {
        if (!cancelled) { setLocalJornadas([]); setLocalOts([]) }
      }
    })()
    return () => { cancelled = true }
  }, [planOts, online])

  // REGLA: cuando hay conexion Y el server respondio (incluso con []), USAMOS
  // server. Nunca reemplazamos por IndexedDB porque eso ocultaria jornadas
  // recien planificadas o, peor aun, mostraria jornadas viejas como vigentes.
  // Solo usamos IndexedDB cuando:
  //   - estamos offline; o
  //   - estamos online pero el server fallo con error de red.
  const usingLocal = (!online || (!serverLoaded && isError)) && localJornadas.length > 0
  const planOtsEff = usingLocal ? localJornadas : (planOts ?? [])
  const otsEff = usingLocal ? localOts : (ots ?? [])
  const { data: usuariosLista } = useUsuariosAsignables()
  const usuariosById = useMemo(() =>
    new Map((usuariosLista ?? []).map((u) => [u.id, u])),
  [usuariosLista])

  const otsById = useMemo(
    () => new Map(otsEff.map((o) => [o.id, o])),
    [otsEff],
  )

  // Secuencia por OT: cuantas jornadas tiene + indice de cada jornada
  const secuenciaByJornada = useMemo(() => {
    const map = new Map<string, { idx: number; total: number }>()
    if (!planOtsEff) return map
    const porOT = new Map<string, CalamaJornadaAsignada[]>()
    for (const j of planOtsEff) {
      const arr = porOT.get(j.ot_id) ?? []
      arr.push(j)
      porOT.set(j.ot_id, arr)
    }
    Array.from(porOT.values()).forEach((arr: CalamaJornadaAsignada[]) => {
      arr.sort((a, b) => (a.fecha_jornada ?? '').localeCompare(b.fecha_jornada ?? ''))
      arr.forEach((j, i) => map.set(j.id, { idx: i + 1, total: arr.length }))
    })
    return map
  }, [planOtsEff])

  // Navegacion de semana y filtro por dia (controles de la tira semanal).
  const [weekOffset, setWeekOffset] = useState(0)
  const [diaSeleccionado, setDiaSeleccionado] = useState<string | null>(null)
  const weekStart = useMemo(() => startOfWeekISOOffset(weekOffset), [weekOffset])
  const weekEnd = useMemo(() => endOfWeekISOOffset(weekOffset), [weekOffset])
  const diasSemanaVisible = useMemo(() => diasDeSemana(weekStart), [weekStart])

  // Si cambia la semana y el dia seleccionado quedo fuera del rango, lo limpio.
  useEffect(() => {
    if (diaSeleccionado && (diaSeleccionado < weekStart || diaSeleccionado > weekEnd)) {
      setDiaSeleccionado(null)
    }
  }, [diaSeleccionado, weekStart, weekEnd])

  // Agrupa jornadas por dia de la semana visible. Atrasadas/futuras/sinFecha
  // solo aplican cuando se mira la semana actual; en semanas pasadas/futuras
  // se muestran solo OTs cuya fecha cae en el rango visible.
  const secciones = useMemo<SeccionVista[]>(() => {
    const today = isoToday()
    const isCurrentWeek = weekOffset === 0

    const atrasadas: SeccionVista = { tipo: 'atrasadas', key: 'atrasadas', label: 'Atrasadas', items: [] }
    const sinFecha: SeccionVista = { tipo: 'sin_fecha', key: 'sin_fecha', label: 'Sin fecha', items: [] }
    const futuras: SeccionVista = { tipo: 'futuras', key: 'futuras', label: 'Próximas semanas', items: [] }
    const completadas: SeccionVista = { tipo: 'completadas', key: 'completadas', label: 'Completadas', items: [] }
    const porDia = new Map<string, SeccionVista>()

    for (const p of planOtsEff) {
      const ot = otsById.get(p.ot_id)
      if (!ot) continue
      const fecha = p.fecha_jornada ?? ot.fecha_programada ?? ''
      const enRango = !!fecha && fecha >= weekStart && fecha <= weekEnd
      const completada = (
        p.estado_plan === 'finalizada' ||
        ot.estado === 'finalizada' || ot.estado === 'cancelada'
      )

      if (completada) {
        if (isCurrentWeek || enRango) completadas.items.push({ planOt: p, ot })
        continue
      }
      if (!fecha) { if (isCurrentWeek) sinFecha.items.push({ planOt: p, ot }); continue }
      if (enRango) {
        let s = porDia.get(fecha)
        if (!s) {
          s = {
            tipo: 'dia', key: `dia:${fecha}`,
            label: formatDiaCorto(fecha),
            esHoy: fecha === today, items: [],
          }
          porDia.set(fecha, s)
        }
        s.items.push({ planOt: p, ot })
        continue
      }
      if (isCurrentWeek) {
        if (fecha < today) atrasadas.items.push({ planOt: p, ot })
        else futuras.items.push({ planOt: p, ot })
      }
    }

    const ordenarItems = (s: SeccionVista) => {
      s.items.sort((a, b) => {
        const order = (estado: string) =>
          estado === 'en_ejecucion' ? 0
          : estado === 'en_pausa' ? 1
          : estado === 'liberada' ? 2 : 3
        const oa = order(a.ot.estado as string)
        const ob = order(b.ot.estado as string)
        if (oa !== ob) return oa - ob
        const pa = a.planOt.prioridad ?? 0
        const pb = b.planOt.prioridad ?? 0
        if (pa !== pb) return pb - pa
        return (a.ot.folio ?? '').localeCompare(b.ot.folio ?? '')
      })
    }

    const result: SeccionVista[] = []
    if (atrasadas.items.length > 0) { ordenarItems(atrasadas); result.push(atrasadas) }
    const diasOrdenados = Array.from(porDia.entries()).sort((a, b) => a[0].localeCompare(b[0]))
    for (const [, s] of diasOrdenados) { ordenarItems(s); result.push(s) }
    if (futuras.items.length > 0) { ordenarItems(futuras); result.push(futuras) }
    if (sinFecha.items.length > 0) { ordenarItems(sinFecha); result.push(sinFecha) }
    if (completadas.items.length > 0) result.push(completadas)
    return result
  }, [planOtsEff, otsById, weekOffset, weekStart, weekEnd])

  // Conteos por dia para la tira semanal (solo OTs activas, no completadas).
  const conteosPorDia = useMemo(() => {
    const map = new Map<string, number>()
    for (const s of secciones) {
      if (s.tipo === 'dia') {
        map.set(s.key.replace('dia:', ''), s.items.length)
      }
    }
    return map
  }, [secciones])

  // Filtrado por dia: si hay dia seleccionado, mostrar solo esa seccion.
  const seccionesFiltradas = useMemo(() => {
    if (!diaSeleccionado) return secciones
    return secciones.filter((s) => s.tipo === 'dia' && s.key === `dia:${diaSeleccionado}`)
  }, [secciones, diaSeleccionado])

  const [completadasOpen, setCompletadasOpen] = useState(false)

  const counts = useMemo(() => {
    let pendientes = 0, en_ejecucion = 0, pausadas = 0, completadas = 0
    for (const p of planOtsEff) {
      if (p.estado_plan === 'finalizada') completadas++
      else if (p.estado_plan === 'en_ejecucion') en_ejecucion++
      else if (p.estado_plan === 'pausada') pausadas++
      else pendientes++
    }
    return { pendientes, en_ejecucion, pausadas, completadas, total: planOtsEff.length }
  }, [planOtsEff])

  const refresh = () => {
    qc.invalidateQueries({ queryKey: ['calama-mis-ots'] })
    qc.invalidateQueries({ queryKey: ['calama', 'ots'] })
  }

  const totalVisibles = seccionesFiltradas.reduce((acc, s) => acc + s.items.length, 0)
  const totalSemana = useMemo(
    () => secciones.filter((s) => s.tipo === 'dia').reduce((acc, s) => acc + s.items.length, 0),
    [secciones],
  )

  return (
    <div className="space-y-3 pt-2">
      {/* Header sticky */}
      <header className="sticky top-0 z-30 bg-amber-700 text-white shadow-md">
        <div className="px-4 py-3">
          <div className="flex items-center justify-between gap-2">
            <div>
              <h1 className="text-lg font-bold flex items-center gap-1.5">
                <ClipboardCheck className="h-5 w-5" /> Mis OTs Calama
              </h1>
              <p className="text-xs text-white/90 truncate">
                {perfil?.nombre_completo ?? 'Operador'} · {new Date().toLocaleDateString('es-CL', { day: '2-digit', month: 'short', weekday: 'short' })}
              </p>
            </div>
            <div className="flex items-center gap-1">
              <button onClick={refresh} aria-label="Actualizar"
                className="rounded-full p-2 bg-white/10 hover:bg-white/20 active:bg-white/30">
                <RefreshCw className={`h-4 w-4 ${isLoading ? 'animate-spin' : ''}`} />
              </button>
              <button onClick={() => signOut()} aria-label="Cerrar sesion"
                className="rounded-full p-2 bg-white/10 hover:bg-white/20 active:bg-white/30">
                <LogOut className="h-4 w-4" />
              </button>
            </div>
          </div>
        </div>
        <div className="grid grid-cols-4 gap-1 px-3 pb-2 text-[10px]">
          <Counter label="Pend." value={counts.pendientes} />
          <Counter label="Ejec." value={counts.en_ejecucion} highlight={counts.en_ejecucion > 0} />
          <Counter label="Pausa" value={counts.pausadas} />
          <Counter label="OK" value={counts.completadas} />
        </div>
        {esAdminOPlanificador && (
          <div className="px-3 pb-3 flex items-center justify-center gap-1">
            <button
              onClick={() => setVerTodas(false)}
              className={`flex-1 rounded px-2 py-1 text-[11px] font-medium ${
                !verTodas ? 'bg-white text-amber-800' : 'bg-white/15 text-white'
              }`}
            >Mis OTs</button>
            <button
              onClick={() => setVerTodas(true)}
              className={`flex-1 rounded px-2 py-1 text-[11px] font-medium ${
                verTodas ? 'bg-white text-amber-800' : 'bg-white/15 text-white'
              }`}
            >Todas las OTs</button>
          </div>
        )}
      </header>

      <div className="px-3 space-y-3">
        {/* Offline-first: estado conexion + acciones (preparar, sincronizar) */}
        <OfflineStatusBanner />
        <OfflineActions />
        <OfflineCountersCompact />
        {/* Banners contextuales:
            - online + server cargo: si lista vacia mostramos pista para Actualizar.
            - online + server fallo por red: aviso + uso local.
            - offline: aviso + uso local. */}
        {usingLocal && online && (
          <div className="rounded-lg border border-orange-200 bg-orange-50 p-2 text-xs text-orange-800">
            No se pudo conectar al servidor. Mostrando jornadas descargadas. Presiona Actualizar para reintentar.
          </div>
        )}
        {usingLocal && !online && (
          <div className="rounded-lg border border-blue-200 bg-blue-50 p-2 text-xs text-blue-800">
            Sin conexion. Mostrando jornadas descargadas. Los cambios quedaran en cola hasta sincronizar.
          </div>
        )}
        {!usingLocal && online && serverLoaded && planOts && planOts.length === 0 && (
          <div className="rounded-lg border border-blue-200 bg-blue-50 p-2 text-xs text-blue-800 flex items-start gap-2">
            <RefreshCw className="h-4 w-4 mt-0.5 shrink-0" />
            <div className="flex-1">
              <div className="font-medium">No tienes jornadas activas asignadas.</div>
              <div className="text-[11px] opacity-80">
                Si tu supervisor recien planifico algo, presiona Actualizar.
              </div>
            </div>
            <button onClick={refresh} className="rounded bg-blue-600 text-white px-2 py-1 text-[11px] font-medium" disabled={isFetching}>
              {isFetching ? '...' : 'Actualizar'}
            </button>
          </div>
        )}

        {isLoading && (
          <div className="flex items-center justify-center gap-2 py-8 text-gray-500 text-sm">
            <Spinner className="h-4 w-4" /> Cargando…
          </div>
        )}

        {!isLoading && totalVisibles === 0 && (
          <div className="rounded-xl border border-gray-200 bg-white p-6 text-center">
            <ClipboardCheck className="mx-auto h-10 w-10 text-gray-300" />
            <p className="mt-3 font-medium text-gray-700">No tienes OTs asignadas</p>
            {esAdminOPlanificador ? (
              <>
                <p className="mt-1 text-sm text-gray-500">
                  Esta vista muestra solo OTs asignadas a tu usuario.
                </p>
                <p className="mt-2 text-xs text-gray-400">
                  Como <span className="font-mono">{rol}</span>, gestiona desde:
                </p>
                <div className="mt-2 flex flex-col gap-1.5 items-stretch">
                  <Link
                    href="/dashboard/operacion-calama/plan-semanal"
                    className="rounded bg-amber-600 text-white px-3 py-2 text-sm font-medium"
                  >
                    Plan semanal
                  </Link>
                  <Link
                    href="/dashboard/operacion-calama/ots"
                    className="rounded border border-gray-300 px-3 py-2 text-sm text-gray-700"
                  >
                    Ordenes Calama (todas)
                  </Link>
                </div>
              </>
            ) : (
              <p className="mt-1 text-sm text-gray-500">
                Contacta a tu supervisor o planificador para que te asigne tareas.
              </p>
            )}
          </div>
        )}

        {/* Tira semanal: navegacion de semana + 7 pildoras de dia + filtro */}
        <div className="rounded-xl border border-gray-200 bg-white shadow-sm">
          <div className="flex items-center justify-between px-2 pt-2 pb-1">
            <button
              type="button"
              onClick={() => setWeekOffset((o) => o - 1)}
              className="p-1.5 -m-1 rounded text-gray-700 active:bg-gray-100"
              aria-label="Semana anterior"
            >
              <ChevronLeft className="h-4 w-4" />
            </button>
            <div className="text-xs font-bold text-gray-800 flex items-center gap-2">
              <Calendar className="h-3.5 w-3.5 text-gray-500" />
              <span>{rangoSemanaLabel(weekStart, weekEnd)}</span>
              <span className="text-[10px] font-mono text-gray-500">({totalSemana})</span>
              {weekOffset !== 0 && (
                <button
                  type="button"
                  onClick={() => { setWeekOffset(0); setDiaSeleccionado(null) }}
                  className="rounded bg-amber-100 text-amber-800 px-1.5 py-0.5 text-[10px] font-semibold active:bg-amber-200"
                >Hoy</button>
              )}
            </div>
            <button
              type="button"
              onClick={() => setWeekOffset((o) => o + 1)}
              className="p-1.5 -m-1 rounded text-gray-700 active:bg-gray-100"
              aria-label="Semana siguiente"
            >
              <ChevronRight className="h-4 w-4" />
            </button>
          </div>
          <div className="grid grid-cols-7 gap-1 px-2 pb-2">
            {diasSemanaVisible.map((fechaISO, idx) => {
              const conteo = conteosPorDia.get(fechaISO) ?? 0
              const esHoy = fechaISO === isoToday()
              const esSeleccionado = diaSeleccionado === fechaISO
              const tieneOTs = conteo > 0
              return (
                <button
                  key={fechaISO}
                  type="button"
                  onClick={() => setDiaSeleccionado(esSeleccionado ? null : fechaISO)}
                  className={`flex flex-col items-center rounded-lg border py-1.5 transition-colors ${
                    esSeleccionado ? 'bg-amber-700 text-white border-amber-700'
                    : esHoy ? 'bg-amber-50 border-amber-300 text-amber-900'
                    : tieneOTs ? 'bg-white border-gray-300 text-gray-800'
                    : 'bg-gray-50 border-gray-200 text-gray-400'
                  }`}
                >
                  <span className="text-[9px] uppercase font-semibold tracking-wide leading-none">
                    {DIAS_INICIAL[idx]}
                  </span>
                  <span className="text-base font-bold leading-tight mt-0.5">
                    {Number(fechaISO.slice(8, 10))}
                  </span>
                  <span className={`text-[9px] mt-0.5 font-mono leading-none ${
                    esSeleccionado ? 'text-white/90'
                    : tieneOTs ? 'text-gray-700' : 'text-gray-400'
                  }`}>
                    {tieneOTs ? conteo : '—'}
                  </span>
                </button>
              )
            })}
          </div>
          {diaSeleccionado && (
            <button
              type="button"
              onClick={() => setDiaSeleccionado(null)}
              className="w-full rounded-b-xl bg-gray-100 text-gray-700 text-xs font-medium py-2 active:bg-gray-200 border-t border-gray-200"
            >
              Toda la semana
            </button>
          )}
        </div>

        {seccionesFiltradas.map((s) => {
          if (s.items.length === 0) return null
          const colapsable = s.tipo === 'completadas'
          const colapsada = colapsable && !completadasOpen

          const headerColor =
            s.tipo === 'atrasadas' ? 'bg-red-50 border-red-200 text-red-800'
            : s.tipo === 'completadas' ? 'bg-green-50 border-green-200 text-green-800'
            : s.tipo === 'sin_fecha' ? 'bg-gray-50 border-gray-200 text-gray-700'
            : s.tipo === 'futuras' ? 'bg-slate-50 border-slate-200 text-slate-700'
            : s.esHoy ? 'bg-amber-100 border-amber-300 text-amber-900'
            : 'bg-white border-gray-200 text-gray-800'

          const cardEstilo =
            s.tipo === 'atrasadas' ? 'border-red-200 bg-red-50'
            : s.tipo === 'completadas' ? 'border-green-200 bg-green-50'
            : s.esHoy ? 'border-amber-200 bg-amber-50'
            : 'border-gray-200 bg-white'

          const icon =
            s.tipo === 'atrasadas' ? <AlertTriangle className="h-4 w-4" />
            : s.tipo === 'completadas' ? <CheckCircle2 className="h-4 w-4" />
            : <Calendar className="h-4 w-4" />

          const Header = (
            <>
              {icon}
              <h2 className="flex-1 text-left text-xs font-bold uppercase tracking-wide flex items-center gap-2">
                <span>{s.label}</span>
                {s.esHoy && (
                  <span className="rounded bg-amber-700 text-white px-1.5 py-0.5 text-[9px] tracking-wider">HOY</span>
                )}
              </h2>
              <span className="text-xs font-semibold tabular-nums">({s.items.length})</span>
              {colapsable && (
                colapsada
                  ? <ChevronDown className="h-4 w-4" />
                  : <ChevronUp className="h-4 w-4" />
              )}
            </>
          )

          return (
            <section key={s.key}>
              {colapsable ? (
                <button
                  type="button"
                  onClick={() => setCompletadasOpen((v) => !v)}
                  className={`w-full flex items-center gap-2 rounded-lg border px-3 py-2 mb-2 active:scale-[0.99] transition-transform ${headerColor}`}
                >
                  {Header}
                </button>
              ) : (
                <div className={`flex items-center gap-2 rounded-lg border px-3 py-2 mb-2 ${headerColor}`}>
                  {Header}
                </div>
              )}
              {!colapsada && (
                <div className="space-y-2">
                  {s.items.map(({ planOt, ot }) => (
                    <OTCardMobile
                      key={planOt.id}
                      ot={ot}
                      planOt={planOt}
                      estilo={cardEstilo}
                      secuencia={secuenciaByJornada.get(planOt.id)}
                      responsableNombre={
                        planOt.responsable_id
                          ? (usuariosById.get(planOt.responsable_id)?.nombre_completo
                            ?? usuariosById.get(planOt.responsable_id)?.email
                            ?? null)
                          : null
                      }
                      mostrarResponsable={verTodas}
                    />
                  ))}
                </div>
              )}
            </section>
          )
        })}
      </div>
    </div>
  )
}

function Counter({ label, value, highlight }: { label: string; value: number; highlight?: boolean }) {
  return (
    <div className={`rounded-lg px-2 py-1 text-center ${highlight ? 'bg-white text-amber-700 font-bold' : 'bg-white/10'}`}>
      <div className="text-[9px] uppercase opacity-90">{label}</div>
      <div className="text-base font-bold leading-tight">{value}</div>
    </div>
  )
}

function OTCardMobile({
  ot, planOt, estilo, secuencia, responsableNombre, mostrarResponsable,
}: {
  ot: CalamaOTConRelaciones
  planOt: CalamaJornadaAsignada
  estilo: string
  secuencia?: { idx: number; total: number }
  responsableNombre?: string | null
  mostrarResponsable?: boolean
}) {
  const codigo = excelCodigoFromFolio(ot.folio)
  const lugar = zonaCodeFromFolio(ot.folio)
  const avanceReal = Number(ot.avance_pct ?? 0)
  const avanceExcel = Number((ot as { avance_excel_pct?: number }).avance_excel_pct ?? 0)

  const estadoTxt = ot.estado === 'en_ejecucion' ? 'En ejecucion'
    : ot.estado === 'en_pausa' ? 'Pausada'
    : ot.estado === 'finalizada' ? 'Completada'
    : ot.estado === 'no_ejecutada' ? 'No ejecutada'
    : ot.estado === 'liberada' ? 'Liberada'
    : ot.estado === 'cancelada' ? 'Cancelada'
    : 'Pendiente'

  const accionTxt = ot.estado === 'en_ejecucion' ? 'Continuar' :
    ot.estado === 'en_pausa' ? 'Reanudar' :
    ot.estado === 'finalizada' ? 'Ver completada' :
    'Ejecutar'

  const accionIcon = ot.estado === 'en_ejecucion' ? <Play className="h-4 w-4" /> :
    ot.estado === 'en_pausa' ? <Pause className="h-4 w-4" /> :
    ot.estado === 'finalizada' ? <CheckCircle2 className="h-4 w-4" /> :
    <Play className="h-4 w-4" />

  const colorEstado = ot.estado === 'en_ejecucion' ? 'bg-amber-500'
    : ot.estado === 'en_pausa' ? 'bg-yellow-500'
    : ot.estado === 'finalizada' ? 'bg-green-500'
    : ot.estado === 'no_ejecutada' ? 'bg-red-500'
    : 'bg-gray-400'

  return (
    <Link
      href={`/m/calama/ot/${ot.id}`}
      className={`block rounded-xl border p-3 shadow-sm active:scale-[0.99] transition-transform ${estilo}`}
    >
      <div className="flex items-start justify-between gap-2 mb-1">
        <div className="flex items-center gap-2">
          <span className={`h-2 w-2 rounded-full ${colorEstado}`} />
          <span className="font-mono text-[11px] text-gray-600">{codigo}</span>
          <span className="text-[10px] uppercase font-medium text-gray-500">{estadoTxt}</span>
          {secuencia && secuencia.total > 1 && (
            <span className="text-[10px] rounded bg-amber-100 text-amber-800 px-1.5 py-0.5 font-mono">
              J{secuencia.idx}/{secuencia.total}
            </span>
          )}
        </div>
        <span className="text-[10px] text-gray-500">
          {planOt.fecha_jornada ?? ot.fecha_programada ?? '—'}
        </span>
      </div>

      <h3 className="font-medium text-gray-900 line-clamp-2 text-sm">{ot.titulo}</h3>

      <div className="mt-2 flex items-center gap-2 text-[11px] text-gray-600 flex-wrap">
        <span className="inline-flex items-center gap-1 rounded bg-white/70 px-1.5 py-0.5">
          <MapPin className="h-3 w-3" />
          {lugar ?? '—'}
        </span>
        <span className="inline-flex items-center gap-1">
          <span className="text-gray-500">Real</span>
          <span className="font-mono font-bold text-gray-900">{avanceReal.toFixed(0)}%</span>
        </span>
        {avanceExcel > 0 && (
          <span className="text-[10px] text-gray-500">/ Excel {avanceExcel.toFixed(0)}%</span>
        )}
        {planOt.horas_planificadas != null && (
          <span className="text-[10px] text-gray-500">· {Number(planOt.horas_planificadas).toFixed(1)}h</span>
        )}
        {planOt.avance_objetivo_pct != null && (
          <span className="text-[10px] rounded bg-blue-100 text-blue-700 px-1 py-0.5">
            objetivo {Number(planOt.avance_objetivo_pct).toFixed(0)}%
          </span>
        )}
      </div>

      {mostrarResponsable && (
        <div className="mt-2 text-[11px] text-gray-700 flex items-center gap-1">
          <span className="text-gray-500">Responsable:</span>
          <span className="font-medium">{responsableNombre ?? <span className="text-red-600">SIN ASIGNAR</span>}</span>
        </div>
      )}

      {planOt.observaciones && (
        <div className="mt-2 rounded bg-amber-100/70 border border-amber-200 px-2 py-1.5 text-[11px] text-amber-900 flex items-start gap-1">
          <MessageSquare className="h-3 w-3 mt-0.5 shrink-0" />
          <span className="line-clamp-2">{planOt.observaciones}</span>
        </div>
      )}

      {/* Barra de avance */}
      <div className="mt-2 h-1.5 w-full rounded-full bg-gray-200 overflow-hidden">
        <div
          className={`h-full ${avanceReal >= 100 ? 'bg-green-500' : avanceReal > 0 ? 'bg-amber-500' : 'bg-gray-300'}`}
          style={{ width: `${Math.max(0, Math.min(100, avanceReal))}%` }}
        />
      </div>

      <div className="mt-3 flex items-center justify-end">
        <div className="inline-flex items-center gap-1.5 rounded-full bg-amber-700 text-white px-3 py-1.5 text-xs font-semibold">
          {accionIcon}
          {accionTxt}
          <ChevronRight className="h-3 w-3 -ml-0.5" />
        </div>
      </div>
    </Link>
  )
}
