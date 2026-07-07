'use client'

import { useEffect, useMemo, useState } from 'react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import {
  Wrench, ChevronRight, RefreshCw, WifiOff, CloudOff, CheckCircle2, Play, Pause, User, LogOut,
} from 'lucide-react'
import { Spinner } from '@/components/ui/spinner'
import { useAuth } from '@/contexts/auth-context'
import { MECANICOS } from '@/lib/taller-grupos'
import {
  useMecanicoOTs, usePendingCount, useSyncTaller, useAutoSyncTaller, useNetworkStatus,
  useDescargarOffline,
} from '@/hooks/use-taller-mecanico'
import { useTallerTecnicos } from '@/hooks/use-taller-plan-semanal'
import type { MecanicoOT } from '@/lib/offline/taller-mecanico-sync'
import { Download } from 'lucide-react'

const LS_KEY = 'taller-mecanico'

function estadoBadge(estado: string) {
  switch (estado) {
    case 'en_ejecucion': return { cls: 'bg-amber-100 text-amber-800', label: 'En ejecución', icon: Play }
    case 'pausada':      return { cls: 'bg-orange-100 text-orange-800', label: 'Pausada', icon: Pause }
    default:             return { cls: 'bg-blue-100 text-blue-800', label: 'Por iniciar', icon: Wrench }
  }
}

