'use client'

// Terreno ENEX — lista de instalaciones programadas por período (MIG208).
// El mantenedor elige una y ejecuta su pauta.

import { useEffect, useMemo, useState } from 'react'
import Link from 'next/link'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import {
  Building2, ChevronRight, ChevronLeft, CheckCircle2, Clock, RefreshCw, AlertTriangle,
  WifiOff, CloudOff, Download,
} from 'lucide-react'
import { Spinner } from '@/components/ui/spinner'
import { MESES, TIPO_INSTALACION_LABEL, type EnexPendiente } from '@/lib/services/enex'
import { getPendientesOffline, prepararEnexOffline, getEnexPendingCount, syncEnexPending } from '@/lib/offline/enex-offline'
import { useNetworkStatus } from '@/hooks/use-calama-offline'

const hoy = () => { const d = new Date(); return { anio: d.getFullYear(), mes: d.getMonth() + 1 } }

export default function EnexTerrenoHome() {
  // El período parte NULL y se fija tras el mount: la página se prerenderiza
  // en el build y usar new Date() en el primer render hidrata mal (React #418)
  // cuando la fecha del build difiere de la del teléfono.
  const [periodo, setPeriodo] = useState<{ anio: number; mes: number } | null>(null)
  useEffect(() => { setPeriodo(hoy()) }, [])
  const anio = periodo?.anio ?? 0
  const mes = periodo?.mes ?? 1
  const qc = useQueryClient()
  const online = useNetworkStatus()
  const [descargaMsg, setDescargaMsg] = useState('')
  const { data: pend = [], isLoading, refetch, isFetching } = useQuery({
    queryKey: ['enex-terreno', anio, mes], queryFn: () => getPendientesOffline(anio, mes),
    networkMode: 'always', staleTime: 10_000, enabled: periodo !== null,
  })
  const { data: pendientesSync = 0 } = useQuery({
    queryKey: ['enex-pending-count'], queryFn: getEnexPendingCount, networkMode: 'always', refetchInterval: 4000,
  })

  // Sincroniza al recuperar conexión
  useEffect(() => {
    const trySync = async () => {
      if (typeof navigator !== 'undefined' && navigator.onLine) {
        const r = await syncEnexPending()
        if (r.ok > 0 || r.failed > 0) { qc.invalidateQueries({ queryKey: ['enex-terreno'] }); qc.invalidateQueries({ queryKey: ['enex-pending-count'] }) }
      }
    }
    window.addEventListener('online', trySync); void trySync()
    return () => window.removeEventListener('online', trySync)
  }, [qc])

  function cambiarMes(d: number) {
    let m = mes + d, a = anio
    if (m < 1) { m = 12; a-- } else if (m > 12) { m = 1; a++ }
    setPeriodo({ anio: a, mes: m })
  }

  const porFaena = useMemo(() => {
    const g: { faena: string; items: EnexPendiente[] }[] = []
    for (const p of [...pend].sort((a, b) => Number(a.cumplida) - Number(b.cumplida))) {
      let x = g.find((y) => y.faena === p.faena)
      if (!x) { x = { faena: p.faena, items: [] }; g.push(x) }
      x.items.push(p)
    }
    return g
  }, [pend])

  const pendientes = pend.filter((p) => !p.cumplida).length

  // Primer render (SSR/hidratación) sin fecha: contenido determinista.
  if (!periodo) return <div className="flex justify-center py-10"><Spinner /></div>

  return (
    <div className="p-3 space-y-3">
      <div className="flex items-center gap-2">
        <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-blue-700 text-white"><Building2 className="h-5 w-5" /></div>
        <div className="flex-1">
          <h1 className="text-base font-bold leading-tight">Terreno ENEX</h1>
          <p className="text-[11px] text-gray-500">Mantención y calibración de instalaciones</p>
        </div>
        <button onClick={() => refetch()} className="text-gray-400"><RefreshCw className={`h-4 w-4 ${isFetching ? 'animate-spin' : ''}`} /></button>
      </div>

      {/* Estado de conexión / cola */}
      <div className={`flex items-center gap-2 rounded-lg border p-2 text-xs ${online ? 'border-green-200 bg-green-50 text-green-700' : 'border-amber-300 bg-amber-50 text-amber-800'}`}>
        {online ? <CheckCircle2 className="h-3.5 w-3.5" /> : <WifiOff className="h-3.5 w-3.5" />}
        <span className="font-medium">{online ? 'En línea' : 'Sin conexión — se guarda local'}</span>
        {pendientesSync > 0 && <span className="ml-auto flex items-center gap-1"><CloudOff className="h-3 w-3" /> {pendientesSync} por sincronizar</span>}
      </div>
      {online && pend.length > 0 && (
        <button onClick={async () => { const n = await prepararEnexOffline(anio, mes); setDescargaMsg(`${n} servicios descargados para usar sin internet`) }}
                className="flex w-full items-center justify-center gap-2 rounded-lg border border-blue-300 bg-blue-50 py-2 text-xs font-medium text-blue-700">
          <Download className="h-4 w-4" /> Descargar el mes para trabajar sin señal
        </button>
      )}
      {descargaMsg && <p className="text-center text-[11px] text-green-600">{descargaMsg}</p>}

      <div className="flex items-center justify-center gap-3">
        <button onClick={() => cambiarMes(-1)} className="rounded-lg border bg-white px-2 py-1.5"><ChevronLeft className="h-4 w-4" /></button>
        <span className="min-w-[120px] text-center text-sm font-semibold">{MESES[mes - 1]} {anio}</span>
        <button onClick={() => cambiarMes(1)} className="rounded-lg border bg-white px-2 py-1.5"><ChevronRight className="h-4 w-4" /></button>
      </div>

      <div className="rounded-lg border border-blue-200 bg-blue-50 px-3 py-2 text-sm text-blue-800">
        {pendientes} servicio{pendientes !== 1 ? 's' : ''} por ejecutar este período
      </div>

      {isLoading ? (
        <div className="flex justify-center py-10"><Spinner /></div>
      ) : pend.length === 0 ? (
        <p className="py-10 text-center text-sm text-gray-400">No hay servicios programados en {MESES[mes - 1]} {anio}. El planificador los programa desde el panel de control.</p>
      ) : porFaena.map((g) => (
        <div key={g.faena}>
          <div className="sticky top-0 z-10 bg-gray-100 rounded px-2 py-1 text-xs font-semibold text-gray-700">{g.faena}</div>
          <div className="space-y-2 pt-2">
            {g.items.map((p) => (
              <Link key={p.programacion_id} href={`/m/enex/${p.programacion_id}`}
                    className="block rounded-xl border border-gray-200 bg-white p-3 active:bg-gray-50">
                <div className="flex items-center gap-2">
                  <span className="flex-1 text-sm font-medium text-gray-800">
                    {p.instalacion}
                    {p.patente && <span className="text-gray-500"> · {p.patente}</span>}
                  </span>
                  {p.cumplida
                    ? <span className="flex items-center gap-1 rounded-full bg-green-100 px-2 py-0.5 text-[10px] font-medium text-green-700"><CheckCircle2 className="h-3 w-3" /> Cumplida</span>
                    : p.estado === 'ejecutada'
                    ? <span className="flex items-center gap-1 rounded-full bg-amber-100 px-2 py-0.5 text-[10px] font-medium text-amber-800"><Clock className="h-3 w-3" /> Falta firma</span>
                    : <span className="flex items-center gap-1 rounded-full bg-blue-100 px-2 py-0.5 text-[10px] font-medium text-blue-700"><Clock className="h-3 w-3" /> Por ejecutar</span>}
                </div>
                <div className="mt-1 flex items-center justify-between text-xs text-gray-500">
                  <span>
                    {TIPO_INSTALACION_LABEL[p.instalacion_tipo]} · {p.tipo_servicio === 'calibracion' ? 'Calibración' : 'Mantención'} · {p.pauta_items} ítems
                    {/* Con varias visitas del mismo punto en el mes, la fecha distingue cuál es cuál */}
                    {p.fecha_programada && (
                      <span className="ml-1 font-semibold text-blue-700">
                        · visita del {p.fecha_programada.slice(8, 10)}/{p.fecha_programada.slice(5, 7)}
                      </span>
                    )}
                  </span>
                  <ChevronRight className="h-4 w-4 text-gray-400" />
                </div>
                {p.pauta_borrador && (
                  <div className="mt-1 flex items-center gap-1 text-[10px] text-amber-600"><AlertTriangle className="h-3 w-3" /> pauta en borrador</div>
                )}
                {!p.pauta_id && (
                  <div className="mt-1 flex items-center gap-1 text-[10px] text-red-600"><AlertTriangle className="h-3 w-3" /> sin pauta asignada — avisa al supervisor</div>
                )}
              </Link>
            ))}
          </div>
        </div>
      ))}
    </div>
  )
}
