'use client'

// Terreno ENEX — lista de instalaciones programadas por período (MIG208).
// El mantenedor elige una y ejecuta su pauta.

import { useMemo, useState } from 'react'
import Link from 'next/link'
import { useQuery } from '@tanstack/react-query'
import { Building2, ChevronRight, ChevronLeft, CheckCircle2, Clock, RefreshCw, AlertTriangle } from 'lucide-react'
import { Spinner } from '@/components/ui/spinner'
import { getTerrenoPendientes, MESES, TIPO_INSTALACION_LABEL, type EnexPendiente } from '@/lib/services/enex'

const hoy = () => { const d = new Date(); return { anio: d.getFullYear(), mes: d.getMonth() + 1 } }

export default function EnexTerrenoHome() {
  const [{ anio, mes }, setPeriodo] = useState(hoy())
  const { data: pend = [], isLoading, refetch, isFetching } = useQuery({
    queryKey: ['enex-terreno', anio, mes], queryFn: () => getTerrenoPendientes(anio, mes), staleTime: 10_000,
  })

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
                  <span>{TIPO_INSTALACION_LABEL[p.instalacion_tipo]} · {p.tipo_servicio === 'calibracion' ? 'Calibración' : 'Mantención'} · {p.pauta_items} ítems</span>
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
