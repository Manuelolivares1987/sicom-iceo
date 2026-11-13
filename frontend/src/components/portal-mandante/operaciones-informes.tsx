'use client'

// ============================================================================
// Portal del mandante — informes de operaciones (MIG688)
// ----------------------------------------------------------------------------
// Calibraciones y mantenciones del contrato ENEX: lo programado, lo ejecutado
// y el informe PDF de cada servicio (certificado de calibración / OT de
// mantenimiento), tal como se entrega al mandante.
// ============================================================================

import { useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { FileDown } from 'lucide-react'
import { Spinner } from '@/components/ui/spinner'
import { cn } from '@/lib/utils'
import { MESES, getOperacionesPortal } from './portal-mandante-api'

const fmt = (s: string | null) => s ? new Date(s.slice(0, 10) + 'T12:00:00').toLocaleDateString('es-CL', { day: '2-digit', month: 'short' }) : '—'
const ESTADO: Record<string, { t: string, c: string }> = {
  ejecutada: { t: 'Ejecutada', c: 'bg-emerald-100 text-emerald-800' },
  cumplida: { t: 'Cumplida', c: 'bg-emerald-100 text-emerald-800' },
  no_realizada: { t: 'No realizada', c: 'bg-red-100 text-red-800' },
  pendiente: { t: 'Programada', c: 'bg-slate-100 text-slate-600' },
}

export function OperacionesInformes({ token, acceso, anio, mes }: {
  token: string, acceso: string, anio: number, mes: number | null
}) {
  const [tipo, setTipo] = useState<'todos' | 'calibracion' | 'mantencion'>('todos')
  const { data, isLoading, error } = useQuery({
    queryKey: ['portal-ops', token, acceso, anio, mes],
    queryFn: () => getOperacionesPortal(token, acceso, anio, mes),
    staleTime: 60_000,
    retry: false,
  })

  const lista = useMemo(() => (data?.servicios ?? []).filter((s) => tipo === 'todos' || s.tipo_servicio === tipo), [data, tipo])
  const resumen = useMemo(() => {
    const hoy = new Date().toISOString().slice(0, 10)
    const vencidos = lista.filter((s) => !s.fecha_programada || s.fecha_programada <= hoy)
    const hechos = vencidos.filter((s) => ['ejecutada', 'cumplida'].includes(s.estado))
    return {
      programados: lista.length,
      ejecutados: lista.filter((s) => ['ejecutada', 'cumplida'].includes(s.estado)).length,
      conInforme: lista.filter((s) => s.informe_pdf_url).length,
      cumplimiento: vencidos.length ? Math.round((100 * hechos.length) / vencidos.length) : null,
    }
  }, [lista])

  if (isLoading) return <div className="flex justify-center py-10"><Spinner /></div>
  if (error) return <p className="text-sm text-red-600">{(error as Error).message}</p>

  return (
    <section className="space-y-3">
      <div className="border-b border-slate-200 pb-2">
        <h3 className="text-sm font-bold uppercase tracking-wide text-slate-800">
          Informes de servicio — {mes ? `${MESES[mes - 1]} ${anio}` : `año ${anio}`}
        </h3>
        <p className="mt-0.5 text-xs text-slate-500">
          Calibraciones (certificado de verificación de volúmenes) y mantenciones (OT de mantenimiento) del contrato.
        </p>
      </div>

      <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
        {[
          ['Programados', resumen.programados],
          ['Ejecutados', resumen.ejecutados],
          ['Con informe', resumen.conInforme],
          ['Cumplimiento a la fecha', resumen.cumplimiento == null ? '—' : `${resumen.cumplimiento}%`],
        ].map(([k, v]) => (
          <div key={k as string} className="rounded-lg border border-slate-200 bg-white px-3 py-2">
            <p className="text-[10px] font-semibold uppercase text-slate-400">{k}</p>
            <p className="text-lg font-bold text-slate-800">{v}</p>
          </div>
        ))}
      </div>

      <div className="flex gap-1.5">
        {(['todos', 'calibracion', 'mantencion'] as const).map((t) => (
          <button key={t} onClick={() => setTipo(t)}
                  className={cn('rounded-full px-3 py-1 text-[11px] font-semibold ring-1',
                    tipo === t ? 'bg-slate-900 text-white ring-slate-900' : 'bg-white text-slate-600 ring-slate-200')}>
            {t === 'todos' ? 'Todos' : t === 'calibracion' ? 'Calibraciones' : 'Mantenciones'}
          </button>
        ))}
      </div>

      {!lista.length ? (
        <p className="rounded-xl border border-dashed border-slate-300 bg-white py-5 text-center text-xs text-slate-400">Sin servicios en el período.</p>
      ) : (
        <div className="overflow-x-auto rounded-xl border border-slate-200 bg-white">
          <table className="w-full text-xs">
            <thead className="bg-slate-50 text-left text-[10px] uppercase text-slate-500">
              <tr><th className="px-3 py-2">Instalación</th><th>Servicio</th><th>Programado</th><th>Ejecutado</th><th>Estado</th><th>OT / técnico</th><th className="pr-3 text-right">Informe</th></tr>
            </thead>
            <tbody>
              {lista.map((s) => {
                const e = ESTADO[s.estado] ?? { t: s.estado, c: 'bg-slate-100 text-slate-600' }
                return (
                  <tr key={s.programacion_id} className="border-t border-slate-100">
                    <td className="px-3 py-2">
                      <p className="font-medium text-slate-900">{s.instalacion}</p>
                      <p className="text-[10px] text-slate-400">{s.faena}{s.patente ? ` · ${s.patente}` : ''}{s.linea ? ` · ${s.linea}` : ''}</p>
                    </td>
                    <td className="capitalize">{s.tipo_servicio === 'calibracion' ? 'Calibración' : 'Mantención'}</td>
                    <td className="whitespace-nowrap">{fmt(s.fecha_programada)}</td>
                    <td className="whitespace-nowrap">{fmt(s.fecha_ejecucion)}</td>
                    <td><span className={cn('rounded-full px-2 py-0.5 text-[10px] font-bold', e.c)}>{e.t}</span></td>
                    <td className="text-[11px] text-slate-600">{[s.ot_numero, s.tecnico].filter(Boolean).join(' · ') || '—'}</td>
                    <td className="pr-3 text-right">
                      {s.informe_pdf_url ? (
                        <a href={s.informe_pdf_url} target="_blank" rel="noopener noreferrer"
                           className="inline-flex items-center gap-1 rounded-lg border border-slate-300 px-2 py-1 text-[11px] font-semibold text-slate-700 hover:bg-slate-50">
                          <FileDown className="h-3.5 w-3.5" /> PDF
                        </a>
                      ) : ['ejecutada', 'cumplida'].includes(s.estado)
                        ? <span className="text-[10px] text-slate-400">En preparación</span>
                        : <span className="text-[10px] text-slate-300">—</span>}
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
      )}
    </section>
  )
}
