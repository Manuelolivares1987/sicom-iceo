'use client'

// ENEX Fase 3: documento imprimible de una ejecución de pauta en terreno.
// Si la pauta es de calibración → "CERTIFICADO DE CALIBRACIÓN" (mediciones
// de aforo con tolerancias); si es mantención → "REPORTE DE SERVICIO DE
// MANTENCIÓN". Firmado por el técnico Pillado y el mandante (ENEX/ESM).

import { useEffect, useMemo, useState } from 'react'
import { useParams } from 'next/navigation'
import { Printer } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import {
  getEjecucionReporte, MESES,
  type EnexReporte, type EnexReporteItem, type EnexItemSinRegistro,
} from '@/lib/services/enex'

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

function duracionCL(seg: number | null): string {
  if (!seg || seg <= 0) return '—'
  const h = Math.floor(seg / 3600), m = Math.round((seg % 3600) / 60)
  return h > 0 ? `${h} h ${String(m).padStart(2, '0')} min` : `${m} min`
}

const nAntes = (i: EnexReporteItem) => i.fotos_antes?.length ?? 0
const nDespues = (i: EnexReporteItem) => i.fotos_despues?.length ?? 0

/** Los datos del servicio (bloque 0) no son actividades intervenidas. */
const esActividad = (i: EnexReporteItem): boolean => {
  const b = i.item?.bloque ?? ''
  const cod = i.item?.codigo ?? ''
  return !b.startsWith('0.') && !cod.startsWith('DS.') && !cod.startsWith('FOT.')
}

