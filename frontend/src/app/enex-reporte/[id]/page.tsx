'use client'

// ENEX Fase 3: documento imprimible de una ejecución de pauta en terreno.
// Si la pauta es de calibración → "CERTIFICADO DE CALIBRACIÓN" (mediciones
// de aforo con tolerancias); si es mantención → "REPORTE DE SERVICIO DE
// MANTENCIÓN". Firmado por el técnico Pillado y el mandante (ENEX/ESM).

import { useEffect, useMemo, useState } from 'react'
import { useParams } from 'next/navigation'
import { Printer } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { getEjecucionReporte, MESES, type EnexReporte, type EnexReporteItem } from '@/lib/services/enex'

const RESULTADO_LABEL: Record<string, { txt: string; cls: string }> = {
  ok: { txt: 'OK', cls: 'bg-green-100 text-green-700' },
  no_ok: { txt: 'NO OK', cls: 'bg-red-100 text-red-700' },
  na: { txt: 'N/A', cls: 'bg-gray-100 text-gray-500' },
  si: { txt: 'SÍ', cls: 'bg-green-100 text-green-700' },
  no: { txt: 'NO', cls: 'bg-red-100 text-red-700' },
}

function fechaCL(iso: string | null): string {
  if (!iso) return '—'
  const [y, m, d] = iso.slice(0, 10).split('-')
  return `${d}-${m}-${y}`
}

