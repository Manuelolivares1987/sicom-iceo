'use client'

import { useMemo } from 'react'
import Link from 'next/link'
import {
  RefreshCw, MapPin, MessageSquare, ChevronRight, AlertTriangle,
  Calendar, LogOut, ClipboardCheck, CheckCircle2, Play, Pause,
} from 'lucide-react'
import { Spinner } from '@/components/ui/spinner'
import { useAuth } from '@/contexts/auth-context'
import { useMisOTsAsignadas } from '@/hooks/use-calama-plan-semanal'
import { useCalamaOTs } from '@/hooks/use-calama'
import { useQueryClient } from '@tanstack/react-query'
import {
  excelCodigoFromFolio, zonaCodeFromFolio,
  type CalamaOTConRelaciones,
} from '@/lib/services/calama'
import type { CalamaPlanOT } from '@/lib/services/calama-plan-semanal'

type Grupo = 'atrasadas' | 'hoy' | 'manana' | 'semana' | 'completadas'

const GRUPOS_CFG: Record<Grupo, { label: string; color: string; icon: React.ReactNode }> = {
  atrasadas:    { label: 'Atrasadas',     color: 'border-red-200 bg-red-50',     icon: <AlertTriangle className="h-4 w-4 text-red-600" /> },
  hoy:          { label: 'Hoy',           color: 'border-amber-200 bg-amber-50', icon: <Calendar className="h-4 w-4 text-amber-700" /> },
  manana:       { label: 'Manana',        color: 'border-blue-200 bg-blue-50',   icon: <Calendar className="h-4 w-4 text-blue-700" /> },
  semana:       { label: 'Esta semana',   color: 'border-gray-200 bg-white',     icon: <Calendar className="h-4 w-4 text-gray-600" /> },
  completadas:  { label: 'Completadas',   color: 'border-green-200 bg-green-50', icon: <CheckCircle2 className="h-4 w-4 text-green-700" /> },
}

function isoToday(): string { return new Date().toISOString().slice(0, 10) }
function isoTomorrow(): string {
  const d = new Date(); d.setDate(d.getDate() + 1)
  return d.toISOString().slice(0, 10)
}
function startOfWeekISO(): string {
  const d = new Date(); const dow = d.getDay()
  const diff = (dow === 0 ? -6 : 1) - dow
  d.setDate(d.getDate() + diff)
  return d.toISOString().slice(0, 10)
}
function endOfWeekISO(): string {
  const d = new Date(startOfWeekISO()); d.setDate(d.getDate() + 6)
  return d.toISOString().slice(0, 10)
}

export default function MobileCalamaPage() {
  const { perfil, signOut } = useAuth()
  const qc = useQueryClient()
  const { data: planOts, isLoading } = useMisOTsAsignadas()
  const { data: ots } = useCalamaOTs()

  const otsById = useMemo(
    () => new Map((ots ?? []).map((o) => [o.id, o])),
    [ots],
  )

  const grupos = useMemo(() => {
    const today = isoToday()
    const tomorrow = isoTomorrow()
    const weekStart = startOfWeekISO()
    const weekEnd = endOfWeekISO()
    const result: Record<Grupo, Array<{ planOt: CalamaPlanOT; ot: CalamaOTConRelaciones }>> = {
      atrasadas: [], hoy: [], manana: [], semana: [], completadas: [],
    }
    for (const p of planOts ?? []) {
      const ot = otsById.get(p.ot_id)
      if (!ot) continue
      const fecha = ot.fecha_programada ?? ''
      if (ot.estado === 'finalizada' || ot.estado === 'cancelada') {
        result.completadas.push({ planOt: p, ot })
        continue
      }
      if (fecha && fecha < today) {
        result.atrasadas.push({ planOt: p, ot })
        continue
      }
      if (fecha === today) { result.hoy.push({ planOt: p, ot }); continue }
      if (fecha === tomorrow) { result.manana.push({ planOt: p, ot }); continue }
      if (fecha >= weekStart && fecha <= weekEnd) { result.semana.push({ planOt: p, ot }); continue }
      result.semana.push({ planOt: p, ot })
    }
    return result
  }, [planOts, otsById])

  const counts = useMemo(() => {
    let pendientes = 0, en_ejecucion = 0, pausadas = 0, completadas = 0
    for (const p of planOts ?? []) {
      if (p.estado_plan === 'finalizada') completadas++
      else if (p.estado_plan === 'en_ejecucion') en_ejecucion++
      else if (p.estado_plan === 'pausada') pausadas++
      else pendientes++
    }
    return { pendientes, en_ejecucion, pausadas, completadas, total: (planOts?.length ?? 0) }
  }, [planOts])

  const refresh = () => {
    qc.invalidateQueries({ queryKey: ['calama-mis-ots'] })
    qc.invalidateQueries({ queryKey: ['calama', 'ots'] })
  }

  const ordenGrupos: Grupo[] = ['atrasadas', 'hoy', 'manana', 'semana', 'completadas']
  const totalVisibles = ordenGrupos.reduce((acc, g) => acc + grupos[g].length, 0)

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
        <div className="grid grid-cols-4 gap-1 px-3 pb-3 text-[10px]">
          <Counter label="Pend." value={counts.pendientes} />
          <Counter label="Ejec." value={counts.en_ejecucion} highlight={counts.en_ejecucion > 0} />
          <Counter label="Pausa" value={counts.pausadas} />
          <Counter label="OK" value={counts.completadas} />
        </div>
      </header>

      <div className="px-3 space-y-3">
        {isLoading && (
          <div className="flex items-center justify-center gap-2 py-8 text-gray-500 text-sm">
            <Spinner className="h-4 w-4" /> Cargando…
          </div>
        )}

        {!isLoading && totalVisibles === 0 && (
          <div className="rounded-xl border border-gray-200 bg-white p-6 text-center">
            <ClipboardCheck className="mx-auto h-10 w-10 text-gray-300" />
            <p className="mt-3 font-medium text-gray-700">No tienes OTs asignadas</p>
            <p className="mt-1 text-sm text-gray-500">
              Contacta a tu supervisor o planificador para que te asigne tareas.
            </p>
          </div>
        )}

        {ordenGrupos.map((g) => {
          const items = grupos[g]
          if (items.length === 0) return null
          const cfg = GRUPOS_CFG[g]
          return (
            <section key={g}>
              <div className="flex items-center gap-2 px-1 mb-2">
                {cfg.icon}
                <h2 className="text-xs font-bold uppercase tracking-wide text-gray-700">
                  {cfg.label} ({items.length})
                </h2>
              </div>
              <div className="space-y-2">
                {items.map(({ planOt, ot }) => (
                  <OTCardMobile
                    key={ot.id}
                    ot={ot}
                    planOt={planOt}
                    estilo={cfg.color}
                  />
                ))}
              </div>
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
  ot, planOt, estilo,
}: {
  ot: CalamaOTConRelaciones
  planOt: CalamaPlanOT
  estilo: string
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
        </div>
        <span className="text-[10px] text-gray-500">{ot.fecha_programada}</span>
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
      </div>

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