export default function EnexReportePage() {
  const params = useParams()
  const ejecId = params?.id as string
  const [sesionOk, setSesionOk] = useState<boolean | null>(null)
  const [reporte, setReporte] = useState<EnexReporte | null>(null)
  const [items, setItems] = useState<EnexReporteItem[]>([])
  const [sinRegistro, setSinRegistro] = useState<EnexItemSinRegistro[]>([])
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
        setReporte(r.reporte); setItems(r.items); setSinRegistro(r.sinRegistro)
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

  // Evidencia por actividad: la ficha se numera una vez y la tabla la cita.
  const conAntesDespues = useMemo(
    () => items.filter((i) => esActividad(i) && (nAntes(i) > 0 || nDespues(i) > 0)), [items])
  const fichaDe = useMemo(
    () => new Map(conAntesDespues.map((i, k) => [i.id, k + 1])), [conAntesDespues])

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
  const actividades = items.filter(esActividad)
  const noOkItems = actividades.filter(
    (i) => i.resultado === 'no_ok' || i.resultado === 'no' || i.dentro_tolerancia === false)
  const noOk = noOkItems.length
  const cta = {
    ejecutadas: actividades.length,
    total: actividades.length + sinRegistro.length,
    ok: actividades.filter((i) => i.resultado === 'ok' || i.resultado === 'si').length,
    na: actividades.filter((i) => i.resultado === 'na').length,
    antes: actividades.reduce((s, i) => s + nAntes(i), 0),
    despues: actividades.reduce((s, i) => s + nDespues(i), 0),
  }

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
          <div><span className="text-gray-500">Duración en terreno:</span> <b>{duracionCL(reporte.duracion_segundos)}</b></div>
          <div>
            <span className="text-gray-500">Resultado:</span>{' '}
            <b className={noOk > 0 ? 'text-red-700' : 'text-green-700'}>
              {noOk > 0 ? `${noOk} observación(es)` : 'Conforme'}
            </b>
          </div>
        </div>

        {/* Resumen: cuánto se intervino y con cuánta evidencia se respalda */}
        <div className="mt-4 grid grid-cols-3 gap-2 sm:grid-cols-6">
          {[
            { n: `${cta.ejecutadas}/${cta.total}`, l: 'Actividades intervenidas', c: 'text-gray-900' },
            { n: cta.ok, l: 'Conformes', c: 'text-green-700' },
            { n: noOk, l: 'No conformes', c: noOk > 0 ? 'text-red-700' : 'text-gray-900' },
            { n: cta.na, l: 'No aplica', c: 'text-gray-500' },
            { n: cta.antes, l: 'Fotos ANTES', c: 'text-amber-700' },
            { n: cta.despues, l: 'Fotos DESPUÉS', c: 'text-green-700' },
          ].map((k, i) => (
            <div key={i} className="rounded border border-gray-300 bg-gray-50 px-2 py-1.5 text-center">
              <div className={`text-base font-bold ${k.c}`}>{k.n}</div>
              <div className="text-[9px] leading-tight text-gray-500">{k.l}</div>
            </div>
          ))}
        </div>

        {/* Hallazgos no conformes arriba: es lo que dispara la siguiente OT */}
        {noOk > 0 && (
          <div className="mt-4 rounded border border-red-200 bg-red-50 p-3">
            <h2 className="text-xs font-bold uppercase tracking-wide text-red-800">
              Hallazgos no conformes ({noOk})
            </h2>
            <ul className="mt-1 space-y-0.5 text-[12px] text-red-900">
              {noOkItems.map((i) => (
                <li key={i.id}>
                  <b>{i.item?.codigo ? `${i.item.codigo} · ` : ''}{i.item?.descripcion}</b>
                  {' — '}{i.observacion ?? 'sin detalle registrado en terreno'}
                  {fichaDe.get(i.id) && <span className="text-red-600"> (ficha {fichaDe.get(i.id)})</span>}
                </li>
              ))}
            </ul>
          </div>
        )}

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
                      <td className="w-20 py-1.5 text-right text-[10px] leading-tight">
                        {nAntes(it) + nDespues(it) > 0 ? (
                          <span className={nAntes(it) > 0 && nDespues(it) > 0 ? 'text-green-700' : 'text-amber-700'}>
                            A:{nAntes(it)} / D:{nDespues(it)}
                            {fichaDe.get(it.id) && <><br />ficha {fichaDe.get(it.id)}</>}
                          </span>
                        ) : esActividad(it) ? <span className="text-gray-300">sin fotos</span> : null}
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

        {/* Actividades de la pauta que no quedaron registradas en la visita */}
        {sinRegistro.length > 0 && (
          <>
            <h2 className="mt-5 border-b border-gray-300 pb-1 text-sm font-bold uppercase tracking-wide">
              Actividades de la pauta sin registro en esta visita ({sinRegistro.length})
            </h2>
            <table className="mt-1 w-full text-[11px]">
              <tbody>
                {sinRegistro.map((i) => (
                  <tr key={i.id} className="rep-item border-b border-gray-100 align-top">
                    <td className="w-14 py-1 pr-2 font-mono text-[10px] text-gray-400">{i.codigo}</td>
                    <td className="py-1 pr-3 text-gray-600">{i.descripcion}</td>
                    <td className="w-24 py-1 text-right text-[10px] text-gray-400">{i.periodicidad ?? '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
            <p className="mt-1 text-[10px] italic text-gray-500">
              Pueden corresponder a otra periodicidad del plan o no aplicar a esta instalación. Se listan
              para trazabilidad del contrato.
            </p>
          </>
        )}

        {/* Anexo: antes y después de cada actividad intervenida */}
        {conAntesDespues.length > 0 && (
          <>
            <h2 className="mt-6 border-b-2 border-gray-800 pb-1 text-sm font-bold uppercase tracking-wide">
              Anexo fotográfico — antes y después por actividad
            </h2>
            <p className="mt-1 text-[11px] text-gray-500">
              {conAntesDespues.length} actividad{conAntesDespues.length !== 1 ? 'es' : ''} con evidencia ·
              {' '}{cta.antes} foto(s) del antes y {cta.despues} del después, en el orden en que las capturó
              el técnico en terreno.
            </p>
            {conAntesDespues.map((it, k) => {
              const malo = it.resultado === 'no_ok' || it.resultado === 'no' || it.dentro_tolerancia === false
              return (
                <div key={`ad-${it.id}`} className="rep-item mt-3 border border-gray-400">
                  <div className="flex items-center gap-2 bg-gray-800 px-2 py-1 text-white">
                    <span className="text-[11px] font-bold">N° {k + 1}</span>
                    <span className="flex-1 text-[11px] font-bold">
                      {it.item?.codigo ? `${it.item.codigo} · ` : ''}{it.item?.descripcion}
                    </span>
                    <span className={`text-[10px] font-bold ${malo ? 'text-red-300' : 'text-green-300'}`}>
                      {it.item?.tipo_campo === 'medicion' && it.valor_medicion != null
                        ? `${it.valor_medicion} ${it.item?.unidad ?? ''}`
                        : (RESULTADO_LABEL[it.resultado ?? '']?.txt ?? 'SIN ESTADO')}
                    </span>
                  </div>
                  <div className="grid grid-cols-2">
                    {([['ANTES', it.fotos_antes ?? [], 'A'], ['DESPUÉS', it.fotos_despues ?? [], 'D']] as const).map(
                      ([tag, fotos, pre]) => (
                        <div key={tag} className={pre === 'A' ? 'border-r border-gray-400 p-2' : 'p-2'}>
                          <div className={`mb-1.5 rounded px-2 py-0.5 text-center text-[10px] font-bold ${
                            pre === 'A' ? 'bg-amber-100 text-amber-800' : 'bg-green-100 text-green-800'}`}>
                            {tag}{fotos.length > 0 ? ` — ${fotos.length} foto${fotos.length !== 1 ? 's' : ''}` : ''}
                          </div>
                          {fotos.length === 0 ? (
                            <p className="py-4 text-center text-[10px] italic text-gray-400">Sin registro fotográfico</p>
                          ) : (
                            <div className="flex flex-wrap gap-1">
                              {fotos.map((u, j) => (
                                <figure key={j} className="w-[72px]">
                                  {/* eslint-disable-next-line @next/next/no-img-element */}
                                  <img src={u} alt={`${tag} ${j + 1}`}
                                       className="h-14 w-[72px] rounded-sm border border-gray-300 object-cover" />
                                  <figcaption className="text-center text-[8px] text-gray-400">{pre}{j + 1}</figcaption>
                                </figure>
                              ))}
                            </div>
                          )}
                        </div>
                      ))}
                  </div>
                  {it.observacion && (
                    <p className="border-t border-gray-300 bg-gray-50 px-2 py-1 text-[10px] text-gray-600">
                      Observación del técnico: {it.observacion}
                    </p>
                  )}
                </div>
              )
            })}
          </>
        )}

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
