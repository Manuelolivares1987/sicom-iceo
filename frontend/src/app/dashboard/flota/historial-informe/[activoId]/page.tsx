'use client'

// [04-09] Informe EMITIBLE del historial de mantenimiento de un equipo.
//
// Manuel: «me han pedido que tengo que hacer el informe del historial de
// mantenimiento». El dato ya existía (v_historial_mantenimiento_equipo,
// MIG310-314: las OT del sistema congeladas al cerrar + las OS anteriores a
// SICOM); esto es el papel: membrete, equipo, tabla cronológica de cada
// intervención con su trabajo realizado y lecturas, listo para imprimir o
// guardar como PDF y entregarlo al cliente o al mandante.

import { useQuery } from '@tanstack/react-query'
import { useParams } from 'next/navigation'
import { Printer, ArrowLeft } from 'lucide-react'
import Link from 'next/link'
import { Spinner } from '@/components/ui/spinner'
import { supabase } from '@/lib/supabase'
import { getHistorialMantenimientoEquipo, type IntervencionHistorial } from '@/lib/services/activos'

type ActivoInforme = {
  nombre: string | null
  patente: string | null
  codigo: string | null
  numero_serie: string | null
  anio: number | null
  modelo: { nombre: string | null; marca: { nombre: string | null } | null } | null
}

const fmtFecha = (s: string | null) =>
  s ? new Date(s).toLocaleDateString('es-CL', { day: '2-digit', month: '2-digit', year: 'numeric' }) : '—'

const num = (n: number | null) => (n == null ? '—' : Math.round(n).toLocaleString('es-CL'))

const TIPO_TXT: Record<string, string> = {
  preventivo: 'Preventiva',
  correctivo: 'Correctiva',
  inspeccion: 'Inspección',
  servicio: 'Servicio',
  emergencia: 'Emergencia',
}

