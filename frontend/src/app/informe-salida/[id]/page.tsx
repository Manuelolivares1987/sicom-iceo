'use client'

// ============================================================================
// Informe de Salida a Arriendo (MIG263) — imprimible, formato papel Pillado.
// Es el documento que acompaña al equipo cuando sale a arriendo: qué se revisó,
// con qué resultado, con la FOTO de cada punto que la exige y de cada hallazgo,
// más los pendientes diferidos y los documentos con su vencimiento.
// ============================================================================

import { useEffect, useState } from 'react'
import { useParams } from 'next/navigation'
import { Printer, ShieldCheck, AlertTriangle, XCircle, MinusCircle, CheckCircle2 } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { getInformeSalida, type InformeSalida, type InformeSalidaItem } from '@/lib/services/informe-salida'

const MESES = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre']

function fechaLarga(iso?: string | null): string {
  if (!iso) return '—'
  const d = new Date(iso)
  return `${String(d.getDate()).padStart(2, '0')} de ${MESES[d.getMonth()]} de ${d.getFullYear()}`
}
function fechaCorta(iso?: string | null): string {
  if (!iso) return '—'
  const d = new Date(iso)
  return `${String(d.getDate()).padStart(2, '0')}/${String(d.getMonth() + 1).padStart(2, '0')}/${d.getFullYear()}`
}
function tituloBloque(b: string): string {
  return b.replace(/^b\d*_?/, '').replace(/_/g, ' ')
}

const RESULTADO_LABEL: Record<string, string> = {
  aprobado: 'APROBADO — Equipo liberado a arriendo',
  aprobado_con_observaciones: 'APROBADO CON OBSERVACIONES — Equipo liberado a arriendo',
  rechazado: 'RECHAZADO — Equipo NO liberado',
  pendiente: 'EN PROCESO — informe preliminar',
}

function IconoResultado({ r }: { r: InformeSalidaItem['resultado'] }) {
  if (r === 'ok') return <CheckCircle2 className="h-3.5 w-3.5 text-green-600" />
  if (r === 'no_ok') return <XCircle className="h-3.5 w-3.5 text-red-600" />
  if (r === 'na') return <MinusCircle className="h-3.5 w-3.5 text-gray-400" />
  return <span className="text-[10px] text-gray-400">—</span>
}

