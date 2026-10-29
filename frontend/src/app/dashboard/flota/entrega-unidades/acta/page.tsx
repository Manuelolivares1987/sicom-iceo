'use client'

// [MIG665] Acta de entrega: una hoja por camión del lote. «Imprimir» → Guardar como PDF.

import { Suspense, useState } from 'react'
import Link from 'next/link'
import { useSearchParams } from 'next/navigation'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { ArrowLeft, Printer } from 'lucide-react'
import { useRequireAuth } from '@/hooks/use-require-auth'
import { useToast } from '@/contexts/toast-context'
import { errorMessage } from '@/lib/utils'
import { anularActa, getActasLote, TXT_FOTO, FOTOS_ENTREGA, type ActaEntrega } from '@/lib/services/entregas-unidad'

const n0 = (v: number | null) => (v == null ? '—' : Math.round(v).toLocaleString('es-CL'))

export default function ActaEntregaPage() {
  return <Suspense fallback={<p className="p-4 text-sm text-gray-500">Cargando…</p>}><Contenido /></Suspense>
}

function Contenido() {
  const { loading } = useRequireAuth()
  const lote = useSearchParams().get('lote') ?? ''
  const q = useQuery({ queryKey: ['entrega-unidades', 'lote', lote], queryFn: () => getActasLote(lote), enabled: !loading && !!lote })
  return (
    <div className="mx-auto max-w-3xl p-3 print:max-w-none print:p-0">
      <div className="mb-3 flex items-center justify-between print:hidden">
        <Link href="/dashboard/flota/entrega-unidades/" className="flex items-center gap-1 text-sm text-blue-600 hover:underline">
          <ArrowLeft className="h-4 w-4" /> Entrega de unidades
        </Link>
        <button type="button" onClick={() => window.print()} className="flex items-center gap-1 rounded bg-gray-900 px-3 py-2 text-sm text-white">
          <Printer className="h-4 w-4" /> Imprimir / PDF
        </button>
      </div>
      {q.isLoading ? <p className="text-sm text-gray-500">Cargando…</p>
        : !q.data?.length ? <p className="text-sm text-gray-500">No se encontró el acta.</p>
        : q.data.map((a) => <Acta key={a.id} a={a} />)}
    </div>
  )
}