export default function MecanicoHomePage() {
  useAutoSyncTaller()
  const online = useNetworkStatus()
  const router = useRouter()
  const { perfil, signOut } = useAuth()
  const { data: ots, isLoading, refetch, isFetching } = useMecanicoOTs()
  const { data: pendientes = 0 } = usePendingCount()
  const sync = useSyncTaller()
  const descargar = useDescargarOffline()
  const [descargaMsg, setDescargaMsg] = useState<string>('')

  // La cuenta operador_taller es COMPARTIDA por los mecánicos: ve TODAS las
  // OTs liberadas (MIG193) y cada uno elige su nombre del catálogo de técnicos
  // para filtrar/destacar las suyas (nombre en la cuadrilla del plan).
  const esOperador = perfil?.rol === 'operador_taller'
  const [soloMias, setSoloMias] = useState(false)
  const { data: tecnicosCat } = useTallerTecnicos(null)

  const [mecanico, setMecanico] = useState<string>('')
  useEffect(() => {
    const saved = typeof window !== 'undefined' ? localStorage.getItem(LS_KEY) : null
    if (saved) setMecanico(saved)
  }, [])
  function elegir(m: string) {
    setMecanico(m)
    if (typeof window !== 'undefined') localStorage.setItem(LS_KEY, m)
  }

  async function salir() {
    try { await signOut() } catch { /* noop */ }
    router.replace('/login')
  }

  // Nombres del selector "Soy:" del operador (catálogo real; MECANICOS de respaldo).
  const nombresPicker = useMemo(() => {
    const cat = (tecnicosCat ?? []).filter((t) => t.activo).map((t) => t.nombre)
    return cat.length > 0 ? cat : [...MECANICOS]
  }, [tecnicosCat])

  // ¿La OT es del mecánico elegido? Nombre completo o primer nombre en la
  // cuadrilla (planes antiguos usan nombres cortos), o asignación por cuenta.
  const esMia = useMemo(() => {
    const n = mecanico.trim().toLowerCase()
    const primer = n.split(/\s+/)[0] ?? ''
    return (o: MecanicoOT): boolean => {
      if (o.asignada_a_mi) return true
      if (!n) return false
      const c = (o.cuadrilla ?? '').toLowerCase()
      return c.includes(n) || (primer.length >= 3 && c.includes(primer))
    }
  }, [mecanico])

  const conMiNombre = useMemo(() => (ots ?? []).filter(esMia).length, [ots, esMia])

  const misOts = useMemo(() => {
    const list = ots ?? []
    if (esOperador) {
      if (soloMias) return list.filter(esMia)
      // Todas, pero las del mecánico elegido primero.
      return [...list].sort((a, b) => Number(esMia(b)) - Number(esMia(a)))
    }
    if (!mecanico) return []
    const m = mecanico.toLowerCase()
    return list.filter((o) => (o.cuadrilla ?? '').toLowerCase().includes(m))
  }, [ots, mecanico, esOperador, soloMias, esMia])

  return (
    <div className="p-3 space-y-3">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-orange-600 text-white">
            <Wrench className="h-5 w-5" />
          </div>
          <div>
            <h1 className="text-base font-bold text-gray-900 leading-tight">Taller — Mecánico</h1>
            <p className="text-[11px] text-gray-500">
              {esOperador ? (mecanico || 'Elige tu nombre') : 'Checklist de ejecución'}
            </p>
          </div>
        </div>
        {esOperador ? (
          <button onClick={salir} aria-label="Cerrar sesión" className="text-gray-400 hover:text-gray-600">
            <LogOut className="h-5 w-5" />
          </button>
        ) : (
          <Link href="/dashboard" className="text-gray-400 hover:text-gray-600"><LogOut className="h-5 w-5" /></Link>
        )}
      </div>

      {/* Estado de conexión / pendientes */}
      <div className={`flex items-center gap-2 rounded-lg border p-2.5 text-sm ${
        online ? 'border-green-200 bg-green-50 text-green-700' : 'border-amber-300 bg-amber-50 text-amber-800'}`}>
        {online ? <CheckCircle2 className="h-4 w-4" /> : <WifiOff className="h-4 w-4" />}
        <span className="font-medium">{online ? 'En línea' : 'Sin conexión — se guardará local'}</span>
        {pendientes > 0 && (
          <span className="ml-auto flex items-center gap-1 text-xs">
            <CloudOff className="h-3.5 w-3.5" /> {pendientes} por sincronizar
          </span>
        )}
        {online && pendientes > 0 && (
          <button onClick={() => sync.mutate()} disabled={sync.isPending}
                  className="ml-2 rounded-md bg-white border border-green-300 px-2 py-1 text-xs text-green-700 disabled:opacity-50">
            {sync.isPending ? 'Sincronizando…' : 'Sincronizar'}
          </button>
        )}
      </div>

      {/* Filtro del operador: todas las liberadas vs. las que traen su nombre */}
      {esOperador && (
        <div className="flex gap-2">
          <button onClick={() => setSoloMias(false)}
                  className={`rounded-full px-3 py-1.5 text-sm border ${
                    !soloMias ? 'bg-orange-600 text-white border-orange-600'
                              : 'bg-white text-gray-700 border-gray-300'}`}>
            Todas ({(ots ?? []).length})
          </button>
          <button onClick={() => setSoloMias(true)}
                  className={`rounded-full px-3 py-1.5 text-sm border ${
                    soloMias ? 'bg-orange-600 text-white border-orange-600'
                             : 'bg-white text-gray-700 border-gray-300'}`}>
            Con mi nombre ({conMiNombre})
          </button>
        </div>
      )}

      {/* Selector de mecánico: en la cuenta compartida del operador cada uno
          elige su nombre (catálogo de técnicos); perfiles del dashboard usan
          la lista corta legacy. */}
      <div>
        <div className="flex items-center gap-1 mb-1 text-xs font-medium text-gray-500">
          <User className="h-3.5 w-3.5" /> Soy:
        </div>
        <div className="flex flex-wrap gap-2">
          {(esOperador ? nombresPicker : [...MECANICOS]).map((m) => (
            <button key={m} onClick={() => elegir(m)}
                    className={`rounded-full px-3 py-1.5 text-sm border ${
                      mecanico === m ? 'bg-orange-600 text-white border-orange-600'
                                     : 'bg-white text-gray-700 border-gray-300'}`}>
              {m}
            </button>
          ))}
        </div>
      </div>

      {/* Descargar para offline */}
      {(esOperador || mecanico) && misOts.length > 0 && online && (
        <button
          onClick={() => descargar.mutate(misOts.map((o) => o.ot_id), {
            onSuccess: (n) => setDescargaMsg(`${n} OTs descargadas para usar sin internet`),
          })}
          disabled={descargar.isPending}
          className="flex w-full items-center justify-center gap-2 rounded-lg border border-orange-300 bg-orange-50 py-2 text-sm font-medium text-orange-700 disabled:opacity-50">
          {descargar.isPending ? <Spinner className="h-4 w-4" /> : <Download className="h-4 w-4" />}
          Descargar mis OTs para usar sin internet
        </button>
      )}
      {descargaMsg && <p className="text-center text-xs text-green-600">{descargaMsg}</p>}

      {/* Lista */}
      <div className="flex items-center justify-between pt-1">
        <h2 className="text-sm font-semibold text-gray-700">
          {esOperador ? (soloMias ? 'OTs con mi nombre' : 'OTs liberadas a ejecución') : 'Mis OTs liberadas'}
        </h2>
        <button onClick={() => refetch()} className="text-gray-400 hover:text-gray-600" disabled={isFetching}>
          <RefreshCw className={`h-4 w-4 ${isFetching ? 'animate-spin' : ''}`} />
        </button>
      </div>

      {!esOperador && !mecanico ? (
        <p className="py-8 text-center text-sm text-gray-400">Elige tu nombre para ver tus OTs.</p>
      ) : isLoading ? (
        <div className="flex justify-center py-8"><Spinner /></div>
      ) : misOts.length === 0 ? (
        <p className="py-8 text-center text-sm text-gray-400">
          {esOperador
            ? (soloMias
                ? (mecanico ? 'No hay OTs liberadas con tu nombre — revisa "Todas".' : 'Elige tu nombre arriba para ver tus OTs.')
                : 'No hay OTs liberadas a ejecución.')
            : 'No tienes OTs liberadas a ejecución.'}
        </p>
      ) : (
        <div className="space-y-2">
          {misOts.map((o) => {
            const b = estadoBadge(o.ot_estado)
            const Icon = b.icon
            const total = o.checklist_total ?? 0
            const hechos = o.checklist_completados ?? 0
            return (
              <Link key={o.ot_id} href={`/m/taller/ot/${o.ot_id}`}
                    className="block rounded-xl border border-gray-200 bg-white p-3 active:bg-gray-50">
                <div className="flex items-center gap-2">
                  <span className="font-mono text-xs font-bold text-gray-900">{o.ot_folio}</span>
                  {esOperador && esMia(o) && (
                    <span className="rounded-full bg-orange-100 px-2 py-0.5 text-[10px] font-medium text-orange-700">
                      ★ Mi nombre
                    </span>
                  )}
                  <span className={`ml-auto flex items-center gap-1 rounded-full px-2 py-0.5 text-[10px] font-medium ${b.cls}`}>
                    <Icon className="h-3 w-3" /> {b.label}
                  </span>
                </div>
                <div className="mt-1 text-sm font-medium text-gray-800">
                  {o.activo_codigo} {o.activo_patente && <span className="text-gray-500">· {o.activo_patente}</span>}
                </div>
                <div className="text-xs text-gray-500">{o.activo_nombre}</div>
                <div className="mt-2 flex items-center justify-between">
                  <div className="text-[11px] text-gray-500">
                    {hechos}/{total} tareas · {Math.round(((o.tiempo_estimado_total_min ?? 0) / 60) * 10) / 10} h
                  </div>
                  <ChevronRight className="h-4 w-4 text-gray-400" />
                </div>
                {total > 0 && (
                  <div className="mt-1.5 h-1.5 w-full rounded-full bg-gray-100">
                    <div className="h-1.5 rounded-full bg-orange-500"
                         style={{ width: `${Math.min(100, Math.round((hechos / total) * 100))}%` }} />
                  </div>
                )}
              </Link>
            )
          })}
        </div>
      )}
    </div>
  )
}