export default function InformeSalidaPage() {
  const params = useParams()
  const id = params?.id as string
  const [sesionOk, setSesionOk] = useState<boolean | null>(null)
  const [inf, setInf] = useState<InformeSalida | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let cancel = false
    supabase.auth.getSession().then(({ data: { session } }) => {
      if (!cancel) setSesionOk(!!session)
    })
    return () => { cancel = true }
  }, [])

  useEffect(() => {
    if (!id || sesionOk !== true) return
    getInformeSalida(id).then(setInf).catch((e) => setError(e.message))
  }, [id, sesionOk])

  if (sesionOk === false) {
    return <div className="p-10 text-center text-sm text-gray-500">
      Inicia sesión para ver el informe de salida.
    </div>
  }
  if (error) return <div className="p-10 text-center text-sm text-red-600">{error}</div>
  if (!inf) return <div className="p-10 text-center text-sm text-gray-400">Cargando informe…</div>

  const eq = inf.equipo
  const aprobado = inf.resultado === 'aprobado' || inf.resultado === 'aprobado_con_observaciones'
  const totalFotos = inf.bloques.reduce(
    (n, b) => n + b.items.filter((i) => !!i.foto_url).length, 0)

  return (
    <div className="mx-auto max-w-[820px] bg-white p-8 text-[13px] leading-relaxed text-gray-900 print:p-0">
      <style>{`@media print {
        .no-print { display: none !important; }
        .page-break { break-inside: avoid; }
        body { background: white; }
      }`}</style>

      <div className="no-print mb-4 flex justify-end">
        <button onClick={() => window.print()}
                className="flex items-center gap-2 rounded bg-gray-900 px-3 py-1.5 text-xs font-semibold text-white">
          <Printer className="h-4 w-4" /> Imprimir / guardar PDF
        </button>
      </div>

      {/* Membrete */}
      <div className="flex items-start justify-between border-b-2 border-gray-800 pb-3">
        <div>
          <div className="text-lg font-bold tracking-tight">TRANSPORTES Y SERVICIOS PILLADO</div>
          <div className="text-[11px] text-gray-600">Arriendo de flota industrial · SICOM-ICEO</div>
        </div>
        <div className="text-right text-[11px]">
          <div className="font-mono text-sm font-bold">{inf.folio ?? 'SIN FOLIO'}</div>
          <div className="text-gray-600">{fechaLarga(inf.fecha)}</div>
        </div>
      </div>

      <h1 className="mt-5 text-center text-base font-bold uppercase tracking-wide">
        Informe de salida a arriendo
      </h1>
      <div className={`mt-2 rounded border px-3 py-2 text-center text-sm font-semibold ${
        aprobado ? 'border-green-400 bg-green-50 text-green-800'
                 : 'border-red-400 bg-red-50 text-red-800'}`}>
        {RESULTADO_LABEL[inf.resultado] ?? inf.resultado}
      </div>

      {/* Equipo */}
      <table className="mt-5 w-full border-collapse text-[12px]">
        <tbody>
          <tr>
            <td className="w-32 border bg-gray-50 px-2 py-1 font-semibold">Equipo</td>
            <td className="border px-2 py-1">{eq.patente ?? eq.codigo} · {eq.nombre ?? '—'}</td>
            <td className="w-32 border bg-gray-50 px-2 py-1 font-semibold">Código</td>
            <td className="border px-2 py-1">{eq.codigo ?? '—'}</td>
          </tr>
          <tr>
            <td className="border bg-gray-50 px-2 py-1 font-semibold">Marca / Modelo</td>
            <td className="border px-2 py-1">{[eq.marca, eq.modelo].filter(Boolean).join(' ') || '—'}</td>
            <td className="border bg-gray-50 px-2 py-1 font-semibold">Año</td>
            <td className="border px-2 py-1">{eq.anio ?? '—'}</td>
          </tr>
          <tr>
            <td className="border bg-gray-50 px-2 py-1 font-semibold">Kilometraje</td>
            <td className="border px-2 py-1">{eq.kilometraje != null ? `${eq.kilometraje.toLocaleString('es-CL')} km` : '—'}</td>
            <td className="border bg-gray-50 px-2 py-1 font-semibold">Horas de uso</td>
            <td className="border px-2 py-1">{eq.horas_uso != null ? `${eq.horas_uso} h` : '—'}</td>
          </tr>
          <tr>
            <td className="border bg-gray-50 px-2 py-1 font-semibold">Cliente / Contrato</td>
            <td className="border px-2 py-1">{[eq.cliente, eq.contrato].filter(Boolean).join(' · ') || '—'}</td>
            <td className="border bg-gray-50 px-2 py-1 font-semibold">Faena</td>
            <td className="border px-2 py-1">{eq.faena ?? '—'}</td>
          </tr>
          <tr>
            <td className="border bg-gray-50 px-2 py-1 font-semibold">Vigencia</td>
            <td className="border px-2 py-1">
              {inf.vigente_hasta
                ? `Hasta el ${fechaCorta(inf.vigente_hasta)} (${inf.dias_vigencia ?? '—'} días)`
                : '—'}
            </td>
            <td className="border bg-gray-50 px-2 py-1 font-semibold">Auditor</td>
            <td className="border px-2 py-1">{inf.auditor?.nombre ?? '—'}</td>
          </tr>
        </tbody>
      </table>

      {/* Resumen */}
      <div className="mt-4 grid grid-cols-5 gap-2 text-center text-[12px]">
        {[
          ['Puntos revisados', inf.resumen.total],
          ['Conformes', inf.resumen.ok],
          ['No conformes', inf.resumen.no_ok],
          ['No aplica', inf.resumen.na],
          ['Fotos', totalFotos],
        ].map(([l, v]) => (
          <div key={String(l)} className="rounded border px-2 py-1">
            <div className="text-[10px] uppercase text-gray-500">{l}</div>
            <div className="text-base font-bold">{v as number}</div>
          </div>
        ))}
      </div>

      {/* Hallazgos primero: es lo que el cliente y el arriendo necesitan ver */}
      {inf.hallazgos.length > 0 && (
        <div className="page-break mt-6">
          <h2 className="border-b border-gray-300 pb-1 text-sm font-bold uppercase">
            Hallazgos ({inf.hallazgos.length})
          </h2>
          <div className="mt-2 space-y-2">
            {inf.hallazgos.map((h, i) => (
              <div key={i} className="page-break flex gap-3 rounded border border-red-200 bg-red-50/40 p-2">
                {h.foto_url && (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img src={h.foto_url} alt="evidencia" className="h-24 w-24 shrink-0 rounded border object-cover" />
                )}
                <div className="text-[12px]">
                  <div className="font-semibold">
                    {h.descripcion}
                    {h.critico && <span className="ml-2 rounded bg-red-600 px-1 text-[10px] font-bold text-white">CRÍTICO</span>}
                  </div>
                  {h.bloque && <div className="text-[10px] uppercase text-gray-500">{tituloBloque(h.bloque)}</div>}
                  {h.observacion && <div className="mt-0.5 text-gray-700">{h.observacion}</div>}
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Pendientes diferidos */}
      {inf.pendientes.length > 0 && (
        <div className="page-break mt-6">
          <h2 className="border-b border-gray-300 pb-1 text-sm font-bold uppercase">
            Pendientes con plazo ({inf.pendientes.length})
          </h2>
          <table className="mt-2 w-full border-collapse text-[12px]">
            <thead>
              <tr className="bg-gray-100">
                <th className="border px-2 py-1 text-left">Pendiente</th>
                <th className="border px-2 py-1 text-left">Sistema</th>
                <th className="border px-2 py-1 text-left">Severidad</th>
                <th className="border px-2 py-1 text-left">Plazo</th>
              </tr>
            </thead>
            <tbody>
              {inf.pendientes.map((p, i) => (
                <tr key={i}>
                  <td className="border px-2 py-1">{p.descripcion}</td>
                  <td className="border px-2 py-1">{p.sistema ?? '—'}</td>
                  <td className="border px-2 py-1">
                    {p.severidad}{p.diferible === false && ' · no diferible'}
                  </td>
                  <td className="border px-2 py-1">{fechaCorta(p.plazo)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {/* Documentos del equipo */}
      {inf.documentos.length > 0 && (
        <div className="page-break mt-6">
          <h2 className="border-b border-gray-300 pb-1 text-sm font-bold uppercase">
            Documentación del equipo
          </h2>
          <table className="mt-2 w-full border-collapse text-[12px]">
            <thead>
              <tr className="bg-gray-100">
                <th className="border px-2 py-1 text-left">Documento</th>
                <th className="border px-2 py-1 text-left">Número</th>
                <th className="border px-2 py-1 text-left">Entidad</th>
                <th className="border px-2 py-1 text-left">Vence</th>
                <th className="border px-2 py-1 text-left">Estado</th>
              </tr>
            </thead>
            <tbody>
              {inf.documentos.map((d, i) => (
                <tr key={i}>
                  <td className="border px-2 py-1">{d.tipo}</td>
                  <td className="border px-2 py-1">{d.numero ?? '—'}</td>
                  <td className="border px-2 py-1">{d.entidad ?? '—'}</td>
                  <td className="border px-2 py-1">{fechaCorta(d.vence)}</td>
                  <td className={`border px-2 py-1 ${d.estado !== 'vigente' ? 'font-semibold text-red-600' : ''}`}>
                    {d.estado}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {/* Detalle completo del checklist */}
      <div className="mt-6">
        <h2 className="border-b border-gray-300 pb-1 text-sm font-bold uppercase">
          Detalle de la revisión — Check-List Inspección y Recepción V03
        </h2>
        {inf.bloques.map((b) => (
          <div key={b.bloque} className="page-break mt-3">
            <div className="bg-gray-100 px-2 py-1 text-[12px] font-bold capitalize">
              {tituloBloque(b.bloque)}
              <span className="ml-2 font-normal text-gray-500">
                ({b.categoria === 'documentacion' ? 'documentación' : 'técnica'})
              </span>
            </div>
            <table className="w-full border-collapse text-[11.5px]">
              <tbody>
                {b.items.map((it, i) => (
                  <tr key={i} className={it.resultado === 'no_ok' ? 'bg-red-50' : undefined}>
                    <td className="w-6 border px-1 py-1 text-center align-top"><IconoResultado r={it.resultado} /></td>
                    <td className="border px-2 py-1 align-top">
                      {it.descripcion}
                      {it.critico && <span className="ml-1 text-[9px] font-bold text-red-600">CRÍTICO</span>}
                      {!it.aplica_tipo && <span className="ml-1 text-[9px] text-gray-400">(no aplica a este tipo)</span>}
                      {it.observacion && <div className="text-[10.5px] text-gray-600">{it.observacion}</div>}
                    </td>
                    <td className="w-20 border px-1 py-1 align-top">
                      {it.foto_url && (
                        // eslint-disable-next-line @next/next/no-img-element
                        <img src={it.foto_url} alt="" className="h-14 w-16 rounded border object-cover" />
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ))}
      </div>

      {inf.observaciones && (
        <div className="page-break mt-6">
          <h2 className="border-b border-gray-300 pb-1 text-sm font-bold uppercase">Observaciones</h2>
          <p className="mt-2 whitespace-pre-line">{inf.observaciones}</p>
        </div>
      )}
      {inf.motivo_rechazo && (
        <div className="page-break mt-6">
          <h2 className="border-b border-red-300 pb-1 text-sm font-bold uppercase text-red-700">Motivo del rechazo</h2>
          <p className="mt-2 whitespace-pre-line">{inf.motivo_rechazo}</p>
        </div>
      )}

      {/* Declaración + firma */}
      <div className="page-break mt-8 rounded border p-3 text-[12px]">
        <div className="flex items-start gap-2">
          <ShieldCheck className="mt-0.5 h-4 w-4 shrink-0 text-emerald-600" />
          <p>
            {aprobado ? (
              <>El equipo individualizado fue revisado según el Check-List de Inspección y Recepción V03 y
              se encuentra <strong>apto para su salida a arriendo</strong>, con la evidencia fotográfica
              adjunta. La conformidad rige hasta el <strong>{fechaCorta(inf.vigente_hasta)}</strong>;
              vencida esa fecha, el equipo debe volver a auditarse antes de salir.</>
            ) : (
              <>El equipo <strong>no fue liberado</strong>: presenta hallazgos que impiden su salida a
              arriendo. Debe resolverse lo indicado y auditarse nuevamente.</>
            )}
          </p>
        </div>
      </div>

      <div className="mt-10 flex justify-center">
        <div className="w-64 text-center">
          {inf.auditor?.firma_url && (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={inf.auditor.firma_url} alt="firma" className="mx-auto h-16 object-contain" />
          )}
          <div className="mt-1 border-t border-gray-800 pt-1 text-[12px] font-semibold">
            {inf.auditor?.nombre ?? '—'}
          </div>
          <div className="text-[11px] text-gray-600">Auditor de Calidad</div>
        </div>
      </div>

      {inf.hallazgos.length > 0 && aprobado && (
        <div className="mt-6 flex items-start gap-2 rounded border border-amber-300 bg-amber-50 p-2 text-[11px] text-amber-900">
          <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
          El equipo sale con {inf.hallazgos.length} hallazgo(s) registrado(s) más arriba. Quedan
          documentados y no impiden la operación, pero deben resolverse en el plazo indicado.
        </div>
      )}

      <div className="mt-8 text-center text-[10px] text-gray-400">
        Documento generado por SICOM-ICEO · {inf.folio ?? '—'} · {fechaCorta(inf.fecha)}
      </div>
    </div>
  )
}
