'use client'

// Vale de bodega imprimible (MIG205): el jefe lo imprime y se lo pasa al
// operador para retirar. Bodega escanea el QR y despacha.
//
// El papel vive en components/bodega/vale-imprimible desde MIG376, porque el
// portal por link imprime exactamente el mismo documento sin sesión. Acá queda
// lo propio de esta puerta: exigir cuenta y traer el vale por su id.

import { useEffect, useState } from 'react'
import { useParams } from 'next/navigation'
import { Printer } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { getTicketById, getTicketItems, type BodegaTicket, type BodegaTicketItem } from '@/lib/services/bodega-tickets'
import { ValeImprimible, EstilosImpresionVale } from '@/components/bodega/vale-imprimible'

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

  return (
    <div className="mx-auto max-w-2xl bg-white p-6 print:max-w-full print:p-0">
      <EstilosImpresionVale />

      {/* Barra de acciones (no se imprime) */}
      <div className="mb-4 flex items-center justify-between rounded-lg border border-gray-200 bg-gray-50 px-4 py-3 print:hidden">
        <p className="text-sm text-gray-600">
          {ticket.origen === 'oficina'
            ? 'Imprime este vale y llévalo a bodega para retirar.'
            : 'Imprime este vale y entrégaselo al operador para retirar en bodega.'}
        </p>
        <button onClick={() => window.print()}
                className="flex items-center gap-1.5 rounded-lg bg-[#0b2a4a] px-4 py-2 text-sm font-semibold text-white">
          <Printer className="h-4 w-4" /> Imprimir
        </button>
      </div>

      <ValeImprimible ticket={ticket} items={items} />
    </div>
  )
}
