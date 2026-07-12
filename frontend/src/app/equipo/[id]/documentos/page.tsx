'use client'

// Documentación vigente del equipo — pública, se llega desde el menú del QR.
// Lista el último documento por tipo con su vigencia y el PDF para revisar.

import { useParams } from 'next/navigation'
import Link from 'next/link'
import { useQuery } from '@tanstack/react-query'
import { ArrowLeft, FileText, AlertTriangle } from 'lucide-react'
import { Spinner } from '@/components/ui/spinner'
import { cn, formatDate } from '@/lib/utils'
import { TIPO_DOC_LABEL } from '@/lib/services/taller-planificacion'
import { useFichaActivo } from '@/hooks/use-activos'
import { supabase } from '@/lib/supabase'

interface DocPublico {
  tipo: string
  fecha_emision: string | null
  fecha_vencimiento: string | null
  dias_restantes: number | null
  estado: 'vigente' | 'por_vencer' | 'vencido' | 'permanente'
  archivo_url: string | null
}

const ESTADO_UI: Record<string, { label: string; cls: string }> = {
  vigente:    { label: 'Vigente',    cls: 'bg-green-100 text-green-700' },
  por_vencer: { label: 'Por vencer', cls: 'bg-yellow-100 text-yellow-700' },
  vencido:    { label: 'RENOVAR',    cls: 'bg-red-100 text-red-700' },
  permanente: { label: 'Permanente', cls: 'bg-gray-100 text-gray-600' },
}
const ORDEN_ESTADO: Record<string, number> = { vencido: 0, por_vencer: 1, vigente: 2, permanente: 3 }

export default function DocumentosEquipoPage() {
  const params = useParams()
  const id = params.id as string
  const { data: ficha } = useFichaActivo(id)
  const { data: docs = [], isLoading } = useQuery({
    queryKey: ['docs-publicos', id],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('rpc_documentos_activo_publico', { p_activo_id: id })
      if (error) throw error
      return (data ?? []) as DocPublico[]
    },
    enabled: !!id,
    staleTime: 60_000,
  })

  const f = ficha as any
  const ordenados = [...docs].sort((a, b) =>
    (ORDEN_ESTADO[a.estado] ?? 9) - (ORDEN_ESTADO[b.estado] ?? 9) ||
    (TIPO_DOC_LABEL[a.tipo] ?? a.tipo).localeCompare(TIPO_DOC_LABEL[b.tipo] ?? b.tipo))
  const vencidos = docs.filter((d) => d.estado === 'vencido').length

  return (
    <div className="flex min-h-screen items-start justify-center bg-gray-100 px-4 py-8">
      <div className="w-full max-w-md rounded-2xl bg-white shadow-lg overflow-hidden">
        <div className="flex flex-col items-center gap-1 border-b border-gray-100 px-6 py-5">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/images/logo_empresa_2.png" alt="Pillado Empresas" className="h-10 object-contain" />
          <p className="text-xs font-medium tracking-wide text-gray-400 uppercase">Documentación vigente</p>
          {f && (
            <p className="font-mono text-lg font-bold text-gray-900">
              {f.patente ?? f.codigo}
              {f.nombre && <span className="ml-2 font-sans text-xs font-normal text-gray-500">{f.nombre}</span>}
            </p>
          )}
        </div>

        <div className="px-4 py-4 space-y-2">
          <Link href={`/equipo/${id}`}
                className="inline-flex items-center gap-1 text-xs font-medium text-gray-500 hover:text-gray-700">
            <ArrowLeft className="h-3.5 w-3.5" /> Volver a la ficha
          </Link>

          {vencidos > 0 && (
            <div className="flex items-center gap-2 rounded-lg border border-red-200 bg-red-50 px-3 py-2 text-xs font-medium text-red-700">
              <AlertTriangle className="h-4 w-4 shrink-0" />
              {vencidos} documento{vencidos > 1 ? 's' : ''} requiere{vencidos > 1 ? 'n' : ''} renovación.
            </div>
          )}

          {isLoading ? (
            <div className="flex justify-center py-10"><Spinner /></div>
          ) : ordenados.length === 0 ? (
            <p className="py-10 text-center text-sm text-gray-400">Este equipo aún no tiene documentos cargados.</p>
          ) : (
            <div className="space-y-1.5">
              {ordenados.map((d) => {
                const ui = ESTADO_UI[d.estado] ?? ESTADO_UI.permanente
                return (
                  <div key={d.tipo} className="flex items-center gap-2 rounded-lg border border-gray-100 bg-gray-50/60 px-2.5 py-2">
                    <FileText className="h-4 w-4 shrink-0 text-gray-300" />
                    <div className="flex-1 min-w-0">
                      <p className="truncate text-xs font-medium text-gray-800">{TIPO_DOC_LABEL[d.tipo] ?? d.tipo}</p>
                      {d.estado !== 'permanente' && d.fecha_vencimiento && (
                        <p className={cn('text-[10px]',
                          d.estado === 'vencido' ? 'text-red-600 font-semibold'
                            : d.estado === 'por_vencer' ? 'text-yellow-600' : 'text-gray-400')}>
                          Vence {formatDate(d.fecha_vencimiento)}
                          {d.estado === 'vencido' && ' — solicitar documento renovado'}
                        </p>
                      )}
                    </div>
                    <span className={cn('rounded-full px-2 py-0.5 text-[9px] font-bold shrink-0', ui.cls)}>{ui.label}</span>
                    {d.archivo_url ? (
                      <a href={d.archivo_url} target="_blank" rel="noreferrer"
                         className="shrink-0 rounded-lg border border-pillado-green-600 px-2 py-1 text-[10px] font-semibold text-pillado-green-600 hover:bg-pillado-green-50">
                        Ver
                      </a>
                    ) : (
                      <span className="shrink-0 text-[9px] text-gray-300">sin PDF</span>
                    )}
                  </div>
                )
              })}
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