export default function InformeHistorialPage() {
  const params = useParams()
  const activoId = params?.activoId as string

  const { data: activo } = useQuery({
    queryKey: ['activo-informe-historial', activoId],
    queryFn: async (): Promise<ActivoInforme | null> => {
      const { data, error } = await supabase.from('activos')
        .select('nombre, patente, codigo, numero_serie, anio, modelo:modelos(nombre, marca:marcas(nombre))')
        .eq('id', activoId).maybeSingle()
      if (error) throw error
      return (data as unknown as ActivoInforme | null) ?? null
    },
    enabled: !!activoId,
  })

  const { data: historial, isLoading } = useQuery({
    queryKey: ['historial-informe', activoId],
    queryFn: async () => {
      const { data, error } = await getHistorialMantenimientoEquipo(activoId, 300)
      if (error) throw error
      return data
    },
    enabled: !!activoId,
  })

  // El informe cuenta lo HECHO: OT terminadas/cerradas + todo el registro
  // histórico. Una OT abierta no es historial todavía.
  const filas: IntervencionHistorial[] = (historial ?? []).filter((i) =>
    i.origen === 'os_legacy'
    || ['cerrada', 'ejecutada_ok', 'ejecutada_con_observaciones'].includes(i.estado))

  if (isLoading) return <div className="flex justify-center py-16"><Spinner /></div>

  const equipoTxt = [activo?.patente ?? activo?.codigo, activo?.nombre].filter(Boolean).join(' · ')
  const hoy = new Date().toLocaleDateString('es-CL', { day: '2-digit', month: 'long', year: 'numeric' })
  const desde = filas.length ? filas[filas.length - 1].fecha : null

  return (
    <div className="mx-auto max-w-4xl bg-white p-6 print:p-0">
      <style jsx global>{`
        @media print {
          nav, aside, header, .no-print { display: none !important; }
          body { background: white !important; }
          .informe-doc { box-shadow: none !important; border: none !important; }
          tr { break-inside: avoid; }
        }
      `}</style>

      {/* Barra (no se imprime) */}
      <div className="no-print mb-4 flex items-center justify-between">
        <Link href={`/dashboard/activos/${activoId}`}
              className="inline-flex items-center gap-1 text-sm text-gray-500 hover:text-gray-800">
          <ArrowLeft className="h-4 w-4" /> Volver a la ficha
        </Link>
        <button onClick={() => window.print()}
                className="flex items-center gap-1.5 rounded-lg bg-[#1e5929] px-4 py-2 text-sm font-semibold text-white">
          <Printer className="h-4 w-4" /> Imprimir / guardar PDF
        </button>
      </div>

      <div className="informe-doc rounded-lg border border-gray-200 p-8 print:rounded-none">
        {/* Membrete */}
        <div className="flex items-end justify-between border-b-2 border-[#1e5929] pb-4">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/images/logo.jpg" alt="Pillado Empresas" className="h-14 object-contain" />
          <div className="text-right">
            <p className="text-lg font-bold text-gray-900">Informe de historial de mantenimiento</p>
            <p className="text-xs text-gray-500">Emitido el {hoy} · SICOM — Pillado y Cía. Ltda.</p>
          </div>
        </div>

        {/* Equipo */}
        <div className="mt-5 grid grid-cols-2 gap-x-8 gap-y-1 text-sm sm:grid-cols-4">
          <div><p className="text-[10px] font-semibold uppercase text-gray-400">Equipo</p>
            <p className="font-bold">{equipoTxt || '—'}</p></div>
          <div><p className="text-[10px] font-semibold uppercase text-gray-400">Marca / modelo</p>
            <p>{[activo?.modelo?.marca?.nombre, activo?.modelo?.nombre].filter(Boolean).join(' ') || '—'}</p></div>
          <div><p className="text-[10px] font-semibold uppercase text-gray-400">N° serie / año</p>
            <p>{[activo?.numero_serie, activo?.anio].filter(Boolean).join(' · ') || '—'}</p></div>
          <div><p className="text-[10px] font-semibold uppercase text-gray-400">Intervenciones</p>
            <p><b>{filas.length}</b>{desde ? ` desde ${fmtFecha(desde)}` : ''}</p></div>
        </div>

        {/* Tabla cronológica */}
        {filas.length === 0 ? (
          <p className="mt-8 text-center text-sm text-gray-400">Este equipo no tiene intervenciones cerradas registradas.</p>
        ) : (
          <table className="mt-6 w-full border-collapse text-[12px]">
            <thead>
              <tr className="border-b-2 border-gray-300 text-left text-[10px] uppercase tracking-wide text-gray-500">
                <th className="py-1.5 pr-2">Fecha</th>
                <th className="py-1.5 pr-2">Folio</th>
                <th className="py-1.5 pr-2">Tipo</th>
                <th className="py-1.5 pr-2">Trabajo realizado</th>
                <th className="py-1.5 pr-2 text-right">Km</th>
                <th className="py-1.5 pr-2 text-right">Horas</th>
                <th className="py-1.5">Responsable</th>
              </tr>
            </thead>
            <tbody>
              {filas.map((i, idx) => (
                <tr key={i.ref_id} className={`border-b border-gray-100 align-top ${idx % 2 ? 'bg-gray-50' : ''}`}>
                  <td className="py-2 pr-2 whitespace-nowrap">{fmtFecha(i.fecha)}</td>
                  <td className="py-2 pr-2 whitespace-nowrap font-mono text-[11px]">{i.folio}</td>
                  <td className="py-2 pr-2 whitespace-nowrap">{TIPO_TXT[i.tipo] ?? i.tipo}</td>
                  <td className="py-2 pr-2">
                    {i.trabajo_realizado || i.motivo || '—'}
                    {i.origen === 'os_legacy' && (
                      <span className="ml-1 text-[10px] italic text-gray-400">(registro anterior a SICOM)</span>
                    )}
                  </td>
                  <td className="py-2 pr-2 text-right tabular-nums">{num(i.km_al_cierre)}</td>
                  <td className="py-2 pr-2 text-right tabular-nums">{num(i.horas_al_cierre)}</td>
                  <td className="py-2">{i.responsable ?? '—'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}

        {/* Pie */}
        <p className="mt-8 border-t border-gray-200 pt-3 text-[10px] leading-relaxed text-gray-400">
          Este informe refleja las intervenciones de mantenimiento registradas en SICOM para el equipo
          individualizado, incluyendo el registro histórico anterior al sistema. El detalle de tareas,
          repuestos y evidencia fotográfica de cada orden está disponible en la plataforma.
          Documento generado automáticamente — Pillado y Cía. Ltda.
        </p>
      </div>
    </div>
  )
}
