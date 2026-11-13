'use client'

// ============================================================================
// Portal del mandante — gestión de prevención del mes (MIG688)
// ----------------------------------------------------------------------------
// Inspecciones de terreno APR (con su PDF), desviaciones abiertas, actividades
// del mes con fotos e indicadores. Mismo lenguaje visual que el resto del
// portal (MIG308).
// ============================================================================

import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { AlertTriangle, Camera, ChevronDown, ChevronRight, FileDown, Loader2 } from 'lucide-react'
import { Spinner } from '@/components/ui/spinner'
import { cn } from '@/lib/utils'
import { descargarPdfDesdeDetalle } from '@/components/prevencion/pdf-inspeccion-apr'
import {
  getInspeccionPortal, getPrevencionPortal, urlsFotosPortal,
  type ActividadPortal,
} from './portal-mandante-api'

const RES: Record<string, { t: string, c: string }> = {
  conforme: { t: 'Conforme', c: 'bg-emerald-100 text-emerald-800' },
  con_desviaciones: { t: 'Con desviaciones', c: 'bg-amber-100 text-amber-800' },
  critico: { t: 'Crítico', c: 'bg-red-600 text-white' },
}
const EST: Record<string, string> = { en_curso: 'En curso', pendiente_cierre_art: 'Falta cierre ART', cerrada: 'Cerrada' }
const fmt = (s: string | null) => s ? new Date(s + 'T12:00:00').toLocaleDateString('es-CL', { day: '2-digit', month: 'short' }) : '—'
const num = (n: number | null | undefined, d = 0) => n == null ? '—' : Number(n).toLocaleString('es-CL', { maximumFractionDigits: d })

function Titulo({ children, bajada }: { children: React.ReactNode, bajada?: string }) {
  return (
    <div className="border-b border-slate-200 pb-2">
      <h3 className="text-sm font-bold uppercase tracking-wide text-slate-800">{children}</h3>
      {bajada && <p className="mt-0.5 text-xs text-slate-500">{bajada}</p>}
    </div>
  )
}

function Galeria({ token, acceso, fotos }: { token: string, acceso: string, fotos: string[] }) {
  const [abierta, setAbierta] = useState(false)
  const { data, isLoading, error } = useQuery({
    queryKey: ['portal-fotos', fotos.join('|')],
    queryFn: () => urlsFotosPortal(token, acceso, fotos),
    enabled: abierta && fotos.length > 0,
    staleTime: 8 * 60_000,
  })
  if (!fotos.length) return null
  return (
    <div>
      <button onClick={() => setAbierta((v) => !v)}
              className="inline-flex items-center gap-1 text-[11px] font-semibold text-slate-600 hover:text-slate-900">
        <Camera className="h-3.5 w-3.5" /> {abierta ? 'Ocultar' : 'Ver'} {fotos.length} foto{fotos.length === 1 ? '' : 's'}
      </button>
      {abierta && (
        <div className="mt-2 flex flex-wrap gap-2">
          {isLoading && <Spinner className="h-4 w-4" />}
          {error && <p className="text-[11px] text-red-600">{(error as Error).message}</p>}
          {fotos.map((p) => data?.[p] && (
            <a key={p} href={data[p]} target="_blank" rel="noopener noreferrer">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={data[p]} alt="Evidencia" className="h-24 w-32 rounded-lg border border-slate-200 object-cover" />
            </a>
          ))}
        </div>
      )}
    </div>
  )
}

function FilaActividad({ a, token, acceso }: { a: ActividadPortal, token: string, acceso: string }) {
  return (
    <li className="space-y-1 px-4 py-3">
      <div className="flex flex-wrap items-center gap-2">
        <span className="rounded bg-slate-100 px-1.5 py-0.5 text-[10px] font-bold text-slate-700">{a.tipo}</span>
        <span className="min-w-0 flex-1 text-sm font-medium text-slate-900">{a.titulo}</span>
        <span className="text-[11px] text-slate-500">{fmt(a.fecha)}</span>
        <span className={cn('rounded-full px-2 py-0.5 text-[10px] font-bold',
          a.estado === 'abierto' ? 'bg-amber-100 text-amber-800' : 'bg-emerald-100 text-emerald-800')}>
          {a.estado}
        </span>
      </div>
      <p className="text-[11px] text-slate-500">
        {a.faena}{a.area_sector ? ` · ${a.area_sector}` : ''}{a.responsable ? ` · ${a.responsable}` : ''}
        {a.asistentes ? ` · ${a.asistentes} asistentes` : ''}{a.duracion_minutos ? ` · ${a.duracion_minutos} min` : ''}
      </p>
      {a.descripcion && <p className="text-xs text-slate-600">{a.descripcion}</p>}
      <Galeria token={token} acceso={acceso} fotos={a.fotos} />
    </li>
  )
}

