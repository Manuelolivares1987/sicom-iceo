'use client'

// Vale de bodega imprimible (MIG205): el jefe lo imprime y se lo pasa al
// operador para retirar. Bodega escanea el QR y despacha.

import { useEffect, useState } from 'react'
import { useParams } from 'next/navigation'
import { QRCodeCanvas } from 'qrcode.react'
import { Printer } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { getTicketById, getTicketItems, type BodegaTicket, type BodegaTicketItem } from '@/lib/services/bodega-tickets'

const ESTADO_LABEL: Record<string, string> = {
  emitido: 'EMITIDO — pendiente de entrega',
  parcial: 'ENTREGA PARCIAL',
  entregado: 'ENTREGADO',
  anulado: 'ANULADO',
}

export default function ValeImprimiblePage() {
  const params = useParams()
  const ticketId = params?.id as string
  const [sesionOk, setSesionOk] = useState<boolean | null>(null)
  const [ticket, setTicket] = useState<BodegaTicket | null>(null)
  const [items, setItems] = useState<BodegaTicketItem[]>([])
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let cancel = false
    supabase.auth.getSession().then(({ data: { session } }) => {
      if (!cancel) setSesionOk(!!session)
    })
    return () => { cancel = true }
  }, [])

  useEffect(() => {
    if (sesionOk !== true || !ticketId) return
    let cancel = false
    ;(async () => {
      try {
        const [t, its] = await Promise.all([getTicketById(ticketId), getTicketItems(ticketId)])
        if (cancel) return
        if (!t) { setError('Vale no encontrado'); return }
        setTicket(t); setItems(its)
      } catch (e) { if (!cancel) setError((e as Error).message) }
    })()
    return () => { cancel = true }
  }, [sesionOk, ticketId])

  if (sesionOk === null) return <div className="py-20 text-center text-gray-400">Verificando acceso…</div>
  if (sesionOk === false) {
    return (
      <div className="py-20 text-center">
        <p className="text-sm text-gray-600">El vale requiere iniciar sesión.</p>
        <a href={`/login?next=${encodeURIComponent(`/vale/${ticketId}`)}`}
           className="mt-4 inline-block rounded-lg bg-[#0b2a4a] px-5 py-2 text-sm font-semibold text-white">
          Iniciar sesión
        </a>
      </div>
    )
  }
  if (error) return <div className="py-20 text-center text-sm text-red-600">{error}</div>
  if (!ticket) return <div className="py-20 text-center text-gray-400">Cargando vale…</div>

  const fecha = new Date(ticket.created_at).toLocaleString('es-CL', {
    day: '2-digit', month: 'long', year: 'numeric', hour: '2-digit', minute: '2-digit',
  })

  return (
    <div className="mx-auto max-w-2xl bg-white p-6 print:p-0">
      {/* Barra de acciones (no se imprime) */}
      <div className="mb-4 flex items-center justify-between rounded-lg border border-gray-200 bg-gray-50 px-4 py-3 print:hidden">
        <p className="text-sm text-gray-600">
          Imprime este vale y entrégaselo al operador para retirar en bodega.
        </p>
        <button onClick={() => window.print()}
                className="flex items-center gap-1.5 rounded-lg bg-[#0b2a4a] px-4 py-2 text-sm font-semibold text-white">
          <Printer className="h-4 w-4" /> Imprimir
        </button>
      </div>

      {/* Vale */}
      <div className="rounded-xl border-2 border-gray-800 print:rounded-none print:border">
        <div className="flex items-start justify-between border-b-2 border-gray-800 p-4">
          <div>
            <h1 className="text-lg font-black tracking-tight text-[#0b2a4a]">VALE DE BODEGA — PILLADO</h1>
            <p className="mt-0.5 font-mono text-2xl font-black">{ticket.folio}</p>
            <p className="mt-1 text-xs text-gray-600">{fecha}</p>
            <p className={`mt-1 inline-block rounded px-2 py-0.5 text-[11px] font-bold ${
              ticket.estado === 'entregado' ? 'bg-green-100 text-green-800'
              : ticket.estado === 'anulado' ? 'bg-red-100 text-red-700' : 'bg-amber-100 text-amber-800'}`}>
              {ESTADO_LABEL[ticket.estado] ?? ticket.estado}
            </p>
          </div>
          <div className="text-center">
            {/* QR = link: cualquier teléfono lo abre en la pantalla de despacho de bodega */}
            <QRCodeCanvas value={`${typeof window !== 'undefined' ? window.location.origin : ''}/dashboard/bodega/tickets?folio=${ticket.folio}`} size={110} />
            <p className="mt-1 font-mono text-[10px] text-gray-500">{ticket.folio}</p>
            <p className="text-[9px] text-gray-400">Escanear = abre el despacho en bodega</p>
          </div>
        </div>

        <div className="grid grid-cols-2 gap-3 border-b border-gray-300 p-4 text-sm">
          <div>
            <p className="text-[11px] uppercase text-gray-500">Equipo / Patente</p>
            <p className="text-lg font-bold">{ticket.activo_patente ?? ticket.activo_codigo}</p>
            <p className="text-xs text-gray-600">{ticket.activo_nombre}</p>
          </div>
          <div>
            <p className="text-[11px] uppercase text-gray-500">Orden de trabajo</p>
            <p className="font-mono font-bold">{ticket.ot_folio}</p>
            <p className="mt-1 text-[11px] uppercase text-gray-500">Autoriza</p>
            <p className="text-xs font-medium">{ticket.emitido_por_nombre ?? '—'}</p>
          </div>
        </div>

        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-gray-300 text-left text-[11px] uppercase text-gray-500">
              <th className="p-2 pl-4">#</th>
              <th className="p-2">Material / repuesto</th>
              <th className="p-2 text-right">Cantidad</th>
              <th className="p-2 pr-4 text-right">Entregado</th>
            </tr>
          </thead>
          <tbody>
            {items.map((it, i) => (
              <tr key={it.id} className="border-b border-gray-200">
                <td className="p-2 pl-4 text-gray-500">{i + 1}</td>
                <td className="p-2">
                  <span className="font-medium">{it.producto_nombre ?? it.descripcion}</span>
                  {it.producto_codigo && <span className="ml-1 font-mono text-[10px] text-gray-400">{it.producto_codigo}</span>}
                  {it.comentario && <div className="text-[10px] italic text-gray-500">{it.comentario}</div>}
                </td>
                <td className="p-2 text-right font-semibold whitespace-nowrap">
                  {it.cantidad_solicitada} {it.unidad ?? it.unidad_medida ?? 'un'}
                </td>
                <td className="p-2 pr-4 text-right text-gray-400">
                  {Number(it.cantidad_entregada) > 0 ? it.cantidad_entregada : '____'}
                </td>
              </tr>
            ))}
          </tbody>
        </table>

        <div className="grid grid-cols-3 gap-4 p-4 pt-8">
          <div className="text-center">
            {ticket.firma_jefe_url ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={ticket.firma_jefe_url} alt="firma jefe" className="mx-auto h-14 object-contain" />
            ) : <div className="h-14" />}
            <div className="border-t border-gray-800 pt-1 text-[11px] font-medium">Jefe de Taller (autoriza)</div>
          </div>
          <div className="text-center">
            <div className="h-14" />
            <div className="border-t border-gray-800 pt-1 text-[11px] font-medium">Operador (retira)</div>
          </div>
          <div className="text-center">
            <div className="h-14" />
            <div className="border-t border-gray-800 pt-1 text-[11px] font-medium">Bodega (entrega)</div>
          </div>
        </div>

        <p className="border-t border-gray-300 p-3 text-center text-[10px] text-gray-500">
          Presentar este vale en bodega. El bodeguero escanea el QR en Bodega → Tickets y registra la
          entrega (total o parcial). Ticket de un solo uso — al completarse queda ENTREGADO.
        </p>
      </div>
    </div>
  )
}