export default function EnexReportePage() {
  const params = useParams()
  const ejecId = params?.id as string
  const [sesionOk, setSesionOk] = useState<boolean | null>(null)
  const [reporte, setReporte] = useState<EnexReporte | null>(null)
  const [items, setItems] = useState<EnexReporteItem[]>([])
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let cancel = false
    supabase.auth.getSession().then(({ data: { session } }) => {
      if (!cancel) setSesionOk(!!session)
    })
    return () => { cancel = true }
  }, [])

  useEffect(() => {
    if (sesionOk !== true || !ejecId) return
    let cancel = false
    ;(async () => {
      try {
        const r = await getEjecucionReporte(ejecId)
        if (cancel) return
        if (!r.reporte) { setError('Ejecución no encontrada'); return }
        setReporte(r.reporte); setItems(r.items)
      } catch (e) { if (!cancel) setError((e as Error).message) }
    })()
    return () => { cancel = true }
  }, [sesionOk, ejecId])

  const bloques = useMemo(() => {
    const g: { bloque: string; items: EnexReporteItem[] }[] = []
    for (const it of items) {
      const b = it.item?.bloque ?? 'General'
      let x = g.find((y) => y.bloque === b)
      if (!x) { x = { bloque: b, items: [] }; g.push(x) }
      x.items.push(it)
    }
    return g
  }, [items])

  if (sesionOk === null) return <div className="py-20 text-center text-gray-400">Verificando acceso…</div>
  if (sesionOk === false) {
    return (
      <div className="py-20 text-center">
        <p className="text-sm text-gray-600">El documento requiere iniciar sesión.</p>
        <a href={`/login?next=${encodeURIComponent(`/enex-reporte/${ejecId}`)}`}
           className="mt-4 inline-block rounded-lg bg-[#0b2a4a] px-5 py-2 text-sm font-semibold text-white">
          Iniciar sesión
        </a>
      </div>
    )
  }
  if (error) return <div className="py-20 text-center text-sm text-red-600">{error}</div>
  if (!reporte) return <div className="py-20 text-center text-gray-400">Cargando documento…</div>

  const esCalibracion = (reporte.pauta?.tipo_servicio ?? reporte.programacion?.tipo_servicio) === 'calibracion'
  const titulo = esCalibracion ? 'CERTIFICADO DE CALIBRACIÓN' : 'REPORTE DE SERVICIO DE MANTENCIÓN'
  const inst = reporte.programacion?.instalacion
  const periodo = reporte.programacion
    ? `${MESES[(reporte.programacion.periodo_mes ?? 1) - 1]} ${reporte.programacion.periodo_anio}` : '—'
  const noOk = items.filter((i) => i.resultado === 'no_ok' || i.resultado === 'no' || i.dentro_tolerancia === false).length

  return (
    <div className="mx-auto max-w-3xl bg-white p-6 print:max-w-full print:p-0">
      <style jsx global>{`
        @media print {
          @page { size: letter portrait; margin: 10mm 12mm; }
          html, body { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
          .rep-doc { font-size: 11px; }
          .rep-doc tr, .rep-item { break-inside: avoid; }
          .rep-firmas { break-inside: avoid; }
        }
      `}</style>

      {/* Barra de acciones (no se imprime) */}
      <div className="mb-4 flex items-center justify-between rounded-lg border border-gray-200 bg-gray-50 px-4 py-3 print:hidden">
        <p className="text-sm text-gray-600">
          {titulo.charAt(0) + titulo.slice(1).toLowerCase()} · {inst?.nombre ?? '—'} — «Guardar como PDF» para enviarlo a ENEX.
        </p>
        <button onClick={() => window.print()}
                className="flex items-center gap-1.5 rounded-lg bg-[#0b2a4a] px-4 py-2 text-sm font-semibold text-white">
          <Printer className="h-4 w-4" /> Imprimir
        </button>
      </div>

      <div className="rep-doc text-gray-900">
        {/* Membrete */}
        <div className="flex items-end justify-between border-b-2 border-gray-800 pb-3">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/images/logo.jpg" alt="Pillado Empresas" className="h-14 object-contain print:h-12" />
          <div className="text-right">
            <h1 className="text-lg font-black tracking-tight text-[#0b2a4a] print:text-base">{titulo}</h1>
            <p className="text-xs text-gray-600">Contrato ENEX / ESM — {periodo}</p>
            {reporte.ot_numero && <p className="font-mono text-sm font-bold">OT {reporte.ot_numero}</p>}
          </div>
        </div>

        {/* Datos generales */}
        <div className="mt-4 grid grid-cols-2 gap-x-8 gap-y-1.5 text-sm sm:grid-cols-3">
          <div><span className="text-gray-500">Faena:</span> <b>{inst?.faena?.nombre ?? '—'}</b></div>
          <div><span className="text-gray-500">Instalación:</span> <b>{inst?.nombre ?? '—'}</b></div>
          <div><span className="text-gray-500">Tipo:</span> <b>{inst?.tipo ?? '—'}{inst?.linea ? ` · ${inst.linea}` : ''}</b></div>
          {inst?.patente && <div><span className="text-gray-500">Patente:</span> <b>{inst.patente}</b></div>}
          <div><span className="text-gray-500">Pauta:</span> <b>{reporte.pauta?.codigo ?? '—'} v{reporte.pauta?.version ?? 1}</b></div>
          <div><span className="text-gray-500">Fecha de ejecución:</span> <b>{fechaCL(reporte.fecha_ejecucion)}</b></div>
          <div><span className="text-gray-500">Técnico:</span> <b>{reporte.tecnico_nombre ?? reporte.ejecutor ?? '—'}</b></div>
          <div>
            <span className="text-gray-500">Resultado:</span>{' '}
            <b className={noOk > 0 ? 'text-red-700' : 'text-green-700'}>
              {noOk > 0 ? `${noOk} observación(es)` : 'Conforme'}
            </b>
          </div>
        </div>

        {/* Ítems por bloque */}
        {bloques.map((b) => (
          <div key={b.bloque}>
            <h2 className="mt-5 border-b border-gray-300 pb-1 text-sm font-bold uppercase tracking-wide">{b.bloque}</h2>
            <table className="mt-1 w-full text-[12px]">
              <tbody>
                {b.items.map((it) => {
                  const esMedicion = it.item?.tipo_campo === 'medicion' || it.valor_medicion != null
                  const res = it.resultado ? RESULTADO_LABEL[it.resultado] : null
                  return (
                    <tr key={it.id} className="rep-item border-b border-gray-100 align-top">
                      <td className="w-14 py-1.5 pr-2 font-mono text-[10px] text-gray-400">{it.item?.codigo}</td>
                      <td className="py-1.5 pr-3">
                        {it.item?.descripcion}
                        {it.observacion && <div className="text-[11px] italic text-gray-500">{it.observacion}</div>}
                      </td>
                      <td className="w-40 py-1.5 text-right">
                        {esMedicion ? (
                          <span>
                            <b>{it.valor_medicion ?? '—'} {it.item?.unidad ?? ''}</b>
                            {(it.item?.tolerancia_min != null || it.item?.tolerancia_max != null) && (
                              <span className="text-[10px] text-gray-500"> (tol. {it.item?.tolerancia_min ?? '—'}–{it.item?.tolerancia_max ?? '—'})</span>
                            )}
                            {it.dentro_tolerancia != null && (
                              <span className={`ml-1 rounded px-1.5 py-0.5 text-[10px] font-bold ${
                                it.dentro_tolerancia ? 'bg-green-100 text-green-700' : 'bg-red-100 text-red-700'}`}>
                                {it.dentro_tolerancia ? 'DENTRO' : 'FUERA'}
                              </span>
                            )}
                          </span>
                        ) : res ? (
                          <span className={`rounded px-2 py-0.5 text-[10px] font-bold ${res.cls}`}>{res.txt}</span>
                        ) : <span className="text-gray-400">—</span>}
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
            {/* Fotos del bloque */}
            {b.items.some((i) => i.foto_url) && (
              <div className="mt-2 flex flex-wrap gap-2">
                {b.items.filter((i) => i.foto_url).map((i) => (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img key={i.id} src={i.foto_url!} alt={i.item?.descripcion ?? 'foto'}
                       className="h-24 w-24 rounded border object-cover print:h-20 print:w-20" />
                ))}
              </div>
            )}
          </div>
        ))}

        {/* Evidencias generales + observación */}
        {(reporte.evidencia_urls?.length ?? 0) > 0 && (
          <>
            <h2 className="mt-5 border-b border-gray-300 pb-1 text-sm font-bold uppercase tracking-wide">Evidencias</h2>
            <div className="mt-2 flex flex-wrap gap-2">
              {(reporte.evidencia_urls ?? []).map((url, i) => (
                // eslint-disable-next-line @next/next/no-img-element
                <img key={i} src={url} alt={`evidencia ${i + 1}`} className="h-24 w-24 rounded border object-cover print:h-20 print:w-20" />
              ))}
            </div>
          </>
        )}
        {reporte.observacion && (
          <>
            <h2 className="mt-5 border-b border-gray-300 pb-1 text-sm font-bold uppercase tracking-wide">Observaciones</h2>
            <p className="mt-1.5 whitespace-pre-wrap text-[12px] text-gray-700">{reporte.observacion}</p>
          </>
        )}

        {/* Firmas: técnico Pillado + mandante ENEX */}
        <div className="rep-firmas mt-12 grid grid-cols-2 gap-10">
          <div className="text-center">
            {reporte.firma_tecnico_url && (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={reporte.firma_tecnico_url} alt="firma técnico" className="mx-auto h-16 object-contain" />
            )}
            <div className="mx-6 border-t border-gray-800 pt-2 text-sm italic">
              <p>{reporte.tecnico_nombre ?? reporte.ejecutor ?? '—'}</p>
              <p>Técnico ejecutor</p>
              <p>Pillado y Cía. Ltda.</p>
            </div>
          </div>
          <div className="text-center">
            {reporte.firma_mandante_url && (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={reporte.firma_mandante_url} alt="firma mandante" className="mx-auto h-16 object-contain" />
            )}
            <div className="mx-6 border-t border-gray-800 pt-2 text-sm italic">
              <p>{reporte.firmante_mandante_nombre ?? '—'}</p>
              <p>Recepción conforme — Mandante</p>
              <p>ENEX / ESM</p>
            </div>
          </div>
        </div>

        {/* Footer */}
        <div className="mt-10 border-t border-gray-300 pt-2">
          <div className="flex justify-between text-xs italic text-gray-700">
            <span>Fono: 051 – 2232159</span>
            <span>contacto@pilladoempresas.cl</span>
            <span>www.pilladoempresas.cl</span>
          </div>
          <div className="mt-1 flex h-1.5">
            <div className="flex-1 bg-orange-500" />
            <div className="flex-1 bg-gray-400" />
            <div className="flex-1 bg-green-600" />
          </div>
        </div>
      </div>
    </div>
  )
}