export function PrevencionGestion({ token, acceso, anio, mes }: {
  token: string, acceso: string, anio: number, mes: number
}) {
  const [pdfId, setPdfId] = useState<string | null>(null)
  const [errPdf, setErrPdf] = useState<string | null>(null)
  const [verTodas, setVerTodas] = useState(false)
  const { data, isLoading, error } = useQuery({
    queryKey: ['portal-prev-gestion', token, acceso, anio, mes],
    queryFn: () => getPrevencionPortal(token, acceso, anio, mes),
    staleTime: 60_000,
    retry: false,
  })

  const pdf = async (id: string, faena: string) => {
    setPdfId(id); setErrPdf(null)
    try {
      const d = await getInspeccionPortal(token, acceso, id)
      await descargarPdfDesdeDetalle(d, faena, (paths) => urlsFotosPortal(token, acceso, paths).catch(() => ({})))
    } catch (e: any) {
      setErrPdf(e?.message ?? 'No se pudo generar el informe')
    } finally { setPdfId(null) }
  }

  if (isLoading) return <div className="flex justify-center py-10"><Spinner /></div>
  if (error || !data) return <p className="text-sm text-red-600">{(error as Error)?.message ?? 'Sin datos'}</p>

  const actividades = verTodas ? data.actividades : data.actividades.slice(0, 15)

  return (
    <div className="space-y-8">
      {/* Indicadores */}
      <section className="space-y-3">
        <Titulo bajada="Dotación y horas-hombre reportadas; índices de frecuencia y gravedad del mes y acumulados del año.">
          Indicadores del mes
        </Titulo>
        {!data.indicadores.length ? (
          <p className="rounded-xl border border-dashed border-slate-300 bg-white py-5 text-center text-xs text-slate-400">
            Indicadores del mes aún no consolidados.
          </p>
        ) : data.indicadores.map((i) => (
          <div key={i.faena} className="grid grid-cols-3 gap-2 sm:grid-cols-6">
            {[
              ['Faena', i.faena], ['Dotación', num(i.dotacion)], ['HH', num(i.hh)],
              ['Accidentes CTP', num(i.accidentes_ctp)], ['IF mes / acum.', `${num(i.if, 1)} / ${num(i.acum_if, 1)}`],
              ['IG mes / acum.', `${num(i.ig, 1)} / ${num(i.acum_ig, 1)}`],
            ].map(([k, v]) => (
              <div key={k} className="rounded-lg border border-slate-200 bg-white px-3 py-2">
                <p className="text-[10px] font-semibold uppercase text-slate-400">{k}</p>
                <p className="text-sm font-bold text-slate-800">{v}</p>
              </div>
            ))}
          </div>
        ))}
      </section>

      {/* Inspecciones */}
      <section className="space-y-3">
        <Titulo bajada="Verificación en terreno de traslado, ingreso, documentos, ejecución y término del trabajo. Cada inspección tiene su informe con fotos.">
          Inspecciones de terreno ({data.inspecciones.length})
        </Titulo>
        {errPdf && <p className="text-xs text-red-600">{errPdf}</p>}
        {!data.inspecciones.length ? (
          <p className="rounded-xl border border-dashed border-slate-300 bg-white py-5 text-center text-xs text-slate-400">Sin inspecciones en el mes.</p>
        ) : (
          <div className="overflow-hidden rounded-xl border border-slate-200 bg-white">
            {data.inspecciones.map((i) => (
              <div key={i.id} className="flex flex-wrap items-center gap-2 border-b border-slate-100 px-4 py-3 last:border-0">
                <div className="min-w-0 flex-1">
                  <p className="text-sm font-medium text-slate-900">{i.trabajo}</p>
                  <p className="text-[11px] text-slate-500">
                    {fmt(i.fecha)} · {i.faena}{i.instalacion ? ` · ${i.instalacion}` : ''} · {EST[i.estado]}
                    {i.inspector ? ` · ${i.inspector}` : ''}
                  </p>
                  {(i.personas_no_habilitadas > 0 || i.desviaciones_abiertas > 0) && (
                    <p className="text-[11px] text-red-700">
                      {i.personas_no_habilitadas > 0 && `${i.personas_no_habilitadas} trabajador(es) no habilitado(s). `}
                      {i.desviaciones_abiertas > 0 && `${i.desviaciones_abiertas} de ${i.desviaciones} desviación(es) abierta(s).`}
                    </p>
                  )}
                </div>
                <span className="text-sm font-bold text-slate-800">{i.pct_cumplimiento == null ? '—' : `${i.pct_cumplimiento}%`}</span>
                <span className={cn('rounded-full px-2 py-0.5 text-[10px] font-bold', RES[i.resultado].c)}>{RES[i.resultado].t}</span>
                <button onClick={() => pdf(i.id, i.faena)} disabled={pdfId === i.id}
                        className="inline-flex items-center gap-1 rounded-lg border border-slate-300 px-2.5 py-1 text-[11px] font-semibold text-slate-700 hover:bg-slate-50">
                  {pdfId === i.id ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <FileDown className="h-3.5 w-3.5" />} Informe
                </button>
              </div>
            ))}
          </div>
        )}
      </section>

      {/* Desviaciones abiertas */}
      <section className="space-y-3">
        <Titulo bajada="Hallazgos de las inspecciones que siguen pendientes, de cualquier mes, con responsable y plazo.">
          Desviaciones abiertas ({data.desviaciones_abiertas.length})
        </Titulo>
        {!data.desviaciones_abiertas.length ? (
          <p className="rounded-xl border border-emerald-200 bg-emerald-50 py-4 text-center text-xs font-medium text-emerald-800">
            No hay desviaciones abiertas.
          </p>
        ) : (
          <ul className="overflow-hidden rounded-xl border border-slate-200 bg-white">
            {data.desviaciones_abiertas.map((d) => (
              <li key={d.id} className="flex flex-wrap items-start gap-2 border-b border-slate-100 px-4 py-3 last:border-0">
                <span className={cn('rounded px-1.5 py-0.5 text-[10px] font-bold uppercase text-white',
                  d.criticidad === 'alta' ? 'bg-red-600' : d.criticidad === 'media' ? 'bg-amber-500' : 'bg-slate-400')}>
                  {d.criticidad}
                </span>
                <div className="min-w-0 flex-1">
                  <p className="text-sm text-slate-900">{d.descripcion}</p>
                  {d.accion && <p className="text-[11px] text-slate-600">Acción: {d.accion}</p>}
                  <p className="text-[11px] text-slate-400">{fmt(d.fecha)} · {d.faena} · {d.trabajo}</p>
                </div>
                <div className="text-right text-[11px]">
                  <p className="text-slate-700">{d.responsable ?? 'Sin responsable'}</p>
                  <p className={cn(d.vencida ? 'font-bold text-red-700' : 'text-slate-500')}>
                    {d.vencida && <AlertTriangle className="mr-0.5 inline h-3 w-3" />}Plazo {fmt(d.fecha_compromiso)}
                  </p>
                </div>
              </li>
            ))}
          </ul>
        )}
      </section>

      {/* Actividades */}
      <section className="space-y-3">
        <Titulo bajada="Charlas, capacitaciones, ART, inspecciones y demás herramientas preventivas registradas en el mes, con su evidencia.">
          Actividades del mes ({data.actividades.length})
        </Titulo>
        {data.resumen_actividades.length > 0 && (
          <div className="flex flex-wrap gap-1.5">
            {data.resumen_actividades.map((r) => (
              <span key={r.tipo} className="rounded-full bg-white px-2.5 py-1 text-[11px] text-slate-700 ring-1 ring-slate-200">
                {r.tipo}: <b>{r.realizados}</b>{r.abiertos > 0 && <span className="text-amber-700"> ({r.abiertos} abiertos)</span>}
              </span>
            ))}
          </div>
        )}
        {!data.actividades.length ? (
          <p className="rounded-xl border border-dashed border-slate-300 bg-white py-5 text-center text-xs text-slate-400">Sin actividades registradas en el mes.</p>
        ) : (
          <>
            <ul className="divide-y divide-slate-100 overflow-hidden rounded-xl border border-slate-200 bg-white">
              {actividades.map((a) => <FilaActividad key={a.id} a={a} token={token} acceso={acceso} />)}
            </ul>
            {data.actividades.length > 15 && (
              <button onClick={() => setVerTodas((v) => !v)} className="inline-flex items-center gap-1 text-xs font-semibold text-slate-600">
                {verTodas ? <ChevronDown className="h-3.5 w-3.5" /> : <ChevronRight className="h-3.5 w-3.5" />}
                {verTodas ? 'Ver menos' : `Ver las ${data.actividades.length}`}
              </button>
            )}
          </>
        )}
      </section>
    </div>
  )
}
