'use client'

// Informe de Recepción y Recobro imprimible: el documento que Pillado
// entrega al cliente al recepcionar un equipo (hallazgos con fotos +
// costos de recobro con IVA), con las firmas del inspector y de cobros.
// Vive en la carpeta del equipo (ficha del activo → Documentos).

import { useEffect, useState } from 'react'
import { useParams } from 'next/navigation'
import { Printer } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import {
  getInformeRecepcionCompleto, getHallazgosInforme, getCostosInforme,
  type InformeRecepcionCompleto, type InformeHallazgo, type InformeCosto,
} from '@/lib/services/informe-recepcion'

const CLP = (n: number) => `$${Math.round(n).toLocaleString('es-CL')}`
const GRAVEDAD_LABEL: Record<string, string> = { menor: 'Menor', mayor: 'Mayor', critica: 'Crítica' }
const TIPO_COSTO_LABEL: Record<string, string> = {
  repuesto: 'Repuesto', mano_obra: 'Mano de obra', servicio_externo: 'Serv. externo', otro: 'Otro',
}
const ESTADO_LABEL: Record<string, string> = {
  borrador: 'BORRADOR', en_inspeccion: 'EN INSPECCIÓN', emitido: 'EMITIDO', cancelado: 'CANCELADO',
}

function fechaCL(iso: string | null): string {
  if (!iso) return '—'
  const [y, m, d] = iso.slice(0, 10).split('-')
  return `${d}-${m}-${y}`
}

