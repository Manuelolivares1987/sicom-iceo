'use client'

// Historial de mantenimiento del equipo, como página propia del menú del QR.
//
// Estaba como acordeón dentro de la ficha, escondido bajo los datos técnicos.
// El cliente escanea el QR para resolver una duda concreta —"¿qué le han
// hecho a esta máquina?"— y eso merece su propia pantalla, al mismo nivel que
// los documentos y el checklist.

import Link from 'next/link'
import { useParams } from 'next/navigation'
import { useQuery } from '@tanstack/react-query'
import { ChevronLeft, AlertTriangle, Wrench } from 'lucide-react'
import { Spinner } from '@/components/ui/spinner'
import { supabase } from '@/lib/supabase'
import { useFichaActivo } from '@/hooks/use-activos'

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

export default function HistorialEquipoPage() {
  const { id } = useParams<{ id: string }>()
  const { data: ficha } = useFichaActivo(id)
  const f = ficha as { codigo?: string; nombre?: string } | undefined

  const { data: eventos = [], isLoading } = useQuery({
    queryKey: ['historial-publico', id],
    queryFn: async () => {
      const { data, error } = await supabase
        .rpc('rpc_historial_mantenimiento_publico', { p_activo_id: id })
      if (error) throw error
      return (data ?? []) as EventoHistorial[]
    },
    enabled: !!id,
    staleTime: 60_000,
  })

  return (
    <div className="flex min-h-screen items-start justify-center bg-gray-100 px-4 py-8">
      <div className="w-full max-w-md overflow-hidden rounded-2xl bg-white shadow-lg">
        <div className="border-b border-gray-100 px-5 py-4">
          <Link href={`/equipo/${id}`} className="inline-flex items-center gap-1 text-xs font-medium text-gray-500 hover:text-gray-800">
            <ChevronLeft className="h-3.5 w-3.5" /> Volver al menú
          </Link>
          <h1 className="mt-2 flex items-center gap-2 text-lg font-bold text-gray-900">
            <span className="text-2xl">🔧</span> Historial de mantenimiento
          </h1>
          {f?.codigo && (
            <p className="text-sm text-gray-500">
              {f.codigo}{f.nombre ? ` · ${f.nombre}` : ''}
            </p>
          )}
        </div>

        <div className="px-5 py-4">
          {isLoading ? (
            <div className="flex justify-center py-8"><Spinner className="h-6 w-6 text-pillado-green-600" /></div>
          ) : eventos.length === 0 ? (
            <div className="py-8 text-center">
              <p className="text-sm font-medium text-gray-600">Todavía sin trabajos registrados</p>
              <p className="mt-1 text-xs text-gray-400">
                Cuando se le haga una mantención a este equipo, va a aparecer acá.
              </p>
            </div>
          ) : (
            <ol className="space-y-4">
              {eventos.map((e, i) => (
                <li key={`${e.folio ?? i}-${i}`} className="relative pl-5">
                  <span className="absolute left-0 top-1.5 h-2.5 w-2.5 rounded-full bg-pillado-green-500" />
                  {i < eventos.length - 1 && (
                    <span className="absolute left-[4px] top-5 h-full w-0.5 bg-gray-200" />
                  )}
                  <p className="text-sm font-semibold text-gray-900">{e.tipo}</p>
                  <p className="text-xs text-gray-500">
                    {fmtFecha(e.fecha)}
                    {e.folio && <span className="ml-1.5 font-mono text-[10px] text-gray-400">{e.folio}</span>}
                  </p>
                  {e.detalle && (
                    <p className="mt-1 whitespace-pre-wrap text-xs leading-relaxed text-gray-700">{e.detalle}</p>
                  )}
                  {(e.kilometraje || e.horometro) && (
                    <p className="mt-1 text-[11px] text-gray-400">
                      {e.kilometraje ? `${Number(e.kilometraje).toLocaleString('es-CL')} km` : ''}
                      {e.kilometraje && e.horometro ? ' · ' : ''}
                      {e.horometro ? `${Number(e.horometro).toLocaleString('es-CL')} hrs` : ''}
                    </p>
                  )}
                  {e.con_observacion && (
                    <p className="mt-1.5 inline-flex items-center gap-1 rounded bg-amber-50 px-2 py-1 text-[11px] font-medium text-amber-800">
                      <AlertTriangle className="h-3 w-3" /> Quedó con observaciones
                    </p>
                  )}
                </li>
              ))}
            </ol>
          )}
        </div>

        <div className="flex items-start gap-1.5 border-t border-gray-100 px-5 py-3 text-[11px] text-gray-400">
          <Wrench className="mt-px h-3 w-3 shrink-0" />
          Trabajos realizados por Pillado y Cía. Ltda.
        </div>
      </div>
    </div>
  )
}