function Acta({ a }: { a: ActaEntrega }) {
  const fotos = [...a.fotos].sort((x, y) =>
    FOTOS_ENTREGA.findIndex((f) => f.tipo === x.tipo) - FOTOS_ENTREGA.findIndex((f) => f.tipo === y.tipo))
  const fecha = new Date(a.fecha)
  return (
    <section className="mb-6 break-after-page rounded border bg-white p-5 text-sm text-gray-900 print:mb-0 print:rounded-none print:border-0 print:p-6">
      <header className="flex items-start justify-between border-b pb-2">
        <div>
          <p className="text-xs uppercase tracking-wide text-gray-500">Pillado Empresas</p>
          <h1 className="text-lg font-bold">Acta de entrega de unidad</h1>
        </div>
        <div className="text-right">
          <p className="font-mono font-semibold">{a.folio}</p>
          <p>{fecha.toLocaleDateString('es-CL')} {fecha.toLocaleTimeString('es-CL', { hour: '2-digit', minute: '2-digit' })}</p>
          {a.lugar && <p className="text-gray-600">{a.lugar}</p>}
        </div>
      </header>
      {a.estado === 'anulada' && (
        <p className="mt-2 rounded bg-red-50 px-2 py-1 font-semibold text-red-700">ANULADA: {a.anulada_motivo}</p>
      )}

      <dl className="mt-3 grid grid-cols-2 gap-x-6 gap-y-1 sm:grid-cols-3">
        <Dato t="Patente" v={a.patente} />
        <Dato t="Código" v={a.activo_codigo ?? '—'} />
        <Dato t="Equipo" v={[a.marca, a.modelo].filter(Boolean).join(' ') || (a.tipo_equipamiento?.replace(/_/g, ' ') ?? '—')} />
        <Dato t="Km" v={n0(a.km)} />
        <Dato t="Horómetro" v={n0(a.horometro)} />
        <Dato t="Recibe" v={a.empresa_recibe} />
      </dl>

      <div className="mt-3 rounded border border-gray-300 p-2">
        <p><b>Llaves entregadas al cliente:</b> {a.llaves_entregadas}</p>
        <p><b>Copias de llaves:</b> {a.copias_en_pillado > 0 ? `${a.copias_en_pillado} quedan en poder de Pillado` : 'sin copia'}</p>
      </div>
      {a.observaciones && <p className="mt-2"><b>Observaciones:</b> {a.observaciones}</p>}

      <div className="mt-3 grid grid-cols-3 gap-2 sm:grid-cols-4 print:grid-cols-4">
        {fotos.map((f) => (
          <figure key={f.tipo} className="break-inside-avoid">
            <img src={f.url} alt={TXT_FOTO[f.tipo] ?? f.tipo} className="h-28 w-full rounded border object-cover print:h-32" />
            <figcaption className="text-center text-[11px] text-gray-600">{TXT_FOTO[f.tipo] ?? f.tipo}</figcaption>
          </figure>
        ))}
      </div>

      <p className="mt-4 text-xs text-gray-700">
        Quien firma declara recibir la unidad en el estado que muestran las fotos y las llaves indicadas. Las copias de las
        llaves quedan en Pillado.
      </p>
      <div className="mt-2 grid grid-cols-2 gap-6">
        <div className="break-inside-avoid">
          <img src={a.firma_url} alt="Firma de quien recibe" className="h-20 object-contain" />
          <div className="border-t pt-1 text-xs">
            <p className="font-semibold">{a.recibe_nombre}</p>
            <p>RUT {a.recibe_rut}{a.recibe_cargo ? ` · ${a.recibe_cargo}` : ''}</p>
            <p>Recibe por {a.empresa_recibe}</p>
          </div>
        </div>
        <div className="flex flex-col justify-end text-xs">
          <div className="border-t pt-1">
            <p className="font-semibold">{a.entregado_por_nombre ?? '—'}</p>
            <p>Entrega por Pillado Empresas</p>
          </div>
        </div>
      </div>
      {a.estado === 'firmada' && <Anular id={a.id} />}
    </section>
  )
}

function Anular({ id }: { id: string }) {
  const toast = useToast()
  const qc = useQueryClient()
  const [abierto, setAbierto] = useState(false)
  const [motivo, setMotivo] = useState('')
  if (!abierto) return (
    <button type="button" onClick={() => setAbierto(true)} className="mt-3 text-xs text-gray-500 hover:underline print:hidden">Anular esta acta</button>
  )
  return (
    <div className="mt-3 flex flex-wrap items-center gap-2 print:hidden">
      <input value={motivo} onChange={(e) => setMotivo(e.target.value)} placeholder="Motivo de la anulación"
             className="min-w-[220px] flex-1 rounded border px-2 py-1 text-xs" />
      <button type="button" disabled={motivo.trim().length < 5} className="rounded bg-red-600 px-2 py-1 text-xs text-white disabled:opacity-40"
              onClick={async () => {
                try { await anularActa(id, motivo); qc.invalidateQueries({ queryKey: ['entrega-unidades'] }); setAbierto(false) }
                catch (e) { toast.error(errorMessage(e)) }
              }}>Anular</button>
      <button type="button" onClick={() => setAbierto(false)} className="text-xs text-gray-500 hover:underline">cancelar</button>
    </div>
  )
}

function Dato({ t, v }: { t: string; v: string }) {
  return <div><dt className="text-xs text-gray-500">{t}</dt><dd className="font-semibold">{v}</dd></div>
}