export default function InformeRecepcionImprimiblePage() {
  const params = useParams()
  const informeId = params?.id as string
  const [sesionOk, setSesionOk] = useState<boolean | null>(null)
  const [informe, setInforme] = useState<InformeRecepcionCompleto | null>(null)
  const [hallazgos, setHallazgos] = useState<InformeHallazgo[]>([])
  const [costos, setCostos] = useState<InformeCosto[]>([])
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let cancel = false
    supabase.auth.getSession().then(({ data: { session } }) => {
      if (!cancel) setSesionOk(!!session)
    })
    return () => { cancel = true }
  }, [])

  useEffect(() => {
    if (sesionOk !== true || !informeId) return
    let cancel = false
    ;(async () => {
      try {
        const [inf, h, c] = await Promise.all([
          getInformeRecepcionCompleto(informeId),
          getHallazgosInforme(informeId),
          getCostosInforme(informeId),
        ])
        if (cancel) return
        if (!inf) { setError('Informe no encontrado'); return }
        setInforme(inf)
        setHallazgos(h.data ?? [])
        setCostos(c.data ?? [])
      } catch (e) { if (!cancel) setError((e as Error).message) }
    })()
    return () => { cancel = true }
  }, [sesionOk, informeId])

  if (sesionOk === null) return <div className="py-20 text-center text-gray-400">Verificando acceso…</div>
  if (sesionOk === false) {
    return (
      <div className="py-20 text-center">
        <p className="text-sm text-gray-600">El informe requiere iniciar sesión.</p>
        <a href={`/login?next=${encodeURIComponent(`/informe-recepcion/${informeId}`)}`}
           className="mt-4 inline-block rounded-lg bg-[#0b2a4a] px-5 py-2 text-sm font-semibold text-white">
          Iniciar sesión
        </a>
      </div>
    )
  }
  if (error) return <div className="py-20 text-center text-sm text-red-600">{error}</div>
  if (!informe) return <div className="py-20 text-center text-gray-400">Cargando informe…</div>

  const eq = informe.activo
  const marcaModelo = [eq?.modelo?.marca?.nombre, eq?.modelo?.nombre].filter(Boolean).join(' ')
  const costosCobrables = costos.filter((c) => c.cobrable_cliente)
  const costosNoCobrables = costos.filter((c) => !c.cobrable_cliente)

  return (
    <div className="mx-auto max-w-3xl bg-white p-6 print:max-w-full print:p-0">
      <style jsx global>{`
        @media print {
          @page { size: letter portrait; margin: 10mm 12mm; }
          html, body { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
          .inf-doc { font-size: 11px; }
          .inf-doc tr, .inf-hallazgo { break-inside: avoid; }
          .inf-firmas { break-inside: avoid; }
        }
      `}</style>

      {/* Barra de acciones (no se imprime) */}
      <div className="mb-4 flex items-center justify-between rounded-lg border border-gray-200 bg-gray-50 px-4 py-3 print:hidden">
        <p className="text-sm text-gray-600">
          Informe {informe.folio ?? 'de recepción'} · {eq?.patente ?? eq?.codigo} — usa «Guardar como PDF» para archivarlo o enviarlo al cliente.
        </p>
        <button onClick={() => window.print()}
                className="flex items-center gap-1.5 rounded-lg bg-[#0b2a4a] px-4 py-2 text-sm font-semibold text-white">
          <Printer className="h-4 w-4" /> Imprimir
        </button>
      </div>

      <div className="inf-doc text-gray-900">
        {/* Membrete */}
        <div className="flex items-end justify-between border-b-2 border-gray-800 pb-3">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/images/logo.jpg" alt="Pillado Empresas" className="h-14 object-contain print:h-12" />
          <div className="text-right">
            <h1 className="text-lg font-black tracking-tight text-[#0b2a4a] print:text-base">
              INFORME DE RECEPCIÓN Y RECOBRO
            </h1>
            <p className="font-mono text-sm font-bold">{informe.folio ?? '—'}</p>
            <p className="text-xs text-gray-600">{ESTADO_LABEL[informe.estado] ?? informe.estado}</p>
          </div>
        </div>

        {/* Datos generales */}
        <div className="mt-4 grid grid-cols-2 gap-x-8 gap-y-1.5 text-sm sm:grid-cols-3">
          <div><span className="text-gray-500">Equipo:</span> <b>{eq?.nombre ?? eq?.codigo ?? '—'}</b></div>
          <div><span className="text-gray-500">Patente:</span> <b>{eq?.patente ?? '—'}</b></div>
          <div><span className="text-gray-500">Marca / Modelo:</span> <b>{marcaModelo || '—'}</b></div>
          <div><span className="text-gray-500">Cliente:</span> <b>{informe.cliente_nombre ?? '—'}</b></div>
          <div><span className="text-gray-500">Entrega arriendo:</span> <b>{fechaCL(informe.fecha_entrega_arriendo)}</b></div>
          <div><span className="text-gray-500">Recepción:</span> <b>{fechaCL(informe.fecha_recepcion)}</b></div>
          {informe.emitido_en && (
            <div><span className="text-gray-500">Emitido:</span> <b>{fechaCL(informe.emitido_en)}</b></div>
          )}
        </div>

        {/* Hallazgos */}
        <h2 className="mt-6 border-b border-gray-300 pb-1 text-sm font-bold uppercase tracking-wide">
          Hallazgos de la recepción ({hallazgos.length})
        </h2>
        {hallazgos.length === 0 ? (
          <p className="mt-2 text-sm text-gray-500">Sin hallazgos: el equipo se recepcionó conforme.</p>
        ) : (
          <div className="mt-2 space-y-3">
            {hallazgos.map((h, i) => (
              <div key={h.id} className="inf-hallazgo rounded border border-gray-200 p-2.5">
                <div className="flex flex-wrap items-center gap-2 text-sm">
                  <span className="font-bold">{String(i + 1).padStart(2, '0')}.</span>
                  <span className="flex-1 font-medium">{h.descripcion}</span>
                  <span className={`rounded px-1.5 py-0.5 text-[10px] font-bold ${
                    h.gravedad === 'critica' || h.gravedad === 'mayor' ? 'bg-red-100 text-red-700' : 'bg-amber-100 text-amber-800'}`}>
                    {GRAVEDAD_LABEL[h.gravedad] ?? h.gravedad}
                  </span>
                  <span className={`rounded px-1.5 py-0.5 text-[10px] font-bold ${
                    h.atribuible_cliente ? 'bg-orange-100 text-orange-800' : 'bg-gray-100 text-gray-600'}`}>
                    {h.atribuible_cliente ? 'Atribuible al cliente' : 'No atribuible'}
                  </span>
                </div>
                {h.seccion && <p className="mt-0.5 text-[11px] text-gray-500">Sección: {h.seccion}</p>}
                {h.observacion && <p className="mt-1 text-[12px] text-gray-700">{h.observacion}</p>}
                {(h.fotos?.length ?? 0) > 0 && (
                  <div className="mt-2 flex flex-wrap gap-2">
                    {h.fotos.map((url, j) => (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img key={j} src={url} alt={`hallazgo ${i + 1} foto ${j + 1}`}
                           className="h-24 w-24 rounded border object-cover print:h-20 print:w-20" />
                    ))}
                  </div>
                )}
              </div>
            ))}
          </div>
        )}

        {/* Costos de recobro */}
        <h2 className="mt-6 border-b border-gray-300 pb-1 text-sm font-bold uppercase tracking-wide">
          Valorización del recobro
        </h2>
        {costos.length === 0 ? (
          <p className="mt-2 text-sm text-gray-500">Sin costos asociados.</p>
        ) : (
          <table className="mt-2 w-full text-[12px]">
            <thead>
              <tr className="border-b border-gray-400 text-left text-[10px] uppercase text-gray-500">
                <th className="py-1 pr-2">Tipo</th>
                <th className="py-1 pr-2">Descripción</th>
                <th className="py-1 pr-2 text-right">Cant.</th>
                <th className="py-1 pr-2 text-right">P. Unit.</th>
                <th className="py-1 pr-2 text-right">Total</th>
                <th className="py-1 text-center">Cobrable</th>
              </tr>
            </thead>
            <tbody>
              {[...costosCobrables, ...costosNoCobrables].map((c) => (
                <tr key={c.id} className="border-b border-gray-100">
                  <td className="py-1 pr-2 text-gray-500">{TIPO_COSTO_LABEL[c.tipo] ?? c.tipo}</td>
                  <td className="py-1 pr-2">{c.descripcion}</td>
                  <td className="py-1 pr-2 text-right">{c.cantidad} {c.unidad ?? ''}</td>
                  <td className="py-1 pr-2 text-right">{CLP(c.precio_unitario)}</td>
                  <td className="py-1 pr-2 text-right font-medium">{CLP(c.total)}</td>
                  <td className="py-1 text-center">{c.cobrable_cliente ? 'Sí' : 'No'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}

        {/* Totales */}
        <div className="mt-3 ml-auto w-64 space-y-1 text-sm">
          <div className="flex justify-between"><span className="text-gray-500">Subtotal neto</span><b>{CLP(informe.subtotal_neto)}</b></div>
          <div className="flex justify-between"><span className="text-gray-500">IVA</span><b>{CLP(informe.iva)}</b></div>
          <div className="flex justify-between border-t border-gray-400 pt-1"><span className="text-gray-500">Total</span><b>{CLP(informe.total)}</b></div>
          <div className="flex justify-between text-orange-700"><span>Cobrable al cliente</span><b>{CLP(informe.total_cobrable_cliente)}</b></div>
          <div className="flex justify-between text-gray-500"><span>No cobrable (interno)</span><span>{CLP(informe.total_no_cobrable)}</span></div>
        </div>

        {informe.observaciones_finales && (
          <>
            <h2 className="mt-5 border-b border-gray-300 pb-1 text-sm font-bold uppercase tracking-wide">Observaciones</h2>
            <p className="mt-1.5 whitespace-pre-wrap text-[12px] text-gray-700">{informe.observaciones_finales}</p>
          </>
        )}

        {/* Firmas */}
        <div className="inf-firmas mt-12 grid grid-cols-2 gap-10">
          <div className="text-center">
            {informe.inspector_firma_url && (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={informe.inspector_firma_url} alt="firma inspector" className="mx-auto h-16 object-contain" />
            )}
            <div className="mx-6 border-t border-gray-800 pt-2 text-sm italic">
              <p>{informe.inspector?.nombre_completo ?? '—'}</p>
              <p>Inspector de Recepción</p>
              <p>Pillado y Cía. Ltda.</p>
            </div>
          </div>
          <div className="text-center">
            {informe.encargado_firma_url && (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={informe.encargado_firma_url} alt="firma cobros" className="mx-auto h-16 object-contain" />
            )}
            <div className="mx-6 border-t border-gray-800 pt-2 text-sm italic">
              <p>{informe.encargado?.nombre_completo ?? '—'}</p>
              <p>Encargado de Cobros</p>
              <p>Pillado y Cía. Ltda.</p>
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
