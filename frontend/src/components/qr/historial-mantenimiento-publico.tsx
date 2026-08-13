'use client'

// Historial de mantenimiento del equipo, para el QR que escanea el cliente.
//
// Va sin plata: qué se hizo y cuándo, no lo que costó. Los montos, las horas
// hombre y los recobros son conversación comercial, no ficha técnica.

import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Wrench, ChevronDown, ChevronRight, AlertTriangle } from 'lucide-react'
import { supabase } from '@/lib/supabase'

type EventoHistorial = {
  fecha: string | null
  tipo: string
  titulo: string
  detalle: string | null
  folio: string | null
  kilometraje: number | null
  horometro: number | null
  con_observacion: boolean
}

const fmtFecha = (f: string | null) =>
  f ? new Date(f + 'T12:00:00').toLocaleDateString('es-CL', { day: 'numeric', month: 'long', year: 'numeric' }) : 'Sin fecha'

export function HistorialMantenimientoPublico({ activoId }: { activoId: string }) {
  const [abierto, setAbierto] = useState(false)

  const { data: eventos = [], isLoading } = useQuery({
    queryKey: ['historial-publico', activoId],
    queryFn: async () => {
      const { data, error } = await supabase
        .rpc('rpc_historial_mantenimiento_publico', { p_activo_id: activoId })
      if (error) throw error
      return (data ?? []) as EventoHistorial[]
    },
    enabled: !!activoId,
    staleTime: 60_000,
  })

  return (
    <div className="rounded-xl border-2 border-gray-200 bg-white">
      <button onClick={() => setAbierto((v) => !v)}
              className="flex w-full items-center gap-3 px-4 py-3 text-left hover:bg-gray-50">
        <span className="text-2xl">🔧</span>
        <span className="flex-1">
          <span className="block text-sm font-bold text-gray-900">Historial de mantenimiento</span>
          <span className="block text-[11px] text-gray-500">
            {isLoading ? 'Cargando…'
              : eventos.length > 0
                ? `${eventos.length} trabajo${eventos.length === 1 ? '' : 's'} registrado${eventos.length === 1 ? '' : 's'}`
                : 'Todavía sin trabajos registrados'}
          </span>
        </span>
        {abierto ? <ChevronDown className="h-4 w-4 text-gray-400" /> : <ChevronRight className="h-4 w-4 text-gray-400" />}
      </button>

      {abierto && (
        <div className="border-t border-gray-100 px-4 py-3">
          {eventos.length === 0 ? (
            <p className="py-2 text-center text-xs text-gray-400">
              Cuando se le haga una mantención a este equipo, aparecerá aquí.
            </p>
          ) : (
            <ol className="space-y-3">
              {eventos.map((e, i) => (
                <li key={`${e.folio ?? i}-${i}`} className="relative pl-5">
                  {/* Línea de tiempo: el punto y el hilo que une los trabajos */}
                  <span className="absolute left-0 top-1.5 h-2.5 w-2.5 rounded-full bg-pillado-green-500" />
                  {i < eventos.length - 1 && (
                    <span className="absolute left-[4px] top-5 h-full w-0.5 bg-gray-200" />
                  )}
                  <p className="text-xs font-semibold text-gray-900">{e.tipo}</p>
                  <p className="text-[11px] text-gray-500">
                    {fmtFecha(e.fecha)}
                    {e.folio && <span className="ml-1 font-mono text-[10px] text-gray-400">{e.folio}</span>}
                  </p>
                  {e.detalle && (
                    <p className="mt-0.5 whitespace-pre-wrap text-[11px] leading-snug text-gray-700">{e.detalle}</p>
                  )}
                  {(e.kilometraje || e.horometro) && (
                    <p className="mt-0.5 text-[10px] text-gray-400">
                      {e.kilometraje ? `${Number(e.kilometraje).toLocaleString('es-CL')} km` : ''}
                      {e.kilometraje && e.horometro ? ' · ' : ''}
                      {e.horometro ? `${Number(e.horometro).toLocaleString('es-CL')} hrs` : ''}
                    </p>
                  )}
                  {e.con_observacion && (
                    <p className="mt-1 inline-flex items-center gap-1 rounded bg-amber-50 px-1.5 py-0.5 text-[10px] font-medium text-amber-800">
                      <AlertTriangle className="h-3 w-3" /> Quedó con observaciones
                    </p>
                  )}
                </li>
              ))}
            </ol>
          )}
          <p className="mt-3 flex items-start gap-1 border-t border-gray-100 pt-2 text-[10px] text-gray-400">
            <Wrench className="mt-px h-3 w-3 shrink-0" />
            Registro de los trabajos realizados por Pillado y Cía. Ltda.
          </p>
        </div>
      )}
    </div>
  )
}
